package com.cama.telemetry.direct_lab;

import android.content.Context;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.os.Process;
import android.util.AtomicFile;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.Proxy;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.TimeZone;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import org.json.JSONArray;
import org.json.JSONObject;

/** Bounded single-process laboratory queue, deliberately not a production SDK. */
final class DirectQueue {
    private static final String ENDPOINT = "http://127.0.0.1:8765/batch/";
    private static final String TOKEN = "phc_synthetic_local_only";
    private static final int BYTE_LIMIT = 1048576;
    private static final int WIRE_LIMIT = 65536;
    private final Context context;
    private final SQLiteDatabase db;
    // Every network body write and durable revocation boundary shares this gate.
    private final Object dispatchGate = new Object();
    private final Object store = new Object();
    private final Object scheduling = new Object();
    private final ScheduledExecutorService sender = Executors.newSingleThreadScheduledExecutor();
    private boolean scheduled;
    private int retrySeconds = 1;
    private int inFlight;
    private JSONObject preflightResults;

    DirectQueue(Context context) throws Exception {
        this.context = context;
        initializeSentinels();
        db = context.openOrCreateDatabase("synthetic_telemetry.db", Context.MODE_PRIVATE, null);
        try (Cursor mode = db.rawQuery("PRAGMA journal_mode=DELETE", null)) {
            if (!mode.moveToFirst() || !"delete".equalsIgnoreCase(mode.getString(0)))
                throw new IllegalStateException("JOURNAL_MODE_NOT_DELETE");
        }
        db.execSQL("PRAGMA synchronous=FULL");
        try (Cursor mode = db.rawQuery("PRAGMA synchronous", null)) {
            if (!mode.moveToFirst() || mode.getInt(0) != 2)
                throw new IllegalStateException("SYNCHRONOUS_NOT_FULL");
        }
        try (Cursor mode = db.rawQuery("PRAGMA secure_delete=ON", null)) {
            if (!mode.moveToFirst() || mode.getInt(0) != 1)
                throw new IllegalStateException("SECURE_DELETE_NOT_ON");
        }
        if (db.setMaximumSize(4L * 1024 * 1024) != 4L * 1024 * 1024)
            throw new IllegalStateException("DATABASE_SIZE_BOUND_NOT_SET");
        db.execSQL("CREATE TABLE IF NOT EXISTS state (key TEXT PRIMARY KEY,value TEXT NOT NULL)");
        db.execSQL("CREATE TABLE IF NOT EXISTS queue (id INTEGER PRIMARY KEY AUTOINCREMENT,"
            + "generation INTEGER NOT NULL,event_id TEXT NOT NULL UNIQUE,body TEXT NOT NULL,bytes INTEGER NOT NULL)");
        synchronized (store) {
            db.beginTransaction();
            try {
                for (String key : new String[]{"consent", "generation", "dropped_count", "refused_count",
                        "revoked_count", "preflight_count", "preflight_rejected", "requests_started",
                        "requests_acked", "transport_failures", "dispatch_attempts"}) {
                    db.execSQL("INSERT OR IGNORE INTO state VALUES (?, '0')", new Object[]{key});
                }
                db.execSQL("INSERT OR IGNORE INTO state VALUES ('run_id', '')");
                db.execSQL("INSERT OR IGNORE INTO state VALUES ('capacity', '1000')");
                purgeObsolete();
                db.setTransactionSuccessful();
            } finally { db.endTransaction(); }
        }
        kick(); // A restart online may send only committed, currently-consented rows.
    }

    private String get(String key) {
        try (Cursor c = db.rawQuery("SELECT value FROM state WHERE key=?", new String[]{key})) {
            if (!c.moveToFirst()) throw new IllegalStateException("STATE_MISSING");
            return c.getString(0);
        }
    }
    private long number(String key) { return Long.parseLong(get(key)); }
    private void set(String key, Object value) {
        db.execSQL("UPDATE state SET value=? WHERE key=?", new Object[]{String.valueOf(value), key});
    }
    private void add(String key, long n) { set(key, Math.addExact(number(key), n)); }
    private long scalar(String sql) {
        try (Cursor c = db.rawQuery(sql, null)) { c.moveToFirst(); return c.getLong(0); }
    }
    private void purgeObsolete() {
        String where = number("consent") == 0 ? "1=1" : "generation<>" + number("generation");
        long count = scalar("SELECT count(*) FROM queue WHERE " + where);
        add("revoked_count", count);
        db.execSQL("DELETE FROM queue WHERE " + where);
    }

    void configure(String run, int capacity) {
        if (run == null || !run.matches("synthetic-[a-z0-9-]{1,48}")
                || (capacity != 32 && capacity != 1000)) throw new IllegalArgumentException("BAD_CONFIG");
        synchronized (store) {
            if (!get("run_id").isEmpty()) {
                if (!get("run_id").equals(run) || number("capacity") != capacity)
                    throw new IllegalStateException("ALREADY_CONFIGURED");
                return;
            }
            db.beginTransaction();
            try {
                set("run_id", run); set("capacity", capacity);
                db.setTransactionSuccessful();
            } finally { db.endTransaction(); }
        }
    }

    void grant() {
        synchronized (dispatchGate) {
            synchronized (store) {
                if (get("run_id").isEmpty()) throw new IllegalStateException("NOT_CONFIGURED");
                db.beginTransaction();
                try {
                    // Purge with the previous false state before enabling any delivery.
                    purgeObsolete();
                    set("consent", 1);
                    db.setTransactionSuccessful();
                } finally { db.endTransaction(); }
            }
        }
        kick();
    }

    void capture(int first, int count) throws Exception {
        if (first < 1 || count < 0 || count > 1000 || first + count - 1 > 100000)
            throw new IllegalArgumentException("BAD_RANGE");
        synchronized (store) {
            if (get("run_id").isEmpty()) throw new IllegalStateException("NOT_CONFIGURED");
            db.beginTransaction();
            try {
                if (number("consent") == 0) {
                    add("refused_count", count);
                } else {
                    String run = get("run_id");
                    for (int seq = first; seq < first + count; seq++) {
                        String id = run + "-" + String.format(Locale.ROOT, "%06d", seq);
                        JSONObject properties = new JSONObject();
                        properties.put("schema_version", 1); properties.put("run_id", run);
                        properties.put("event_id", id); properties.put("sequence", seq);
                        properties.put("event_name", "cm_lab_probe"); properties.put("synthetic", true);
                        properties.put("$geoip_disable", true); properties.put("$process_person_profile", false);
                        JSONObject item = new JSONObject();
                        item.put("event", "cm_lab_probe"); item.put("properties", properties);
                        item.put("distinct_id", run); item.put("timestamp", utc());
                        item.put("uuid", UUID.randomUUID().toString());
                        String body = item.toString();
                        int bytes = body.getBytes(StandardCharsets.UTF_8).length;
                        db.execSQL("INSERT INTO queue(generation,event_id,body,bytes) VALUES (?,?,?,?)",
                            new Object[]{number("generation"), id, body, bytes});
                        while (scalar("SELECT count(*) FROM queue") > number("capacity")
                                || scalar("SELECT coalesce(sum(bytes),0) FROM queue") > BYTE_LIMIT) {
                            db.execSQL("DELETE FROM queue WHERE id=(SELECT min(id) FROM queue)");
                            add("dropped_count", 1);
                        }
                    }
                }
                db.setTransactionSuccessful();
            } finally { db.endTransaction(); }
        }
        kick();
    }

    void revoke(String nonce, String stopAt) throws Exception {
        if (stopAt != null && !Arrays.asList("before_intent_commit", "after_intent", "during_purge", "after_purge").contains(stopAt))
            throw new IllegalArgumentException("BAD_STOP_STAGE");
        synchronized (dispatchGate) {
            synchronized (store) {
                db.beginTransaction();
                try {
                    set("consent", 0);
                    add("generation", 1);
                    checkpoint(nonce, stopAt, "before_intent_commit");
                    db.setTransactionSuccessful();
                } finally { db.endTransaction(); }
                // First durable revocation boundary. A command before this commit is unacknowledged.
                checkpoint(nonce, stopAt, "after_intent");
                db.beginTransaction();
                try {
                    purgeObsolete();
                    checkpoint(nonce, stopAt, "during_purge");
                    db.setTransactionSuccessful();
                } finally { db.endTransaction(); }
                checkpoint(nonce, stopAt, "after_purge");
            }
        }
    }

    private void checkpoint(String nonce, String requested, String stage) throws Exception {
        if (!stage.equals(requested)) return;
        JSONObject value = new JSONObject();
        value.put("action_nonce", nonce); value.put("stage", stage); value.put("pid", Process.myPid());
        value.put("consent", false); value.put("generation", number("generation"));
        value.put("revocation_durable", !stage.equals("before_intent_commit"));
        writeAtomic("checkpoint.json", value.toString().getBytes(StandardCharsets.UTF_8));
        // The harness kills the process here, including during an uncommitted purge transaction.
        for (;;) Thread.sleep(1000);
    }

    void kick() {
        synchronized (scheduling) {
            if (scheduled) return;
            scheduled = true;
            sender.schedule(this::sendOnce, 100, TimeUnit.MILLISECONDS);
        }
    }

    private void sendOnce() {
        HttpURLConnection connection = null;
        List<Long> ids = new ArrayList<>();
        boolean hasRows = false, acknowledged = false, started = false;
        try {
            byte[] bytes;
            synchronized (dispatchGate) {
                synchronized (store) {
                    if (number("consent") == 0) return;
                    JSONArray batch = new JSONArray();
                    try (Cursor c = db.rawQuery("SELECT id,body FROM queue WHERE generation=? ORDER BY id LIMIT 20",
                            new String[]{String.valueOf(number("generation"))})) {
                        while (c.moveToNext()) { ids.add(c.getLong(0)); batch.put(new JSONObject(c.getString(1))); }
                    }
                    if (ids.isEmpty()) return;
                    hasRows = true;
                    JSONObject payload = new JSONObject();
                    payload.put("api_key", TOKEN); payload.put("batch", batch);
                    bytes = payload.toString().getBytes(StandardCharsets.UTF_8);
                    try {
                        validateBytes(bytes, get("run_id"));
                        add("preflight_count", 1);
                    } catch (Exception failure) {
                        add("preflight_rejected", 1);
                        return; // Fail closed: nothing from this malformed batch is written.
                    }
                }
                URL target = new URL(ENDPOINT);
                if (!target.getHost().equals("127.0.0.1") || target.getPort() != 8765
                        || !target.getProtocol().equals("http") || !target.getPath().equals("/batch/"))
                    throw new IllegalStateException("NOT_LOOPBACK");
                // A loopback request must never use an Android-configured remote HTTP proxy.
                connection = (HttpURLConnection) target.openConnection(Proxy.NO_PROXY);
                connection.setInstanceFollowRedirects(false);
                connection.setRequestMethod("POST"); connection.setDoOutput(true);
                connection.setConnectTimeout(3000); connection.setReadTimeout(30000);
                connection.setRequestProperty("Content-Type", "application/json");
                connection.setRequestProperty("Accept", "application/json");
                connection.setRequestProperty("Accept-Encoding", "identity");
                connection.setRequestProperty("Connection", "close");
                connection.setRequestProperty("User-Agent", "Java/1.8");
                connection.setFixedLengthStreamingMode(bytes.length);
                synchronized (store) { add("dispatch_attempts", 1); }
                try (OutputStream output = connection.getOutputStream()) {
                    output.write(bytes); output.flush();
                }
                synchronized (store) { add("requests_started", 1); inFlight++; started = true; }
            }
            // The dispatch gate is released: revocation need not wait for this ACK.
            int status = connection.getResponseCode();
            acknowledged = status == 200;
            if (acknowledged) {
                synchronized (store) {
                    db.beginTransaction();
                    try {
                        for (Long id : ids) db.execSQL("DELETE FROM queue WHERE id=?", new Object[]{id});
                        add("requests_acked", 1);
                        db.setTransactionSuccessful();
                    } finally { db.endTransaction(); }
                }
            }
        } catch (Exception failure) {
            // Preserve the exact serialized record and UUID for a later retry.
            synchronized (store) { add("transport_failures", 1); }
        } finally {
            if (connection != null) connection.disconnect();
            synchronized (scheduling) {
                boolean again;
                synchronized (store) {
                    if (started) inFlight--;
                    again = number("consent") == 1 && scalar("SELECT count(*) FROM queue") > 0;
                }
                scheduled = false;
                if (again) {
                    scheduled = true;
                    int delay = acknowledged ? 0 : retrySeconds;
                    retrySeconds = acknowledged ? 1 : Math.min(retrySeconds * 2, 8);
                    sender.schedule(this::sendOnce, delay, TimeUnit.SECONDS);
                } else if (!hasRows || acknowledged) retrySeconds = 1;
            }
        }
    }

    /** Check the final serialized body, independently of the construction above. */
    static void validateBytes(byte[] bytes, String run) throws Exception {
        if (run == null || !run.matches("synthetic-[a-z0-9-]{1,48}"))
            throw new IllegalArgumentException("RUN");
        if (bytes.length == 0 || bytes.length > WIRE_LIMIT) throw new IllegalArgumentException("SIZE");
        JSONObject body = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
        exact(body, "api_key", "batch");
        if (!TOKEN.equals(body.getString("api_key"))) throw new IllegalArgumentException("TOKEN");
        JSONArray batch = body.getJSONArray("batch");
        if (batch.length() < 1 || batch.length() > 20) throw new IllegalArgumentException("BATCH");
        Set<String> eventIds = new HashSet<>();
        for (int i = 0; i < batch.length(); i++) {
            JSONObject item = batch.getJSONObject(i);
            exact(item, "event", "properties", "distinct_id", "timestamp", "uuid");
            if (!"cm_lab_probe".equals(item.getString("event")) || !run.equals(item.getString("distinct_id")))
                throw new IllegalArgumentException("IDENTITY");
            String uuid = item.getString("uuid");
            if (!UUID.fromString(uuid).toString().equals(uuid)) throw new IllegalArgumentException("UUID");
            String timestamp = item.getString("timestamp");
            if (!timestamp.matches("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z"))
                throw new IllegalArgumentException("TIME");
            SimpleDateFormat timeFormat = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT);
            timeFormat.setTimeZone(TimeZone.getTimeZone("UTC")); timeFormat.setLenient(false);
            if (!timeFormat.format(timeFormat.parse(timestamp)).equals(timestamp))
                throw new IllegalArgumentException("TIME");
            JSONObject p = item.getJSONObject("properties");
            exact(p, "schema_version", "run_id", "event_id", "sequence", "event_name", "synthetic",
                "$geoip_disable", "$process_person_profile");
            Object seqValue = p.get("sequence");
            if (!(seqValue instanceof Integer) || !(p.get("schema_version") instanceof Integer))
                throw new IllegalArgumentException("INTEGER");
            int seq = (Integer) seqValue;
            String id = run + "-" + String.format(Locale.ROOT, "%06d", seq);
            if (p.getInt("schema_version") != 1 || seq < 1 || seq > 100000
                    || !run.equals(p.getString("run_id")) || !id.equals(p.getString("event_id"))
                    || !eventIds.add(id) || !"cm_lab_probe".equals(p.getString("event_name"))
                    || !Boolean.TRUE.equals(p.get("synthetic"))
                    || !Boolean.TRUE.equals(p.get("$geoip_disable"))
                    || !Boolean.FALSE.equals(p.get("$process_person_profile")))
                throw new IllegalArgumentException("CONTRACT");
        }
    }
    private static void exact(JSONObject object, String... names) {
        Set<String> keys = new HashSet<>();
        Iterator<String> iterator = object.keys();
        while (iterator.hasNext()) keys.add(iterator.next());
        if (!keys.equals(new HashSet<>(Arrays.asList(names)))) throw new IllegalArgumentException("KEYS");
    }
    /** Native fail-closed counterexamples; fixtures never enter the queue or transport. */
    void preflightChecks() throws Exception {
        final String run = "synthetic-preflight-control";
        JSONObject property = new JSONObject();
        property.put("schema_version", 1); property.put("run_id", run);
        property.put("event_id", run + "-000001"); property.put("sequence", 1);
        property.put("event_name", "cm_lab_probe"); property.put("synthetic", true);
        property.put("$geoip_disable", true); property.put("$process_person_profile", false);
        JSONObject event = new JSONObject();
        event.put("event", "cm_lab_probe"); event.put("distinct_id", run);
        event.put("uuid", "00000000-0000-4000-8000-000000000001");
        event.put("timestamp", "2026-11-02T00:00:00.000Z"); event.put("properties", property);
        JSONObject fixture = new JSONObject();
        fixture.put("api_key", TOKEN); fixture.put("batch", new JSONArray().put(event));
        byte[] valid = fixture.toString().getBytes(StandardCharsets.UTF_8);
        validateBytes(valid, run);
        JSONObject result = new JSONObject(); result.put("valid_fixture_accepted", true);
        for (String kind : new String[]{"foreign_distinct_id", "extra_property", "wrong_privacy_flag",
                "non_fake_token", "invalid_timestamp"}) {
            JSONObject bad = new JSONObject(new String(valid, StandardCharsets.UTF_8));
            JSONObject item = bad.getJSONArray("batch").getJSONObject(0);
            switch (kind) {
                case "foreign_distinct_id": item.put("distinct_id", "00000000-0000-4000-8000-000000000002"); break;
                case "extra_property": item.getJSONObject("properties").put("extra", "synthetic"); break;
                case "wrong_privacy_flag": item.getJSONObject("properties").put("$geoip_disable", false); break;
                case "non_fake_token": bad.put("api_key", "synthetic-wrong-token"); break;
                case "invalid_timestamp": item.put("timestamp", "2026-02-30T00:00:00.000Z"); break;
                default: throw new IllegalStateException("FIXTURE");
            }
            boolean rejected = false;
            try { validateBytes(bad.toString().getBytes(StandardCharsets.UTF_8), run); }
            catch (Exception expected) { rejected = true; }
            result.put(kind + "_rejected", rejected);
            if (!rejected) throw new IllegalStateException("PREFLIGHT_COUNTEREXAMPLE_ACCEPTED");
        }
        result.put("all_passed", true);
        synchronized (store) { preflightResults = result; }
    }
    private static String utc() {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        return format.format(new Date());
    }

    private void initializeSentinels() throws Exception {
        SharedPreferences prefs = context.getSharedPreferences("unrelated_settings", Context.MODE_PRIVATE);
        if (!prefs.getBoolean("initialized", false)) {
            File trace = new File(context.getFilesDir(), "unrelated_trace.txt");
            if (trace.exists() || context.getDatabasePath("synthetic_telemetry.db").exists())
                throw new IllegalStateException("SENTINELS_MISSING_OR_PARTIAL");
            String sentinel = UUID.randomUUID().toString();
            try (FileOutputStream output = new FileOutputStream(trace)) {
                output.write(("SYNTHETIC TRACE SENTINEL WITHOUT COORDINATES " + sentinel + "\n")
                    .getBytes(StandardCharsets.UTF_8));
                output.getFD().sync();
            }
            if (!prefs.edit().putString("setting", "synthetic-setting-" + sentinel)
                    .putBoolean("initialized", true).commit()) throw new IllegalStateException("SENTINEL");
        }
    }
    private String traceHash() throws Exception {
        File file = new File(context.getFilesDir(), "unrelated_trace.txt");
        if (!file.isFile()) return "MISSING";
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (FileInputStream input = new FileInputStream(file)) {
            byte[] bytes = new byte[1024]; int n;
            while ((n = input.read(bytes)) != -1) digest.update(bytes, 0, n);
        }
        StringBuilder hex = new StringBuilder();
        for (byte value : digest.digest()) hex.append(String.format(Locale.ROOT, "%02x", value & 255));
        return hex.toString();
    }
    void writeState(String nonce, String action, boolean ok, String error) throws Exception {
        JSONObject state = new JSONObject();
        synchronized (store) {
            state.put("schema_version", 1); state.put("action_nonce", nonce);
            state.put("action", action); state.put("action_ok", ok); state.put("error", error);
            state.put("pid", Process.myPid()); state.put("run_id", get("run_id"));
            state.put("consent", number("consent") == 1);
            for (String key : new String[]{"generation", "capacity", "dropped_count", "refused_count",
                    "revoked_count", "preflight_count", "preflight_rejected", "requests_started",
                    "requests_acked", "transport_failures", "dispatch_attempts"}) state.put(key, number(key));
            state.put("queue_count", scalar("SELECT count(*) FROM queue"));
            state.put("queue_bytes", scalar("SELECT coalesce(sum(bytes),0) FROM queue"));
            state.put("queue_byte_limit", BYTE_LIMIT); state.put("database_max_bytes", db.getMaximumSize());
            state.put("in_flight_count", inFlight);
            state.put("trace_sha256", traceHash());
            state.put("setting_value", context.getSharedPreferences("unrelated_settings", Context.MODE_PRIVATE)
                .getString("setting", "MISSING"));
            if (preflightResults != null) state.put("preflight_checks", preflightResults);
        }
        writeAtomic("state.json", state.toString().getBytes(StandardCharsets.UTF_8));
    }
    private void writeAtomic(String name, byte[] bytes) throws Exception {
        AtomicFile file = new AtomicFile(new File(context.getFilesDir(), name));
        FileOutputStream output = file.startWrite();
        try { output.write(bytes); file.finishWrite(output); }
        catch (Exception failure) { file.failWrite(output); throw failure; }
    }
}

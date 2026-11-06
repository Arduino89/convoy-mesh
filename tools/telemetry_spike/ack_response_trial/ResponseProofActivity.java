package com.cama.telemetry.direct_lab;

import android.app.Activity;
import android.os.Bundle;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.util.AtomicFile;
import android.widget.TextView;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;

/** Permissionless offline proof: never constructs DirectQueue or a transport. */
public final class ResponseProofActivity extends Activity {
    private static String currentCase = "predicate";
    private static void require(boolean value, String category) throws Exception {
        if (!value) throw new CheckFailure(category);
    }
    private static final class CheckFailure extends Exception {
        CheckFailure(String category) { super(category); }
    }
    private static Object field(Object value, String key) throws Exception {
        Field member = value.getClass().getDeclaredField(key); member.setAccessible(true);
        return member.get(value);
    }
    private static String snapshot(SQLiteDatabase database) {
        StringBuilder value = new StringBuilder();
        try (Cursor c = database.rawQuery("SELECT id,generation,event_id,body,bytes FROM queue ORDER BY id", null)) {
            while (c.moveToNext()) for (int n = 0; n < 5; n++) value.append(c.getString(n)).append('|');
        }
        return value.toString();
    }
    private static long scalar(SQLiteDatabase database, String sql) {
        try (Cursor c = database.rawQuery(sql, null)) { c.moveToFirst(); return c.getLong(0); }
    }
    private static JSONObject fixture(Method classify, Method apply, String name, int code, String body,
                                      boolean accepted, String category) throws Exception {
        currentCase = name;
        Object decision = classify.invoke(null, code, body);
        boolean actual = (Boolean) field(decision, "accepted");
        require(actual == accepted, "ACCEPTANCE_MISMATCH");
        require(category.equals(field(decision, "category")), "CATEGORY_MISMATCH");
        try (SQLiteDatabase database = SQLiteDatabase.create(null)) {
            database.execSQL("CREATE TABLE state (key TEXT PRIMARY KEY,value TEXT NOT NULL)");
            database.execSQL("INSERT INTO state VALUES ('requests_acked','0')");
            database.execSQL("CREATE TABLE queue (id INTEGER PRIMARY KEY AUTOINCREMENT,"
                + "generation INTEGER NOT NULL,event_id TEXT NOT NULL UNIQUE,body TEXT NOT NULL,bytes INTEGER NOT NULL)");
            String tailBody = "";
            for (int n = 1; n <= 3; n++) {
                String serialized = "{\"uuid\":\"00000000-0000-4000-8000-00000000000" + n
                    + "\",\"event_id\":\"synthetic-ack-" + n + "\"}";
                database.execSQL("INSERT INTO queue VALUES (?,0,?,?,?)", new Object[]{n,
                    "synthetic-ack-" + n, serialized, serialized.getBytes(StandardCharsets.UTF_8).length});
                if (n == 3) tailBody = serialized;
            }
            String before = snapshot(database);
            List<Long> selected = Arrays.asList(1L, 2L);
            apply.invoke(null, database, selected, actual);
            long rows = scalar(database, "SELECT count(*) FROM queue");
            long acknowledgments = scalar(database, "SELECT CAST(value AS INTEGER) FROM state WHERE key='requests_acked'");
            require(rows == (accepted ? 1 : 3), "QUEUE_COUNT_MISMATCH");
            require(acknowledgments == (accepted ? 1 : 0), "ACK_COUNTER_MISMATCH");
            boolean unchanged = before.equals(snapshot(database));
            require(accepted || unchanged, "REJECTED_ROWS_CHANGED");
            require(scalar(database, "SELECT count(*) FROM queue WHERE id=3 AND event_id='synthetic-ack-3'") == 1,
                "UNRELATED_TAIL_REMOVED");
            try (Cursor c = database.rawQuery("SELECT body,bytes,generation FROM queue WHERE id=3", null)) {
                require(c.moveToFirst() && tailBody.equals(c.getString(0)) && c.getInt(1) ==
                    tailBody.getBytes(StandardCharsets.UTF_8).length && c.getInt(2) == 0, "TAIL_BYTES_CHANGED");
            }
            // Even an accepted response deliberately not acknowledged must retain everything.
            if (accepted) {
                String tail = snapshot(database);
                apply.invoke(null, database, Arrays.asList(3L), false);
                require(tail.equals(snapshot(database)) && scalar(database,
                    "SELECT CAST(value AS INTEGER) FROM state WHERE key='requests_acked'") == 1,
                    "DISCARDED_ACK_DELETED_ROWS");
            }
            JSONObject result = new JSONObject();
            result.put("case", name); result.put("response_category", field(decision, "category"));
            result.put("accepted", actual); result.put("queue_rows_before", 3); result.put("queue_rows_after", rows);
            result.put("ack_counter", acknowledgments);
            result.put("rejected_rows_byte_identical", accepted ? JSONObject.NULL : unchanged);
            result.put("unrelated_tail_preserved", true); result.put("passed", true);
            return result;
        }
    }

    private JSONObject execute(String variant) throws Exception {
        Class<?> queue = Class.forName("com.cama.telemetry.direct_lab.DirectQueue", false, getClassLoader());
        Method predicate = queue.getDeclaredMethod("acceptedCloudResponse", JSONObject.class); predicate.setAccessible(true);
        boolean documented = (Boolean) predicate.invoke(null, new JSONObject("{\"status\":\"Ok\"}"));
        boolean legacy = (Boolean) predicate.invoke(null, new JSONObject("{\"status\":1}"));
        require(documented == variant.equals("after") && legacy, "DOCUMENTED_RESPONSE_BEFORE_AFTER");
        JSONObject result = new JSONObject();
        result.put("documented_status_ok_accepted", documented); result.put("legacy_integer_one_accepted", legacy);
        result.put("sender_instantiated", false); result.put("transport_invoked", false);
        result.put("raw_response_body_recorded", false);
        JSONArray cases = new JSONArray();
        if (variant.equals("after")) {
            Method classify = queue.getDeclaredMethod("classifyCloudResponse", int.class, String.class); classify.setAccessible(true);
            Method apply = queue.getDeclaredMethod("applyAcknowledgment", SQLiteDatabase.class, List.class, boolean.class);
            apply.setAccessible(true);
            cases.put(fixture(classify, apply, "documented_ok", 200, "{\"status\":\"Ok\"}", true, "ACKNOWLEDGED"));
            cases.put(fixture(classify, apply, "legacy_one", 200, "{\"status\":1}", true, "ACKNOWLEDGED"));
            cases.put(fixture(classify, apply, "empty_quota", 200, "{\"status\":\"Ok\",\"quota_limited\":[]}", true, "ACKNOWLEDGED"));
            cases.put(fixture(classify, apply, "false_quota", 200, "{\"status\":\"Ok\",\"quota_limited\":false}", true, "ACKNOWLEDGED"));
            cases.put(fixture(classify, apply, "null_quota", 200, "{\"status\":\"Ok\",\"quota_limited\":null}", true, "ACKNOWLEDGED"));
            for (String status : new String[]{"\"ok\"", "\"OK\"", "\" Ok \"", "\"1\"", "1.5", "1.0", "0", "true", "null"})
                cases.put(fixture(classify, apply, "unknown_status_" + cases.length(), 200,
                    "{\"status\":" + status + "}", false, "UNRECOGNIZED_RESPONSE"));
            cases.put(fixture(classify, apply, "missing_status", 200, "{}", false, "UNRECOGNIZED_RESPONSE"));
            for (String quota : new String[]{"[\"product_analytics\"]", "true", "\"unknown\"", "{}", "0"})
                cases.put(fixture(classify, apply, "limited_quota_" + cases.length(), 200,
                    "{\"status\":\"Ok\",\"quota_limited\":" + quota + "}", false, "QUOTA_LIMITED"));
            for (String malformed : new String[]{"", "{\"status\":", "[]", "null", "{status:\"Ok\"}",
                    "{'status':'Ok'}", "{\"status\":\"Ok\"} trailing", "{\"status\":\"Ok\"}{\"status\":1}",
                    "{\"status\":\"No\",\"status\":\"Ok\"}", "{\"status\":\"Ok\",\"value\":NaN}"})
                cases.put(fixture(classify, apply, "malformed_" + cases.length(), 200,
                    malformed, false, "MALFORMED_RESPONSE"));
            cases.put(fixture(classify, apply, "non_200", 401, "{\"status\":\"Ok\"}", false, "HTTP_REJECTED"));
            cases.put(fixture(classify, apply, "server_error", 503, "{\"status\":\"Ok\"}", false, "HTTP_NOT_ACKNOWLEDGED"));
            char[] oversized = new char[8193]; Arrays.fill(oversized, ' ');
            cases.put(fixture(classify, apply, "bounded_size", 200, new String(oversized), false, "RESPONSE_TOO_LARGE"));
        }
        result.put("cases", cases); result.put("case_count", cases.length()); result.put("passed", true);
        return result;
    }

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        String nonce = getIntent().getStringExtra("nonce"), variant = getIntent().getStringExtra("variant");
        if (nonce == null || !nonce.matches("[a-f0-9]{32}") || !("before".equals(variant) || "after".equals(variant))) return;
        JSONObject value = new JSONObject();
        try { value = execute(variant); }
        catch (Exception failure) {
            try {
                value.put("passed", false);
                value.put("failure_category", failure instanceof CheckFailure ? failure.getMessage() : "NATIVE_PROOF_FAILED");
                value.put("failed_case", currentCase);
            } catch (Exception ignored) { }
        }
        try {
            value.put("schema_version", 1); value.put("scope", "PERMISSIONLESS_ANDROID_ACK_FUNCTIONS_OFFLINE");
            value.put("variant", variant); value.put("nonce", nonce);
            AtomicFile file = new AtomicFile(new File(getFilesDir(), "response-proof.json"));
            FileOutputStream out = file.startWrite();
            try { out.write(value.toString().getBytes(StandardCharsets.UTF_8)); file.finishWrite(out); }
            catch (Exception failure) { file.failWrite(out); throw failure; }
            TextView label = new TextView(this); label.setText("Offline ACK proof: " + value.optBoolean("passed")); setContentView(label);
        } catch (Exception ignored) { finish(); }
    }
}

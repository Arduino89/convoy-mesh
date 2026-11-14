package com.cama.telemetry.runtime_control;

import android.app.Activity;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.Process;
import android.widget.TextView;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import org.json.JSONObject;

/** Native runtime control only: no network permission, SDK, Flutter or telemetry. */
public final class MainActivity extends Activity {
    private String nonce;
    private long launches;
    private boolean committed;
    private TextView label;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        label = new TextView(this);
        label.setTextSize(22);
        label.setPadding(24, 24, 24, 24);
        setContentView(label);
        nonce = getIntent().getStringExtra("control_nonce");
        if (nonce == null || !nonce.matches("[a-f0-9]{32}")) {
            label.setText("CONTROL NOT READY: launch nonce missing");
            return;
        }
        SharedPreferences prefs = getSharedPreferences("runtime_control", MODE_PRIVATE);
        long previous = prefs.getLong("launches", 0L);
        if (previous < 0L || previous == Long.MAX_VALUE) {
            label.setText("CONTROL NOT READY: invalid counter");
            return;
        }
        launches = previous + 1L;
        committed = prefs.edit().putLong("launches", launches).commit();
        label.setText("Runtime control\nlaunches=" + launches + "\npid=" + Process.myPid()
            + "\npersisted=" + committed);
    }

    @Override public void onResume() {
        super.onResume();
        if (!committed) return;
        try {
            JSONObject record = new JSONObject();
            record.put("schema_version", 1);
            record.put("package", getPackageName());
            record.put("nonce", nonce);
            record.put("pid", Process.myPid());
            record.put("launches", launches);
            record.put("ready", true);
            File temporary = new File(getFilesDir(), "ready.tmp");
            File destination = new File(getFilesDir(), "ready.json");
            try (FileOutputStream stream = new FileOutputStream(temporary)) {
                stream.write(record.toString().getBytes(StandardCharsets.UTF_8));
                stream.getFD().sync();
            }
            if (!temporary.renameTo(destination)) throw new IllegalStateException("rename");
            label.append("\nresumed=ready");
        } catch (Exception failure) {
            // A previous sentinel cannot pass: every launch requires a new nonce and PID.
            label.append("\nCONTROL NOT READY: sentinel write failed");
        }
    }
}

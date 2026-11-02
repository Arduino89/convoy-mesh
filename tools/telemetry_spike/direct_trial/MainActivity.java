package com.cama.telemetry.direct_lab;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.widget.TextView;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Debug-only command surface. No Convoy code, analytics SDK or arbitrary payloads. */
public final class MainActivity extends Activity {
    private static DirectQueue queue;
    private static final ExecutorService COMMANDS = Executors.newSingleThreadExecutor();
    private TextView label;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        label = new TextView(this);
        label.setText("Synthetic direct telemetry LAB\nLoopback only");
        setContentView(label);
        handle(getIntent());
    }

    @Override public void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handle(intent);
    }

    private void handle(Intent intent) {
        final String action = intent.getStringExtra("action");
        final String nonce = intent.getStringExtra("nonce");
        if (nonce == null || !nonce.matches("[a-f0-9]{32}") || action == null) return;
        final String run = intent.getStringExtra("run_id");
        final int capacity = intent.getIntExtra("capacity", 1000);
        final int start = intent.getIntExtra("start", 1);
        final int count = intent.getIntExtra("count", 0);
        final String stop = intent.getStringExtra("stop_at");
        COMMANDS.execute(() -> {
            try {
                if (queue == null) queue = new DirectQueue(getApplicationContext());
                boolean ok = false;
                String error = "";
                try {
                    switch (action) {
                        case "configure": queue.configure(run, capacity); break;
                        case "grant": queue.grant(); break;
                        case "capture": queue.capture(start, count); break;
                        case "flush": queue.kick(); break;
                        case "revoke": queue.revoke(nonce, stop); break;
                        case "preflight_checks": queue.preflightChecks(); break;
                        case "state": break;
                        default: throw new IllegalArgumentException("UNKNOWN_ACTION");
                    }
                    ok = true;
                } catch (Exception failure) {
                    // No exception messages/device diagnostics are exported.
                    error = "COMMAND_FAILED";
                }
                queue.writeState(nonce, action, ok, error);
                final boolean passed = ok;
                runOnUiThread(() -> label.setText("Synthetic direct telemetry LAB\n" + action
                    + " completed=" + passed));
            } catch (Exception failure) {
                runOnUiThread(() -> label.setText("LAB BLOCKED: storage unavailable"));
            }
        });
    }
}

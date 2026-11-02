# Synthetic direct Android sender

An isolated native APK, `com.cama.telemetry.direct_lab`, using Android SQLite,
`AtomicFile`, and `HttpURLConnection`. No analytics SDK, Flutter dependency,
new server, background framework, account or cloud destination. The existing
runtime-control builder, Android runner, exact wire auditor and reconciliation
contract are reused. The new code is limited to a bounded local queue, explicit
consent transitions, one sender thread and debug commands for reproducible tests.

Build with the installed JDK17/platform36/build-tools36.0.0, after the separate
runtime control has passed:

```sh
python3 tools/telemetry_spike/direct_trial/build.py \
  --sdk "$ANDROID_HOME" --jdk "$JAVA_HOME" \
  --source-commit "$GITHUB_SHA" --out "$RUNNER_TEMP/direct-build"
```

The build receipt identifies the exact sources, verified APK identity, signing
certificate and APK hash. This is disposable debug signing, not a release.

## Consent and persistence

Initial consent is false. Capture while denied only increases a refusal counter.
Revocation commits false consent and a new generation using SQLite DELETE journal
and synchronous FULL, then deletes only the telemetry queue in a second transaction.
A boot with false consent purges leftover rows before any sender starts. Grant
purges obsolete rows before enabling capture/delivery in one transaction. An ACK
can delete only its own monotonically allocated row IDs, never change consent or
restore queued data. No trace or settings reset is used.

The first committed false-consent transaction is the durable revocation boundary.
An interruption **before** that commit has no accepted/acknowledged revocation and
can recover the previous consent and deliver old data. The `before_intent_commit`
counterexample records this separately; it must never be counted as a successful
accepted revocation. The other hooks (`after_intent`, `during_purge`, `after_purge`)
interrupt after the boundary, including with a purge transaction still open.
Restart online must still transmit no revoked queued rows.

A dispatch gate covers final validation and the fixed-length HTTP request body's
write, flush and close. Revocation then proceeds without waiting for the response.
The local receiver distinguishes batches already received before revocation.
Already-transmitted data cannot be recalled. An attempted/partial network write
is also potentially transmitted: `dispatch_attempts` counts attempts before
writing, whereas `requests_started` counts completed body writes, not proof of
remote receipt. Waiting for the gate may take the connection/write time; no
claim is made that tapping revoke retroactively prevents an earlier dispatch.

## Payload, bounds and retries

Only the synthetic six-field event contract plus its two privacy controls and
existing event envelope are serialized. `distinct_id` is exactly the synthetic
run ID; per-event UUID and timestamp are created once and retained in retries.
`validateBytes` checks the final serialized bytes immediately before transport;
`preflight_checks` exercises native rejection of a foreign UUID identity, extra
property, wrong privacy flag, wrong token and invalid timestamp without enqueueing
or sending fixtures. The existing receiver independently checks final headers
and payload. HTTP 200 alone does not mean its audit passed.

The only endpoint is literal loopback `127.0.0.1:8765/batch/`, with a built-in fake
token, no redirects and no device-configured remote proxy. The explicit
`Java/1.8` user agent identifies this Java API client without exposing Android
model/build data; it does not impersonate PostHog. `adb reverse` availability
controls reachability; this is not a radio or airplane-mode test.

The queue is bounded to 32 or 1,000 rows and 1 MiB of serialized event bytes; the
SQLite maximum is 4 MiB (its transient journal and process RAM are separate).
Oldest drops are counted durably, including across restart. Each request contains
at most 20 rows and 64 KiB. One sender retries after 1, 2, 4, then 8 seconds, with
3-second connect and 30-second response limits. Retries are intentionally
at-least-once: an ACK lost after receipt can produce duplicates with the same UUID.
Cloud deduplication, TTL/retention policy, phone energy cost, OEM lifecycle,
multi-process concurrency, power loss and flash-forensic erasure remain unproven.

## Debug command contract

Launch `.MainActivity` with `--es action NAME --es nonce HEX32`.
`configure` takes a synthetic `run_id` and `capacity` 32 or 1000 and cannot reset
an already-configured installation. Other commands: `grant`, `capture` (`start`,
`count`), `flush`, `revoke` (optional `stop_at`), `state`, `preflight_checks`.
Completed commands write `files/state.json` with the matching nonce. Crash hooks
write `files/checkpoint.json` with the matching nonce, stage and whether revocation
is durable, then wait to be killed. A partial command never gets a success ACK.

The unrelated settings value and trace are random synthetic per-install
sentinels. Missing sentinel initialization alongside an existing database/trace
blocks startup; a missing trace is not recreated. Baseline actual values/hashes
must be compared after every critical transition. `pm clear` is permissible only
between independent cases, never as a revocation implementation.

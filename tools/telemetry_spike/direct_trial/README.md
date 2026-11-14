# Synthetic direct Android sender

An isolated native APK, `com.cama.telemetry.direct_lab`, using Android SQLite,
`AtomicFile`, and `HttpURLConnection`. No analytics SDK, Flutter dependency,
new server, background framework or account. Loopback is the default; the optional
cloud profile below requires a separately provisioned private configuration. The existing
runtime-control builder, Android runner, exact wire auditor and reconciliation
contract are reused. The new code is limited to a bounded local queue, explicit
consent transitions, one sender thread and debug commands for reproducible tests.

## Verified checkpoint — 3 November 2026

The local Android regression of source `2d76100fda1df0637e953f4ad90f26073028880c`
completed successfully in [run 41600690330, job 125798442094](https://github.com/Arduino89/convoy-mesh/actions/runs/41600690330/job/125798442094).
The APK is 45,459 bytes, SHA-256
`91eacc843b92be29806fe69cc2d8b76e3615c8b9dc177563d33ef8f33c3d83fe`.
The [independent review](../../../docs/telemetry-evidence/2026-11-03/direct-review-41600690330/INDEPENDENT_REVIEW.md)
verified 107 bundle hashes and reconstructed delivery/revocation/retry/sentinel
results. The 133 passing host tests remain separate from Android evidence.
See the [reproducible review command](../README.md) to recompute the receipts
without rerunning Android.

All native states report `local_loopback`. The seven additional budget/response
helper checks ran on Android; they do not test private cloud configuration, HTTPS
or durable cloud reservations. **Cloud remains NOT_RUN:** authenticated access to
`data_deletion_requests` reports that its alpha API is not publicly available,
and the protected GitHub runner secret is absent. The
[cloud preflight](../../../docs/telemetry-evidence/2026-11-03/cloud-preflight.json)
must be satisfied before any ingestion. Historical receipts and Convoy remain
unchanged.

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

The default endpoint is literal loopback `127.0.0.1:8765/batch/`, with a built-in fake
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

## Separately gated PostHog Cloud profile

The current authorization permits one synthetic run in the existing EU laboratory
project after destination/access/privacy/retention/deletion/free-quota review.
It does not permit automatic cloud activation, another account or Convoy changes.
There is no cloud credential in this APK or source. While the app is force-stopped,
the authorized harness may provision `files/cloud-config.private.json` through
stdin in the app's private sandbox. It is never an intent extra, argv value,
public artifact or diagnostic output. The JSON has exactly `mode` (`posthog_cloud`),
`endpoint` (`https://eu.i.posthog.com/batch/`), `api_key`, synthetic `run_id` and an
integer `row_limit` from 1 to 500. No other endpoint is accepted. HTTPS uses default
Android TLS certificate and hostname verification and configured proxy policy;
redirects remain disabled. Network-state permission supplies only availability,
internet/validation flags and coarse transport type, not SSID or device identity.

Cloud mode must be introduced into an unconfigured installation. Its endpoint,
key, run ID and limit are bound in SQLite; missing or altered configuration after
binding blocks startup, without falling back to loopback. **Never clear app data
between cloud phases.** Use one installation and run for normal IDs 1–100,
revoked IDs 101–120, new IDs 121–130 and retry IDs 131–140. Revocation and consent
do not reset the cloud budget. A new job/installation requires an externally
verified remaining authorization budget; there is no automatic cloud rerun.

Before each possible network attempt, a FULL SQLite transaction reserves the
batch's entire row count. Failed connections, partial writes, retries, deliberately
ignored responses and process interruptions never refund reservations. Both the
configured lower limit and a native ceiling of **500 reserved rows** apply. A
20-row batch with only 10 rows remaining is blocked before connection; it is not
silently shrunk. Network reported offline or unvalidated is checked before
reservation. Reservation counts are conservative upper bounds, not proof of
transmission or cloud receipt. `cloud_rows_written` counts completed body writes.

The explicit cloud-only `arm_retry` command (`start=131`, `count=10`) must precede
capture with an empty queue and no in-flight request. It arms one durable fault:
after an accepted HTTP 200 for that exact batch, discard the acknowledgement once,
retain the rows and retry their identical UUIDs/timestamps. This is **deliberately
ignored HTTP acknowledgement**, not measured network loss. It cannot be rearmed
or reset by consent changes. At-most-500 budgeting still counts each attempt.

Two fsynced, append-only files contain synthetic audit evidence:
`cloud-preflight.jsonl` records each reserved batch's event bytes with the project
token explicitly replaced by `<redacted:project-token>`; it is therefore not an
unredacted copy of the complete HTTP body. `cloud-transport.jsonl` records attempt
IDs, event IDs/UUIDs, row counts, reservation totals, body-write completion and
response classifications. Neither file contains the key, arbitrary response text
or request credentials. Audit-write failure blocks subsequent delivery. Their
size is bounded by the 500-row budget and bounded event schema; they are separate
from the SQLite size ceiling and are not ordinary production diagnostic logs.

A cloud HTTP 200 is accepted only with a bounded JSON object containing integer
`status: 1` and no effective `quota_limited` marker. Unknown success bodies,
quota-limited responses and HTTP 3xx/4xx halt further delivery while preserving
the queue for investigation. This acknowledgement still does **not** establish
ingestion: connector readback must enumerate raw stored event rows, UUIDs,
properties, missing and duplicate IDs. Server enrichment, retention and deletion
remain separate observations, not guarantees inferred from this transport.

## Gated execution and connector reconciliation

Cloud execution is manual and disabled by default. The workflow requires the
local regressions at the exact checked-out commit before cloud capture. `prepare_ci_cloud.py` takes no
arguments in CI: it reads `CONVOY_CLOUD_GATE` and the step-scoped secret
`CONVOY_LAB_POSTHOG_TOKEN`, validates the gate against Git HEAD,
`GITHUB_WORKFLOW:GITHUB_RUN_NUMBER` and attempt 1, then creates mode-0600
`$RUNNER_TEMP/cloud-private/gate.json` and `config.json`. A missing or pending
deletion/access/privacy/retention/quota/local-regression check prevents creation.
The gate expires within 24 hours and records the externally verified remaining
budget. Reusing a gate for another workflow number or retry is rejected.
At this checkpoint cloud execution is **NOT_RUN**; operational prechecks are
incomplete and no passing cloud gate has been issued.

Only after those gates, `tools/telemetry_spike/run_ci_cloud_lab.sh` starts the
separate cloud experiment. The harness requires a fresh LAB install and the same
Android boot as the independent runtime control. It enables airplane mode and
disables Wi-Fi and mobile data for offline capture, then checks the native
`ConnectivityManager` result; merely removing `adb reverse` is insufficient.
Restoration is checked before online transmission. Credentials enter the private
app file through stdin, never a command argument. Cleanup stops the app, removes
that file and restores the initial radio settings. If process stop cannot be
attested, cleanup attempts to leave the emulator offline instead.

The cloud harness emits `TRANSPORT_COMPLETE_READBACK_PENDING`, never a delivery
PASS. Its public `preflight.jsonl` omits the already-redacted credential field,
retaining `credential_redacted`, envelope keys and exact synthetic event bodies.
Partial failures retain available receipts; an unknown budget consumes the full
remaining allowance for any future authorization rather than granting a refund.

Generate the required raw-row and separate count queries from actual receipts:

```sh
python3 tools/telemetry_spike/reconcile_cloud_trial.py \
  --transport "$RUNNER_TEMP/cloud-public/result.json" \
  --out "$RUNNER_TEMP/cloud-query"
```

Without `--readback`, exit 1 with `PENDING_READBACK` is intentional. `query.json`
contains both exact queries: an explicit timestamp window with a 300-second clock
margin, run/identity/client-UUID selectors, raw `LIMIT 500`, and `count()` using
the same predicate. Neither query deduplicates. The window is finite; arbitrary
server timestamp/identity mutation outside it is not ruled out.

Execute both queries through the existing connector and preserve the original
responses privately. The normalized readback JSON requires `schema_version: 1`,
`project_id: 330212`, the exact `run_id` and `source_commit`, `query`, `count_query`,
`queried_at_utc`, `complete: true`, `raw_count`, `rows`, and
`row_response_ref`/`row_response_sha256` plus
`count_response_ref`/`count_response_sha256`. Each row contains all eight columns:
`uuid`, `event`, `properties`, `timestamp`, `distinct_id`, `created_at`,
`person_mode`, `person_id`. `normalize_connector_rows()` accepts the extracted
column/row arrays and parses JSON properties without dropping duplicate rows.
Display-only pipe tables must first be extracted faithfully; screenshots or a
count alone are insufficient. The raw count must equal the returned row count.
Populate counts, response references and SHA-256 hashes from actual connector
outputs; the normalized file is not a substitute for those original responses.

```sh
python3 tools/telemetry_spike/reconcile_cloud_trial.py \
  --transport "$RUNNER_TEMP/cloud-public/result.json" \
  --readback /private/path/normalized-readback.json \
  --out "$RUNNER_TEMP/cloud-readback"
```

The result distinguishes received/missing/revoked/duplicate IDs and the observed
handling of repeated UUIDs. Extra server metadata requires review; unknown scalar
values and person identifiers are redacted. These commands are a prepared
protocol, not evidence that a cloud run or deletion has occurred.

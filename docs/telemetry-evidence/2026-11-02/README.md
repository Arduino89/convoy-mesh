# Synthetic Android telemetry receipts — 2 November 2026

Executable source: `764bc41080c7b85d25ea895ed16c4b94130c5822`.
[Run 41429419307 / job 125223965237](https://github.com/Arduino89/convoy-mesh/actions/runs/41429419307/job/125223965237).
The job **failed the revocation requirement** after completing all four SDK scenarios; Android was operational. No merge, release, Convoy integration or real users.

| Check | Actual observation |
|---|---|
| Independent native control on the same boot | PASS; PID2110→2268, persisted counter1→2 |
| Offline capture, process restart, network return |100/100 unique, no missing or duplicate rows |
| Refusal |20 attempts before first consent in each fresh installation; no requests to the local receiver in those windows |
| Revocation and reconsent |FAIL: all20 forbidden IDs101..120 reappeared; all10 new IDs121..130 arrived |
| Unrelated synthetic file and preference |Unchanged at observed boundaries, including fresh native reads after flush |
| Final request content |11 requests,182 event rows, no contract violations; exact run distinct_id and independent event UUID |
| Lost response after acceptance |20 rows for10 IDs, each repeated with the same UUID |
| Queue32 saturation |32/45 received; missing IDs1..13 explicitly retained in the oracle |

Primary receipts are in [run-41429419307](run-41429419307). The original46-file export was reconstructed from job-log chunks:39,125 bytes, SHA-256 `3bb5a34c963068ed33e023844be56502181613ce14d884d46f31c21579453996`. Every member was verified against its SHA256SUMS.txt before review. No APK, debugger connection, credential, screen recording or complete diagnostic log is included.

From the repository root, verify and recompute the exported observations:

```sh
(cd docs/telemetry-evidence/2026-11-02/run-41429419307 && sha256sum -c SHA256SUMS.txt)
python3 tools/telemetry_spike/summarize_followup.py docs/telemetry-evidence/2026-11-02/run-41429419307/lab-public
python3 -m unittest discover -s tools/telemetry_spike -p 'test_*.py' -q
```

`summarize_followup.py` reports observations, not adoption approval. `lab-public/result.json` retains the final acceptance verdict and searches revoked IDs across both the normal and later retry receivers. The77 host tests passed locally and in this run; they are not Android evidence. A [separate reviewer recalculated the raw synthetic receipts](independent-review-41429419307.json) with independent Counter/set logic, confirming event counts, refusal windows, ordering, UUIDs and13 fresh native sentinel reads. This was receipt review, not another Android run or adoption approval.

[execution-provenance.json](execution-provenance.json) includes earlier bootstrap attempts and the first successful control-only run41427231262. The two top-level control receipts belong to that earlier run, not the full SDK run. [identity-regression](identity-regression) contains the historical red/green verifier regression: two failures before and two passes after, separate from native execution.

The emitter deliberately validates and canonicalizes JSON. Consequently the in-run gate reference hashes the original formatted receipt, while the exported receipt has a different byte hash. [runtime-gate-serialization.json](runtime-gate-serialization.json) records both. The [original receipt reconstructed from its ordered job-log JSON](runtime-gate-original-reconstructed.json) matches the referenced SHA-256 and is semantically identical to the canonical export. No Android rerun was used to reconcile this formatting difference.

Scope and limits: actual official Android SDK, local fake-token receiver, debug x86_64/API35 emulator. No new PostHog Cloud ingestion, global traffic capture, OS-reboot/crash-during-write guarantee, revocation during an in-flight request, iOS test or physical battery/OEM/GPS/Bluetooth result. The file/preference are synthetic preservation sentinels; Convoy data was never accessed. Queue losses are visible through the laboratory oracle, not a demonstrated production discard counter. See the [decision report](../../telemetry-minimum-infrastructure.md) for resource observations and the documented, unexecuted Firebase comparison.

APKs were rebuilt because earlier artifacts were unavailable. Source, lock, resolved native version, APK digest and signing-certificate receipts are retained. Repeating the build reproduces the experiment; debug signing and build metadata do not promise byte-identical APKs. This evidence-only documentation update does not imply a new Android execution.

Source-level follow-up: [sdk-source-review.json](sdk-source-review.json) pins18 exact vendor Git blobs for Android3.75.0/core6.48.0, and [independent-sdk-source-review.json](independent-sdk-source-review.json) records a separate source review. These explain why reset preserves queued events and why close is not purge; they are not new Android executions. Interrupted revocation remains NOT_RUN. The executable/harness and original46-file native export are unchanged.

Scoped Mixpanel follow-up: [mixpanel-preflight.json](mixpanel-preflight.json) records Flutter 3.1.0 and declared Android 8.11.1 source review with 19 verified official Git blobs, including a [separate Android review](independent-mixpanel-source-review.json). Endpoint-at-init and a supported asynchronous queue-delete API are present; extra session metadata and the opt-in event prevent the unchanged minimum-content contract from passing the precheck. **PRECHECK_BLOCKED_MINIMIZATION; every Mixpanel runtime scenario remains NOT_RUN**, including interrupted revocation and sentinel preservation. No new dependency resolution, build, Android/host test, cloud account, ingestion or runner execution. The original PostHog receipts remain unchanged; this receipt does not reuse their counts as Mixpanel results.

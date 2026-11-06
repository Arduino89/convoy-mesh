# Offline Android ACK compatibility follow-up

Scope: PR #5 laboratory only. **Zero new PostHog events**, including retries of the 20 previously stored events. No merge, integration, release, paid service or credential access.

The executable baseline is `75b83254c99f20703f8a4ddbcc0da92a41d9990c`. Its `DirectQueue.java` is identical to actual run #15 source `809caf200f6232b162fee009fa2a7c2b484d7855`, SHA-256 `81222e42f65f27d5524ad80b5b66eb5f685b6f3091e5d467a564636ecaa31312`.

## Established incompatibility and correction

The official [API overview, Responses / 200](https://posthog.com/docs/api#status-code-200) documents `{"status":"Ok"}`. That response acknowledges the request; it does not establish valid events or durable ingestion. The old predicate accepts only integer `1`. The actual run #15 response value and body were not recorded and remain unknown.

The correction accepts exact string `Ok` plus the existing integer `1`, preserving the conservative quota guard. Android's strict JSON reader rejects malformed, trailing, nonstandard and duplicate-key JSON before interpretation. The audit records a finite `response_category`; it does not preserve the body, an arbitrary status value or a body hash.

The unchanged selected-row deletion and `requests_acked` increment now share one SQLite transaction helper used by the sender and native proof. Rejected or deliberately discarded acknowledgments return before any database mutation. The host cloud trial reports an allowlisted permanent-block cause immediately, including when the queue happens to be empty.

## Reproducible proof

The same permissionless Activity is compiled twice: first with the baseline Java verbatim, then with the corrected class. Reflection invokes the actual private predicate without constructing a sender. The baseline must reject `Ok` (behavior RED; the counterexample harness succeeds by observing this). The candidate must accept it and pass 33 native classification / SQLite cases.

SQLite databases are in-memory and separate from application data. Negative cases preserve IDs, UUIDs, body bytes and counters. Positive cases delete only the selected batch and preserve the unrelated tail. The proof also checks an accepted but deliberately unacknowledged tail remains queued. Both APKs request zero permissions, and hashes, package, version and signature are checked before installation. An independent Android lifecycle control and an offline radio / default-network barrier run first.

The runner entry point is `bash tools/telemetry_spike/run_ci_ack_response.sh`. It requires SDK 36, build-tools 36.0.0, JDK 17, a working API 35 emulator and `BASELINE_JAVA` pointing to the pinned baseline file. It runs the lifecycle control, builds both proof APKs, then runs the native comparison. Source, APK and signature identities are retained in the result. No normal LAB sender, cloud configuration, credentials or POST is invoked, including loopback.

Host fail-fast regressions exercise the actual `run_cases` / drain path. To reproduce RED, copy the current `tools/telemetry_spike` directory to a temporary directory, replace only `ci_cloud_trial.py` with that file from the baseline commit, and run `python3 -m unittest test_ci_cloud_trial -q` there: 23 tests, 4 expected failures. With the candidate module, all 23 pass. [Recorded host comparison](host-red-green.json).

Current host suite: 202 controls, 201 passed and one historical shell / pipefail reproduction skipped on this host's newer Dash. These checks do not replace Android. [Independent source review](independent-source-review.json) passed. Android execution and review of the concrete, pinned workflow are still pending.

## Limits

The baseline proof covers the old predicate. Candidate fixtures cover the real String classifier and shared SQLite ACK transaction. They do not execute the InputStream / UTF-8 I/O path, TLS, full sender, server storage or cloud delivery. Cloud revocation, new consent, retry / deduplication, physical phones, battery and overall infrastructure privacy remain unverified. Existing local Android runs #14 / #15 remain historical evidence.

The prior 20 rows and closed 700-row prudential budget remain untouched, with future cloud allowance zero. A one-use, public standard runner wrapper is planned for run #16, attempt 1, pinned to the prepared source and baseline; it contains no secrets or cloud inputs and must be independently reviewed before launch and restored afterwards. [Plan](plan.json).

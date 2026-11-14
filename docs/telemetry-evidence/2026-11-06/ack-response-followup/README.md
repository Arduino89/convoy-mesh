# Offline Android ACK compatibility follow-up

**Android run #16 passed:** the unchanged baseline rejects documented `Ok`; the candidate accepts it and passes all 33 native cases. Independent source, concrete workflow and runtime receipt reviews passed. [Summary](summary.json) · [Android receipt](android-result.json) · [CI identity](ci-metadata.json).

Scope: PR #5 laboratory only. **Zero new PostHog events**, including retries of the 20 previously stored events. No merge, integration, release, paid service or credential access.

The executable baseline is `75b83254c99f20703f8a4ddbcc0da92a41d9990c`. Its `DirectQueue.java` is identical to actual run #15 source `809caf200f6232b162fee009fa2a7c2b484d7855`, SHA-256 `81222e42f65f27d5524ad80b5b66eb5f685b6f3091e5d467a564636ecaa31312`.

## Established incompatibility and correction

The official [API overview, Responses / 200](https://posthog.com/docs/api#status-code-200) documents `{"status":"Ok"}`. That response acknowledges the request; it does not establish valid events or durable ingestion. The old predicate accepts only integer `1`. The actual run #15 response value and body were not recorded and remain unknown.

The correction accepts exact string `Ok` plus the existing integer `1`, preserving the conservative quota guard. Android's strict JSON reader rejects malformed, trailing, nonstandard and duplicate-key JSON before interpretation. The audit records a finite `response_category`; it does not preserve the body, an arbitrary status value or a body hash.

The unchanged selected-row deletion and `requests_acked` increment now share one SQLite transaction helper used by the sender and native proof. Rejected or deliberately discarded acknowledgments return before any database mutation. The host cloud trial reports an allowlisted permanent-block cause immediately, including when the queue happens to be empty.

## Reproducible proof

The same permissionless Activity is compiled twice: first with the baseline Java verbatim, then with the corrected class. Reflection invokes the actual private predicate without constructing a sender. The baseline must reject `Ok` (behavior RED; the counterexample harness succeeds by observing this). The candidate must accept it and pass 33 native classification / SQLite cases.

SQLite databases are in-memory and separate from application data. Negative cases preserve IDs, UUIDs, body bytes and counters. Positive cases delete only the selected batch and preserve the unrelated tail. The proof also checks an accepted but deliberately unacknowledged tail remains queued. Both APKs request zero permissions, and hashes, package, version and signature are checked before installation. An independent Android lifecycle control and an offline radio / default-network barrier run first.

The runner entry point is `bash tools/telemetry_spike/run_ci_ack_response.sh`. It requires SDK 36, build-tools 36.0.0, JDK 17, a working API 35 emulator and `BASELINE_JAVA` pointing to the pinned baseline file. It runs the lifecycle control, builds both proof APKs, then runs the native comparison. Source, APK and signature identities are retained in the result. The native fixture entry point never invokes the normal LAB sender, cloud configuration, credentials or POST. Inherited host tests may use loopback fixtures and runner bootstrap uses network; the boundary is zero PostHog ingestion.

Host fail-fast regressions exercise the actual `run_cases` / drain path. To reproduce RED, copy the current `tools/telemetry_spike` directory to a temporary directory, replace only `ci_cloud_trial.py` with that file from the baseline commit, and run `python3 -m unittest test_ci_cloud_trial -q` there: 23 tests, 4 expected failures. With the candidate module, all 23 pass. [Recorded host comparison](host-red-green.json).

The CI host suite passed **202/202, with no skips**. The earlier local host result was 201 passed / one historical shell reproduction skipped on newer Dash; it is separate from CI and from Android. [Independent source review](independent-source-review.json) passed; [concrete workflow review](independent-workflow-review.json) gave GO only for this offline run. [Independent runtime receipt review](independent-runtime-review.json) passed.

## Limits

The baseline proof covers the old predicate. Candidate fixtures cover the real String classifier and shared SQLite ACK transaction. They do not execute the InputStream / UTF-8 I/O path, TLS, full sender, server storage or cloud delivery. Cloud revocation, new consent, retry / deduplication, physical phones, battery and overall infrastructure privacy remain unverified. Existing local Android runs #14 / #15 remain historical evidence.

The prior 20 rows and closed 700-row prudential budget remain untouched, with future cloud allowance zero. The independently reviewed one-use public standard runner wrapper executed run #16, attempt 1. It contains no PostHog secrets or cloud inputs. The original workflow was restored byte for byte in closure `24374ddd4f855a6df01780bfeb92c135704f5ee7` with `[skip ci]`, then independently checked on GitHub. [Restoration review](independent-restoration-review.json). [Plan](plan.json).

## Exact execution and result

- Candidate source: `d93b3095f78f4924e2cf132d82e4bc041a626f7c`; baseline queue: `75b83254c99f20703f8a4ddbcc0da92a41d9990c`.
- Wrapper: `8d6c7c023eb404098d77392ef7ed0504d86572f6`, workflow SHA-256 `9a08fba8fd0e566e1a95147656512a045c848f8f002d1b789fa41b039d5b90dd`.
- [Run 42310498585 / number 16 / attempt 1 / job 128210433580](https://github.com/Arduino89/convoy-mesh/actions/runs/42310498585/job/128210433580): **SUCCESS**, API 35 x86_64 emulator, JDK 17.0.21, platform 36 / build-tools 36.0.0.
- The independent Android lifecycle control passed all eight stages on the same boot, first PID 2527 then PID 2729, with persistent launch count 1 to 2. It completed before the two fixture APKs were built and executed.

| Native boundary | Observed result |
|---|---|
| Actual baseline predicate / documented Ok | Rejected; legacy integer 1 accepted |
| Actual candidate predicate / documented Ok | Accepted; legacy integer 1 still accepted |
| Five accepted classifier / SQLite cases | Only selected IDs deleted, ACK counter 1, unrelated tail and deliberately discarded ACK preserved |
| Ten unknown status, five quota, ten malformed cases | All rows / IDs / serialized bytes unchanged, ACK counter 0 |
| HTTP rejection, server error, oversized body | Three further retained-queue cases passed |
| Offline / cleanup | Three barriers passed, both processes stopped, initial radio settings restored |

The native receipt has 33 passed cases: five accepted and 28 rejected. It records categories and queue observations, without actual response bodies or arbitrary status values. The exact 18,842-byte exported receipt is SHA-256 `83278d90dec731556d8f93580dcec2c44be38ba1b7c64c7c8658d83a932ebeb1`. The historical server body remains unknown.

Proof APKs are version 1.0 / code 1, min SDK 24 / target 36, with zero requested permissions. They were checked and installed by tools in the runner, not distributed or independently downloaded. Full builder / source / signer provenance, also for the control APK, is in the Android receipt:

- Before: `com.cama.telemetry.ack_before`, 49,555 bytes; APK SHA-256 `b4f8c120c4309eaa918eedd77fe18ea1336fc7208657ded2c4f12b25d2db9f11`; certificate SHA-256 `a8d5bd52f3d8711971de90eed42d87772698c7861c7f802c0bd01a435135cd61`.
- After: `com.cama.telemetry.ack_after`, 53,651 bytes; APK SHA-256 `172a76feeb19b2b65fc777c15fc4f06109343c6095f78f5097fabb7e405e6c28`; certificate SHA-256 `eea1d6d35243cd1551a0afa7d9a8ce4747de257cd4fcfb1e9e0e794245649f46`.

`build.status` describes the earlier build-only checkpoint; the separate native receipt and final result establish execution. No existing cloud queue was loaded or replayed. An acknowledgment fixture is not a PostHog storage count. The prior 20 received events, cloud revocation / retry gaps and all field-test limits remain unchanged. Next gate: review this offline correction; any future cloud trial requires a separate explicit allowance.

## Independent receipt recalculation

The independent reviewer fetched the actual job logs and terminal metadata separately, reconstructed all seven export chunks, matched the receipt byte for byte and checked the original control receipt as well. [Independent runtime review](independent-runtime-review.json) records the provenance and limits. It approves only the offline Android function / SQLite evidence.

From this evidence directory, run `python3 verify_runtime_evidence.py android-result.json`. The verifier uses only the Python standard library and this receipt; it imports no producer predicate, runs no Android and makes no network request. It recomputes 33 cases / five accepted / 28 byte-identical retained queues, lifecycle order, source/build identities, permission reports, offline snapshots and cleanup. Its expected input SHA-256 is fixed to the actual export. Original APK bytes were not independently downloaded. Source/workflow review and actual GitHub provenance remain separate from this local recalculation.

The runtime review's restoration status describes the point before publication of the closure. [Independent restoration review](independent-restoration-review.json) closes that pending field at commit `24374ddd4f855a6df01780bfeb92c135704f5ee7`: all nine executed code files are unchanged, PR #5 is draft, and the last run remains #16 with no extra execution observed. The final receipt commit changes documentation only. Verified original workflow SHA-256 `5e66eb7f83814e4a6bc15accfbc5a5b7f13b4c8e4fc683a83d33d52bff813cc5`.

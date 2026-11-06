# Convoy Mesh — continuity

## STATUS

**0.7.7-exp1+9 experimental pedestrian candidate**, [draft PR #4](https://github.com/Arduino89/convoy-mesh/pull/4), `experiment/pedestrian-acquisition-v1`. **149/149 CI tests pass**. [Android run #121](https://github.com/Arduino89/convoy-mesh/actions/runs/37198612027), attempt 1, **SUCCESS** for both build and emulator jobs. Exact APK bytes, source and signature independently verified; automated delivery gate passed. Physical two-phone evidence pending. No production or merge approval.

User authorized implementation, branch, commits, draft PR and build on 2026-10-03, replacing the earlier read-only phase. Fix demonstrated acquisition/cadence defects first; preserve provider/5 s request/BLE/HISTORY. Do not restart from main or PR #3.

## CURRENT ARCHITECTURE

Nearby: native BLE without continuous GNSS/FGS. Map preview: location without outing track. Outing: GNSS/track plus native foreground owner. Source freshness, UI time and radio presence remain separate. HISTORY ACK/retry is bounded and never overwrites live position.

Estimator: static consensus plus majority-supported moving acquisition; first/reacquired points do not add trail. At most 26 time bins within 25 s. Motion evidence prefers 20 s, using the existing 25 s window when fewer than five observations are present. No provisional publication. IMU alone cannot authorize large unsupported innovations. Classifier unchanged; service test clock defaults to DateTime.now in production.

Diagnostics remain independent of outing lifetime, local and capped at four minutes. Process-loss outing reconstruction is still absent.

Experimental distribution: native GitHub Releases, fixed tag `experimental-latest` and asset `Convoy-Mesh-Experimental.apk`; a separate versioned prerelease preserves each promoted APK. The branch-local `.github/workflows/experimental-download.yml` explicitly selects an approved successful CI run/source/hash, validates and publishes existing bytes. No automatic publication of ordinary builds, rebuild or signing change.

## CANONICAL SOURCES

- [README](README.md): current install/artifact checkpoint and fixed download URL.
- [Experimental download](https://github.com/Arduino89/convoy-mesh/releases/tag/experimental-latest); `.github/workflows/experimental-download.yml`: reviewed distribution, archived version and byte verification.
- [Experiment rationale, measured limits and field protocol](docs/pedestrian-exp1.md).
- [Synthetic CSV](docs/pedestrian-exp1-results.csv); regenerate with `ConvoyMeshApp/tool/pedestrian_candidate_probe.dart`.
- `ConvoyMeshApp/test/`, `.github/workflows/android-debug.yml`, `tools/android_smoke.sh`: actual estimator/service and APK/emulator evidence.
- PR #1 continuity at `c3ef471` retains older milestone details; this is the current handoff, not another changelog.

## STABILIZED DECISIONS

Cama authorized public experimental APK distribution with one fixed download link on 2026-10-06. Reuse-first level 4: native GitHub Releases/Actions; no website, account service or updater added. Promote only an explicitly reviewed candidate; versioned archive assets are not overwritten. Keep DRAFT/no merge. The debug signing limitation remains; fixed URLs do not guarantee Android update compatibility.

Walking/hiking only, offline BLE, no road/origin snapping. Uncertainty overlap does not prove identical position; RSSI is not metres. Do not compare clocks across phones. No ledger/GATT/CoC/fusion-library/rendering changes here. Real logs and coordinates stay private.

Previous candidate untouched on `fix/v0.4-stability` / PR #1: **0.7.6+8**, executable `3e056f88ab44a4fbb9989058a9191e2bebc3cba4`, run #105 `34701227901`, SHA-256 `6fd9baa63e41e62259ac8d11db9993b034605625c91be478b3f51ee594fbc3f8`. Automated gates passed, physical hardening pending. Old APK artifact expired; retain copies/installs.

Experiment installs beside it as `com.example.convoy_mesh.pedestrianexp1` / **Convoy Mesh Exp**. Separate permissions/identity/data; only one app active per phone. No uninstall needed. Old certificate unavailable and debug keys not retained: future upgrade compatibility must be verified. Uninstall deletes local data.

## COMPLETED

- `7248589`: shared estimator regressions/probe. Baseline: 122 pass/19 fail; all 107 original tests pass.
- `be04599`: bounded temporal evidence and supported moving acquisition; independent irregular-interval/minority counterexamples included.
- `d0d6818`: service tests and isolated clock; preview/freshness/segments/log lifetime covered.
- `8ab7c06`: isolated version/package, SDK/dependency pins, signature checks and stronger smoke.
- `844e3a9`: short-gap support; recovery metric requires new support, not just an unexpired old anchor.
- Candidate: 147/147 passed locally and in run #120; all 149 pass in run #121 after two real-service regressions were added. Analyzer completed with the same 21 nonfatal findings.
- Independent replay matched all 18 run #120 outing observations without Android lifecycle. The slow synthetic stimulus, not GPS suspension, reproduced the missing trail; no production threshold was lowered.
- `9ca9107`: ordinary GPS-walk smoke with a positive screen-on control, post-sleep diagnostic boundary, strict fresh-trail/source-motion assertions, plus reliable quiet-IMU ordinary-walk and isolated-jump service tests.
- Run #121 built/tested exact source `9ca9107f229af91354116278c9970b39d0a4e81e`; signature/package/version/minSDK 24/arm64 checks and API35 emulator passed. Post-sleep GPS 14 -> 28 and trail 4 -> 18; all 14 new points fresh over 69.01 s / 86.52 m. Resume, preview isolation and diagnostic survival after outing stop passed.
- Reconstructed APK matches CI and emulator SHA-256 `9737bf12b116a4321f0e7a54f9b09b1d0e13ff0c95e682aba3ba0d9b793dba11` / 164,372,655 bytes. Independent signed-content/RSA verification passed. Keep the exact delivered APK; README holds install identity.

## CURRENT WORK

**Isolated telemetry LAB / draft PR #5 — offline ACK correction verified.** Branch `experiment/telemetry-runtime-lab`; exact executed source `d93b3095f78f4924e2cf132d82e4bc041a626f7c`, wrapper `8d6c7c023eb404098d77392ef7ed0504d86572f6`. [Run42310498585 / number16 / attempt1 / job128210433580](https://github.com/Arduino89/convoy-mesh/actions/runs/42310498585/job/128210433580) SUCCESS. CI host202/202 with zero skips; Android lifecycle control8/8 before fixture build/execution. Verbatim baseline Java75b8325 (identical to run15's809caf Java) rejects documented HTTP200 `status: Ok`; candidate accepts it and retains integer1. All33 native classifier / isolated SQLite ACK cases pass:5 accepted remove only selected rows;28 rejected preserve IDs/body bytes/counter; all unrelated tails preserved. Actual host run_cases fail-fast comparison:4 failures before,23/23 after. Permanent blocks now report an allowlisted cause immediately; response audit stores only finite categories.

[Evidence, exact APK identities, reproduction and limits](docs/telemetry-evidence/2026-11-06/ack-response-followup/README.md). Independent source, concrete workflow and runtime receipt reviews passed. Standard-library receipt recalculation needs no Android/network or producer predicates. Both fixture APKs request zero permissions; no sender, project credentials/configuration or old cloud queue were loaded. Three offline barriers, both process stops and radio restoration passed. Host loopback fixtures and runner bootstrap networking are separate. Full sender/InputStream/UTF-8 decoding/TLS/cloud storage were not exercised. Earlier full local runs14/15 remain historical on their prior source; no new full-sender revocation/saturation claim.

**Cloud evidence remains separate and blocked.** Source `809caf200f6232b162fee009fa2a7c2b484d7855`, run42300571195 / number15 / attempt1 / job128176961434: first20 synthetic events received with20 unique UUIDs; HTTP200 confirmation rejected,0ACK and queue100 (20 received/unacknowledged plus80 never attempted). Actual response status/value/body were not retained and remain unknown. Cloud revocation, new consent/new delivery, retry and deduplication NOT_RUN. [Run15 evidence](docs/telemetry-evidence/2026-11-06/run-42300571195/README.md). Prior Android preparation and local runtime gates are documented there and in the [telemetry report](docs/telemetry-minimum-infrastructure.md); do not restart from the old broken emulator.

Previous cloud authorization is closed:500 earlier uncertain rows +200 additional =700 prudential ceiling, **future allowance0**, including old20 retries and the180 unused rows. No new PostHog event ingestion, event readback or deletion in this offline phase. Overall infrastructure privacy, physical phones/battery and GNSS/BLE remain unverified. Original workflow restored byte for byte at `24374ddd4f855a6df01780bfeb92c135704f5ee7` and [independently checked](docs/telemetry-evidence/2026-11-06/ack-response-followup/independent-restoration-review.json); final checkpoint changes documentation only, with skip-ci and no new Android execution. Convoy unchanged, PR5draft, no merge/release/integration/paid service/real users.

## NEXT GATE

Review the offline ACK correction and its independent Android evidence. This closes the documented-format incompatibility gate only. Cloud revocation, new consent/new delivery, retry/deduplication and end-to-end privacy remain unverified; the new full sender was not rerun. Future cloud allowance is zero, including old20 retries, until a separate explicit mandate. Do not silently reuse the previous180 unused rows. Physical phones/battery and GNSS/BLE field work remain separate; no adoption, merge, release or integration authority.

## DO NOT

No merge of PR #4 or #1. No old main/ledger base. Do not present old APK as improved. Do not promise zero drift and zero lag from indistinguishable inputs, metre-level accuracy, lossless HISTORY or guaranteed force-stop survival. Do not invent lines across missing history. Do not touch Cama-Enterprise, Sagre, NUC/Bridge or shared workers.

## OPEN RISKS / DEBT

- Automated screen-off evidence now passes for ordinary injected walking; very slow walking/quiet IMU and real GNSS/BLE/OEM behavior are not certified by it.
- GPS-only 0.3 m/s/accuracy 10 m still misses track movement; synthetic fresh error reaches 24 m.
- Tight curves/returns defeat net/path; coherent drift is observationally ambiguous. Exact cadence invariance is unproven; gain remains per sample.
- Acquisition is heuristic, not calibrated confidence. No physical accuracy/battery benefit measured.
- HISTORY loss/retry, OEM/deep Doze, endurance and process-loss recovery need physical evidence; identity/colour convergence remains separate.
- Original lock was incomplete. New lock matches all 76 versions recoverable from old CI logs; no old APK byte-reproducibility claim.
- Debug signing and analyzer/deprecation debt remain.

## CLEANUP PENDING

No automatic removal of branches/builds. Keep the exact delivered APK; CI retention is finite 90 days. Superseded intermediate CI runs are not candidate identities. No public/private-log duplication.

## LAST CHECKPOINT

6 November 2026: offline ACK run16/attempt1/job128210433580 SUCCESS on exact source `d93b309`;202/202 CI host and33/33 native cases. Independent source/workflow/runtime/restoration reviews passed. Original workflow restored; final receipt checkpoint is documentation only. Cloud run15's20 receipts remain separate and closed, future allowance zero. PR5draft, Convoy unchanged. Application field checkpoint remains README/PR4.

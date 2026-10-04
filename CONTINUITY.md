# Convoy Mesh — continuity

## STATUS

**0.7.7-exp1+9 experimental pedestrian candidate**, [draft PR #4](https://github.com/Arduino89/convoy-mesh/pull/4), `experiment/pedestrian-acquisition-v1`. 147/147 tests passed locally and in CI. [Android run #120](https://github.com/Arduino89/convoy-mesh/actions/runs/37116465888) completed with **build/signature/package checks passed, emulator smoke FAILED**. Physical two-phone evidence pending; APK delivery gate remains blocked. No production or merge approval.

User authorized implementation, branch, commits, draft PR and build on 2026-10-03, replacing the earlier read-only phase. Fix demonstrated acquisition/cadence defects first; preserve provider/5 s request/BLE/HISTORY. Do not restart from main or PR #3.

## CURRENT ARCHITECTURE

Nearby: native BLE without continuous GNSS/FGS. Map preview: location without outing track. Outing: GNSS/track plus native foreground owner. Source freshness, UI time and radio presence remain separate. HISTORY ACK/retry is bounded and never overwrites live position.

Estimator: static consensus plus majority-supported moving acquisition; first/reacquired points do not add trail. At most 26 time bins within 25 s. Motion evidence prefers 20 s, using the existing 25 s window when fewer than five observations are present. No provisional publication. IMU alone cannot authorize large unsupported innovations. Classifier unchanged; service test clock defaults to DateTime.now in production.

Diagnostics remain independent of outing lifetime, local and capped at four minutes. Process-loss outing reconstruction is still absent.

## CANONICAL SOURCES

- [README](README.md): current install/artifact checkpoint.
- [Experiment rationale, measured limits and field protocol](docs/pedestrian-exp1.md).
- [Synthetic CSV](docs/pedestrian-exp1-results.csv); regenerate with `ConvoyMeshApp/tool/pedestrian_candidate_probe.dart`.
- `ConvoyMeshApp/test/`, `.github/workflows/android-debug.yml`, `tools/android_smoke.sh`: actual estimator/service and APK/emulator evidence.
- PR #1 continuity at `c3ef471` retains older milestone details; this is the current handoff, not another changelog.

## STABILIZED DECISIONS

Walking/hiking only, offline BLE, no road/origin snapping. Uncertainty overlap does not prove identical position; RSSI is not metres. Do not compare clocks across phones. No ledger/GATT/CoC/fusion-library/rendering changes here. Real logs and coordinates stay private.

Previous candidate untouched on `fix/v0.4-stability` / PR #1: **0.7.6+8**, executable `3e056f88ab44a4fbb9989058a9191e2bebc3cba4`, run #105 `34701227901`, SHA-256 `6fd9baa63e41e62259ac8d11db9993b034605625c91be478b3f51ee594fbc3f8`. Automated gates passed, physical hardening pending. Old APK artifact expired; retain copies/installs.

Experiment installs beside it as `com.example.convoy_mesh.pedestrianexp1` / **Convoy Mesh Exp**. Separate permissions/identity/data; only one app active per phone. No uninstall needed. Old certificate unavailable and debug keys not retained: future upgrade compatibility must be verified. Uninstall deletes local data.

## COMPLETED

- `7248589`: shared estimator regressions/probe. Baseline: 122 pass/19 fail; all 107 original tests pass.
- `be04599`: bounded temporal evidence and supported moving acquisition; independent irregular-interval/minority counterexamples included.
- `d0d6818`: service tests and isolated clock; preview/freshness/segments/log lifetime covered.
- `8ab7c06`: isolated version/package, SDK/dependency pins, signature checks and stronger smoke.
- `844e3a9`: short-gap support; recovery metric requires new support, not just an unexpired old anchor.
- Candidate: 147/147 pass locally and in run #120; analyzer completed under existing nonfatal policy.
- Run #120 built source `d330ec111e8558fa4df804817bfe36a38f980618`, verified APK signature, package/version, minSDK 24 and arm64/x86_64. Compiled artifact identity is in README. Emulator/field gates did not pass.

## CURRENT WORK

Triage run #120 job `111184795867`: `Local trail did not grow while screen was off (0 -> 0)`. Diagnostics show GPS fixes continued (8 -> 22), Outing/foreground owner remained active, and the classifier reported `moving=false`, `motion_reliable=true` during injected GPS movement. This identifies the failed assertion, not yet whether the cause is a motion-filter defect or inconsistent emulator inputs. Recover evidence from artifacts `emulator-diagnostics` / `convoy-build-provenance` on that run. Compiled APK exists; it is not a passed delivery candidate. Runs #118/#119 were cancelled by later branch pushes; no experiment run was active at the 2026-10-04 recovery check. Original Work execution/error telemetry is unavailable here.

## NEXT GATE

Resolve the exact run #120 screen-off/trail failure from its diagnostics and reproduce it through the real estimator/service, then pass the Android gate without weakening its trail assertion. Only after that: deliver a hash-verified APK and use the three existing Cama/Francesca sessions in `docs/pedestrian-exp1.md`. Physical targets remain Mi9Lite/API29 and M2101K6G/API33; field evidence precedes accuracy claims or merge.

## DO NOT

No merge of PR #4 or #1. No old main/ledger base. Do not present old APK as improved. Do not promise zero drift and zero lag from indistinguishable inputs, metre-level accuracy, lossless HISTORY or guaranteed force-stop survival. Do not invent lines across missing history. Do not touch Cama-Enterprise, Sagre, NUC/Bridge or shared workers.

## OPEN RISKS / DEBT

- Blocking Android evidence: run #120 screen-off GPS movement produced no trail; diagnosis pending. Do not infer GPS suspension or treat APK creation as smoke success.
- GPS-only 0.3 m/s/accuracy 10 m still misses track movement; synthetic fresh error reaches 24 m.
- Tight curves/returns defeat net/path; coherent drift is observationally ambiguous. Exact cadence invariance is unproven; gain remains per sample.
- Acquisition is heuristic, not calibrated confidence. No physical accuracy/battery benefit measured.
- HISTORY loss/retry, OEM/deep Doze, endurance and process-loss recovery need physical evidence; identity/colour convergence remains separate.
- Original lock was incomplete. New lock matches all 76 versions recoverable from old CI logs; no old APK byte-reproducibility claim.
- Debug signing and analyzer/deprecation debt remain.

## CLEANUP PENDING

No automatic removal of branches/builds. Keep the exact delivered APK; CI retention is finite 90 days. Superseded intermediate CI runs are not candidate identities. No public/private-log duplication.

## LAST CHECKPOINT

2026-10-04: recovered PR #4, its six implementation/documentation commits, exact build provenance and emulator diagnostics after Cama reported the Work chat stopped updating. Run #120 finished 2026-10-03 10:36:07 UTC (12:36:07 Europe/Rome): compilation/tests/identity passed, screen-off trail assertion failed. This recovery changes documentation only; executable source remains `d330ec11`. No merge, rebuild or field validation. Chat/UI interruption cause is unverified; the concrete pending gate is recorded above.

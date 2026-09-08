# Convoy Mesh — continuity

## STATUS

Reliability candidate **0.7.0+7: automated gate passed; two-physical-phone validation pending**. Not a production release. The delivered APK is bound to immutable source head `0032e4e0389ecf19d7cd38c019393434f828f511`, PR merge checkout `30f20d3c9ee341d55bff9bf7b319d99df9eca66d`, and completed workflow run #59 (`34215831566`). This checkpoint update is documentation only, not a newly built app. Recheck PR #1 and compare any newer revision against the validated source; every executable/test/build change needs its own gate.

## CURRENT ARCHITECTURE

Flutter UI and one outing engine; manufacturer-filtered native Android BLE reception; one Dart POS/NAME/PING scheduler; a stateful pedestrian position estimator fed by source-timestamped GPS observations; an explicit foreground-service lifetime with bounded owner pulses/wake lock; opt-in persistent JSONL diagnostics.

## CANONICAL SOURCES

- `README.md`: product scope, limitations and build commands.
- PR #1 and its actual source revision: operative change set.
- `.github/workflows/android-debug.yml`: automated gate and evidence artifacts.
- `ConvoyMeshApp/lib/ble/ble_tx_scheduler.dart`: transmission scheduling contract.
- `ConvoyMeshApp/lib/location/pedestrian_position_estimator.dart`: runtime estimator.
- `ConvoyMeshApp/test/reliability_regression_test.dart` and `test/gps_motion_evidence_regression_test.dart` under the same app: synthetic reliability requirements.
- `ConvoyMeshApp/test/diagnostic_persistence_test.dart`: persistence requirements.
- `tools/android_smoke.sh`: Android install/lifecycle checks and explicit exclusions.

## STABILIZED DECISIONS

Walking/hiking groups only. No vehicles or road snapping. Offline local position exchange is distinct from a downloaded basemap. Signal strength is not measured distance. Hardware capability detection is not implemented ranging. Never equate a live heartbeat with a fresh position.

Writes are confined to `Arduino89/convoy-mesh`. No NUC jobs, Sagre edits, Host Bridge requests, shared-worker changes or writes to `Arduino89/Cama-Enterprise`. Private field logs stay outside this public repository. No paid service or deployment is authorized by this checkpoint.

## COMPLETED

- Baseline: `b29e17de118f49b9359cc1e3af4e89bbc0653999`; integrated candidate includes scheduler, source-age handling, native scan/runtime, persistent diagnostics and uncertainty UI.
- September stationary failure reproduced before repair: test-only commit `e778ddef51cd333b19bf8443d888dacba37ceb35`, run #57 (`34214510036`): 69 passed / 7 failed. A single anomalous endpoint could dominate net/path motion evidence even after the stationary display rejected it. Positive walking controls passed.
- Local repair `d7332077584a7df0bc172550f1e41a78602e1515`: require distributed material progress before GPS overrides still/unknown IMU. No existing test assertion weakened. Principle 11: level 6 localized repair, no dependency/authority changes. Run #58 passed all 76 tests and built an APK; its emulator startup assertion was premature while Flutter was loading.
- Harness repair `0032e4e0389ecf19d7cd38c019393434f828f511`: bounded wait for the actual foreground owner, no relaunch or ignored process death, and explicit screen-off assertion.
- **Final run #59 (`34215831566`): build SUCCESS; emulator SUCCESS.** All 76 tests passed. Analysis passed with 5 warnings and 15 infos (nonblocking, retained in log). APK compiled and was installed on Android API 35 x86_64. Same PID 2476 and the same foreground service survived >70 seconds with `mWakefulness=Asleep`, then resumed without detected app exception. Final screenshot shows the real Radar UI, not a splash/error screen.
- APK artifact `10051830422`: 164346831 bytes after extraction. SHA-256 `8bff221765f592a4dafa6d3a7b9ed4246e92f411a72270eaedc5e4783aee098b`. CI checksum, downloaded APK checksum and emulator checksum match. Provenance artifact `10051831015`; test log `10051751583`; analyzer log `10051759649`; emulator diagnostics `10051959432`. Artifacts currently expire 2026-09-22; verify availability before reuse.
- PR comment `5583631351` records repair and verification. Isolation notice remains comment `5574400151`.

## CURRENT WORK

Reuse branch `fix/v0.4-stability` and PR #1; no parallel implementation. The automated blocker is resolved. Candidate APK is ready for physical-device testing, not certified mountain performance. Do not relaunch old failed runs or substitute older APKs.

## NEXT GATE

Validate **the same candidate APK on both Android phones**: stationary outdoor convergence, start walking, Home/screen lock and return, then compare the two short diagnostic logs. Export existing logs before uninstalling any previous build with an incompatible debug signature. Keep field logs private. Record actual observations before further tuning or merge.

## DO NOT

Do not merge PR #1 before physical-device validation. Do not claim perfect GPS, guaranteed background survival, active UWB/RTT, authenticated groups, full multi-hop mesh or downloaded offline maps. Do not silently change another project's jobs or force-push over a concurrent writer. Check HEAD and blob SHA before every existing-file update. Do not describe the documentation-only checkpoint commit as the source of the built APK.

## OPEN RISKS / DEBT

- The emulator gate is bounded installation/runtime evidence, not real BLE reception, GNSS accuracy, OEM power policies or battery endurance.
- Debug signing is not a production release policy; the delivered candidate's signing certificate differs from the previously supplied 0.6 APK.
- Five analyzer warnings and 15 infos remain; no independent reviewer sign-off.
- Legacy GPS helper remains for compatibility/tests; the new estimator is the runtime path.
- Relative POS source-age metadata is not complete clock synchronization; legacy packets have unknown source age.
- Authenticated membership, general multi-hop relaying and downloaded basemaps remain outside this stabilization.
- Diagnostic retention/deletion UX needs a later privacy/storage pass.

## CLEANUP PENDING

Classify unused legacy screens/helpers after integrated validation; do not delete wholesale during reliability work. Remove the temporary branch only after an approved merge. Keep history in Git instead of duplicating app variants.

## LAST CHECKPOINT

2026-09-08: failure reproduced, motion-evidence predicate repaired, 76 tests passed, exact APK built and Android install/screen-off/resume gate passed. Documentation-only closeout follows the immutable validated source above. Next gate is physical-device validation; no NUC/Sagre changes were made.

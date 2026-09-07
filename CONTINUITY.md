# Convoy Mesh — continuity

## STATUS

Reliability candidate 0.7.0 under verification. **Not a release and not yet validated on two physical phones.** Recheck PR #1, its current HEAD and the exact workflow run; do not use a previous green build as evidence for this candidate.

## CURRENT ARCHITECTURE

Flutter UI and one outing engine; manufacturer-filtered native Android BLE reception; one Dart POS/NAME/PING scheduler; a stateful pedestrian position estimator fed by source-timestamped GPS observations; an explicit foreground-service lifetime with bounded owner pulses/wake lock; opt-in persistent JSONL diagnostics.

## CANONICAL SOURCES

- `README.md`: product scope, current limitations and build commands.
- PR #1 and its actual source revision: operative change set.
- `.github/workflows/android-debug.yml`: automated gate and evidence artifacts.
- `ConvoyMeshApp/lib/ble/ble_tx_scheduler.dart`: transmission scheduling contract.
- `ConvoyMeshApp/lib/location/pedestrian_position_estimator.dart`: current position estimator.
- `ConvoyMeshApp/test/reliability_regression_test.dart`: synthetic reliability requirements.
- `ConvoyMeshApp/test/diagnostic_persistence_test.dart`: persistence requirements.
- `tools/android_smoke.sh`: Android install/lifecycle checks and explicit exclusions.

## STABILIZED DECISIONS

Walking/hiking groups only. No vehicles or road snapping. Offline local position exchange is distinct from a downloaded basemap. Signal strength is not measured distance. Hardware capability detection is not implemented ranging. Never equate a live heartbeat with a fresh position.

Writes are confined to `Arduino89/convoy-mesh`. No NUC jobs, Sagre edits, Host Bridge requests, shared-worker changes or writes to `Arduino89/Cama-Enterprise`. Private field logs stay outside this public repository. No paid service or deployment is authorized by this checkpoint.

## COMPLETED BASELINE

The previous candidate was at `b29e17de118f49b9359cc1e3af4e89bbc0653999`; its earlier tests do not validate the new candidate. An isolation notice was posted in PR #1 (comment 5574400151). Build provenance/source capture was introduced in commit `7a85e1a11234ffb012bd3094eba12d26147e8c4b`. New scheduler, estimator and filtered-scan helper commits followed; inspect current source for the integrated state.

## CURRENT WORK

Reuse branch `fix/v0.4-stability` and PR #1; do not create a parallel implementation. Integrated changes address NAME starvation, source-fix freshness, stationary convergence, filtered reception, outing start/stop, diagnostic persistence and explicit uncertainty UI. Regression tests and an emulator lifecycle script are part of the candidate. Their existence is not proof that they have passed.

## NEXT GATE

Finish **automated verification of the exact current candidate**: retrieve completed workflow status plus test/analyzer/native-build logs; diagnose any failure without weakening tests or substituting a previous APK. Check the emulator result separately from an infrastructure failure. Only after the software gate is established, identify and checksum a matching APK and propose the short two-device field validation. Keep unverified behavior explicitly pending.

## DO NOT

Do not merge PR #1 before physical-device validation. Do not claim perfect GPS, guaranteed background survival, active UWB/RTT, authenticated groups, full multi-hop mesh or downloaded offline maps. Do not silently change another project's jobs or force-push over a concurrent writer. Check HEAD and blob SHA before every existing-file update.

## OPEN RISKS / DEBT

- OEM power management, battery cost and BLE/GNSS behavior need physical-device evidence.
- Debug signing is not a production signing/release policy.
- Existing legacy GPS helper remains for compatibility/tests; the new estimator is the intended runtime path.
- Relative POS source-age metadata is not complete clock synchronization; legacy packets have unknown source age.
- Production security/group membership and general multi-hop relaying are not implemented by this stabilization.
- Local diagnostic retention and deletion UX need a later privacy/storage pass.
- No independent reviewer sign-off has been obtained.

## CLEANUP PENDING

Classify unused legacy screens/helpers after integrated validation; do not delete them wholesale during reliability work. Remove the temporary branch only after an approved merge. Keep history in Git instead of duplicating app variants.

## LAST CHECKPOINT

2026-09-07: isolated candidate implementation and automated gate prepared. Verification results must be recorded from the actual final run, not inferred from build configuration or this document.

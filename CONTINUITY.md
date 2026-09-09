# Convoy Mesh — continuity

## STATUS

Reliability candidate **0.7.0 field-fix: automated gate passed; repeat two-phone validation pending**. Not a production release. The APK to test is bound to immutable executable/test source head `87064e4e53872df81bb157c3deabd7da2b5f02cd` and completed workflow run #63 (`34327979730`). This continuity commit is documentation-only; do not treat its newer SHA as the APK source.

## CURRENT ARCHITECTURE

Flutter UI and one outing engine; Android native manufacturer-filtered BLE reception; one Dart POS/NAME/PING scheduler; stateful pedestrian GPS estimator with consensus, static anchoring, conservative origin loop-closure and source timestamps; explicit foreground-service lifetime; persistent opt-in JSONL diagnostics.

## CANONICAL SOURCES

- `README.md`: product scope, limitations and build commands.
- PR #1 and current branch: operative change set.
- `.github/workflows/android-debug.yml`: automated gate/evidence.
- `ConvoyMeshApp/lib/ble/ble_tx_scheduler.dart`: transmission scheduling.
- `ConvoyMeshApp/android/app/src/main/kotlin/com/example/convoy_mesh/ConvoyBleScanner.kt`: native receive filter.
- `ConvoyMeshApp/lib/location/pedestrian_position_estimator.dart`: runtime position estimator.
- `ConvoyMeshApp/test/reliability_regression_test.dart`, `gps_motion_evidence_regression_test.dart`, `field_log_regression_test.dart`: reliability regressions.
- `tools/android_smoke.sh`: bounded Android install/screen-off/resume gate.

## STABILIZED DECISIONS

Walking/hiking groups only. No vehicle assumptions/road snapping. Live radio presence and fresh coordinates are separate facts. RSSI is proximity/signal quality, not a metre ruler. Private field logs stay outside the public repository. No NUC/Sagre/Host Bridge/shared-worker writes from Convoy work.

## COMPLETED

- Previous integrated candidate `0032e4e0389ecf19d7cd38c019393434f828f511` passed 76 tests and emulator lifecycle gate in run #59.
- **Real two-phone test 2026-09-09** used that exact build on `Fra` (Mi 9 Lite, Android API 29) and `cama` (M2101K6G, API 33). Both logs show BLE ready, scan subscription present and advertising active. Fra requested/succeeded 40/40 TX (34 POS, 6 NAME); cama 41/41 (35 POS, 6 NAME). Yet both had `scan_events_total=0`, `rx_valid_total=0`, no peer ever created. This isolates the failure to receive-side filtered discovery, not pairing/TTL/parser/TX scheduling.
- The same logs provide positive background evidence: after the first `paused` lifecycle event Fra continued with 29 successful BLE TX and 36 GPS fixes; cama continued with 21 TX and 23 GPS fixes. This does not certify all OEM policies, but the outing owner was not simply dying on Home/screen state.
- GPS static behaviour was materially improved. In cama's short out-and-return trace, raw GNSS ended ~14 m from its own initial fix while the displayed estimate ended ~16 m away; the filter was not the main source of that residual. This motivated conservative loop closure rather than looser smoothing.
- Receive fix `7e60a170ac571ddf73c3c6ff24424000320a9117`: native scan now filters by manufacturer company ID only (plus defensive swapped-ID compatibility), then lets the codec validate `CM`; raw AD parsing is a compatibility fallback. It removes the unsafe assumption that `CM` must be the first bytes exposed to Android's `ScanFilter` while preserving a real filter for screen-off scanning.
- GPS loop-closure fix `0ad793b5414e824684a11b1961151c245b0336ef`: after an accepted excursion, two consecutive approaching fixes must overlap the origin uncertainty region before the estimator reconciles to the outing start. It cannot close a loop from stationary drift alone and does not claim improved absolute GNSS accuracy.
- Synthetic field regressions `87064e4e53872df81bb157c3deabd7da2b5f02cd` cover biased GNSS return, high-quality nearby pass without false snap, and stationary drift without fake loop.
- **Run #63 (`34327979730`) passed:** 79/79 Flutter tests, analyze completed (20 existing/nonblocking issues retained), APK build/fingerprint/upload successful, Android emulator install + >70 s screen-off owner + resume smoke successful.
- Run #63 APK artifact `10094660748`; extracted APK size `164351059` bytes; SHA-256 `211f0b450f712e267c553420dc2aa8e53e96251dece1172474546b4bd38f1d51` (CI checksum equals downloaded APK checksum). Artifacts expire 2026-09-23 unless retained elsewhere.

## CURRENT WORK

No further executable changes after validated source `87064e4e53872df81bb157c3deabd7da2b5f02cd`. Candidate is ready for the next short physical test. Reuse branch `fix/v0.4-stability` and PR #1; no parallel implementation.

## NEXT GATE

Install the **same run #63 APK** on both phones and record a 2–4 minute test. First verify peer discovery (`scan_events_total > 0`, `rx_packet`/peer appears). Then make one short out-and-return walk and leave a few fixes at the endpoint to observe `loop_closed_origin` when evidence supports it. Also include one Home/screen-lock interval. Upload both JSONL files; keep them private.

## DO NOT

Do not merge PR #1 before this repeat physical validation. Do not claim metre-level GNSS, guaranteed force-stop survival, active UWB/RTT, authenticated group membership or general multi-hop mesh. Do not weaken the native filter back to permanent unfiltered background scanning merely to make discovery work. Do not touch NUC/Sagre/Host Bridge from this project.

## OPEN RISKS / DEBT

- Manufacturer-ID-only filtered reception is CI/build validated but requires the two real phones to prove the real-device regression is fixed.
- Loop closure improves route consistency only when uncertainty/evidence supports a return; it cannot know ground truth when GNSS is biased.
- OEM power/battery behaviour still needs longer physical evidence.
- Debug signing is not a production signing policy.
- Analyzer retains 5 warnings + 15 infos, mostly legacy/style/deprecations; cleanup is separate from this field gate.
- Authenticated membership, general multi-hop relaying, downloaded basemaps and diagnostic retention/deletion UX remain later work.

## CLEANUP PENDING

After physical validation, classify legacy GPS/screens/helpers and clean analyzer/deprecation debt separately. Do not delete wholesale during reliability validation. Remove temporary branch only after an approved merge.

## LAST CHECKPOINT

2026-09-09: two real logs isolated zero-event receive regression despite successful TX; filter fixed without reverting to unfiltered background scan; conservative origin loop closure added; 79 tests + build + Android screen-off/resume gate passed on exact source `87064e4e53872df81bb157c3deabd7da2b5f02cd`. Next gate is repeat two-phone test with the matching APK.

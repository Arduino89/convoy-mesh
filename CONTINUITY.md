# Convoy Mesh — continuity

## STATUS

Reliability candidate **0.7.2 Nearby + catch-up: automated gate passed; two-phone catch-up validation pending**. Not a production release. The APK to test is bound to source head `465ee5c43f69b681faa7ea9d9c9895264c31343b` and workflow run #79 (`34376335782`). Do not merge PR #1 before the physical catch-up/GPS gate.

## CURRENT ARCHITECTURE

Flutter UI with two runtime modes. **Nearby** starts automatically while the app is open: Android-native BLE scan + manufacturer advertising for presence/name, without continuous GPS or foreground service. **Outing** adds GPS/trail and the foreground service for screen-off operation. BLE TX and RX are both Android-native. A bounded HISTORY packet queue can replay the sender's own missing trail after reconnection; recovered peer points are timestamped separately from live position and rendered dashed.

## CANONICAL SOURCES

- `README.md`: product scope and limitations.
- PR #1 / `fix/v0.4-stability`: operative changes.
- `.github/workflows/android-debug.yml`: automated gate and evidence.
- `ConvoyMeshApp/lib/services/convoy_mesh_service.dart`: Nearby/Outing modes, peer state and catch-up scheduling.
- `ConvoyMeshApp/lib/ble/convoy_ble_codec.dart`: POS/NAME/PING/HISTORY wire format.
- `ConvoyMeshApp/android/app/src/main/kotlin/com/example/convoy_mesh/ConvoyBleAdvertiser.kt` and `ConvoyBleScanner.kt`: native radio path.
- `ConvoyMeshApp/lib/location/pedestrian_position_estimator.dart`: GPS estimator / conservative loop closure.
- `ConvoyMeshApp/test/trail_catchup_test.dart` and other tests under `ConvoyMeshApp/test/`.
- `tools/android_smoke.sh`: Nearby→Outing→screen-off→resume gate.

## STABILIZED DECISIONS

Walking/hiking groups only. No vehicle assumptions or road snapping. Live radio presence and fresh coordinates are separate facts. RSSI is signal/proximity, not metres. Recovered HISTORY never replaces a peer's current position. Live POS/NAME/PING has priority over catch-up. Private field logs stay outside the public repo. Convoy work does not touch NUC/Sagre/Host Bridge/shared-worker state.

## COMPLETED

- 0.7.1 native-BLE source `9bf625a82767c0f65aea46ee72eac87bf018d2d1`, run #68: software/emulator gate passed after replacing plugin TX with Android-native advertising.
- **Physical two-phone result 2026-09-09:** user confirmed Mi 9 Lite/API29 and M2101K6G/API33 now see each other with the 0.7.1 native-BLE APK. This closes the symmetric zero-RX blocker seen in the earlier plugin-TX builds.
- GPS static drift is materially improved in current testing; an intermittent peer status that can look like Francesca's GPS is unavailable remains under observation. UI wording now distinguishes a present peer with non-recent/no usable position from a proven GPS failure.
- Nearby/Outing split implemented: opening the app performs lightweight discovery; `Avvia uscita` enables GPS + FGS; ending the outing returns to Nearby while the app remains open.
- HISTORY catch-up implemented for known-peer reconnection gaps: up to 28 down-sampled own-track points per reconnection, bounded to 90-minute retention and transmitted only in scheduler idle slots. Receiver inserts recovered points chronologically without changing the live fix. Map renders recovered links as explicit dashed fragments compatible with `flutter_map 6.2.1`.
- Catch-up regressions verify wire budget, recovered/live separation, chronological insertion, and bounded first/last-preserving selection.
- **Run #79 (`34376335782`) passed completely:** 85/85 Flutter tests, analyze PASS, APK build/fingerprint/upload PASS, Android emulator smoke PASS. Smoke verifies app opens in Nearby without FGS, real UI `Avvia uscita` promotes to FGS, same outing owner survives >70 s verified screen-off and resumes without detected fatal exception.
- Run #79 APK artifact `10114133945`; extracted APK size `164339383` bytes; SHA-256 `9f2ad7c9658d777007a9f6cc003fe1dc9e608a94d56f0e266386aba39451f7d6`. Local downloaded checksum matches CI checksum. Artifacts expire 2026-09-23 unless retained elsewhere.

## CURRENT WORK

No executable changes after the run #79 source head. Candidate APK is ready for physical validation on the same two Android phones. Continue on the existing branch/PR only.

## NEXT GATE

Install the **same 0.7.2 / run #79 APK** on both phones. First confirm that opening both apps, without starting an outing, shows each other in Nearby. Then start an outing on both, establish live position, separate beyond BLE range for >30 seconds while one or both walk, reconnect within 90 minutes and observe that current position updates first and missing route points arrive as dashed HISTORY. Repeat directions if practical. Record short JSONL logs, especially any period where Francesca is shown with a non-recent/unusable GPS position.

## DO NOT

Do not merge PR #1 before physical catch-up and GPS-status validation. Do not claim HISTORY transfer works on real radio until observed. Do not claim metre-level GNSS, guaranteed force-stop survival, active UWB/RTT, authenticated membership or general multi-hop mesh. Do not touch NUC/Sagre/Host Bridge from this project.

## OPEN RISKS / DEBT

- Catch-up is bounded advertisement replay, not a reliable acknowledged bulk-transfer protocol; real reconnection loss/reordering must be measured before deciding whether acknowledgements/GATT are necessary.
- Francesca's occasional stale/no-usable-position state needs logs before changing GPS thresholds.
- OEM battery behaviour needs longer physical evidence.
- `flutter_ble_peripheral` remains installed but unused at runtime; remove after current physical gate.
- Debug signing is not a production signing policy. Analyzer/deprecation cleanup, authenticated groups, general multi-hop, downloaded basemaps and diagnostic retention UX remain later work.

## CLEANUP PENDING

After physical validation, remove unused advertising-plugin dependency and classify legacy GPS/screens/helpers in a separate hygiene pass. Remove the temporary branch only after an approved merge.

## LAST CHECKPOINT

2026-09-09: native BLE discovery confirmed on the real phone pair; Nearby automatic discovery and bounded dashed HISTORY catch-up added; run #79 passed 85 tests, analyze, APK build and Nearby→Outing→screen-off/resume smoke on exact head `465ee5c43f69b681faa7ea9d9c9895264c31343b`. Next gate is two-phone physical catch-up plus Francesca GPS-status observation.
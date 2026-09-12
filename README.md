# Convoy Mesh

Android/Flutter app for **walking and hiking groups in low-connectivity areas**. Bluetooth exchanges nearby participants' information; GPS supplies geographic coordinates. This is not vehicle navigation or a replacement for normal mountain-safety precautions.

## Current work

The `fix/v0.4-stability` branch and PR #1 contain the **0.7.6 hardening candidate**. This is an internal milestone label: the exact test candidate is identified by source HEAD + APK checksum, not by the `pubspec.yaml` version string alone.

Current validated executable source: `5eba40d3e9e81f3be2e85592bd6f4bcb3caad25d`, workflow run #100 (`34697873143`), APK SHA-256 `d3456d97d8c369739b750290bfeb7bfd6b15adb3f5d2ccbe40f4170b0caa9276`. The automated gate passed; real two-phone validation is still required before merge.

Read `CONTINUITY.md` before continuing work. This is not a certified release: emulator checks and physical-device evidence are separate gates.

### Reliability changes being validated

- One scheduler owns POS, NAME and PING. Repeated name requests cannot occupy every position slot.
- Presence and GPS freshness are independent: receiving a heartbeat must not refresh an old coordinate.
- GPS measurements use the provider's timestamp. UI events have a separate timestamp.
- POS advertising now has a bounded native lifetime based on remaining freshness; receive-side age also includes Android scan-delivery delay, so an old repeated payload cannot become artificially young for a new receiver.
- HISTORY has application-level ACK/retry. An unseen out-of-order HISTORY sequence is stored instead of being rejected by live-state sequencing; duplicates are idempotent and can be re-ACKed after ACK loss.
- HISTORY and ACK queues have explicit global bounds and share idle radio slots while live POS/NAME/PING retain priority.
- The pedestrian estimator waits for a short spatial consensus, rejects isolated outliers, and permits a better stationary cluster to correct a poor initial anchor without drawing a false walking trail.
- Automatic rewriting of the live position to the trip origin is disabled. GNSS uncertainty compatibility is not treated as proof that the user is exactly back at the start.
- The motion classifier detects sustained low-intensity movement, requires sustained quiet to return to still, and invalidates partially satisfied timing windows after a sensor-delivery gap.
- Android reception uses a manufacturer-data `ScanFilter`, not an unrestricted screen-off scan.
- Nearby clean-install startup requests the location permission required by the current manifest/scan contract, but does not start continuous GPS or a foreground service.
- Map GPS preview and Outing track ownership are separated. Starting an outing resets its trail; clearing a local trail or regenerating identity invalidates relevant pending transfer state.
- A single cached Flutter engine and a foreground service own an active outing. The notification includes an explicit stop action. A bounded wake lock is renewed only while the outing owner responds.
- Diagnostic JSONL is opt-in, four minutes maximum, buffered to private local files about once a second. A diagnostic session can span Nearby → Outing → Nearby and is not implicitly ended by `Termina uscita`.
- Radar and map distinguish reported GPS uncertainty, measurement age and Bluetooth signal strength. RSSI is not presented as measured metres.

## What the candidate does not claim

- No guarantee of metre-level GPS accuracy or of a specific Bluetooth range.
- No live position when the sender has no usable fix or the devices cannot communicate.
- HISTORY is more reliable than the previous best-effort replay, but it is not yet a full missing-range reconciliation protocol and is not claimed lossless until tested on real phones.
- A supported UWB/Wi-Fi RTT feature is **not** active ranging; only hardware capability detection is present.
- Nearby advertising/scanning is **not yet a general multi-hop mesh**. Do not infer relay coverage from the app's name.
- No persistent outing/session reconstruction after process loss is claimed. Force-stop is deliberately not bypassed.
- The optional OpenStreetMap background uses the network. Switching it off leaves coordinates, markers and tracks, not a downloaded offline map package. Do not bulk-download public OSM tiles.
- A foreground service and passing emulator test do not certify OEM battery policies, deep Doze radio behaviour or battery endurance on real phones.
- No GATT history transport is currently required by the design. Advertising + ACK is tested first; richer GATT transfer is a later option only if field evidence justifies it.
- Debug APKs are test candidates; durable production signing, group authentication and release hardening remain separate work.

## App use

Launch the app and grant the requested location/Bluetooth permissions. Nearby discovery runs while the app is foregrounded without continuous GPS. The outing status and **Avvia uscita / Termina uscita** control are visible above the tabs.

The **Test log** tab owns diagnostic recording explicitly. A recording may begin in Nearby, continue through an Outing and remain active after `Termina uscita`; end it from the Test log page when the physical test is complete.

The Test log page shows the build identifier and persistent-storage state. It can export the last file after a restart. Logs contain coordinates; they are not uploaded automatically and must not be committed to this public repository.

## Validation

```sh
cd ConvoyMeshApp
flutter pub get
flutter test --coverage --reporter expanded
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter build apk --debug --dart-define=BUILD_COMMIT=local-review
```

Run #100 passed **107 Flutter tests**, analyzer execution, exact APK build/fingerprint/upload and the Android API 35 emulator smoke. The clean-install smoke requested and granted location permission, kept Nearby free of a foreground runtime, started diagnostics before the outing, promoted the outing to the foreground service, survived verified screen-off in the same process, recorded GPS fixes `3 → 18` and local trail additions `0 → 1` while asleep, resumed, and returned to Nearby without implicitly ending the diagnostic session.

Analyzer warnings/infos are currently reported but not blocking; run #100 reports 5 warnings + 15 infos. Do not describe this as warning-free analysis. CI archives the exact source revision, resolved dependency lock, Flutter version, test output, analysis output and APK checksum. Its emulator step is not a real two-phone radio or mountain-GNSS test.

Private logs can be replayed locally through the production GPS estimator:

```sh
dart run tool/replay_diagnostics.dart /private/path/test.jsonl
```

Older logs may lack source timestamps or estimator state. The replay reports those assumptions. Without independent ground truth, smoother output is not proof of greater absolute accuracy.

## Main components

- `ConvoyMeshApp/lib/services/convoy_mesh_service.dart`: BLE scheduling, receive decisions, peer state and acknowledged HISTORY replay.
- `ConvoyMeshApp/lib/ble/convoy_ble_codec.dart`: POS/NAME/PING/HISTORY/HISTORY_ACK wire format.
- `ConvoyMeshApp/lib/location/pedestrian_position_estimator.dart`: bounded stateful pedestrian estimator.
- `ConvoyMeshApp/lib/location/pedestrian_motion_classifier.dart`: strong/slow/quiet motion hysteresis with stale-sensor handling.
- `ConvoyMeshApp/lib/services/location_fusion_service.dart`: sensor/provider lifecycle, preview/outing separation and measurement freshness.
- `ConvoyMeshApp/android/app/src/main/kotlin/com/example/convoy_mesh/`: foreground ownership, filtered scanning, native advertising TTL and platform bridge.
- `ConvoyMeshApp/lib/services/diagnostic_recorder.dart`: local diagnostic persistence and export.
- `ConvoyMeshApp/test/`: unit, receive-path, estimator, persistence and UI regressions.
- `tools/android_smoke.sh`: bounded synthetic clean-install/Nearby/Outing/screen-off/resume test.

Keep fixes local to this repository. Development of other projects, shared NUC services or company-wide workflows is not part of this change.

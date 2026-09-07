# Convoy Mesh

Android/Flutter app for **walking and hiking groups in low-connectivity areas**. Bluetooth exchanges nearby participants' information; GPS supplies geographic coordinates. This is not vehicle navigation or a replacement for normal mountain-safety precautions.

## Current work

The `fix/v0.4-stability` branch and PR #1 contain the **0.7.0 reliability candidate**. Read `CONTINUITY.md` before continuing work. It is not a certified release: automated checks and physical-device validation are different gates. Do not merge the candidate before the latter.

### Reliability changes being validated

- One scheduler owns POS, NAME and PING. Repeated name requests cannot occupy every position slot.
- Presence and GPS freshness are independent: receiving a heartbeat must not refresh an old coordinate.
- GPS measurements use the provider's timestamp. UI events have a separate timestamp.
- The pedestrian estimator waits for a short spatial consensus, rejects isolated outliers, and permits a better stationary cluster to correct a poor initial anchor without drawing a false walking trail.
- Sensor availability includes sample age. Missing or stale accelerometer data does not mean that the user is certainly stationary.
- Android reception uses a manufacturer-data `ScanFilter`, not an unrestricted screen-off scan.
- A single cached Flutter engine and a foreground service own an active outing. The notification includes an explicit stop action. A bounded wake lock is renewed only while the outing owner responds.
- Diagnostic JSONL is opt-in, four minutes maximum, buffered to private local files about once a second. A process interruption can still lose the unflushed suffix; recovered files are labelled accordingly.
- Radar and map distinguish reported GPS uncertainty, measurement age and Bluetooth signal strength. RSSI is not presented as measured metres.

## What the candidate does not claim

- No guarantee of metre-level GPS accuracy or of a specific Bluetooth range.
- No live position when the sender has no usable fix or the devices cannot communicate.
- A supported UWB/Wi-Fi RTT feature is **not** active ranging; only hardware capability detection is present.
- Nearby advertising/scanning is **not yet a general multi-hop mesh**. Do not infer relay coverage from the app's name.
- The optional OpenStreetMap background uses the network. Switching it off leaves coordinates, markers and tracks, not a downloaded offline map package. Do not bulk-download public OSM tiles.
- A foreground service and passing emulator test do not certify OEM battery policies, deep sleep, radio performance or battery endurance on real phones. Force-stop is deliberately not bypassed.
- Debug APKs are test candidates; durable production signing, group authentication and release hardening remain separate work.

## App use

Launch the app and grant the requested location/Bluetooth permissions. The outing status and **Avvia uscita / Termina uscita** control are visible above the tabs. Ending a diagnostic recording does not itself end the outing. Ending the outing stops its sensing and radio work and closes an active diagnostic recording.

The **Test log** tab shows the build identifier and persistent-storage state. It can export the last file after a restart. Logs contain coordinates; they are not uploaded automatically and must not be committed to this public repository.

## Validation

```sh
cd ConvoyMeshApp
flutter pub get
flutter test --coverage --reporter expanded
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter build apk --debug --dart-define=BUILD_COMMIT=local-review
```

Analyzer warnings/infos are currently reported but not blocking. Do not describe this as warning-free analysis. CI archives the exact source revision, resolved dependency lock, Flutter version, test output, analysis output and APK checksum. Its Android emulator step installs the same APK and checks the foreground owner across screen-off and resume; this is not a real two-phone radio test.

Private logs can be replayed locally through the production GPS estimator:

```sh
dart run tool/replay_diagnostics.dart /private/path/test.jsonl
```

Older logs may lack source timestamps or estimator state. The replay reports those assumptions. Without independent ground truth, smoother output is not proof of greater absolute accuracy.

## Main components

- `ConvoyMeshApp/lib/services/convoy_mesh_service.dart`: one BLE transmission scheduler, receive decisions and peer state.
- `ConvoyMeshApp/lib/location/pedestrian_position_estimator.dart`: bounded stateful pedestrian estimator.
- `ConvoyMeshApp/lib/services/location_fusion_service.dart`: sensor/provider lifecycle and measurement freshness.
- `ConvoyMeshApp/android/app/src/main/kotlin/com/example/convoy_mesh/`: foreground ownership, filtered scanning and platform bridge.
- `ConvoyMeshApp/lib/services/diagnostic_recorder.dart`: local diagnostic persistence and export.
- `ConvoyMeshApp/test/`: unit, receive-path, estimator, persistence and UI regressions.
- `tools/android_smoke.sh`: bounded synthetic Android lifecycle test.

Keep fixes local to this repository. Development of other projects, shared NUC services or company-wide workflows is not part of this change.

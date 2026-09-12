# Convoy Mesh

Android/Flutter app for **walking and hiking groups in low-connectivity areas**. Bluetooth exchanges nearby participants' information; GPS supplies geographic coordinates. This is not vehicle navigation or a replacement for normal mountain-safety precautions.

## Current work

The `fix/v0.4-stability` branch and PR #1 contain the **0.7.6+8 hardening candidate**.

Validated executable identity for the next physical gate:

- source `3e056f88ab44a4fbb9989058a9191e2bebc3cba4`
- workflow run #105 `34701227901`
- APK SHA-256 `6fd9baa63e41e62259ac8d11db9993b034605625c91be478b3f51ee594fbc3f8`
- Android package `0.7.6+8` (App info: `0.7.6`)

The automated gate passed completely; real two-phone validation is still required before merge. Later documentation commits do not replace the executable identity above.

Earlier milestones accidentally reused `0.7.0+7`, which allowed one physical phone to remain on old build `93dfb23…` while the other ran `5eba40…` without the public Android version exposing the mismatch. This was caught before field testing from the different Test-log UI/build hashes. The controlled field gate therefore requires **clean install on both phones** and explicit build verification before walking.

Read `CONTINUITY.md` before continuing work. This is not a certified release: emulator checks and physical-device evidence are separate gates.

### Reliability changes being validated

- POS/NAME/PING share one scheduler; name traffic cannot starve position traffic.
- Presence and GPS freshness are independent; heartbeat reception does not refresh an old coordinate.
- POS native advertising lifetime is bounded by remaining source-fix freshness, and receive age includes native Android scan-delivery delay.
- HISTORY uses application ACK/retry, accepts unseen out-of-order recovered packets, re-ACKs idempotent duplicates, and has bounded HISTORY/ACK queues with live traffic priority.
- The pedestrian estimator keeps spatial-consensus/outlier protection but no longer snaps automatically to the trip origin merely because uncertainty regions overlap.
- Slow-motion classification requires sustained evidence; quiet must persist to return to still; sensor-delivery gaps reset partially satisfied timing windows.
- Clean-install Nearby requests the location permission required by the current scan contract without starting continuous GPS/FGS.
- Map preview and Outing track ownership are separated; reset/identity operations invalidate relevant pending transfer state.
- Diagnostic recording may span Nearby → Outing → Nearby and is not implicitly ended by `Termina uscita`.
- Radar/map distinguish GPS uncertainty, source age and Bluetooth signal; RSSI is not metres.

## What the candidate does not claim

No guaranteed metre-level GPS or Bluetooth range, no lossless HISTORY claim, no receiver-declared missing-range protocol yet, no persistent outing reconstruction after process loss, no active UWB/RTT ranging, no general multi-hop mesh, no authenticated group protocol, no downloaded offline basemap package and no production signing policy.

GATT is not part of the current recovery design. Advertising + ACK is tested first; GATT/session/point/range redesign is considered only if physical evidence justifies it.

## App use / physical preflight

For the controlled field gate, uninstall Convoy from both phones and install the exact run #105 APK. Before walking, both phones must show:

- Android App info: **0.7.6**
- Test log build prefix: **`3e056f88`**
- no recovered old `File pronto` card after clean install
- in Nearby, without starting Outing, enabled **`Avvia test • max 4 min`** once startup is complete
- mutual Nearby discovery

If any item differs, stop before collecting field data.

The **Test log** recording may start in Nearby, continue through Outing and remain active after `Termina uscita`; end/export it explicitly after the test. Logs contain coordinates and are not uploaded automatically.

## Validation

```sh
cd ConvoyMeshApp
flutter pub get
flutter test --coverage --reporter expanded
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter build apk --debug --dart-define=BUILD_COMMIT=local-review
```

Run #105 passed **107 Flutter tests**, analyzer execution, exact APK build/fingerprint/upload and Android API 35 clean-install/screen-off/resume smoke. Emulator success is not a real two-phone radio or mountain-GNSS test.

Private logs can be replayed locally:

```sh
dart run tool/replay_diagnostics.dart /private/path/test.jsonl
```

Older logs may lack source timestamps or estimator state. Without independent ground truth, smoother output is not proof of greater absolute accuracy.

## Main components

- `ConvoyMeshApp/lib/services/convoy_mesh_service.dart`: BLE scheduling, receive decisions, peer state, POS freshness and acknowledged HISTORY replay.
- `ConvoyMeshApp/lib/ble/convoy_ble_codec.dart`: POS/NAME/PING/HISTORY/HISTORY_ACK wire format.
- `ConvoyMeshApp/lib/location/pedestrian_position_estimator.dart`: bounded stateful pedestrian estimator.
- `ConvoyMeshApp/lib/location/pedestrian_motion_classifier.dart`: strong/slow/quiet motion hysteresis with stale-sensor handling.
- `ConvoyMeshApp/lib/services/location_fusion_service.dart`: sensor/provider lifecycle, preview/outing separation and measurement freshness.
- `ConvoyMeshApp/android/app/src/main/kotlin/com/example/convoy_mesh/`: foreground ownership, filtered scanning, native advertising TTL and platform bridge.
- `ConvoyMeshApp/lib/services/diagnostic_recorder.dart`: local diagnostic persistence, version/build stamp and export.
- `ConvoyMeshApp/test/`: unit, receive-path, estimator, persistence and UI regressions.
- `tools/android_smoke.sh`: bounded synthetic clean-install/Nearby/Outing/screen-off/resume gate.

Keep fixes local to this repository. Development of other projects, shared NUC services or company-wide workflows is not part of this change.

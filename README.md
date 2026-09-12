# Convoy Mesh

Android/Flutter app for **walking and hiking groups in low-connectivity areas**. Bluetooth exchanges nearby participants' information; GPS supplies geographic coordinates. This is not vehicle navigation or a replacement for normal mountain-safety precautions.

## Current work

The `fix/v0.4-stability` branch and PR #1 contain the **0.7.6+8 hardening candidate**.

Current validated executable source: `3e056f88ab44a4fbb9989058a9191e2bebc3cba4`, workflow run #105 (`34701227901`), APK SHA-256 `6fd9baa63e41e62259ac8d11db9993b034605625c91be478b3f51ee594fbc3f8`. The automated gate passed completely; real two-phone validation is still required before merge. Later documentation commits do not replace this executable identity.

Unlike earlier milestones that accidentally reused `0.7.0+7`, this candidate has an explicit higher Android package version. Android App info should show **0.7.6**, and diagnostic JSONL records `0.7.6+8`. The in-app diagnostic page also displays the exact `BUILD_COMMIT`; verify the same build on both phones before any field test.

The old/new build mismatch was caught before physical testing: one phone still showed build `93dfb23…` while the other showed `5eba40…`. Therefore the controlled field gate requires a **clean install on both phones**, not an in-place upgrade. Do not begin the walking/separation test unless both phones show version `0.7.6`, build prefix `3e056f88`, matching Nearby/Test-log behaviour and no recovered old `File pronto` state.

Read `CONTINUITY.md` before continuing work. This is not a certified release: emulator checks and physical-device evidence are separate gates.

### Reliability changes being validated

- One scheduler owns POS, NAME and PING. Repeated name requests cannot occupy every position slot.
- Presence and GPS freshness are independent: receiving a heartbeat must not refresh an old coordinate.
- GPS measurements use the provider's timestamp. UI events have a separate timestamp.
- POS advertising has a bounded native lifetime based on remaining freshness; receive-side age also includes Android scan-delivery delay, so an old repeated payload cannot become artificially young for a new receiver.
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

The Test log page shows the exact build identifier and persistent-storage state. It can export the last file after a restart. A `File pronto` card can legitimately appear after an in-place upgrade because previous diagnostic JSONL files are retained; use clean installs for the controlled two-phone gate. Logs contain coordinates; they are not uploaded automatically and must not be committed to this public repository.

## Validation

```sh
cd ConvoyMeshApp
flutter pub get
flutter test --coverage --reporter expanded
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter build apk --debug --dart-define=BUILD_COMMIT=local-review
```

Run #105 passed **107 Flutter tests**, analyzer execution, exact APK build/fingerprint/upload and the Android API 35 emulator smoke. The smoke uses a clean install, requests location from Nearby, keeps Nearby free of a foreground runtime, starts diagnostics before the outing, promotes the outing to the foreground service, survives verified screen-off in the same process, records GPS fixes and local trail growth while asleep, resumes, and returns to Nearby without implicitly ending the diagnostic session.

Analyzer warnings/infos are reported but not blocking under the current policy. Do not describe this as warning-free analysis. CI archives the exact source revision, resolved dependency lock, Flutter version, test output, analysis output and APK checksum. Its emulator step is not a real two-phone radio or mountain-GNSS test.

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

# Convoy Mesh

Android/Flutter for **walking and hiking groups in low-connectivity areas**: offline BLE exchanges and GNSS coordinates. No vehicle assumptions or road snapping. Not a replacement for mountain-safety precautions.

## Current work

**0.7.7-exp1+9**, [draft PR #4](https://github.com/Arduino89/convoy-mesh/pull/4), branch `experiment/pedestrian-acquisition-v1`. Based on PR #1 application line `c3ef471754d7e1a4b3cf2558e5c2fadbb9d4f0a7`, not old main or PR #3 ledger. **No merge.**

**149/149 CI tests pass**. The unchanged application baseline plus the same 34 shared regressions passes 122 and fails 19; all 107 original tests pass. [Android run #121](https://github.com/Arduino89/convoy-mesh/actions/runs/37198612027), attempt 1, passed both build and API35 emulator jobs, including signature/package checks and fresh trail growth while asleep. The exact APK bytes and signature have also been independently verified. Ready for the requested experimental two-phone trial; physical validation remains pending.

Read [CONTINUITY](CONTINUITY.md), [implementation, measured limits and field protocol](docs/pedestrian-exp1.md), and [synthetic comparison CSV](docs/pedestrian-exp1-results.csv).

### Verified APK checkpoint — 4 October 2026

- Executable source: `9ca9107f229af91354116278c9970b39d0a4e81e`; run #121 / `37198612027`, attempt 1, **success**. Later documentation commits do not change the APK's build stamp.
- Delivered filename: `Convoy-Mesh-0.7.7-exp1-9-9ca9107.apk`; **164,372,655 bytes**. SHA-256 verified across all transport parts, reconstructed APK and emulator input: `9737bf12b116a4321f0e7a54f9b09b1d0e13ff0c95e682aba3ba0d9b793dba11`. Original artifact `convoy-mesh-debug-apk` / `11302051883`.
- Verified APK v2 debug signature; certificate SHA-256 `cb1d666bfbeadb5ae3cf4b191470505f2f2fa5f985a8bda5bd7ad3fe95efb118`. Package/version/label correct; minSDK **24**, arm64-v8a / armeabi-v7a / x86_64 included. Independent local verification also recomputed signed content and checked the RSA signature.
- Screen-on control: four trail points. After verified Android sleep: **14 new GPS fixes and 14 fresh trail points**, source span **69.01 s**, raw net movement **86.52 m**, mean **1.25 m/s**. Counts increased 14 -> 28 GPS and 4 -> 18 trail; wakefulness was `Asleep` at both boundaries. Resume and independent Test log after outing stop passed.
- Run #120's zero-trail failure was reproduced without Android lifecycle: its ~0.44 m/s GPS-only stimulus with quiet IMU stayed below the existing motion gate. Corrected only the smoke stimulus and added two service regressions; production thresholds unchanged. Very slow walking remains a measured limitation.
- Next: the three physical sessions in the existing protocol. No merge, production release or real-device accuracy claim.

### Previous candidate preserved

The `fix/v0.4-stability` branch / PR #1 remains unchanged. Previous executable **0.7.6+8**: source `3e056f88ab44a4fbb9989058a9191e2bebc3cba4`, run #105 `34701227901`, APK SHA-256 `6fd9baa63e41e62259ac8d11db9993b034605625c91be478b3f51ee594fbc3f8`. Automated gates passed; physical hardening remained pending. Its APK artifact has expired: retain existing copies/installs. It is not newly downloadable or signature-comparable here.

### Experimental changes

- Acquire a supported moving endpoint without requiring a stationary cluster; no provisional coordinates sent to peers or recorded.
- Retain at most 26 source-time bins over 25 s; select motion evidence by time, preserving bounded short-gap support.
- Require GPS corroboration for large innovations even when IMU says moving.
- Test the actual service's preview/outing ownership, freshness and track segments with an injected test clock.

Provider, requested **5-second** updates, IMU classifier, BLE/HISTORY and renderer are unchanged. Slow GPS-only walking, tight curves and coherent drift retain measured limitations. No new fusion library, ledger, GATT/CoC or cosmetic animation.

## Install and retain rollback

Install as **Convoy Mesh Exp**, package `com.example.convoy_mesh.pedestrianexp1`, version **0.7.7-exp1+9**. This is a separate app, not an in-place update: previous app/data remain installed. Grant permissions and set names again; use only one Convoy app at a time per phone.

Do not uninstall the previous app merely to try this candidate. To return, end the experimental outing and reopen the previous app. Uninstalling deletes local data: export wanted logs first. Debug signing keys are not retained between CI builds, so future in-place updates cannot be assumed compatible. Keep the exact delivered APK and compare version/build stamps on both phones.

Test log can start in Nearby, span an Outing and remain active after **Termina uscita**. End/export it explicitly; each recording is capped at four minutes. Logs contain coordinates and remain private. The three sessions in the protocol each fit that limit.

## Architecture and nonclaims

Nearby uses native Android BLE without continuous GNSS/FGS. Map preview does not own outing history. Outing adds GNSS/trail and the foreground owner. Radio presence and source-coordinate freshness are separate; heartbeat does not refresh old coordinates. POS TTL respects remaining fix freshness. Bounded HISTORY ACK/retry never overwrites live peer position.

No guaranteed metre-level positioning, radio range, lossless HISTORY, receiver-declared missing ranges, process-loss outing reconstruction, guaranteed force-stop survival, authenticated groups, general multi-hop mesh, downloaded offline basemap or production signing policy.

## Validation

Use Flutter **3.47.4**, matching the previous CI SDK:

```sh
cd ConvoyMeshApp
flutter pub get --enforce-lockfile
flutter test --no-pub --coverage --reporter expanded
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
dart run tool/pedestrian_candidate_probe.dart candidate
ORG_GRADLE_PROJECT_convoyExperimental=true flutter build apk --debug --no-pub --dart-define=BUILD_COMMIT=local-review
```

CI verifies exact source, tests/analyzer, APK signature/package/version/minSDK/ABI and API35 preview/screen-off/resume/Test-log behavior. APK transport parts are downloads of the same bytes, not additional candidates. Emulator checks do not prove physical GNSS/BLE, OEM Doze or battery endurance. Analyzer retains the existing nonfatal warning/info policy.

Private logs can be replayed locally with `dart run tool/replay_diagnostics.dart /private/path/test.jsonl`; never commit them. Smoother output alone does not prove absolute accuracy.

## Main components

- `ConvoyMeshApp/lib/location/pedestrian_position_estimator.dart`: bounded estimator.
- `ConvoyMeshApp/lib/services/location_fusion_service.dart`: provider lifecycle, preview/outing and track writer.
- `ConvoyMeshApp/lib/location/pedestrian_motion_classifier.dart`: unchanged motion evidence.
- `ConvoyMeshApp/lib/services/convoy_mesh_service.dart`, `lib/ble/convoy_ble_codec.dart`: unchanged radio protocol.
- `ConvoyMeshApp/android/app/src/main/kotlin/com/example/convoy_mesh/`: native ownership/BLE.
- `ConvoyMeshApp/lib/services/diagnostic_recorder.dart`: local logs and version/build stamp.
- `ConvoyMeshApp/test/`, `tools/android_smoke.sh`, `.github/workflows/android-debug.yml`: automated evidence.

Work only in `Arduino89/convoy-mesh`. Do not touch Cama-Enterprise, Sagre, NUC/Bridge or shared-worker state.

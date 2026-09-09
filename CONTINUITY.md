# Convoy Mesh — continuity

## STATUS

Reliability candidate **0.7.1 native-BLE: automated gate passed; repeat two-phone validation pending**. Not a production release. The APK to test is bound to executable source head `9bf625a82767c0f65aea46ee72eac87bf018d2d1` and workflow run #68 (`34331609526`). This continuity commit is documentation-only and is not the APK source.

## CURRENT ARCHITECTURE

Flutter UI and one outing engine; **Android-native manufacturer advertising and Android-native manufacturer-filtered scanning**; one Dart POS/NAME/PING scheduler; stateful pedestrian GPS estimator with consensus, static anchoring, conservative origin loop-closure and source timestamps; explicit foreground-service lifetime; persistent opt-in JSONL diagnostics.

## CANONICAL SOURCES

- `README.md`: product scope, limitations and build commands.
- PR #1/current branch: operative changes.
- `.github/workflows/android-debug.yml`: automated gate/evidence.
- `ConvoyMeshApp/android/app/src/main/kotlin/com/example/convoy_mesh/ConvoyBleAdvertiser.kt`: native TX contract.
- `ConvoyMeshApp/android/app/src/main/kotlin/com/example/convoy_mesh/ConvoyBleScanner.kt`: native RX filter.
- `ConvoyMeshApp/lib/ble/native_ble_advertiser.dart`: Dart→native TX bridge.
- `ConvoyMeshApp/lib/ble/ble_tx_scheduler.dart`: POS/NAME/PING scheduling.
- `ConvoyMeshApp/lib/location/pedestrian_position_estimator.dart`: runtime GPS estimator.
- reliability tests under `ConvoyMeshApp/test/` and `tools/android_smoke.sh`.

## STABILIZED DECISIONS

Walking/hiking groups only. No vehicle assumptions/road snapping. Live radio presence and fresh coordinates are separate facts. RSSI is signal/proximity, not a metre ruler. Private field logs stay outside the public repo. Convoy work must not touch NUC/Sagre/Host Bridge/shared-worker state.

## COMPLETED

- Candidate `0032e4e...` established GPS/background baseline and passed its software gate.
- First real two-phone test on Mi 9 Lite/API29 and M2101K6G/API33: both phones transmitted successfully but both reported `scan_events_total=0`; GPS/background continued after pause. This isolated the main failure below peer/parser logic.
- Field-fix `87064e4e...` relaxed the native RX filter to company-id matching and added conservative GPS origin loop-closure; run #63 passed 79 tests/build/emulator.
- **Second real two-phone test on the run #63 build** repeated the failure on both directions. During the controlled ~1-minute log both devices reported BLE ready, `scanning=true`, `advertising=true`, manual scan restart, 10 requested TX and 10 plugin-success TX each, yet `scan_events_total=0`, `rx_valid_total=0`, and no peers. This rules out a Mi-9-only issue and makes plugin-advertising success insufficient evidence that compatible radio frames were emitted.
- Native TX bridge `4c866dc62791cee5d5dd4c42ef83e6972f3c1c95`, Android advertiser `1b1b79f3acef7e53862ffacb48df2de4f49ad84b`, method-channel wiring `7331805207aa4201eb818acf078fa16e57de667e`, and service integration `9bf625a82767c0f65aea46ee72eac87bf018d2d1` remove `flutter_ble_peripheral` from the runtime TX path. TX and RX now use the same Android manufacturer contract: company ID `0x0C0A` plus Convoy payload.
- **Run #68 (`34331609526`) passed:** Flutter tests PASS, analyze PASS, APK build/fingerprint/upload PASS, Android install + >70 s screen-off owner + resume smoke PASS.
- Run #68 APK artifact `10096095919`; extracted APK size `164328227` bytes; SHA-256 `db53ad322d033cfffc2e4299500f991aaea2fec0374a435b6e39e4199337e9d7`. CI provenance checksum matches the downloaded APK. Artifacts expire 2026-09-23 unless retained elsewhere.

## CURRENT WORK

No further executable changes after validated source `9bf625a82767c0f65aea46ee72eac87bf018d2d1`. Candidate is ready for the shortest possible physical RX test. Reuse `fix/v0.4-stability` and PR #1; no parallel implementation.

## NEXT GATE

Install the **same run #68 APK** on both phones. Start outing and Test log on both, keep phones close for 30–60 seconds, press `Invia nome` once if desired, then stop/export. The primary success criterion is simply `scan_events_total > 0` / `rx_packet` / peer visible on each device. If RX works, only then repeat walking/return/background testing. Upload both distinct JSONL files privately.

## DO NOT

Do not merge PR #1 before real two-phone RX succeeds. Do not claim metre-level GNSS, guaranteed force-stop survival, active UWB/RTT, authenticated membership or general multi-hop mesh. Do not revert to permanent unfiltered background scanning merely to create visible peers. Do not touch NUC/Sagre/Host Bridge from this project.

## OPEN RISKS / DEBT

- Native TX/RX now share the same Android API contract, but only the real two phones can prove radio discovery is fixed.
- `flutter_ble_peripheral` remains an installed but unused dependency for now; remove it only after native TX is validated on the phones.
- Loop closure improves route consistency when evidence supports a return; it cannot determine ground truth under biased GNSS.
- OEM battery behaviour needs longer physical evidence.
- Debug signing is not a production signing policy.
- Analyzer/deprecation cleanup, authenticated groups, multi-hop relaying, downloaded basemaps and diagnostic retention UX are later work.

## CLEANUP PENDING

After physical BLE validation, remove the unused BLE advertising plugin/dependency and classify legacy GPS/screens/helpers in a separate hygiene pass. Remove the temporary branch only after an approved merge.

## LAST CHECKPOINT

2026-09-09: second real pair of logs confirmed symmetric zero-event RX despite successful plugin TX; advertising moved fully native; run #68 passed automated test/build/emulator gate on exact source `9bf625a82767c0f65aea46ee72eac87bf018d2d1`. Next gate is a 30–60 second two-phone RX-only test with the matching APK.

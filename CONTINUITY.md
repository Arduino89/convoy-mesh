# Convoy Mesh — continuity

## STATUS

Reliability candidate **0.7.3 GPS indicator / foreground locate: automated gate passed; physical GPS-indicator validation pending**. Not a production release. The APK is bound to executable source head `93dfb23e921b0da23f0b29788f353e8fb28c8d8a` and workflow run #85 (`34601810676`). Do not merge PR #1 before the remaining physical GPS/catch-up gate.

## CURRENT ARCHITECTURE

Flutter UI with two runtime modes. **Nearby** starts automatically while the app is open: Android-native BLE scan + manufacturer advertising for presence/name, without continuous GPS or foreground service. **Outing** adds GPS/trail and the foreground service for screen-off operation. BLE TX and RX are both Android-native. A bounded HISTORY packet queue replays the sender's own missing trail after reconnection; recovered peer points are timestamped separately from live position and rendered dashed. The map location control can now start a foreground-only GPS acquisition without starting an outing.

## CANONICAL SOURCES

- `README.md`: product scope and limitations.
- PR #1 / `fix/v0.4-stability`: operative changes.
- `.github/workflows/android-debug.yml`: automated gate and evidence.
- `ConvoyMeshApp/lib/services/convoy_mesh_service.dart`: Nearby/Outing modes, peer state and catch-up scheduling.
- `ConvoyMeshApp/lib/ble/convoy_ble_codec.dart`: POS/NAME/PING/HISTORY wire format.
- `ConvoyMeshApp/android/app/src/main/kotlin/com/example/convoy_mesh/ConvoyBleAdvertiser.kt` and `ConvoyBleScanner.kt`: native radio path.
- `ConvoyMeshApp/lib/location/pedestrian_position_estimator.dart`: GPS estimator / conservative loop closure.
- `ConvoyMeshApp/lib/location/gps_visual_state.dart`: map lock/search/quality visual state.
- `ConvoyMeshApp/test/trail_catchup_test.dart`, `gps_visual_state_test.dart` and other tests under `ConvoyMeshApp/test/`.
- `tools/android_smoke.sh`: Nearby→Outing→screen-off→resume gate.

## STABILIZED DECISIONS

Walking/hiking groups only. No vehicle assumptions or road snapping. Live radio presence and fresh coordinates are separate facts. RSSI is signal/proximity, not metres. Recovered HISTORY never replaces a peer's current position. Live POS/NAME/PING has priority over catch-up. Private field logs stay outside the public repo. Convoy work does not touch NUC/Sagre/Host Bridge/shared-worker state.

## COMPLETED

- 0.7.1 native-BLE source `9bf625a82767c0f65aea46ee72eac87bf018d2d1`, run #68: software/emulator gate passed after replacing plugin TX with Android-native advertising.
- **Physical two-phone result 2026-09-09:** Mi 9 Lite/API29 and M2101K6G/API33 see each other with native BLE. This closed the symmetric zero-RX blocker.
- 0.7.2 source `465ee5c43f69b681faa7ea9d9c9895264c31343b`, run #79: Nearby automatic discovery + bounded HISTORY catch-up passed 85 tests/analyze/build/smoke.
- **Physical 0.7.2 result 2026-09-11:** Nearby discovery works immediately on both phones without pressing `Avvia uscita`. During a real out-and-return separation the catch-up mechanism also worked: cama queued/sent 13 historical points after a ~99 s peer gap and Francesca accepted 7 unique HISTORY points. Therefore HISTORY is proven on real radio but is currently best-effort, not 1:1 reliable. The selected 13 points represented ~111 m of filtered path; the 7 received points represented ~76 m, with the first received history point ~34 m after the first queued one. The map now refuses to draw a recovered link across a temporal gap >30 s, so missing HISTORY remains a gap rather than a fabricated straight line.
- **Francesca GPS evidence from the same test:** her phone produced 50 GPS fixes over ~199 s; worst fix-to-fix gap was ~6.3 s. This argues against the phone GPS actually stopping during that session. Intermittent peer “non aggiornata” is therefore tracked as radio/POS freshness until contrary evidence appears.
- cama's displayed GPS uncertainty during the same test was roughly 7–25 m (median ~12.4 m), consistent with the several-metre road offset visible in the screenshot; no road snapping is introduced because Convoy is hiking/off-road first.
- Map GPS control now actively acquires location even in Nearby mode. Visual contract: red steady = not acquired/not active; red slow pulse = acquiring; green steady = recent stable fix; green pulse = recent but uncertain fix, with faster pulse as quality worsens. Foreground-only acquisition is stopped when the app leaves foreground and its preview observations are reset before a real outing starts.
- Five pure regressions cover GPS visual state transitions and pulse-speed ordering.
- **Run #85 (`34601810676`) passed completely:** 90 Flutter tests, analyze PASS, APK build/fingerprint/upload PASS, Android emulator smoke PASS. The exact APK source head is `93dfb23e921b0da23f0b29788f353e8fb28c8d8a`.
- Run #85 APK size `164356815` bytes; SHA-256 `5a18ed8e1a00ccf0343b81e1a5337bca6a60032d72fc97725cbdd24087a47bee`. Downloaded checksum matches CI provenance.

## CURRENT WORK

No executable changes after run #85 head. Candidate is ready for a short physical check of the new location control. HISTORY real-radio loss is measured and remains the next reliability improvement after this UI/foreground-location check.

## NEXT GATE

On one or both real phones, open the app without starting an outing, open Mappa and tap the location target. Confirm: steady red before acquisition, slow red pulse while acquiring, green when a recent fix exists, and return to non-active/red after leaving the foreground without an outing. If the fix is weak, confirm the green pulse accelerates as quality degrades. A full BLE separation test is not required for this gate; native BLE/Nearby/catch-up have already been observed physically. Preserve JSONL only if the indicator contradicts the underlying fix state.

After that, harden HISTORY delivery based on the measured 13→7 loss. Prefer a short post-reconnect settling interval and bounded replay/redundancy while maintaining live POS priority; do not hide packet loss by drawing straight lines over missing history.

## DO NOT

Do not merge PR #1 before physical GPS-indicator/catch-up follow-up. Do not claim HISTORY is lossless. Do not claim metre-level GNSS, guaranteed force-stop survival, active UWB/RTT, authenticated membership or general multi-hop mesh. Do not touch NUC/Sagre/Host Bridge from this project.

## OPEN RISKS / DEBT

- HISTORY transfer is proven but incomplete on real radio (7/13 unique points accepted in the measured reconnection). It needs bounded redundancy or an acknowledged transfer mechanism if replay remains lossy.
- Several-metre GNSS offset remains physically plausible at the measured 7–25 m uncertainty; mountain logs are still valuable for estimator tuning.
- Peer stale-position display can arise from radio/POS freshness even when local GPS continues normally; keep facts separate.
- OEM battery behaviour needs longer physical evidence.
- `flutter_ble_peripheral` remains installed but unused at runtime; remove after current physical gates.
- Debug signing is not a production signing policy. Analyzer/deprecation cleanup, authenticated groups, general multi-hop, downloaded basemaps and diagnostic retention UX remain later work.

## CLEANUP PENDING

After physical validation, remove unused advertising-plugin dependency and classify legacy GPS/screens/helpers in a separate hygiene pass. Remove the temporary branch only after an approved merge.

## LAST CHECKPOINT

2026-09-11: real 0.7.2 test proved automatic Nearby + HISTORY catch-up, while quantifying HISTORY loss (13 queued / 7 accepted) and showing Francesca GPS remained continuously active. 0.7.3 adds active foreground-only map location acquisition, requested red/green reliability indication, and honest gaps for missing recovered points. Run #85 passed 90 tests, analyze, APK build and Android smoke on exact head `93dfb23e921b0da23f0b29788f353e8fb28c8d8a`.
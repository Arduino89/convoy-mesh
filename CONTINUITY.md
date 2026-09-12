# Convoy Mesh — continuity

## STATUS

Reliability candidate **0.7.6 hardening: automated gate passed; physical two-phone hardening validation pending**. Not a production release.

Exact validated executable source: `5eba40d3e9e81f3be2e85592bd6f4bcb3caad25d`.
Workflow run #100: `34697873143`.
APK SHA-256: `d3456d97d8c369739b750290bfeb7bfd6b15adb3f5d2ccbe40f4170b0caa9276`.
APK size: `164362891` bytes.

`0.7.6` is the current hardening milestone label; use HEAD + checksum as the candidate identity because the package version string alone is not sufficient. Do not merge PR #1 before the physical gate below.

## CURRENT ARCHITECTURE

Flutter UI with two runtime modes.

**Nearby** starts automatically while the app is foregrounded: Android-native BLE scan + manufacturer advertising for presence/name, without continuous GPS or foreground service. On a clean install it requests the location permission required by the current Android scan contract because Convoy does not declare `neverForLocation`; granting it in Nearby does not start continuous GPS.

**Outing** adds GPS/trail and the foreground service for screen-off operation. BLE TX and RX are Android-native. POS advertising has a native timeout derived from remaining fix freshness; receive-side age includes native scan-delivery delay.

HISTORY replay uses stable wire sequence IDs across retries plus peer-targeted `HISTORY_ACK`. An unseen HISTORY packet may be accepted out of order; deduplication is based on stored-history identity rather than live-state sequence ordering. Duplicate stored HISTORY may be re-ACKed. HISTORY and ACK queues are globally bounded and share idle radio slots while POS/NAME/PING retain priority.

The map location control can start foreground-only GPS preview without starting an outing. Preview does not own outing history. Starting a real outing resets its local track. Clearing the local trail or regenerating identity clears relevant queued transfer state.

The pedestrian motion classifier has strong-motion, sustained slow-motion and sustained-quiet evidence, and resets partially satisfied timing windows after a sensor-delivery gap. The estimator no longer rewrites a live GNSS position to the trip origin merely because uncertainty regions overlap.

Diagnostic recording is independent from outing lifetime: one Test log can span Nearby → Outing → Nearby and remains active after `Termina uscita` until explicitly ended or its bounded lifetime expires.

## CANONICAL SOURCES

- `README.md`: product scope, limitations and current verified candidate.
- PR #1 / `fix/v0.4-stability`: operative changes and field checkpoints.
- `.github/workflows/android-debug.yml`: automated gate and evidence.
- `ConvoyMeshApp/lib/services/convoy_mesh_service.dart`: Nearby/Outing modes, peer state, POS freshness and HISTORY/ACK scheduling.
- `ConvoyMeshApp/lib/ble/convoy_ble_codec.dart`: POS/NAME/PING/HISTORY/HISTORY_ACK wire format.
- `ConvoyMeshApp/android/app/src/main/kotlin/com/example/convoy_mesh/ConvoyBleAdvertiser.kt` and `ConvoyBleScanner.kt`: native radio path, advertising timeout and scan timing evidence.
- `ConvoyMeshApp/lib/location/pedestrian_position_estimator.dart`: bounded GPS estimator; no automatic origin snap.
- `ConvoyMeshApp/lib/location/pedestrian_motion_classifier.dart`: strong/slow/quiet hysteresis and stale-sensor handling.
- `ConvoyMeshApp/lib/services/location_fusion_service.dart`: provider/sensor lifecycle and preview/outing track ownership.
- `ConvoyMeshApp/lib/location/gps_visual_state.dart`: map lock/search/quality visual state.
- `ConvoyMeshApp/test/trail_catchup_test.dart`, `reliability_contract_test.dart`, `pedestrian_motion_classifier_test.dart`, `gps_visual_state_test.dart` and other tests under `ConvoyMeshApp/test/`.
- `tools/android_smoke.sh`: clean install → Nearby → diagnostic → Outing → screen-off walking → resume → Nearby gate.

## STABILIZED DECISIONS

Walking/hiking groups only. No vehicle assumptions or road snapping. Live radio presence and fresh coordinates are separate facts. RSSI is signal/proximity, not metres. Recovered HISTORY never replaces a peer's current position. Live POS/NAME/PING has priority over catch-up. Private field logs stay outside the public repo. Convoy work does not touch NUC/Sagre/Host Bridge/shared-worker state.

Do not treat GNSS uncertainty overlap as proof of identical location. Do not compare monotonic clocks across phones. Do not claim an ACK means radio reception only: current ACK is emitted after a usable HISTORY point is represented locally. Do not replace advertising with GATT without field evidence that the bounded advertising+ACK design is insufficient.

## COMPLETED

- 0.7.1 native-BLE source `9bf625a82767c0f65aea46ee72eac87bf018d2d1`, run #68: software/emulator gate passed after replacing plugin TX with Android-native advertising.
- **Physical two-phone result 2026-09-09:** Mi 9 Lite/API29 and M2101K6G/API33 see each other with native BLE. This closed the symmetric zero-RX blocker.
- 0.7.2 source `465ee5c43f69b681faa7ea9d9c9895264c31343b`, run #79: Nearby automatic discovery + bounded HISTORY catch-up passed 85 tests/analyze/build/smoke.
- **Physical 0.7.2 result 2026-09-11:** Nearby discovery works immediately on both phones without pressing `Avvia uscita`. During a real out-and-return separation, Cama queued/sent 13 historical points after a ~99 s peer gap and Francesca accepted 7 unique HISTORY points. HISTORY was therefore proven on real radio but incomplete. The map refuses to draw a recovered link across a temporal gap >30 s, so missing HISTORY remains a gap rather than a fabricated straight line.
- **Francesca GPS evidence from the same test:** 50 GPS fixes over ~199 s; worst fix-to-fix gap ~6.3 s. Intermittent peer “non aggiornata” is therefore tracked separately from the local GPS stream.
- Cama's displayed GPS uncertainty during the same test was roughly 7–25 m (median ~12.4 m). No road snapping is introduced because Convoy is hiking/off-road first.
- 0.7.3 map GPS control added foreground-only acquisition and the red/green quality indicator. Run #85 (`34601810676`) passed 90 tests/analyze/build/smoke on source `93dfb23e921b0da23f0b29788f353e8fb28c8d8a`.
- **2026-09-11 HISTORY_ACK step:** source `3972d98d89b2418f90f88b5effee052e6c94fd68`, run #92 `34611219539`. Added peer-targeted HISTORY acknowledgements, stable retry sequence, per-peer completion, retry bounds and diagnostic/Outing lifetime separation. Automated gate passed.
- **2026-09-11 slow-walk + screen-off step:** source `3a9e0441786d4ff6d210375ee8de9231b905f479`, run #98 `34619461768`. Added sustained low-intensity motion classification, stronger still hysteresis and smoke evidence that GPS + local trail grow while screen is off. 100 tests passed; APK SHA-256 `5e7ab4cdad851d5d63d6086adb4ab33ae9ad36cfa46b490ebeb94176b925ac0c`.
- **Independent review 2026-09-12:** identified P0 HISTORY out-of-order/ACK semantics, stale POS radio lifetime and clean-install Nearby permission flow, plus origin snap, sensor-gap, queue-bounds and preview/outing contamination risks. It recommended correcting advertising+ACK first and deferring GATT/session protocol expansion until field data justify it.
- **0.7.6 hardening executable step:** `e18eea1c9cc5a302d484d8e20b1780cc0eee1171` corrected out-of-order HISTORY storage/ACK, POS native lifetime + callback delay, automatic origin snap, stale motion windows, clean-install location request, queue bounds/fairness and outing/preview/reset boundaries. Run #99 built/tests/analyzed successfully but its emulator smoke failed only because the harness used an unsupported `adb shell pm check-permission` command on the API 35 image.
- **Portable smoke fix:** `5eba40d3e9e81f3be2e85592bd6f4bcb3caad25d` changed the permission assertion to `dumpsys package` evidence without changing app behavior.
- **Run #100 (`34697873143`) passed completely:** 107/107 Flutter tests, analyzer PASS under the existing nonfatal warning/info policy, exact APK build/fingerprint/upload PASS, Android emulator smoke PASS.
- Run #100 clean-install smoke explicitly revoked location first, launched Nearby, observed and tapped the permission request, verified location permission granted and no Nearby foreground service, started Test log before the outing, promoted Outing to FGS, verified screen-off, and recorded GPS fixes `3 → 18` plus `track_added` `0 → 1` while asleep. The same process resumed and `Termina uscita` returned to Nearby without ending the diagnostic session.
- Run #100 analyzer retains 20 nonblocking issues: 5 warnings + 15 infos. This is tracked cleanup, not a warning-free claim.

## CURRENT WORK

No further executable changes are planned before the next physical gate. The validated executable remains `5eba40d3e9e81f3be2e85592bd6f4bcb3caad25d`; later README/CONTINUITY edits are documentation-only and do not supersede its APK evidence.

The next work item is a short two-phone field test focused on the exact contracts changed by the independent review: clean-install Nearby permissions, live POS freshness, screen-off slow walking, acknowledged HISTORY replay after a real separation and clean Outing/diagnostic boundaries.

## NEXT GATE — TWO-PHONE FIELD TEST

Use the exact run #100 APK on both phones. Before uninstalling an older debug build, export any diagnostic files worth keeping.

Recommended single outing:

1. On **one** phone perform a clean install. Open Convoy and grant Nearby/Bluetooth + location when requested. Do **not** press `Avvia uscita` yet. The two phones should discover each other in Nearby. The other phone may be upgraded in place.
2. On both phones open **Test log** and start a diagnostic session while still in Nearby.
3. Start **Outing** on both phones. Keep screens on for ~30–60 s and walk slowly together; verify both current markers update rather than remaining anchored.
4. Turn both screens off and continue a slow normal walk for ~1–2 min. No special exaggerated movement is required.
5. Separate far enough that the peer becomes stale/offline for roughly 45–90 s while both users keep walking. Then return together and wait about 30–60 s for recovery traffic.
6. Check that live peer position becomes fresh again and recovered dashed history appears without replacing the current marker. Missing history must remain a visible gap rather than a fabricated straight line.
7. End **Outing** on both phones. Confirm the Test log session is still active in Nearby; then end/export it explicitly from Test log.

Keep both exported JSONL files. Record only obvious visual anomalies separately: Nearby did not discover after clean install; a stale position appeared fresh; the local marker remained frozen during slow walking; a recovered point overwrote the current marker; or one phone disappeared permanently after screen-off/rejoin.

## ASTRA / ARCHITECTURE GATE

Do **not** spend another architecture-review pass before the physical test.

Use a high-depth independent review after the field logs if one of these occurs:

- acknowledged HISTORY remains materially incomplete or recovery takes too long after rejoin;
- real multi-peer behaviour suggests ACK/control traffic is crowding out POS;
- process/screen-off recovery fails in a way that cannot be isolated to a local lifecycle bug;
- the next step requires choosing among `sessionId + pointId + segmentId`, explicit missing-range reconciliation, persisted session journal or a brief GATT transfer path.

If the field test is clean, the next review can wait until immediately before that larger session/point/range protocol redesign.

## DO NOT

Do not merge PR #1 before the physical hardening gate. Do not claim HISTORY is lossless. Do not claim metre-level GNSS, guaranteed force-stop/background survival, active UWB/RTT, authenticated membership or general multi-hop mesh. Do not touch NUC/Sagre/Host Bridge from this project.

Do not reintroduce automatic origin snapping. Do not hide missing recovered history with straight-line interpolation. Do not move to GATT or a general CRDT engine merely because they are available patterns.

## OPEN RISKS / DEBT

- Real-phone HISTORY_ACK loss/retry and out-of-order behaviour still need physical evidence; emulator/unit tests cannot manufacture real radio asymmetry.
- Current HISTORY recovery still infers a replay opportunity from radio-gap state; it does not yet have receiver-declared missing ranges or persistent session identity.
- HISTORY payload does not carry logical `sessionId`, `pointId` and original `segmentId`; richer identity/reconciliation is a later architectural block.
- Process-loss outing reconstruction is not implemented; diagnostics persistence is not a session journal.
- Deep Doze/OEM energy policies and battery endurance need longer physical evidence.
- GPS-only fallback can still be conservative during very slow/tight-turn walking when IMU evidence is absent; field latency should be measured before loosening it.
- `flutter_ble_peripheral` remains installed but unused at runtime; remove after current physical gates.
- Analyzer/deprecation cleanup remains: 5 warnings + 15 infos on run #100.
- Group identity/colour convergence remains separate. Personal identity, outing identity and group membership must not be collapsed into a single colour rule.
- Debug signing is not a production signing policy. Authenticated groups, general multi-hop, downloaded basemaps and diagnostic retention UX remain later work.

## CLEANUP PENDING

After physical validation, remove the unused advertising-plugin dependency and classify legacy GPS/screens/helpers in a separate hygiene pass. Perform analyzer/deprecation cleanup without mixing it into radio/GNSS reliability changes. Remove the temporary branch only after an approved merge.

## LAST CHECKPOINT

2026-09-12: independent review drove a bounded hardening pass rather than a transport rewrite. Exact executable `5eba40d3e9e81f3be2e85592bd6f4bcb3caad25d` passed run #100 with 107 tests, analyzer/build and clean-install Android screen-off smoke. APK SHA-256 `d3456d97d8c369739b750290bfeb7bfd6b15adb3f5d2ccbe40f4170b0caa9276`. The next evidence must come from the two real phones; no additional architecture review is needed before that test.

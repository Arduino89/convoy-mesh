# Convoy Mesh — continuity

## STATUS

Reliability candidate **0.7.6+8 hardening: automated gate passed; physical two-phone validation pending**. Not a production release.

Exact validated executable source: `3e056f88ab44a4fbb9989058a9191e2bebc3cba4`.
Workflow run #105: `34701227901`.
APK SHA-256: `6fd9baa63e41e62259ac8d11db9993b034605625c91be478b3f51ee594fbc3f8`.
Android package version: `0.7.6+8`; App info should show `0.7.6`.

Later README/CONTINUITY edits are documentation-only and do not supersede the executable candidate above. Do not merge PR #1 before the physical gate below.

## WHY THE PACKAGE VERSION WAS BUMPED

The previous physical-prep attempt exposed that two different source builds, old `93dfb23e921b0da23f0b29788f353e8fb28c8d8a` and newer `5eba40d3e9e81f3be2e85592bd6f4bcb3caad25d`, both declared `0.7.0+7`. One phone therefore remained on the old build while the other had the new code, even though the package UI did not make the mismatch obvious.

The mismatch was caught before the field test because the Test log pages differed and their displayed `BUILD_COMMIT` values were `93dfb23…` versus `5eba40…`. The old build also showed disabled text `Avvia prima l’uscita`, while the hardened build permits diagnostics to start in Nearby.

`0.7.6+8` intentionally increments both version name and version code and stamps the same version into diagnostic JSONL. For the controlled gate, use a clean install on **both** phones and verify identical build commit before starting.

## CURRENT ARCHITECTURE

Flutter UI has two runtime modes.

**Nearby** starts automatically while the app is foregrounded: Android-native BLE scan + manufacturer advertising for presence/name, without continuous GPS or foreground service. On a clean install it requests the location permission required by the current scan contract because Convoy does not declare `neverForLocation`; granting it in Nearby does not start continuous GPS.

**Outing** adds GPS/trail and the foreground service for screen-off operation. BLE TX and RX are Android-native. POS advertising has a native timeout derived from remaining fix freshness; receive-side age includes native scan-delivery delay.

HISTORY replay uses stable wire sequence IDs across retries plus peer-targeted `HISTORY_ACK`. An unseen HISTORY packet may be accepted out of order; deduplication is based on stored HISTORY identity rather than live-state sequence ordering. Duplicate stored HISTORY may be re-ACKed. HISTORY and ACK queues are globally bounded and share idle radio slots while POS/NAME/PING retain priority.

Map GPS preview does not own Outing history. Starting a real Outing resets its local track. Clearing local trail or regenerating identity invalidates relevant pending transfer state.

The pedestrian motion classifier has strong-motion, sustained slow-motion and sustained-quiet evidence and resets partially satisfied timing windows after sensor-delivery gaps. The estimator no longer rewrites a live GNSS position to the trip origin merely because uncertainty regions overlap.

Diagnostic recording is independent from Outing lifetime: one Test log can span Nearby → Outing → Nearby and remains active after `Termina uscita` until explicitly ended or its four-minute bound expires.

## CANONICAL SOURCES

- `README.md`: product scope, limitations and current verified candidate.
- PR #1 / `fix/v0.4-stability`: operative changes and checkpoints.
- `.github/workflows/android-debug.yml`: automated gate and evidence.
- `ConvoyMeshApp/lib/services/convoy_mesh_service.dart`: Nearby/Outing modes, peer state, POS freshness and HISTORY/ACK scheduling.
- `ConvoyMeshApp/lib/ble/convoy_ble_codec.dart`: POS/NAME/PING/HISTORY/HISTORY_ACK wire format.
- `ConvoyMeshApp/android/app/src/main/kotlin/com/example/convoy_mesh/ConvoyBleAdvertiser.kt` and `ConvoyBleScanner.kt`: native radio path, advertising timeout and scan timing evidence.
- `ConvoyMeshApp/lib/location/pedestrian_position_estimator.dart`: bounded GPS estimator; no automatic origin snap.
- `ConvoyMeshApp/lib/location/pedestrian_motion_classifier.dart`: strong/slow/quiet hysteresis and stale-sensor handling.
- `ConvoyMeshApp/lib/services/location_fusion_service.dart`: provider/sensor lifecycle and preview/outing track ownership.
- `ConvoyMeshApp/lib/services/diagnostic_recorder.dart`: local diagnostic persistence, version/build stamp and export.
- `ConvoyMeshApp/test/trail_catchup_test.dart`, `reliability_contract_test.dart`, `pedestrian_motion_classifier_test.dart`, `gps_visual_state_test.dart` and the remaining tests under `ConvoyMeshApp/test/`.
- `tools/android_smoke.sh`: clean install → Nearby → diagnostic → Outing → screen-off walking → resume → Nearby gate.

## STABILIZED DECISIONS

Walking/hiking groups only. No vehicle assumptions or road snapping. Live radio presence and fresh coordinates are separate facts. RSSI is signal/proximity, not metres. Recovered HISTORY never replaces a peer's current position. Live POS/NAME/PING has priority over catch-up. Private field logs stay outside the public repo. Convoy work does not touch NUC/Sagre/Host Bridge/shared-worker state.

Do not treat GNSS uncertainty overlap as proof of identical location. Do not compare monotonic clocks across phones. Current HISTORY ACK is emitted after a usable point is represented locally. Do not replace advertising with GATT without field evidence that the bounded advertising+ACK design is insufficient.

## HISTORY OF VERIFIED MILESTONES

- 0.7.1 native-BLE source `9bf625a82767c0f65aea46ee72eac87bf018d2d1`, run #68: software/emulator gate passed after replacing plugin TX with Android-native advertising.
- **Physical result 2026-09-09:** Mi 9 Lite/API29 and M2101K6G/API33 saw each other with native BLE, closing the symmetric zero-RX blocker.
- 0.7.2 source `465ee5c43f69b681faa7ea9d9c9895264c31343b`, run #79: Nearby automatic discovery + bounded HISTORY catch-up passed 85 tests/analyze/build/smoke.
- **Physical result 2026-09-11:** Nearby worked immediately. After ~99 s separation, Cama queued/sent 13 historical points and Francesca accepted 7 unique HISTORY points. Real radio HISTORY was proven but incomplete; missing HISTORY stayed a visible gap rather than being fabricated as a straight line.
- Same physical test: Francesca produced 50 GPS fixes over ~199 s with worst fix gap ~6.3 s. Cama displayed roughly 7–25 m uncertainty (median ~12.4 m). No road snapping introduced.
- 0.7.3 foreground map-location indicator source `93dfb23e921b0da23f0b29788f353e8fb28c8d8a`, run #85: 90 tests/analyze/build/smoke passed.
- HISTORY_ACK step source `3972d98d89b2418f90f88b5effee052e6c94fd68`, run #92: peer-targeted ACKs, stable retry sequence, per-peer completion, retry bounds and diagnostic/Outing lifetime separation; gate passed.
- Slow-walk + screen-off step source `3a9e0441786d4ff6d210375ee8de9231b905f479`, run #98: sustained low-intensity motion classification and smoke evidence that GPS + local trail grow while screen is off; 100 tests passed.
- **Independent review 2026-09-12:** identified HISTORY ordering/ACK semantics, stale POS radio lifetime, clean-install Nearby permission flow, origin snap, sensor-gap, queue-bounds and preview/outing contamination risks. It recommended advertising+ACK hardening before any GATT/session rewrite.
- Hardening source `e18eea1c9cc5a302d484d8e20b1780cc0eee1171`: corrected those immediate contracts. Run #99 build/tests/analyze passed; emulator failed only because the harness used unsupported `adb shell pm check-permission`.
- Portable harness fix source `5eba40d3e9e81f3be2e85592bd6f4bcb3caad25d`, run #100: 107/107 tests, analyzer/build and full clean-install Android smoke passed. This was behaviorally valid but still declared the reused package version `0.7.0+7`.
- **Packaging correction source `3e056f88ab44a4fbb9989058a9191e2bebc3cba4`, run #105:** only package/diagnostic version stamps changed to `0.7.6+8`; BLE/GPS/HISTORY behavior was unchanged. 107/107 tests, analyzer, exact APK build/fingerprint and Android smoke all passed. This is the canonical physical-test APK.

## CURRENT WORK

No further executable changes are planned before the physical gate. The validated executable is `3e056f88ab44a4fbb9989058a9191e2bebc3cba4`; subsequent documentation commits do not replace its APK evidence.

The next evidence must come from two real phones on the **same clean-installed build**.

## NEXT GATE — TWO-PHONE FIELD TEST

Before the outing:

1. Export any old diagnostic JSONL worth keeping, then uninstall Convoy Mesh from **both** phones.
2. Install the exact run #105 APK on both phones.
3. In Android App info, verify both show version **0.7.6**.
4. Open Convoy, grant requested permissions, then open **Test log** on each phone. Verify both show build beginning `3e056f88…`. A clean install should not show a recovered `File pronto` card.
5. Still without starting an Outing, confirm the diagnostic button is enabled as `Avvia test • max 4 min` once Nearby is active and the phones discover each other.

Recommended single outing:

6. Start Test log on both phones while still in Nearby.
7. Start Outing on both. Walk slowly together for ~30–60 s with screens on; both current markers should update.
8. Turn both screens off and continue a normal slow walk for ~1–2 min.
9. Separate far enough for the peer to become stale/offline for roughly 45–90 s while both keep walking. Rejoin and wait ~30–60 s for recovery traffic.
10. Check that live peer position becomes fresh again and recovered dashed history appears without replacing the current marker. Missing history must remain a gap rather than a fabricated straight line.
11. End Outing on both. The Test log should remain active in Nearby; then end/export it explicitly.
12. Keep both JSONL files. Record obvious anomalies only: Nearby failed after clean install; stale position appeared fresh; local marker stayed frozen during slow walking; recovered HISTORY overwrote live position; or a phone disappeared permanently after screen-off/rejoin.

## ASTRA / ARCHITECTURE GATE

Do **not** spend another high-depth review before this physical test.

Use Astra Alto after the field logs if one of these occurs:

- acknowledged HISTORY remains materially incomplete or recovery takes too long after rejoin;
- multi-peer behaviour suggests ACK/control traffic crowds out POS;
- process/screen-off recovery fails in a way that cannot be isolated to a local lifecycle bug;
- the next step requires choosing among `sessionId + pointId + segmentId`, explicit missing-range reconciliation, a persisted session journal or brief GATT transfer.

If the field test is clean, Astra can wait until immediately before that larger protocol redesign.

## DO NOT

Do not merge PR #1 before the physical hardening gate. Do not claim HISTORY is lossless. Do not claim metre-level GNSS, guaranteed force-stop/background survival, active UWB/RTT, authenticated membership or general multi-hop mesh. Do not touch NUC/Sagre/Host Bridge from this project.

Do not reintroduce automatic origin snapping. Do not hide missing recovered history with straight-line interpolation. Do not move to GATT or a general CRDT engine merely because those patterns exist.

## OPEN RISKS / DEBT

- Real-phone HISTORY_ACK loss/retry and out-of-order behaviour still need physical evidence; emulator/unit tests cannot reproduce all radio asymmetry.
- Current HISTORY recovery still infers replay opportunity from radio-gap state; it has no receiver-declared missing ranges or persistent session identity.
- HISTORY payload does not carry logical `sessionId`, `pointId` and original `segmentId`; richer identity/reconciliation is a later architectural block.
- Process-loss outing reconstruction is not implemented; diagnostics persistence is not a session journal.
- Deep Doze/OEM energy policies and battery endurance need longer physical evidence.
- GPS-only fallback can remain conservative during very slow/tight-turn walking when IMU evidence is absent; field latency should be measured before loosening it.
- `flutter_ble_peripheral` remains installed but unused at runtime; remove after current physical gates.
- Analyzer/deprecation cleanup remains separate from radio/GNSS reliability work.
- Group identity/colour convergence remains separate. Personal identity, outing identity and group membership must not be collapsed into one colour rule.
- Debug signing is not a production signing policy. Authenticated groups, general multi-hop, downloaded basemaps and diagnostic retention UX remain later work.

## CLEANUP PENDING

After physical validation, remove the unused advertising-plugin dependency and classify legacy GPS/screens/helpers in a separate hygiene pass. Perform analyzer/deprecation cleanup without mixing it into radio/GNSS reliability changes. Remove the temporary branch only after an approved merge.

## LAST CHECKPOINT

2026-09-12: the old/new build mismatch on the two physical phones was caught before testing because Test log showed `93dfb23…` on Francesca and `5eba40…` on Cama. The root packaging issue was reused `0.7.0+7` metadata across distinct candidates. Canonical field build is now `0.7.6+8`, executable `3e056f88ab44a4fbb9989058a9191e2bebc3cba4`, run #105, APK SHA-256 `6fd9baa63e41e62259ac8d11db9993b034605625c91be478b3f51ee594fbc3f8`. Automated gate is green; next evidence must come from two clean-installed real phones.

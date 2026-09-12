# Convoy Mesh — continuity

## STATUS

Reliability candidate **0.7.6+8 hardening: automated gate passed; physical two-phone validation pending**. Not a production release.

Validated executable identity for the next physical gate:

- source `3e056f88ab44a4fbb9989058a9191e2bebc3cba4`
- workflow run #105 `34701227901`
- APK SHA-256 `6fd9baa63e41e62259ac8d11db9993b034605625c91be478b3f51ee594fbc3f8`
- Android package `0.7.6+8` (App info: `0.7.6`)

Later documentation commits are documentation-only and do not replace this executable identity. Do not merge PR #1 before the physical gate below.

## PACKAGE VERSION / PHYSICAL PREFLIGHT INCIDENT

The previous field-prep attempt exposed that old source `93dfb23e921b0da23f0b29788f353e8fb28c8d8a` and newer source `5eba40d3e9e81f3be2e85592bd6f4bcb3caad25d` both declared `0.7.0+7`. Francesca's phone therefore remained on `93dfb23…` while Cama's clean-installed phone ran `5eba40…`, even though Android App info did not distinguish the source builds.

The mismatch was caught **before** walking tests because Test log differed: old `93dfb23…` required an Outing and showed disabled text `Avvia prima l’uscita`; hardened code permits diagnostics to start in Nearby. The displayed `BUILD_COMMIT` also differed.

`0.7.6+8` fixes the packaging ambiguity by incrementing both version name and version code and stamping the same version into diagnostic JSONL. The controlled gate now requires a clean install on **both** phones and an explicit build/version check before walking.

## CURRENT ARCHITECTURE

Flutter UI has two runtime modes.

**Nearby** starts automatically while the app is foregrounded: Android-native BLE scan + manufacturer advertising for presence/name, without continuous GPS or foreground service. A clean install requests the location permission required by the current scan contract because Convoy does not declare `neverForLocation`; granting it does not start continuous GPS.

**Outing** adds GPS/trail and the foreground service for screen-off operation. BLE TX and RX are Android-native. POS advertising has a native timeout derived from remaining fix freshness; receive age includes native scan-delivery delay.

HISTORY replay uses stable wire sequence IDs across retries plus peer-targeted `HISTORY_ACK`. An unseen HISTORY packet may be accepted out of order; deduplication uses stored-history identity rather than live-state sequence ordering. Stored duplicates may be re-ACKed. HISTORY and ACK queues are globally bounded and share idle slots while live POS/NAME/PING retain priority.

Map GPS preview does not own Outing history. Starting an Outing resets local trail. Clearing local trail or regenerating identity invalidates relevant pending transfer state.

The pedestrian classifier has strong-motion, sustained slow-motion and sustained-quiet evidence and resets partially satisfied timing windows after sensor-delivery gaps. The estimator no longer rewrites a live GNSS position to the origin merely because uncertainty regions overlap.

Diagnostic recording is independent from Outing lifetime: Test log may span Nearby → Outing → Nearby and remains active after `Termina uscita` until explicitly ended or its four-minute bound expires.

## STABILIZED DECISIONS

Walking/hiking groups only. No vehicle assumptions or road snapping. Live radio presence and fresh coordinates are separate facts. RSSI is proximity/signal, not metres. Recovered HISTORY never replaces current peer position. POS/NAME/PING retain priority over catch-up. Private field logs stay outside the public repo. Convoy work does not touch NUC/Sagre/Host Bridge/shared-worker state.

Do not treat GNSS uncertainty overlap as proof of identical location. Do not compare monotonic clocks across phones. HISTORY ACK means a usable recovered point is represented locally, not merely that a radio callback occurred. Do not move to GATT without field evidence that bounded advertising+ACK is insufficient.

## VERIFIED MILESTONE HISTORY

- 0.7.1 native BLE `9bf625a82767c0f65aea46ee72eac87bf018d2d1`, run #68: software/emulator gate passed.
- Physical 2026-09-09: Mi 9 Lite/API29 and M2101K6G/API33 saw each other with native BLE, closing zero-RX.
- 0.7.2 `465ee5c43f69b681faa7ea9d9c9895264c31343b`, run #79: Nearby + bounded HISTORY, 85 tests/analyze/build/smoke passed.
- Physical 2026-09-11: automatic Nearby worked. After ~99 s separation Cama queued/sent 13 HISTORY points; Francesca accepted 7 unique points. HISTORY was real but incomplete; missing data stayed a visible gap.
- Same physical test: Francesca 50 GPS fixes/~199 s, worst gap ~6.3 s. Cama uncertainty ~7–25 m, median ~12.4 m. No road snapping introduced.
- 0.7.3 map-location indicator `93dfb23e921b0da23f0b29788f353e8fb28c8d8a`, run #85: 90 tests/analyze/build/smoke passed.
- HISTORY_ACK `3972d98d89b2418f90f88b5effee052e6c94fd68`, run #92: peer-targeted ACK, stable retry sequence, per-peer completion and diagnostic/Outing separation; passed.
- Slow-walk + screen-off `3a9e0441786d4ff6d210375ee8de9231b905f479`, run #98: sustained slow-motion classifier + trail-growth smoke; 100 tests passed.
- Independent review 2026-09-12: found HISTORY ordering/ACK, POS freshness, first-run permissions, origin snap, sensor-gap, queue-bounds and preview/outing issues; recommended advertising+ACK before GATT/session redesign.
- Hardening `e18eea1c9cc5a302d484d8e20b1780cc0eee1171`: corrected immediate contracts. Run #99 build/tests/analyze passed; smoke failed only due unsupported harness command.
- Portable smoke fix `5eba40d3e9e81f3be2e85592bd6f4bcb3caad25d`, run #100: 107/107 tests + analyzer/build/smoke passed, but still reused `0.7.0+7` package metadata.
- Canonical packaging correction `3e056f88ab44a4fbb9989058a9191e2bebc3cba4`, run #105: only package/diagnostic version stamps changed to `0.7.6+8`; BLE/GPS/HISTORY behavior unchanged. 107/107 tests, analyzer, APK build/fingerprint and Android smoke all passed.

## NEXT GATE — TWO-PHONE FIELD TEST

Preflight — complete **all five** before walking:

1. Export any old diagnostic file worth keeping, then uninstall Convoy from **both** phones.
2. Install the exact run #105 APK on both.
3. Android App info must show **0.7.6** on both.
4. Open Convoy, grant permissions, then Test log. Both must show build prefix **`3e056f88`**. Clean installs should not recover an old `File pronto` card.
5. Without starting an Outing, once Nearby is active the diagnostic button must be enabled as **`Avvia test • max 4 min`**, and the phones should discover each other.

If any preflight item differs between the two phones, stop and correct installation before collecting field data.

Field outing:

6. Start Test log on both while still in Nearby.
7. Start Outing on both; walk slowly together ~30–60 s with screens on and verify both current markers move.
8. Turn both screens off and continue normal slow walking ~1–2 min.
9. Separate enough for peer stale/offline ~45–90 s while both keep walking; rejoin and allow ~30–60 s recovery.
10. Live peer position should become fresh again; recovered dashed HISTORY may appear but must not replace the current marker. Missing history stays a gap.
11. End Outing on both. Test log should remain active in Nearby; end/export it explicitly.
12. Keep both JSONL files and note only obvious anomalies: Nearby failure, stale-as-fresh display, frozen local marker, HISTORY overwriting live position, or permanent disappearance after screen-off/rejoin.

## ASTRA / ARCHITECTURE GATE

Do **not** spend another high-depth review before this physical gate.

Use Astra Alto after field logs if acknowledged HISTORY remains materially incomplete/slow, ACK traffic crowds out POS, process/screen-off recovery reveals a nonlocal design problem, or the next step requires choosing among `sessionId + pointId + segmentId`, explicit missing-range reconciliation, persisted session journal, or brief GATT transfer.

If field results are clean, Astra can wait until immediately before that larger protocol redesign.

## OPEN RISKS / DEBT

- Real-phone HISTORY_ACK loss/retry and out-of-order behavior still need physical evidence.
- Replay opportunity is still inferred from radio-gap state; no receiver-declared missing ranges or persistent session identity yet.
- HISTORY payload lacks logical `sessionId`, `pointId` and original `segmentId`.
- Process-loss outing reconstruction is not implemented; diagnostics persistence is not a session journal.
- Deep Doze/OEM energy policies and battery endurance need longer physical evidence.
- GPS-only fallback may remain conservative during very slow/tight-turn walking when IMU evidence is absent.
- `flutter_ble_peripheral` remains installed but unused at runtime; remove after physical gates.
- Analyzer/deprecation cleanup remains separate.
- Group identity/colour convergence remains a separate design block.
- Debug signing is not a production signing policy; authenticated groups, general multi-hop and downloaded basemaps remain later work.

## DO NOT

Do not merge PR #1 before the physical hardening gate. Do not claim HISTORY lossless, metre-level GNSS, guaranteed force-stop survival, active UWB/RTT, authenticated membership or general multi-hop. Do not reintroduce origin snapping, interpolate missing HISTORY as straight lines, or move to GATT/CRDT just because the patterns exist. Do not touch NUC/Sagre/Host Bridge from this project.

## LAST CHECKPOINT

2026-09-12: preflight caught a real build mismatch before field testing (`93dfb23…` on Francesca vs `5eba40…` on Cama), caused by reused `0.7.0+7` package metadata. Canonical field build is now `0.7.6+8`, executable `3e056f88ab44a4fbb9989058a9191e2bebc3cba4`, run #105, APK SHA-256 `6fd9baa63e41e62259ac8d11db9993b034605625c91be478b3f51ee594fbc3f8`. Automated gate is green; next evidence must come from two clean-installed, build-matched real phones.

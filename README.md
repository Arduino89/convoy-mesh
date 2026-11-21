# Convoy Mesh

**Ramo Wi-Fi Direct LAB separato (2026-11-21):** [contratto e gate sperimentale](experiments/wifi_direct_offline_lab/README.md). Esperimento con Bluetooth spento, senza Internet, scambio sintetico e ACK fra due Android. Da implementare e provare; nessun effetto sulla +20 firmata, nessuna prova telefono né rete mesh dichiarata.

Android/Flutter for **walking and hiking groups in low-connectivity areas**: offline BLE exchanges and GNSS coordinates. No vehicle assumptions or road snapping. Not a replacement for mountain-safety precautions.

## Download on both phones

[Download the current experimental APK](https://github.com/Arduino89/convoy-mesh/releases/download/experimental-latest/Convoy-Mesh-Experimental.apk) — fixed public link; no GitHub account required. [Version and instructions](https://github.com/Arduino89/convoy-mesh/releases/tag/experimental-latest).

The filename/link remain the same when a reviewed candidate is promoted. Versioned prereleases retain earlier APKs; check the actual version/build inside the app. This is an experimental distribution channel, not a stable release. Android still requires confirmation to install. The current debug signing limitation below remains: a fixed download URL does not guarantee future in-place upgrade compatibility.

Publication reuses native GitHub Releases and the already-verified CI artifact, without rebuilding or signing it again. `.github/workflows/experimental-download.yml` publishes only the explicit run/source/checksum approved in that file; ordinary application builds do not automatically become downloads. After review, update those three values on the existing experiment branch. The workflow checks both successful Android jobs, exact source/hash/package/signature provenance, archives the version, updates `experimental-latest`, and downloads the published asset to recheck its hash. Only the rolling distribution tag may move. This branch-local push workflow does not depend on merging into main.

## Permanent beta signing — prepared, not active (20 November 2026)

Cama requested normal Android in-place updates for every subsequent delivered beta, without repeated uninstall or data loss. Keep the current Outdoor application ID `com.example.convoy_mesh.outdoor`, use a dedicated owner-controlled stable signing key for this beta line, and increment `versionCode` on each delivered candidate (first stable-signed candidate >=18). Reuse Android APK signing and the existing GitHub Actions/approved artifact distribution, not a custom updater or new paid service. Separate the beta signing identity from any future public-store release identity until the permanent package/Play App Signing decision is made; never silently switch the beta package or key.

**First transition:** previous +16 and +17 CI debug certificates differ; the previous private signing keys were not retained by the workflow. Investigate recovery before assuming an in-place migration is possible. Without the installed APK's original private key or a valid supported signing lineage, Android will reject a newly signed update. Export wanted diagnostic logs and custom settings before any necessary one-time uninstall; or preserve the existing app and agree a separate package migration. Never delete app data or uninstall on a user's behalf.

**Provisioning and gate:** the owner generates or controls the dedicated keystore and retains an encrypted offline backup, passwords separate. Never send the key/password in chat, repository, public artifacts or logs. Use restricted GitHub Actions secret storage and an owner-approved signing step on reviewed source; pin the expected *public* signing certificate SHA-256, reject absent/mismatched keys (no debug fallback for delivery), sign only the exact authorized artifact, and record final package/version/hash/certificate/run. Prefer isolating key access from build/test code and unreviewed agent writes. Do not expose a long-lived production signing key to debug/test workflows. Codex/Work or equivalent executable environment plus independent review must validate the signing and update gate.

**Required evidence before first durable beta handoff:** two successively numbered APKs signed by the same intended key, verified using apksigner; install the first on Android, create synthetic identity/settings/diagnostic data, update using Android package installation without uninstall, and assert version, data and permissions remain intact. Negative controls: wrong cert, missing signing configuration, and wrong package rejected; downgrade not distributed. Verify reusable artifacts and signature proof. No changes to BLE/GPS/PostHog/runtime behavior, no merge or public release; the existing `experimental-latest` link targets the pedestrian experiment and must not silently switch to Outdoor. Use explicitly approved private beta handoff. This is a plan, not evidence of a working long-lived key.

**20 November preparation:** candidate +18 changes only binary version metadata (no Dart, radio, GPS, map, PostHog or design changes); corrected stale emulator version expectation without weakening assertions. Normal CI artifact is still a DEBUG candidate, not a signed beta delivery. Added `tools/sign_outdoor_beta.sh` for owner-operated signing of an exact reviewed candidate on a trusted SDK machine; verifies source hash, package, version, APK alignment and pinned public certificate, and fails without producing a deliverable on mismatch. No long-lived key has been generated or uploaded. Owner-controlled provisioning and an actual upgrade proof remain required before activating an automated signing job or distributing +18. The earlier +17 can still be used for the independent consented telemetry test.

**Owner provisioning update:** owner reports creating the PKCS12 key and entering two environment secrets. Pinned public SHA-256 `dd058e998369d9e3b46ae91e60177b95a31aa096a6ed04b9f7ba29142480f965`. Dedicated branch-only workflow `.github/workflows/outdoor-beta-signing.yml` uses environment `convoy-beta-signing` (owner must verify required reviewers and branch restrictions), signs only exact successful +18/+19 inputs, tests update in a separate secret-free emulator job, then exposes a final +19 artifact only on success. Still pending actual approval, secret access, certificate verification, upgrade gate and independent review. Never publish the beta via the old release link.

## Current work

**Outgoing GPS warm handoff candidate +20 (2026-11-21).** Consent-based +19 PostHog log (21 retained/21 sent, 0 exclusions and drops, 21 seconds) confirms an Outing stop at elapsed 14.141 s, runtime FGS stopped 14.308 s and a fresh preview provider request at 16.083 s; the later fix remained acquiring before Test log stop. This is expected in previous code: `ConvoyMeshService.stopOuting` unconditionally disposes GPS. The separate Test log stop only stops diagnostics and has no GPS disposal code. Choice: reuse current GPS service/map page, minimal state ownership change. When Termina uscita is pressed while Map is visible and app resumed, demote Outing to foreground-only GPS preview without new provider, track points, or FGS; preserve original measurement time and frozen trail. When off Map or background, stop GPS as before. 3 regression cases and a signed-beta version +20; emulator verifies actual new GPS callback after stop, no request/FGS/trail. Initial acquisition speed remains unproven by this ~21 s partial-outing log; no changes to GPS filter thresholds/cadence or BLE. CI and review pending. +19 signed remains recommended until +20 signed by same owner key and verified with in-place update; no public release or auto-upload.


**Warm GPS handoff candidate +19 (20 November 2026).** Field report on +17: pressing Avvia uscita loses the previously acquired GPS indicator. Static cause confirmed: AppShell explicitly disposed preview and LocationFusionService reset the estimator. Preserve provider/filter and original timestamps on promotion; establish a separate outing history boundary. Added GPS request/ready/promotion diagnostic markers and tests, baseline counterproof, and emulator assertions. Cold acquisition still requires three consistent fixes over >=8 seconds with the existing five-second request cadence; thresholds unchanged and actual first-fix delay not yet established. New CI, independent review, and physical A/B test are pending. +18 signing-only candidate retained separately; permanent signing remains inactive. No release or new real data transfer.

**Outdoor LAB frontend (draft [PR #9](https://github.com/Arduino89/convoy-mesh/pull/9), `experiment/frontend-design-studio`):** residual correction `a91ff715ae13bd0525f8bfdeb4b023bad1817597` passed [run #44514378831](https://github.com/Arduino89/convoy-mesh/actions/runs/44514378831), 210 tests, three expected baseline failures, APK build and emulator. New closed-beta candidate **0.7.7-outdoor+17** restores explicit PostHog EU upload on owner direction (2026-11-19), retaining per-send own/peer consent, exact preview, no auto-send or retry. It adds terminal transfer totals and an isolated seven-event synthetic cloud test. **New CI and exact readback pending**; retention/deletion not verified, no public release or fixed-download change. See [continuity](CONTINUITY.md) and [diagnostic contract](docs/diagnostic-study-contract.md).

**Diagnostic beta candidate on this branch:** `0.7.7-diaglab+15`, draft [PR #8](https://github.com/Arduino89/convoy-mesh/pull/8); executable source `7557bd21df41a91275e4c40ff25c4ebc3afc1cbc`. [Run #43740328846](https://github.com/Arduino89/convoy-mesh/actions/runs/43740328846) attempt 1 **SUCCESS** in Flutter tests, analyze, debug APK build and Android emulator screen-off smoke. **Scope deliberately small, Radar BLE only:** BLE status names localized with subtle green/red tint, status tap routing (app permissions/Bluetooth/location settings or explanation; ready => short SnackBar); active scanning has #4 concentric pulse waves (inactive => static); local and peer names slightly emphasized; long Nearby/RSSI/GPS caveat moved behind help `?`, keeping a compact mode/GPS freshness line visible. No BLE/GPS behavior or other page modified. `+14` tester-context diagnostics stay intact; see [study contract](docs/diagnostic-study-contract.md) and [continuity](CONTINUITY.md). **No merge or public release**. Private handoff APK identity: `com.example.convoy_mesh.diaglab`, versionCode 15, versionName `0.7.7-diaglab`, **164427847 bytes**, SHA-256 `129dc9c776dc23ff3ec2e6a6d4648080e9a3971bb5068e6fd157b43a968a5fa9`; source artifact `convoy-mesh-debug-apk` (id 14172416652). APK v2 debug cert SHA-256 `498f41d9740526d4dfa64a7cb09849e7e2c7047d75a595401c187b08c8c7bb85` differs from +13: no in-place update guaranteed; **export local logs before any uninstall**. Real handset appearance/permission settings still to be verified. Cloud personal-data deletion/retention remains an independent blocker for broader data collection.

**Underlying pedestrian baseline:** **0.7.7-exp1+9**, [draft PR #4](https://github.com/Arduino89/convoy-mesh/pull/4), branch `experiment/pedestrian-acquisition-v1`. Based on PR #1 application line `c3ef471754d7e1a4b3cf2558e5c2fadbb9d4f0a7`, not old main or PR #3 ledger. **No merge.**

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

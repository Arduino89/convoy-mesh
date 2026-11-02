# Convoy Mesh — continuity

## STATUS

**0.7.7-exp1+9 experimental pedestrian candidate**, [draft PR #4](https://github.com/Arduino89/convoy-mesh/pull/4), `experiment/pedestrian-acquisition-v1`. **149/149 CI tests pass**. [Android run #121](https://github.com/Arduino89/convoy-mesh/actions/runs/37198612027), attempt 1, **SUCCESS** for both build and emulator jobs. Exact APK bytes, source and signature independently verified; automated delivery gate passed. Physical two-phone evidence pending. No production or merge approval.

User authorized implementation, branch, commits, draft PR and build on 2026-10-03, replacing the earlier read-only phase. Fix demonstrated acquisition/cadence defects first; preserve provider/5 s request/BLE/HISTORY. Do not restart from main or PR #3.

## CURRENT ARCHITECTURE

Nearby: native BLE without continuous GNSS/FGS. Map preview: location without outing track. Outing: GNSS/track plus native foreground owner. Source freshness, UI time and radio presence remain separate. HISTORY ACK/retry is bounded and never overwrites live position.

Estimator: static consensus plus majority-supported moving acquisition; first/reacquired points do not add trail. At most 26 time bins within 25 s. Motion evidence prefers 20 s, using the existing 25 s window when fewer than five observations are present. No provisional publication. IMU alone cannot authorize large unsupported innovations. Classifier unchanged; service test clock defaults to DateTime.now in production.

Diagnostics remain independent of outing lifetime, local and capped at four minutes. Process-loss outing reconstruction is still absent.

Experimental distribution: native GitHub Releases, fixed tag `experimental-latest` and asset `Convoy-Mesh-Experimental.apk`; a separate versioned prerelease preserves each promoted APK. The branch-local `.github/workflows/experimental-download.yml` explicitly selects an approved successful CI run/source/hash, validates and publishes existing bytes. No automatic publication of ordinary builds, rebuild or signing change.

## CANONICAL SOURCES

- [README](README.md): current install/artifact checkpoint and fixed download URL.
- [Experimental download](https://github.com/Arduino89/convoy-mesh/releases/tag/experimental-latest); `.github/workflows/experimental-download.yml`: reviewed distribution, archived version and byte verification.
- [Experiment rationale, measured limits and field protocol](docs/pedestrian-exp1.md).
- [Synthetic CSV](docs/pedestrian-exp1-results.csv); regenerate with `ConvoyMeshApp/tool/pedestrian_candidate_probe.dart`.
- `ConvoyMeshApp/test/`, `.github/workflows/android-debug.yml`, `tools/android_smoke.sh`: actual estimator/service and APK/emulator evidence.
- PR #1 continuity at `c3ef471` retains older milestone details; this is the current handoff, not another changelog.

## STABILIZED DECISIONS

Cama authorized public experimental APK distribution with one fixed download link on 2026-10-06. Reuse-first level 4: native GitHub Releases/Actions; no website, account service or updater added. Promote only an explicitly reviewed candidate; versioned archive assets are not overwritten. Keep DRAFT/no merge. The debug signing limitation remains; fixed URLs do not guarantee Android update compatibility.

Walking/hiking only, offline BLE, no road/origin snapping. Uncertainty overlap does not prove identical position; RSSI is not metres. Do not compare clocks across phones. No ledger/GATT/CoC/fusion-library/rendering changes here. Real logs and coordinates stay private.

Previous candidate untouched on `fix/v0.4-stability` / PR #1: **0.7.6+8**, executable `3e056f88ab44a4fbb9989058a9191e2bebc3cba4`, run #105 `34701227901`, SHA-256 `6fd9baa63e41e62259ac8d11db9993b034605625c91be478b3f51ee594fbc3f8`. Automated gates passed, physical hardening pending. Old APK artifact expired; retain copies/installs.

Experiment installs beside it as `com.example.convoy_mesh.pedestrianexp1` / **Convoy Mesh Exp**. Separate permissions/identity/data; only one app active per phone. No uninstall needed. Old certificate unavailable and debug keys not retained: future upgrade compatibility must be verified. Uninstall deletes local data.

## COMPLETED

- `7248589`: shared estimator regressions/probe. Baseline: 122 pass/19 fail; all 107 original tests pass.
- `be04599`: bounded temporal evidence and supported moving acquisition; independent irregular-interval/minority counterexamples included.
- `d0d6818`: service tests and isolated clock; preview/freshness/segments/log lifetime covered.
- `8ab7c06`: isolated version/package, SDK/dependency pins, signature checks and stronger smoke.
- `844e3a9`: short-gap support; recovery metric requires new support, not just an unexpired old anchor.
- Candidate: 147/147 passed locally and in run #120; all 149 pass in run #121 after two real-service regressions were added. Analyzer completed with the same 21 nonfatal findings.
- Independent replay matched all 18 run #120 outing observations without Android lifecycle. The slow synthetic stimulus, not GPS suspension, reproduced the missing trail; no production threshold was lowered.
- `9ca9107`: ordinary GPS-walk smoke with a positive screen-on control, post-sleep diagnostic boundary, strict fresh-trail/source-motion assertions, plus reliable quiet-IMU ordinary-walk and isolated-jump service tests.
- Run #121 built/tested exact source `9ca9107f229af91354116278c9970b39d0a4e81e`; signature/package/version/minSDK 24/arm64 checks and API35 emulator passed. Post-sleep GPS 14 -> 28 and trail 4 -> 18; all 14 new points fresh over 69.01 s / 86.52 m. Resume, preview isolation and diagnostic survival after outing stop passed.
- Reconstructed APK matches CI and emulator SHA-256 `9737bf12b116a4321f0e7a54f9b09b1d0e13ff0c95e682aba3ba0d9b793dba11` / 164,372,655 bytes. Independent signed-content/RSA verification passed. Keep the exact delivered APK; README holds install identity.

## CURRENT WORK

2026-11-02 scoped Mixpanel precheck: Flutter 3.1.0 source d8dbb35abde88c676748f179db922f9e0a20094f declares Android 8.11.1/common 1.1.0; Android source 56b8a0b33cec9a08fb046bd3d1d75f9e9743de80 inspected, not built/resolved in the LAB. Initial custom endpoint and supported optOutTracking queue deletion exist. PRECHECK_BLOCKED_MINIMIZATION: excludeProperties filters the properties bag but not subsequently attached $mp_metadata; optInTracking emits $opt_in even with automatic events disabled. Native public binding was considered; missing Flutter options alone are not the rejection reason. No full-event public veto/filter found for the unchanged minimum contract. Session identifiers are not characterized as hardware IDs or measured personal-data disclosure. Purge/interruption/sentinel tests and all other Mixpanel scenarios remain NOT_RUN, not FAIL or PASS. No account/cloud/build/runner activation, executable change or new host tests. PostHog diagnosis is closed for the examined configuration; original failing evidence is preserved. Firebase remains PLAN_ONLY on hold. Same PR#5 DRAFT, Convoy unchanged; see existing telemetry report and mixpanel-preflight.json.

2026-11-02 source-level revocation follow-up: PR#5 remains DRAFT. Exact vendor tags android-v3.75.0/core-v6.48.0 both resolve to8309f837ef92d3b05eae222c94294d79ce0c7dec;18 source blobs verified. Binding correctly reaches the same shared client. optOut blocks new capture, reset preserves outbound queue by contract, close attempts flush then stops timers/connectivity without purging files. beforeSend runs before enqueue, not on disk replay. No supported queue-purge API found; internal clear/queueProvider/storagePrefix/httpClient/persistOptOut are not adopted. Public encryption hook supplies no verified purge/barrier guarantee. No code changes, fork, manual deletion, forced drain or new Android/cloud execution. Interrupted revocation remains NOT_RUN: current app has pre-persistence and incomplete-cleanup windows, which do not explain the already-measured20 after completed revocation. See source-review evidence in the existing report and docs/telemetry-firebase-trial-plan.md. Last executable source/run remains764bc410/41429419307;77 host tests are historical, unchanged.

2026-11-02 authorized LAB publication: dedicated branch `experiment/telemetry-runtime-lab`, draft PR#5, based on operational HEAD2d8a50a. Synthetic laboratory and dedicated workflow only; no Convoy integration, merge, release or real users. Independent native runtime control PASS: source46f05ca, run41427231262/job125216668769, PID2024→2150 and persisted launches1→2. Full SDK cycle source764bc41080c7b85d25ea895ed16c4b94130c5822, run41429419307/job125223965237 completed: same-boot control PASS (PID2110→2268, launches1→2), pinned LAB build/analyze PASS, normal100/100, new10/10 after reconsent, final-wire content audit PASS, sentinels preserved. **REVOCATION FAIL: all20 revoked IDs101..120 reappeared.** Lost-ACK retry20rows/10IDs/sameUUID, overflow32/45 with first13 visibly missing. Job correctly FAILED on acceptance, not Android failure. 77 host tests PASS. Standard public ubuntu-24.04 only, no Actions artifact/cache uploads. Current receipts and limits belong in docs/telemetry-minimum-infrastructure.md; previous cloud results remain historical.

Historical checkpoint before GitHub authorization — 2026-11-02 identity review: restored verified delivery v2 (SHA256 a19e33ec5f8cd843166a2bd118c70fbc807427b79701bb7fedde4d2277cdc689) because the new executor only retained the initial checkpoint. Fixed `distinct_id == run_id` enforcement; foreign UUID is rejected/redacted while event UUID remains independent. Two new regressions FAIL before/PASS after; final Python suite 56/56 including 14 runtime guards. Current executor lacks Android toolchain, prior APKs and KVM: zero new emulator launches or SDK phases. Independent native control app/protocol prepared; not built or executed. Existing GitHub KVM runner succeeded historically but current workflow only exercises Convoy; dedicated LAB job remains a local inactive proposal. No push, workflow activation, spend or real users. PR#4 remote HEAD still 2d8a50a, open/draft; Convoy app/workflows unchanged.

2026-11-01 telemetry follow-up (local only): native public `beforeSend` configured before SDK setup; local-only binding keeps official SDK queue/transport. `optOut/reset/optOut/close` probe, unrelated-data sentinels, strict complete-wire audit and lost-ACK receiver prepared. Source `90b9e0d`; x86_64 debug LAB built/analyzed, 40 Python checks pass. **New SDK cases NOT_RUN:** Android system services fail before LAB execution, including on a clean disposable emulator; installer/input Broken pipe and DeadSystemException, root cause unestablished. No new privacy/purge PASS. Runtime stopped; final emulator shutdown SIGSEGV retained as limitation. Existing 100/100, revoked 20/20 and missing 13 results belong to prior build only. See the existing telemetry report/kit; app Convoy unchanged.

2026-11-01 telemetry evaluation: **local, unpublished** branch `experiment/telemetry-minimum-infrastructure`, based on reverified PR #4 HEAD `2d8a50a`. See [decision/evidence](docs/telemetry-minimum-infrastructure.md) and [reproducible kit](tools/telemetry_spike/README.md). PostHog EU project 330212 is connected on its free plan. API control 10/10 and actual Flutter/Android SDK airplane-mode → force-stop/reopen → cloud reconciliation 100/100 passed, no missing/duplicates; 25 Python checks pass. Adoption blocked: all 20 revoked queued events reappear after reconsent, and native metadata exceeds the six-field whitelist. Native cap32 overflow returned IDs14..45 of45: first13 missing, consistent with oldest eviction. Physical resource gates and independent review remain pending. Separate debug LAB APK only; Convoy app/dependencies/workflows/current APK unchanged. No push, spend, publication or real-user collection.

The exact experimental APK is available at https://github.com/Arduino89/convoy-mesh/releases/download/experimental-latest/Convoy-Mesh-Experimental.apk. Both publisher runs `37437992245` and `37438081554` passed, including re-download/hash verification. Archived tag `experimental-0.7.7-exp1-9-9ca9107` preserves the same bytes. On 2026-10-07 the anonymous fixed URL returned HTTP 206, the expected APK length and ZIP header; the public candidate receipt matched run #121, source and SHA-256. GitHub access is restored and PR #4 remains open/draft. Reuse-first level 2: reuse the already-verified APK, existing release workflow and field protocol; no application changes or new build. The next work is Cama/Francesca's physical trial.

Run #120 diagnosis is complete: ~0.44 m/s with reliable quiet IMU gives only ~8.9 m over 20 s, below the existing 10 m GPS-motion gate. Run #121 corrected the smoke to ordinary walking and passed stronger assertions without changing the application thresholds. Historical runs #118/#119 were cancelled by later pushes; run #120 failed. Original Work execution/error telemetry remains unavailable, so its chat interruption cause is unverified.

## NEXT GATE

Telemetry task: review the pinned Mixpanel precheck incompatibility. Do not run its dependent Android scenarios while the unchanged minimum-payload contract lacks a supported path; do not broaden the contract or filter after receipt to obtain a PASS. Reopening requires public supported control of the extra session metadata and consent events, then the already-authorized local decisive revocation/interruption test. No account or access is needed to review this evidence. PostHog's examined configuration remains blocked and must not be rerun unchanged. Firebase remains a suspended plan with unresolved pre-cloud payload observability; no activation, billing or automatic platform switch. Convoy field gate below is unchanged.

Use the three existing Cama/Francesca sessions in `docs/pedestrian-exp1.md`, each below four minutes, on Mi9Lite/API29 and M2101K6G/API33. Confirm both logs show 0.7.7-exp1+9 / `9ca9107`, preserve private exports and annotate failures. Field evidence precedes accuracy claims or merge; no need to rerun the passed automated gate unless executable changes or new counterexamples warrant it.

## DO NOT

No merge of PR #4 or #1. No old main/ledger base. Do not present old APK as improved. Do not promise zero drift and zero lag from indistinguishable inputs, metre-level accuracy, lossless HISTORY or guaranteed force-stop survival. Do not invent lines across missing history. Do not touch Cama-Enterprise, Sagre, NUC/Bridge or shared workers.

## OPEN RISKS / DEBT

- Automated screen-off evidence now passes for ordinary injected walking; very slow walking/quiet IMU and real GNSS/BLE/OEM behavior are not certified by it.
- GPS-only 0.3 m/s/accuracy 10 m still misses track movement; synthetic fresh error reaches 24 m.
- Tight curves/returns defeat net/path; coherent drift is observationally ambiguous. Exact cadence invariance is unproven; gain remains per sample.
- Acquisition is heuristic, not calibrated confidence. No physical accuracy/battery benefit measured.
- HISTORY loss/retry, OEM/deep Doze, endurance and process-loss recovery need physical evidence; identity/colour convergence remains separate.
- Original lock was incomplete. New lock matches all 76 versions recoverable from old CI logs; no old APK byte-reproducibility claim.
- Debug signing and analyzer/deprecation debt remain.

## CLEANUP PENDING

No automatic removal of branches/builds. Keep the exact delivered APK; CI retention is finite 90 days. Superseded intermediate CI runs are not candidate identities. No public/private-log duplication.

## LAST CHECKPOINT

2026-11-02 Mixpanel source precheck completed: supported endpoint/purge candidate, minimization incompatible with the current contract. All Mixpanel runtime cases NOT_RUN; no new CI/host execution. Updated same draft PR#5 and existing report/evidence. No Convoy change, cloud activation, spending, SDK fork or merge. Current next gate is review of this scoped result, not immediate Firebase activation.

2026-11-02 source diagnosis completed and independently reviewed; no new executable/runtime result. Supported purge not found in exact SDK versions; preserve failing native evidence and prepared Firebase prerequisites. PR#5 remains draft, no merge/integration/users.

2026-11-02 authorized GitHub follow-up: draft PR#5 and actual native full run41429419307 completed. Android/build/delivery/content/sentinels controls passed;20 revoked events reappeared, so adoption remains BLOCKED. Durable synthetic receipts retained; no merge/release/Convoy integration. See CURRENT WORK for exact source/run/job. Earlier checkpoint: identity verifier fixed with red/green regressions, delivery restored from archive v2; local runtime unavailable.

2026-11-01 follow-up: candidate native filter and public-reset probe compiled, independent static harness review fixes applied; execution blocked by Android system instability. No SDK fork, custom production sender, cost, publication, real users or Convoy change. Resume from evidence/runtime-preflight and exact build receipt; do not mark missing phases passed. Remote PR#4 rechecked open/draft at 2d8a50a.

2026-11-01, **local patch only**: real synthetic cloud access and SDK offline/process-restart delivery are now demonstrated. Build/source identities, raw synthetic query receipts, normalized rows and reconciliation are preserved. Privacy/consent/resource gates remain separate; no production certification, global learning or integrated memory claimed. Canonical remote files remain unchanged; preserve the patch for review.

2026-10-07: recovered GitHub access after the 6 October restriction. Rechecked draft PR #4, both successful publisher runs, published release asset size/digest and the anonymous fixed download/receipt. Exact application candidate remains `9ca9107` / 0.7.7-exp1+9; subsequent commits concern documentation and distribution. Reconciled PR description with the fixed link and archived version. No executable edits, rebuild, signing change, merge or physical validation. Next gate remains the three private physical sessions.

Policy review: the available account notice does not identify a specific rule or operation; root cause remains unverified. GitHub's [Actions terms](https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features#actions) expressly cover production/testing/deployment/publication of the associated project, and [Releases documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) describes software binary distribution. The reviewed Convoy build/publish workflow fits those stated purposes; this is not an audit of other account activity or a finding about why GitHub restricted access. [API terms](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service#h-api-terms) and [acceptable-use policies](https://docs.github.com/en/site-policy/acceptable-use-policies/github-acceptable-use-policies) prohibit abusive/excessive usage, but no such trigger is established by the available evidence. A specific explanation would require GitHub Support's reason. No reusable root-cause lesson established; preserve the incident's limits rather than inventing a global rule.

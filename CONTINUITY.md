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

**2026-11-05 offline LAB preparation corrected and verified:** source `e094db2d815b10aca3ce49cdd9007304818220b3`, run42072267635/number13/attempt1/job127403084581 **SUCCESS**. Independent Android control first; fresh install, private directory, exact shell_v2 feature, shell-T write, mode600 and exact dummy readback, process stop/private-file absence/radio restoration all PASS. Offline barrier passed before and after; no LAB activity, consent, capture or cloud call.45targeted host controls passed in CI;178fullhost separately. Native application source stays `2d76100fda1df0637e953f4ad90f26073028880c`, five source/build hashes unchanged. [Evidence/summary](docs/telemetry-evidence/2026-11-05/run-42072267635/summary.json). Independent receipt recomputation PASS and byte-identical reproducible script retained with the evidence; original workflow restored in the evidence closure with skip-ci, no more Android runs.

Established defect: prequoted script passed to exec-in's own argument escaping; client0 did not certify remote write. Run10 reproduced STAT1FILE_NOT_FOUND after silentWRITE0. Supported correction uses shell-T/shell_v2 and confirms creation only after mode/readback. Two newly introduced harness defects (sh/pipefail wrapper and CSV interpretation of line-oriented features CLI) were reproduced, minimally corrected and retained as regressions. Run11 also had an unlocalized offline-barrier timeout; later probes passed the unchanged gate, so no universal environment-stability claim. [Cause, attempts and limits](docs/telemetry-minimum-infrastructure.md). Historical run8 exact stderr/command is not retroactively established.

**2026-11-06 cloud LAB15 concluded BLOCKED after the first20 actually arrived:** executable source `809caf200f6232b162fee009fa2a7c2b484d7855`, wrapper `340571da315d9f19e35ef3374902fcd2be8cfd62`, run42300571195/number15/attempt1/job128176961434 FAILURE. All193/193CI host controls, independent Android control and all local regressions passed;9/9private-provision phases and cleanup passed. First20reserved/written once, HTTP200parseableJSON rejected byLAB status-integer1predicate,0ACK/queue100. Actualstatusvalue/type/body were notrecorded; downstreamdrain120stimeout is notthecause. Raw PostHog rows/count independently confirm20unique firstbatch/sameIDs/UUIDs/timestamps/eightproperties/privacyflags,0duplicates inthissinglerequest. **Cloud revocation, newconsent/newdelivery and retry NOT_RUN.** [Summary/cause/repro](docs/telemetry-evidence/2026-11-06/run-42300571195/README.md).

The singleadditional200-row authorization is closed: historical500unknown + new200 = cumulative700prudential; ledgerpositivelyrecovered20reserved/written/1attempt/0ACK, but futureallowance0/noautomaticrefund oruseofunused180. No newcloudcalls ordelete. Private originalreadback retained separately; publicservermetadata valuesredacted. person_mode/person_idcolumns needreview and do notproveprofilecreation. Fullprivacy/infrastructure and physicalphones/battery/GNSS/BLE unverified.

Exact-source local14 also SUCCESS: run42299072769/job128171820455;193/193host,107hashes,16requests/232rows/222unique,80revoked+30refused absent,13overflowlossesvisible/10sentinelpairs preserved. Local15 independentlyrecomputed too. [Local14review](docs/telemetry-evidence/2026-11-06/run-42299072769/independent-runtime-review.json). Native5hashes remain unchanged. A later HOST-ONLY analyzer correction replaces an overconfident genericretrylabel with NOT_ATTESTED_INCOMPLETE_CLIENT_EVIDENCE:24targetedtestsPASS, identicalBLOCKED/status/counts/thresholds; it is not attributed to Android809source. Originalworkflow restoredbyte-for-byte in the skip-ci closure. PR5DRAFT; Convoy unchanged, no merge/release/spend/realusers/integration.

## NEXT GATE

Offline only: review the bounded response-shape receipt and immediate-stop proposal in response-acceptance-cause.json, preserveunknownvalues privately and add syntheticregressions; establish supported actual ACKcontract before changingacceptance. No furtherAndroid/cloudtrial is authorized by the closed single15gate. Any later cloudexecution requires a new concrete reviewedsource/run/budget decision; no automaticrefund, rerun or substitution. Actualdeletion separately requires Cama exactproject/run/UUIDset and previewapproval.

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

2026-11-06 source809caf/run14localPASS193; run15/job128176961434BLOCKED with20actualcloudreceipts and ACKpredicatefailure, cloudrevocation/retryNOT_RUN. Independentreviews and reproduciblescripts under6November;24host-onlylabelregressionsPASS. Budget700conservative/future0; originalworkflowrestoredatclosure, no newrun. Application fieldcheckpoint remains README/PR4.

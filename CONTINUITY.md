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

2026-11-05 offline LAB diagnosis/correction, same branch experiment/telemetry-runtime-lab and draft PR5. **Exact reproduced failure now known:** run42065607773/number10/attempt1/job127378742920, sourceb282c3f8, native control PASS; fresh LAB installation confirmed and mkdir successful, legacy exec-in returns0 silently, then PRIVATE_STAT exits1/FILE_NOT_FOUND. Cleanup confirms stopped process, private-file absence and initial radio restoration. Budget receipt survives the failure with all countersnull and prior500conservativelycounted/0authorized. [Run10 receipt/review](docs/telemetry-evidence/2026-11-05/run-42065607773/summary.json).

Code defect: the prequoted script was passed to exec-in, whose argument escaping preserves those quotes, while its client0 does not attest remote exit. Primary pinned AOSP source and a deterministic host shell reproduction show invalid remote command127/fileabsent; the corrected supported shell-T/shell_v2 path writes mode600 and exact bytes. [Cause/limits](docs/telemetry-evidence/2026-11-05/provision-transport-cause.json). The precise ADB version in run10 and original stderr/run8 command remain unknown; this does not retroactively certify the historical run8 cause. Narrow correction uses shell-T with shell_v2 required; only verified mode+byte-readback confirms file creation. Command completion has a separate flag. **Corrected Android proof still pending** until one reviewed run11/attempt1;174host tests PASS, app/native source remains pinned2d76100 and unchanged.

The first new diagnostic run9/42064249734 failed earlier in the introduced workflow wrapper: sh rejected Bash pipefail before Python. Minimal explicit Bash entry corrected that separate defect; run10 then executed control and reproduced the actual file failure. [Run9 cause/review](docs/telemetry-evidence/2026-11-05/run-42064249734/summary.json). Do not repeat identical attempts; run11 changes the established transfer defect only, adds numeric ADB identity and keeps the same offline/no-LAB-launch boundary. Original complete LAB job is excluded by exact marker. No real token, capture/grant, new budget or cloud calls.

Prior source2d76100 local regressions remain valid: run8/41993361681 control+133host+local sender PASS,80revoked0reappeared,new events delivered,sentinels intact,13overflow losses visible; independent111hash/raw review. [Evidence](docs/telemetry-evidence/2026-11-05/run-41993361681/README.md). Unknown native cloud counters mean **500counted prudentially/0remaining**, not500proved sends; query0 does not refund. Future budget, actual deletion and integration require their separate decisions. No Convoy/main change, merge, release, real users, phones/GPS/Bluetooth/battery validation or SDK fork.

## NEXT GATE

Telemetry task: independently review the exact shell-T correction and run11/attempt1 guard, execute one corrected offline install/provision/cleanup, then independently verify mode600/exact dummy readback, source/APK/control identity, cleanup and budgetnull/0. Stop on failure without identical retries. If successful, restore the original workflow, update the same PR/continuity and present a separately gated future cloud proposal; no cloud budget is granted now.

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

2026-11-05 sourceb282c3f8/run10 confirms control/installation/mkdir PASS but PRIVATE_STAT1FILE_NOT_FOUND after exec-in0; cleanup and unknown budget receipt preserved. Primary-source/host reproduction identifies prequoting/exec-in contract defect. Supported shell-T correction and174host tests ready for reviewed offline run11; new Android fix NOT_YET_VERIFIED. Prior run8 remains500conservative/0authorized. Application/physical field checkpoint unchanged in README/PR4.

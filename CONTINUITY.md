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

**2026-11-14 — beta telemetry direction (Cama):** Convoy must remain useful offline without an account. Internet and diagnostic collection are optional; each beta tester must opt in separately and be able to revoke. Aim for a *new* reviewable beta candidate that measures the real two-phone trial and sends minimized technical events to the existing EU PostHog project, filterable by anonymous installation/consent epoch, session, version and problem category. No GPS coordinates, tracks, names or advertising identifiers in automatic telemetry. Preserve outing data and the currently published 0.7.7-exp1+9 APK. This is product direction, not an app-user consent, live integration, new APK, merge or release approval.

**Execution order/resource constraint:** Reuse PR #5's verified local sender and existing `cloud-proposal.md`; first close cloud receiving/ACK/dedup/revocation proof with a newly reviewed, explicit per-run gate (proposal: maximum 160 new event transmissions, previous closed ceiling 700, prospective total 860). Until that scoped cap, gate and invocation are explicitly approved, the effective cloud transmission allowance remains zero. Then implement on a separate reviewable app candidate: default-off capture/queue, durable consent and revocation, bounded retry/expiration and send safeguards, privacy-preserving grouping, and tests covering offline/restart/consent/restore. Field-test both phones and verify matching records actually persisted in PostHog before any distribution decision. Conserve Work/Codex credits for Sagre; read-only inspection and narrowly scoped preparation may use GitHub tools, but a functioning Android APK or live cloud outcome requires runtime evidence and cannot be inferred from static review.

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

**Isolated telemetry LAB / draft PR5 — full sender verified locally, 7 November2026.** Exact executed source `50386a5c8ce5b0cf628073989a0eaf1549008e79`, wrapper `21938337ca1ac00ecd35697d16f592a62fa7477e`; [run42389745788 / number17 / attempt1 / job128454627737](https://github.com/Arduino89/convoy-mesh/actions/runs/42389745788/job/128454627737) SUCCESS. Host205/205no skips; Androidcontrol8/8 before LAB. Same actual HTTP200 reader used by local and cloud paths. Six new HTTP cases PASS:25queued→firstOk removes only20→same5originaltail→secondOk empties; quota/unknown/malformed/invalidUTF8/truncated200 preserve25serializedSQLite rows and0ACK after completed rejection and offline restart, then recover onOk. Full inherited suite:9PASSED+one intentional before-durable-intent boundary;100normal delivered,80durablyrevoked/30refused absent, synthetic traces/settings conserved, UUIDretry stable and13overflowlosses visible.

[Current evidence, APK identity, independent reviews and offline recalculation](docs/telemetry-evidence/2026-11-07/full-sender-local/README.md). No newSDK/server/endpoint/integration. Fixedloopback, fake token, fresh emulator, no cloud configuration/credentials; radio/defaultnetwork barriers and stopLAB/removeADBroute before radio restoration. Independent source, concrete workflow and runtime reviews passed. Original workflow restored byte-identically at b3bfaf8 and independently verified on GitHub; final receipt commit changes documentation only, no new Android source/execution. This proves real HTTP/InputStream/UTF8 behavior locally, not TLS/PostHog storage or physicalphone behavior. Earlier33functionfixtures remain historical; they were reused rather than reexecuted.

**Cloud remains separate and unauthorized.** Historical run15/source809caf:20actuallyreceived/0ACK/queue100, exact responsebodyunknown; no cloud revocation/newconsent/retry/dedupe proof. No old20 reloaded/retried. Prior prudential700closed, currentfutureallowance0. Convoy unchanged; no merge/release/integration/paidservice/realusers. Application field checkpoint remainsREADME/PR4.

## NEXT GATE

**Authorization update — 2026-11-14 (Cama):** exactly one synthetic PostHog EU laboratory trial is authorized, at most **160 event-transmissions inclusive of retries**, with **no activation of paid services**, no real personal data, no old-20 replay, no app integration/release. Conservative previous ceiling 700 + new allowance 160 = 860. A user approval of the cap is not a passing execution gate: same-source/CI, fresh project/privacy/retention/deletion/free-quota checks and one-use run/attempt binding remain mandatory. No cloud execution was performed when this entry was recorded. Reuse the existing laboratory and the restored workflow; avoid unreviewed remote dispatch or blind rerun.

**Identity note:** application BLE `my_id` is a random positive 31-bit value saved in `SharedPreferences`, displayed as "Il mio ID" and regenerable by the user. It identifies a current BLE participant, not an authenticated human; it is broadcast alongside location protocol packets and must not be used as the persistent cloud `distinct_id` or uploaded automatically. Future beta telemetry should use a separate, consent-scoped random installation identity and optionally allow the tester to provide a *voluntary test label* when correlating private field results. Never upload real names or coordinates.

Review full local evidence and the [non-executing cloud proposal](docs/telemetry-evidence/2026-11-07/full-sender-local/cloud-proposal.md):160new event-transmissions maximum (130nominal+30margin), only after separate Cama approval and reviewed new gate700+160=860. Oldunused180 and old20 retries remain excluded. No cloud execution from this closure. Phones/battery/GNSS/BLE remain separate subsequent gates.

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

**14 November 2026 — fail-closed deletion-gate correction:** Commit `b2f883b` on draft PR #5 tightens `validate_cloud_gate` for new schema-2 allowances after 700 conservatively consumed rows: `deletion.status=VERIFIED` alone no longer passes. A separate `anonymous_event_deletion` evidence contract now requires a declared completed request for an anonymous distinct ID, positive before-count, exactly zero after-count, distinct nonempty request/readback references, and a fresh readback timestamp. Host regressions cover the former false-positive and profile-only/HTTP-accepted/stale/nonzero cases; historical 500+200 fixtures remain compatible. The evidence contract itself is **not** independent proof of PostHog deletion: real server request and raw readback remain unavailable through current connector, so `deletion` stays **HOLD**, no live cloud trial or APK changes. CI [run #20](https://github.com/Arduino89/convoy-mesh/actions/runs/43631868440) was IN_PROGRESS with host checks PASS and cloud provisioning SKIPPED at this checkpoint; Android completion not yet certified. Next: confirm run #20 result, then verify a supported server-side deletion/readback mechanism with authorized synthetic evidence; only then reassess the capped single cloud launch.

**14 November 2026 — anonymous deletion assessment:** Live read-only PostHog query on `cm_lab_probe` (1–14 November) found **182 synthetic events, 4 distinct IDs, all 182 explicitly `$process_person_profile=false`**. Anonymous event IDs need not have person profiles, so a `persons-bulk-delete` API plus asynchronous HTTP202 cannot certify deletion of these event rows. PostHog documents a separate Data Deletion API, but project access/permissions and terminal event-removal verification remain unproven. No deletion or cloud send performed; the `deletion` preflight stays **HOLD**. The [existing cloud proposal](docs/telemetry-evidence/2026-11-07/full-sender-local/cloud-proposal.md) now records evidence and next verification. The single 160-event authorization remains unused; PR5 draft and APK unchanged.

**14 November 2026 — cloud preflight checkpoint:** Run #19 `43613462960`, attempt 1, exact executed source `dddcc57`: **SUCCESS**, host and Android local sender controls passed; cloud provisioning step **SKIPPED**. Live PostHog project 330212/EU: free plan, no active subscription, 182/1,000,000 current events, anonymize IP enabled, session replay disabled, default event retention **12 months** (not 30 days). A deletion tool exists but its behavior has not been demonstrated; deletion gate remains **UNVERIFIED**, hence cloud run **HOLD**. Cama's one-use 160 synthetic-transmission authorization stands; no event use yet from this allowance. Verified preflight details in [cloud proposal](docs/telemetry-evidence/2026-11-07/full-sender-local/cloud-proposal.md). Next: demonstrate required deletion/privacy controls in authorized synthetic scope, recheck free quota, independently review exact source and one-shot guarded workflow, then perform at most one guarded cloud run when all checks pass. No APK/app changes, paid activation, merge or publication.

**14 November 2026 — single-run 160-gate preparation:** Run #18 (43612874058, attempt 1, source `04630cf`) completed SUCCESS: host controls and Android synthetic loopback passed; cloud provisioning step SKIPPED (no PostHog transmission). Follow-up commit `dddcc57` changes only `review_cloud_launch.py` and `test_cloud_launch_gate.py`: expected one-use cloud wrapper 160 new rows, prior conservative ceiling 700, cumulative 860; rejects old 200/700 grant and budget discrepancies while preserving legacy fixtures in `test_ci_cloud_trial.py`. Run #19 (43613462960, attempt 1) host controls succeeded; at last check Android loopback still IN_PROGRESS. No live cloud gate has been prepared/reviewed, no cloud launch, no app integration or release. Next: confirm full run #19 result, then verify current free quota/privacy/retention/deletion, exact source and remaining one-use guard. Never activate the old 200-row workflow or assume a host test is a successful live trial.

7 November2026: full local sender run17/attempt1/job128454627737 SUCCESS on50386a5;205host,control8,10inheritedscenarios and6newHTTPcases verified. Independent runtime review passed; originalworkflow restoration independently verified, final receipt documentation-only. Cloud budget remains0;160onlyproposed. PR5draft, Convoy unchanged.

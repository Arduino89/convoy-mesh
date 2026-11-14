# Cloud LAB15 — blocked after first20 events delivered

Runtime source `809caf200f6232b162fee009fa2a7c2b484d7855`; wrapper `340571da315d9f19e35ef3374902fcd2be8cfd62`. [Run42300571195/job128176961434](https://github.com/Arduino89/convoy-mesh/actions/runs/42300571195/job/128176961434), number15/attempt1 FAILURE. All193host controls and independent Android control/local regressions passed before the partial cloud phase.

120scanner-approved data receipts plus SHA256inventory: export ZIP105,923bytes/SHA256`a887bd4817320277fa7981cffaf3256342b7507691763dd98b674b686e734586`. No raw diagnostic logs, privateconfig, token, real coordinates, personal names or APK in this folder. Original stdout control/build receipt reconstruction is hash-checked against runtime references.

Preparation9/9passed.100normal events persisted offline across process restart; the first20were written once, returnedHTTP200, were rejected by the LAB acknowledgment predicate and remained unacknowledged in queue100. Raw PostHog records/count independently confirm20unique/sameIDs/UUIDs/timestamps/expectedproperties, no duplicates in that firstrequest. The other80normal events were notattempted. Revocation/newconsent/newdelivery/controlledretry were NOT_RUN. Empty revoked cohorts or retry sets cannot certify those scenarios.

`response-acceptance-cause.json` separates the parseable-response status predicate rejection from its downstream120sdrain timeout. Actualstatusvalue/type/body were not recorded; neither a specificvalue nor a parsingfailure is claimed. No acknowledgment predicate was relaxed and no newsend performed.

`readback-public/` preserves output from the runtime809analyzer. `readback-public-corrected/` changes only an overconfident retry interpretation to NOT_ATTESTED_INCOMPLETE_CLIENT_EVIDENCE: bothresultsremainBLOCKED/raw20; allthresholds/countsunchanged.24host regressions pass, with an independent exactdiff review in ../analysis-label-review.json. This host-only correction belongs to the closure source, not the Android809runtime.

Private raw connector rows/count and normalizedreadback are retained separately; only key/type metadata for person_mode/person_id ispublic. Their presence is notproofthat a personprofilewascreated. All eight expected eventproperties/flags match the first20prewrite records. Fullprivacy/infrastructure remainsunverified.

Reproduce the independent public-only partial review:

```sh
python3 recompute_cloud15_blocked.py bundle --support . --gate ../cloud-launch-gate.json --out /tmp/cloud15-public-review.json
```

For the complete readbackreview, add --readback PATH --rows-response PATH --count-response PATH using the privatearchive files and the script's help. Public-only recomputation does not include serverreceipt assertions; the private inputs are necessary for that part. Run15local raw review is also reproducible with recompute_run15_local.py (see --help); all107localreceipts are retained. extract_private_readback.py reconstructs the8column rawtable without droppingduplicates and rejects duplicateJSONkeys/nonfinitevalues; test_private_readback_extraction.py preserves its syntheticcounterexamples. These are analysis helpers, not anotherAndroid/cloudexecution.

Cleanup verified: LABstopped, privatefile removed/absencechecked, radiosrestored; workflowprivateinputsremoved. Ledgerrecovery observed20reserved/written,1attempt,0ACK. This does notrefundtheallowance: cumulative700conservative/future0;unusednative180authorizesnofuturelaunch. Originalworkflow restoredbyte-for-byte in the skip-ci closure. PR5draft, Convoyunchanged; no merge/release/realusers/spend/deletion. Nextgate is the bounded offline ACKdiagnostic proposal, not another cloudtrial.

Portable synthetic parser checks (same test algorithm, paths changed to arguments only):

```sh
python3 test_private_readback_extraction.py --out /tmp/observer-review.json
```

The originally executed scratch harness is retained as observer-synthetic-harness-executed.py with its original paths; observer code hash unchanged. The portable helper run has its separate receipt; it is not another network or Android execution.

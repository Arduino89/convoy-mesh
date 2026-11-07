# Local Android validation — run14

Source `809caf200f6232b162fee009fa2a7c2b484d7855`; [run42299072769/job128171820455](https://github.com/Arduino89/convoy-mesh/actions/runs/42299072769/job/128171820455), attempt1 SUCCESS. Cloud configuration and cleanup skipped because cloud disabled; all193 host controls passed with no skip. The host outside CI separately had one historical shell reproduction skipped on a newer Dash; that does not change the CI receipt.

`bundle/` contains only the explicit scanner-approved synthetic receipts. Export ZIP89,215bytes/SHA256`4e04af33698d083efa9a46b9bd6287ad99fbc81a41c49211bffb123388585390`;107 data-file hashes plus digest inventory verified. Original stdout control/build receipts are reconstructed preserving insertion order and accepted only after their hashes match the runtime references; normalized export copies are semantically equal.

Reproduce without app imports, Android or network:

```sh
python3 recompute_run14_local.py bundle --support . --source-review ../source-review.json --out /tmp/run14-review.json
cmp /tmp/run14-review.json independent-runtime-review.json
```

Independent recomputation: normal100/100;80revoked events absent across durable revoke/three named crash cutpoints;30refused absent;10sentinel pairs preserved; retry20rows/10stableidentities; saturation32/45 received, oldest13missing and loss counter13visible.16requests/232rows/222unique IDs;98,000bodybytes;393native states/397nonces.

The independent control PID changed2386→2636, launchcounter2→3, sameboot. This meets the existing strictpositive/+1 contract; why an earlier onCreate occurred is not established. Before durable revoke and already-received inflight cases remain explicit boundaries. Rowcapacity alone was saturated; disk/bytecaps, all crashes, physicalphones/GNSS/BLE/battery and cloud delivery are not proved here. APK was built/identity-checked in CI, not distributed or independently downloaded.

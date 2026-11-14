#!/usr/bin/env python3
from pathlib import Path
from datetime import datetime,timezone
import argparse,re,json
from android_lab_control import adb,PACKAGE
parser=argparse.ArgumentParser(description='Read only the LAB UID history; never save a full network dump.')
parser.add_argument('--out',type=Path,required=True)
args=parser.parse_args()
if args.out.exists(): raise SystemExit('Use a new evidence path')
if not adb('get-serialno').startswith('emulator-'): raise SystemExit('Synthetic emulator only')
uid=int(adb('exec-out','run-as',PACKAGE,'id','-u'))
raw=adb('shell','-n','dumpsys','netstats','detail')
in_uid=False; selected=False; groups=0; rows=[]; current_set=''
for line in raw.splitlines():
 if line.strip()=='UID stats:': in_uid=True;continue
 if line.strip()=='UID tag stats:': in_uid=False
 if not in_uid: continue
 if 'ident=' in line and 'uid=' in line:
  u=re.search(r'\buid=(-?\d+)',line);tag=re.search(r'\btag=(\S+)',line);st=re.search(r'\bset=(\S+)',line)
  selected=bool(u and int(u[1])==uid and tag and tag[1]=='0x0')
  current_set=st[1] if st else 'UNKNOWN'
  if selected: groups+=1
 if selected and re.search(r'\bst=\d+',line):
  fields=dict(re.findall(r'\b(st|rb|rp|tb|tp|op)=(\d+)',line))
  if 'rb' in fields and 'tb' in fields: rows.append({**{k:int(v) for k,v in fields.items()},'set':current_set})
receipt={'utc':datetime.now(timezone.utc).isoformat(),'scope':'LAB_UID_NETWORK_HISTORY_LAST_POLL_NO_BASELINE_NOT_SDK_ONLY','package':PACKAGE,'uid':uid,'groups':groups,'history_rows':rows,'raw_dump_saved':False,'no_baseline':True,'battery':'NOT_MEASURED','limitations':['Cumulative across all lab APK runs; no paired OFF/ON baseline.','NetworkStats last-poll data may lag; not a TLS-body or radio-energy measurement.','No inference of production or four-hour traffic budget.']}
if rows and not ('ALL' in {x['set'] for x in rows} and len({x['set'] for x in rows})>1):
 receipt.update(rx_bytes=sum(x['rb'] for x in rows),tx_bytes=sum(x['tb'] for x in rows))
else: receipt['traffic_measurement']='UNAVAILABLE_OR_AMBIGUOUS_NOT_ZERO'
args.out.write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt))

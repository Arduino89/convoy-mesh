#!/usr/bin/env python3
import argparse,copy,hashlib,json,subprocess,sys,tempfile
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument('--repo',type=Path,default=Path(__file__).resolve().parents[4])
parser.add_argument('--observer',type=Path,default=Path(__file__).with_name('extract_private_readback.py'))
parser.add_argument('--out',type=Path,required=True)
args=parser.parse_args();repo=args.repo.resolve();observer=args.observer.resolve()
sys.path.insert(0,str(repo/'tools/telemetry_spike'))
from test_reconcile_cloud_trial import CloudReadbackGuards
from reconcile_cloud_trial import READBACK_COLUMNS,expected_queries
fixture=CloudReadbackGuards();fixture.setUp()
queries=expected_queries(fixture.transport,fixture.preflight)
with tempfile.TemporaryDirectory(prefix='cloud200-observer-review-') as tmp:
 d=Path(tmp);(d/'transport.json').write_text(json.dumps(fixture.transport))
 (d/'preflight.jsonl').write_text(''.join(json.dumps(x)+'\n' for x in fixture.preflight))
 row=copy.deepcopy(fixture.cloud_items[1]);row['properties']['synthetic_metadata']='left|right'
 row['person_mode']='NULL';row['person_id']='00000000-0000-0000-0000-000000000000'
 def render(props=None):
  cells=[]
  for name in READBACK_COLUMNS:
   cells.append((props if props is not None else json.dumps(row[name],separators=(',',':'))) if name=='properties' else row[name])
  return '|'.join(cells)
 header='|'.join(READBACK_COLUMNS)
 valid_table=header+'\n'+render()+'\n'+render()
 def wrap(table,query):
  return json.dumps({'content':[{'type':'text','text':json.dumps({'query':{'query':query},'results':table})}],'isError':False})
 def run(name,table=valid_table,count=2,rows_raw=None,count_raw=None,expected_success=False):
  folder=d/name;folder.mkdir();r=folder/'rows.json';c=folder/'count.json';out=folder/'out.json'
  r.write_text(wrap(table,queries['rows']) if rows_raw is None else rows_raw)
  c.write_text(wrap('raw_count\n'+str(count),queries['count']) if count_raw is None else count_raw)
  result=subprocess.run([sys.executable,str(observer),'--repo',str(repo),'--transport',str(d/'transport.json'),'--preflight',str(d/'preflight.jsonl'),'--rows-response',str(r),'--count-response',str(c),'--out',str(out)],capture_output=True,text=True)
  passed=(result.returncode==0)==expected_success
  details={'case':name,'expected_success':expected_success,'exit_code':result.returncode,'output_created':out.exists()}
  if expected_success and result.returncode==0:
   parsed=json.loads(out.read_text())
   details.update(raw_count=parsed['raw_count'],rows_preserved=len(parsed['rows']),identical_rows_preserved=parsed['rows'][0]==parsed['rows'][1],embedded_pipe_preserved=all(x['properties']['synthetic_metadata']=='left|right' for x in parsed['rows']),scalar_NULL_preserved_as_string=all(x['person_mode']=='NULL' and isinstance(x['person_mode'],str) for x in parsed['rows']),raw_row_hash_matches=parsed['row_response_sha256']==hashlib.sha256(r.read_bytes()).hexdigest(),raw_count_hash_matches=parsed['count_response_sha256']==hashlib.sha256(c.read_bytes()).hexdigest())
   passed=passed and all(details[k] for k in ('identical_rows_preserved','embedded_pipe_preserved','scalar_NULL_preserved_as_string','raw_row_hash_matches','raw_count_hash_matches')) and parsed['raw_count']==2 and len(parsed['rows'])==2
  if not expected_success:passed=passed and not out.exists()
  details['passed']=passed
  return details
 cases=[]
 cases.append(run('embedded_pipe_and_duplicate_rows',expected_success=True))
 cases.append(run('duplicate_property_key',table=header+'\n'+render('{"sentinel":"first","sentinel":"last"}'),count=1))
 cases.append(run('nonfinite_property_NaN',table=header+'\n'+render('{"sentinel":NaN}'),count=1))
 cases.append(run('nonfinite_property_Infinity',table=header+'\n'+render('{"sentinel":Infinity}'),count=1))
 cases.append(run('duplicate_outer_key',rows_raw=wrap(valid_table,queries['rows'])[:-1]+',"isError":false}'))
 inner='{"query":{"query":'+json.dumps(queries['rows'])+'},"results":'+json.dumps(valid_table)+',"results":'+json.dumps(valid_table)+'}'
 cases.append(run('duplicate_inner_key',rows_raw=json.dumps({'content':[{'type':'text','text':inner}],'isError':False})))
 cases.append(run('count_mismatch',count=1))
 cases.append(run('wrong_column_count',table=valid_table.replace(header,header+'|extra',1)))
 cases.append(run('blank_internal_row',table=header+'\n'+render()+'\n\n'+render()))
 cases.append(run('unexpected_tail_width',table=header+'\n'+render()+'|extra',count=1))
 report={'status':'PASS_SYNTHETIC_OBSERVER_EXTRACTION' if all(x['passed'] for x in cases) else 'FAIL','scope':'TEMPORARY_SYNTHETIC_END_TO_END_NO_NETWORK','observer_sha256':hashlib.sha256(observer.read_bytes()).hexdigest(),'cases':cases,'tests_run':len(cases),'tests_passed':sum(x['passed'] for x in cases),'network_called':False,'runtime_or_repository_source_changed':False}
 args.out.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report,indent=2))
 if not all(x['passed'] for x in cases):raise SystemExit(1)

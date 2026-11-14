#!/usr/bin/env python3
"""Independent read-only review of exported synthetic cloud15 receipts.

No LAB code imports, Android execution, network access or deletion. Raw server
readback is an optional private input; only metadata key counts are published.
"""
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
import hashlib, json, re, uuid
from pathlib import Path

SOURCE='809caf200f6232b162fee009fa2a7c2b484d7855'
RUN='synthetic-cloud-20261106-r15'
FIELDS={'schema_version','run_id','event_id','sequence','event_name','synthetic'}
PROPS=FIELDS|{'$geoip_disable','$process_person_profile'}
ITEM={'event','distinct_id','uuid','timestamp','properties'}
COLUMNS=['uuid','event','properties','timestamp','distinct_id','created_at','person_mode','person_id']

def check(value,label):
    if not value: raise ValueError(label)
def pairs(items):
    out={}
    for k,v in items:
        check(k not in out,'duplicate JSON key'); out[k]=v
    return out
def parse(text):
    return json.loads(text,object_pairs_hook=pairs,parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite JSON')))
def read(path): return parse(path.read_text())
def rows(path): return [parse(s) for s in path.read_text().splitlines() if s]
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def stamp(value):
    check(isinstance(value,str),'timestamp type')
    result=datetime.fromisoformat(value.replace('Z','+00:00'))
    check(result.tzinfo is not None,'timestamp timezone')
    return result.astimezone(timezone.utc)
def event(n): return {'schema_version':1,'run_id':RUN,'event_id':f'{RUN}-{n:06d}','sequence':n,'event_name':'cm_lab_probe','synthetic':True}
def offline(s):
    c=s['connectivity']
    return c['probe_available'] is True and all(c[k] is False for k in ['active_network','internet_capable','validated']) and c['transports']==[]
def uid(value):
    check(isinstance(value,str) and str(uuid.UUID(value))==value,'canonical UUID')
    return value

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('bundle',type=Path);p.add_argument('--support',type=Path,required=True)
    p.add_argument('--gate',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--readback',type=Path);p.add_argument('--rows-response',type=Path);p.add_argument('--count-response',type=Path);args=p.parse_args();b=args.bundle;c=b/'cloud-public';s=args.support
    manifest={}
    for line in (b/'SHA256SUMS.txt').read_text().splitlines():
        sha,name=line.split('  ',1)
        check(name not in manifest and re.fullmatch('[a-f0-9]{64}',sha),'manifest schema')
        check(not Path(name).is_absolute() and '..' not in Path(name).parts,'manifest path')
        check((b/name).is_file() and not (b/name).is_symlink() and digest(b/name)==sha,'manifest hash '+name);manifest[name]=sha
    check(len(manifest)==120,'120 data receipts')
    check({str(x.relative_to(b)) for x in b.rglob('*') if x.is_file()}==set(manifest)|{'SHA256SUMS.txt'},'exact bundle inventory')
    export=read(s/'export-manifest.json');check(set(export['files'])==set(manifest)|{'SHA256SUMS.txt'},'export inventory')
    r=read(c/'result.json');budget=r['budget'];rec=read(c/'budget-recovery.json')
    accounting={'accounting_schema_version':2,'limit':200,'total_ceiling':700,'prior_rows_conservative_consumed':500,'additional_rows_authorized':200}
    check(r['source_commit']==SOURCE and r['run_id']==RUN and r['project_id']==330212 and r['execution_id']=='Isolated Android telemetry laboratory:15','identity')
    check(r['status']=='BLOCKED' and r['blocked_reason']=='HTTP_TRANSPORT_DRAIN_WINDOW_EXPIRED','explicit blocked outcome')
    check(all(type(budget[k]) is int and budget[k]==v for k,v in accounting.items()) and budget['reserved_rows'] is None and budget['unattested_consume_full_remaining'] is True,'unattested summary not zero')
    check(rec['authorization_accounting']==accounting and rec['authorized_total_ceiling']==rec['conservative_consumed_for_future_launches']==700 and rec['remaining_for_future_launches']==0 and rec['automatic_refund_allowed'] is False,'no refund')
    check(rec['status']=='OBSERVED_COMMITTED_LAB_LEDGER' and [rec[k] for k in ['reserved_rows','reserved_attempts','body_written_rows','body_written_requests','acknowledged_requests']]==[20,1,20,1,0] and rec['cloud_received_rows'] is None,'committed ledger')
    gate=read(args.gate);ref=read(c/'cloud-gate-reference.json')
    check(gate['source_commit']==SOURCE and gate['run_id']==RUN and gate['execution_id']=='Isolated Android telemetry laboratory:15' and gate['run_attempt']==1,'gate identity')
    check(hashlib.sha256((json.dumps(gate,separators=(',',':'))+'\n').encode()).hexdigest()==ref['sha256'] and ref['authorization_accounting']==accounting,'exact private gate binding')
    build=read(b/'direct-build/build-receipt.json');apk=read(c/'apk-receipt.json');origbuild=s/'original-build-receipt.json'
    check(read(origbuild)==build and digest(origbuild)==apk['build_receipt_sha256'],'original build hash')
    for k in ['source_commit','apk_sha256','apk_bytes','identity','source_sha256']:check(build[k]==apk[k],'APK '+k)
    check(build['source_commit']==SOURCE and build['analytics_sdk'] is None and build['new_dependencies']==[] and build['identity']['package']=='com.cama.telemetry.direct_lab','build identity')
    runtime=read(b/'runtime-control-smoke/receipt.json');runtime_ref=read(c/'runtime-gate-reference.json');origcontrol=s/'original-control-receipt.json'
    check(read(origcontrol)==runtime and digest(origcontrol)==runtime_ref['sha256'],'original control hash')
    check(runtime['status']==runtime_ref['status']=='PASS_NATIVE_RUNTIME_CONTROL' and runtime['gate_pass'] is True and runtime['boot_id']==runtime_ref['boot_id'],'same boot control')
    prep=rows(c/'preparation.jsonl')
    check([v['phase'] for v in prep]==['INSTALL_APK','INSTALL_VERIFY','PRIVATE_MKDIR','PRIVATE_SHELL_FEATURES','PRIVATE_WRITE','PRIVATE_STAT','PRIVATE_VERIFY','PRIVATE_REMOVE','PRIVATE_REMOVE_VERIFY'],'9 preparation stages')
    check(all(type(v['returncode']) is int and v['returncode']==0 and v['error_category']=='NONE' for v in prep),'9 preparation exits0')
    check(r['shell_v2_confirmed'] is True and r['shell_features_observation']['exact_shell_v2_count']==1,'shell protocol')
    check(all(r['cleanup'][k] is True for k in ['installation_confirmed','private_write_command_completed','configuration_write_confirmed','provisioned','lab_stopped','private_config_removed','initial_radio_settings_restored']),'cleanup')
    planned=[event(n) for n in [*range(1,101),*range(121,141)]]
    check(rows(c/'expected.jsonl')==planned and rows(c/'revoked-intent.jsonl')==[event(n) for n in range(101,121)],'planned oracle only')
    pre=rows(c/'preflight.jsonl');tx=rows(c/'transport.jsonl');check(len(pre)==1 and len(tx)==4,'partial attempt inventory')
    pr=pre[0];batch=pr['payload']['batch'];check(pr['attempt_id']==1 and pr['budget_reserved_rows']==pr['rows']==20 and pr['body_bytes']==7883,'20 row reservation')
    check(pr['credential_redacted'] is True and pr['envelope_keys']==['api_key','batch'] and set(pr['payload'])=={'batch'},'credential redaction')
    originals={}
    for n,item in enumerate(batch,1):
        check(set(item)==ITEM and item['event']=='cm_lab_probe' and item['distinct_id']==RUN,'envelope whitelist')
        props=item['properties'];check(set(props)==PROPS and props['$geoip_disable'] is True and props['$process_person_profile'] is False,'property whitelist/privacy')
        check(type(props['sequence']) is int and type(props['schema_version']) is int and props['synthetic'] is True and {k:props[k] for k in FIELDS}==event(n),'exact first20 business values')
        uid(item['uuid']);stamp(item['timestamp']);originals[event(n)['event_id']]=item
    check(len(batch)==20 and len({v['uuid'] for v in batch})==20,'20 distinct UUIDs')
    check(pr['prewrite_content_audit']['violations']==[] and pr['prewrite_content_audit']['normalized_rows']==[event(n) for n in range(1,21)],'cross-check observer normalization')
    check([v['phase'] for v in tx]==['reserved','body_written','response','finished'],'ordered attempt lifecycle')
    for v in tx:
        check(v['attempt_id']==1 and v['budget_reserved_rows']==v['rows']==20 and v['row_limit']==200 and v['event_ids']==list(originals) and v['uuids']==[x['uuid'] for x in batch],'transport identities')
    response,finished=tx[2:]
    check(response['response_code']==finished['response_code']==200 and response['response_accepted'] is False and response['quota_limited'] is False and response['ack_discarded'] is False and finished['ack_discarded'] is False and finished['acknowledged'] is False and finished['body_written'] is True,'HTTP200 rejected, no ack, no controlled retry')
    check(all(stamp(tx[i]['utc'])<=stamp(tx[i+1]['utc']) for i in range(3)),'attempt time order')
    states=rows(c/'states.jsonl');network=rows(c/'network.jsonl');life=rows(c/'lifecycle.jsonl');check(states and states[0]['action']=='configure','baseline')
    first=states[0];check(first['consent'] is False and first['queue_count']==first['cloud_rows_reserved']==first['requests_started']==0,'initial deny')
    pair=first['setting_value'],first['trace_sha256'];suffix=pair[0].removeprefix('synthetic-setting-');uid(suffix)
    check(hashlib.sha256(('SYNTHETIC TRACE SENTINEL WITHOUT COORDINATES '+suffix+'\n').encode()).hexdigest()==pair[1],'trace sentinel bytes')
    nonces=set();prev=0
    for v in states:
        check(v['run_id']==RUN and v['transport_mode']=='posthog_cloud_https' and v['action_ok'] is True and v['error']=='','state identity')
        check((v['setting_value'],v['trace_sha256'])==pair,'sentinels unchanged')
        check(v['action_nonce'] not in nonces and re.fullmatch('[a-f0-9]{32}',v['action_nonce']),'state nonce');nonces.add(v['action_nonce'])
        check(type(v['cloud_rows_reserved']) is int and prev<=v['cloud_rows_reserved']<=20 and v['cloud_row_limit']==200,'monotonic ledger');prev=v['cloud_rows_reserved']
    captures=[(i,v) for i,v in enumerate(states) if v['action']=='capture'];check(len(captures)==1 and captures[0][1]['queue_count']==100 and offline(captures[0][1]),'normal100 captured offline')
    ci,cap=captures[0];restart=next(v for v in states[ci+1:] if v['pid']!=cap['pid'])
    check(offline(restart) and restart['queue_count']==100 and restart['consent'] is True and restart['cloud_rows_reserved']==restart['requests_started']==0,'offline restart before any attempt')
    check(len(network)==2 and network[0]['online_requested'] is False and offline(network[0]) and network[0]['cloud_rows_reserved']==network[0]['requests_started']==0,'observed offline')
    check(network[1]['online_requested'] is True and all(network[1]['connectivity'][k] is True for k in ['probe_available','active_network','internet_capable','validated']),'observed validated online')
    check(len(life)==3 and life[0]=={'action':'force_stop','old_pid':cap['pid'],'pid_absent':True} and life[1]=={'action':'restart','old_pid':cap['pid'],'new_pid':restart['pid']} and life[2]=={'action':'force_stop','old_pid':restart['pid'],'pid_absent':True},'restart and final stop')
    final=states[-1];check(final==r['last_persisted_state'] and final['queue_count']==100 and final['in_flight_count']==0 and final['cloud_rows_reserved']==final['cloud_rows_written']==20 and final['requests_started']==1 and final['requests_acked']==0,'final blocked snapshot')
    check(final['cloud_block_reason']=='UNRECOGNIZED_RESPONSE' and final['cloud_transport_blocked']==1 and final['cloud_audit_failures']==final['cloud_budget_blocked']==final['retry_ack_discarded']==final['revoked_count']==0,'fail-closed state, no revocation/retry reached')
    check(not any(v['action'] in ['revoke','arm_retry'] for v in states),'dependent scenarios not run')
    report={'schema_version':1,'status':'BLOCKED_DIAGNOSTIC_VERIFIED_NOT_ACCEPTANCE_PASS','reviewer':'/root/review_launch','scope':'INDEPENDENT_RECOMPUTATION_OF_ACTUAL_PARTIAL_CLOUD_RECEIPTS_NOT_NEW_EXECUTION','source_commit':SOURCE,'run_id':RUN,'github_run_id':42300571195,'github_job_id':128176961434,'attempt':1,'manifest_entries_verified':len(manifest),'export_zip_sha256':export['sha256'],'blocked_reason':'HTTP_TRANSPORT_DRAIN_WINDOW_EXPIRED','native_block_reason':'UNRECOGNIZED_RESPONSE','causal_limit':'Response body/shape not retained. HTTP200 plus response_accepted=false proves parser rejection, not its exact response-content cause.','budget':dict(accounting,committed_reserved_rows=20,observed_body_written_rows=20,acknowledged_requests=0,cloud_received_rows=None,conservative_consumed_for_future_launches=700,remaining_for_future_launches=0,automatic_refund_allowed=False),'apk':{'source_commit':SOURCE,'package':build['identity']['package'],'bytes':build['apk_bytes'],'sha256':build['apk_sha256'],'certificate_sha256':build['identity']['certificate_sha256'],'original_receipt_hash_verified':True},'independent_control':{'status':'PASS_NATIVE_RUNTIME_CONTROL','original_hash_verified':True,'same_boot':True},'preparation':{'phases':9,'all_exits0':True,'shell_v2_confirmed':True,'private_content_write_verified':True,'final_stop_private_removal_radio_restore':True},'normal':{'status':'PARTIAL_BLOCKED_NOT_DELIVERY_PASS','captured_offline':100,'survived_offline_restart':100,'reserved_first_batch':20,'written_first_batch':20,'http_status':200,'response_accepted':False,'acknowledged':False,'queue_remaining':100,'prewrite_whitelist_verified_for_rows':20,'settings_and_trace_preserved_all_states':True,'state_observations':len(states),'unique_state_nonces':len(nonces),'network_observations':2},'dependent_cloud_cases':{'revocation':'NOT_RUN','new_consent_after_revocation':'NOT_RUN','new_events_after_revocation':'NOT_RUN','controlled_retry_same_uuid':'NOT_RUN','cloud_deduplication':'NOT_RUN'},'cloud_readback_status':'PENDING_DIAGNOSTIC_QUERY','limits':['This diagnostic verifies an actual blocked attempt; no acceptance threshold was relaxed.','Prewrite whitelist is observed before sending, not an independent TLS wire capture; the credential value is redacted.','The native180 remaining counter does not authorize another run; all700 stay conservatively consumed for future launches.','Planned revoked-intent/expected files are oracles, not proof that those dependent scenarios executed.','Queue100 after20bodywrites reflects no accepted acknowledgment; it is not proof the server stored zero events.','HTTP response body was not retained; no exact response-content root cause can be reconstructed from these files.','Emulator/local controls do not establish phone battery/GNSS/BLE/OEM behavior.','No rerun, deletion, release, merge, Convoy integration or new spending performed by this review.']}
    if args.readback:
        rb=read(args.readback);check(rb['source_commit']==SOURCE and rb['run_id']==RUN and rb['project_id']==330212 and rb['complete'] is True,'diagnostic readback provenance')
        check(type(rb['raw_count']) is int and rb['raw_count']==len(rb['rows'])<500,'diagnostic raw count')
        response_provenance={}
        tables={}
        for prefix,override,qfield in [('row',args.rows_response,'query'),('count',args.count_response,'count_query')]:
            rawpath=override or Path(rb[prefix+'_response_ref'])
            check(rawpath.is_file() and digest(rawpath)==rb[prefix+'_response_sha256'],'original '+prefix+' response hash')
            rawresponse=read(rawpath);check(rawresponse.get('isError') is not True,'original connector error')
            texts=[x['text'] for x in rawresponse['content'] if x['type']=='text'];check(len(texts)==1,'unambiguous raw connector text')
            rawtable=parse(texts[0]);check(rawtable['query']['query']==rb[qfield] and isinstance(rawtable['results'],str),'raw query binding')
            tables[prefix]=rawtable['results']
            response_provenance[prefix]={'response_sha256':digest(rawpath),'reference_sha256':hashlib.sha256(rb[prefix+'_response_ref'].encode()).hexdigest()}
        rawlines=tables['row'].splitlines();check(rawlines[0].split('|')==COLUMNS,'raw table header')
        rawparsed=[];decoder=json.JSONDecoder(object_pairs_hook=pairs,parse_constant=lambda _:(_ for _ in ()).throw(ValueError('nonfinite raw table JSON')))
        for line in rawlines[1:]:
            check(bool(line),'blank raw row');prefix=line.split('|',2);check(len(prefix)==3,'raw row prefix')
            rest=prefix[2].lstrip();props,end=decoder.raw_decode(rest);tail=rest[end:].lstrip();check(tail.startswith('|'),'raw JSON boundary')
            suffix=tail[1:].split('|');check(len(suffix)==5,'raw row width')
            rawparsed.append(dict(zip(COLUMNS,[prefix[0],prefix[1],props,*suffix])))
        check(rawparsed==rb['rows'],'all raw rows preserved in exact order without deduplication')
        countlines=tables['count'].splitlines();check(len(countlines)==2 and countlines[0]=='raw_count' and countlines[1].isdigit() and int(countlines[1])==rb['raw_count'],'raw count binding')
        report['connector_response_provenance']=response_provenance
        report['raw_extraction_independently_rechecked']=True
        report['source_authentication_limit']='REFERENCED_CONNECTOR_RESPONSES_NOT_CRYPTOGRAPHIC_ATTESTATION'

        check(stamp(rb['queried_at_utc'])>=stamp(r['finished_utc']),'readback time')
        begin=stamp(r['started_utc']).replace(microsecond=0)-timedelta(seconds=300);finish=stamp(r['finished_utc']);end=finish.replace(microsecond=0)+timedelta(seconds=300+bool(finish.microsecond))
        selector=("timestamp >= toDateTime('"+begin.strftime('%Y-%m-%d %H:%M:%S')+"', 'UTC') AND timestamp <= toDateTime('"+end.strftime('%Y-%m-%d %H:%M:%S')+"', 'UTC') AND (properties.run_id = '"+RUN+"' OR distinct_id = '"+RUN+"' OR uuid IN ("+', '.join("'"+u+"'" for u in sorted(x['uuid'] for x in batch))+"))")
        q='SELECT '+', '.join(COLUMNS)+' FROM events WHERE '+selector+' ORDER BY timestamp, uuid LIMIT 500';count='SELECT count() AS raw_count FROM events WHERE '+selector
        check(' '.join(rb['query'].split())==' '.join(q.split()) and ' '.join(rb['count_query'].split())==' '.join(count.split()),'independent exact diagnostic raw/count queries')
        seen=Counter();metadata=Counter();protocol=Counter()
        for v in rb['rows']:
            check(set(v)==set(COLUMNS),'raw row columns');props=v['properties'];check(isinstance(props,dict),'properties object')
            check(type(props['sequence']) is int and type(props['schema_version']) is int and props['synthetic'] is True,'server business types')
            business={k:props[k] for k in FIELDS};check(business==event(props['sequence']),'server business values');eid=business['event_id']
            check(eid in originals,'only known transmitted first20');orig=originals[eid]
            check(v['event']==orig['event'] and v['distinct_id']==RUN and v['uuid'].lower()==orig['uuid'] and stamp(v['timestamp'])==stamp(orig['timestamp']),'stored envelope matches client')
            stamp(v['created_at']);seen[eid]+=1
            for key in set(props)-PROPS:
                label=key if isinstance(key,str) and re.fullmatch(r'[A-Za-z0-9_$.: -]{1,100}',key) else '<redacted-key-name>';metadata[label]+=1
            for key in ['person_mode','person_id']:
                if v[key] is not None:metadata['column:'+key]+=1
            for key,val in [('$geoip_disable',True),('$process_person_profile',False)]:
                if props.get(key) is not val:protocol['stored_control_missing_or_changed:'+key]+=1
        report['cloud_readback_status']='DIAGNOSTIC_ONLY_NOT_ACCEPTANCE_PASS'
        report['diagnostic_cloud']={'raw_rows':len(rb['rows']),'unique_known_bodywritten_events':len(seen),'known_bodywritten_missing_in_window':20-len(seen),'duplicate_rows':sum(seen.values())-len(seen),'metadata_key_counts':dict(sorted(metadata.items())),'stored_control_observations':dict(protocol),'metadata_values_redacted':True,'revocation_exercised':False,'retry_exercised':False,'query_window_start':begin.isoformat(),'query_window_end':end.isoformat(),'private_readback_sha256':digest(args.readback)}
        report['limits']+=['Diagnostic readback can establish receipt of the attempted first20 only; it does not convert this blocked run into a completed delivery/revocation/retry pass.','Identity mutations outside the finite timestamp window or future late arrivals are not ruled out.','Server-added metadata values are private; nonnull person columns alone do not prove profile creation.']
    args.out.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'status':report['status'],'sha256':digest(args.out),'state_observations':len(states),'reserved_rows':20,'body_written_rows':20,'cloud_readback_status':report['cloud_readback_status']}))
if __name__=='__main__':main()

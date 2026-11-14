#!/usr/bin/env python3
"""Faithfully extract a bounded connector table; original responses stay private."""
import argparse,hashlib,json,sys
from datetime import datetime,timezone
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument("--repo",type=Path,required=True);p.add_argument("--transport",type=Path,required=True)
p.add_argument("--preflight",type=Path,required=True);p.add_argument("--rows-response",type=Path,required=True)
p.add_argument("--count-response",type=Path,required=True);p.add_argument("--out",type=Path,required=True)
a=p.parse_args();sys.path.insert(0,str(a.repo/"tools/telemetry_spike"))
from reconcile_cloud_trial import READBACK_COLUMNS,expected_queries,normalize_connector_rows,parse_json
def unique(pairs):
 value={}
 for key,item in pairs:
  if key in value:raise ValueError("duplicate JSON key")
  value[key]=item
 return value
def nonfinite(value):raise ValueError("nonfinite JSON number")
transport=parse_json(a.transport.read_text());preflight=[parse_json(x) for x in a.preflight.read_text().splitlines() if x]
q=expected_queries(transport,preflight)
def table(path,query):
 raw=path.read_bytes();value=parse_json(raw.decode())
 if value.get("isError"):raise ValueError("connector error")
 texts=[x["text"] for x in value["content"] if x["type"]=="text"]
 if len(texts)!=1:raise ValueError("ambiguous connector text")
 obj=parse_json(texts[0])
 if obj.get("query",{}).get("query")!=query:raise ValueError("query mismatch in raw response")
 if not isinstance(obj.get("results"),str):raise ValueError("unsupported results")
 return obj["results"],hashlib.sha256(raw).hexdigest()
rows_text,row_sha=table(a.rows_response,q["rows"]);count_text,count_sha=table(a.count_response,q["count"])
lines=rows_text.splitlines()
if not lines or lines[0].split("|")!=READBACK_COLUMNS:raise ValueError("unexpected raw columns")
rows=[];decoder=json.JSONDecoder(object_pairs_hook=unique,parse_constant=nonfinite)
for line in lines[1:]:
 if not line:raise ValueError("blank table row")
 first=line.split("|",2)
 if len(first)!=3:raise ValueError("missing row prefix")
 rest=first[2].lstrip();properties,end=decoder.raw_decode(rest)
 tail=rest[end:].lstrip()
 if not tail.startswith("|"):raise ValueError("properties boundary")
 suffix=tail[1:].split("|")
 if len(suffix)!=5:raise ValueError("tail width")
 rows.append([first[0],first[1],properties,*suffix])
countlines=count_text.splitlines()
if len(countlines)!=2 or countlines[0]!="raw_count" or not countlines[1].isdigit():raise ValueError("raw count shape")
count=int(countlines[1])
if count!=len(rows) or count>=500:raise ValueError("incomplete table/count/limit reached")
normalized=normalize_connector_rows(READBACK_COLUMNS,rows)
result={"schema_version":1,"project_id":330212,"run_id":transport["run_id"],"source_commit":transport["source_commit"],
 "query":q["rows"],"count_query":q["count"],"queried_at_utc":datetime.now(timezone.utc).isoformat(),"complete":True,
 "raw_count":count,"rows":normalized,
 "row_response_ref":str(a.rows_response),"row_response_sha256":row_sha,
 "count_response_ref":str(a.count_response),"count_response_sha256":count_sha}
a.out.write_text(json.dumps(result,indent=2)+"\n")
print(json.dumps({"status":"EXTRACTED_ALL_RAW_ROWS_WITHOUT_DEDUP","raw_count":count,
 "row_response_sha256":row_sha,"count_response_sha256":count_sha,"private_values_not_printed":True}))


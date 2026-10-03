#!/usr/bin/env python3
"""One bounded public OSV readback; writes only its exclusively owned packet."""
from pathlib import Path
from datetime import datetime, timezone
import collections
import hashlib
import json
import re
import subprocess
import time
from urllib.parse import quote

OWNED=Path(__file__).resolve().parent
ROOT=OWNED.parents[3]
GRAPH=ROOT/'docs/release/critical-implementation-2026-10-01/root-arc09-aab-failure-readback1/production-runtime-graph.json'
GRAPH_SHA='20bb8fa08b757b0c29cbc7dc2f281f1616c78da4de468e6c796e928149eb2056'
WHOLE_SECONDS=300
REQUEST_SECONDS=25
RESPONSE_LIMIT_BYTES=4*1024*1024
MAX_PUBLIC_REQUESTS=128
DOCS=[('osv-querybatch','https://google.github.io/osv.dev/post-v1-querybatch/'),
      ('osv-query','https://google.github.io/osv.dev/post-v1-query/'),
      ('osv-advisory','https://google.github.io/osv.dev/get-v1-vulns/'),
      ('osv-schema','https://ossf.github.io/osv-schema/')]

def utc():return datetime.now(timezone.utc).isoformat()
def sha(raw):return hashlib.sha256(raw).hexdigest()
def encoded(value):return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
def write_json(path,value):path.write_bytes(json.dumps(value,indent=2,sort_keys=True,ensure_ascii=False).encode()+b'\n')

raw=GRAPH.read_bytes()
if sha(raw)!=GRAPH_SHA:raise SystemExit('sealed runtime graph hash mismatch')
graph=json.loads(raw)
if len(graph['components'])!=173 or len(graph['edges'])!=995 or len(graph['artifacts'])!=141:
    raise SystemExit('sealed runtime graph count mismatch')
readback_path=GRAPH.with_name('readback.json');readback_raw=readback_path.read_bytes();readback=json.loads(readback_raw)
if readback['runtime_graph_sha256']!=GRAPH_SHA:raise SystemExit('source readback graph binding mismatch')
queries=[];query_by_coordinate={};component_map=[]
for index,component in enumerate(graph['components']):
    entry={'graph_component_index':index,'graph_component':component}
    if component.get('kind')=='module' and all(isinstance(component.get(k),str) and component[k] for k in ['group','name','version']):
        coordinate=(component['group'],component['name'],component['version'])
        if coordinate not in query_by_coordinate:
            query_index=len(queries);query_by_coordinate[coordinate]=query_index
            queries.append({'query_index':query_index,'query':{'package':{'ecosystem':'Maven','name':component['group']+':'+component['name']},'version':component['version']},
                            'graph_component_indexes':[],'responses':[],'advisory_ids':[],
                            'pagination_complete':False,'status':'not-yet-requested','errors':[]})
        query_index=query_by_coordinate[coordinate];queries[query_index]['graph_component_indexes'].append(index)
        entry.update(query_index=query_index,queryability='exact-Maven-coordinate-version')
    else:
        entry.update(query_index=None,queryability='unqueryable-in-this-Maven-graph',
                     reason='local project component supplies no Maven group:name/version; plugin/path names do not authorize ecosystem or version inference' if component.get('kind')=='project' else 'incomplete or unsupported component identity')
    component_map.append(entry)
if len(queries)!=157:raise SystemExit('unexpected exact Maven query count')
plan={'format':'collect-selected-runtime-osv-plan-v1','graph_path':str(GRAPH),'graph_sha256':GRAPH_SHA,
      'component_count':173,'exact_Maven_queries':157,'local_project_unqueryable_count':16,
      'whole_public_request_envelope_seconds':WHOLE_SECONDS,'request_max_time_seconds':REQUEST_SECONDS,
      'subprocess_timeout_seconds_at_most':30,'response_limit_bytes':RESPONSE_LIMIT_BYTES,'max_public_requests':MAX_PUBLIC_REQUESTS,
      'automatic_retries':0,'redirects_followed':False,'proxy_and_curl_config_disabled':True,
      'TLS_peer_verification_required':True,'credentials_or_API_keys_used':False,
      'docs_browsed_before_execution':True,'queries':[{k:v for k,v in q.items() if k in ['query_index','query','graph_component_indexes']} for q in queries],
      'component_mapping':component_map}
write_json(OWNED/'query-plan.json',plan)
(OWNED/'requests').mkdir()
start=time.monotonic();deadline=start+WHOLE_SECONDS;started_utc=utc();receipts=[]

def request(label,url,payload=None):
    remaining=deadline-time.monotonic()
    if remaining<=0 or len(receipts)>=MAX_PUBLIC_REQUESTS:
        return {'label':label,'url':url,'request_performed':False,'error':'whole public request envelope or request-count bound exhausted'}
    number=len(receipts);folder=OWNED/'requests'/f'{number:03d}-{label}';folder.mkdir()
    request_bytes=b'' if payload is None else encoded(payload)
    (folder/'request-body.bin').write_bytes(request_bytes)
    headers=['Accept: application/json' if 'api.osv.dev' in url else 'Accept: text/html','Accept-Encoding: identity']
    if payload is not None:headers.append('Content-Type: application/json')
    method='GET' if payload is None else 'POST'
    timeout=min(REQUEST_SECONDS,max(0.1,remaining-1))
    argv=['/usr/bin/curl','-q','--silent','--show-error','--http1.1','--proto','=https','--proxy','',
          '--max-time',str(timeout),'--connect-timeout',str(min(10,timeout)),'--max-filesize',str(RESPONSE_LIMIT_BYTES),
          '--retry','0','--user-agent','Collect-runtime-advisory-readback/1.0','--request',method,
          '--dump-header',str(folder/'response-headers.bin'),'--output',str(folder/'response-body.bin'),
          '--trace',str(folder/'http-trace.txt'),'--write-out','%{json}']
    for header in headers:argv.extend(['--header',header])
    if payload is not None:argv.extend(['--data-binary','@'+str(folder/'request-body.bin')])
    argv.append(url)
    write_json(folder/'request.json',{'method':method,'URL':url,'body_file':'request-body.bin','body_sha256':sha(request_bytes),'body_bytes':len(request_bytes),
               'explicit_headers':headers,'credentials_used':False,'TLS_peer_verification_disabled':False,'argv':argv})
    beginning=utc();clock=time.monotonic();stdout=b'';stderr=b'';exit_code=None;exception=None
    try:
        proc=subprocess.run(argv,capture_output=True,timeout=min(30,max(0.1,deadline-time.monotonic())))
        stdout,stderr,exit_code=proc.stdout,proc.stderr,proc.returncode
    except subprocess.TimeoutExpired as error:
        stdout=error.stdout or b'';stderr=error.stderr or b'';exception='subprocess-timeout-public-request-bound'
    except OSError as error:exception=type(error).__name__+': '+str(error)
    (folder/'curl-writeout.bin').write_bytes(stdout);(folder/'curl-stderr.bin').write_bytes(stderr)
    metadata={}
    try:metadata=json.loads(stdout)
    except (ValueError,UnicodeError):pass
    response_path=folder/'response-body.bin';response=response_path.read_bytes() if response_path.exists() else b''
    record={'label':label,'url':url,'request_performed':True,'method':method,'started_utc':beginning,'finished_utc':utc(),
            'actual_seconds':round(time.monotonic()-clock,6),'curl_exit_code':exit_code,'exception':exception,
            'http_status':metadata.get('http_code'),'ssl_verify_result':metadata.get('ssl_verify_result'),
            'effective_URL':metadata.get('url_effective'),'remote_IP':metadata.get('remote_ip'),
            'response_bytes_retained':len(response),'response_sha256':sha(response),
            'request_body_sha256':sha(request_bytes),'receipt_directory':folder.relative_to(OWNED).as_posix(),
            'response_complete':exit_code==0 and metadata.get('http_code')==200 and metadata.get('ssl_verify_result')==0 and len(response)<=RESPONSE_LIMIT_BYTES}
    if len(response)>RESPONSE_LIMIT_BYTES:record['error']='response bound exceeded; retained raw bytes are not complete query evidence'
    write_json(folder/'receipt.json',record);receipts.append(record)
    return record

for label,url in DOCS:request(label,url)
pending=[(q['query_index'],None) for q in queries];seen_tokens=collections.defaultdict(set);batch=0
while pending and time.monotonic()<deadline and len(receipts)<MAX_PUBLIC_REQUESTS:
    payload_queries=[]
    for index,token in pending:
        item=dict(queries[index]['query'])
        if token is not None:item['page_token']=token
        payload_queries.append(item)
    receipt=request(f'querybatch-{batch:03d}','https://api.osv.dev/v1/querybatch',{'queries':payload_queries});batch+=1
    body_path=OWNED/receipt.get('receipt_directory','missing')/'response-body.bin'
    response=None
    if receipt.get('response_complete'):
        try:response=json.loads(body_path.read_bytes())
        except (ValueError,UnicodeError):pass
    results=response.get('results') if isinstance(response,dict) else None
    if not isinstance(results,list) or len(results)!=len(pending):
        for index,token in pending:
            queries[index]['responses'].append({'receipt':receipt,'request_page_token':token})
            queries[index]['status']='coverage-unknown-request-or-response-error';queries[index]['errors'].append('HTTP/TLS/JSON/results-shape failure; no automatic retry')
        pending=[];break
    following=[]
    for position,((index,token),result) in enumerate(zip(pending,results)):
        q=queries[index];q['responses'].append({'receipt_directory':receipt['receipt_directory'],'result_position':position,'request_page_token':token,'result':result})
        if not isinstance(result,dict) or 'error' in result or not isinstance(result.get('vulns',[]),list):
            q['status']='coverage-unknown-malformed-result';q['errors'].append('unusable per-query result');continue
        records=result.get('vulns',[])
        for item in records:
            if not isinstance(item,dict) or not isinstance(item.get('id'),str) or not re.fullmatch(r'[A-Za-z0-9_.:-]+',item['id']):
                q['errors'].append('returned vulnerability without safely queryable exact ID');continue
            if item['id'] not in q['advisory_ids']:q['advisory_ids'].append(item['id'])
        next_token=result.get('next_page_token')
        if next_token:
            if not isinstance(next_token,str) or next_token in seen_tokens[index]:
                q['status']='coverage-unknown-invalid-or-repeated-page-token';q['errors'].append('pagination token invalid/repeated; retained without retry')
            else:
                seen_tokens[index].add(next_token);following.append((index,next_token));q['status']='pagination-incomplete'
        else:
            q['pagination_complete']=True
            q['status']='coverage-unknown-malformed-vulnerability' if q['errors'] else 'OSV-advisory-records-returned' if q['advisory_ids'] else 'no-known-OSV-records-returned-for-exact-query'
    pending=following
for index,token in pending:
    queries[index]['status']='coverage-unknown-public-envelope-exhausted';queries[index]['errors'].append('unread pagination remains');queries[index]['unread_page_token']=token

advisories=[]
for advisory_id in sorted({v for q in queries for v in q['advisory_ids']}):
    receipt=request('advisory-'+advisory_id,'https://api.osv.dev/v1/vulns/'+quote(advisory_id,safe=''))
    value=None
    if receipt.get('response_complete'):
        try:value=json.loads((OWNED/receipt['receipt_directory']/'response-body.bin').read_bytes())
        except (ValueError,UnicodeError):pass
    valid=isinstance(value,dict) and value.get('id')==advisory_id
    advisories.append({'requested_id':advisory_id,'detail_status':'official-record-retained' if valid else 'detail-coverage-unknown',
                       'receipt':receipt,'queried_by':[q['query_index'] for q in queries if advisory_id in q['advisory_ids']],
                       'record':value if valid else None})

for component in component_map:
    index=component['query_index']
    if index is not None:component.update(query_status=queries[index]['status'],advisory_ids=queries[index]['advisory_ids'],pagination_complete=queries[index]['pagination_complete'])
summary={'graph_components':len(graph['components']),'Maven_query_count':len(queries),'project_unqueryable_count':16,
         'query_status_counts':dict(collections.Counter(q['status'] for q in queries)),
         'distinct_returned_advisory_ids':len(advisories),'official_details_retained':sum(a['detail_status']=='official-record-retained' for a in advisories),
         'public_request_count':len(receipts),'started_utc':started_utc,'finished_utc':utc(),'whole_public_actual_seconds':round(time.monotonic()-start,6),
         'AAB_built':False,'packaged_SBOM_complete':False,'ARC09_closed':False,'security_acceptance':False,'license_approval':False,'exploitability_established':False}
result={'format':'collect-selected-runtime-osv-readback-v1','summary':summary,'queries':queries,'components':component_map,'advisories':advisories,'public_requests':receipts}
write_json(OWNED/'query-results.json',result)
write_json(OWNED/'source-fences.json',{'format':'collect-selected-runtime-advisory-source-fences-v1','sealed_graph':{'path':str(GRAPH),'sha256':GRAPH_SHA,'bytes':len(raw)},
            'sealed_readback':{'path':str(readback_path),'sha256':sha(readback_raw),'bytes':len(readback_raw),'record':readback},
            'source_graph_equal_after_query':sha(GRAPH.read_bytes())==GRAPH_SHA,'source_readback_equal_after_query':sha(readback_path.read_bytes())==sha(readback_raw),
            'root_native_build_ownership_preserved':True,'maintained_source_APP_SDK_DB_writes':0,'Gradle_mapper_or_tests_run':False,
            'original_whole_driver_failure_preserved':readback['original_monitor_failure_preserved'],'actual_packaged_AAB_not_claimed':True})
print(json.dumps(summary,indent=2),flush=True)

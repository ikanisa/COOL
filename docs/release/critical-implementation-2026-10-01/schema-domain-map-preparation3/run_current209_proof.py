#!/usr/bin/env python3
"""Bounded private parse/generate/readback only; no SQL/runtime execution."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import time

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
RELEASE=HERE.parent
INTEGRATION=RELEASE/'root-tooling-source-integration1'
BASELINE=INTEGRATION/'generated-current209-complete-qa'
REPLAY=RELEASE/'ordinary-schema-catalog209-execution1/observed-output'
CATALOGS=[REPLAY/'ordinary_clean/final-effective-catalog.json',REPLAY/'ordinary_populated/final-effective-catalog.json']
GENERATOR=HERE/'collect_schema_domain_map.py'
OUTPUT=HERE/'generated-current209-lineage1'
ENV={'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','TMPDIR':'/private/tmp'}

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def save(name,value):
    with (HERE/name).open('x') as out:
        json.dump(value,out,indent=2,sort_keys=True);out.write('\n');out.flush();os.fsync(out.fileno())

def fingerprint(path):
    before=path.lstat()
    if path.resolve()!=path or not stat.S_ISREG(before.st_mode) or before.st_nlink!=1:raise ValueError('unsafe input: '+str(path))
    data=path.read_bytes();after=path.lstat()
    keys=('st_dev','st_ino','st_mode','st_nlink','st_size','st_mtime_ns','st_ctime_ns','st_uid','st_gid')
    if any(getattr(before,key)!=getattr(after,key) for key in keys):raise ValueError('input read race')
    return dict(sha256=hashlib.sha256(data).hexdigest(),bytes=before.st_size,device=before.st_dev,inode=before.st_ino,
        mode=before.st_mode,nlink=before.st_nlink,mtime_ns=before.st_mtime_ns,ctime_ns=before.st_ctime_ns,uid=before.st_uid,gid=before.st_gid)

def group_exists(pid):
    try:os.killpg(pid,0);return True
    except ProcessLookupError:return False

def run(name,argv):
    started=time.monotonic();proc=subprocess.Popen(argv,cwd=ROOT,env=ENV,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    timeout=False
    try:stdout,stderr=proc.communicate(timeout=120)
    except subprocess.TimeoutExpired:
        timeout=True;os.killpg(proc.pid,signal.SIGTERM)
        try:stdout,stderr=proc.communicate(timeout=3)
        except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);stdout,stderr=proc.communicate(timeout=3)
    residual=group_exists(proc.pid)
    if residual:os.killpg(proc.pid,signal.SIGKILL)
    for suffix,data in (('.stdout',stdout),('.stderr',stderr)):
        with (HERE/(name+suffix)).open('xb') as out:out.write(data)
    receipt=dict(argv=argv,cwd=str(ROOT),environment=ENV,deadline_seconds=120,actual_seconds=round(time.monotonic()-started,3),exit_code=proc.returncode,timed_out=timeout,residual_process_group_required_stop=residual,owned_process_group_absent=not group_exists(proc.pid),stdout_sha256=hashlib.sha256(stdout).hexdigest(),stderr_sha256=hashlib.sha256(stderr).hexdigest())
    save(name+'.json',receipt)
    if timeout or proc.returncode or residual or not receipt['owned_process_group_absent']:raise ValueError('failed bounded process: '+name)
    print(name+' PASS '+str(receipt['actual_seconds'])+'s',flush=True)
    return receipt,json.loads(stdout)

def main():
    if OUTPUT.exists():raise ValueError('fresh unique output must be absent')
    current=json.loads((HERE/'current-authorized-inputs-before.json').read_text())
    for name,expected in current['maintained12'].items():
        if fingerprint(Path(name))!=expected:raise ValueError('authorized current12 identity drift')
    baseline_manifest=json.loads((BASELINE/'input-manifest.json').read_text())
    paths={Path(i['path']) if Path(i['path']).is_absolute() else ROOT/i['path'] for i in baseline_manifest['inputs']}
    paths.update([GENERATOR,HERE/'collect_schema_domain_caller_seams.json',HERE/'focused_tests.py',HERE/'original_tests.py',Path(__file__).resolve(),Path(sys.executable).resolve()])
    paths.update(p for p in BASELINE.iterdir() if p.is_file())
    before={str(path):fingerprint(path) for path in sorted(paths)}
    save('transitive-inputs-before.json',before)
    differences=[i['path'] for i in baseline_manifest['inputs'] if before[str(Path(i['path']) if Path(i['path']).is_absolute() else ROOT/i['path'])]['sha256']!=i['sha256']]
    if differences!=['scripts/supabase_cli_helpers.sh']:raise ValueError('unexpected dated baseline differences: '+str(differences))
    commands={}
    command,coverage=run('current209-generation',[sys.executable,'-I','-B',str(GENERATOR),'--root',str(ROOT),'--catalog',str(CATALOGS[0]),'--catalog',str(CATALOGS[1]),'--replay-migrations',str(REPLAY/'captured-migrations'),'--output',str(OUTPUT),'--require-current'])
    commands['generation']=command
    command,verification=run('current209-full-semantic-readback',[sys.executable,'-I','-B',str(GENERATOR),'--root',str(ROOT),'--output',str(OUTPUT),'--verify','--require-current'])
    commands['verification']=command
    after={str(path):fingerprint(path) for path in sorted(paths)}
    save('transitive-inputs-after.json',after)
    if before!=after:raise ValueError('full current input identity drift')
    doc=json.loads((OUTPUT/'schema-domain-map.json').read_text());old=json.loads((BASELINE/'schema-domain-map.json').read_text());catalog=json.loads(CATALOGS[0].read_text())
    for kind,key in [('schema','schemas'),('relation','relations'),('function','functions'),('type','types')]:
        if [o['catalog_row'] for o in doc['objects'] if o['kind']==kind]!=catalog[key]:raise ValueError('raw catalog row loss')
    expected={k:v for k,v in catalog.items() if k not in {'schemas','relations','functions','types'}}
    if doc['catalog_supporting_records']!=expected:raise ValueError('catalog category loss')
    if doc['grants']!=old['grants'] or len(doc['grants'])!=4157:raise ValueError('grant drift')
    if doc['reviewed_caller_seams']!=old['reviewed_caller_seams'] or len(doc['reviewed_caller_seams'])!=18:raise ValueError('caller seam drift')
    gaps=json.loads((OUTPUT/'gaps.json').read_text());oldgaps=json.loads((BASELINE/'gaps.json').read_text())
    resolved={r['identity'] for r in gaps['function_body_match_review'] if r['resolved']}
    expected_resolved={'collect_hybrid.roster_revision_receipt_v149_frozen(p_revision uuid)','public.collect_operations_legacy_configure_policy_v1(p_request_id uuid, p_expected_revision bigint, p_mode text, p_emergency_stop boolean, p_reason_code text)'}
    if resolved!=expected_resolved:raise ValueError('unexpected static-lineage recoveries: '+str(resolved))
    if {r['identity'] for r in gaps['function_body_match_review']}!=set(oldgaps['functions_without_exact_body_match']):raise ValueError('original127 review coverage loss')
    if set(gaps['functions_without_exact_body_match'])!=set(oldgaps['functions_without_exact_body_match'])-resolved:raise ValueError('open gap normalization')
    if coverage['functions_without_exact_body_hash_match_by_scope']!={'platform-schema':91,'application-schema-or-public':34}:raise ValueError('unexpected gap scope counts')
    if coverage['maintained_source_files']!=664 or coverage['catalog_migrations']!=209:raise ValueError('scope drift')
    if len(catalog)!=20 or verification['semantic_output_files_verified']!=5 or verification['status']!='PASS':raise ValueError('required semantic verification absent')
    generated_manifest=json.loads((OUTPUT/'input-manifest.json').read_text())
    admitted={i['path'] for i in generated_manifest['inputs'] if i['kind']=='maintained-caller-source'}
    if not {'scripts/qa/backend_release_delivery.py','scripts/qa/postgres_admission.py'}<=admitted:raise ValueError('QA scope lost')
    for item in generated_manifest['inputs']:
        path=Path(item['path']);path=path if path.is_absolute() else ROOT/path
        if digest(path)!=item['sha256']:raise ValueError('generated manifest drift')
    save('current209-result.json',dict(status='PASS',commands=commands,coverage=coverage,full_semantic_verification=verification,
        all20_catalog_categories_and_raw_rows_preserved=True,all4157_grants_preserved=True,all18_reviewed_caller_seams_preserved=True,
        maintained664_QA_scope_preserved=True,original127_gap_records_reasoned=True,only2_static_rename_gaps_resolved=sorted(resolved),
        dynamic27_plus2_plus5_still_unresolved=True,platform91_distinct_and_unresolved=True,current12_and_full_transitive_identities_unchanged=True,
        dated_baseline_helper_only_authorized_change=differences,input_files=len(generated_manifest['inputs']),maintained_writes=False,
        SQL_Docker_runtime_installation_or_provider_execution=False,business_owner_assignments_verified=False,runtime_call_graph_complete=False,
        promotion_or_release_admission_issued=False))
    print('PASS two exact static aliases;125 open gaps; all5 semantic outputs/current inputs preserved',flush=True)

if __name__=='__main__':
    try:main()
    except Exception as error:
        save('current209-refusal.json',dict(status='REFUSED',error_type=type(error).__name__,reason=str(error),maintained_writes=False));raise

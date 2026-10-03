#!/usr/bin/env python3
"""Bounded private proof; no maintained edits or database/network calls."""
import ast
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
PROOF=Path(__file__).resolve().parent
INTEGRATION=PROOF.parent
AUTHORITY=INTEGRATION/'current-source-after-review-corrections.json'
OUTPUT=INTEGRATION/'generated-current209-complete-qa'
HISTORICAL=INTEGRATION/'generated-current209'
PYTHON=Path('/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3')
GENERATOR=ROOT/'scripts/audits/collect_schema_domain_map.py'
TESTS=ROOT/'scripts/tests/collect_schema_domain_map_test.py'
REPLAY=ROOT/'docs/release/critical-implementation-2026-10-01/ordinary-schema-catalog209-execution1/observed-output'
CATALOGS=[REPLAY/'ordinary_clean/final-effective-catalog.json',REPLAY/'ordinary_populated/final-effective-catalog.json']
CLEAN_ENV={'PATH':'/usr/bin:/bin:/usr/sbin:/sbin'}

def sha(raw):return hashlib.sha256(raw).hexdigest()
def now():return datetime.now(timezone.utc).isoformat()
def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
def save(name,value):(PROOF/name).write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')

def authority_check(authority):
    expected=authority['after_sha256']
    if len(expected)!=12:raise ValueError('authoritative source set is not12 files')
    actual={path:sha((ROOT/path).read_bytes()) for path in expected}
    drift=[path for path in expected if expected[path]!=actual[path]]
    if drift:raise ValueError('authoritative input drift: '+','.join(drift))
    return {'status':'PASS','at_utc':now(),'authority_sha256':sha(AUTHORITY.read_bytes()),'files':actual}

def directory_snapshot(path):
    return [{'path':p.relative_to(path).as_posix(),'sha256':sha(p.read_bytes())} for p in sorted(path.rglob('*')) if p.is_file()]

def load_generator():
    spec=importlib.util.spec_from_file_location('collect_schema_domain_current_validation',GENERATOR)
    module=importlib.util.module_from_spec(spec);sys.modules[spec.name]=module;spec.loader.exec_module(module)
    return module

def transitive_inputs(module):
    inputs=[]
    catalog=json.loads(CATALOGS[0].read_bytes())
    if len(catalog['migrations'])!=209:raise ValueError('expected current209 catalog')
    module.admit_catalog_paths(CATALOGS)
    if CATALOGS[0].read_bytes()!=CATALOGS[1].read_bytes():raise ValueError('root-sealed catalog bytes differ')
    for path in CATALOGS:
        inputs.append({'path':path.relative_to(ROOT).as_posix(),'sha256':sha(path.read_bytes()),'kind':'effective-catalog'})
    sources,excluded=module.maintained_sources(ROOT)
    for path in sources:
        relative=path.relative_to(ROOT).as_posix()
        inputs.append({'path':relative,'sha256':sha(path.read_bytes()),'kind':'maintained-caller-source','caller_group':module.caller_group(relative)})
    migrations=sorted((ROOT/'supabase/migrations').glob('*.sql'))
    captured=sorted((REPLAY/'captured-migrations').glob('*.sql'))
    if len(migrations)!=209 or [p.name for p in migrations]!=[p.name for p in captured]:raise ValueError('current209 original/replay migration set mismatch')
    for path,replayed in zip(migrations,captured):
        version=path.name.split('_',1)[0];raw=path.read_bytes()
        if raw!=replayed.read_bytes():raise ValueError('replay migration bytes mismatch: '+path.name)
        inputs.append({'path':path.relative_to(ROOT).as_posix(),'sha256':sha(raw),'kind':'original-migration','version':version,'represented_in_catalog':version in catalog['migrations']})
        inputs.append({'path':replayed.relative_to(ROOT).as_posix(),'sha256':sha(replayed.read_bytes()),'kind':'replayed-original-migration','version':version})
    for relative,kind in [('supabase/config.toml','local-platform-config'),('scripts/sql/collect_recovery_source_catalog.sql','catalog-or-platform-setup'),('scripts/sql/receipt_transport_platform_prerequisites.sql','catalog-or-platform-setup'),('scripts/supabase_schema_inventory.sh','catalog-or-platform-setup'),('scripts/audits/collect_migration_history_review.rb','catalog-or-platform-setup'),('scripts/audits/collect_schema_domain_map.py','generator-proposal'),('scripts/audits/collect_schema_domain_caller_seams.json','reviewed-caller-seams')]:
        inputs.append({'path':relative,'sha256':sha((ROOT/relative).read_bytes()),'kind':kind})
    inputs=sorted({(i['kind'],i['path']):i for i in inputs}.values(),key=lambda i:(i['kind'],i['path']))
    required={'scripts/qa/backend_release_delivery.py','scripts/qa/postgres_admission.py'}
    admitted={i['path'] for i in inputs if i['kind']=='maintained-caller-source'}
    if not required<=admitted:raise ValueError('actual QA deployment/admission consumers excluded')
    return {'status':'PASS','at_utc':now(),'input_manifest_sha256':sha(canonical(inputs)),'input_count':len(inputs),'maintained_caller_source_count':len(sources),'actual_qa_consumers_admitted':sorted(required),'inputs':inputs,'excluded_files':excluded}

def group_exists(pid):
    try:os.killpg(pid,0);return True
    except ProcessLookupError:return False

def run(name,argv):
    started=now();timer=time.monotonic();proc=subprocess.Popen(argv,cwd=ROOT,env=CLEAN_ENV,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    timed_out=False
    try:stdout,stderr=proc.communicate(timeout=120)
    except subprocess.TimeoutExpired:
        timed_out=True;os.killpg(proc.pid,signal.SIGTERM)
        try:stdout,stderr=proc.communicate(timeout=3)
        except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);stdout,stderr=proc.communicate(timeout=3)
    residual=group_exists(proc.pid)
    if residual:
        os.killpg(proc.pid,signal.SIGKILL)
        for _ in range(50):
            if not group_exists(proc.pid):break
            time.sleep(.02)
    (PROOF/(name+'.stdout')).write_bytes(stdout);(PROOF/(name+'.stderr')).write_bytes(stderr)
    receipt={'argv':argv,'cwd':str(ROOT),'environment':CLEAN_ENV,'deadline_seconds':120,'pid':proc.pid,'started_utc':started,'finished_utc':now(),'actual_seconds':round(time.monotonic()-timer,3),'exit_code':proc.returncode,'timed_out':timed_out,'residual_process_group_required_stop':residual,'owned_process_group_absent':not group_exists(proc.pid),'stdout_sha256':sha(stdout),'stderr_sha256':sha(stderr)}
    save(name+'.json',receipt)
    print(name,proc.returncode,stdout.decode().strip() or stderr.decode().splitlines()[-1],flush=True)
    if timed_out or proc.returncode or not receipt['owned_process_group_absent']:raise ValueError('actual command failed: '+name)
    return receipt,stdout,stderr

def main():
    if Path(sys.executable)!=PYTHON or not sys.flags.isolated or not sys.dont_write_bytecode:raise ValueError('exact absolute Python -I -B required')
    if OUTPUT.exists():raise ValueError('unique fresh output already exists; preserve it')
    authority=json.loads(AUTHORITY.read_bytes());before=authority_check(authority);save('source12-before.json',before)
    historical_before=directory_snapshot(HISTORICAL);save('historical-output-before.json',historical_before)
    module=load_generator();transitive_before=transitive_inputs(module);save('transitive-inputs-before.json',transitive_before)
    commands={}
    test,_,stderr=run('schema-domain-tests',[str(PYTHON),'-I','-B',str(TESTS)])
    match=re.search(rb'Ran (\d+) tests',stderr)
    if not match or int(match.group(1))!=32:raise ValueError('expected exactly32 actual tests')
    commands['schema-domain-tests']=test
    generate,stdout,_=run('schema-domain-generation',[str(PYTHON),'-I','-B',str(GENERATOR),'--catalog',str(CATALOGS[0]),'--catalog',str(CATALOGS[1]),'--replay-migrations',str(REPLAY/'captured-migrations'),'--output',str(OUTPUT),'--require-current'])
    commands['schema-domain-generation']=generate;coverage=json.loads(stdout)
    verify,stdout,_=run('schema-domain-full-semantic-readback',[str(PYTHON),'-I','-B',str(GENERATOR),'--output',str(OUTPUT),'--verify','--require-current'])
    commands['schema-domain-full-semantic-readback']=verify;readback=json.loads(stdout)
    after=authority_check(authority);save('source12-after.json',after)
    if before['files']!=after['files'] or before['authority_sha256']!=after['authority_sha256']:raise ValueError('authoritative12 hash drift during actual validation')
    transitive_after=transitive_inputs(module);save('transitive-inputs-after.json',transitive_after)
    manifest=json.loads((OUTPUT/'input-manifest.json').read_bytes())
    if transitive_before['inputs']!=transitive_after['inputs'] or manifest['inputs']!=transitive_after['inputs']:raise ValueError('full transitive input manifest drift/mismatch')
    if manifest['excluded_files']!=transitive_after['excluded_files']:raise ValueError('transitive exclusions mismatch')
    historical_after=directory_snapshot(HISTORICAL)
    if historical_before!=historical_after:raise ValueError('historical output drift')
    save('result.json',{'status':'PASS','at_utc':now(),'actual_test_count':32,'commands':commands,'source12_before_after_match':True,'source12_authority_sha256':before['authority_sha256'],'transitive_before_after_and_generated_manifest_match':True,'transitive_input_count':len(manifest['inputs']),'transitive_input_manifest_sha256':transitive_after['input_manifest_sha256'],'actual_qa_consumers_admitted':transitive_after['actual_qa_consumers_admitted'],'historical_generated_current209_preserved':True,'historical_output_files_verified':len(historical_after),'generated_output':str(OUTPUT.relative_to(ROOT)),'generated_output_files':directory_snapshot(OUTPUT),'coverage':coverage,'readback':readback,'maintained_mutations':False,'runtime_or_business_authority_claimed':False,'BE08_closed':False})
    print('PASS source12 unchanged; full transitive inputs and all5 semantic artifacts verified; BE08 remains open',flush=True)

if __name__=='__main__':
    try:main()
    except Exception as error:
        save('refusal.json',{'status':'REFUSED','at_utc':now(),'reason':str(error),'maintained_mutations':False});raise

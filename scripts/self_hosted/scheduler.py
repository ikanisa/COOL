"""Run reviewed scheduler operators inside the private self-hosted network.

Both lanes install inactive. Native extension/custody preparation, provider
readiness, retained probe UUID and activation are distinct explicit operations.
Only the operator container receives the owner connection; functions never do.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import uuid
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.self_hosted.release_operator import Operator
from scripts.self_hosted.configure import private_file,read_env

def operator_cache(op):
    cache=op.root/'private/operator-cache';cache.mkdir(mode=0o700,exist_ok=True)
    for name in ('package.json','package-lock.json'):
        source=op.root/'source/scripts/supabase'/name;target=cache/name
        if target.exists():
            if target.read_bytes()!=source.read_bytes():raise ValueError('Operator dependency cache belongs to another source')
        else:shutil.copy2(source,target)
    return cache

def prepare_dependencies(op):
    config=op.docker_preflight();cache=operator_cache(op)
    op.run([op.docker,'run','--rm','--user',str(os.getuid())+':'+str(os.getgid()),'--read-only','--cap-drop','ALL','--security-opt','no-new-privileges:true',
        '--mount','type=bind,src='+str(cache)+',dst=/operator','--workdir','/operator','--env','NPM_CONFIG_CACHE=/operator/npm-cache',
        '--entrypoint','npm',config['services']['web']['image'],'ci','--omit=dev','--ignore-scripts','--no-audit','--no-fund'],timeout=60)
    lock_sha=hashlib.sha256((cache/'package-lock.json').read_bytes()).hexdigest()
    (cache/'installed-lock.sha256').write_text(lock_sha+'\n')
    return {'operator_dependencies_installed':True,'lock_sha256':lock_sha,'provider_calls':0}

def execute(op,lane,args,readiness=None):
    config=op.docker_preflight();cache=operator_cache(op)
    expected=hashlib.sha256((cache/'package-lock.json').read_bytes()).hexdigest()
    if not (cache/'node_modules/pg/package.json').is_file() or (cache/'installed-lock.sha256').read_text().strip()!=expected:raise ValueError('Prepare exact pinned operator dependencies first')
    keys=json.loads((op.root/'private/keys.json').read_text());public=read_env(op.root/'public.env')
    env={key:public[key] for key in ('COLLECT_DEPLOYMENT_PROFILE','COLLECT_DEPLOYMENT_PROFILE_SHA256')}
    env.update({'COLLECT_DB_CA_PEM':(op.root/'private/db-tls/ca.crt').read_text().strip(),
        'COLLECT_JOBS_DATABASE_URL':'postgres://postgres:'+keys['POSTGRES_PASSWORD']+'@db:5432/postgres',
        'COLLECT_EMAIL_JOBS_DATABASE_URL':'postgres://postgres:'+keys['POSTGRES_PASSWORD']+'@db:5432/postgres',
        'COLLECT_PG_MODULE':'/operator/node_modules/pg','NODE_PATH':'/operator/node_modules'})
    command=[op.docker,'run','--rm','--user',str(os.getuid())+':'+str(os.getgid()),'--network',op.project+'_default','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges:true',
        '--mount','type=bind,src='+str(cache)+',dst=/operator,readonly','--mount','type=bind,src='+str(op.root/'source')+',dst=/source,readonly',
        '--workdir','/source']
    # Docker's --env-file does not implement Compose quoted-value decoding.
    # Use a public bootstrap script to read the exact private JSON instead.
    values=op.root/'private'/('operator-'+uuid.uuid4().hex+'.json')
    with values.open('x') as out:os.chmod(values,0o600);json.dump(env,out)
    command+=['--mount','type=bind,src='+str(values)+',dst=/operator-env.json,readonly']
    if readiness:
        readiness=readiness.absolute();private_file(readiness)
        command+=['--mount','type=bind,src='+str(readiness)+',dst=/readiness.json,readonly']
    module='scripts/supabase/jobs_operator.mjs' if lane=='main' else 'scripts/supabase/email_jobs_operator.mjs'
    bootstrap="const fs=require('node:fs'),cp=require('node:child_process');const e=JSON.parse(fs.readFileSync('/operator-env.json','utf8'));const r=cp.spawnSync(process.execPath,process.argv.slice(1),{env:{PATH:process.env.PATH,...e},stdio:'inherit'});process.exit(r.status??1);"
    command+=['--entrypoint','node',config['services']['web']['image'],'-e',bootstrap,module,*args]
    try:
        data=op.run(command,timeout=60).decode()
        if len(data)>131072:raise ValueError('Operator response exceeds bounded metadata contract')
        return [json.loads(line) for line in data.splitlines() if line.strip()]
    finally:values.unlink(missing_ok=True)

def native_custody(op):
    op.docker_preflight()
    keys=json.loads((op.root/'private/keys.json').read_text())
    for key in ('COLLECT_JOB_TOKEN','COLLECT_EMAIL_JOB_TOKEN'):
        if len(keys[key])<32 or any(c not in 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-' for c in keys[key]):raise ValueError('Generated dedicated scheduler token required')
    # Dedicated Collect installation only. No extension is dropped/replaced,
    # no key is rotated and no pre-existing Vault secret is overwritten.
    sql="SELECT private.collect_assert_deployment('"+op.meta['profile_sha256']+"');BEGIN;CREATE EXTENSION IF NOT EXISTS pg_cron;CREATE EXTENSION IF NOT EXISTS pg_net;CREATE EXTENSION IF NOT EXISTS supabase_vault;REVOKE ALL ON SCHEMA vault,net FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer,collect_sms_runtime;REVOKE ALL ON ALL TABLES IN SCHEMA vault,net FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer,collect_sms_runtime;REVOKE ALL ON ALL SEQUENCES IN SCHEMA vault,net FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer,collect_sms_runtime;REVOKE ALL ON ALL FUNCTIONS IN SCHEMA vault,net FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer,collect_sms_runtime;"
    for key,name in [('COLLECT_JOB_TOKEN','collect_job_token_v1'),('COLLECT_EMAIL_JOB_TOKEN','collect_email_job_token_v1')]:
        token_sha=hashlib.sha256(keys[key].encode()).hexdigest()
        commitment='collect.selfhost.scheduler-token.v1:'+token_sha
        sql+="DO $$DECLARE n integer;BEGIN SELECT count(*) INTO n FROM vault.secrets WHERE name='"+name+"';IF n=0 THEN PERFORM vault.create_secret('"+keys[key]+"','"+name+"','"+commitment+"');ELSIF n<>1 OR NOT EXISTS(SELECT 1 FROM vault.secrets WHERE name='"+name+"' AND description='"+commitment+"') OR NOT EXISTS(SELECT 1 FROM vault.decrypted_secrets WHERE name='"+name+"' AND encode(sha256(convert_to(decrypted_secret,'UTF8')),'hex')='"+token_sha+"') THEN RAISE EXCEPTION 'existing_scheduler_secret_requires_independent_reconciliation';END IF;END$$;"
    op.sql(sql+'COMMIT;')
    return {'native_dependencies_configured':True,'vault_references':['collect_job_token_v1','collect_email_job_token_v1'],'plaintext_returned':False,'cron_activated':False}

def install_email(op):
    config=op.docker_preflight();public=read_env(op.root/'public.env')
    # Rendering requires only built-in Node modules and public identity.
    script="import {renderEmailSql} from './scripts/supabase/email_jobs_operator.mjs';process.env.COLLECT_DEPLOYMENT_PROFILE=process.argv[1];process.env.COLLECT_DEPLOYMENT_PROFILE_SHA256=process.argv[2];process.stdout.write(JSON.stringify(await renderEmailSql()));"
    artifact=json.loads(op.run([op.docker,'run','--rm','--network','none','--read-only','--cap-drop','ALL','--mount','type=bind,src='+str(op.root/'source')+',dst=/source,readonly','--workdir','/source','--entrypoint','node',config['services']['web']['image'],'--input-type=module','-e',script,public['COLLECT_DEPLOYMENT_PROFILE'],public['COLLECT_DEPLOYMENT_PROFILE_SHA256']]).decode())
    rendered=artifact['sql']
    if len(rendered)>1024*1024 or '__PROFILE_SHA256__' in rendered:raise ValueError('Exact bounded rendered email template required')
    existing=op.sql("SELECT to_regclass('collect_ops.email_config') IS NOT NULL;").decode().strip()
    if existing=='t':
        state=execute(op,'email',['status'])
        if len(state)!=1 or any(state[0].get(key)!=value for key,value in {'config_sha256':artifact['configSha'],'template_sha256':artifact['templateSha'],'profile_sha256':op.meta['profile_sha256'],'endpoint':op.profile['supabase_origin']+'/functions/v1/collect-email-jobs','enabled':False,'cron_active':False}.items()):raise ValueError('Existing email lane must match the exact inactive artifact; no replacement attempted')
        return {'reconciled_existing':True,'email_installed_inactive':True,'state':state[0]}
    if existing!='f':raise ValueError('Email installation state unconfirmed')
    op.sql(rendered)
    return {'email_installed_inactive':True,'sql_sha256':hashlib.sha256(rendered.encode()).hexdigest()}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--release',type=Path,required=True);p.add_argument('--lane',choices=['main','email'],default='main');p.add_argument('action',choices=['prepare-dependencies','prepare-native-custody','install-inactive','status','probe','reconcile','activate','pause','review-unknown']);p.add_argument('--readiness',type=Path);p.add_argument('--dispatch-id',type=uuid.UUID);p.add_argument('--evidence-sha256');p.add_argument('--apply',action='store_true');a=p.parse_args()
    try:
        op=Operator(a.release)
        if a.action!='status' and not a.apply:result={'action':a.action,'lane':a.lane,'planned':True,'applied':False}
        elif a.action=='prepare-dependencies':result=prepare_dependencies(op)
        elif a.action=='prepare-native-custody':result=native_custody(op)
        elif a.lane=='email' and a.action=='install-inactive':result=install_email(op)
        elif a.lane=='main':
            command=[{'pause':'deactivate'}.get(a.action,a.action)]
            if a.apply:command+=['--apply']
            if a.readiness:command+=['--readiness','/readiness.json']
            if a.dispatch_id:command+=['--dispatch-id',str(a.dispatch_id)]
            if a.evidence_sha256:command+=['--evidence-sha256',a.evidence_sha256]
            if a.action in ('probe','review-unknown') and not a.dispatch_id:raise ValueError('Retained original dispatch UUID required')
            result=execute(op,'main',command,a.readiness)
        else:
            if a.action=='probe':
                if not a.readiness or not a.dispatch_id:raise ValueError('Reviewed readiness and original dispatch UUID required')
                execute(op,'email',['readiness','/readiness.json'],a.readiness);command=['probe',str(a.dispatch_id)]
            elif a.action in ('activate','review-unknown'):
                if not a.evidence_sha256:raise ValueError('Exact review evidence digest required')
                command=[a.action,*([str(a.dispatch_id)] if a.action=='review-unknown' and a.dispatch_id else []),a.evidence_sha256]
            else:command=[a.action]
            result=execute(op,'email',command,a.readiness)
        print(json.dumps(result,sort_keys=True))
    except (OSError,ValueError,KeyError,RuntimeError) as error:
        print(json.dumps({'status':'refused_or_unconfirmed','error_class':type(error).__name__,'private_values_disclosed':False}),file=sys.stderr);sys.exit(1)

"""Root-only finite SQL qualification on the exact newly owned CURRENT32 clone.

No production target, Docker lifecycle, provider, timestamp backdating, trigger
disablement or original-request replay. Retain the snapshot and the test clone.
The VM witness supplied to SQL here is explicitly synthetic contract evidence;
only the separate protected c638 host validation proves actual VM cessation.
"""
from pathlib import Path
import argparse
from contextlib import contextmanager
import datetime
import hashlib
import json
import os
import re
import select
import subprocess
import sys
import time
from types import SimpleNamespace
import uuid

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.self_hosted.database import DatabaseInstaller,migrations,transaction_sql,literal
from scripts.self_hosted.retained_snapshot import Docker,verify_snapshot,require_owned_fresh_clone,physical_directory

MIGRATION='20261110181002_collect_local_stopped_admission.sql'
HEX=re.compile(r'[a-f0-9]{64}\Z')
DATA_TABLES=('auth.users','auth.sessions','app.users','app.auth_sessions','app.admin_users','app.admin_grants',
             'app.payments','app.ledger_entries','app.sms_receipts','app.momo_transactions','app.momo_processing_jobs',
             'private.burimunsi_accounts','private.burimunsi_device_grants')
canonical=lambda v:json.dumps(v,sort_keys=True,separators=(',',':')).encode()
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()


def need(ok,message):
    if not ok:raise ValueError(message)


def save(path,value):
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'w') as h:json.dump(value,h,indent=2);h.write('\n');h.flush();os.fsync(h.fileno())
    fd=os.open(path.parent,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
    try:os.fsync(fd)
    finally:os.close(fd)


def metadata_sql(admission):
    hashes=[]
    for relation in DATA_TABLES:
        hashes.extend([literal(relation),"(SELECT encode(sha256(convert_to(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb)::text,'UTF8')),'hex') FROM "+relation+' t)'])
    return "SELECT jsonb_build_object('major',current_setting('server_version_num')::int/10000,'database',current_database(),"+\
      "'boot',to_jsonb(pg_postmaster_start_time()),'profile',(SELECT profile_sha256 FROM private.collect_deployment_identity WHERE singleton),"+\
      "'control',(SELECT to_jsonb(c) FROM private.collect_fence_control c WHERE singleton),"+\
      "'admission',(SELECT to_jsonb(a) FROM private.collect_fence_admissions a WHERE admission_id="+literal(admission)+"::uuid),"+\
      "'journal',(SELECT jsonb_agg(to_jsonb(s) ORDER BY version) FROM supabase_migrations.collect_installation_steps s),"+\
      "'local_schema',to_regclass('private.collect_fence_local_stopped_admissions') IS NOT NULL,"+\
      "'scheduler',private._collect_fence_scheduler_status(),'role_hash',(SELECT encode(sha256(convert_to(jsonb_agg(jsonb_build_object('name',rolname,'super',rolsuper,'bypass',rolbypassrls,'inherit',rolinherit,'login',rolcanlogin,'create_role',rolcreaterole,'create_db',rolcreatedb,'replication',rolreplication) ORDER BY rolname)::text,'UTF8')),'hex') FROM pg_roles),"+\
      "'data_hashes',jsonb_build_object("+','.join(hashes)+"));"


def require_actual32(before,records,args):
    need(len(records)==35 and records[32]['name']==MIGRATION,'Exact new35 chain required')
    need(before['major']==17 and before['database']=='postgres' and before['profile']==args.profile_sha256
         and before['local_schema'] is False,'Exact retained32/profile before repair required')
    rows=before['journal']
    need(len(rows)==32 and [r['version'] for r in rows]==[r['name'] for r in records[:32]]
         and all(row['source_sha256']==record['sha256'] and row['profile_sha256']==args.profile_sha256 for row,record in zip(rows,records)),
         'Actual first32 journal must match exact reviewed prefix')
    c=before['control'];a=before['admission']
    need(c['mode']=='quiescing' and c['epoch']==args.epoch and c['source_sha256']==args.source_sha256
         and c['operation_id']==args.fence_operation,'Original committed quiesce required; never begin again')
    need(a and a['admission_id']==args.admission_id and a['epoch']==args.epoch and a['source_sha256']==args.source_sha256
         and a['kind']=='http_admin' and a['state'] in ('active','unresolved'),'Exact original old admission required')
    created=datetime.datetime.fromisoformat(a['created_at'].replace('Z','+00:00'))
    boot=datetime.datetime.fromisoformat(before['boot'].replace('Z','+00:00'))
    need(created<boot,'Original restored timestamp must actually precede QA postmaster boot; no backdating')
    need(before['scheduler'].get('blocking') is False,'Current32 scheduler must already be clear')


class UnknownOutcome(RuntimeError):pass


def observed_oid(value):
    # PG's to_jsonb(oid) uses a JSON string; keep strict ASCII uint32 syntax.
    if isinstance(value,str):
        need(re.fullmatch(r'[1-9][0-9]{0,9}',value) is not None,'Canonical observed PostgreSQL OID required')
        value=int(value)
    need(type(value) is int and 1<=value<=4294967295,'Positive observed PostgreSQL OID required')
    return value


def require_upgrade_ack(value,epoch,source,operation):
    need(isinstance(value,dict) and value.get('contractVersion')==3 and value.get('found') is True,
         'Source upgrade receipt envelope required')
    control=value.get('control')
    need(isinstance(control,dict) and control.get('mode')=='fenced' and control.get('epoch')==epoch
         and control.get('source_sha256')==source and control.get('operation_id')==operation,
         'Separate source upgrade control ACK required')
    return value


def qualify(args):
    need(HEX.fullmatch(args.clone_id) and HEX.fullmatch(args.source_sha256) and HEX.fullmatch(args.profile_sha256),'Exact clone/source/profile IDs required')
    args.admission_id=str(uuid.UUID(args.admission_id));args.fence_operation=str(uuid.UUID(args.fence_operation))
    records=migrations(ROOT)
    snapshot_dir=physical_directory(args.snapshot_directory);snapshot=verify_snapshot(snapshot_dir)
    clone=json.loads((snapshot_dir/'clone.json').read_text())
    need(clone['container_id']==args.clone_id and clone['operation_id']==snapshot['operation_id']
         and clone['source_container_id']==snapshot['source_container_id'],'Exact captured CURRENT32 clone binding required')
    if not args.execute:return {'planned':True,'executed':False,'clone_id':args.clone_id,'new_migration':MIGRATION,'production_acceptance':False}
    output=physical_directory(args.directory,fresh=True);docker=Docker(snapshot['docker_host'],output)
    def owned():require_owned_fresh_clone(docker.inspect(args.clone_id),snapshot,args.clone_id,clone['volume'])
    argv=docker.argv+['exec','-i',args.clone_id,'psql','-h','/tmp','-U','postgres','-d','postgres','-XAtq','--no-password','-v','ON_ERROR_STOP=1']
    checks=[];serial=0
    save(output/'qualification-intent.json',{'clone_id':args.clone_id,'snapshot_operation_id':snapshot['operation_id'],
        'source_container_id':snapshot['source_container_id'],'original_admission_id':args.admission_id,
        'original_fence_operation':args.fence_operation,'original_source':args.source_sha256,'epoch':args.epoch,
        'operator_sha256':digest(Path(__file__)),'automatic_replay':False,'provider_calls':0,'production_acceptance':False})
    def sql(text,*,expect=None,expect_message=None,name=None,timeout=120,user='postgres'):
        nonlocal serial
        need(user in ('postgres','supabase_admin'),'Only genuine owned-QA owner/bootstrap sessions allowed')
        owned();serial+=1;name=name or 'sql-'+f'{serial:03d}'
        save(output/(name+'-intent.json'),{'sql_sha256':hashlib.sha256(text.encode()).hexdigest(),'expected_sqlstate':expect,'automatic_replay':False})
        stdout=output/(name+'.private.stdout');stderr=output/(name+'.private.stderr')
        with stdout.open('xb') as out,stderr.open('xb') as err:
            os.chmod(stdout,0o600);os.chmod(stderr,0o600)
            selected_argv=list(argv);selected_argv[selected_argv.index('-U')+1]=user
            process=subprocess.Popen(selected_argv,stdin=subprocess.PIPE,stdout=out,stderr=err,start_new_session=True)
            try:process.communicate(('\\set VERBOSITY verbose\nSET TIME ZONE \'UTC\';\n'+text).encode(),timeout=timeout)
            except subprocess.TimeoutExpired:
                save(output/(name+'-result.json'),{'acknowledged':False,'pid':process.pid,'process_left_untouched':True,'automatic_replay':False})
                raise UnknownOutcome('QA statement outcome unknown; clone and processes quarantined') from None
        error=stderr.read_text(errors='replace');observed=stdout.read_bytes()
        save(output/(name+'-result.json'),{'acknowledged':True,'exit_code':process.returncode,'stdout_sha256':digest(stdout),'stderr_sha256':digest(stderr),'automatic_replay':False})
        if expect:
            need(process.returncode!=0 and re.search(r'ERROR:\s+'+re.escape(expect)+r':',error),'Exact expected SQL refusal unconfirmed')
            if expect_message:need(expect_message in error,'Exact expected refusal branch unconfirmed')
        else:need(process.returncode==0,'QA SQL failed; retained private diagnostics')
        return observed
    @contextmanager
    def lease(key,label):
        owned();token='LOCAL_LEASE_'+uuid.uuid4().hex
        save(output/(label+'-intent.json'),{'key':key,'clone_id':args.clone_id,'automatic_replay':False,'backend_termination_allowed':False})
        error_path=output/(label+'.private.stderr');error=error_path.open('xb');os.chmod(error_path,0o600)
        process=subprocess.Popen(argv,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=error,start_new_session=True)
        text="BEGIN;SET LOCAL statement_timeout='10s';SELECT pg_advisory_xact_lock_shared(7346371,"+str(key)+");\n\\echo "+token+'\n'
        process.stdin.write(text.encode());process.stdin.flush();observed=b'';deadline=time.monotonic()+15
        try:
            while (token+'\n').encode() not in observed:
                need(process.poll() is None and time.monotonic()<deadline,'Owned QA lease not acknowledged')
                ready,_,_=select.select([process.stdout],[],[],max(0,deadline-time.monotonic()))
                if ready:
                    chunk=os.read(process.stdout.fileno(),8192);need(bool(chunk),'Owned QA lease ended early');observed+=chunk
            save(output/(label+'-ready.json'),{'pid':process.pid,'key':key,'positive_ready':True,'clone_id':args.clone_id})
            unknown=False
            try:yield
            except UnknownOutcome:unknown=True;raise
            finally:
              if not unknown:
                process.stdin.write(('ROLLBACK;\n\\echo '+token+'_RELEASED\n\\q\n').encode());process.stdin.flush();process.stdin.close()
                try:process.wait(timeout=15)
                except subprocess.TimeoutExpired:raise UnknownOutcome('QA lease cleanup unconfirmed; left untouched') from None
                observed+=process.stdout.read()
                need(process.returncode==0 and (token+'_RELEASED\n').encode() in observed,'Positive original QA lease cleanup required')
                save(output/(label+'-released.json'),{'exit_code':0,'original_rollback_acknowledged':True,'backend_terminated':False})
        finally:
            error.close()
            with (output/(label+'.private.stdout')).open('xb') as handle:os.chmod(handle.name,0o600);handle.write(observed)
    before=json.loads(sql('BEGIN READ ONLY;'+metadata_sql(args.admission_id)+'COMMIT;',name='before-readonly'))
    require_actual32(before,records,args);save(output/'before.private.json',before)
    meta={'profile_sha256':args.profile_sha256,'source_sha256':hashlib.sha256(canonical(records)).hexdigest()}
    candidate=output/'candidate';source=candidate/'source'
    for relative in ('deploy/self-hosted/migrations.lock.json',*('supabase/migrations/'+r['name'] for r in records)):
        target_path=source/relative;target_path.parent.mkdir(parents=True,exist_ok=True)
        with target_path.open('xb') as handle:handle.write((ROOT/relative).read_bytes())
        need(digest(target_path)==digest(ROOT/relative),'Exact qualification migration copy required')
    op=SimpleNamespace(root=candidate,meta=meta,profile={},sql=sql)
    installer=DatabaseInstaller(op);target=records[32];migration=(ROOT/'supabase/migrations'/MIGRATION).read_text()
    def unchanged32():
        now=json.loads(sql('BEGIN READ ONLY;'+metadata_sql(args.admission_id)+'COMMIT;'))
        need(now['journal']==before['journal'] and now['admission']==before['admission'] and now['control']==before['control']
             and now['data_hashes']==before['data_hashes'] and now['role_hash']==before['role_hash'] and now['local_schema'] is False,'Known refused install changed CURRENT32')
    for key,label in ((1,'work'),(2,'write')):
        with lease(key,'install-'+label):
            sql(transaction_sql(migration,target,args.profile_sha256,uuid.uuid4()),expect='55P03',name='install-'+label+'-refused')
        unchanged32();checks.append('install_requires_'+label+'_exclusive')
    installed=installer.apply_records([target]);need(installed==[MIGRATION],'Only new33 may be installed')
    after33=json.loads(sql('BEGIN READ ONLY;'+metadata_sql(args.admission_id)+'COMMIT;'))
    need(after33['journal'][:32]==before['journal'] and len(after33['journal'])==33
         and after33['admission']==before['admission'] and after33['control']==before['control']
         and after33['data_hashes']==before['data_hashes'] and after33['role_hash']==before['role_hash'],'New33 must preserve actual32 and raw original')
    checks.append('committed_quiescing_install_preserves32')
    operations={name:str(uuid.uuid4()) for name in ('record','obligation','upgrade','release','fresh','fresh_fence','fresh_release','cf_admission','cf_record','cf_obligation')}
    save(output/'operations.json',operations)
    witness={'format':'collect.local-vm-executor-stopped.v1','vmIdentitySha256':hashlib.sha256(b'QUALIFICATION SYNTHETIC VM WITNESS ONLY').hexdigest(),
        'runtimeVolumeUuid':str(uuid.UUID(snapshot['operation_id'])),'databaseId':args.clone_id,'databaseBootAt':before['boot'],
        'edgeContainerId':'e'*64,'edgeStartedAt':before['boot'],'stoppedBindingSha256':'a'*64,'custodyReceiptSha256':'b'*64,'resumedReceiptSha256':'c'*64}
    def record(*,executor=witness,recovery=None,obligation=None,admission=None,epoch=None,source=None,kind='http_admin',fence=None):
        values=[recovery or operations['record'],fence or args.fence_operation,admission or args.admission_id,
                args.epoch if epoch is None else epoch,source or args.source_sha256,kind,'d'*64,obligation or operations['obligation'],'f'*64]
        return 'SELECT private.collect_fence_record_local_stopped_v1('+','.join(map(literal,values))+','+('NULL' if executor is None else literal(json.dumps(executor,separators=(',',':'))))+');'
    helpers="""CREATE FUNCTION pg_temp.l_check(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'local stopped qualification: %',label;END IF;END$$;
CREATE FUNCTION pg_temp.l_expect(statement text,state text,message text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$BEGIN BEGIN EXECUTE statement;EXCEPTION WHEN OTHERS THEN IF SQLSTATE=state AND(message IS NULL OR SQLERRM=message) THEN RETURN;END IF;RAISE;END;RAISE EXCEPTION 'expected local stopped refusal %',state;END$$;
"""
    def refusal(call,state='55000',message=None):
        return 'SELECT pg_temp.l_expect('+literal(call)+','+literal(state)+(','+literal(message) if message else '')+');\n'
    role_name='collect_cf_preserve_20991231'
    need(json.loads(sql('SELECT to_jsonb(to_regrole('+literal(role_name)+') IS NULL);')) is True,'QA fixture role must not preexist')
    # postgres is genuinely NOSUPERUSER in the retained installation. Use the
    # real isolated bootstrap session only for this create/drop test fixture;
    # every protocol/installer call remains an actual postgres owner session.
    role_oid=observed_oid(json.loads(sql('BEGIN;CREATE ROLE '+role_name+' NOLOGIN;SELECT to_jsonb(oid) FROM pg_roles WHERE rolname='+literal(role_name)+';DROP ROLE '+role_name+';COMMIT;',user='supabase_admin',name='qa-only-role-absence')))
    def cf_record(admission,recovery,obligation):
        values=[recovery,args.fence_operation,'rrlduytparvsjfmegalh',admission,args.epoch,args.source_sha256,'http_admin','a'*64,role_oid,role_name,'b'*64]
        return 'SELECT private.collect_fence_record_stopped_admission_v3('+','.join(map(literal,values))+',true,'+literal(obligation)+','+literal('c'*64)+');'
    cf_row='INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,state) VALUES('+','.join(map(literal,[operations['cf_admission'],args.epoch,args.source_sha256,'http_admin','active']))+');'
    cross=cf_row+cf_record(operations['cf_admission'],operations['cf_record'],operations['cf_obligation'])
    for call in (record(recovery=operations['cf_record']),record(obligation=operations['cf_obligation']),
                 record(admission=operations['cf_admission']),record(recovery=args.admission_id),record(recovery=args.fence_operation)):
        cross+=refusal(call,'55000','collect_stopped_shared_identity_conflict')
    sql('BEGIN;'+helpers+cross+'ROLLBACK;',name='cf-to-local-namespace-refusals')
    for key,label in ((1,'work'),(2,'write')):
        with lease(key,'record-'+label):sql("BEGIN;SET LOCAL lock_timeout='150ms';"+record()+'COMMIT;',expect='55P03',name='record-'+label+'-refused')
        checks.append('record_requires_'+label+'_exclusive')
    sql('BEGIN ISOLATION LEVEL REPEATABLE READ;'+record()+'COMMIT;',expect='55000',expect_message='collect_fence_unavailable',name='repeatable-read-record-refused')
    sql('BEGIN READ ONLY;'+record()+'COMMIT;',expect='55000',expect_message='collect_fence_unavailable',name='readonly-record-refused')
    statements=[]
    for change in [dict(epoch=args.epoch+1),dict(source='9'*64),dict(kind='jobs'),dict(fence=str(uuid.uuid4())),dict(admission=str(uuid.uuid4()))]:
        statements.append(refusal(record(**change)))
    malformed=[[],{},None,{**witness,'extra':'not permitted'},{**witness,'vmIdentitySha256':None},{**witness,'databaseBootAt':'2000-01-01T00:00:00Z'},
               {**witness,'edgeStartedAt':before['admission']['created_at']},{**witness,'custodyReceiptSha256':'x'*9000}]
    for value in malformed:statements.append(refusal(record(executor=value),'22023' if value is None else '55000'))
    statements.extend(refusal('SET LOCAL ROLE '+role+';'+record(),'42501') for role in ('anon','authenticated','service_role','collect_runtime','collect_edge','collect_sms_runtime','collect_sms_edge'))
    # Role errors run independently so SET LOCAL cannot leak between cases.
    for role in ('anon','authenticated','service_role','collect_runtime','collect_edge','collect_sms_runtime','collect_sms_edge'):
        sql('BEGIN;SET LOCAL ROLE '+role+';'+record()+'COMMIT;',expect='42501',name='role-'+role+'-refused')
    statements=statements[:-7]
    sql('BEGIN;'+helpers+''.join(statements)+'ROLLBACK;',name='tuple-metadata-negatives')
    checks.extend(('owner_acl_isolation_and_readonly','exact_tuple_closed_metadata_and_boot'))
    sql('BEGIN;'+record()+'COMMIT;',name='original-record')
    status=json.loads(sql('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;SELECT private.collect_fence_local_stopped_status_v1('+literal(operations['record'])+');COMMIT;',name='original-status-readonly'))
    need(status['found'] is True and status['originalAdmission']==before['admission']
         and status['localStoppedLifecycle']['original_admission_snapshot']==before['admission']
         and status['localStoppedLifecycle']['recovered_external_dispatches'] is None
         and status['localStoppedLifecycle']['recovered_uncertain_dispatches'] is None
         and all(status.get(key) is False for key in ('originalCountersRecovered','runtimeFinishRecovered','unknownObligationSettled','providerSettlement','wholeSystemAcceptance','sb29Satisfied')),
         'Raw original and UNKNOWN must remain truthful')
    save(output/'proof-readonly-status.json',status);checks.append('original_record_and_select_only_ack_recovery')
    negative=refusal('UPDATE private.collect_fence_local_stopped_admissions SET recovered_external_dispatches=0')+\
        refusal('DELETE FROM private.collect_fence_local_stopped_admissions')+refusal('TRUNCATE private.collect_fence_local_stopped_admissions')+\
        refusal('UPDATE private.collect_fence_admissions SET reason=reason WHERE admission_id='+literal(args.admission_id))+\
        refusal('DELETE FROM private.collect_fence_working_admissions WHERE admission_id='+literal(args.admission_id))
    prefix="BEGIN;SET LOCAL ROLE collect_runtime;SET LOCAL collect.edge_verified='true';"
    tuple_args=','.join([literal(args.admission_id),str(args.epoch),literal(args.source_sha256)])
    for name,call in [('work','private.collect_fence_assert_work('+tuple_args+')'),('write','private.collect_fence_assert_write('+tuple_args+')'),
                      ('close','private.collect_fence_close('+tuple_args+",'settled','completed',0,0)")]:
        lock='SELECT pg_advisory_xact_lock_shared(7346371,1);' if name=='work' else ''
        sql(prefix+lock+'SELECT '+call+';COMMIT;',expect='55000',name='late-original-'+name+'-refused')
    sql('BEGIN;'+helpers+negative+'ROLLBACK;',name='immutable-original-and-proof')
    cross=cf_row
    for call in (cf_record(operations['cf_admission'],operations['record'],str(uuid.uuid4())),
                 cf_record(operations['cf_admission'],str(uuid.uuid4()),operations['obligation']),
                 cf_record(args.admission_id,str(uuid.uuid4()),str(uuid.uuid4()))):
        cross+=refusal(call,'55000','collect_stopped_shared_identity_conflict')
    for collision in (operations['record'],operations['obligation'],args.admission_id):
        cross+=refusal('INSERT INTO private.collect_fence_operations(operation_id,action,epoch,source_sha256) VALUES('+','.join(map(literal,[collision,'drain',args.epoch,args.source_sha256]))+');','55000','collect_stopped_operation_conflict')
    sql('BEGIN;'+helpers+cross+'ROLLBACK;',name='local-to-cf-and-control-namespace-refusals')
    checks.append('both_proof_directions_and_control_id_namespaces')
    checks.append('late_original_authority_and_erasure_refused')
    retention="""SELECT pg_temp.l_check(EXISTS(SELECT 1 FROM jsonb_array_elements(private._retention_manifest_catalog_v2()->'private_classes') c
 WHERE c->>'name'='private:collect_fence_local_stopped_admissions' AND c->>'scope'='shared_fence' AND c->'blocked'='true'::jsonb),'blocked shared retention catalog');
SELECT pg_temp.l_check((SELECT jsonb_agg(descriptor) FROM private._retention_manifest_rows_v2('local-stopped-qualification-absent-subject')
 WHERE class_name='private:collect_fence_local_stopped_admissions')=
 '[{"kind":"class","status":"unmapped","subject_count":null,"erasure":"blocked","present":true}]'::jsonb,
 'original manifest path emits only blocked unmapped descriptor, never proof rows');"""
    sql('BEGIN;'+helpers+retention+'ROLLBACK;',name='shared-retention-catalog')
    drained=json.loads(sql('BEGIN;SELECT private.collect_fence_drain_v3('+','.join([literal(args.fence_operation),str(args.epoch),literal(args.source_sha256)])+');COMMIT;',name='same-original-drain'))
    need(drained['mode']=='fenced' and drained['operationId']==args.fence_operation and drained['epoch']==args.epoch
         and drained['rawActiveAdmissions']+drained['rawUnresolvedAdmissions']==1
         and drained['effectiveActiveAdmissions']==drained['effectiveUnresolvedAdmissions']==0
         and drained['stoppedLifecycleProofs']==1 and drained['retainedUnquantifiedUnknownObligations']==1
         and drained['applicationFenceComplete'] is False,'Only same original local lease drain, not external settlement')
    checks.append('same_original_drain_preserves_unknown')
    new_source=meta['source_sha256']
    upgrade_call='SELECT private.collect_fence_upgrade_source_v3('+','.join(map(literal,[operations['upgrade'],args.fence_operation,args.epoch,args.source_sha256,new_source,'1'*64,'2'*64,'3'*64]))+');'
    release_call='SELECT private.collect_fence_release_v3('+','.join([literal(operations['release']),str(args.epoch),literal(args.source_sha256)])+');'
    # One local proof plus9999 real CF protocol rows exercises the SHARED bound.
    # These are SQL-only synthetic table facts; no original timestamp is changed.
    budget="""DO $budget$DECLARE i integer;role_oid oid:=__ROLE_OID__;a uuid;role_name text:='collect_cf_preserve_20991231';BEGIN
 FOR i IN 1..9999 LOOP a:=gen_random_uuid();
 INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,state) VALUES(a,__EPOCH__,__SOURCE__,'http_admin','active');
 PERFORM private.collect_fence_record_stopped_admission_v3(gen_random_uuid(),__FENCE__,'rrlduytparvsjfmegalh',a,__EPOCH__,__SOURCE__,'http_admin',repeat('a',64),role_oid,role_name,repeat('b',64),true,gen_random_uuid(),repeat('c',64));
 END LOOP;
 PERFORM pg_temp.l_check(private._collect_stopped_proof_total()=10000,'shared proof capacity exact');
END;$budget$;
""".replace('__ROLE_OID__',str(role_oid)).replace('__EPOCH__',str(args.epoch)).replace('__SOURCE__',literal(args.source_sha256)).replace('__FENCE__',literal(args.fence_operation))
    full_status="SELECT pg_temp.l_check(private.collect_fence_owner_status_v3()->>'stoppedLifecycleProofs'='10000' AND private._collect_fence_resources()->'capacityBlocked'='false'::jsonb,'combined status and unchanged independent capacityBlocked');"
    budget+=refusal(record(recovery=str(uuid.uuid4()),obligation=str(uuid.uuid4())),'55000','collect_stopped_shared_capacity')
    # CF-only count9999 would permit another row; the local proof must block it.
    cf_next="SELECT private.collect_fence_record_stopped_admission_v3(gen_random_uuid(),"+literal(args.fence_operation)+",'rrlduytparvsjfmegalh',"+literal(args.admission_id)+','+str(args.epoch)+','+literal(args.source_sha256)+",'http_admin',repeat('a',64),1::oid,'collect_cf_preserve_20991231',repeat('b',64),true,gen_random_uuid(),repeat('c',64));"
    budget+=refusal(cf_next,'55000','collect_stopped_shared_capacity')+refusal(upgrade_call,'55000','collect_fence_capacity')+refusal(release_call,'55000','collect_fence_capacity')
    sql('BEGIN;'+helpers+budget+full_status+'ROLLBACK;',name='shared-budget-boundary',timeout=180)
    checks.append('shared10000_budget_both_insert_paths_upgrade_release_and_status')
    upgraded=json.loads(sql('BEGIN;'+upgrade_call+'COMMIT;',name='qualified-source-upgrade'))
    require_upgrade_ack(upgraded,args.epoch+1,new_source,operations['upgrade'])
    opened=json.loads(sql('BEGIN;SELECT private.collect_fence_release_v3('+','.join([literal(operations['release']),str(args.epoch+1),literal(new_source)])+');COMMIT;',name='separate-new-source-release'))
    need(opened['mode']=='open' and opened['epoch']==args.epoch+2 and opened['retainedUnquantifiedUnknownObligations']==1,'Release must retain UNKNOWN obligation')
    fresh=operations['fresh'];epoch=args.epoch+2
    registered=json.loads(sql(prefix+'SELECT private.collect_fence_register('+','.join(map(literal,[fresh,new_source,'http_admin']))+');COMMIT;',name='new-source-admission'))
    need(registered['admissionId']==fresh and registered['epoch']==epoch,'New source/epoch admission required')
    begin='SELECT private.collect_fence_begin_quiesce('+','.join([literal(operations['fresh_fence']),str(epoch),literal(new_source)])+');'
    new_record=record(admission=fresh,epoch=epoch,source=new_source,fence=operations['fresh_fence'],recovery=str(uuid.uuid4()),obligation=str(uuid.uuid4()))
    sql('BEGIN;'+begin+new_record+'COMMIT;',expect='55000',expect_message='collect_local_stopped_committed_quiesce_required',name='uncommitted-new-quiesce-refused')
    sql('BEGIN;'+begin+'COMMIT;',name='qualification-only-fresh-quiesce')
    sql('BEGIN;'+new_record+'COMMIT;',expect='55000',expect_message='collect_local_stopped_executor_unconfirmed',name='actual-current-admission-refused')
    # This fixture itself registered the fresh work and never ran a handler or
    # provider. Its known cancelled-before-work close is not recovery of6bf.
    sql(prefix+'SELECT private.collect_fence_close('+','.join([literal(fresh),str(epoch),literal(new_source)])+",'settled','cancelled_before_work',0,0);COMMIT;",name='known-fresh-fixture-close')
    sql('BEGIN;SELECT private.collect_fence_drain_v3('+','.join([literal(operations['fresh_fence']),str(epoch),literal(new_source)])+');COMMIT;',name='qualification-only-fresh-drain')
    sql('BEGIN;SELECT private.collect_fence_release_v3('+','.join([literal(operations['fresh_release']),str(epoch),literal(new_source)])+');COMMIT;',name='qualification-only-fresh-release')
    checks.append('new_epoch_admission_and_current_or_uncommitted_proof_refusal')
    after=json.loads(sql('BEGIN READ ONLY;'+metadata_sql(args.admission_id)+'COMMIT;',name='final-readonly'))
    need(after['admission']==before['admission'] and after['data_hashes']==before['data_hashes'] and after['role_hash']==before['role_hash']
         and after['journal'][:32]==before['journal'] and len(after['journal'])==33,'Original history/auth/business/financial data must remain unchanged')
    inputs={p.relative_to(ROOT).as_posix():digest(p) for p in (ROOT/'deploy/self-hosted/migrations.lock.json',Path(__file__),*(ROOT/'supabase/migrations'/r['name'] for r in records))}
    result={'format':'collect.local-stopped.current32-qualification.v1','status':'pass','clone_id':args.clone_id,
        'snapshot_operation_id':snapshot['operation_id'],'original_fence_operation':args.fence_operation,'checks':checks,
        'inputs':inputs,'source_sha256':hashlib.sha256(canonical(inputs)).hexdigest(),'first32_preserved':True,
        'new_migrations':[MIGRATION],'raw_original_preserved':True,'unknown_obligation_retained':True,
        'provider_calls':0,'physical_vm_cessation_exercised':False,'fixture_vm_witness_synthetic':True,
        'original_counters_recovered':False,'original_request_replayed':False,'production_acceptance':False,
        'test_clone_retained':True,'original16_fixture_inputs_or_results_modified':False}
    save(output/'after.private.json',after);save(output/'result.json',result)
    return {key:result[key] for key in ('status','checks','clone_id','production_acceptance')}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('snapshot-directory','directory'):parser.add_argument('--'+name,type=Path,required=True)
    for name in ('clone-id','source-sha256','profile-sha256','admission-id','fence-operation'):parser.add_argument('--'+name,required=True)
    parser.add_argument('--epoch',type=int,required=True);parser.add_argument('--execute',action='store_true')
    try:print(json.dumps(qualify(parser.parse_args()),sort_keys=True))
    except Exception as error:raise SystemExit('Local stopped qualification refused/unconfirmed: '+type(error).__name__) from None

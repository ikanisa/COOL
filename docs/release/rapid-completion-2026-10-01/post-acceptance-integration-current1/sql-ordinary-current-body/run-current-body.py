#!/usr/bin/env python3
"""Bounded normal-owner acceptance of the already-reviewed changed read body."""
from pathlib import Path
import datetime, hashlib, json, os, sys, types, uuid

W = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
P = Path(__file__).resolve().parent
B = W/'docs/release/collect-codex-goal-2026-09-30/exception-inbox-audit-v2-20261001/affected-plan-attempt1'
FEATURE = 'supabase/migrations/20261001200000_exception_inbox_audit_v2.sql'
NEW = '7f6aea2058be51ae93b4f25d0dc0463b05f13476d6e41093a355bdc6871033d7'
OLD = 'a83543aa0266eb40ba5abd4c94c26b0db6d3fc8e238929bc2794154a7fa773f9'
EMAIL = '99790000-0000-4000-8000-000000000001'
SID = '99790000-0000-4000-8000-000000010001'
sha = lambda b: hashlib.sha256(b).hexdigest()
q = lambda x: "'" + str(x).replace("'", "''") + "'"
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
allowed = {'HOME','USER','LOGNAME','TMPDIR','PATH','LANG','LC_ALL','LC_CTYPE','SHELL'}
env = {k:v for k,v in os.environ.items() if k in allowed}
os.environ.clear(); os.environ.update(env, PYTHONDONTWRITEBYTECODE='1', PYTHONUTF8='1')
result = dict(kind='ordinary_owner_changed_exception_audit_body', status='running',
              cases=[], phases={}, target={}, started_at=now(),
              shared_database_written=False, hosted_called=False, provider_called=False,
              source_rows_copied=False, signed_jwt_tested=False,
              managed_hosted_owner_parity=False, whole187_current_body_replayed=False,
              query_plan37_repeated=False,
              fixture_limits=['Owner-normalized row-free schema153 plus captured18-stage predecessor setup before demotion.',
                              'Mock cron catalogs; no scheduler, Vault, net, Auth service or signed-JWT invocation.',
                              'Only the current v2 feature install/replacement and reads are fresh ordinary-owner acceptance.'])
def save():
    (P/'result.json').write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')
def case(name, ok):
    result['cases'].append({'name':name,'status':'pass' if ok else 'failed'})
    save(); print(('PASS ' if ok else 'FAIL ')+name, flush=True)
    if not ok: raise AssertionError(name)
def retain(name, value):
    (P/name).write_text(json.dumps(value, indent=2, sort_keys=True)+'\n')
def function_parts(text):
    a = text.index('create function public.admin_get_exception_entity_audit_v2(')
    b = text.index('end$$;', a)+len('end$$;')
    return text[:a], text[a:b], text[b:]

target = None
try:
    proof = json.loads((B/'result.json').read_text())
    assert proof['status']=='pass' and len(proof['cases'])==37 and proof['sources_unchanged'] is True
    bodies = {path:(B/'executed-inputs'/path).read_bytes() for path in proof['source_sha256']}
    assert all(sha(bodies[path])==digest for path,digest in proof['source_sha256'].items())
    baseline = {path:(B/'executed-inputs'/path).read_bytes() for path in proof['baseline_sha256']}
    assert all(sha(baseline[path])==digest for path,digest in proof['baseline_sha256'].items())
    old_path = next(path for path in bodies if path.startswith('docs/release/') and path.endswith(Path(FEATURE).name))
    assert sha(bodies[FEATURE])==NEW and sha(bodies[old_path])==OLD
    assert sha((W/FEATURE).read_bytes())==NEW
    old = function_parts(bodies[old_path].decode()); new = function_parts(bodies[FEATURE].decode())
    case('outside changed function and its signature/configuration are exact old accepted bytes',
         old[0]+old[2]==new[0]+new[2] and old[1].split('as $$',1)[0]==new[1].split('as $$',1)[0])
    replacement = new[1].replace('create function ', 'create or replace function ', 1)
    (P/'changed-function-replacement.sql').write_text(replacement+'\n')
    frozen = P/'executed-inputs'; frozen.mkdir()
    for path,body in bodies.items():
        dest=frozen/path; dest.parent.mkdir(parents=True,exist_ok=True); dest.write_bytes(body)
    for path,body in baseline.items():
        dest=frozen/'.cache/receipt-foundation-attempt8'/path
        dest.parent.mkdir(parents=True,exist_ok=True); dest.write_bytes(body)
    result['source_sha256']=proof['source_sha256']
    result['baseline_sha256']=proof['baseline_sha256']
    result['runner_sha256']=sha(Path(__file__).read_bytes())
    result['replacement_sha256']=sha(replacement.encode())
    prior=W/'docs/release/rapid-completion-2026-10-01/post-acceptance-delta-current1/sql-ordinary187/validation.json'
    prior_json=json.loads(prior.read_text()); assert prior_json['status']=='pass'
    result['reused_proofs']={'full187_structural_ordinary_installer':{'path':str(prior),'sha256':sha(prior.read_bytes()),'applications':374,'checks':36,'migration_sha256':OLD},
                             'current37_query_proof':{'path':str(B/'result.json'),'sha256':sha((B/'result.json').read_bytes()),'cases':37,'migration_sha256':NEW}}
    mods={}
    for name in ['shadow_supervisor_uat','receipt_backlog_events_uat','collect_admin_combined_upgrade_uat','collect_current_release_upgrade_uat']:
        path='scripts/tests/'+name+'.py'; m=types.ModuleType(name)
        m.__file__=str(frozen/path); sys.modules[name]=m
        exec(compile(bodies[path],m.__file__,'exec'),m.__dict__); mods[name]=m
    u=mods['shadow_supervisor_uat']; f=mods['receipt_backlog_events_uat']; private=mods['collect_current_release_upgrade_uat']
    result['tools']={'python':sys.version,'python_path':sys.executable,'python_sha256':sha(Path(sys.executable).read_bytes()),
                     'docker_path':private.DOCKER,'docker_sha256':sha(Path(private.DOCKER).read_bytes()),'image':private.IMAGE,'image_id':private.IMAGE_ID}
    stages=[path for path in bodies if path.startswith('supabase/migrations/') and path!=FEATURE]
    assert len(stages)==18
    target=private.Target(P,'ordinary_body',result['target']); target.__enter__()
    u.CONTAINER=target.name; u.SQL_LOG=P/'queries.log'; u.CONCURRENCY_LOG=P/'concurrency.log'; f.RAW_QUERY_LOG=P/'queries.sql'
    sql=lambda db,s:u.psql(db,s).stdout.strip()
    scalar=lambda db,s:sql(db,s).splitlines()[-1]
    owner=lambda db,s:u.call(db,s,EMAIL,SID)
    service=lambda db,s:json.loads(scalar(db,"begin;set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"+s+';commit;'))
    finance=lambda db:{k:v for k,v in f.business_fingerprint(db).items() if k not in ('raw_payment_sms','parsed_payment_events')}
    databases={phase:'ordinary_body_'+phase+'_'+uuid.uuid4().hex[:10] for phase in ['new','retained']}
    for phase,db in databases.items():
        outcome=result['phases'][phase]={'database':db,'stage':'privileged predecessor fixture setup'}; save()
        u.psql('postgres','create database '+db+' template template0;')
        sql(db,'create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);'+baseline['schema-only.sql'].decode()+baseline['api-acl.sql'].decode())
        f.seed(db)
        sql(db,"update public.feature_flags set enabled=true where key='hybrid_sms_notifications';"+f.service(f.payment_sql('99880000-0000-4000-8000-000000050001',amount=50))+"update public.feature_flags set enabled=false where key='hybrid_sms_notifications';insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network)values(%s,%s,'+250788971001',repeat('a',64),'mtn_momo');"%(q(f.GROUP),q(u.UID)))
        initial=finance(db)
        for path in stages:
            installed=u.psql(db,bodies[path].decode(),False)
            if installed.returncode: raise RuntimeError('predecessor setup '+path+': '+installed.stderr[-3500:])
        assert finance(db)==initial
        outcome['predecessor_stage_count']=len(stages)
        outcome['privileged_setup_complete']=True
    target.sql('alter role postgres nosuperuser;', user='supabase_admin',label='controlled platform setup ends; ordinary application installer demotion')
    authority=lambda db:json.loads(scalar(db,"select jsonb_build_object('current_user',current_user,'superuser',(select rolsuper from pg_roles where rolname=current_user));"))
    case('application installer is actually postgres NOSUPERUSER before either feature context',all(authority(db)=={'current_user':'postgres','superuser':False} for db in databases.values()))
    # Catalog map includes every existing public/Collect function definition,
    # function owner/ACL/configuration and table owner/ACL/RLS, excluding only
    # the changed target body from definition comparison.
    catalog_sql="""select jsonb_build_object(
    'definitions',(select coalesce(jsonb_object_agg(p.oid::regprocedure::text,encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex')),'{}')from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public'or n.nspname like 'collect_%')and p.proname<>'admin_get_exception_entity_audit_v2'),
    'function_attributes',(select coalesce(jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'security_definer',p.prosecdef,'configuration',p.proconfig)),'{}')from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'or n.nspname like 'collect_%'),
    'tables',(select coalesce(jsonb_object_agg(n.nspname||'.'||c.relname,jsonb_build_object('owner',pg_get_userbyid(c.relowner),'acl',c.relacl::text,'RLS',c.relrowsecurity,'force_RLS',c.relforcerowsecurity)),'{}')from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in('r','p','v','m','S')and(n.nspname='public'or n.nspname like 'collect_%')));"""
    catalog=lambda db:json.loads(scalar(db,catalog_sql))
    life_tables=['exceptions','exception_escalations','exception_inbox_deliveries','exception_inbox_reads','exception_workflow_requests','exception_actions']
    life=lambda db:{table:json.loads(scalar(db,"select jsonb_build_object('rows',count(*),'sha256',encode(extensions.digest(coalesce(string_agg(to_jsonb(x)::text,E'\\n'order by to_jsonb(x)::text),''),'sha256'),'hex'))from collect_ops."+table+' x;')) for table in life_tables}
    for phase,db in databases.items():
        outcome=result['phases'][phase]; outcome['stage']='ordinary feature setup and prior immutable lifecycle'
        sql(db,"insert into public.admin_permissions(name,description)values('payments.read','Synthetic'),('audit.read','Synthetic')on conflict do nothing;insert into public.admin_role_permissions(role_id,permission_name)select %s,name from public.admin_permissions on conflict do nothing;"%q(f.ROLE))
        sql(db,"insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)values(%s,'authenticated','authenticated','info@ikanisa.com',clock_timestamp(),'{}','{}');"%q(EMAIL))
        service(db,'select public.bootstrap_collect_email_operator_v1('+q(EMAIL)+');')
        sql(db,"insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values(%s,%s,clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');"%(q(SID),q(EMAIL)))
        rid=str(uuid.uuid4())
        sql(db,"insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status)values(%s,%s,%s,'M-Money','Synthetic parser failure',%s,repeat('a',64),'failed');"%(q(rid),q(f.GROUP),q(u.UID),q(sha(rid.encode()))))
        item=json.loads(scalar(db,'select to_jsonb(e)from collect_ops.exceptions e where source_id='+q(rid)+';'))
        owner(db,'select public.admin_act_operational_exception_v1(%s,%s,%d,\'acknowledge\',\'review_started\');'%(q(str(uuid.uuid4())),q(item['id']),item['revision']))
        def action(op,revision):
            return owner(db,'select public.admin_act_exception_workflow_v2(%s,%s,%d,%d,%s,%s,%s,\'owner_review_required\',clock_timestamp()+interval \'90 seconds\');'%(q(str(uuid.uuid4())),q(item['id']),item['revision'],revision,q(op),q(EMAIL) if op=='assign' else 'null',"clock_timestamp()+interval '2 hours'" if op=='assign' else 'null'))
        action('assign',0); escalation=action('escalate',1)
        service(db,'select public.process_exception_escalations_v1(25);')
        owner(db,'select public.admin_read_exception_escalation_v1('+q(escalation['escalation_id'])+');')
        if phase=='retained':
            installed=u.psql(db,bodies[old_path].decode(),False)
            (P/'retained-old.install.log').write_text(installed.stdout+installed.stderr)
            case('retained old accepted v2 installs as ordinary owner',installed.returncode==0 and authority(db)['superuser'] is False)
        before_fin=finance(db); before_life=life(db); before_catalog=catalog(db)
        outcome['financial_before']=before_fin; outcome['lifecycle_before']=before_life
        retain(phase+'-catalog-before.json',before_catalog)
        case(phase+' starts with nonempty financial and retained lifecycle evidence',before_fin['payments']['rows']>=2 and before_fin['journal']['rows']>=2 and all(x['rows']>0 for x in before_life.values()))
        outcome['stage']='ordinary current feature install' if phase=='new' else 'ordinary changed-function replacement'; save()
        installed=u.psql(db,bodies[FEATURE].decode() if phase=='new' else 'begin;'+replacement+';commit;',False)
        (P/(phase+'-current.install.log')).write_text(installed.stdout+installed.stderr)
        outcome['installer_authority']=authority(db)
        case(phase+' current source installs as postgres NOSUPERUSER',installed.returncode==0 and outcome['installer_authority']=={'current_user':'postgres','superuser':False})
        after_catalog=catalog(db); retain(phase+'-catalog-after.json',after_catalog)
        preserved=all(all(after_catalog[section].get(key)==value for key,value in mapping.items()) for section,mapping in before_catalog.items())
        case(phase+' preserves all preexisting outside-body definitions owner ACL and configuration',preserved and (phase=='new' or after_catalog==before_catalog))
        function=json.loads(scalar(db,"select jsonb_build_object('definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),'owner_superuser',(select rolsuper from pg_roles where oid=p.proowner),'security_definer',p.prosecdef,'acl',p.proacl::text,'configuration',p.proconfig)from pg_proc p where p.oid='public.admin_get_exception_entity_audit_v2(uuid,integer,timestamptz,uuid)'::regprocedure;"))
        outcome['function']=function; outcome['function_definition_sha256']=sha(function['definition'].encode())
        case(phase+' installed security-definer owner is actual non-superuser postgres',function['owner']=='postgres' and function['owner_superuser'] is False and function['security_definer'] is True)
        observed=owner(db,'select public.admin_get_exception_entity_audit_v2('+q(item['id'])+',25,null,null);')
        retain(phase+'-authenticated-public-page.json',observed)
        rows=observed['rows']
        case(phase+' actual authenticated RPC reads six joined review workflow lifecycle records',observed['contract_version']==2 and observed['status']=='available' and observed['entity_id']==item['id'] and len(rows)==6 and {x['source']for x in rows}=={'exception_action','exception_workflow_request','exception_escalation_event'})
        denied=u.psql(db,'begin;'+u.auth(EMAIL,SID)+'select * from collect_ops.exception_escalation_events;rollback;',False)
        (P/(phase+'-private-read-refusal.log')).write_text(denied.stdout+denied.stderr)
        case(phase+' authenticated private direct read is refused',denied.returncode!=0 and '42501:' in denied.stderr)
        private_acl=scalar(db,"select not exists(select 1 from pg_proc p cross join unnest(array['anon','authenticated','service_role'])r where p.proname in('capture_escalation_event','exception_event_id','exception_scope_v2','exception_actor_v2')and has_function_privilege(r,p.oid,'EXECUTE'))and not exists(select 1 from pg_class c cross join unnest(array['anon','authenticated','service_role'])r where c.oid='collect_ops.exception_escalation_events'::regclass and has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE'));")
        case(phase+' private helpers and evidence expose no direct API grants',private_acl=='t')
        outcome['financial_after']=finance(db); outcome['lifecycle_after']=life(db)
        case(phase+' install and read preserve exact nonempty financial and lifecycle fingerprints',outcome['financial_after']==before_fin and outcome['lifecycle_after']==before_life)
        outcome['status']='pass'; outcome['stage']='complete'; save()
    case('both contexts install identical normalized current function definition',result['phases']['new']['function_definition_sha256']==result['phases']['retained']['function_definition_sha256'])
    case('captured source helper and current live function migration remain exact',all(sha((B/'executed-inputs'/path).read_bytes())==digest for path,digest in proof['source_sha256'].items()) and sha((W/FEATURE).read_bytes())==NEW)
    result['status']='pass'; result['completed_at']=now()
except BaseException as error:
    result['status']='failed'; result['failure']=str(error); result['completed_at']=now(); save(); raise
finally:
    if target is not None:
        target.close(); result['all_task_containers_removed']=result['target'].get('task_container_removed') is True
    save()
print(json.dumps({'status':result['status'],'cases':len(result['cases']),'result':str(P/'result.json'),'all_task_containers_removed':result.get('all_task_containers_removed')}),flush=True)

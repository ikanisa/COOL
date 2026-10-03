#!/usr/bin/env python3
"""Focused real SQL follow-up v2 UAT on an owned network-none target.

Retains every executed helper and migration BEFORE import/use. The schema153
fixture has local owner/claims normalization, mock cron catalog shape and no
GoTrue, installer ACL, provider, scheduler or current whole-chain acceptance.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import sys
import time
import types
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIGRATION = 'supabase/migrations/20261001190000_exception_followup_v2.sql'
STAGES = ['supabase/migrations/20260930213000_operator_email_auth.sql',
          'supabase/migrations/20260930220527_operator_email_cutover_guard.sql',
          'supabase/migrations/20260930230100_receipt_backlog_events.sql',
          'supabase/migrations/20260930230200_admin_receipt_overview.sql',
          'supabase/migrations/20260930230300_admin_transaction_lifecycle.sql',
          'supabase/migrations/20260930211605_android_gateway_identity.sql',
          'supabase/migrations/20261001000100_operational_exception_inbox.sql',
          'supabase/migrations/20261001120000_operational_exception_lifecycle.sql', MIGRATION]
HELPERS = ['shadow_supervisor_uat', 'receipt_backlog_events_uat',
           'collect_admin_combined_upgrade_uat', 'collect_current_release_upgrade_uat']
EMAIL = '99790000-0000-4000-8000-000000000001'
EMAIL_SID = '99790000-0000-4000-8000-000000010001'
RAW = '99790000-0000-4000-8000-000000060001'
OTHER = '99880000-0000-4000-8000-000000000001'
OTHER_SID = '99880000-0000-4000-8000-000000010001'
SHA = lambda body: hashlib.sha256(body).hexdigest()
q = lambda value: "'" + str(value).replace("'", "''") + "'"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report-dir', required=True, type=pathlib.Path)
    args = parser.parse_args()
    report = args.report_dir.resolve()
    assert not report.exists(), 'Fresh evidence directory required'
    assert str(report).startswith(str(ROOT/'docs/release')+'/'), 'Owned release evidence leaf required'
    report.mkdir(parents=True)
    evidence = dict(kind='exception_followup_v2_schema153_subset', status='running', cases=[],
                    hosted_called=False, shared_database_written=False, source_rows_copied=False,
                    carrier_called=False, auth_provider_tested=False, full_candidate_tested=False,
                    fixture_limitations=['Local installer postgres superuser normalization',
                        'Owner-normalized retained schema153 plus captured additive subset',
                        'SET LOCAL authenticated role and synthetic JWT claims; no signed JWT',
                        'Mock cron catalog only; scheduler/net/provider runtime untested'])
    save = lambda: (report/'result.json').write_text(json.dumps(evidence, indent=2)+'\n')
    sources = {name:(ROOT/name).read_bytes() for name in STAGES+
               ['scripts/tests/'+h+'.py' for h in HELPERS]+[str(pathlib.Path(__file__).relative_to(ROOT))]}
    baseline_path = ROOT/'.cache/receipt-foundation-attempt8'
    baseline = {name:(baseline_path/name).read_bytes() for name in ['schema-only.sql','api-acl.sql']}
    captured = report/'executed-inputs';captured.mkdir()
    for name, body in sources.items():
        path=captured/name;path.parent.mkdir(parents=True, exist_ok=True);path.write_bytes(body)
    for name,body in baseline.items(): (captured/name).write_bytes(body)
    evidence['source_sha256']={name:SHA(body) for name,body in sources.items()}
    evidence['baseline_sha256']={name:SHA(body) for name,body in baseline.items()}
    save()
    # These actual retained helper bytes execute with their original __file__
    # to preserve existing ROOT semantics. Dependencies already in sys.modules
    # ensure no local helper can silently reimport later workspace bytes.
    modules={}
    for name in HELPERS:
        module=types.ModuleType(name);module.__file__=str(ROOT/'scripts/tests'/f'{name}.py')
        sys.modules[name]=module
        exec(compile(sources[f'scripts/tests/{name}.py'], module.__file__, 'exec'), module.__dict__)
        modules[name]=module
    u=modules['shadow_supervisor_uat'];foundation=modules['receipt_backlog_events_uat']
    fixture=modules['collect_admin_combined_upgrade_uat'];private=modules['collect_current_release_upgrade_uat']
    assert SHA(baseline['schema-only.sql'])==fixture.DUMP_HASH and SHA(baseline['api-acl.sql'])==fixture.ACL_HASH
    evidence['tool']={'docker_path':u.DOCKER,'docker_sha256':SHA(pathlib.Path(u.DOCKER).read_bytes()),
                      'python':sys.version,'image':private.IMAGE,'image_id':private.IMAGE_ID}
    def check(ok):
        if not ok: raise AssertionError('Expectation failed')
        return True
    def case(name,fn):
        try:value=fn()
        except Exception as error:
            evidence['cases'].append(dict(name=name,status='failed',error=str(error)));save();raise
        evidence['cases'].append(dict(name=name,status='pass',detail=value));save();print('PASS '+name,flush=True)
        return value
    db='exception_followup_v2_'+uuid.uuid4().hex[:12]
    target=None;sessions=[]
    sql=lambda body:u.psql(db,body).stdout.strip()
    owner=lambda body:u.call(db,body,EMAIL,EMAIL_SID)
    other=lambda body:u.call(db,body,OTHER,OTHER_SID)
    service=lambda body:json.loads(sql(foundation.service(body)).splitlines()[-1])
    fail=lambda body,state,reason=None:u.expected_error(db,body,state,reason,uid=EMAIL,sid=EMAIL_SID)
    def financial():return foundation.business_fingerprint(db)
    def error_transaction(mutation,body,reason=None):
        result=u.psql(db,'begin;'+mutation+u.auth(EMAIL,EMAIL_SID)+body+';rollback;',False)
        return check(result.returncode!=0 and '42501:' in result.stderr and (reason is None or reason in result.stderr))
    def utc_after(interval):return sql('select collect_ops.utc(clock_timestamp()+interval '+q(interval)+');')
    def binding(item,rev,action='assign',assignee=OTHER,due=None,reason='review_started',expiry=None,request=None):
        return dict(request_id=request or str(uuid.uuid4()),exception_id=item['id'],
                    source_revision=item['revision'],workflow_revision=rev,action=action,
                    assignee_id=assignee if action=='assign' else None,
                    due_at=(due or utc_after('2 hours')) if action=='assign' else None,
                    reason_code=reason,expires_at=expiry or utc_after('90 seconds'))
    def fingerprint(b):
        text='\n'.join(['collect-exception-workflow-v2',b['request_id'],b['exception_id'],
            str(b['source_revision']),str(b['workflow_revision']),b['action'],b['assignee_id'] or '-',
            b['due_at'] or '-',b['reason_code'],b['expires_at']])
        return SHA(text.encode())
    def act(b,version=2):return 'select public.admin_act_exception_workflow_v%d(%s,%s,%d,%d,%s,%s,%s,%s,%s);'%(version,
        q(b['request_id']),q(b['exception_id']),b['source_revision'],b['workflow_revision'],q(b['action']),
        'null' if b['assignee_id'] is None else q(b['assignee_id']),
        'null' if b['due_at'] is None else q(b['due_at']),q(b['reason_code']),q(b['expires_at']))
    def lookup(b,fp=None,expiry=None):return 'select public.admin_get_exception_workflow_request_v2(%s,%s,%s);'%(
        q(b['request_id']),q(fp or fingerprint(b)),q(expiry or b['expires_at']))
    def retain(name,data):(report/name).write_text(json.dumps(data,indent=2)+'\n')
    directory='select public.admin_list_exception_followup_operators_v2();'
    try:
        target=private.Target(report,'exception_followup_v2',evidence.setdefault('target',{}));target.__enter__()
        u.CONTAINER=target.name;u.SQL_LOG=report/'queries.log';u.CONCURRENCY_LOG=report/'concurrency.log'
        foundation.RAW_QUERY_LOG=report/'queries.sql'
        u.psql('postgres','create database '+db+' template template0;')
        sql('create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);'
            'create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);'+
            baseline['schema-only.sql'].decode()+baseline['api-acl.sql'].decode())
        foundation.seed(db)
        sql("update public.feature_flags set enabled=true where key='hybrid_sms_notifications';"+
            foundation.service(foundation.payment_sql('99880000-0000-4000-8000-000000050001',amount=50))+
            "update public.feature_flags set enabled=false where key='hybrid_sms_notifications';")
        sql("insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network)values(%s,%s,'+250788971001',repeat('a',64),'mtn_momo');"%(q(foundation.GROUP),q(u.UID)))
        before=financial();v1_before=None
        for name in STAGES:
            if name==MIGRATION:
                v1_before=sql("select encode(extensions.digest(pg_get_functiondef('public.admin_act_exception_workflow_v1(uuid,uuid,bigint,bigint,text,uuid,timestamptz,text,timestamptz)'::regprocedure),'sha256'),'hex');")
            result=u.psql(db,sources[name].decode(),False)
            (report/(pathlib.Path(name).stem+'.install.log')).write_text(result.stdout+result.stderr)
            case(name+' installs and preserves nonempty finance/primary receipt',lambda result=result:check(result.returncode==0 and financial()==before))
        case('v1 action SQL definition remains byte identical',lambda:check(v1_before==sql("select encode(extensions.digest(pg_get_functiondef('public.admin_act_exception_workflow_v1(uuid,uuid,bigint,bigint,text,uuid,timestamptz,text,timestamptz)'::regprocedure),'sha256'),'hex');")))
        evidence['v1_action_definition_sha256']=v1_before
        sql("insert into public.admin_permissions(name,description)values('payments.read','Synthetic'),('admin_users.manage','Synthetic')on conflict do nothing;insert into public.admin_role_permissions(role_id,permission_name)select %s,name from public.admin_permissions on conflict do nothing;"%q(foundation.ROLE))
        sql("insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)values(%s,'authenticated','authenticated','info@ikanisa.com',clock_timestamp(),'{}','{}');"%q(EMAIL))
        service('select public.bootstrap_collect_email_operator_v1(%s);'%q(EMAIL))
        sql("insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values(%s,%s,clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');"%(q(EMAIL_SID),q(EMAIL)))
        # Keep transition mode to prove that only the additive v2 gate excludes
        # the still-valid legacy identity; do not rewrite the policy fixture.
        legacy_read='select public.admin_list_operational_exceptions_v1();'
        case('v1 transition-approved WhatsApp owner remains authorized',lambda:check(u.call(db,legacy_read)['contract_version']==1))
        for body in [directory,"select public.admin_get_exception_workflow_request_v2(%s,repeat('0',64),clock_timestamp());"%q(uuid.uuid4()),
                     "select public.admin_act_exception_workflow_v2(null,null,null,null,null,null,null,null,null);"]:
            case('v2 explicitly refuses legacy transition identity '+body.split('(')[0],lambda body=body:u.expected_error(db,body,'42501','exception_followup_email_owner_required'))
        # Thirty eligible operators and three ineligible profiles make actual
        # pagination and revalidation observable without contact disclosures.
        eligible=['99880000-0000-4000-8000-%012d'%i for i in range(1,31)]
        for i,user in enumerate(eligible,1):
            sql("insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)values(%s,'authenticated','authenticated',%s,clock_timestamp(),'{}','{}');insert into collect_admin_access.email_approvals(user_id,email,reason,approved_at)values(%s,%s,'Synthetic eligible recipient',clock_timestamp()-interval '2 minutes');insert into public.admin_user_roles(user_id,role_id,reason,created_at)values(%s,%s,'Synthetic recipient grant',clock_timestamp()-interval '1 minute');update public.profiles set created_at=date_trunc('second',clock_timestamp())-interval '1 day',display_name='DO NOT EXPORT EMAIL OR CONTACT'where id=%s;"%(q(user),q('synthetic%d@example.invalid'%i),q(user),q('synthetic%d@example.invalid'%i),q(user),q(foundation.ROLE),q(user)))
        sql("insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values(%s,%s,clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');"%(q(OTHER_SID),q(OTHER)))
        # No email approval, expired email approval, non-owner role.
        for i,kind in enumerate(['unapproved','expired','role_missing'],40):
            user='99880000-0000-4000-8000-%012d'%i
            sql("insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)values(%s,'authenticated','authenticated',%s,clock_timestamp(),'{}','{}');"%(q(user),q('synthetic%d@example.invalid'%i)))
            if kind!='unapproved':
                sql("insert into collect_admin_access.email_approvals(user_id,email,reason,approved_at,expires_at)values(%s,%s,'Synthetic excluded recipient',clock_timestamp()-interval '2 minutes',%s);"%(q(user),q('synthetic%d@example.invalid'%i),"clock_timestamp()-interval '1 minute'" if kind=='expired' else 'null'))
            if kind!='role_missing':sql("insert into public.admin_user_roles(user_id,role_id,reason,created_at)values(%s,%s,'Synthetic excluded grant',clock_timestamp()-interval '1 minute');"%(q(user),q(foundation.ROLE)))
        page=owner(directory);retain('observed-directory-first.json',page)
        case('directory has exactly minimal redacted fields and60s TTL',lambda:check(set(page)=={'contract_version','scope','checked_at','sample_valid_until','limit','rows','next_cursor'} and page['contract_version']==2 and page['scope']=='platform_global' and all(set(r)=={'operator_id','display_label','created_at'} and r['display_label'].startswith('Collect ID ') for r in page['rows']) and (datetime.datetime.fromisoformat(page['sample_valid_until'].replace('Z','+00:00'))-datetime.datetime.fromisoformat(page['checked_at'].replace('Z','+00:00'))).total_seconds()==60))
        cursor=page['next_cursor'];last=owner('select public.admin_list_exception_followup_operators_v2(25,%s,%s);'%(q(cursor['created_at']),q(cursor['operator_id'])));retain('observed-directory-last.json',last)
        case('paired25 keyset traverses31eligible operators without duplicates',lambda:check(len(page['rows'])==25 and len(last['rows'])==6 and last['next_cursor'] is None and {r['operator_id']for r in page['rows']+last['rows']}==set(eligible+[EMAIL]) and page['rows'][-1]['operator_id']==cursor['operator_id']))
        case('directory requires no generic admin_users permission',lambda:check(u.psql(db,'begin;delete from public.admin_role_permissions where role_id=%s and permission_name in(\'admin_users.read\',\'admin_users.manage\');'%q(foundation.ROLE)+u.auth(EMAIL,EMAIL_SID)+directory+'rollback;',False).returncode==0))
        for args in ['0','26','null',"25,clock_timestamp(),null","25,null,'%s'"%OTHER,"25,'infinity','%s'"%OTHER]:
            case('directory rejects invalid bounds/pair '+args,lambda args=args:fail('select public.admin_list_exception_followup_operators_v2('+args+');','22023','exception_followup_directory_input_invalid'))
        empty=u.psql(db,'begin;update public.profiles set created_at=clock_timestamp()+interval \'1 day\';'+u.auth(EMAIL,EMAIL_SID)+directory+'rollback;').stdout.strip().splitlines()[-1]
        case('empty eligible page is explicit without invented count',lambda:check(json.loads(empty)['rows']==[] and json.loads(empty)['next_cursor'] is None))
        for role in ['anon','service_role']:
            for body in [directory,'select public.admin_act_exception_workflow_v2(null,null,null,null,null,null,null,null,null);','select public.admin_get_exception_workflow_request_v2(null,null,null);']:
                case(role+' cannot execute v2 '+body.split('(')[0],lambda role=role,body=body:u.expected_error(db,body,'42501',role=role))
        case('new private helpers have no API execute or schema grants',lambda:check(sql("select not exists(select 1 from pg_proc p cross join unnest(array['anon','authenticated','service_role'])r where p.pronamespace='collect_ops'::regnamespace and p.proname in('followup_v2_actor','followup_v2_fingerprint')and has_function_privilege(r,p.oid,'EXECUTE')) and not exists(select 1 from unnest(array['anon','authenticated','service_role'])r where has_schema_privilege(r,'collect_ops','USAGE'));")=='t'))
        for mutation,label in [("update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id=%s;"%q(EMAIL_SID),'expired session'),("update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id=%s;"%q(EMAIL),'revoked approval'),("update public.admin_user_roles set revoked_at=clock_timestamp()where user_id=%s;"%q(EMAIL),'revoked grant'),("update auth.users set banned_until=clock_timestamp()+interval '1 day'where id=%s;"%q(EMAIL),'banned actor')]+[("delete from public.admin_role_permissions where role_id=%s and permission_name=%s;"%(q(foundation.ROLE),q(p)),p)for p in ['payments.read','notifications.read','system_health.read']]:
            case('directory current authority refuses '+label,lambda mutation=mutation:error_transaction(mutation,directory))
        for isolation in ['repeatable read','serializable']:
            probe=u.psql(db,'begin isolation level '+isolation+';'+u.auth(EMAIL,EMAIL_SID)+directory+'rollback;',False)
            case(isolation+' cannot retain stale authority',lambda probe=probe:check(probe.returncode!=0 and '40001:'in probe.stderr))
        sql("insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status)values(%s,%s,%s,'M-Money','Synthetic followup parser failure',repeat('e',64),repeat('a',64),'failed');"%(q(RAW),q(foundation.GROUP),q(u.UID)))
        item=json.loads(sql('select to_jsonb(e)from collect_ops.exceptions e where source_id=%s;'%q(RAW)))
        original=binding(item,0);receipt=owner(act(original));retain('observed-assignment-binding.json',original);retain('observed-assignment-receipt.json',receipt)
        case('assign another eligible operator/custom deadline binds exact Python SHA256',lambda:check(receipt['request_fingerprint']==fingerprint(original) and receipt['contract_version']==2 and receipt['workflow_revision']==1 and not receipt['financial_action'] and not receipt['send_action'] and not receipt['source_resolved']))
        read=owner('select public.admin_get_exception_workflow_v1(%s);'%q(item['id']))
        case('actual v1 workflow projection retains selected other operator/custom deadline',lambda:check(read['assignee_id']==OTHER and read['due_at']==original['due_at']))
        case('v2 exact replay adds no revision or audit action',lambda:check(owner(act(original))==receipt and sql('select revision from collect_ops.exception_workflows where exception_id=%s;'%q(item['id']))=='1'))
        case('v1 replay remains its exact old version1 receipt',lambda:check(owner(act(original,1))=={k:v for k,v in receipt.items()if k!='request_fingerprint'}|{'contract_version':1}))
        found=owner(lookup(original));retain('observed-recorded-lookup.json',found)
        case('original lookup proves exact immutable request fingerprint and receipt',lambda:check(found['status']=='recorded' and found['receipt']==receipt and found['expires_at']==original['expires_at']))
        for field,value in [('assignee_id',eligible[1]),('due_at',utc_after('3 hours')),('reason_code','contact_review'),('expires_at',utc_after('80 seconds'))]:
            changed=dict(original,**{field:value})
            case('altered '+field+' changes exact intent fingerprint',lambda changed=changed:check(fingerprint(changed)!=receipt['request_fingerprint']))
            case('reused UUID refuses altered '+field,lambda changed=changed:fail(act(changed),'22023','exception_workflow_request_conflict'))
        case('lookup refuses wrong fingerprint before returning receipt',lambda:fail(lookup(original,'0'*64),'22023','exception_followup_request_conflict'))
        case('lookup refuses wrong expiry before returning receipt',lambda:fail(lookup(original,expiry=utc_after('80 seconds')),'22023','exception_followup_request_conflict'))
        foreign=other(lookup(original));retain('observed-foreign-lookup.json',foreign)
        case('another eligible current actor cannot discover original actor receipt',lambda:check(foreign['status']=='not_recorded' and foreign['receipt'] is None))
        absent=binding(item,1,expiry=utc_after('-1 second'))
        unknown=owner(lookup(absent));retain('observed-expired-unrecorded-lookup.json',unknown)
        case('expired absent request reports server time without authorizing replay',lambda:check(unknown['status']=='not_recorded' and unknown['receipt'] is None and unknown['checked_at']>unknown['expires_at']))
        case('expired absent action cannot be reenrolled',lambda:fail(act(absent),'22023','exception_workflow_request_expired'))
        for permission in ['notifications.manage']:
            mutation="delete from public.admin_role_permissions where role_id=%s and permission_name=%s;"%(q(foundation.ROLE),q(permission))
            case('action requires mutation authority '+permission,lambda mutation=mutation:error_transaction(mutation,act(binding(item,1))))
            case('read does not require mutation authority '+permission,lambda mutation=mutation:check(u.psql(db,'begin;'+mutation+u.auth(EMAIL,EMAIL_SID)+directory+'rollback;',False).returncode==0))
        case('stale workflow revision remains refused byv1 domain',lambda:fail(act(binding(item,0)),'55000','exception_workflow_source_changed'))
        case('custom past deadline refused',lambda:fail(act(binding(item,1,due=utc_after('-1 second'))),'22023','exception_workflow_deadline_invalid'))
        case('custom deadline beyond30days refused',lambda:fail(act(binding(item,1,due=utc_after('30 days 1 minute'))),'22023','exception_workflow_deadline_invalid'))
        long_deadline=binding(item,1,due=utc_after('29 days 23 hours'));long_receipt=owner(act(long_deadline))
        case('custom deadline within30day domain actually persists',lambda:check(long_receipt['workflow_revision']==2 and owner('select public.admin_get_exception_workflow_v1(%s);'%q(item['id']))['due_at']==long_deadline['due_at']))
        revoked=binding(item,2,assignee=eligible[1])
        owner('select public.admin_revoke_email_operator_v1(%s,\'Synthetic recipient revoked after directory\');'%q(eligible[1]))
        case('directory selection never overrides later recipient revocation',lambda:fail(act(revoked),'42501','exception_workflow_recipient_unavailable'))
        case('later directory excludes revoked selection',lambda:check(eligible[1]not in [r['operator_id']for r in owner('select public.admin_list_exception_followup_operators_v2(25);')['rows']]))
        # Actual action holds the roster/request/domain locks through commit.
        # Lookup must disclose no state until authority is available.
        held=u.Session(db,'v2_actual_action_holder');sessions.append(held)
        pending=binding(item,2);held.write('begin;'+u.auth(EMAIL,EMAIL_SID)+act(pending)+"select 'ACTION_HELD';");held.read('ACTION_HELD')
        start=time.monotonic()
        case('original lookup behind actual pending action returns bounded authority_busy',lambda:fail(lookup(pending),'55P03','exception_followup_authority_busy'))
        evidence['lookup_busy_seconds']=round(time.monotonic()-start,3)
        held.write("commit;select 'ACTION_COMMITTED';");held.read('ACTION_COMMITTED')
        reconciled=owner(lookup(pending));retain('observed-after-commit-lookup.json',reconciled)
        case('manual original UUID read after commit reconciles without reenrollment',lambda:check(reconciled['status']=='recorded' and reconciled['receipt']['workflow_revision']==3))
        # A request lock without an action/roster fence proves the distinct
        # in_progress state is reached only AFTER successful authority.
        held.write("begin;select pg_advisory_xact_lock(hashtextextended('collect-ops-workflow-request:'||%s,0));select 'REQUEST_HELD';"%q(absent['request_id']));held.read('REQUEST_HELD')
        progress=owner(lookup(absent));retain('observed-in-progress-lookup.json',progress)
        case('in_progress retains original fingerprint/expiry without state or receipt',lambda:check(progress['status']=='in_progress' and progress['receipt'] is None and progress['request_fingerprint']==fingerprint(absent)))
        held.write("rollback;select 'REQUEST_RELEASED';");held.read('REQUEST_RELEASED')
        # Real recipient revocation and assignment serialize on current roster
        # authority; the post-wait assignment cannot use the earlier directory.
        recipient=eligible[2];race=binding(item,3,assignee=recipient)
        held.write('begin;'+u.auth(EMAIL,EMAIL_SID)+'select public.admin_revoke_email_operator_v1(%s,\'Synthetic real concurrent revocation\');select \'REVOKE_HELD\';'%q(recipient));held.read('REVOKE_HELD')
        waiter=u.Session(db,'v2_assignment_after_revoke');sessions.append(waiter)
        waiter.write("set application_name='collect_v2_recipient_waiter';begin;"+u.auth(EMAIL,EMAIL_SID)+act(race)+"commit;select 'RACE_DONE';")
        waiting=False;deadline=time.monotonic()+8
        while time.monotonic()<deadline:
            waiting=sql("select exists(select 1 from pg_stat_activity where datname=%s and application_name='collect_v2_recipient_waiter'and wait_event_type='Lock');"%q(db))=='t'
            if waiting:break
            time.sleep(.03)
        check(waiting);held.write("commit;select 'REVOKE_COMMITTED';");held.read('REVOKE_COMMITTED')
        output=waiter.read('RACE_DONE');retain('observed-recipient-revocation-race.json',{'actually_waited':waiting,'output':output})
        case('actual concurrent revocation fences stale selected recipient',lambda:check(any('42501:'in line and 'exception_workflow_recipient_unavailable'in line for line in output) and sql('select count(*)from collect_ops.exception_workflow_requests where request_id=%s;'%q(race['request_id']))=='0'))
        # Domain evidence is immutable; v2 adds no tables, outbox or transport.
        for table in ['exception_workflow_requests','exception_inbox_deliveries','exception_inbox_reads']:
            case(table+' remains private RLS without API direct grants',lambda table=table:check(sql("select c.relrowsecurity and not exists(select 1 from unnest(array['anon','authenticated','service_role'])r where has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE'))from pg_class c where c.oid=%s::regclass;"%q('collect_ops.'+table))=='t'))
        case('immutable original request cannot be edited',lambda:fail('update collect_ops.exception_workflow_requests set reason_code=\'contact_review\';','42501'))
        privileged=u.psql(db,"begin;update collect_ops.exception_workflow_requests set reason_code='contact_review';rollback;",False)
        case('even fixture table owner cannot rewrite retained request',lambda:check(privileged.returncode!=0 and '55000:'in privileged.stderr))
        case('public audit attributes actual owner and retains original request link',lambda:check(sql("select actor_user_id=%s and metadata->>'request_id'=%s and metadata->>'financial_action'='false'and metadata->>'send_action'='false'from public.audit_logs where action='operations.exception.workflow.assign'and metadata->>'request_id'=%s;"%(q(EMAIL),q(original['request_id']),q(original['request_id'])))=='t'))
        case('all follow-up operations preserve nonempty financial/primary/send evidence',lambda:check(financial()==before))
        evidence['financial_before']=before;evidence['financial_after']=financial()
        evidence['status']='pass'
    except Exception as error:
        evidence['status']='failed';evidence['error']=str(error);raise
    finally:
        for session in sessions:
            try:session.close()
            except Exception as error:evidence.setdefault('cleanup_errors',[]).append(str(error))
        if target is not None:target.close()
        evidence['sources_unchanged']=all((ROOT/name).read_bytes()==body for name,body in sources.items())
        evidence['finished_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()


if __name__=='__main__':main()

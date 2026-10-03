#!/usr/bin/env python3
"""Current email/scope subset in a disposable clone of retained schema153.

No hosted/source rows, Auth provider, OTP, carrier or device is used.
"""
import argparse, datetime, hashlib, json, pathlib, time, uuid
import collect_admin_combined_upgrade_uat as fixture

u, foundation = fixture.u, fixture.foundation
ROOT = fixture.ROOT
EMAIL = '99730000-0000-4000-8000-000000000001'
EMAIL_SID = '99730000-0000-4000-8000-000000010001'
EMAIL_OLD = '99730000-0000-4000-8000-000000010002'
STAGES = ['supabase/migrations/20260930213000_operator_email_auth.sql',
          'supabase/migrations/20260930220527_operator_email_cutover_guard.sql', *fixture.STAGES]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report-dir',required=True)
    report=pathlib.Path(parser.parse_args().report_dir).resolve()
    assert not report.exists(), 'Fresh evidence directory required'
    report.mkdir(parents=True)
    evidence={'kind':'current_email_scope_schema153_subset','started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'hosted_written':False,'shared_source_written':False,'source_rows_copied':False,'otp_sent':False,
              'signed_jwt_provider_tested':False,'full_hosted_upgrade_tested':False,'cases':[]}
    def save(): (report/'result.json').write_text(json.dumps(evidence,indent=2)+'\n')
    def case(name,fn):
        value=fn(); evidence['cases'].append({'name':name,'status':'pass','detail':value});save();print('PASS '+name,flush=True)
    def check(value): assert value,value;return True
    sql=lambda db,text:u.psql(db,text).stdout.strip()
    db='collect_email_scope_'+uuid.uuid4().hex[:12];made=False;sessions=[]
    u.SQL_LOG=report/'queries.log'
    u.CONCURRENCY_LOG=report/'concurrency.log'
    try:
        labels=json.loads(u.command([u.DOCKER,'inspect',u.CONTAINER,'--format','{{json .Config.Labels}}']).stdout)
        ports=json.loads(u.command([u.DOCKER,'inspect',u.CONTAINER,'--format','{{json .HostConfig.PortBindings}}']).stdout)
        assert labels['com.supabase.cli.project']==u.PROJECT and labels['com.docker.compose.project']==u.PROJECT
        assert all(p['HostPort']=='55722' for p in ports['5432/tcp'])
        assert json.loads(sql('postgres',"select jsonb_build_object('cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'));"))=={'cron':'off','net':'0'}
        dump=(fixture.BASELINE/'schema-only.sql').read_bytes();acl=(fixture.BASELINE/'api-acl.sql').read_bytes()
        assert fixture.sha(dump)==fixture.DUMP_HASH and fixture.sha(acl)==fixture.ACL_HASH
        bodies={p:(ROOT/p).read_bytes() for p in STAGES}
        (report/'executed-migrations').mkdir()
        for path,body in bodies.items():
            (report/'executed-migrations'/pathlib.Path(path).name).write_bytes(body)
        (report/'executed-runner.py').write_bytes(pathlib.Path(__file__).read_bytes())
        evidence['source_sha256']={p:fixture.sha(v) for p,v in bodies.items()}
        evidence['runner_sha256']=fixture.sha(pathlib.Path(__file__).read_bytes())
        evidence['baseline']={'schema_sha256':fixture.DUMP_HASH,'acl_sha256':fixture.ACL_HASH,'migration_count_at_capture':153}
        u.psql('postgres','create database '+db+' template template0;');made=True
        mock='create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);'
        u.psql(db,mock+dump.decode()+acl.decode());foundation.seed(db)
        u.psql(db,"update public.feature_flags set enabled=true where key='hybrid_sms_notifications';"+foundation.service(foundation.payment_sql('99710000-0000-4000-8000-000000049999',amount=50))+"update public.feature_flags set enabled=false where key='hybrid_sms_notifications';")
        initial=foundation.business_fingerprint(db)
        for path,body in bodies.items():
            result=u.psql(db,body.decode(),False);(report/(pathlib.Path(path).stem+'.install.log')).write_text(result.stdout+result.stderr)
            assert result.returncode==0,result.stderr
            case(path+' preserves nonempty financial/receipt evidence',lambda:check(initial==foundation.business_fingerprint(db)))
        u.psql(db,"insert into public.admin_permissions(name,description) values('overview.read','Synthetic'),('payments.read','Synthetic'),('admin_users.read','Synthetic'),('admin_users.manage','Synthetic');insert into public.admin_role_permissions(role_id,permission_name) select '%s',name from public.admin_permissions on conflict do nothing;"%foundation.ROLE)
        u.psql(db,"insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data) values('%s','authenticated','authenticated','info@ikanisa.com','{}','{}');insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values('%s','%s',clock_timestamp()-interval '1 hour',clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');"%(EMAIL,EMAIL_OLD,EMAIL))
        service=lambda text:json.loads(sql(db,foundation.service(text)).splitlines()[-1])
        case('authenticated cannot invoke privileged email reservation',lambda:u.expected_error(db,"select public.bootstrap_collect_email_operator_v1('%s');"%EMAIL,'42501'))
        case('anon cannot invoke privileged email reservation',lambda:u.expected_error(db,"select public.bootstrap_collect_email_operator_v1('%s');"%EMAIL,'42501',role='anon'))
        denied=u.psql(db,foundation.service("select public.bootstrap_collect_email_operator_v1('%s');"%u.UID),False)
        case('service cannot reserve another email/account',lambda:check(denied.returncode!=0 and '22023:' in denied.stderr))
        reserved=service("select public.bootstrap_collect_email_operator_v1('%s')"%EMAIL)
        case('selected reservation does not verify email',lambda:check(reserved['ok'] and not reserved['email_verified']))
        case('unverified reserved email has no approved identity',lambda:check(sql(db,"select collect_admin_access.approved_identity('%s');"%EMAIL)=='f'))
        u.psql(db,"update auth.users set email_confirmed_at=clock_timestamp() where id='%s';"%EMAIL)
        case('old session predating email approval/grant is refused',lambda:u.expected_error(db,'select public.admin_receipt_overview_v1();','42501',uid=EMAIL,sid=EMAIL_OLD))
        u.psql(db,"insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values('%s','%s',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');"%(EMAIL_SID,EMAIL))
        owner=lambda text:u.call(db,text,uid=EMAIL,sid=EMAIL_SID)
        case('verified fresh approved email reads actual Overview contract',lambda:check(owner('select public.admin_receipt_overview_v1();')['posted']['value_rwf']=='300'))
        identity=owner('select public.admin_current_user();')
        case('actual Admin identity uses email-approved owner authority',lambda:check(identity['user_id']==EMAIL and 'notifications.read' in identity['permissions']))
        before=sql(db,"select to_jsonb(a) from collect_admin_access.email_approvals a where user_id='%s';"%EMAIL)
        service("select public.bootstrap_collect_email_operator_v1('%s')"%EMAIL)
        case('reservation replay does not change approval age',lambda:check(before==sql(db,"select to_jsonb(a) from collect_admin_access.email_approvals a where user_id='%s';"%EMAIL)))
        approval=owner("select public.admin_get_operator_approval_v1('%s');"%EMAIL)
        case('versioned email approval read is exact, masked and active',lambda:check(
            set(approval)==set('contract_version user_id provider mode identity_masked approved_at expires_at status approved role_granted admin_access access_status'.split())
            and approval['contract_version']==1 and approval['provider']=='email' and approval['mode']=='transition'
            and approval['identity_masked']=='i***@***' and approval['status']=='approved'
            and approval['approved'] and approval['role_granted'] and approval['admin_access']
            and 'info@ikanisa.com' not in json.dumps(approval)))
        case('legacy list state identifies approved email as active without a phone label',lambda:check(
            json.loads(sql(db,"select collect_admin_access.account_state('%s');"%EMAIL))['status']=='approved'
            and json.loads(sql(db,"select collect_admin_access.account_state('%s');"%EMAIL))['phone_masked'] is None))
        def transaction_probe(body,expression):
            observed=sql(db,'begin;'+body+expression+';rollback;').splitlines()[-1]
            return json.loads(observed)
        # Fixtures simulate server-owned Auth verification; they never call the
        # hosted provider and user_metadata is not an approval source.
        secondary="update auth.users set email='second@collect.example',email_confirmed_at=clock_timestamp() where id='%s';"%u.UID
        for name,setup in [
            ('unverified email with user_metadata claim',"update auth.users set email='second@collect.example',email_confirmed_at=null,raw_user_meta_data='{\"email_verified\":true}' where id='%s';"%u.UID),
            ('mismatched verified email',secondary),
        ]:
            requested='wrong@collect.example' if name.startswith('mismatched') else 'second@collect.example'
            def probe(setup=setup,requested=requested):
                result=u.psql(db,'begin;'+setup+u.auth(EMAIL,EMAIL_SID)+"select public.admin_approve_email_operator_v1('%s','%s','Synthetic owner approval');rollback;"%(u.UID,requested),False)
                return check(result.returncode!=0 and '42501:' in result.stderr)
            case(name+' cannot be approved',probe)
        case('owner cannot approve own email again',lambda:u.expected_error(db,"select public.admin_approve_email_operator_v1('%s','info@ikanisa.com','Synthetic self approval');"%EMAIL,'22023',uid=EMAIL,sid=EMAIL_SID))
        case('owner cannot revoke own email approval',lambda:u.expected_error(db,"select public.admin_revoke_email_operator_v1('%s','Synthetic self revocation');"%EMAIL,'22023',uid=EMAIL,sid=EMAIL_SID))
        approved_secondary=transaction_probe(secondary+u.auth(EMAIL,EMAIL_SID),"select public.admin_approve_email_operator_v1('%s',' SECOND@COLLECT.EXAMPLE ','Synthetic owner approval')"%u.UID)
        case('verified target email approval is exact and normalized',lambda:check(approved_secondary=={'ok':True,'status':'approved','user_id':u.UID}))
        def replay_probe():
            setup=secondary+u.auth(EMAIL,EMAIL_SID)+"select public.admin_approve_email_operator_v1('%s','second@collect.example','Synthetic owner approval');"%u.UID
            setup+='reset role;'
            setup+="select set_config('collect.test_approval', (select approved_at::text from collect_admin_access.email_approvals where user_id='%s'),true);"%u.UID
            setup+="select set_config('collect.test_audit_count', (select count(*)::text from public.audit_logs where action='admin.email.approved' and entity_id='%s'),true);"%u.UID
            setup+=u.auth(EMAIL,EMAIL_SID)+"select public.admin_approve_email_operator_v1('%s','second@collect.example','Synthetic idempotent replay');"%u.UID
            # Read private evidence as the test harness, not through the API.
            setup+='reset role;'
            result=transaction_probe(setup,"select jsonb_build_object('same_age',(select approved_at::text=current_setting('collect.test_approval') from collect_admin_access.email_approvals where user_id='%s'),'same_audit_count',(select count(*)::text=current_setting('collect.test_audit_count') from public.audit_logs where action='admin.email.approved' and entity_id='%s'))"%(u.UID,u.UID))
            return check(result=={'same_age':True,'same_audit_count':True})
        case('email approval replay preserves age and does not duplicate audit',replay_probe)
        revoked_secondary=transaction_probe(secondary+u.auth(EMAIL,EMAIL_SID)+
            "select public.admin_approve_email_operator_v1('%s','second@collect.example','Synthetic owner approval');"%u.UID,
            "select public.admin_revoke_email_operator_v1('%s','Synthetic owner revocation')"%u.UID)
        case('different email account revocation has an exact bound receipt',lambda:check(revoked_secondary=={'ok':True,'status':'revoked','user_id':u.UID}))
        for name,permission,expression in [
            ('approval read','admin_users.read',"select public.admin_get_operator_approval_v1('%s');"%EMAIL),
            ('approval mutation','admin_users.manage',"select public.admin_approve_email_operator_v1('%s','second@collect.example','Synthetic owner approval');"%u.UID),
            ('revocation mutation','admin_users.manage',"select public.admin_revoke_email_operator_v1('%s','Synthetic owner revocation');"%u.UID),
        ]:
            def denied(permission=permission,expression=expression):
                result=u.psql(db,"begin;delete from public.admin_role_permissions where role_id='%s' and permission_name='%s';"%(foundation.ROLE,permission)+u.auth(EMAIL,EMAIL_SID)+expression+'rollback;',False)
                return check(result.returncode!=0 and '42501:' in result.stderr)
            case(name+' requires its independent current permission',denied)
        case('anon cannot inspect operator approval',lambda:u.expected_error(db,"select public.admin_get_operator_approval_v1('%s');"%EMAIL,'42501',role='anon'))
        case('approval read cannot enumerate an absent account',lambda:u.expected_error(db,"select public.admin_get_operator_approval_v1('99730000-0000-4000-8000-000000000099');",'22023',uid=EMAIL,sid=EMAIL_SID))
        def no_fallback():
            setup=secondary+"insert into collect_admin_access.email_approvals(user_id,email,reason,revoked_at) values('%s','second@collect.example','Synthetic revoked email',clock_timestamp());"%u.UID
            return check(transaction_probe(setup,"select to_jsonb(collect_admin_access.approved_identity('%s'))"%u.UID) is False)
        case('revoked email record prevents legacy phone fallback during transition',no_fallback)
        legacy_phone=sql(db,"select collect_admin_access.verified_phone('%s');"%u.UID)
        case('legacy approval remains compatible only during transition',lambda:check(owner(
            "select public.admin_approve_whatsapp('%s','%s','Synthetic legacy transition');"%(u.UID,legacy_phone))=={'ok':True,'status':'approved','user_id':u.UID}))
        def email_record_blocks_legacy():
            result=u.psql(db,'begin;'+secondary+
                "insert into collect_admin_access.email_approvals(user_id,email,reason,revoked_at) values('%s','second@collect.example','Synthetic revoked email',clock_timestamp());"%u.UID+
                u.auth(EMAIL,EMAIL_SID)+"select public.admin_approve_whatsapp('%s','%s','Synthetic obsolete dialog');rollback;"%(u.UID,legacy_phone),False)
            return check(result.returncode!=0 and 'operator_legacy_approval_disabled' in result.stderr)
        case('email enrollment prevents new legacy approvals even during transition',email_record_blocks_legacy)
        # Owner access itself must disappear when the reserved email is unverified;
        # another current operator may inspect its pending-verification state.
        pending=transaction_probe("update auth.users set email_confirmed_at=null where id='%s';"%EMAIL+u.auth(),"select public.admin_get_operator_approval_v1('%s')"%EMAIL)
        case('another operator sees pending verification without granting access',lambda:check(pending['status']=='pending_verification' and not pending['approved'] and not pending['admin_access']))
        # All mutations below roll back, so they cannot affect later cases.
        for name,mutation in [
          ('email changes',"update auth.users set email='different@collect.example' where id='%s';"%EMAIL),
          ('email becomes unverified',"update auth.users set email_confirmed_at=null where id='%s';"%EMAIL),
          ('email approval revoked',"update collect_admin_access.email_approvals set revoked_at=clock_timestamp() where user_id='%s';"%EMAIL),
          ('approval expires',"update collect_admin_access.email_approvals set approved_at=clock_timestamp()-interval '2 hours',expires_at=clock_timestamp()-interval '1 hour' where user_id='%s';"%EMAIL),
          ('grant revoked',"update public.admin_user_roles set revoked_at=clock_timestamp() where user_id='%s';"%EMAIL),
          ('session expires',"update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='%s';"%EMAIL_SID),
          ('account banned',"update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id='%s';"%EMAIL),
          ('required permission revoked',"delete from public.admin_role_permissions where role_id='%s' and permission_name='overview.read';"%foundation.ROLE),
        ]:
            def probe(mutation=mutation):
                result=u.psql(db,'begin;'+mutation+u.auth(EMAIL,EMAIL_SID)+'select public.admin_receipt_overview_v1();rollback;',False)
                return check(result.returncode!=0 and '42501:' in result.stderr)
            case(name+' denies fresh email authority',probe)
        def cutover_race():
            before=sql(db,"select to_jsonb(a) from collect_admin_access.whatsapp_approvals a where user_id='%s';"%u.UID)
            cutover=u.Session(db,'email_cutover_holder');stale=u.Session(db,'obsolete_approval_waiter');sessions.extend([cutover,stale])
            cutover.write('begin;'+u.auth(EMAIL,EMAIL_SID)+"select public.admin_set_operator_email_mode_v1('Synthetic concurrent email cutover');select 'CUTOVER_HELD';")
            cutover.read('CUTOVER_HELD')
            stale.write("set application_name='collect_email_obsolete_approval';begin;"+u.auth(EMAIL,EMAIL_SID)+
                "select public.admin_approve_whatsapp('%s','%s','Synthetic obsolete concurrent dialog');commit;select 'APPROVAL_COMPLETE';"%(u.UID,legacy_phone))
            waiting=False;deadline=time.monotonic()+8
            while time.monotonic()<deadline:
                waiting=sql(db,"select exists(select 1 from pg_stat_activity where datname='%s' and application_name='collect_email_obsolete_approval' and wait_event_type='Lock');"%db)=='t'
                if waiting:break
                time.sleep(.05)
            assert waiting,'Obsolete approval did not reach the authority lock'
            cutover.write("commit;select 'CUTOVER_COMMITTED';");cutover.read('CUTOVER_COMMITTED')
            output=stale.read('APPROVAL_COMPLETE')
            assert any('42501:' in line and 'operator_legacy_approval_disabled' in line for line in output),output
            assert before==sql(db,"select to_jsonb(a) from collect_admin_access.whatsapp_approvals a where user_id='%s';"%u.UID)
            return {'actually_waited_on_lock':waiting,'denied_after_cutover_commit':True,'legacy_approval_unchanged':True}
        case('queued legacy approval is refused after concurrent email cutover commits',cutover_race)
        case('email-only cutover requires current verified email operator',lambda:u.expected_error(db,"select public.admin_set_operator_email_mode_v1('Synthetic cutover');",'42501'))
        case('verified email cutover succeeds',lambda:check(owner("select public.admin_set_operator_email_mode_v1('Synthetic reviewed email cutover');")['mode']=='email'))
        case('old phone operator cannot access after cutover',lambda:u.expected_error(db,'select public.admin_receipt_overview_v1();','42501'))
        case('email owner remains eligible after cutover',lambda:check(owner('select public.admin_receipt_overview_v1();')['receipts_state']=='available'))
        case('stale legacy approval dialog is refused after email cutover',lambda:u.expected_error(db,
            "select public.admin_approve_whatsapp('%s','%s','Synthetic obsolete dialog');"%(u.UID,legacy_phone),'42501','operator_legacy_approval_disabled',uid=EMAIL,sid=EMAIL_SID))
        service_legacy=u.psql(db,foundation.service("select public.admin_bootstrap_whatsapp_approval('%s','%s','Synthetic obsolete bootstrap');"%(u.UID,legacy_phone)),False)
        case('service bootstrap cannot restore WhatsApp approval after email cutover',lambda:check(service_legacy.returncode!=0 and 'operator_legacy_approval_disabled' in service_legacy.stderr))
        legacy=owner("select public.admin_get_operator_approval_v1('%s');"%u.UID)
        case('email mode read explicitly disables legacy WhatsApp approval',lambda:check(legacy['mode']=='email' and legacy['provider']=='whatsapp' and legacy['status']=='legacy_disabled' and not legacy['admin_access']))
        case('sensitive reconciliation keeps aal2 requirement',lambda:check(sql(db,"select collect_security.reconciliation_actor_current('%s','%s');"%(EMAIL,EMAIL_SID))=='f'))
        case('private approval/policy tables retain RLS and no API select',lambda:check(sql(db,"select bool_and(c.relrowsecurity and not has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE')) from pg_class c cross join unnest(array['anon','authenticated','service_role']) r where c.relnamespace='collect_admin_access'::regnamespace and c.relname in ('email_approvals','operator_auth_policy');")=='t'))
        # Actual received observations: route/hash metadata is authoritative.
        u.psql(db,"insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network) values('%s','%s','+250788971001',repeat('a',64),'mtn_momo');"%(foundation.GROUP,u.UID))
        for n,hashchar in [(1,'a'),(2,'b'),(3,'a'),(4,'a'),(5,'a'),(6,'a'),(7,'a')]:
            raw='99730000-0000-4000-8000-%012d'%n
            u.psql(db,"insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,parse_status,received_at_device,receiver_momo_number_hash) values('%s','%s','%s','M-Money','Synthetic scope evidence',repeat('%s',64),'pending',clock_timestamp(),repeat('%s',64));"%(raw,foundation.GROUP,u.UID,str(n),hashchar))
            if n>=3:
                network='unknown' if n==4 else 'airtel_money' if n==7 else 'mtn_momo';direction='outgoing' if n==5 else 'incoming';payment='false' if n==3 else 'true'
                u.psql(db,"insert into public.parsed_payment_events(raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,direction,currency) values('%s','%s','%s',%s,'%s','%s','RWF');"%(raw,foundation.GROUP,u.UID,payment,network,direction))
                if n==6:u.psql(db,"update public.parsed_payment_events set receiver_phone_hash=repeat('b',64) where raw_sms_id='%s';"%raw)
        listing=owner('select public.admin_list_collect_transactions();')
        (report/'observed-scope-list.json').write_text(json.dumps(listing,indent=2)+'\n')
        case('only bound Rwanda route observation is classified as a transaction',lambda:check(listing['total']==1 and listing['rows'][0]['id']=='momo:99730000-0000-4000-8000-000000000001'))
        case('pending source remains parsing/verification evidence only',lambda:check(listing['rows'][0]['lifecycle']['allocation']=='pending_parse' and listing['rows'][0]['lifecycle']['ledger']=='not_posted'))
        case('private scope helper cannot be probed directly',lambda:u.expected_error(db,"select collect_security.rwanda_sms_scope('99730000-0000-4000-8000-000000000001');",'42501',uid=EMAIL,sid=EMAIL_SID))
        final=foundation.business_fingerprint(db)
        for key in initial:
            if key not in ('raw_payment_sms','parsed_payment_events'):
                case(key+' unchanged by email transition and read matrix',lambda key=key:check(initial[key]==final[key]))
        evidence['source_still_matches_executed_bytes']=all((ROOT/p).read_bytes()==b for p,b in bodies.items())
        assert evidence['source_still_matches_executed_bytes']
        evidence['status']='pass'
    except Exception as error:
        evidence['status']='failed';evidence['error']=str(error);save();raise
    finally:
        for session in sessions:session.close()
        if made:evidence['isolated_database_removed']=u.psql('postgres','drop database '+db+' with(force);',False).returncode==0
        u.SQL_LOG=None;u.CONCURRENCY_LOG=None;evidence['completed_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()

if __name__=='__main__':main()

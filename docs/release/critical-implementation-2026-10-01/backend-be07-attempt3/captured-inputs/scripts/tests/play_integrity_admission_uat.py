#!/usr/bin/env python3
"""Exact current-chain SQL admission UAT in a uniquely owned offline target.

No URL, provider, source row or hosted/shared write is accepted. Auth/storage
shape and installer/pg_net prerequisites are explicitly normalized locally.
"""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
from pathlib import Path
import time
import types

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / 'scripts/tests/collect_current_release_upgrade_uat.py'
BASELINE = ROOT / '.cache/receipt-foundation-attempt8/schema-only.sql'
PREREQUISITE = ROOT / 'scripts/sql/receipt_transport_platform_prerequisites.sql'
FIXTURE = ROOT / 'scripts/tests/play_integrity_admission_uat.sql'
ACTOR = '99570000-0000-4000-8000-000000000001'
OTHER = '99570000-0000-4000-8000-000000000002'
SID = '99570000-0000-4000-8000-000000000011'
REPLACEMENT = '99570000-0000-4000-8000-000000000012'
OTHER_SID = '99570000-0000-4000-8000-000000000021'
HASH = hashlib.sha256(b'+250788995701').hexdigest()
LOCAL_NET = ('alter function net.http_get(text,jsonb,jsonb,integer)security definer;'
             'alter function net.http_get(text,jsonb,jsonb,integer)set search_path=net;'
             'alter function net.http_post(text,jsonb,jsonb,jsonb,integer)security definer;'
             'alter function net.http_post(text,jsonb,jsonb,jsonb,integer)set search_path=net;')
SERVICE = "set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report-dir', required=True)
    args = parser.parse_args()
    report = Path(args.report_dir).resolve()
    assert not report.exists(), 'Fresh evidence directory required'
    report.mkdir(parents=True)
    captured = report / 'captured-inputs'
    paths = [Path(__file__), FIXTURE, HELPER, BASELINE, PREREQUISITE,
             ROOT / 'supabase/functions/verify-play-integrity/index.ts',
             ROOT / 'supabase/functions/_shared/integrity_admission.ts',
             ROOT / 'supabase/functions/_shared/integrity_admission_test.ts',
             ROOT / 'supabase/functions/_shared/integrity_policy.ts',
             ROOT / 'supabase/functions/_shared/play_integrity_binding.ts',
             ROOT / 'supabase/functions/_shared/roster_provenance.ts',
             ROOT / 'supabase/functions/_shared/supabase.ts',
             ROOT / 'supabase/functions/_shared/production_contract.ts',
             ROOT / 'scripts/tests/play_integrity_handler_test.ts']
    paths += sorted((ROOT / 'supabase/migrations').glob('*.sql'))
    before = {}
    for path in paths:
        body = path.read_bytes()
        relative = str(path.relative_to(ROOT))
        dest = captured / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(body)
        before[relative] = sha(body)
    helper = types.ModuleType('captured_integrity_helper')
    helper.__file__ = str(captured / HELPER.relative_to(ROOT))
    exec(compile(Path(helper.__file__).read_bytes(), helper.__file__, 'exec'), helper.__dict__)
    helper.ROOT = ROOT
    helper.BASELINE = captured / BASELINE.relative_to(ROOT)
    items = []
    for path in sorted((captured / 'supabase/migrations').glob('*.sql')):
        version, name = path.stem.split('_', 1)
        body = path.read_bytes()
        items.append(dict(path='supabase/migrations/' + path.name, version=version, name=name, body=body.decode(), sha256=sha(body)))
    assert len({i['version'] for i in items}) == len(items)
    assert items[-1]['path'] == 'supabase/migrations/20261001234000_play_integrity_admission.sql'
    result = dict(status='running', started_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  scope='Synthetic exact-current SQL admission/resource and immutable capability UAT', source_hashes=before,
                  cases=[], target={}, hosted_written=False, shared_database_written=False, provider_called=False,
                  source_rows_copied=False, signed_auth_provider_runtime_tested=False, policy_approved=False, final_acceptance=False)
    target = None
    counter = 0
    q = helper.quoted

    def save():
        (report / 'result.json').write_text(json.dumps(result, indent=2) + '\n')

    def case(name, ok, **details):
        result['cases'].append(dict(name=name, status='pass' if ok else 'fail', **details))
        save()
        print(('PASS ' if ok else 'FAIL ') + name, flush=True)
        if not ok:
            raise AssertionError(name)

    def execute(sql, check=True, label='actual service API'):
        return target.sql('begin;' + SERVICE + sql + 'commit;', check=check, label=label)

    def data(sql):
        return json.loads(execute(sql).stdout.strip().splitlines()[-1])

    def snapshot():
        return target.scalar("select jsonb_build_array((select count(*)from collect_integrity.reservations),"
                             "(select count(*)from collect_integrity.phases),(select count(*)from collect_integrity.completions),"
                             "(select count(*)from public.native_action_capabilities));")

    def deny(label, sql, state):
        prior = snapshot()
        response = execute(sql, check=False, label=label)
        case(label, response.returncode != 0 and state in response.stderr and snapshot() == prior,
             expected_sqlstate=state, observed_exit=response.returncode)

    def payload(action):
        if action == 'group.create':
            return dict(group_name='Synthetic private group', group_is_public=False, receiver_momo_number_hash=HASH)
        return dict(client_envelope_id='99570000-0000-4000-8000-000000000061', raw_sender='M-Money', raw_body_sha256='b'*64, receiver_momo_number_hash=HASH, received_at_device=None)

    def request(action='group.create', actor=ACTOR, session=SID):
        nonlocal counter
        counter += 1
        return dict(actor=actor, session=session, nonce='99570000-0000-4000-8000-%012d' % (1000+counter),
                    action=action, request_hash=sha(('request'+str(counter)).encode()),
                    token_hash=sha(('token'+str(counter)).encode()), receiver_hash=HASH, payload=payload(action))

    def reserve(req):
        return 'select public.reserve_play_integrity_admission_v1(' + ','.join(q(req[k]) for k in ['actor','session','nonce','action','request_hash','token_hash','receiver_hash']) + ',' + q(json.dumps(req['payload'])) + '::jsonb);'

    def begin(req, rid, phase='oauth'):
        return 'select public.begin_play_integrity_admission_v1(' + ','.join(map(q,[req['actor'],req['session'],rid,phase])) + ');'

    def complete(req, rid, body=None):
        return 'select public.complete_play_integrity_admission_v1(' + ','.join(map(q,[req['actor'],req['session'],rid])) + ',' + q(json.dumps(req['payload'] if body is None else body)) + "::jsonb,'app.cool.mobile','PLAY_RECOGNIZED',array['MEETS_DEVICE_INTEGRITY'],clock_timestamp(),12,200);"

    def finish(req, rid, outcome='ambiguous'):
        return 'select public.finish_play_integrity_admission_v1(' + ','.join(map(q,[req['actor'],req['session'],rid,outcome])) + ',12,503);'

    def reset_policy():
        target.sql('update collect_integrity.policy set actor_action_minute=100,actor_daily=10000,actor_active=10,global_minute=10000,global_daily=100000,global_active=100;')

    def wait_block(label):
        deadline = time.monotonic()+10
        while time.monotonic()<deadline:
            info = target.json("select coalesce(jsonb_agg(jsonb_build_object('wait',wait_event_type,'blockers',pg_blocking_pids(pid))),'[]')from pg_stat_activity where application_name="+q(label)+";")
            if any(i['wait']=='Lock' and i['blockers'] for i in info):
                return info
            time.sleep(.08)
        raise AssertionError('No real blocking relation observed: '+label)

    def wait_sleep(label):
        deadline=time.monotonic()+10
        while time.monotonic()<deadline:
            if target.scalar('select exists(select 1 from pg_stat_activity where application_name='+q(label)+"and wait_event='PgSleep');")=='t': return
            time.sleep(.08)
        raise AssertionError('Holder not observed: '+label)

    def submit(executor, label, sql):
        return executor.submit(target.sql, 'set application_name='+q(label)+";set statement_timeout='15s';begin;"+sql,
                               check=False,label='actual concurrent '+label)

    save()
    try:
        platform, provenance = helper.platform_shape()
        (report/'platform-schema-only.sql').write_text(platform)
        result['platform_shape']=provenance
        with helper.Target(report,'integrity',result['target']) as target:
            target.sql(platform,label='captured row-free platform shape')
            for item in items:
                if item['version']=='20261001160000':
                    target.sql(LOCAL_NET,user='supabase_admin',label='local image net metadata normalization')
                    target.sql((captured/PREREQUISITE.relative_to(ROOT)).read_text(),user='supabase_admin',label='captured private-reader platform prerequisite')
                    result['platform_prerequisite']=dict(local_net_sha256=sha(LOCAL_NET.encode()),private_reader_sha256=before[str(PREREQUISITE.relative_to(ROOT))],scope='local image installer metadata only')
                helper.apply(target,[item],result['target'])
            case('every exact current migration replays',int(target.scalar('select count(*)from supabase_migrations.schema_migrations;'))==len(items),count=len(items))
            target.sql("select set_config('collect.integrity_qa','isolated_clone',false);"+(captured/FIXTURE.relative_to(ROOT)).read_text(),label='synthetic exact-session/profile/consent fixtures')
            defaults=target.json('select to_jsonb(p)from collect_integrity.policy p;')
            result['engineering_policy_defaults']=defaults
            case('bounded engineering policy defaults installed',defaults==dict(id=True,version=1,actor_action_minute=10,actor_daily=500,actor_active=2,global_minute=100,global_daily=5000,global_active=20,lease_seconds=180))
            acl=target.json("select jsonb_build_object('public_rpc_count',(select count(*)from pg_proc where pronamespace='public'::regnamespace and proname in('reserve_play_integrity_admission_v1','begin_play_integrity_admission_v1','complete_play_integrity_admission_v1','finish_play_integrity_admission_v1')and has_function_privilege('service_role',oid,'EXECUTE')and not has_function_privilege('authenticated',oid,'EXECUTE')and not has_function_privilege('anon',oid,'EXECUTE')),'legacy_revoked',not has_function_privilege('service_role','public.mint_native_action_capability(uuid,text,text,jsonb,text,text,text,text[],timestamptz)','EXECUTE'),'private_schema_denied',not has_schema_privilege('service_role','collect_integrity','USAGE'),'private_table_denied',not has_table_privilege('service_role','collect_integrity.reservations','INSERT'));" )
            case('only four service APIs; private evidence and sessionless mint denied',acl==dict(public_rpc_count=4,legacy_revoked=True,private_schema_denied=True,private_table_denied=True))
            reset_policy()
            healthy=[]
            for action in ['group.create','sms.ingest']:
                req=request(action);r=data(reserve(req));rid=r['reservation_id']
                case(action+' exact actor/session/content reservation',r['state']=='reserved'and r['actor_id']==ACTOR and r['session_id']==SID and r['token_sha256']==req['token_hash'])
                case(action+' reserve lost acknowledgement safely resumes before any Google phase',data(reserve(req))==r)
                deny(action+' completion requires a decode admission',complete(req,rid),'55000')
                deny(action+' decode cannot precede OAuth',begin(req,rid,'decode'),'55000')
                case(action+' OAuth admitted once',data(begin(req,rid))['state']=='oauth_started')
                deny(action+' handler restart cannot redispatch OAuth',begin(req,rid),'55000')
                deny(action+' uncertain external work cannot auto-reserve again',reserve(req),'55000')
                case(action+' decode admitted once',data(begin(req,rid,'decode'))['state']=='decode_started')
                deny(action+' decode replay denied',begin(req,rid,'decode'),'55000')
                altered=dict(req['payload'],extra='different')
                deny(action+' changed completion content denied',complete(req,rid,altered),'22023')
                done=data(complete(req,rid))
                case(action+' actual retained mint succeeds atomically',done['status']=='pass'and done['request_hash']==req['request_hash']and done['action']==action)
                case(action+' lost completion acknowledgement returns same capability',data(reserve(req))['result']==done and data(complete(req,rid))==done)
                case(action+' ambiguous cleanup never overwrites committed success',data(finish(req,rid))['state']=='completed')
                replacement=dict(req,session=REPLACEMENT)
                deny(action+' same-user replacement cannot inherit reservation',reserve(replacement),'55000')
                deny(action+' same-user replacement cannot begin old work',begin(replacement,rid),'42501')
                deny(action+' same-user replacement cannot complete old work',complete(replacement,rid),'42501')
                healthy.append((req,rid))
            req=request();r=data(reserve(req));rid=r['reservation_id']
            deny('different actor cannot acquire originating-session reservation',begin(dict(req,actor=OTHER,session=OTHER_SID),rid),'42501')
            replay=request();replay['token_hash']=req['token_hash'];deny('same token across different nonce denied',reserve(replay),'55000')
            for key,value in [('action','sms.ingest'),('request_hash','c'*64),('token_hash','d'*64),('payload',dict(req['payload'],group_name='Other'))]:
                changed=dict(req,**{key:value})
                if key=='action':changed['payload']=payload(value)
                deny('same nonce cannot replace '+key,reserve(changed),'55000')
            for label,change,undo in [
                ('logout',"delete from auth.sessions where id="+q(SID)+';',"insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values("+q(SID)+','+q(ACTOR)+",clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');"),
                ('expiry',"update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id="+q(SID)+';',"update auth.sessions set not_after=clock_timestamp()+interval '1 hour'where id="+q(SID)+';'),
                ('ban',"update auth.users set banned_until=clock_timestamp()+interval '1 hour'where id="+q(ACTOR)+';',"update auth.users set banned_until=null where id="+q(ACTOR)+';'),
                ('anonymous',"update auth.users set is_anonymous=true where id="+q(ACTOR)+';',"update auth.users set is_anonymous=false where id="+q(ACTOR)+';'),
                ('consent revocation',"update public.receiver_mode_consents set enabled=false where user_id="+q(ACTOR)+';',"update public.receiver_mode_consents set enabled=true where user_id="+q(ACTOR)+';')]:
                target.sql(change)
                deny(label+' blocks new reservation',reserve(request()),'42501')
                deny(label+' blocks external phase',begin(req,rid),'42501')
                target.sql(undo)
            malformed=request();malformed['payload']['group_is_public']=True;deny('public group payload denied',reserve(malformed),'22023')
            malformed=request();malformed['payload']['group_name']='x'*121;deny('oversized purpose payload denied',reserve(malformed),'22023')
            malformed=request('sms.ingest');malformed['payload']['raw_sender']=None;deny('missing SMS binding denied',reserve(malformed),'22023')
            malformed=request();malformed['payload']['padding']='x'*16384;deny('SQL payload byte bound denied',reserve(malformed),'22023')
            target.sql("update public.receiver_mode_consents set created_at=clock_timestamp()-interval '11 minutes'where user_id="+q(ACTOR)+';')
            deny('stale SMS consent denied before admission',reserve(request('sms.ingest')),'42501')
            target.sql('update public.receiver_mode_consents set created_at=clock_timestamp()where user_id='+q(ACTOR)+';')
            # Unknown external outcomes retain active capacity until lease;
            # spent minute/day counters are never refunded by cleanup.
            prior_count=int(target.scalar('select count(*)from collect_integrity.reservations;'))
            data(begin(req,rid));data(finish(req,rid))
            case('ambiguous cleanup retains spent history',int(target.scalar('select count(*)from collect_integrity.reservations;'))==prior_count)
            deny('ambiguous result requires reconciliation rather than token redispatch',reserve(req),'55000')
            active="select count(*)from collect_integrity.reservations a where actor_id="+q(ACTOR)+"and expires_at>clock_timestamp()and not exists(select 1 from collect_integrity.completions c where c.reservation_id=a.id and c.outcome in('completed','rejected','failed'))"
            case('uncertain work remains in outstanding resource bound',int(target.scalar(active+';'))>=1)
            saturation=[('actor_action_minute',"select count(*)from collect_integrity.reservations where actor_id="+q(ACTOR)+"and action='group.create'and reserved_at>clock_timestamp()-interval '1 minute'"),
                        ('actor_daily','select count(*)from collect_integrity.reservations where actor_id='+q(ACTOR)),('actor_active',active),
                        ('global_minute',"select count(*)from collect_integrity.reservations where reserved_at>clock_timestamp()-interval '1 minute'"),
                        ('global_daily','select count(*)from collect_integrity.reservations'),('global_active',active.replace('actor_id='+q(ACTOR)+'and ',''))]
            for column,countsql in saturation:
                reset_policy();limit=int(target.scalar(countsql+';'));assert limit>=1
                target.sql('update collect_integrity.policy set '+column+'='+str(limit)+';')
                deny(column+' saturation denies new costly work',reserve(request()),'53300')
            reset_policy()
            # Expired immutable fixture: never edit admitted provenance.
            expired=request();expired_id='99570000-0000-4000-8000-000000007001'
            target.sql("insert into collect_integrity.reservations(id,actor_id,session_id,nonce,action,request_hash,token_sha256,receiver_hash,payload_sha256,binding_sha256,policy_version,reserved_at,expires_at)values("+','.join(map(q,[expired_id,ACTOR,SID,expired['nonce'],'group.create',expired['request_hash'],expired['token_hash'],HASH,sha(json.dumps(expired['payload']).encode()),'e'*64]))+",1,clock_timestamp()-interval '4 minutes',clock_timestamp()-interval '1 minute');",label='synthetic immutable expired reservation')
            deny('expired reservation never admits provider phase',begin(expired,expired_id),'55000')
            deny('expired reservation never completes entitlement',complete(expired,expired_id),'22023')
            response=target.sql('begin isolation level repeatable read;'+SERVICE+reserve(request())+'commit;',check=False)
            case('old transaction snapshots cannot make quota decisions',response.returncode!=0 and '40001'in response.stderr)
            for table in ['reservations','phases','completions']:
                response=target.sql('update collect_integrity.'+table+' set '+('nonce=nonce'if table=='reservations'else 'reservation_id=reservation_id')+';',check=False)
                case(table+' immutable evidence cannot be rewritten',response.returncode!=0 and '55000'in response.stderr)
            # Atomic row-version quota fence: one unit remains, two real
            # concurrent SQL transactions; observe actual blocking PIDs.
            for scope in ['actor_active','global_active']:
                reset_policy()
                count=int(target.scalar((active if scope=='actor_active'else active.replace('actor_id='+q(ACTOR)+'and ',''))+';'))
                target.sql('update collect_integrity.policy set '+scope+'='+str(count+1)+';')
                a=request();b=request(actor=ACTOR if scope=='actor_active'else OTHER,session=SID if scope=='actor_active'else OTHER_SID)
                with concurrent.futures.ThreadPoolExecutor(max_workers=2)as ex:
                    first=submit(ex,scope+'-holder',SERVICE+reserve(a)+'select pg_sleep(2);commit;')
                    wait_sleep(scope+'-holder')
                    second=submit(ex,scope+'-waiter',SERVICE+reserve(b)+'commit;')
                    blocked=wait_block(scope+'-waiter')
                    one,two=first.result(),second.result()
                case(scope+' concurrency admits exactly one remaining slot',one.returncode==0 and two.returncode!=0 and '53300'in two.stderr,blocking=blocked)
            reset_policy()
            a=request();rid=data(reserve(a))['reservation_id']
            with concurrent.futures.ThreadPoolExecutor(max_workers=2)as ex:
                first=submit(ex,'phase-holder',SERVICE+begin(a,rid)+'select pg_sleep(2);commit;');wait_sleep('phase-holder')
                second=submit(ex,'phase-waiter',SERVICE+begin(a,rid)+'commit;');blocked=wait_block('phase-waiter')
                one,two=first.result(),second.result()
            case('concurrent phase/restart cannot redispatch the same provider operation',one.returncode==0 and two.returncode!=0 and '55000'in two.stderr,blocking=blocked)
            # Revocation first wins; phase first holds authorization through
            # its transaction. No SQL transaction spans real provider IO.
            for ordering in ['revocation-first','phase-first']:
                reset_policy();a=request();rid=data(reserve(a))['reservation_id']
                revoke='update auth.sessions set not_after=clock_timestamp()-interval \'1 second\'where id='+q(SID)+';'
                with concurrent.futures.ThreadPoolExecutor(max_workers=2)as ex:
                    if ordering=='revocation-first':
                        first=submit(ex,'revocation-holder',revoke+'select pg_sleep(2);commit;');wait_sleep('revocation-holder')
                        second=submit(ex,'admission-waiter',SERVICE+begin(a,rid)+'commit;');blocked=wait_block('admission-waiter')
                    else:
                        first=submit(ex,'admission-holder',SERVICE+begin(a,rid)+'select pg_sleep(2);commit;');wait_sleep('admission-holder')
                        second=submit(ex,'revocation-waiter',revoke+'commit;');blocked=wait_block('revocation-waiter')
                    one,two=first.result(),second.result()
                case(ordering+' uses actual Auth and admission locks',one.returncode==0 and (two.returncode==0 if ordering=='phase-first'else two.returncode!=0 and '42501'in two.stderr),blocking=blocked)
                deny(ordering+' revoked session cannot later decode',begin(a,rid,'decode'),'42501')
                target.sql('update auth.sessions set not_after=clock_timestamp()+interval \'1 hour\'where id='+q(SID)+';')
            result['status']='pass'
    except Exception as error:
        result['status']='fail';result['error']=str(error)
        raise
    finally:
        result['completed_at']=datetime.datetime.now(datetime.timezone.utc).isoformat()
        drift=[path for path,digest in before.items()if not(ROOT/path).is_file()or sha((ROOT/path).read_bytes())!=digest]
        result['source_drift']=drift;result['source_current_at_finish']=not drift
        if drift:result['status']='stale-source'
        save()


if __name__=='__main__':
    main()

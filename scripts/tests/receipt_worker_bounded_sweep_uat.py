#!/usr/bin/env python3
"""Focused private-staged worker query proof; owned network-none PG17 only.

The 177 exact unchanged fixture prerequisites and four affected feature
prerequisites are composed, not the whole current release candidate. Financial
rows are synthetic canonical postings. Role claims are SQL trust fixtures.
"""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
import pathlib
import sys
import time
import types
import uuid

ROOT = pathlib.Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
SOURCE = pathlib.Path('/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-08')
STAGE = pathlib.Path(__file__).resolve().parent
MIGRATION = STAGE/'20261001210000_receipt_worker_bounded_sweep.sql'
FEATURES = ['20261001110000_receipt_operational_authority.sql',
            '20261001120000_operational_exception_lifecycle.sql',
            '20261001140000_receipt_deferral_exceptions.sql',
            '20261001150000_receipt_exception_worker.sql']
FUNCTIONS = ['collect_ops.queue_receipt_exception_source()',
             'public.process_receipt_deferral_exceptions_v1(uuid,integer,timestamptz)',
             'collect_ops.receipt_exception_source(text,uuid)',
             'collect_ops.receipt_exception_quota_available(text,uuid)']
PUBLIC_SCAN = FUNCTIONS[1]
sha = lambda b: hashlib.sha256(b).hexdigest()
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
ident = lambda: str(uuid.uuid4())

def save(path, value):
    path.write_text(json.dumps(value, indent=2)+'\n')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--report-dir', required=True)
    parser.add_argument('--migration', type=pathlib.Path, default=MIGRATION if MIGRATION.is_file() else ROOT/'supabase/migrations'/MIGRATION.name)
    args = parser.parse_args()
    report = pathlib.Path(args.report_dir).resolve()
    assert not report.exists()
    report.mkdir(parents=True)
    inputs = report/'inputs'
    inputs.mkdir()
    (inputs/'migrations').mkdir()
    sources = {}
    def capture(path, destination):
        b = path.read_bytes()
        sources[str(path)] = b
        destination.write_bytes(b)
        return b
    runner = capture(pathlib.Path(__file__), inputs/'executed-runner.py')
    helper = capture(SOURCE/'scripts/tests/collect_current_release_upgrade_uat.py', inputs/'executed-helper.py')
    marker = capture(SOURCE/'.collect-release-candidate.json', inputs/'source08-marker.json')
    baseline = capture(ROOT/'.cache/receipt-foundation-attempt8/schema-only.sql', inputs/'row-free-platform.sql')
    staged = capture(args.migration.resolve(), inputs/MIGRATION.name)
    metadata = json.loads(marker)
    items = []
    for p in sorted((SOURCE/'supabase/migrations').glob('*.sql')):
        b = capture(p, inputs/'migrations'/p.name)
        assert b == (ROOT/'supabase/migrations'/p.name).read_bytes()
        assert sha(b) == metadata['source_files'][str(p.relative_to(SOURCE))]['sha256']
        sources[str(ROOT/'supabase/migrations'/p.name)] = b
        version, name = p.stem.split('_', 1)
        items.append(dict(version=version, name=name, path=str(p.relative_to(SOURCE)), sha256=sha(b), body=b.decode()))
    assert len(items) == 177
    bodies = {name: capture(ROOT/'supabase/migrations'/name, inputs/name) for name in FEATURES}
    runtime = pathlib.Path(sys.executable).resolve()
    runtime_hash = sha(runtime.read_bytes())
    result = dict(status='running', scope='177 unchanged captured fixture prerequisites plus exact 110000/120000/140000/150000 and staged 210000; excludes complete current187 replay',
                  started_at=now(), checks=[], target={}, migration_sha256=sha(staged), runner_sha256=sha(runner),
                  helper_sha256=sha(helper), baseline_sha256=sha(baseline), python_path=str(runtime), python_sha256=runtime_hash,
                  source_bindings={str(p): sha(b) for p,b in sources.items()}, hosted_written=False,
                  device_used=False, sms_sent=False, provider_called=False, jwt_verified=False,
                  complete_retention=False, canonical_source_written=False)
    save(report/'execution-binding.json', {k:v for k,v in result.items() if k not in ('checks','target')})
    m = types.ModuleType('captured_helper')
    m.__file__ = str(inputs/'executed-helper.py')
    exec(compile(helper, m.__file__, 'exec'), m.__dict__)
    m.ROOT = SOURCE
    m.BASELINE = inputs/'row-free-platform.sql'
    q = m.quoted
    def case(name, ok=True):
        result['checks'].append(dict(name=name, passed=bool(ok)))
        save(report/'result.json', result)
        print(('PASS ' if ok else 'FAIL ')+name, flush=True)
        if not ok:
            raise AssertionError(name)
    try:
        with m.Target(report, 'bounded_sweep', result['target']) as t:
            save(report/'target-handle.json', result['target'])
            platform, provenance = m.platform_shape()
            save(report/'platform-provenance.json', provenance)
            t.sql(platform, label='captured row-free platform')
            m.apply(t, items[:124], result['target'])
            m.seed_populated(t, result['target'], case)
            m.apply(t, items[124:], result['target'])
            for name,b in bodies.items():
                t.sql(b.decode(), label='exact affected feature prerequisite '+name)
            auth = "set local role authenticated;select set_config('request.jwt.claims',"+q(json.dumps(dict(sub=m.UID,session_id=m.SID,role='authenticated',aal='aal1')))+",true);"
            service = "set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
            def call(expression, as_service=False):
                return json.loads(t.sql('begin;'+(service if as_service else auth)+'select '+expression+';commit;').stdout.strip().splitlines()[-1])
            def error(expression, code, label, as_service=False):
                value = t.sql('begin;'+(service if as_service else auth)+'select '+expression+';rollback;', check=False)
                case(label, value.returncode != 0 and code in value.stderr)
            t.sql("begin;update auth.users set email='bounded-owner@example.test',email_confirmed_at=clock_timestamp()where id="+q(m.UID)+";insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values("+q(m.UID)+",'bounded-owner@example.test',clock_timestamp()-interval '2 minutes','Synthetic bounded sweep owner');commit;")
            # Generate representative independent sources through real canonical
            # posting, rather than fabricating snapshot/journal balance rows.
            wallet = sha(b'+250788971001')
            t.sql("begin;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);do $$declare n integer;p uuid;ref text;begin for n in 1..1100 loop p:=('99790000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;ref:='BOUNDED-SOURCE-'||n::text;insert into public.payments(id,collection_id,member_record_id,receiver_user_id,receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status)values(p,"+q(m.GROUP)+","+q(m.MEMBER)+","+q(m.UID)+","+q(wallet)+",1,ref,'mtn_momo','manual_admin','review');perform public.confirm_provider_payment(p,'mtn_momo',ref,'SYNTHETIC-'||ref,"+q(wallet)+",1,clock_timestamp(),repeat('b',64));end loop;end$$;commit;", label='1100 synthetic canonical posted financial sources')
            snapshots = t.json("select jsonb_agg(id order by id)from collect_hybrid.momo_balance_snapshots where payment_id::text like '99790000-%';")
            assert len(snapshots) == 1100
            low, heavy, future, handled_only = snapshots[0], snapshots[550], snapshots[800], snapshots[-1]
            principal = t.scalar("select id from collect_supervisor.identities limit 1;") if t.scalar('select exists(select 1 from collect_supervisor.identities);') == 't' else ident()
            if t.scalar('select exists(select 1 from collect_supervisor.identities where id='+q(principal)+');') == 'f':
                # Use the existing owner enrollment API; no key is proved and
                # the identity remains pending, so no run authority is created.
                pub = 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEaxfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54WK84zV2sxXs7LtkBoN79R9Q=='
                principal = call('public.admin_enroll_receipt_operations_identity_v2('+','.join([q(ident()),q(pub),q(sha(__import__('base64').b64decode(pub))),"clock_timestamp()+interval '1 day'"])+')')['principal_id']
            t.sql("insert into collect_receipt_operations.runs(id,request_id,principal_id,fence_version,policy_revision,mode,collection_ids,started_at,expires_at)select ('997a0000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,gen_random_uuid(),"+q(principal)+",n,1,'Shadow',array["+q(m.GROUP)+"]::uuid[],statement_timestamp(),statement_timestamp()+interval '120 seconds'from generate_series(1,8000)n;", label='installer-only immutable duplicate-history run anchors')
            t.sql("insert into collect_receipt_operations.requests(request_id,principal_id,action,request_sha256,input,issued_at,recorded_at,result)select ('997b0000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,"+q(principal)+",'prove_key',repeat('c',64),'{}',clock_timestamp(),clock_timestamp(),'{}'from generate_series(1,6000)n;", label='installer-only request anchors; never armed or dispatched')
            # Lifetime duplicates of one source, an earlier handled row and a
            # source represented solely by successful handling.
            t.sql("insert into collect_receipt_operations.backlog_results select r.id,"+q(heavy)+",case when r.fence_version%2=0 then 'QUOTA_EXHAUSTED'else 'CONTACT_MISSING'end,false,null,clock_timestamp()from collect_receipt_operations.runs r where fence_version<=6000;insert into collect_ops.receipt_backlog_budget_deferrals select ('997b0000-0000-4000-8000-'||lpad(r.fence_version::text,12,'0'))::uuid,r.id,"+q(heavy)+",clock_timestamp()from collect_receipt_operations.runs r where fence_version<=6000;insert into collect_receipt_operations.backlog_results values('997a0000-0000-4000-8000-000000007000',"+q(heavy)+",'RECEIPT_EXISTS',true,(select id from collect_hybrid.sms_notification_outbox limit 1),clock_timestamp()),('997a0000-0000-4000-8000-000000007001',"+q(handled_only)+",'RECEIPT_EXISTS',true,(select id from collect_hybrid.sms_notification_outbox limit 1),clock_timestamp());", label='actual producer append of duplicate-heavy historical backlog and budget rows')
            financial_tables = [('public','payments'),('public','payment_provider_confirmations'),('collect_hybrid','momo_journal_entries'),('collect_hybrid','momo_journal_lines'),('collect_hybrid','momo_balance_snapshots'),('collect_hybrid','member_balances'),('collect_hybrid','collection_balances'),('collect_hybrid','sms_notification_outbox'),('collect_hybrid','sms_notification_attempts'),('collect_receipt_policy','content_evidence')]
            financial_spec = m.columns(t, financial_tables)
            financial = lambda: m.fingerprints(t, financial_spec)
            finance = financial()
            private_spec = m.columns(t, [('collect_ops', name) for name in ['receipt_exception_work','receipt_exception_progress','receipt_exception_scans','receipt_exception_scan_observations','receipt_backlog_budget_deferrals','receipt_worker_jobs','receipt_worker_receipts','receipt_worker_configuration','receipt_worker_configuration_history']])
            original_private = m.fingerprints(t, private_spec)
            function_attrs = lambda: t.json("select jsonb_agg(jsonb_build_object('oid',p.oid,'owner',p.proowner,'acl',p.proacl,'config',p.proconfig,'args',p.proargtypes::text,'result',p.prorettype,'volatile',p.provolatile,'definer',p.prosecdef)order by p.oid)from pg_proc p where p.pronamespace in('public'::regnamespace,'collect_ops'::regnamespace);")
            attrs = function_attrs()
            cron = t.json('select jsonb_agg(to_jsonb(j)order by jobid)from cron.job j;')
            old_defs = {name:t.json('select to_jsonb(pg_get_functiondef('+q(name)+'::regprocedure));') for name in FUNCTIONS}
            old_source = t.json('select collect_ops.receipt_exception_source(\'receipt_backlog\','+q(heavy)+');')
            old_quota = t.scalar('select collect_ops.receipt_exception_quota_available(\'receipt_backlog\','+q(heavy)+');')
            # Existing exact ACK must remain byte-identical across migration.
            first_id, first_expiry = ident(), t.scalar("select collect_ops.utc(clock_timestamp()+interval '100 seconds');")
            first = call('public.process_receipt_deferral_exceptions_v1('+','.join([q(first_id),'1',q(first_expiry)])+')', True)
            original_private = m.fingerprints(t, private_spec)
            t.sql("alter role postgres nosuperuser;", user='supabase_admin', label='demote fixture owner before new migration and changed-body proof')
            case('new migration installer is genuinely NOSUPERUSER', t.scalar('select not rolsuper from pg_roles where rolname=current_user;') == 't')
            for name in FUNCTIONS:
                drift = old_defs[name].replace('$function$', '$function$-- unexpected predecessor\n', 1)
                assert drift != old_defs[name]
                bad = t.sql('begin;'+drift+';\n'+staged.decode(), check=False, label='fail-closed predecessor drift '+name)
                case('drift refuses atomically for '+name, bad.returncode != 0 and 'receipt_worker_bounded_sweep_predecessor_unavailable' in bad.stderr and t.scalar("select to_regclass('collect_ops.receipt_backlog_sweep_sources')is null;") == 't' and function_attrs() == attrs)
            # A table-lock holder queues the actual migration. A producer that
            # arrives behind its pending lock must use the new definer registry
            # hook after commit, so no source can fall between backfill and hook.
            with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
                holder = pool.submit(t.sql, "begin;set local application_name='bounded-sweep-held-producer';lock table collect_receipt_operations.backlog_results in row exclusive mode;select pg_sleep(2);commit;")
                for _ in range(80):
                    if t.scalar("select exists(select 1 from pg_stat_activity where application_name='bounded-sweep-held-producer'and wait_event='PgSleep');") == 't':break
                    time.sleep(.01)
                else:raise AssertionError('producer table lock fixture unavailable')
                migrating = pool.submit(t.sql, "set application_name='bounded-sweep-migration';"+staged.decode(), label='exact staged migration under ordinary owner')
                for _ in range(80):
                    if t.scalar("select exists(select 1 from pg_stat_activity where application_name='bounded-sweep-migration'and wait_event='relation');") == 't':break
                    time.sleep(.01)
                else:raise AssertionError('actual migration table wait unavailable')
                arriving = pool.submit(t.sql, "begin;set local application_name='bounded-sweep-arriving-producer';insert into collect_receipt_operations.backlog_results values('997a0000-0000-4000-8000-000000007002',"+q(future)+",'CONTACT_MISSING',false,null,clock_timestamp());commit;", label='producer committed behind pending migration lock')
                for _ in range(80):
                    if t.scalar("select exists(select 1 from pg_stat_activity where application_name='bounded-sweep-arriving-producer'and wait_event='relation');") == 't':break
                    time.sleep(.01)
                else:raise AssertionError('arriving producer was not queued behind migration')
                holder.result();migrating.result();arriving.result()
            case('producer queued behind migration is visible in registry and independent work', t.scalar('select exists(select 1 from collect_ops.receipt_backlog_sweep_sources where snapshot_id='+q(future)+')and exists(select 1 from collect_ops.receipt_exception_work where source_id='+q(future)+"and origin='backlog');") == 't')
            case('changed definitions retain every function OID signature owner ACL and control attribute', function_attrs() == attrs)
            case('migration and registry do not alter finance receipts flags policy or cron', financial() == finance and t.json('select jsonb_agg(to_jsonb(j)order by jobid)from cron.job j;') == cron)
            case('preexisting sweep progress ACK and worker evidence remain exact', m.fingerprints(t, {k:v for k,v in private_spec.items() if k not in ['collect_ops.receipt_exception_work']}) == {k:v for k,v in original_private.items() if k not in ['collect_ops.receipt_exception_work']} )
            case('registry exactly matches predecessor lifetime UNION membership', t.scalar('select not exists((select snapshot_id from collect_ops.receipt_backlog_sweep_sources except(select snapshot_id from collect_receipt_operations.backlog_results where not business_handled union select snapshot_id from collect_ops.receipt_backlog_budget_deferrals))union all((select snapshot_id from collect_receipt_operations.backlog_results where not business_handled union select snapshot_id from collect_ops.receipt_backlog_budget_deferrals)except select snapshot_id from collect_ops.receipt_backlog_sweep_sources));') == 't')
            case('historical unhandled remains after later handled; handled-only source stays absent', t.scalar('select exists(select 1 from collect_ops.receipt_backlog_sweep_sources where snapshot_id='+q(heavy)+')and not exists(select 1 from collect_ops.receipt_backlog_sweep_sources where snapshot_id='+q(handled_only)+');') == 't')
            case('duplicate-heavy source and quota evidence preserve original winning rows', t.json('select collect_ops.receipt_exception_source(\'receipt_backlog\','+q(heavy)+');') == old_source and t.scalar('select collect_ops.receipt_exception_quota_available(\'receipt_backlog\','+q(heavy)+');') == old_quota)
            for role in ['anon','authenticated','service_role']:
                denied = t.sql('begin;set local role '+role+';select * from collect_ops.receipt_backlog_sweep_sources;rollback;', check=False)
                case(role+' cannot directly read or write private registry', denied.returncode != 0 and '42501' in denied.stderr and t.scalar("select not has_table_privilege("+q(role)+",'collect_ops.receipt_backlog_sweep_sources','SELECT,INSERT,UPDATE,DELETE')and(select relrowsecurity from pg_class where oid='collect_ops.receipt_backlog_sweep_sources'::regclass);") == 't')
            for action in ['update collect_ops.receipt_backlog_sweep_sources set snapshot_id=snapshot_id;', 'delete from collect_ops.receipt_backlog_sweep_sources;']:
                denied = t.sql(action, check=False)
                case('registry identity cannot be '+('updated' if action.startswith('update') else 'deleted'), denied.returncode != 0 and '55000' in denied.stderr)
            repeated = call('public.process_receipt_deferral_exceptions_v1('+','.join([q(first_id),'1',q(first_expiry)])+')', True)
            case('pre-migration exact original scan ACK replays byte-identically without new work', repeated == first)
            lookup = call('public.get_receipt_deferral_exception_scan_v1('+q(first_id)+')', True)
            case('lost old scan response still resolves exact immutable ACK', lookup['receipt'] == first and lookup['status'] == 'recorded')
            error('public.process_receipt_deferral_exceptions_v1('+','.join([q(first_id),'2',q(first_expiry)])+')','22023','original scan UUID cannot change limit',True)
            error('public.process_receipt_deferral_exceptions_v1('+','.join([q(ident()),'26',"clock_timestamp()+interval '100 seconds'"])+')','22023','new scanner still caps source and queue work at25',True)
            error('public.process_receipt_deferral_exceptions_v1('+','.join([q(ident()),'1',"clock_timestamp()-interval '1 second'"])+')','55000','expired scanner still refuses before progress',True)
            error('public.process_receipt_deferral_exceptions_v1('+','.join([q(ident()),'1',"clock_timestamp()+interval '121 seconds'"])+')','22023','scanner cannot extend expiry beyond120seconds',True)
            error('public.process_receipt_deferral_exceptions_v1('+','.join([q(ident()),'1',"clock_timestamp()+interval '100 seconds'"])+')','42501','authenticated owner cannot use service-only scanner')
            # Add independent distinct sources through the actual producer hook.
            t.sql("insert into collect_receipt_operations.backlog_results select '997a0000-0000-4000-8000-000000007003'::uuid,s.id,'CONTACT_MISSING',false,null,clock_timestamp()from collect_hybrid.momo_balance_snapshots s where s.payment_id::text like '99790000-%'and s.id not in("+','.join(map(q,[low,heavy,future,handled_only]))+');analyze collect_ops.receipt_backlog_sweep_sources;analyze collect_receipt_operations.backlog_results;analyze collect_ops.receipt_backlog_budget_deferrals;', label='1096 additional actual producer source memberships')
            t.sql("update collect_ops.receipt_exception_progress set phase='receipt_backlog',last_id="+q(heavy)+"where singleton;", label='installer-only preserved mid-sweep cursor fixture')
            cursor = t.json('select to_jsonb(p)from collect_ops.receipt_exception_progress p;')
            new_id = ident()
            new_expiry = t.scalar("select collect_ops.utc(clock_timestamp()+interval '100 seconds');")
            page = call('public.process_receipt_deferral_exceptions_v1('+','.join([q(new_id),'25',q(new_expiry)])+')', True)
            last = t.scalar('select last_id from collect_ops.receipt_exception_progress where singleton;')
            expected_last = t.scalar('select snapshot_id from(select snapshot_id from collect_ops.receipt_backlog_sweep_sources where snapshot_id>'+q(heavy)+'order by snapshot_id limit 25)s order by snapshot_id desc limit 1;')
            case('mid-sweep cursor and epoch advance by exact25 canonical distinct sources', page['seeded'] == 25 and page['processed'] == 25 and last == expected_last and page['scan_epoch'] == cursor['epoch'])
            work_before = int(t.scalar('select count(*)from collect_ops.receipt_exception_work;'))
            t.sql("insert into collect_receipt_operations.backlog_results values('997a0000-0000-4000-8000-000000007004',"+q(low)+",'CONTACT_MISSING',false,null,clock_timestamp());", label='source committed strictly behind active cursor')
            case('behind-cursor arrival appends immediate independent work and permanent source membership', int(t.scalar('select count(*)from collect_ops.receipt_exception_work;')) == work_before+1 and t.scalar('select exists(select 1 from collect_ops.receipt_backlog_sweep_sources where snapshot_id='+q(low)+');') == 't' and t.scalar('select last_id from collect_ops.receipt_exception_progress;') == last)
            # Exhaust just the final page so repeating phase/epoch semantics
            # are proven without processing the entire unrelated lifetime queue.
            t.sql("update collect_ops.receipt_exception_progress set last_id=(select snapshot_id from collect_ops.receipt_backlog_sweep_sources order by snapshot_id desc limit 1)where singleton;", label='installer-only exact tail cursor fixture')
            end = call('public.process_receipt_deferral_exceptions_v1('+q(ident())+",1,clock_timestamp()+interval '100 seconds')", True)
            case('tail exhaustion returns to receipt-event phase and increments epoch', end['seeded'] == 0 and end['scan_phase'] == 'receipt_event' and end['scan_epoch'] == cursor['epoch']+1)
            t.sql("update collect_ops.receipt_exception_progress set phase='receipt_backlog',last_id=null where singleton;", label='installer-only next repeating cycle fixture')
            start = call('public.process_receipt_deferral_exceptions_v1('+q(ident())+",1,clock_timestamp()+interval '100 seconds')", True)
            case('next repeating sweep revisits behind-cursor source without false handled claim', start['seeded'] == 1 and t.scalar('select last_id from collect_ops.receipt_exception_progress;') == low and not start['source_scan_complete'] and not start['financial_action'] and not start['send_action'])
            sweep_query = "select b.snapshot_id from collect_ops.receipt_backlog_sweep_sources b where b.snapshot_id>=coalesce($1,'00000000-0000-0000-0000-000000000000'::uuid)and($1 is null or b.snapshot_id>$1)order by b.snapshot_id limit $2"
            plan = json.loads(t.sql('set plan_cache_mode=force_generic_plan;prepare actual_sweep(uuid,integer)as '+sweep_query+';explain(analyze,buffers,format json)execute actual_sweep('+q(heavy)+',25);').stdout)
            save(report/'observed-generic-sweep-plan.json', plan)
            def nodes(node):
                yield node
                for child in node.get('Plans',[]):yield from nodes(child)
            ns = list(nodes(plan[0]['Plan']))
            access = [n for n in ns if n.get('Relation Name') == 'receipt_backlog_sweep_sources']
            case('generic repeating sweep uses primary-key index and examines at most26 source rows', len(access) == 1 and access[0]['Node Type'] in ['Index Scan','Index Only Scan'] and access[0]['Actual Rows']+access[0].get('Rows Removed by Filter',0) <= 26 and 'Index Cond' in access[0])
            plan_source = json.loads(t.sql("explain(analyze,buffers,format json)select x.code from((select b.code,b.recorded_at,b.run_id from collect_receipt_operations.backlog_results b where b.snapshot_id="+q(heavy)+"and not b.business_handled order by b.recorded_at desc,b.run_id desc limit 1)union all(select 'QUOTA_EXHAUSTED',b.recorded_at,b.run_id from collect_ops.receipt_backlog_budget_deferrals b where b.snapshot_id="+q(heavy)+"order by b.recorded_at desc,b.run_id desc limit 1))x order by x.recorded_at desc,x.run_id desc limit 1;").stdout)
            save(report/'observed-duplicate-source-evidence-plan.json', plan_source)
            source_access = [n for n in nodes(plan_source[0]['Plan']) if n.get('Relation Name') in ['backlog_results','receipt_backlog_budget_deferrals']]
            case('6000 duplicates per evidence branch yield two indexed one-row winners', len(source_access) == 2 and all(n['Node Type'] in ['Index Scan','Index Only Scan'] and n['Actual Rows'] <= 1 and n.get('Rows Removed by Filter',0) == 0 for n in source_access))
            # Actual source bodies, not a widened public reader, match these
            # bounded statements. No other function definition may change.
            current_defs = {name:t.json('select to_jsonb(pg_get_functiondef('+q(name)+'::regprocedure));') for name in FUNCTIONS}
            save(report/'observed-current-functions.json', current_defs)
            indexes = t.json("select jsonb_object_agg(indexname,indexdef)from pg_indexes where schemaname in('collect_ops','collect_receipt_operations')and indexname in('receipt_worker_jobs_latest','receipt_worker_receipts_latest','receipt_backlog_unhandled_source_latest','receipt_backlog_handled_source_first','receipt_backlog_quota_source_latest','receipt_run_event_quota_source_latest','receipt_backlog_budget_source_latest');")
            save(report/'observed-indexes.json', indexes)
            case('all seven latest/source evidence indexes installed exactly', len(indexes) == 7)
            # Explicit immutable installer history anchors test global latest
            # ordering at realistic size. These declared fixture JSON rows are
            # not represented as genuine completed worker executions.
            t.sql("with stamp as materialized(select clock_timestamp()-interval '1 day' as stamp_at)insert into collect_ops.receipt_worker_jobs select ('997c0000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,1,25,20,(stamp_at at time zone 'UTC')::date,stamp_at+make_interval(secs=>n/1000),stamp_at+make_interval(secs=>n/1000)+interval '90 seconds'from stamp cross join generate_series(1,2000)n;insert into collect_ops.receipt_exception_scans select request_id,1,expires_at,created_at+interval '1 second',jsonb_build_object('installer_fixture_only',true,'request_id',request_id)from collect_ops.receipt_worker_jobs;insert into collect_ops.receipt_worker_receipts select request_id,created_at+interval '2 seconds',jsonb_build_object('installer_fixture_only',true,'request_id',request_id),request_id from collect_ops.receipt_worker_jobs;analyze collect_ops.receipt_worker_jobs;analyze collect_ops.receipt_worker_receipts;", label='2000 declared immutable worker/query-only history fixtures')
            for table, order, index in [('receipt_worker_jobs','created_at desc,request_id desc','receipt_worker_jobs_latest'),('receipt_worker_receipts','recorded_at desc,request_id desc','receipt_worker_receipts_latest')]:
                latest_plan = json.loads(t.sql(f'explain(analyze,buffers,format json) select * from collect_ops.{table} order by {order} limit 1;').stdout)
                save(report/('observed-'+table+'-latest-plan.json'), latest_plan)
                latest_access = [n for n in nodes(latest_plan[0]['Plan']) if n.get('Relation Name') == table]
                case(table+' latest read uses exact ordering index and consumes one history row', len(latest_access) == 1 and latest_access[0].get('Index Name') == index and latest_access[0]['Actual Rows'] == 1 and not any(n['Node Type'] == 'Sort' for n in nodes(latest_plan[0]['Plan'])))
            latest = t.scalar('select request_id from collect_ops.receipt_worker_jobs order by created_at desc,request_id desc limit 1;')
            original_result = t.json('select result from collect_ops.receipt_worker_receipts where request_id='+q(latest)+';')
            retained = call('public.get_receipt_exception_worker_request_v1('+q(latest)+')', True)
            case('service lookup returns exact retained query-fixture original and deadline', retained['status'] == 'recorded' and retained['receipt'] == original_result and retained['expires_at'] == t.scalar('select collect_ops.utc(expires_at)from collect_ops.receipt_worker_jobs where request_id='+q(latest)+';'))
            case('all financial evidence unchanged through scanners; real journals remain balanced; zero sends', financial() == finance and t.scalar("select not exists(select 1 from collect_hybrid.sms_notification_attempts)and not exists(select 1 from net.http_request_queue)and(select bool_and(debit=credit)from(select sum(amount_rwf)filter(where direction='debit')debit,sum(amount_rwf)filter(where direction='credit')credit from collect_hybrid.momo_journal_lines group by journal_entry_id)x);") == 't')
            case('worker remains disabled and original cron remains inactive', t.scalar("select not enabled from collect_ops.receipt_worker_configuration where singleton;") == 't' and t.scalar("select not active from cron.job where jobname='collect-receipt-exceptions';") == 't')
            save(report/'final-projection.json', t.json("select jsonb_build_object('registry_sources',(select count(*)from collect_ops.receipt_backlog_sweep_sources),'history_rows',(select count(*)from collect_receipt_operations.backlog_results),'budget_rows',(select count(*)from collect_ops.receipt_backlog_budget_deferrals),'progress',(select to_jsonb(p)from collect_ops.receipt_exception_progress p),'scans',(select count(*)from collect_ops.receipt_exception_scans));"))
        case('owned disposable target removed after actual SQL proof', result['target'].get('task_container_removed') is True)
        result['status'] = 'pass'
    except BaseException as error:
        result['status'] = 'failed'
        result['error'] = str(error)
        raise
    finally:
        result['sources_unchanged'] = all(pathlib.Path(p).read_bytes() == b for p,b in sources.items())
        result['python_unchanged'] = sha(runtime.read_bytes()) == runtime_hash
        result['finished_at'] = now()
        save(report/'result.json', result)

if __name__ == '__main__':
    main()

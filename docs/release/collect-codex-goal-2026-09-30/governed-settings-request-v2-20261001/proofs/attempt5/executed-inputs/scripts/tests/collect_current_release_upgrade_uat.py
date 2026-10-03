#!/usr/bin/env python3
"""Offline app-DDL clean replay and populated hosted-version upgrade rehearsal.

Only creates/removes task-owned networkless containers. It accepts no database
URL, copies no source rows or credentials, and never writes a shared database.
Auth is a retained schema-only platform shape, not a GoTrue/provider test.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import re
import subprocess
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
DOCKER = '/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker'
IMAGE = 'public.ecr.aws/supabase/postgres:17.6.1.095'
IMAGE_ID = 'sha256:35ebf7c6d3b77a430146b0a91974ed1fc14432b5741db4a3e41cd5f899b17f1a'
BASELINE = ROOT / '.cache/receipt-foundation-attempt8/schema-only.sql'
BASELINE_HASH = '77262947961ac1a724195ea77bdb98088cebd30caecc625ded1d4a93ccbf6d3d'
HOSTED = ROOT / 'docs/release/collect-codex-goal-2026-09-30/hosted-readback/metadata.json'
UID = '99780000-0000-4000-8000-000000000001'
OTHER = '99780000-0000-4000-8000-000000000002'
SID = '99780000-0000-4000-8000-000000010001'
GROUP = '99780000-0000-4000-8000-000000030001'
MEMBER = '99780000-0000-4000-8000-000000040001'
PAYMENT = '99780000-0000-4000-8000-000000050001'
RAW = '99780000-0000-4000-8000-000000060001'
EVENT = '99780000-0000-4000-8000-000000070001'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def quoted(value):
    return "'" + str(value).replace("'", "''") + "'"


def command(args, text=None, check=True, timeout=120):
    result = subprocess.run(args, input=text, text=True, capture_output=True, timeout=timeout)
    if check and result.returncode:
        raise RuntimeError(result.stderr[-3500:])
    return result


def platform_shape():
    raw = BASELINE.read_bytes()
    assert sha(raw) == BASELINE_HASH
    header = re.compile(r'^--\n-- Name: (.*?); Type: (.*?); Schema: (.*?); Owner: -\n--\n', re.M)
    matches = list(header.finditer(raw.decode()))
    kept, omitted = [], []
    for i, match in enumerate(matches):
        name, kind, schema = match.groups()
        block = raw.decode()[match.end():matches[i+1].start() if i+1 < len(matches) else len(raw)]
        if schema not in ('auth', 'storage'):
            continue
        # App migrations recreate these public-function triggers. Retaining
        # them would import application dependencies before app migration1.
        if kind == 'TRIGGER' and 'EXECUTE FUNCTION public.' in block:
            omitted.append({'name': name, 'kind': kind, 'schema': schema})
            continue
        assert kind != 'POLICY', 'Unexpected platform policy needs explicit review'
        kept.append(match.group() + block)
    assert kept and any('CREATE TABLE auth.sessions' in b for b in kept)
    prefix = '''set check_function_bodies=off;set standard_conforming_strings=on;
drop schema if exists auth cascade;drop schema if exists storage cascade;
create schema auth;create schema storage;create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
'''
    sql = prefix + '\n'.join(kept) + '''
grant usage on schema auth,storage,extensions to anon,authenticated,service_role;
grant execute on all functions in schema auth to anon,authenticated,service_role;
create schema if not exists supabase_migrations;
create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[]);
do $$begin if not exists(select 1 from pg_publication where pubname='supabase_realtime')then
 create publication supabase_realtime;end if;end$$;
'''
    return sql, {'retained_dump_sha256': BASELINE_HASH, 'extracted_platform_sha256': sha(sql.encode()),
                 'kept_blocks': len(kept), 'omitted_app_triggers': omitted,
                 'source_rows_copied': False, 'platform_role_and_grant_normalization': True,
                 'auth_provider_runtime_tested': False, 'storage_runtime_tested': False}


class Target:
    def __init__(self, report, phase, evidence):
        self.report = report / phase
        self.report.mkdir()
        self.phase = phase
        self.name = 'collect_current_rehearsal_' + phase + '_' + uuid.uuid4().hex[:12]
        self.evidence = evidence
        self.made = False

    def sql(self, text, check=True, label='query', user='postgres'):
        with (self.report / 'queries.sql').open('a') as log:
            log.write('-- Offline synthetic target: ' + label + '\n' + text + '\n')
        result = command([DOCKER, 'exec', '-i', self.name, 'psql', '-XqAt', '-U', user, '-d', 'postgres',
                          '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'],
                         'set search_path=public,extensions,auth;set timezone=\'UTC\';\n' + text, False)
        with (self.report / 'queries.log').open('a') as log:
            log.write(json.dumps({'label': label, 'sql_sha256': sha(text.encode()), 'exit_code': result.returncode}) + '\n')
            log.write(result.stdout + result.stderr)
        if check and result.returncode:
            raise RuntimeError(label + ': ' + result.stderr[-3500:])
        return result

    def scalar(self, sql):
        return self.sql(sql).stdout.strip().splitlines()[-1]

    def json(self, sql):
        return json.loads(self.scalar(sql))

    def __enter__(self):
        assert command([DOCKER, 'image', 'inspect', IMAGE, '--format', '{{.Id}}']).stdout.strip() == IMAGE_ID
        # Password is random, local and unlogged. No source credential is read.
        password = uuid.uuid4().hex + uuid.uuid4().hex
        created = command([DOCKER, 'run', '--detach', '--pull=never', '--name', self.name,
                           '--label', 'collect.rehearsal.owner=' + self.name, '--network', 'none',
                           '--tmpfs', '/var/lib/postgresql/collect-rehearsal:rw,size=1073741824',
                           '-e', 'POSTGRES_PASSWORD=' + password,
                           '-e', 'PGDATA=/var/lib/postgresql/collect-rehearsal/data', IMAGE,
                           'postgres', '-D', '/var/lib/postgresql/collect-rehearsal/data',
                           '-c', 'shared_preload_libraries=pg_cron,pg_net,pg_stat_statements',
                           '-c', 'wal_level=logical',
                           '-c', 'cron.database_name=postgres', '-c', 'cron.launch_active_jobs=off',
                           '-c', 'cron.log_run=on', '-c', 'cron.timezone=UTC',
                           '-c', 'pg_net.batch_size=0', '-c', 'listen_addresses=']).stdout.strip()
        self.made = True
        self.evidence['container_id'] = created
        self.evidence['container_name'] = self.name
        for attempt in range(200):
            init_log = command([DOCKER, 'logs', self.name], check=False)
            if 'PostgreSQL init process complete; ready for start up.' not in init_log.stdout:
                time.sleep(.25)
                continue
            ready = command([DOCKER, 'exec', self.name, 'pg_isready', '-U', 'postgres', '-d', 'postgres'], check=False)
            if ready.returncode == 0:
                break
            time.sleep(.25)
        else:
            raise RuntimeError('Task-owned offline Postgres did not become ready')
        info = json.loads(command([DOCKER, 'inspect', self.name, '--format',
                                  '{{json .HostConfig}}']).stdout)
        labels = json.loads(command([DOCKER, 'inspect', self.name, '--format', '{{json .Config.Labels}}']).stdout)
        assert labels['collect.rehearsal.owner'] == self.name
        assert info['NetworkMode'] == 'none' and not info['PortBindings']
        # Cached image's managed postgres is not a superuser. Normalize only
        # local installer permissions, explicitly recorded as a limitation.
        self.sql("grant pg_read_all_settings,pg_read_all_stats to postgres;alter role postgres superuser;",user='supabase_admin',label='isolated installer owner normalization')
        self.evidence['installer_normalization'] = 'Task-local postgres superuser for schema-only owner-normalized DDL; managed hosted installer privileges not attested'
        settings = self.json("select jsonb_build_object('cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'),'listen',current_setting('listen_addresses'),'server',current_setting('server_version'));")
        assert settings['cron'] == 'off' and settings['net'] == '0' and settings['listen'] == ''
        self.evidence['guard'] = {'network': 'none', 'published_ports': False, 'labels_verified': True, **settings}
        # These image roles are prerequisites rather than app-created accounts.
        self.sql("do $$begin if not exists(select 1 from pg_roles where rolname='anon')then create role anon nologin;end if;if not exists(select 1 from pg_roles where rolname='authenticated')then create role authenticated nologin;end if;if not exists(select 1 from pg_roles where rolname='service_role')then create role service_role nologin bypassrls;end if;end$$;")
        return self

    def close(self):
        if self.made:
            logs = command([DOCKER, 'logs', self.name], check=False)
            (self.report / 'container.log').write_text(logs.stdout + logs.stderr)
            removal = command([DOCKER, 'rm', '--force', '--volumes', self.name], check=False)
            self.evidence['task_container_removed'] = removal.returncode == 0
            self.made = False

    def __exit__(self, *ignored):
        self.close()


def bootstrap_owner(target):
    target.sql("""begin;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values(%s,'authenticated','authenticated','250788971001',clock_timestamp(),'{}','{}');
update public.profiles set is_platform_admin=true,country_code='RW',currency_code='RWF',
momo_number='0788971001',momo_number_hash=encode(extensions.digest('+250788971001','sha256'),'hex'),
momo_provider='mtn_momo',momo_number_verified_at=clock_timestamp() where id=%s;
commit;""" % (quoted(UID), quoted(UID)), label='synthetic bootstrap profile before reserved groups')


def apply(target, items, outcome):
    for item in items:
        if item['version'] == '20260901134820':
            bootstrap_owner(target)
        started = time.monotonic()
        result = target.sql(item['body'], check=False, label=item['path'])
        log = target.report / (pathlib.Path(item['path']).stem + '.log')
        log.write_text(result.stdout + result.stderr)
        row = {'path': item['path'], 'version': item['version'], 'sha256': item['sha256'],
               'status': 'pass' if result.returncode == 0 else 'failed',
               'seconds': round(time.monotonic()-started, 3)}
        outcome.setdefault('migrations', []).append(row)
        print(target.phase + ' ' + row['status'].upper() + ' ' + item['path'], flush=True)
        if result.returncode:
            row['error'] = result.stderr
            raise RuntimeError('Migration failed: ' + item['path'] + '\n' + result.stderr[-3500:])
        target.sql("insert into supabase_migrations.schema_migrations(version,name,statements)values(%s,%s,array[%s]);" %
                   (quoted(item['version']), quoted(item['name']), quoted(item['body'])), label='local exact source registry ' + item['version'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report-dir', required=True)
    args = parser.parse_args()
    report = pathlib.Path(args.report_dir).resolve()
    assert not report.exists(), 'Fresh report directory required'
    report.mkdir(parents=True)
    evidence = {'kind': 'offline_current_app_ddl_and_populated_hosted_version_upgrade',
                'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'cases': [],
                'production_written': False, 'shared_database_written': False, 'source_rows_copied': False,
                'provider_called': False, 'otp_sent': False, 'scheduler_executed': False,
                'signed_jwt_tested': False, 'image': IMAGE, 'image_id': IMAGE_ID,
                'runner_sha256': sha(pathlib.Path(__file__).read_bytes()), 'phases': {}}

    def save():
        (report / 'result.json').write_text(json.dumps(evidence, indent=2) + '\n')

    def case(name, value=True):
        assert value, name
        evidence['cases'].append({'name': name, 'status': 'pass'})
        save()
        print('PASS ' + name, flush=True)

    targets = []
    try:
        hosted_bytes = HOSTED.read_bytes()
        hosted = json.loads(hosted_bytes)
        registered = hosted['migrations']
        assert len(registered) == 124 and registered[-1]['version'] == '20260906160000'
        (report / 'hosted-migration-inventory.json').write_text(json.dumps({'metadata_sha256': sha(hosted_bytes),
            'metadata_only': True, 'installed_bodies_verified': False, 'migrations': registered}, indent=2) + '\n')
        snapshots = report / 'captured-source'
        snapshots.mkdir()
        items = []
        for path in sorted((ROOT / 'supabase/migrations').glob('*.sql')):
            data = path.read_bytes()
            version, name = path.stem.split('_', 1)
            item = {'path': str(path.relative_to(ROOT)), 'version': version, 'name': name,
                    'sha256': sha(data), 'body': data.decode()}
            items.append(item)
            (snapshots / path.name).write_bytes(data)
        assert len({i['version'] for i in items}) == len(items)
        assert [i['version'] for i in items[:124]] == [i['version'] for i in registered]
        assert all(sha((ROOT/i['path']).read_bytes()) == i['sha256'] for i in items)
        evidence['source_inventory'] = [{k: v for k, v in i.items() if k != 'body'} for i in items]
        evidence['hosted_boundary'] = {'count': 124, 'latest': '20260906160000',
            'metadata_sha256': sha(hosted_bytes), 'version_prefix_parity': True,
            'name_differences': [{'version': h['version'], 'hosted': h['name'], 'local': i['name']}
             for h, i in zip(registered, items) if h['name'] != i['name']],
            'hosted_application_body_parity_verified': False}
        platform, provenance = platform_shape()
        (report / 'platform-schema-only-bootstrap.sql').write_text(platform)
        evidence['platform_bootstrap'] = provenance
        save()
        for phase in ('clean', 'populated'):
            outcome = evidence['phases'][phase] = {}
            target = Target(report, phase, outcome)
            targets.append(target)
            with target:
                target.sql(platform, label='retained platform schema-only bootstrap')
                case(phase + ' bootstrap has no Auth users or application objects',
                     target.scalar("select not exists(select 1 from auth.users)and to_regclass('public.profiles')is null;") == 't')
                if phase == 'clean':
                    apply(target, items, outcome)
                    case('all frozen application migrations replay on empty app with explicit bootstrap owner',
                         int(target.scalar('select count(*)from supabase_migrations.schema_migrations;')) == len(items))
                else:
                    apply(target, items[:124], outcome)
                    case('populated predecessor exactly reaches hosted124 version boundary',
                         target.json("select jsonb_build_object('count',count(*),'latest',max(version))from supabase_migrations.schema_migrations;") == {'count': 124, 'latest': '20260906160000'})
                    hosted_rpcs = hosted['metadata'][0]['release_metadata']['public_rpc']
                    local_rpcs = target.json("select jsonb_agg(jsonb_build_object('name',p.proname,'identity_args',pg_get_function_identity_arguments(p.oid),'definition_sha256',encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex'))order by p.proname)from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('admin_list_collect_transactions','collect_list_pending_receipts','collect_notification_health');")
                    outcome['focused_hosted_rpc_body_parity'] = [{'name': h['name'], 'identity_args':h['identity_args'],
                        'hosted_sha256':h['definition_sha256'],
                        'local_sha256':next((l['definition_sha256']for l in local_rpcs if l['name']==h['name']and l['identity_args']==h['identity_args']),None)}for h in hosted_rpcs]
                    for row in outcome['focused_hosted_rpc_body_parity']:
                        row['match'] = row['hosted_sha256']==row['local_sha256']
                    (target.report/'focused-hosted-rpc-parity.json').write_text(json.dumps(outcome['focused_hosted_rpc_body_parity'],indent=2)+'\n')
                    seed_populated(target, evidence, case)
                    for item in items[124:]:
                        before = fingerprints(target, evidence['preserved_columns'])
                        config_before = fingerprints(target, evidence['config_columns'])
                        apply(target, [item], outcome)
                        after = fingerprints(target, evidence['preserved_columns'])
                        assert before == after, 'Canonical fixture changed at ' + item['path']
                        config_after = fingerprints(target, evidence['config_columns'])
                        outcome['migrations'][-1]['canonical_fingerprints_preserved'] = True
                        outcome['migrations'][-1]['configuration_changed_tables'] = [k for k in config_before if config_before[k] != config_after[k]]
                        save()
                    verify_populated(target, evidence, case, len(items))
                outcome['scheduler_readback'] = target.json("select jsonb_build_object('launcher_enabled',current_setting('cron.launch_active_jobs'),'history',(select count(*)from cron.job_run_details),'net_batch',current_setting('pg_net.batch_size'),'jobs',(select coalesce(jsonb_agg(jsonb_build_object('name',jobname,'active',active,'command_sha256',encode(extensions.digest(command,'sha256'),'hex'))order by jobname),'[]')from cron.job));")
                case(phase + ' never launches cron history or external network work',
                     outcome['scheduler_readback']['launcher_enabled'] == 'off' and outcome['scheduler_readback']['history'] == 0 and outcome['scheduler_readback']['net_batch'] == '0')
                outcome['status'] = 'pass'
                save()
        evidence['status'] = 'pass'
    except Exception as error:
        evidence['status'] = 'failed'
        evidence['failure'] = str(error)
        save()
        raise
    finally:
        for target in targets:
            target.close()
        evidence['current_source_drift'] = []
        for item in evidence.get('source_inventory', []):
            now = ROOT / item['path']
            after = sha(now.read_bytes()) if now.exists() else None
            if after != item['sha256']:
                evidence['current_source_drift'].append({'path': item['path'], 'captured_sha256': item['sha256'], 'current_sha256': after})
        known = {i['path'] for i in evidence.get('source_inventory', [])}
        evidence['source_added_after_capture'] = [str(p.relative_to(ROOT)) for p in sorted((ROOT/'supabase/migrations').glob('*.sql')) if str(p.relative_to(ROOT)) not in known]
        evidence['case_count'] = len(evidence['cases'])
        evidence['completed_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        save()


def seed_populated(target, evidence, case):
    wallet_hash = hashlib.sha256(b'+250788971001').hexdigest()
    setup = """begin;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values(%s,'authenticated','authenticated','250788971002',clock_timestamp(),'{}','{}');
update public.profiles set country_code='FR',currency_code='EUR' where id=%s;
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
values(%s,'+250788971001',clock_timestamp()-interval '2 minutes','Synthetic upgrade identity only');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select %s,r.id,'Synthetic upgrade authority',clock_timestamp()-interval '1 minute'from public.admin_roles r where r.name='platform_owner'
and not exists(select 1 from public.admin_user_roles g where g.user_id=%s and g.role_id=r.id and g.revoked_at is null);
update public.admin_user_roles set created_at=clock_timestamp()-interval '1 minute'
where user_id=%s and revoked_at is null;
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values(%s,%s,clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
insert into public.admin_role_permissions(role_id,permission_name)
select r.id,p.name from public.admin_roles r cross join public.admin_permissions p where r.name='platform_owner' on conflict do nothing;
insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type,
contribution_visibility,allow_anonymous,diaspora_enabled,creation_origin)
values(%s,'current-upgrade-synthetic',%s,'Synthetic current upgrade','Family / friends','private','private','ikimina','members',false,false,'admin_assisted');
insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network)
values(%s,%s,'+250788971001',%s,'mtn_momo');
insert into collect_hybrid.member_records(id,collect_id,origin,created_by)values(%s,'978201','admin_assisted',%s);
insert into collect_hybrid.member_momo_identities(member_id,member_name,momo_name,momo_number)
values(%s,'Synthetic upgrade member','SYNTHETIC MEMBER','+250788978201');
insert into public.collection_members(collection_id,member_record_id,role,status)values(%s,%s,'member','active');
insert into collect_hybrid.sms_receipt_policies(collection_id,enabled,reason,updated_by)
values(%s,true,'Synthetic upgrade receipt policy',%s);
insert into collect_hybrid.sms_receipt_member_consents(member_record_id,enabled,capture_method,reason,recorded_by)
values(%s,true,'written','Synthetic upgrade consent',%s);
insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,
receiver_momo_number_hash,parse_status,received_at_device)
values(%s,%s,%s,'M-Money','Synthetic retained financial observation',encode(extensions.digest('Synthetic retained financial observation','sha256'),'hex'),%s,'parsed',clock_timestamp()-interval '1 day');
insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,
network,currency,direction,receiver_phone_hash,amount_rwf,transaction_id,allocation_status,sender_name)
values(%s,%s,%s,%s,true,'mtn_momo','RWF','incoming',%s,300,'UPGRADE-300','unallocated','Synthetic payer');
commit;""" % tuple(map(quoted, [OTHER,OTHER,UID,UID,UID,UID,SID,UID,GROUP,UID,GROUP,UID,wallet_hash,
                                MEMBER,UID,MEMBER,GROUP,MEMBER,GROUP,UID,MEMBER,UID,
                                RAW,GROUP,UID,wallet_hash,EVENT,RAW,GROUP,UID,wallet_hash]))
    target.sql(setup, label='synthetic populated predecessor identities observation and consent')
    (target.report/'synthetic-seed.sql').write_text(setup)
    # No carrier/provider action occurs: these are trusted-boundary fixtures
    # executed in the networkless test DB to exercise canonical accounting.
    for n, amount, enabled in [(1,300,True),(2,500,True),(3,50,False)]:
        identifier = '99780000-0000-4000-8000-%012d' % (50000+n)
        event = quoted(EVENT) if n == 1 else 'null'
        post = """update public.feature_flags set enabled=%s where key='hybrid_sms_notifications';
begin;select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into public.payments(id,parsed_event_id,collection_id,member_record_id,receiver_user_id,
receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,posted_at)
values(%s,%s,%s,%s,%s,%s,%d,%s,'mtn_momo','manual_admin','review',null);
select public.confirm_provider_payment(%s,'mtn_momo',%s,%s,%s,%d,clock_timestamp(),repeat('b',64));commit;
""" % ('true' if enabled else 'false',quoted(identifier),event,quoted(GROUP),quoted(MEMBER),
       quoted(UID),quoted(wallet_hash),amount,quoted('UPGRADE-'+str(amount)),quoted(identifier),
       quoted('UPGRADE-'+str(amount)),quoted('SYNTHETIC-CONF-'+str(amount)),quoted(wallet_hash),amount)
        target.sql(post, label='synthetic canonical posting ' + str(amount))
        with (target.report/'synthetic-seed.sql').open('a') as log:log.write(post)
    intents = """insert into public.payment_intents(id,collection_id,contributor_user_id,expected_amount_rwf,
receiver_momo_number_hash,sender_phone_hash,contribution_code)
values('99780000-0000-4000-8000-000000080001',%s,%s,5000,%s,%s,'SYNTHETIC-VALID'),
('99780000-0000-4000-8000-000000080002',%s,%s,6000,%s,repeat('f',64),'SYNTHETIC-UNVERIFIED');
""" % tuple(map(quoted,[GROUP,UID,wallet_hash,wallet_hash,GROUP,UID,wallet_hash]))
    target.sql(intents,label='synthetic legacy valid and unverified pending intents')
    with (target.report/'synthetic-seed.sql').open('a') as log:log.write(intents)
    tables = [('public','payments'),('public','payment_provider_confirmations'),
              ('public','raw_payment_sms'),('public','parsed_payment_events'),('public','payment_allocations'),
              ('collect_hybrid','momo_journal_entries'),('collect_hybrid','momo_journal_lines'),
              ('collect_hybrid','momo_balance_snapshots'),('collect_hybrid','member_balances'),
              ('collect_hybrid','collection_balances'),('collect_hybrid','sms_notification_outbox'),
              ('collect_hybrid','sms_notification_attempts'),('collect_hybrid','sms_notification_confirmations'),
              ('auth','users'),('auth','sessions'),('public','profiles'),
              ('collect_admin_access','whatsapp_approvals'),('public','admin_user_roles')]
    configs = [('public',t)for t in ['feature_flags','system_settings','profile_country_rules',
              'admin_navigation_items','admin_roles','admin_role_permissions','admin_permissions']]
    evidence['preserved_columns'] = columns(target,tables)
    evidence['config_columns'] = columns(target,configs)
    evidence['populated_predecessor_fingerprints'] = fingerprints(target,evidence['preserved_columns'])
    evidence['config_before_upgrade'] = fingerprints(target,evidence['config_columns'])
    (target.report/'preexisting-primary-receipts.json').write_text(json.dumps(target.json(
        "select jsonb_agg(to_jsonb(o)order by payment_id)from collect_hybrid.sms_notification_outbox o;"),indent=2)+'\n')
    case('nonempty predecessor has 850 RWF, three balanced journals and two immutable primary receipts',
         target.scalar("select (select confirmed_rwf=850 from collect_hybrid.member_balances where collection_id=%s and member_record_id=%s)and(select count(*)=3 from collect_hybrid.momo_journal_entries)and(select count(*)=2 from collect_hybrid.sms_notification_outbox);"%(quoted(GROUP),quoted(MEMBER)))=='t')
    case('predecessor dispatch is paused with no carrier attempts',target.scalar("select not enabled and not exists(select 1 from collect_hybrid.sms_notification_attempts)from public.feature_flags where key='hybrid_sms_notifications';")=='t')


def columns(target, tables):
    result = {}
    for schema, table in tables:
        result[schema+'.'+table] = target.json("select jsonb_agg(column_name order by ordinal_position)from information_schema.columns where table_schema=%s and table_name=%s;"%(quoted(schema),quoted(table)))
        assert result[schema+'.'+table], schema+'.'+table
    return result


def fingerprints(target, spec):
    pieces = []
    for table, names in spec.items():
        keys = 'array[' + ','.join(map(quoted,names)) + ']'
        pieces.append("select %s k,jsonb_build_object('rows',count(*),'sha256',encode(extensions.digest(coalesce(string_agg(j::text,E'\\n' order by j::text),''),'sha256'),'hex'))v from(select(select jsonb_object_agg(k,v)from jsonb_each(to_jsonb(t))x(k,v)where k=any(%s))j from %s t)s"%(quoted(table),keys,table))
    return target.json('select jsonb_object_agg(k,v)from('+ ' union all '.join(pieces) + ')s;')


def verify_populated(target, evidence, case, count):
    evidence['populated_after_upgrade_fingerprints'] = fingerprints(target,evidence['preserved_columns'])
    evidence['config_after_upgrade'] = fingerprints(target,evidence['config_columns'])
    case('every pending migration preserves 18 predecessor financial receipt Auth and approval projections',
         evidence['populated_after_upgrade_fingerprints']==evidence['populated_predecessor_fingerprints'])
    case('full upgrade registry reaches exact captured count',int(target.scalar('select count(*)from supabase_migrations.schema_migrations;'))==count)
    case('confirmed payer migration cancels only the incompatible legacy intent',
         target.json("select jsonb_object_agg(contribution_code,status)from public.payment_intents where contribution_code like 'SYNTHETIC-%';")=={'SYNTHETIC-VALID':'pending','SYNTHETIC-UNVERIFIED':'cancelled'})
    case('Rwanda mode retains existing FR profile while retiring non-Rwanda country configuration',
         target.scalar("select exists(select 1 from public.profiles where id=%s and country_code='FR'and currency_code='EUR')and not exists(select 1 from public.profile_country_rules where country_code<>'RW');"%quoted(OTHER))=='t')
    case('all retained journals remain two-line balanced',target.scalar("select not exists(select 1 from collect_hybrid.momo_journal_entries j left join collect_hybrid.momo_journal_lines l on l.journal_entry_id=j.id group by j.id having count(*)<>2 or sum(case when l.direction='debit'then l.amount_rwf else-l.amount_rwf end)<>0);")=='t')
    case('paused predecessor payment is never silently backfilled',target.scalar("select not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id='99780000-0000-4000-8000-000000050003');")=='t')
    claims = {'sub':UID,'session_id':SID,'role':'authenticated','aal':'aal1','exp':int(time.time())+3600}
    auth = 'begin;set local role authenticated;select set_config(\'request.jwt.claims\','+quoted(json.dumps(claims))+',true);'
    def read(sql):return json.loads(target.sql(auth+sql+';commit;',label='authenticated actual upgraded read').stdout.strip().splitlines()[-1])
    observed = read("select public.admin_get_collect_investigation_v1('transaction',%s)"%quoted(RAW))
    (target.report/'observed-upgraded-investigation.json').write_text(json.dumps(observed,indent=2)+'\n')
    case('current investigation reads actual retained posting and independent current balance',
         observed['scope']=='rwanda_momo'and observed['payment_state']==observed['receipt_state']=='available'
         and observed['payment']['lifecycle']['ledger']=='posted'and observed['receipt']['member_balance_rwf']=='300'
         and observed['payment']['current_balances']['member_rwf']=='850')
    overview = read("select public.admin_receipt_overview_v1('RW')")
    (target.report/'observed-upgraded-overview.json').write_text(json.dumps(overview,indent=2)+'\n')
    case('upgraded Overview receipt section remains independently authorized',overview['receipts']is not None)
    history = read('select public.list_collect_shadow_runs_v1()')
    (target.report/'observed-upgraded-shadow-history.json').write_text(json.dumps(history,indent=2)+'\n')
    case('manual shadow history exists without any scheduled or claimed runs',history['total']==0 and history['rows']==[])
    case('upgraded read calls preserve all predecessor projections',fingerprints(target,evidence['preserved_columns'])==evidence['populated_predecessor_fingerprints'])
    case('new handset dispatch authority remains unavailable',target.scalar("select not exists(select 1 from collect_gateway.dispatch_arms);")=='t')


if __name__ == '__main__':
    main()

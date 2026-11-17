"""Qualify BuriMunsi SQL on a disposable copy of an isolated retained clone.

No live source migration, GoTrue call, email, SMS or external provider operation.
Synthetic Allocate exercises the real shared ledger only in the owned test DB.
Fixture identities are inserted by SQL into the actual native Supabase schema;
this is not provider-authentication or production acceptance.
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import re
import select
import shutil
import subprocess
import sys
import time
import uuid
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from scripts.self_hosted.retained_snapshot import Docker,LABEL,verify_snapshot,physical_directory,private_json,require_owned_fresh_clone
from scripts.self_hosted.database import DatabaseInstaller,migrations,sha,literal,BASELINE
from scripts.supabase.deployment_profile import canonical_profile

FIXTURES=('operator-seed.sql','operator-readonly.sql','operator-contract.sql','member-command-contract.sql',
          'source-scope-contract.sql','provisioning-contract.sql','gateway-contract.sql',
          'scope-setup-contract.sql','gateway-upload-contract.sql','managed-email-contract.sql',
          'phone-pin-contract.sql','gateway-handoff-contract.sql','phone-pin-readonly-contract.sql','gateway-handoff-readonly-contract.sql',
          'platform-public-group-contract.sql','canonical-adoption-contract.sql')
COMPILED_CONTRACTS={
    'member-command-contract.sql':('member',('guards','person','membership','change','audit')),
    'source-scope-contract.sql':('source',('source_functions',)),
    'provisioning-contract.sql':('provisioning',('provisioning_inputs',)),
    'gateway-contract.sql':('gateway',('gateway_inputs',)),
    'scope-setup-contract.sql':('scope-setup',('setup_inputs',)),
    'gateway-upload-contract.sql':('gateway-upload',('gateway_upload_inputs',)),
    'managed-email-contract.sql':('managed-email',()),
    'phone-pin-contract.sql':('phone-pin',()),
    'phone-pin-readonly-contract.sql':('phone-pin-readonly',()),
    'gateway-handoff-contract.sql':('gateway-handoff',('native_pair_inputs',)),
    'gateway-handoff-readonly-contract.sql':('gateway-handoff-readonly',('native_pair_inputs',)),
    'platform-public-group-contract.sql':('platform-public-group',('setup_inputs',)),
    'canonical-adoption-contract.sql':('canonical-adoption',('adoption_inputs',)),
}


BASELINE_MIGRATIONS=31
PIN_MIGRATION='20261110143000_burimunsi_native_phone_pin.sql'
LOCAL_STOPPED_MIGRATION='20261110181002_collect_local_stopped_admission.sql'
HANDOFF_MIGRATION='20261110181003_burimunsi_gateway_handoff.sql'
ADOPTION_MIGRATION='20261110193000_burimunsi_canonical_receipt_adoption.sql'
REVIEWED_SUFFIX=(
    '20261109234517_burimunsi_native_operator_schema.sql',
    '20261110030800_burimunsi_sms_source_scope.sql',
    '20261110032620_burimunsi_native_provisioning.sql',
    '20261110040728_burimunsi_gateway_classification.sql',
    '20261110052756_burimunsi_dynamic_scope_setup.sql',
    '20261110093218_burimunsi_managed_email_preauth.sql',PIN_MIGRATION,LOCAL_STOPPED_MIGRATION,HANDOFF_MIGRATION,ADOPTION_MIGRATION)
STATE_SQL="""SELECT json_build_object(
'auth_users',(SELECT count(*) FROM auth.users),
'native_accounts',(SELECT count(*) FROM private.burimunsi_accounts),
'business_users',(SELECT count(*) FROM app.users),
'collections',(SELECT count(*) FROM app.collections),
'ledger_entries',(SELECT count(*) FROM app.ledger_entries),
'receiving_accounts',(SELECT count(*) FROM app.momo_receiving_accounts),
'fence_initialized',EXISTS(SELECT 1 FROM private.collect_fence_control),
'deployment_bound',EXISTS(SELECT 1 FROM private.collect_deployment_identity),
'native_pin_schema',to_regclass('private.burimunsi_pin_session_links') IS NOT NULL,
'native_local_stopped_schema',to_regclass('private.collect_fence_local_stopped_admissions') IS NOT NULL,
'native_handoff_schema',to_regclass('private.burimunsi_gateway_handoffs') IS NOT NULL,
'native_adoption_schema',to_regprocedure('private.burimunsi_adopt_completed_receipt()') IS NOT NULL,
'migrations',(SELECT count(*) FROM supabase_migrations.collect_installation_steps));"""
JOURNAL_SQL="SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY version),'[]'::jsonb) FROM supabase_migrations.collect_installation_steps s;"


def compile_fixture_process(node,compiler,output,kind):
    """Preserve local compiler diagnostics before propagating an unknown result."""
    compiled=subprocess.run([node,str(compiler)],cwd=ROOT,check=False,capture_output=True,timeout=30)
    for suffix,value in (('stdout',compiled.stdout),('stderr',compiled.stderr)):
        path=output/(kind+'-compiler.private.'+suffix)
        with path.open('xb') as stream:
            os.chmod(path,0o600);stream.write(value)
    compiled.check_returncode()
    return compiled


def fixture_format(kind):
    compiler_kind='gateway-handoff' if kind.startswith('gateway-handoff') else kind
    return ('collect.platform-sponsored.sql-fixture.v1' if compiler_kind=='platform-public-group'
            else f'collect.burimunsi.{compiler_kind}-sql-fixture.v1')


def require_allocation_result(value):
    flags=('original_native_allocate_executed','native_session_revalidated','exact_replay_same_result',
           'second_request_did_not_repost','canonical_duplicate_did_not_repost','first_scope_preserved',
           'owned_psql_cleanup_confirmed')
    if (not isinstance(value,dict) or value.get('format')!='collect.burimunsi.adopted-native-allocation.actual-pg.v1'
            or value.get('status')!='pass' or any(value.get(flag) is not True for flag in flags)
            or value.get('production_acceptance') is not False or value.get('gotrue_exercised') is not False
            or value.get('provider_calls')!=0
            or value.get('native_work_close',{}).get('applicationWorkFinished') is not True
            or value.get('counts')!={'payments':1,'ledger':1,'links':1,'snapshots':1,'receipts':1}
            or value.get('canonical_counts')!={'facts':1,'accepted':1,'duplicates':1,'scopes':1}):
        raise ValueError('Actual native Allocate on adopted canonical fact unconfirmed')
    return value


def reviewed_chain(records):
    if len(records)!=BASELINE_MIGRATIONS+4 or tuple(r['name'] for r in records[-10:])!=REVIEWED_SUFFIX:
        raise ValueError('Exact reviewed 31-to-32-to-33-to-34-to-35 BuriMunsi migration chain required')
    return records[:BASELINE_MIGRATIONS],records[-4:]


def clean_state(*,upgraded=False):
    return {'auth_users':0,'native_accounts':0,'business_users':0,'collections':0,
            'ledger_entries':0,'receiving_accounts':0,'fence_initialized':upgraded,
            'deployment_bound':upgraded,'native_pin_schema':upgraded,'native_local_stopped_schema':upgraded,'native_handoff_schema':upgraded,'native_adoption_schema':upgraded,
            'migrations':BASELINE_MIGRATIONS+4*int(upgraded)}


def require_clean_baseline(observed,journal,records):
    baseline,_=reviewed_chain(records)
    if (observed!=clean_state() or not isinstance(journal,list)
            or [row.get('version') for row in journal]!=[r['name'] for r in baseline]):
        raise ValueError('Exact clean inactive31 native schema rehearsal required')
    return sha(json.dumps(journal,sort_keys=True,separators=(',',':')).encode())


def selected_fixtures(contract):
    if contract=='all':return FIXTURES
    if contract=='install-only':return ()
    mapping={
        'member':('member-command-contract.sql',),'source':('source-scope-contract.sql',),
        'provisioning':('provisioning-contract.sql',),'gateway':('gateway-contract.sql',),
        'scope-setup':('scope-setup-contract.sql',),'gateway-upload':('gateway-upload-contract.sql',),
        'managed-email':('managed-email-contract.sql',),
        'phone-pin':('phone-pin-contract.sql','phone-pin-readonly-contract.sql'),
        'phone-pin-readonly':('phone-pin-readonly-contract.sql',),
        'gateway-handoff':('gateway-handoff-contract.sql','gateway-handoff-readonly-contract.sql'),
        'gateway-handoff-readonly':('gateway-handoff-readonly-contract.sql',)}
    mapping.update({'platform-public-group':('platform-public-group-contract.sql',),
                    'canonical-adoption':('canonical-adoption-contract.sql',)})
    if contract not in mapping:raise ValueError('Known qualification contract required')
    return (*FIXTURES[:3],*mapping[contract])


def require_control(value,mode,epoch,operation,source):
    if (not isinstance(value,dict) or value.get('mode')!=mode or value.get('epoch')!=epoch
            or value.get('operationId')!=str(operation) or value.get('sourceSha256')!=source
            or value.get('activeAdmissions')!=0 or value.get('unresolvedAdmissions')!=0
            or (mode=='fenced' and value.get('applicationFenceComplete') is not True)):
        raise ValueError('Exact isolated qualification fence readback required')
    return value


def upgrade_disposable_baseline(installer,baseline_journal,operations,*,install_state='fenced'):
    """Qualify clean31->35, with FENCED DDL or empty32-34 then FENCED35.

    The retained CURRENT32 orphan is qualified separately. Neither this clean
    source nor any original journal is reset, replayed or backdated.
    """
    baseline,targets=reviewed_chain(installer.records)
    applied=installer.applied()
    if (list(applied)!=[r['name'] for r in baseline] or list(applied.values())!=baseline_journal
            or install_state not in ('fenced','uninitialized')):
        raise ValueError('Exact copied31 journal and supported installation state required')
    op=installer.op;source=op.meta['source_sha256'];profile=canonical_profile(op.profile)
    if sha(profile.encode())!=op.meta['profile_sha256']:
        raise ValueError('Exact qualification profile digest required')
    init=operations['initialize'];quiesce=operations['quiesce'];release=operations['release']
    if len({init,quiesce,release})!=3:raise ValueError('Distinct journalled qualification operations required')
    op.sql('BEGIN;SELECT private.collect_bind_deployment('+','.join(literal(v) for v in [init,profile,op.meta['profile_sha256']])+');COMMIT;')
    def control(name,operation,epoch=None):
        args=[operation]+([] if epoch is None else [epoch])+[source]
        if name=='collect_fence_initialize':args.append(BASELINE)
        return json.loads(op.sql('BEGIN;SET LOCAL lock_timeout=\'5s\';SET LOCAL statement_timeout=\'30s\';SELECT private.'+name+'('+','.join(literal(v) for v in args)+');COMMIT;'))
    def initialize_and_fence():
        initial=require_control(control('collect_fence_initialize',init),'open',1,init,source)
        quiescing=require_control(control('collect_fence_begin_quiesce',quiesce,1),'quiescing',1,quiesce,source)
        fenced=require_control(control('collect_fence_drain',quiesce,1),'fenced',1,quiesce,source)
        return initial,quiescing,fenced
    if install_state=='fenced':initial,quiescing,fenced=initialize_and_fence()
    journals={};done=[];previous=baseline_journal
    for count,target in enumerate(targets,BASELINE_MIGRATIONS+1):
        if install_state=='uninitialized':
            if json.loads(op.sql('SELECT to_jsonb(EXISTS(SELECT 1 FROM private.collect_fence_control));')) is not False:
                raise ValueError('Empty controller must remain uninitialized before adoption')
            # Adoption's unchanged precondition requires a committed fence.
            if target['name']==ADOPTION_MIGRATION:initial,quiescing,fenced=initialize_and_fence()
        applied=installer.apply_records([target]);after=list(installer.applied().values())
        if (applied!=[target['name']] or len(after)!=count or after[:count-1]!=previous
                or [row['version'] for row in after]!=[r['name'] for r in installer.records[:count]]):
            raise ValueError('Additive'+str(count)+' changed its exact predecessor journal or has unknown outcome')
        journals['journal'+str(count)]=after;previous=after;done.extend(applied)
        if install_state=='fenced' or target['name']==ADOPTION_MIGRATION:
            require_control(json.loads(op.sql('SELECT private.collect_fence_owner_status();')),'fenced',1,quiesce,source)
    still_fenced=require_control(json.loads(op.sql('SELECT private.collect_fence_owner_status();')),'fenced',1,quiesce,source)
    opened=require_control(control('collect_fence_release',release,1),'open',2,release,source)
    return {'format':'collect.burimunsi.disposable-31-to-32-to-33-to-34-to-35.v1','new_migrations':done,
            'installation_state':install_state,'preserved_journal_prefix':34,'baseline_journal_prefix':BASELINE_MIGRATIONS,
            **journals,'initial':initial,'quiescing':quiescing,'fenced':fenced,'after_migration':still_fenced,'released':opened,
            'live_source_migrated':False,'production_acceptance':False}


def qualify(args):
    source=physical_directory(args.snapshot_directory)
    snapshot=verify_snapshot(source)
    clone=json.loads((source/'clone.json').read_text())
    identity=clone.get('container_id','')
    if not re.fullmatch('[a-f0-9]{64}',identity) or clone.get('operation_id')!=snapshot['operation_id'] or clone.get('source_container_id')!=snapshot['source_container_id']:
        raise ValueError('Exact owned retained clone required')
    release=physical_directory(args.release)
    config=json.loads((release/'rehearsal.json').read_text())
    profile=config['profile'];meta=config['meta'];pins=config['source_pins']
    if profile.get('environment')!='qualification' or profile.get('id')!='collect-retained-rehearsal':
        raise ValueError('Isolated qualification profile required')
    records=migrations(ROOT)
    reviewed_chain(records)
    expected={'deploy/self-hosted/migrations.lock.json','scripts/supabase/testing/member-realtime-metadata.sql',
              *('supabase/migrations/'+r['name'] for r in records)}
    if set(pins)!=expected or sha(json.dumps(pins,sort_keys=True,separators=(',',':')).encode())!=meta['source_sha256']:
        raise ValueError('Exact source-bound SQL rehearsal required')
    for name,digest in pins.items():
        if sha((ROOT/name).read_bytes())!=digest or sha((release/'source'/name).read_bytes())!=digest:
            raise ValueError('Current migration/rehearsal bytes changed')
    if not args.execute:return {'planned':True,'executed':False,'production_acceptance':False}
    output=physical_directory(args.directory,fresh=True)
    docker=Docker(snapshot['docker_host'],output)
    def owned():
        require_owned_fresh_clone(docker.inspect(identity),snapshot,identity,clone.get('volume',''))
    counter=0
    def sql(text,*,database='postgres',user='postgres'):
        nonlocal counter
        owned();counter+=1
        result=docker.run(['exec','-i',identity,'psql','-h','/tmp','-U',user,'-d',database,'-XAtq','-v','ON_ERROR_STOP=1'],input=text.encode())
        path=output/f'sql-{counter:03d}.private.stdout'
        with path.open('xb') as stream:os.chmod(path,0o600);stream.write(result)
        return result
    before=json.loads(sql(STATE_SQL))
    baseline_journal=json.loads(sql(JOURNAL_SQL))
    baseline_journal_sha256=require_clean_baseline(before,baseline_journal,records)
    reused=None
    if args.reuse_empty:
        previous=physical_directory(args.reuse_empty)
        reused=json.loads((previous/'descriptor.json').read_text())
        if reused.get('format')!='collect.burimunsi.retained-qualification.v4' or reused.get('container_id')!=identity or reused.get('source_sha256')!=meta['source_sha256'] or reused.get('baseline_journal_sha256')!=baseline_journal_sha256 or not re.fullmatch(r'collect_burimunsi_[a-f0-9]{24}_test',reused.get('database','')):
            raise ValueError('Exact owned empty test database required')
    database=reused['database'] if reused else 'collect_burimunsi_'+uuid.uuid4().hex[:24]+'_test'
    descriptor={'format':'collect.burimunsi.retained-qualification.v4','container_id':identity,
                'baseline_journal_sha256':baseline_journal_sha256,'baseline_migrations':BASELINE_MIGRATIONS,
                'target_migrations':len(records),'target_migration':ADOPTION_MIGRATION,'contract':args.contract,'install_state':args.install_state,
                'database':database,'network':'none','published_ports':False,'source_sha256':meta['source_sha256'],
                'fixture_auth_inserted_by_sql':args.contract!='install-only','gotrue_exercised':False,'production_acceptance':False}
    private_json(output/'descriptor.json',descriptor)
    # Native preload workers keep the retained postgres database open. Use a
    # logical copy rather than terminating those workers to copy a template.
    # Dump/restore keeps the actual native Auth/Realtime definitions and ACLs.
    try:
        if reused:
            observed=json.loads(sql(STATE_SQL,database=database))
            if observed!=clean_state(upgraded=True):raise ValueError('Reused upgraded qualification must still have no fixture accounts')
        else:
            dump=output/'native-schema.private.dump'
            docker.run(['exec',identity,'pg_dump','-h','/tmp','-U','postgres','-d','postgres',
                        '--format=custom','--no-password'],output=dump)
            sql('CREATE DATABASE "'+database+'" WITH OWNER postgres TEMPLATE template0;',database='template1',user='supabase_admin')
            docker.run(['exec','-i',identity,'pg_restore','-h','/tmp','-U','supabase_admin','-d',database,
                        '--exit-on-error','--no-password'],input=dump.read_bytes())
    except Exception as error:
        private_json(output/'failure.json',{'status':'fail','stage':'private_native_database_copy',
                     'error_class':type(error).__name__,'diagnostics_retained_private':True,'production_acceptance':False})
        raise
    class NativeOperator:
        root=release
        def docker_preflight(self):owned();return {'network':'none','ports':False}
        def sql(self,text):return sql(text,database=database)
    op=NativeOperator();op.meta=meta;op.profile=profile
    installer=DatabaseInstaller(op)
    operations=(json.loads((previous/'initialization.json').read_text())['operations'] if reused else
                {name:str(uuid.uuid4()) for name in ('initialize','quiesce','release')})
    operations={name:str(uuid.UUID(value)) for name,value in operations.items()}
    if set(operations)!={'initialize','quiesce','release'}:raise ValueError('Exact qualification operation intent required')
    private_json(output/'initialization.json',{'operations':operations,'production_acceptance':False})
    try:
        if reused:
            upgrade=json.loads((previous/'qualification-upgrade.json').read_text())
            if (upgrade.get('format')!='collect.burimunsi.disposable-31-to-32-to-33-to-34-to-35.v1' or upgrade.get('new_migrations')!=[PIN_MIGRATION,LOCAL_STOPPED_MIGRATION,HANDOFF_MIGRATION,ADOPTION_MIGRATION]
                    or upgrade.get('preserved_journal_prefix')!=34 or upgrade.get('installation_state')!=args.install_state):
                raise ValueError('Exact prior disposable upgrade receipt required')
            rows=installer.applied()
            if (len(rows)!=len(records) or list(rows.values())[:BASELINE_MIGRATIONS]!=baseline_journal
                    or list(rows.values())[:32]!=upgrade.get('journal32') or list(rows.values())[:33]!=upgrade.get('journal33')
                    or list(rows.values())[:34]!=upgrade.get('journal34')):
                raise ValueError('Reused additive35 journal changed')
            require_control(json.loads(op.sql('SELECT private.collect_fence_owner_status();')),'open',2,operations['release'],meta['source_sha256'])
        else:
            upgrade=upgrade_disposable_baseline(installer,baseline_journal,operations,install_state=args.install_state)
        private_json(output/'qualification-upgrade.json',upgrade)
    except Exception as error:
        private_json(output/'failure.json',{'status':'fail','stage':'isolated_31_to_32_to_33_to_34_to_35_upgrade',
                     'error_class':type(error).__name__,'diagnostics_retained_private':True,'production_acceptance':False})
        raise
    inputs={name:digest for name,digest in pins.items()}
    inputs[Path(__file__).relative_to(ROOT).as_posix()]=sha(Path(__file__).read_bytes())
    def scoped_contract(template,kind,fields):
        """Run actual statements as normal collect_runtime, compiling shared SQL when needed,
        with an independently held, real registered application WORK lease.
        This qualifies SQL/RLS, not an Edge HTTP or GoTrue/native login.
        """
        plan={}
        if fields:
            node=shutil.which('node')
            if not node or not subprocess.run([node,'--version'],check=True,capture_output=True,text=True).stdout.startswith('v24.'):
                raise ValueError('Current Node24 fixture compiler required')
            compiler_kind='gateway-handoff' if kind.startswith('gateway-handoff') else kind
            compiler=ROOT/f'supabase/tests/burimunsi/compile-{compiler_kind}-fixture.mjs'
            inputs[compiler.relative_to(ROOT).as_posix()]=sha(compiler.read_bytes())
            compiled=compile_fixture_process(node,compiler,output,kind)
            plan=json.loads(compiled.stdout)
            if plan.get('format')!=fixture_format(kind) or plan.get('production_acceptance') is not False:
                raise ValueError('Exact SQL-only fixture compiler required')
            private_json(output/f'{kind}-statements.json',plan)
            for name,digest in plan['sources'].items():
                if not re.fullmatch(r'[a-zA-Z0-9_./-]+',name) or '..' in Path(name).parts or sha((ROOT/name).read_bytes())!=digest:
                    raise ValueError('Compiled member source changed')
                inputs[name]=digest
        admission=str(uuid.uuid4());source=meta['source_sha256']
        prefix="BEGIN ISOLATION LEVEL READ COMMITTED;SET LOCAL ROLE collect_runtime;SET LOCAL collect.edge_verified='true';"
        work_kind='http_admin' if kind in ('provisioning','scope-setup','platform-public-group') else 'http_collect'
        registered=json.loads(sql(prefix+"SELECT private.collect_fence_register('"+admission+"'::uuid,'"+source+"','"+work_kind+"');COMMIT;",database=database))
        epoch=registered.get('epoch')
        if registered.get('admissionId')!=admission or registered.get('sourceSha256')!=source or registered.get('state')!='active' or not isinstance(epoch,int) or epoch<1:
            raise ValueError('Genuine member SQL work registration required')
        private_json(output/f'{kind}-work-registration.json',registered)
        lease_query=prefix+"SET LOCAL statement_timeout='5s';SET LOCAL lock_timeout='5s';SELECT pg_advisory_xact_lock_shared(7346371,1);SELECT private.collect_fence_assert_work('"+admission+"'::uuid,"+str(epoch)+",'"+source+"');\n\\echo COLLECT_SCOPED_LEASE_READY\n"
        lease_error=(output/f'{kind}-lease.private.stderr').open('xb');os.chmod(lease_error.name,0o600)
        owned();lease=subprocess.Popen(['docker','-H',snapshot['docker_host'],'exec','-i',identity,'psql','-h','/tmp','-U','postgres','-d',database,
                    '-XAtq','-v','ON_ERROR_STOP=1'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=lease_error)
        observed=b''
        try:
            lease.stdin.write(lease_query.encode());lease.stdin.flush();deadline=time.monotonic()+10
            while b'COLLECT_SCOPED_LEASE_READY\n' not in observed:
                if lease.poll() is not None or time.monotonic()>=deadline:raise ValueError('Member SQL lease unconfirmed')
                ready,_,_=select.select([lease.stdout],[],[],max(0,deadline-time.monotonic()))
                if ready:
                    chunk=os.read(lease.stdout.fileno(),8192)
                    if not chunk:raise ValueError('Member SQL lease ended')
                    observed+=chunk
            replacements={'ADMISSION_ID':admission,'ADMISSION_EPOCH':str(epoch),'ADMISSION_SOURCE':source,
                          **{('PLATFORM_PUBLIC_INPUTS' if kind=='platform-public-group' and name=='setup_inputs' else name.upper()):plan[name] for name in fields}}
            text=template
            if '__HANDOFF_SUPPORT__' in text:
                support=ROOT/'supabase/tests/burimunsi/gateway-handoff-support.sql'
                inputs[support.relative_to(ROOT).as_posix()]=sha(support.read_bytes())
                text=text.replace('__HANDOFF_SUPPORT__',support.read_text())
            for name,value in replacements.items():
                if '__'+name+'__' not in text:raise ValueError('Member fixture template mismatch')
                text=text.replace('__'+name+'__',value)
            if '__HANDOFF_RACE__' in text:
                setup,recovery=text.split('__HANDOFF_RACE__')
                concurrent_handoff(setup,recovery,replacements,kind)
            else:
                sql(text,database=database)
            if kind=='canonical-adoption':
                # Same owned network-none QA database; producer WORK stays
                # held, and original native Allocate registers its own real WORK. Original JS native/financial components run
                # on PostgreSQL; no provider, port or production target.
                owned()
                runner=ROOT/'supabase/tests/burimunsi/run-canonical-allocation-fixture.mjs'
                inputs[runner.relative_to(ROOT).as_posix()]=sha(runner.read_bytes())
                command=[node,str(runner)]
                payload={'docker':shutil.which('docker'),'host':snapshot['docker_host'],
                         'container':identity,'database':database,'template':text,'payload':plan['payload'],'body':plan['body'],
                         'admission':admission,'epoch':epoch,'sourceSha256':source,'kind':work_kind,
                         'rawOutput':str(output/'canonical-native-allocation.private.raw.json')}
                actual=subprocess.run(command,input=json.dumps(payload).encode(),cwd=ROOT,capture_output=True,timeout=90)
                for suffix,value in (('stdout',actual.stdout),('stderr',actual.stderr)):
                    with (output/('canonical-native-allocation.private.'+suffix)).open('xb') as stream:
                        os.chmod(stream.name,0o600);stream.write(value)
                actual.check_returncode()
                allocation=json.loads(actual.stdout)
                require_allocation_result(allocation)
                private_json(output/'canonical-native-allocation-result.json',allocation)
            closed=json.loads(sql(prefix+"SELECT private.collect_fence_close('"+admission+"'::uuid,"+str(epoch)+",'"+source+"','settled','completed',0,0);COMMIT;",database=database))
            if closed.get('state')!='settled' or closed.get('externalDispatches')!=0 or closed.get('uncertainDispatches')!=0:
                raise ValueError('Member SQL work closure unconfirmed')
            private_json(output/f'{kind}-work-close.json',closed)
        except Exception:
            # Do not leave an apparently running admission after a failed
            # qualification. Preserve uncertainty; this never claims business
            # success or dispatch knowledge from a lost SQL acknowledgement.
            try:
                closed=json.loads(sql(prefix+"SELECT private.collect_fence_close('"+admission+"'::uuid,"+str(epoch)+",'"+source+"','unresolved','work_lost',0,0);COMMIT;",database=database))
                private_json(output/f'{kind}-work-failure-close.json',closed)
            except Exception:
                private_json(output/f'{kind}-work-failure-close.json',{'status':'unconfirmed','production_acceptance':False})
            raise
        finally:
            try:
                rest,_=lease.communicate(input=b'ROLLBACK;\n\\q\n',timeout=10);observed+=rest
                if lease.returncode:raise ValueError('Member SQL lease cleanup unconfirmed')
            except subprocess.TimeoutExpired:
                lease.kill();lease.communicate(timeout=5);raise ValueError('Member SQL lease cleanup timed out')
            finally:
                lease_error.close();path=output/f'{kind}-lease.private.stdout'
                with path.open('xb') as stream:os.chmod(path,0o600);stream.write(observed)
    def concurrent_handoff(setup,recovery,replacements,kind):
        """Actual two-connection native/Owner serialization in the owned copy.

        The old-phone transaction holds the real setup lock before Owner starts.
        Observed pg_stat_activity lock-wait is required; timing is not evidence.
        No request is retried after missing acknowledgement.
        """
        support=ROOT/'supabase/tests/burimunsi/gateway-handoff-support.sql'
        helpers=support.read_text().split('-- Initial disabled scope,',1)[0]
        admission=replacements['ADMISSION_ID'];epoch=replacements['ADMISSION_EPOCH'];source=replacements['ADMISSION_SOURCE']
        owner_tag='collect_handoff_owner_'+admission.replace('-','')
        frame="BEGIN;SET LOCAL search_path=app,pg_catalog;SET LOCAL lock_timeout='10s';SET LOCAL statement_timeout='20s';"+helpers+"SET LOCAL ROLE collect_runtime;"
        frame+="SELECT set_config('collect.edge_verified','true',true),set_config('burimunsi.collection_id','buri-qualification-group',true),"
        frame+="set_config('collect.fence_admission_id',"+literal(admission)+",true),set_config('collect.fence_epoch',"+literal(epoch)+",true),set_config('collect.fence_source_sha256',"+literal(source)+",true);"
        query="SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'));COMMIT;\n"
        owner_command="SELECT pg_temp.h_apply(jsonb_build_object('operation','finalize_replacement','collectionId','buri-qualification-group','requestId','fd331000-0000-4000-8000-000000000003','expectedScopeVersion',2,'receivingAccountId','buri-qualification-wallet','reason','QUALIFICATION concurrent Owner recovery','handoffId','fd331000-0000-4000-8000-000000000002'))"
        sql(setup,database=database)
        processes=[];streams=[]
        def start(label,initial,ready):
            path=output/(kind+'-'+label+'.private.stderr');stream=path.open('xb');os.chmod(path,0o600);streams.append(stream)
            owned();process=subprocess.Popen(['docker','-H',snapshot['docker_host'],'exec','-i',identity,'psql','-h','/tmp','-U','postgres','-d',database,'-XAtq','-v','ON_ERROR_STOP=1'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=stream)
            record={'process':process,'label':label,'observed':b''};processes.append(record)
            process.stdin.write(initial.encode());process.stdin.flush();deadline=time.monotonic()+10
            while ready.encode() not in record['observed']:
                if process.poll() is not None or time.monotonic()>=deadline:raise ValueError('Concurrent handoff participant not ready')
                readable,_,_=select.select([process.stdout],[],[],max(0,deadline-time.monotonic()))
                if readable:
                    chunk=os.read(process.stdout.fileno(),8192)
                    if not chunk:raise ValueError('Concurrent handoff participant ended')
                    record['observed']+=chunk
            return record
        try:
            native=start('native',frame+"SELECT pg_temp.h_set('old-current','fd330000-0000-4000-8000-000000000001','old-device');SELECT pg_advisory_xact_lock(734636924058501::bigint);\n\\echo HANDOFF_NATIVE_LOCKED\n",'HANDOFF_NATIVE_LOCKED')
            owner=start('owner',frame+"SET LOCAL application_name="+literal(owner_tag)+";SELECT pg_temp.h_owner();\n\\echo HANDOFF_OWNER_STARTED\nSELECT pg_temp.h_expect($race$"+owner_command+"$race$,'40001');COMMIT;\n",'HANDOFF_OWNER_STARTED')
            deadline=time.monotonic()+5;waiting=False
            while time.monotonic()<deadline:
                waiting=json.loads(sql("SELECT to_json(count(*)=1) FROM pg_stat_activity WHERE datname="+literal(database)+" AND application_name="+literal(owner_tag)+" AND wait_event_type='Lock' AND wait_event='advisory';",database=database))
                if waiting:break
                time.sleep(0.02)
            if waiting is not True:raise ValueError('Actual Owner setup advisory lock wait unconfirmed')
            native['process'].stdin.write(query.encode());native['process'].stdin.flush()
            for record in (native,owner):
                rest,_=record['process'].communicate(timeout=25);record['observed']+=rest
                if record['process'].returncode:raise ValueError('Concurrent handoff participant outcome unconfirmed')
            private_json(output/(kind+'-concurrency.json'),{'status':'pass','native_committed_once':True,'owner_advisory_wait_observed':True,'owner_stale_cas_rejected':True,'post_replay':False,'provider_calls':0,'production_acceptance':False})
            sql(helpers+recovery,database=database)
        finally:
            for record in processes:
                process=record['process']
                if process.poll() is None:
                    process.kill();rest,_=process.communicate(timeout=5);record['observed']+=rest
                path=output/(kind+'-'+record['label']+'.private.stdout')
                with path.open('xb') as stream:os.chmod(path,0o600);stream.write(record['observed'])
            for stream in streams:stream.close()
    checks=[]
    try:
        selected=selected_fixtures(args.contract)
        for name in selected:
            path=ROOT/'supabase/tests/burimunsi'/name
            inputs[path.relative_to(ROOT).as_posix()]=sha(path.read_bytes())
            if name in COMPILED_CONTRACTS:scoped_contract(path.read_text(),*COMPILED_CONTRACTS[name])
            else:sql(path.read_text(),database=database)
            checks.append({'fixture':name,'status':'pass'})
        if json.loads(sql(STATE_SQL))!=before or json.loads(sql(JOURNAL_SQL))!=baseline_journal:
            raise ValueError('Clean31 rehearsal source or immutable journal changed')
        result={**descriptor,'status':'pass','checks':checks,'inputs':inputs,'clean_rehearsal_unchanged':True,
                'live_source_migrated':False,'provider_calls':0,'test_database_retained_private':True,
                'additive32_installed_fenced':args.install_state=='fenced','additive33_installed_fenced':args.install_state=='fenced',
                'additive34_installed_fenced':args.install_state=='fenced','additive35_installed_fenced':args.install_state=='fenced','preserved_journal_prefix':34}
        private_json(output/'result.json',result)
        return {k:result[k] for k in ['status','checks','clean_rehearsal_unchanged','gotrue_exercised','production_acceptance']}
    except Exception as error:
        private_json(output/'failure.json',{'status':'fail','error_class':type(error).__name__,'checks':checks,
                     'diagnostics_retained_private':True,'production_acceptance':False})
        raise

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot-directory',type=Path,required=True)
    parser.add_argument('--release',type=Path,required=True)
    parser.add_argument('--directory',type=Path,required=True)
    parser.add_argument('--execute',action='store_true')
    parser.add_argument('--contract',choices=('all','install-only','member','source','provisioning','gateway','scope-setup','gateway-upload','managed-email','phone-pin','phone-pin-readonly','gateway-handoff','gateway-handoff-readonly','platform-public-group','canonical-adoption'),default='all',
                        help='Bounded qualification slice; all maintained contracts run by default')
    parser.add_argument('--install-state',choices=('fenced','uninitialized'),default='fenced',help='Explicit normal DDL state for the clean31 baseline; CURRENT32 repair has a separate qualifier')
    parser.add_argument('--reuse-empty',type=Path,help='Reuse only an exact previously owned additive35 test database with zero fixture accounts')
    try:
        print(json.dumps(qualify(parser.parse_args()),sort_keys=True))
    except Exception as error:
        print(json.dumps({'status':'refused_or_unconfirmed','error_class':type(error).__name__,'private_values_disclosed':False}),file=sys.stderr)
        sys.exit(1)

"""Qualify BuriMunsi SQL on a disposable copy of an isolated retained clone.

No live source migration, GoTrue call, email, SMS, network or financial operation.
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
from scripts.self_hosted.retained_snapshot import Docker,LABEL,verify_snapshot,physical_directory,private_json
from scripts.self_hosted.database import DatabaseInstaller,migrations,sha

FIXTURES=('operator-seed.sql','operator-readonly.sql','operator-contract.sql','member-command-contract.sql')

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
    if len(records)!=26 or records[-1]['name']!='20261109234517_burimunsi_native_operator_schema.sql':
        raise ValueError('Exact reviewed BuriMunsi migration chain required')
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
        current=docker.inspect(identity)
        if current['Id']!=identity or current['Image']!=snapshot['image_id'] or not current['State']['Running'] or current['Config']['Labels'].get(LABEL)!=snapshot['operation_id'] or current['HostConfig']['NetworkMode']!='none' or current['HostConfig'].get('PortBindings') or current['NetworkSettings'].get('Ports'):
            raise ValueError('Exact running isolated native clone required')
    counter=0
    def sql(text,*,database='postgres',user='postgres'):
        nonlocal counter
        owned();counter+=1
        result=docker.run(['exec','-i',identity,'psql','-h','/tmp','-U',user,'-d',database,'-XAtq','-v','ON_ERROR_STOP=1'],input=text.encode())
        path=output/f'sql-{counter:03d}.private.stdout'
        with path.open('xb') as stream:os.chmod(path,0o600);stream.write(result)
        return result
    state_sql="SELECT json_build_object('auth_users',(SELECT count(*) FROM auth.users),'native_accounts',(SELECT count(*) FROM private.burimunsi_accounts),'fence_initialized',EXISTS(SELECT 1 FROM private.collect_fence_control),'migrations',(SELECT count(*) FROM supabase_migrations.collect_installation_steps));"
    before=json.loads(sql(state_sql))
    if before!={'auth_users':0,'native_accounts':0,'fence_initialized':False,'migrations':26}:
        raise ValueError('Clean inactive native schema rehearsal required')
    reused=None
    if args.reuse_empty:
        previous=physical_directory(args.reuse_empty)
        reused=json.loads((previous/'descriptor.json').read_text())
        if reused.get('format')!='collect.burimunsi.retained-qualification.v1' or reused.get('container_id')!=identity or reused.get('source_sha256')!=meta['source_sha256'] or not re.fullmatch(r'collect_burimunsi_[a-f0-9]{24}_test',reused.get('database','')):
            raise ValueError('Exact owned empty test database required')
    database=reused['database'] if reused else 'collect_burimunsi_'+uuid.uuid4().hex[:24]+'_test'
    descriptor={'format':'collect.burimunsi.retained-qualification.v1','container_id':identity,
                'database':database,'network':'none','published_ports':False,'source_sha256':meta['source_sha256'],
                'fixture_auth_inserted_by_sql':True,'gotrue_exercised':False,'production_acceptance':False}
    private_json(output/'descriptor.json',descriptor)
    # Native preload workers keep the retained postgres database open. Use a
    # logical copy rather than terminating those workers to copy a template.
    # Dump/restore keeps the actual native Auth/Realtime definitions and ACLs.
    try:
        if reused:
            observed=json.loads(sql(state_sql,database=database))
            if observed!={**before,'fence_initialized':True}:raise ValueError('Reused qualification must still have no fixture accounts')
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
    operation=uuid.UUID(json.loads((previous/'initialization.json').read_text())['operation_id']) if reused else uuid.uuid4()
    private_json(output/'initialization.json',{'operation_id':str(operation),'production_acceptance':False})
    installer.initialize(operation)
    inputs={name:digest for name,digest in pins.items()}
    inputs[Path(__file__).relative_to(ROOT).as_posix()]=sha(Path(__file__).read_bytes())
    def member_contract(template):
        """Compile actual common statements, then run as normal collect_runtime
        with an independently held, real registered application WORK lease.
        This qualifies SQL/RLS, not an Edge HTTP or GoTrue/native login.
        """
        node=shutil.which('node')
        if not node or not subprocess.run([node,'--version'],check=True,capture_output=True,text=True).stdout.startswith('v24.'):
            raise ValueError('Current Node24 fixture compiler required')
        compiler=ROOT/'supabase/tests/burimunsi/compile-member-fixture.mjs'
        inputs[compiler.relative_to(ROOT).as_posix()]=sha(compiler.read_bytes())
        compiled=subprocess.run([node,str(compiler)],cwd=ROOT,check=True,capture_output=True,timeout=30)
        plan=json.loads(compiled.stdout)
        if plan.get('format')!='collect.burimunsi.member-sql-fixture.v1' or plan.get('production_acceptance') is not False:
            raise ValueError('Exact SQL-only fixture compiler required')
        private_json(output/'member-statements.json',plan)
        for name,digest in plan['sources'].items():
            if not re.fullmatch(r'[a-zA-Z0-9_./-]+',name) or '..' in Path(name).parts or sha((ROOT/name).read_bytes())!=digest:
                raise ValueError('Compiled member source changed')
            inputs[name]=digest
        admission=str(uuid.uuid4());source=meta['source_sha256']
        prefix="BEGIN ISOLATION LEVEL READ COMMITTED;SET LOCAL ROLE collect_runtime;SET LOCAL collect.edge_verified='true';"
        registered=json.loads(sql(prefix+"SELECT private.collect_fence_register('"+admission+"'::uuid,'"+source+"','http_collect');COMMIT;",database=database))
        epoch=registered.get('epoch')
        if registered.get('admissionId')!=admission or registered.get('sourceSha256')!=source or registered.get('state')!='active' or not isinstance(epoch,int) or epoch<1:
            raise ValueError('Genuine member SQL work registration required')
        private_json(output/'member-work-registration.json',registered)
        lease_query=prefix+"SET LOCAL statement_timeout='5s';SET LOCAL lock_timeout='5s';SELECT pg_advisory_xact_lock_shared(7346371,1);SELECT private.collect_fence_assert_work('"+admission+"'::uuid,"+str(epoch)+",'"+source+"');\n\\echo COLLECT_MEMBER_LEASE_READY\n"
        lease_error=(output/'member-lease.private.stderr').open('xb');os.chmod(lease_error.name,0o600)
        owned();lease=subprocess.Popen(['docker','-H',snapshot['docker_host'],'exec','-i',identity,'psql','-h','/tmp','-U','postgres','-d',database,
                    '-XAtq','-v','ON_ERROR_STOP=1'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=lease_error)
        observed=b''
        try:
            lease.stdin.write(lease_query.encode());lease.stdin.flush();deadline=time.monotonic()+10
            while b'COLLECT_MEMBER_LEASE_READY\n' not in observed:
                if lease.poll() is not None or time.monotonic()>=deadline:raise ValueError('Member SQL lease unconfirmed')
                ready,_,_=select.select([lease.stdout],[],[],max(0,deadline-time.monotonic()))
                if ready:
                    chunk=os.read(lease.stdout.fileno(),8192)
                    if not chunk:raise ValueError('Member SQL lease ended')
                    observed+=chunk
            replacements={'ADMISSION_ID':admission,'ADMISSION_EPOCH':str(epoch),'ADMISSION_SOURCE':source,
                          **{name.upper():plan[name] for name in ['guards','person','membership','change','audit']}}
            text=template
            for name,value in replacements.items():
                if '__'+name+'__' not in text:raise ValueError('Member fixture template mismatch')
                text=text.replace('__'+name+'__',value)
            sql(text,database=database)
            closed=json.loads(sql(prefix+"SELECT private.collect_fence_close('"+admission+"'::uuid,"+str(epoch)+",'"+source+"','settled','completed',0,0);COMMIT;",database=database))
            if closed.get('state')!='settled' or closed.get('externalDispatches')!=0 or closed.get('uncertainDispatches')!=0:
                raise ValueError('Member SQL work closure unconfirmed')
            private_json(output/'member-work-close.json',closed)
        except Exception:
            # Do not leave an apparently running admission after a failed
            # qualification. Preserve uncertainty; this never claims business
            # success or dispatch knowledge from a lost SQL acknowledgement.
            try:
                closed=json.loads(sql(prefix+"SELECT private.collect_fence_close('"+admission+"'::uuid,"+str(epoch)+",'"+source+"','unresolved','work_lost',0,0);COMMIT;",database=database))
                private_json(output/'member-work-failure-close.json',closed)
            except Exception:
                private_json(output/'member-work-failure-close.json',{'status':'unconfirmed','production_acceptance':False})
            raise
        finally:
            try:
                rest,_=lease.communicate(input=b'ROLLBACK;\n\\q\n',timeout=10);observed+=rest
                if lease.returncode:raise ValueError('Member SQL lease cleanup unconfirmed')
            except subprocess.TimeoutExpired:
                lease.kill();lease.communicate(timeout=5);raise ValueError('Member SQL lease cleanup timed out')
            finally:
                lease_error.close();path=output/'member-lease.private.stdout'
                with path.open('xb') as stream:os.chmod(path,0o600);stream.write(observed)
    checks=[]
    try:
        for name in FIXTURES:
            path=ROOT/'supabase/tests/burimunsi'/name
            inputs[path.relative_to(ROOT).as_posix()]=sha(path.read_bytes())
            if name=='member-command-contract.sql':member_contract(path.read_text())
            else:sql(path.read_text(),database=database)
            checks.append({'fixture':name,'status':'pass'})
        if json.loads(sql(state_sql))!=before:raise ValueError('Clean rehearsal source changed')
        result={**descriptor,'status':'pass','checks':checks,'inputs':inputs,'clean_rehearsal_unchanged':True,
                'live_source_migrated':False,'provider_calls':0,'test_database_retained_private':True}
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
    parser.add_argument('--reuse-empty',type=Path,help='Reuse only an exact previously owned, initialized test database with zero fixture accounts')
    try:
        print(json.dumps(qualify(parser.parse_args()),sort_keys=True))
    except Exception as error:
        print(json.dumps({'status':'refused_or_unconfirmed','error_class':type(error).__name__,'private_values_disclosed':False}),file=sys.stderr)
        sys.exit(1)

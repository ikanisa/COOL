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
import sys
import uuid
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from scripts.self_hosted.retained_snapshot import Docker,LABEL,verify_snapshot,physical_directory,private_json
from scripts.self_hosted.database import DatabaseInstaller,migrations,sha

FIXTURES=('operator-seed.sql','operator-readonly.sql','operator-contract.sql')

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
    checks=[]
    try:
        for name in FIXTURES:
            path=ROOT/'supabase/tests/burimunsi'/name
            inputs[path.relative_to(ROOT).as_posix()]=sha(path.read_bytes())
            sql(path.read_text(),database=database)
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

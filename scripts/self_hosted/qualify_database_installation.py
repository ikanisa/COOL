"""Execute the maintained fresh installer on a new owned PostgreSQL 17 cluster.

Only fixed loopback port 55447 and fresh private paths are accepted. Auth and
Realtime are the explicitly synthetic interfaces used by existing fixtures;
Docker, actual GoTrue/Realtime services and production admission are not tested.
The installer, migration transactions and immutable journal are real.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import uuid
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from scripts.self_hosted.database import DatabaseInstaller,HOSTED_METADATA,SQL10,sha,migrations
from scripts.supabase.deployment_profile import canonical_profile,profile_sha256

PORT=55447
INPUTS=('scripts/self_hosted/database.py','scripts/self_hosted/qualify_database_installation.py',
        'scripts/supabase/deployment_profile.py','deploy/self-hosted/migrations.lock.json',
        'deploy/self-hosted/images.lock.json','supabase/tests/sql/00_local_auth_fixture.sql',
        'scripts/supabase/testing/member-realtime-interface.sql','scripts/supabase/testing/member-realtime-metadata.sql')

def write_private(path,value):
    with path.open('xb') as stream:os.chmod(path,0o600);stream.write(value)

def qualify(args):
    if os.environ.get('COLLECT_CI_SYNTHETIC')!='true':raise ValueError('Explicit synthetic qualification required')
    base=args.private_directory.absolute();receipt=args.receipt.absolute();binaries=args.pg_bin.resolve(strict=True)
    if base.exists() or base.parent.resolve(strict=True)!=base.parent or receipt.exists() or receipt.parent.resolve(strict=True)!=receipt.parent:raise ValueError('Fresh physical paths required')
    for name in ('postgres','initdb','pg_ctl','psql'):
        if not (binaries/name).is_file():raise ValueError('Complete native PostgreSQL toolchain required')
    with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as probe:probe.bind(('127.0.0.1',PORT))
    sources=[*INPUTS,*[p.relative_to(ROOT).as_posix() for p in sorted((ROOT/'supabase/migrations').glob('*.sql'))]]
    reviewed=migrations(ROOT)
    expected_count=len(reviewed)
    pins={name:sha((ROOT/name).read_bytes()) for name in sources}
    profile=json.loads((ROOT/'deploy/self-hosted/profile.example.json').read_text())
    profile.update({'id':'collect-installer-qualification','environment':'qualification'})
    source_sha=sha(json.dumps(pins,sort_keys=True,separators=(',',':')).encode())
    uid,gid=(65534,65534) if os.getuid()==0 else (os.getuid(),os.getgid())
    runner=['setpriv','--reuid='+str(uid),'--regid='+str(gid),'--clear-groups'] if os.getuid()==0 else []
    os.umask(0o077);base.mkdir(mode=0o700)
    if os.getuid()==0:os.chown(base,uid,gid)
    socket_dir=base/'socket';socket_dir.mkdir(mode=0o700)
    if os.getuid()==0:os.chown(socket_dir,uid,gid)
    bootstrap_password=secrets.token_hex(32);owner_password=secrets.token_hex(32)
    counter=0;started=False;stage='initialize';checks=[];result={}
    def run(command,input_bytes=None,env=None,timeout=60,allowed_failure=False):
        nonlocal counter
        counter+=1
        completed=subprocess.run(command,cwd=ROOT,input=input_bytes,env=env,capture_output=True,timeout=timeout)
        write_private(base/('command-'+str(counter)+'.private.log'),completed.stdout+b'\n'+completed.stderr)
        if completed.returncode and not allowed_failure:raise RuntimeError('Native installer command failed; private diagnostic retained')
        return completed
    def sql(text,*,bootstrap=False,allowed_failure=False):
        env={key:os.environ[key] for key in ('PATH','LD_LIBRARY_PATH') if key in os.environ}
        env.update({'PGHOST':'127.0.0.1','PGPORT':str(PORT),'PGDATABASE':'postgres' if bootstrap else 'collect_installer_test',
                    'PGUSER':'collect_installer_bootstrap' if bootstrap else 'postgres','PGPASSWORD':bootstrap_password if bootstrap else owner_password,'PGCONNECT_TIMEOUT':'5'})
        return run([str(binaries/'psql'),'--no-psqlrc','--no-password','--quiet','--tuples-only','--no-align','--set','ON_ERROR_STOP=1'],input_bytes=text.encode(),env=env,allowed_failure=allowed_failure)
    try:
        password_file=base/'bootstrap-password';write_private(password_file,(bootstrap_password+'\n').encode())
        if os.getuid()==0:os.chown(password_file,uid,gid)
        run(runner+[str(binaries/'initdb'),'-D',str(base/'data'),'-U','collect_installer_bootstrap','--encoding=UTF8','--locale=C','--auth-host=scram-sha-256','--auth-local=scram-sha-256','--pwfile='+str(password_file)])
        password_file.unlink()
        with (base/'data/postgresql.conf').open('a') as stream:stream.write("\nlisten_addresses='127.0.0.1'\nport=55447\nunix_socket_directories='"+str(socket_dir).replace("'","''")+"'\ntimezone='UTC'\nlog_timezone='UTC'\nlog_statement='none'\nlog_min_error_statement='panic'\n")
        run(runner+[str(binaries/'pg_ctl'),'-D',str(base/'data'),'-l',str(base/'server.private.log'),'-w','-t','20','start']);started=True
        stage='synthetic_platform_setup'
        sql("CREATE ROLE postgres LOGIN NOSUPERUSER NOINHERIT CREATEROLE NOCREATEDB NOBYPASSRLS NOREPLICATION PASSWORD '"+owner_password+"';CREATE DATABASE collect_installer_test OWNER postgres;",bootstrap=True)
        # Platform-shape doubles are created by the actual owner. Their contents
        # remain explicitly synthetic; the installed application is unchanged.
        sql((ROOT/'supabase/tests/sql/00_local_auth_fixture.sql').read_text())
        sql((ROOT/'scripts/supabase/testing/member-realtime-interface.sql').read_text())
        sql('ALTER TABLE auth.users ADD COLUMN email_confirmed_at timestamptz;ALTER TABLE auth.users ADD COLUMN is_anonymous boolean NOT NULL DEFAULT false;')
        stage='release_fixture'
        release=base/'release';(release/'source').mkdir(parents=True);(release/'private').mkdir(mode=0o700)
        for name in sources:
            target=release/'source'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/name,target)
        shutil.copyfile(ROOT/'deploy/self-hosted/images.lock.json',release/'images.lock.json')
        write_private(release/'private/keys.json',json.dumps({'COLLECT_EDGE_PASSWORD':secrets.token_hex(32),'COLLECT_SMS_EDGE_PASSWORD':secrets.token_hex(32)}).encode())
        class NativeOperator:
            root=release
            meta={'profile_sha256':profile_sha256(profile),'source_sha256':source_sha}
            def docker_preflight(self):return {'explicit_native_transport_substitution':True}
            def sql(self,text):return sql(text).stdout
        op=NativeOperator();op.profile=profile
        installer=DatabaseInstaller(op)
        stage='foundation'
        first=installer.foundation();assert len(first['new_migrations'])==9
        assert installer.foundation()['new_migrations']==[]
        checks.append({'case':'nine_real_migrations_commit_with_journal_and_exact_retry','status':'pass'})
        stage='capture_and_binding'
        observation_path=base/'platform-observation.private.json';installer.capture(observation_path)
        observation=json.loads(observation_path.read_text());assert observation['status']=='observed_not_admitted'
        raw=(release/'source/supabase/migrations'/SQL10).read_text();rendered=raw.replace("'"+HOSTED_METADATA+"'","'"+observation['metadata_sha256']+"'")
        # This is explicit local test evidence, never a production approval.
        binding={key:observation[key] for key in ('profile_sha256','source_sha256','images_sha256','metadata_sha256','metadata_expression_sha256')}
        binding.update({'format':'collect.selfhost.realtime-binding.v1','status':'reviewed','sql10_source_sha256':sha(raw.encode()),'sql10_rendered_sha256':sha(rendered.encode()),
                        'review_evidence_sha256':sha(json.dumps({'synthetic_platform_interface':True,'production_approval':False,'observation':observation},sort_keys=True).encode())})
        bad=base/'wrong-binding.private.json';write_private(bad,json.dumps({**binding,'profile_sha256':'0'*64}).encode())
        refused=False
        try:installer.complete(bad)
        except ValueError:refused=True
        assert refused and len(installer.applied())==9
        checks.append({'case':'mismatched_platform_review_refused_before_next_migration','status':'pass'})
        binding_path=base/'synthetic-binding.private.json';write_private(binding_path,json.dumps(binding).encode())
        stage='complete'
        completed=installer.complete(binding_path);assert completed['migration_count']==expected_count and len(completed['new_migrations'])==expected_count-9
        assert installer.complete(binding_path)['new_migrations']==[]
        rows=installer.applied();assert len(rows)==expected_count
        checks.append({'case':f'complete_{expected_count}_migration_transaction_journals_and_exact_retry','status':'pass'})
        stage='initialize'
        operation=uuid.uuid4();installer.initialize(operation);installer.initialize(operation)
        refused=False
        try:installer.initialize(uuid.uuid4())
        except RuntimeError:refused=True
        assert refused
        checks.append({'case':'same_original_initialization_uuid_readback_and_other_uuid_refusal','status':'pass'})
        stage='journal_immutability'
        for statement in ("DELETE FROM supabase_migrations.collect_installation_steps", "UPDATE supabase_migrations.collect_installation_steps SET source_sha256=repeat('0',64)","TRUNCATE supabase_migrations.collect_installation_steps"):
            failed=sql(statement,allowed_failure=True);assert failed.returncode and b'installation_history_is_immutable' in failed.stderr
        assert len(installer.applied())==expected_count
        checks.append({'case':'owner_update_delete_truncate_refused_without_journal_loss','status':'pass'})
        stage='transaction_rollback'
        failed=sql("BEGIN;CREATE TABLE public.collect_journal_rollback_probe(id integer);INSERT INTO supabase_migrations.collect_installation_steps(version,source_sha256,rendered_sha256,profile_sha256,operation_id) SELECT version,source_sha256,rendered_sha256,profile_sha256,gen_random_uuid() FROM supabase_migrations.collect_installation_steps LIMIT 1;COMMIT;",allowed_failure=True)
        assert failed.returncode and sql("SELECT to_regclass('public.collect_journal_rollback_probe') IS NULL;").stdout.strip()==b't'
        checks.append({'case':'journal_conflict_rolls_back_original_ddl_in_same_transaction','status':'pass'})
        stage='source_readback'
        assert pins=={name:sha((ROOT/name).read_bytes()) for name in sources}
        result={'status':'pass','migration_count':expected_count,'checks':checks,'initialization_operation_id':str(operation)}
    except Exception as error:
        write_private(base/'failure.private.log',(type(error).__name__+': '+str(error)+'\n').encode())
        result={'status':'fail','stage':stage,'error_class':type(error).__name__,'checks':checks,'private_diagnostics_retained':True}
    finally:
        if started:
            try:run(runner+[str(binaries/'pg_ctl'),'-D',str(base/'data'),'-w','-t','20','-m','fast','stop']);result['owned_cluster_stopped']=True
            except Exception:result.update({'status':'fail','owned_cluster_stopped':False,'cleanup_unconfirmed':True})
    result.update({'format':'collect.selfhost.native-installer.v1','postgres_major':17,'owned_loopback_port':PORT,'inputs':pins,
                   'source_sha256':source_sha,'profile_sha256':profile_sha256(profile),'synthetic_auth_and_realtime':True,
                   'actual_non_superuser_owner':True,'docker_transport_substituted':True,'external_provider_calls':0,'production_acceptance':False})
    with receipt.open('x') as stream:os.chmod(receipt,0o644);json.dump(result,stream,indent=2);stream.write('\n')
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--pg-bin',type=Path,required=True);parser.add_argument('--private-directory',type=Path,required=True);parser.add_argument('--receipt',type=Path,required=True);args=parser.parse_args()
    try:
        result=qualify(args);print(json.dumps({key:result.get(key) for key in ('status','stage','migration_count','owned_cluster_stopped','production_acceptance')}));sys.exit(0 if result['status']=='pass' else 1)
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as error:
        print(json.dumps({'status':'refused','error_class':type(error).__name__,'private_values_disclosed':False}),file=sys.stderr);sys.exit(1)

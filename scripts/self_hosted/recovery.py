"""Encrypt complete cold backups and restore only into a fresh stopped target.

Requires age on the operator host and a local Linux Docker engine. Plaintext
backup archives are never written. Database, Auth, Storage objects, gateway,
Vault/signing/data/session keys, configuration and source are captured together.
The age identity belongs outside the release and must be backed up separately.
"""
from __future__ import annotations
import argparse
import copy
from datetime import datetime,timezone
import hashlib
import json
import os
from pathlib import Path,PurePosixPath
import re
import subprocess
import sys
sys.dont_write_bytecode=True
import tarfile
import time
import uuid
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from scripts.self_hosted.release_operator import Operator
from scripts.self_hosted.configure import private_file,read_env
from scripts.self_hosted.prepare import dotenv,seal_configuration

def file_sha(path):
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        for data in iter(lambda:stream.read(1024*1024),b''):digest.update(data)
    return digest.hexdigest()
def fresh_absolute(path):
    if not path.is_absolute() or path.exists() or path.is_symlink() or path.parent.resolve(strict=True)!=path.parent:raise ValueError('Fresh absolute physical output required')
def write_private(path,value):
    with path.open('x') as out:os.chmod(path,0o600);json.dump(value,out,sort_keys=True,indent=2);out.write('\n')
def local_docker(docker):
    if os.environ.get('DOCKER_HOST') and not os.environ['DOCKER_HOST'].startswith('unix://'):raise ValueError('Remote Docker refused')
    result=subprocess.run([docker,'context','inspect','--format','{{json .Endpoints.docker.Host}}'],capture_output=True,check=True,timeout=15)
    if not json.loads(result.stdout).startswith('unix://'):raise ValueError('Local Unix Docker context required')

def backup(op,output,recipient):
    fresh_absolute(output);fresh_absolute(Path(str(output)+'.json'))
    if output.is_relative_to(op.root) or not re.fullmatch(r'age1[0-9a-z]{50,90}',recipient):raise ValueError('External output and age X25519 recipient required')
    config=op.docker_preflight()
    # Drain/lifecycle proofs are retained in the database. This command never
    # invents a provider outcome to make a backup look settled.
    op.sql("SELECT private.collect_assert_deployment('"+op.meta['profile_sha256']+"');DO $$DECLARE s jsonb;BEGIN SELECT private.collect_fence_owner_status_v3() INTO s;IF s->>'mode'<>'fenced' OR (s->'schedulerStatus'->>'blocking')::boolean IS DISTINCT FROM false OR s->>'localLeaseDrainComplete' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'committed_fenced_controller_and_inactive_scheduler_required';END IF;END$$;")
    started=time.monotonic();op.compose('stop','--timeout','45',timeout=60)
    running=op.compose('ps','--status','running','--quiet').decode().strip()
    if running:raise ValueError('All services must be stopped for a consistent complete backup')
    helper=config['services']['web']['image'];partial=output.with_name(output.name+'.partial-'+uuid.uuid4().hex)
    # Reject outside links and special files rather than silently omitting
    # tablespaces, sockets or an external object-store mount from recovery.
    scan="""const fs=require('node:fs'),path=require('node:path');let files=0,bytes=0;function walk(p){for(const n of fs.readdirSync(p)){const q=path.join(p,n),s=fs.lstatSync(q);if(s.isSymbolicLink()||!s.isDirectory()&&!s.isFile()||s.mode&0o6000)throw Error('unsupported_backup_entry');if(s.isDirectory())walk(q);else{files++;bytes+=s.size;if(files>2000000||bytes>500*1024**3)throw Error('backup_budget_exceeded');}}}walk('/backup');process.stdout.write(JSON.stringify({files,bytes}));"""
    op.run([op.docker,'run','--rm','--network','none','--read-only','--cap-drop','ALL','--cap-add','DAC_READ_SEARCH',
        '--mount','type=bind,src='+str(op.root)+',dst=/backup,readonly','--entrypoint','node',helper,'-e',scan],timeout=60)
    log=op.root/'private'/('backup-'+uuid.uuid4().hex+'.log')
    with log.open('xb') as diagnostic,partial.open('xb') as target:
        os.chmod(log,0o600);os.chmod(partial,0o600)
        producer=subprocess.Popen([op.docker,'run','--rm','--network','none','--read-only','--cap-drop','ALL','--cap-add','DAC_READ_SEARCH',
            '--mount','type=bind,src='+str(op.root)+',dst=/backup,readonly','--entrypoint','tar',helper,'--create','--numeric-owner','--file=-','--directory=/backup','.'],stdout=subprocess.PIPE,stderr=diagnostic)
        try:
            encryptor=subprocess.Popen(['age','--encrypt','--recipient',recipient],stdin=producer.stdout,stdout=target,stderr=diagnostic)
            producer.stdout.close();encrypted=encryptor.wait();produced=producer.wait()
            if encrypted or produced:raise RuntimeError('Encrypted cold backup unconfirmed; preserve the private diagnostic and partial file')
            target.flush();os.fsync(target.fileno())
        finally:
            if producer.poll() is None:producer.terminate();producer.wait(timeout=10)
    partial.replace(output)
    receipt={'format':'collect.selfhost.cold-backup.v1','profile':op.profile,'profile_sha256':op.meta['profile_sha256'],
        'source_sha256':op.meta['source_sha256'],'images_sha256':file_sha(op.root/'images.lock.json'),'helper_image':helper,
        'ciphertext_sha256':file_sha(output),'ciphertext_bytes':output.stat().st_size,'recipient_sha256':hashlib.sha256(recipient.encode()).hexdigest(),
        'created_at':datetime.now(timezone.utc).isoformat(),'elapsed_seconds':round(time.monotonic()-started,3),
        'all_services_stopped':True,'controller_fenced':True,'external_effects_reconciled':False,
        'scope':['database_all_schemas','auth_and_jwt_keys','storage_metadata_and_files','sms_gateway','vault_and_secrets','data_and_session_keys','configuration','source','frontend_artifacts'],
        'restore_tested':False,'services_restarted':False}
    write_private(Path(str(output)+'.json'),receipt)
    return {'backup_created':True,'ciphertext_sha256':receipt['ciphertext_sha256'],'bytes':receipt['ciphertext_bytes'],'services_stopped':True,'restore_tested':False}

def safe_member(member,seen,total,max_bytes,max_files,uid,gid):
    name=member.name
    if len(name)>2048 or '\\' in name or '\0' in name or name.startswith('/') or '..' in PurePosixPath(name).parts:raise ValueError('Unsafe archive path')
    parts=[p for p in PurePosixPath(name).parts if p not in ('','.')] ;normalized='/'.join(parts) or '.'
    if normalized in seen or len(seen)>=max_files:raise ValueError('Duplicate or excessive archive entries')
    if not(member.isdir() or member.isfile()) or member.issparse() or member.mode&0o6000 or member.size<0 or total+member.size>max_bytes:raise ValueError('Only bounded ordinary files and directories may be restored')
    seen.add(normalized);item=copy.copy(member);item.name=normalized;item.pax_headers={};item.uname='';item.gname=''
    # Preserve service data ownership. Operator-owned source/configuration must
    # belong to the restoring operator even if the host UID changed.
    service_owned=normalized=='data' or normalized.startswith('data/') or normalized=='private/db-tls' or normalized.startswith('private/db-tls/')
    if not service_owned:item.uid=uid;item.gid=gid
    return item,total+member.size

def restore(archive,receipt_path,identity,destination,*,docker='docker',max_bytes=500*1024**3,max_files=2_000_000):
    fresh_absolute(destination);private_file(identity);local_docker(docker)
    if identity.is_relative_to(destination):raise ValueError('Recovery identity must be independent of the release')
    receipt=json.loads(receipt_path.read_text())
    if receipt.get('format')!='collect.selfhost.cold-backup.v1' or receipt.get('all_services_stopped') is not True or receipt.get('controller_fenced') is not True or file_sha(archive)!=receipt.get('ciphertext_sha256') or archive.stat().st_size!=receipt.get('ciphertext_bytes'):raise ValueError('Exact complete cold backup receipt required')
    helper=receipt.get('helper_image','')
    local_images=json.loads((ROOT/'deploy/self-hosted/images.lock.json').read_text())
    if helper!=local_images['services']['web']['reference']:raise ValueError('Reviewed immutable restore helper required')
    project='collect-'+receipt['profile']['id']
    existing=subprocess.run([docker,'ps','-aq','--filter','label=com.docker.compose.project='+project],capture_output=True,check=True,timeout=15).stdout.strip()
    if existing:raise ValueError('Restore requires an independent target without this deployment project')
    destination.mkdir(mode=0o700);log=destination.parent/(destination.name+'.restore-'+uuid.uuid4().hex+'.log');started=time.monotonic()
    seen=set();total=0
    with log.open('xb') as diagnostic:
        os.chmod(log,0o600)
        decryptor=subprocess.Popen(['age','--decrypt','--identity',str(identity),str(archive)],stdout=subprocess.PIPE,stderr=diagnostic)
        consumer=subprocess.Popen([docker,'run','--rm','--network','none','--read-only','--cap-drop','ALL','--cap-add','CHOWN','--cap-add','FOWNER','--cap-add','DAC_OVERRIDE',
            '--mount','type=bind,src='+str(destination)+',dst=/restore','--entrypoint','tar',helper,'--extract','--numeric-owner','--same-owner','--file=-','--directory=/restore'],stdin=subprocess.PIPE,stderr=diagnostic)
        try:
            with tarfile.open(fileobj=decryptor.stdout,mode='r|') as source,tarfile.open(fileobj=consumer.stdin,mode='w|',format=tarfile.PAX_FORMAT) as target:
                for member in source:
                    item,total=safe_member(member,seen,total,max_bytes,max_files,os.getuid(),os.getgid())
                    target.addfile(item,source.extractfile(member) if item.isfile() else None)
            consumer.stdin.close();decryptor.stdout.close()
            if consumer.wait() or decryptor.wait():raise RuntimeError('Restore unconfirmed; fresh target remains stopped and quarantined')
        finally:
            for process in (consumer,decryptor):
                if process.poll() is None:process.terminate();process.wait(timeout=10)
    op=Operator(destination)
    if op.meta['source_sha256']!=receipt['source_sha256'] or op.meta['profile_sha256']!=receipt['profile_sha256'] or file_sha(destination/'images.lock.json')!=receipt['images_sha256']:raise ValueError('Restored release identity changed')
    # Only the physical root label changes. Database, secrets, source, hosts,
    # application identity and all unresolved obligations remain byte-identical.
    stack=read_env(destination/'private/stack.env');stack['COLLECT_RELEASE_ROOT']=str(destination)
    path=destination/'private/stack.env';temp=path.with_suffix('.restore-next')
    with temp.open('x') as out:os.chmod(temp,0o600);out.write(dotenv(stack))
    temp.replace(path)
    seal_configuration(destination)
    result={'format':'collect.selfhost.restore.v1','source_sha256':receipt['source_sha256'],'profile_sha256':receipt['profile_sha256'],
        'ciphertext_sha256':receipt['ciphertext_sha256'],'restored_files':len(seen),'restored_bytes':total,
        'elapsed_seconds':round(time.monotonic()-started,3),'status':'restored_not_started','provider_activation':False,'production_acceptance':False}
    write_private(destination/'restore-receipt.json',result)
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='action',required=True)
    b=sub.add_parser('backup');b.add_argument('--release',type=Path,required=True);b.add_argument('--output',type=Path,required=True);b.add_argument('--recipient',required=True);b.add_argument('--apply',action='store_true')
    r=sub.add_parser('restore');r.add_argument('--archive',type=Path,required=True);r.add_argument('--receipt',type=Path,required=True);r.add_argument('--identity',type=Path,required=True);r.add_argument('--destination',type=Path,required=True);r.add_argument('--apply',action='store_true')
    a=p.parse_args()
    try:
        if not a.apply:result={'action':a.action,'planned':True,'applied':False,'services_started':False}
        elif a.action=='backup':result=backup(Operator(a.release),a.output,a.recipient)
        else:result=restore(a.archive,a.receipt,a.identity,a.destination)
        print(json.dumps(result,sort_keys=True))
    except (OSError,ValueError,KeyError,RuntimeError,subprocess.SubprocessError,tarfile.TarError) as error:
        print(json.dumps({'status':'refused_or_unconfirmed','error_class':type(error).__name__,'private_values_disclosed':False,'automatic_restart':False}),file=sys.stderr);sys.exit(1)

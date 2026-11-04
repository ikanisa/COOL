"""Encrypt complete cold backups and restore only into a fresh stopped target.

Requires age on the operator host and a local Linux Docker engine. Plaintext
backup archives are never written. Database, Auth, Storage objects, gateway,
Vault/signing/data/session keys, configuration and source are captured together.
The age identity belongs outside the release and must be backed up separately.
"""
from __future__ import annotations
import argparse
import copy
from contextlib import contextmanager,suppress
from datetime import datetime,timezone
import hashlib
import json
import os
from pathlib import Path,PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
sys.dont_write_bytecode=True
import tarfile
import tempfile
import time
import uuid
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from scripts.self_hosted.release_operator import Operator
from scripts.self_hosted.configure import private_file,read_env
from scripts.self_hosted.prepare import dotenv,seal_configuration

# This limits only the host age/Docker CLI wait after starting the pipeline.
# Slower installations may select an explicitly reviewed value up to 7 days.
DEFAULT_BACKUP_PIPELINE_TIMEOUT_SECONDS=24*60*60
MAX_BACKUP_PIPELINE_TIMEOUT_SECONDS=7*24*60*60

def file_sha(path):
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        for data in iter(lambda:stream.read(1024*1024),b''):digest.update(data)
    return digest.hexdigest()
def stream_sha(stream):
    """Hash an opened archive, then rewind it for decryption."""
    stream.seek(0)
    digest=hashlib.sha256()
    for data in iter(lambda:stream.read(1024*1024),b''):digest.update(data)
    stream.seek(0)
    return digest.hexdigest()

@contextmanager
def verified_ciphertext_snapshot(source,receipt,parent):
    """Copy the exact receipted ciphertext to an anonymous private file.

    The temporary file contains ciphertext only and is opened on the restore
    destination filesystem. Concurrent exhaustion can still abort the copy;
    the original archive is never modified. Same-UID or privileged access to
    this process and its file descriptors remains a trusted-host boundary.
    Directory ACLs and the security of ancestor directories must also be
    controlled by the operator; POSIX mode checks cannot establish these.
    """
    expected_size=receipt.get('ciphertext_bytes');expected_hash=receipt.get('ciphertext_sha256')
    if type(expected_size) is not int or expected_size<0 or not isinstance(expected_hash,str) or not re.fullmatch(r'[0-9a-f]{64}',expected_hash):
        raise ValueError('Exact complete cold backup receipt required')
    _require_private_restore_directory(parent)
    if shutil.disk_usage(parent).free<expected_size:raise ValueError('Insufficient space for verified ciphertext snapshot')
    with tempfile.TemporaryFile(mode='w+b',dir=parent,prefix='.collect-restore-') as snapshot:
        info=os.fstat(snapshot.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_nlink!=0 or info.st_uid!=os.geteuid() or stat.S_IMODE(info.st_mode)&0o077:
            raise ValueError('Private anonymous ciphertext snapshot unavailable')
        source.seek(0);remaining=expected_size;digest=hashlib.sha256()
        while remaining:
            chunk=source.read(min(1024*1024,remaining))
            if not chunk:raise ValueError('Archive changed during snapshot')
            if snapshot.write(chunk)!=len(chunk):raise OSError('Ciphertext snapshot write incomplete')
            digest.update(chunk);remaining-=len(chunk)
        if source.read(1) or digest.hexdigest()!=expected_hash:raise ValueError('Archive changed during snapshot')
        snapshot.flush();snapshot.seek(0)
        if stream_sha(snapshot)!=expected_hash:raise ValueError('Ciphertext snapshot verification failed')
        yield snapshot
def fresh_absolute(path):
    if not path.is_absolute() or path.exists() or path.is_symlink() or path.parent.resolve(strict=True)!=path.parent:raise ValueError('Fresh absolute physical output required')
def write_private(path,value,*,durable=False):
    descriptor=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(descriptor,'w') as out:
        identity=os.fstat(out.fileno());json.dump(value,out,sort_keys=True,indent=2);out.write('\n')
        out.flush()
        if not _same_regular_inode(path,identity):raise ValueError('Receipt publication identity changed')
        if durable:
            os.fsync(out.fileno());_fsync_directory(path.parent)
            if not _same_regular_inode(path,identity):raise ValueError('Receipt publication identity changed')
def _same_regular_inode(path,expected):
    observed=path.lstat()
    return stat.S_ISREG(observed.st_mode) and (observed.st_dev,observed.st_ino)==(expected.st_dev,expected.st_ino)
def _require_private_backup_directory(path):
    observed=path.lstat()
    if not stat.S_ISDIR(observed.st_mode) or observed.st_uid!=os.geteuid() or observed.st_mode&0o022:
        raise ValueError('Backup directory must be operator-owned and not group/world writable')
def _require_private_restore_directory(path):
    if not path.is_absolute() or path.resolve(strict=True)!=path:
        raise ValueError('Restore directory must be physical and absolute')
    observed=path.lstat()
    if not stat.S_ISDIR(observed.st_mode) or observed.st_uid!=os.geteuid() or observed.st_mode&0o022:
        raise ValueError('Restore directory must be operator-owned and not group/world writable')
def _fsync_directory(path):
    descriptor=os.open(path,os.O_RDONLY|getattr(os,'O_DIRECTORY',0))
    try:os.fsync(descriptor)
    finally:os.close(descriptor)
def _preflight_backup_publication(parent):
    """Prove safe publication before downtime; retain the owned probe as evidence."""
    probe=Path(tempfile.mkdtemp(prefix='.collect-backup-probe-',dir=parent))
    source=probe/'source';linked=probe/'linked'
    with source.open('xb') as staged:
        os.chmod(source,0o600);staged.write(b'probe');staged.flush();os.fsync(staged.fileno())
        expected=os.fstat(staged.fileno())
        os.link(source,linked,follow_symlinks=False)
        if not _same_regular_inode(source,expected) or not _same_regular_inode(linked,expected):raise ValueError('Backup capability probe identity changed')
        _fsync_directory(probe);_fsync_directory(parent)
        if not _same_regular_inode(source,expected) or not _same_regular_inode(linked,expected):raise ValueError('Backup capability probe identity changed')
    return probe.name
def promote_backup_no_replace(partial,output,staged_fd):
    """Publish the held inode atomically or leave the output unconfirmed.

    Hard-link support and directory fsync are required. No copy or ordinary
    rename fallback may expose a partial final name or replace an existing file.
    """
    expected=os.fstat(staged_fd)
    if not stat.S_ISREG(expected.st_mode) or not _same_regular_inode(partial,expected):raise ValueError('Staged backup identity changed')
    os.link(partial,output,follow_symlinks=False)
    if not _same_regular_inode(output,expected) or not _same_regular_inode(partial,expected):raise ValueError('Backup publication identity changed')
    descriptor=os.open(output,os.O_RDONLY|os.O_NOFOLLOW)
    try:
        actual=os.fstat(descriptor)
        if not stat.S_ISREG(actual.st_mode) or (actual.st_dev,actual.st_ino,actual.st_size,actual.st_mtime_ns)!=(expected.st_dev,expected.st_ino,expected.st_size,expected.st_mtime_ns):raise ValueError('Backup publication identity changed')
        digest=hashlib.sha256()
        with os.fdopen(descriptor,'rb',closefd=False) as stream:
            for data in iter(lambda:stream.read(1024*1024),b''):digest.update(data)
        final=os.fstat(descriptor)
        if (final.st_size,final.st_mtime_ns)!=(actual.st_size,actual.st_mtime_ns) or not _same_regular_inode(output,expected) or not _same_regular_inode(partial,expected):raise ValueError('Backup publication content changed')
        _fsync_directory(output.parent)
        if not _same_regular_inode(output,expected) or not _same_regular_inode(partial,expected):raise ValueError('Backup publication identity changed')
        # Retain the original hard-link name. A pathname check followed by an
        # unlink could otherwise remove a different actor's replacement.
        return digest.hexdigest(),final.st_size,expected
    finally:os.close(descriptor)
def local_docker(docker):
    if os.environ.get('DOCKER_HOST') and not os.environ['DOCKER_HOST'].startswith('unix://'):raise ValueError('Remote Docker refused')
    result=subprocess.run([docker,'context','inspect','--format','{{json .Endpoints.docker.Host}}'],capture_output=True,check=True,timeout=15)
    if not json.loads(result.stdout).startswith('unix://'):raise ValueError('Local Unix Docker context required')

def _cleanup_pipeline(*processes,operation='Backup'):
    """Stop and reap each spawned child, even when another cleanup fails.

    This bounds the graceful termination wait, not the running pipeline's
    overall duration. Surface cleanup failures instead of reporting success.
    """
    errors=[]
    for process in processes:
        if process is None:continue
        try:
            if process.poll() is None:
                with suppress(ProcessLookupError):process.terminate()
                try:process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    with suppress(ProcessLookupError):process.kill()
                    process.wait()
        except Exception as error:errors.append(error)
        finally:
            for pipe in (process.stdin,process.stdout,process.stderr):
                if pipe is not None:
                    try:pipe.close()
                    except (OSError,ValueError):pass
    if errors:raise RuntimeError(operation+' pipeline cleanup unconfirmed') from errors[0]

def backup(op,output,recipient,*,pipeline_timeout_seconds=DEFAULT_BACKUP_PIPELINE_TIMEOUT_SECONDS):
    if type(pipeline_timeout_seconds) is not int or not 1<=pipeline_timeout_seconds<=MAX_BACKUP_PIPELINE_TIMEOUT_SECONDS:
        raise ValueError('Backup pipeline timeout must be an integer between 1 and 604800 seconds')
    fresh_absolute(output);fresh_absolute(Path(str(output)+'.json'))
    _require_private_backup_directory(output.parent)
    if output.is_relative_to(op.root) or not re.fullmatch(r'age1[0-9a-z]{50,90}',recipient):raise ValueError('External output and age X25519 recipient required')
    config=op.docker_preflight()
    capability_probe=_preflight_backup_publication(output.parent)
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
        producer=encryptor=None
        try:
            deadline=time.monotonic()+pipeline_timeout_seconds
            producer=subprocess.Popen([op.docker,'run','--rm','--network','none','--read-only','--cap-drop','ALL','--cap-add','DAC_READ_SEARCH',
                '--mount','type=bind,src='+str(op.root)+',dst=/backup,readonly','--entrypoint','tar',helper,'--create','--numeric-owner','--file=-','--directory=/backup','.'],stdout=subprocess.PIPE,stderr=diagnostic)
            encryptor=subprocess.Popen(['age','--encrypt','--recipient',recipient],stdin=producer.stdout,stdout=target,stderr=diagnostic)
            producer.stdout.close()
            try:
                remaining=deadline-time.monotonic()
                if remaining<=0:raise subprocess.TimeoutExpired('backup pipeline',pipeline_timeout_seconds)
                encrypted=encryptor.wait(timeout=remaining)
                if encrypted:raise RuntimeError('Encrypted cold backup unconfirmed; preserve the private diagnostic and partial file')
                remaining=deadline-time.monotonic()
                if remaining<=0:raise subprocess.TimeoutExpired('backup pipeline',pipeline_timeout_seconds)
                produced=producer.wait(timeout=remaining)
            except subprocess.TimeoutExpired as error:
                raise RuntimeError('Encrypted cold backup timed out; preserve the private diagnostic and partial file') from error
            if produced:raise RuntimeError('Encrypted cold backup unconfirmed; preserve the private diagnostic and partial file')
            target.flush();os.fsync(target.fileno())
            ciphertext_sha256,ciphertext_bytes,ciphertext_identity=promote_backup_no_replace(partial,output,target.fileno())
        finally:
            _cleanup_pipeline(encryptor,producer)
    receipt={'format':'collect.selfhost.cold-backup.v1','profile':op.profile,'profile_sha256':op.meta['profile_sha256'],
        'source_sha256':op.meta['source_sha256'],'images_sha256':file_sha(op.root/'images.lock.json'),'helper_image':helper,
        'ciphertext_sha256':ciphertext_sha256,'ciphertext_bytes':ciphertext_bytes,'recipient_sha256':hashlib.sha256(recipient.encode()).hexdigest(),
        'created_at':datetime.now(timezone.utc).isoformat(),'elapsed_seconds':round(time.monotonic()-started,3),
        'all_services_stopped':True,'controller_fenced':True,'external_effects_reconciled':False,
        'scope':['database_all_schemas','auth_and_jwt_keys','storage_metadata_and_files','sms_gateway','vault_and_secrets','data_and_session_keys','configuration','source','frontend_artifacts'],
        'restore_tested':False,'services_restarted':False}
    if not _same_regular_inode(output,ciphertext_identity) or not _same_regular_inode(partial,ciphertext_identity):raise ValueError('Backup publication identity changed')
    write_private(Path(str(output)+'.json'),receipt,durable=True)
    return {'backup_created':True,'ciphertext_sha256':receipt['ciphertext_sha256'],'bytes':receipt['ciphertext_bytes'],'services_stopped':True,'restore_tested':False,'staged_hardlink_retained':partial.name,'capability_probe_retained':capability_probe}

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
    fresh_absolute(destination);_require_private_restore_directory(destination.parent);private_file(identity);local_docker(docker)
    if identity.is_relative_to(destination):raise ValueError('Recovery identity must be independent of the release')
    receipt=json.loads(receipt_path.read_text())
    if receipt.get('format')!='collect.selfhost.cold-backup.v1' or receipt.get('all_services_stopped') is not True or receipt.get('controller_fenced') is not True:raise ValueError('Exact complete cold backup receipt required')
    # Bind verification and decryption to one held, non-symlink file. Reopening
    # the pathname after verification permits a replacement to be decrypted.
    # A FIFO with no writer would otherwise block before fstat can reject it.
    descriptor=os.open(archive,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    with os.fdopen(descriptor,'rb') as archive_stream:
        opened=os.fstat(archive_stream.fileno())
        if not stat.S_ISREG(opened.st_mode) or opened.st_size!=receipt.get('ciphertext_bytes') or stream_sha(archive_stream)!=receipt.get('ciphertext_sha256'):raise ValueError('Exact complete cold backup receipt required')
        with verified_ciphertext_snapshot(archive_stream,receipt,destination.parent) as snapshot:
            return _restore_verified_archive(snapshot,receipt,identity,destination,docker=docker,max_bytes=max_bytes,max_files=max_files,source_stream=archive_stream)

def _restore_verified_archive(archive_stream,receipt,identity,destination,*,docker,max_bytes,max_files,source_stream=None):
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
        decryptor=consumer=None
        try:
            decryptor=subprocess.Popen(['age','--decrypt','--identity',str(identity)],stdin=archive_stream,stdout=subprocess.PIPE,stderr=diagnostic)
            consumer=subprocess.Popen([docker,'run','--rm','--interactive','--network','none','--read-only','--cap-drop','ALL','--cap-add','CHOWN','--cap-add','FOWNER','--cap-add','DAC_OVERRIDE',
                '--mount','type=bind,src='+str(destination)+',dst=/restore','--entrypoint','tar',helper,'--extract','--numeric-owner','--same-owner','--file=-','--directory=/restore'],stdin=subprocess.PIPE,stderr=diagnostic)
            with tarfile.open(fileobj=decryptor.stdout,mode='r|') as source,tarfile.open(fileobj=consumer.stdin,mode='w|',format=tarfile.PAX_FORMAT) as target:
                for member in source:
                    item,total=safe_member(member,seen,total,max_bytes,max_files,os.getuid(),os.getgid())
                    target.addfile(item,source.extractfile(member) if item.isfile() else None)
            consumer.stdin.close();decryptor.stdout.close()
            if consumer.wait() or decryptor.wait():raise RuntimeError('Restore unconfirmed; fresh target remains stopped and quarantined')
            # The decryptor read only the receipted private snapshot. A later
            # persistent change to the source is also reported as unconfirmed.
            after=os.fstat(archive_stream.fileno())
            if after.st_size!=receipt['ciphertext_bytes'] or stream_sha(archive_stream)!=receipt['ciphertext_sha256']:raise ValueError('Archive changed during restore')
            if source_stream is not None:
                after_source=os.fstat(source_stream.fileno())
                if after_source.st_size!=receipt['ciphertext_bytes'] or stream_sha(source_stream)!=receipt['ciphertext_sha256']:raise ValueError('Archive changed during restore')
        finally:
            _cleanup_pipeline(consumer,decryptor,operation='Restore')
    op=Operator(destination)
    if op.meta['source_sha256']!=receipt['source_sha256'] or op.meta['profile_sha256']!=receipt['profile_sha256'] or file_sha(destination/'images.lock.json')!=receipt['images_sha256']:raise ValueError('Restored release identity changed')
    # Only the physical root label changes. Database, secrets, source, hosts,
    # application identity and all unresolved obligations remain byte-identical.
    stack=read_env(destination/'private/stack.env');stack['COLLECT_RELEASE_ROOT']=str(destination)
    content=dotenv(stack)
    path=destination/'private/stack.env';temp=path.with_suffix('.restore-next')
    with temp.open('x',encoding='utf8') as out:os.chmod(temp,0o600);out.write(content)
    temp.replace(path)
    seal_configuration(destination)
    result={'format':'collect.selfhost.restore.v1','source_sha256':receipt['source_sha256'],'profile_sha256':receipt['profile_sha256'],
        'ciphertext_sha256':receipt['ciphertext_sha256'],'restored_files':len(seen),'restored_bytes':total,
        'elapsed_seconds':round(time.monotonic()-started,3),'status':'restored_not_started','provider_activation':False,'production_acceptance':False}
    write_private(destination/'restore-receipt.json',result)
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='action',required=True)
    b=sub.add_parser('backup');b.add_argument('--release',type=Path,required=True);b.add_argument('--output',type=Path,required=True);b.add_argument('--recipient',required=True);b.add_argument('--pipeline-timeout-seconds',type=int,default=DEFAULT_BACKUP_PIPELINE_TIMEOUT_SECONDS);b.add_argument('--apply',action='store_true')
    r=sub.add_parser('restore');r.add_argument('--archive',type=Path,required=True);r.add_argument('--receipt',type=Path,required=True);r.add_argument('--identity',type=Path,required=True);r.add_argument('--destination',type=Path,required=True);r.add_argument('--apply',action='store_true')
    a=p.parse_args()
    try:
        if a.action=='backup' and not 1<=a.pipeline_timeout_seconds<=MAX_BACKUP_PIPELINE_TIMEOUT_SECONDS:raise ValueError('Invalid backup pipeline timeout')
        if not a.apply:result={'action':a.action,'planned':True,'applied':False,'services_started':False}
        elif a.action=='backup':result=backup(Operator(a.release),a.output,a.recipient,pipeline_timeout_seconds=a.pipeline_timeout_seconds)
        else:result=restore(a.archive,a.receipt,a.identity,a.destination)
        print(json.dumps(result,sort_keys=True))
    except (OSError,ValueError,KeyError,RuntimeError,subprocess.SubprocessError,tarfile.TarError) as error:
        print(json.dumps({'status':'refused_or_unconfirmed','error_class':type(error).__name__,'private_values_disclosed':False,'automatic_restart':False}),file=sys.stderr);sys.exit(1)

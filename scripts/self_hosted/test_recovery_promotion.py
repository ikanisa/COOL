"""Publication must bind the held ciphertext inode without overwriting files."""
import errno
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from scripts.self_hosted.recovery import _cleanup_pipeline,_require_private_backup_directory,_restore_verified_archive,backup,promote_backup_no_replace,restore,verified_ciphertext_snapshot,write_private


class BackupPromotionTests(unittest.TestCase):
    def test_snapshot_remains_bound_when_source_changes_and_is_restored(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory).resolve();archive=base/'archive';original=b'original ciphertext';archive.write_bytes(original)
            receipt={'ciphertext_bytes':len(original),'ciphertext_sha256':hashlib.sha256(original).hexdigest()}
            with archive.open('rb') as source,verified_ciphertext_snapshot(source,receipt,base) as snapshot:
                info=os.fstat(snapshot.fileno())
                self.assertEqual((info.st_nlink,info.st_uid,info.st_mode&0o077),(0,os.geteuid(),0))
                archive.write_bytes(b'modified ciphertext')
                self.assertEqual(snapshot.read(),original)
                archive.write_bytes(original)
                snapshot.seek(0);self.assertEqual(snapshot.read(),original)
            self.assertEqual(list(base.iterdir()),[archive])

    def test_restore_refuses_shared_parent_before_docker_or_target(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory).resolve();parent=base/'shared';parent.mkdir()
            for mode in (0o770,0o707):
                parent.chmod(mode)
                with patch('scripts.self_hosted.recovery.local_docker') as docker:
                    with self.assertRaisesRegex(ValueError,'operator-owned and not group/world writable'):
                        restore(base/'archive',base/'receipt',base/'identity',parent/'destination')
                    docker.assert_not_called()
                self.assertEqual(list(parent.iterdir()),[])

    def test_snapshot_refuses_symlink_parent_before_creation(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory).resolve();real=base/'real';real.mkdir();link=base/'link';link.symlink_to(real,target_is_directory=True)
            archive=base/'archive';archive.write_bytes(b'ciphertext')
            receipt={'ciphertext_bytes':10,'ciphertext_sha256':hashlib.sha256(b'ciphertext').hexdigest()}
            with archive.open('rb') as source,patch('scripts.self_hosted.recovery.tempfile.TemporaryFile') as create:
                with self.assertRaisesRegex(ValueError,'physical and absolute'):
                    with verified_ciphertext_snapshot(source,receipt,link):self.fail('must not yield')
                create.assert_not_called()
            self.assertEqual(list(real.iterdir()),[])

    def test_snapshot_rejects_nonprivate_file_and_closes_it(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory).resolve();archive=base/'archive';archive.write_bytes(b'ciphertext')
            receipt={'ciphertext_bytes':10,'ciphertext_sha256':hashlib.sha256(b'ciphertext').hexdigest()}
            temporary=tempfile.TemporaryFile(mode='w+b',dir=base);os.fchmod(temporary.fileno(),0o640)
            with archive.open('rb') as source,patch('scripts.self_hosted.recovery.tempfile.TemporaryFile',return_value=temporary):
                with self.assertRaisesRegex(ValueError,'Private anonymous ciphertext snapshot unavailable'):
                    with verified_ciphertext_snapshot(source,receipt,base):self.fail('must not yield')
            self.assertTrue(temporary.closed)
            self.assertEqual(list(base.iterdir()),[archive])

    def test_snapshot_rejects_foreign_owner_and_closes_it(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory).resolve();archive=base/'archive';archive.write_bytes(b'ciphertext')
            receipt={'ciphertext_bytes':10,'ciphertext_sha256':hashlib.sha256(b'ciphertext').hexdigest()}
            temporary=tempfile.TemporaryFile(mode='w+b',dir=base)
            info=os.fstat(temporary.fileno());fields=list(info);fields[4]=os.geteuid()+1;foreign=os.stat_result(fields)
            with archive.open('rb') as source,patch('scripts.self_hosted.recovery.tempfile.TemporaryFile',return_value=temporary),patch('scripts.self_hosted.recovery.os.fstat',return_value=foreign):
                with self.assertRaisesRegex(ValueError,'Private anonymous ciphertext snapshot unavailable'):
                    with verified_ciphertext_snapshot(source,receipt,base):self.fail('must not yield')
            self.assertTrue(temporary.closed)
            self.assertEqual(list(base.iterdir()),[archive])

    def test_transient_change_during_copy_is_refused_even_if_source_restored(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory).resolve();archive=base/'archive';original=b'original ciphertext';archive.write_bytes(original)
            receipt={'ciphertext_bytes':len(original),'ciphertext_sha256':hashlib.sha256(original).hexdigest()}
            with archive.open('rb') as source:
                real_read=source.read;first=True
                def mutate_then_restore(size=-1):
                    nonlocal first
                    if not first:return real_read(size)
                    first=False
                    archive.write_bytes(b'X'+original[1:])
                    result=real_read(size)
                    archive.write_bytes(original)
                    return result
                with patch.object(source,'read',side_effect=mutate_then_restore):
                    with self.assertRaisesRegex(ValueError,'Archive changed during snapshot'):
                        with verified_ciphertext_snapshot(source,receipt,base):self.fail('must not yield unverified snapshot')
            self.assertEqual(archive.read_bytes(),original)
            self.assertEqual(list(base.iterdir()),[archive])

    def test_insufficient_snapshot_space_refuses_without_modifying_source(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory).resolve();archive=base/'archive';archive.write_bytes(b'ciphertext')
            receipt={'ciphertext_bytes':10,'ciphertext_sha256':hashlib.sha256(b'ciphertext').hexdigest()}
            with archive.open('rb') as source,patch('scripts.self_hosted.recovery.shutil.disk_usage',return_value=SimpleNamespace(free=9)):
                with self.assertRaisesRegex(ValueError,'Insufficient space'):
                    with verified_ciphertext_snapshot(source,receipt,base):self.fail('must not yield a snapshot')
            self.assertEqual(archive.read_bytes(),b'ciphertext')
            self.assertEqual(list(base.iterdir()),[archive])

    def test_restore_rejects_fifo_without_blocking(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory).resolve();archive=base/'archive';os.mkfifo(archive)
            identity=base/'identity';identity.write_text('synthetic');identity.chmod(0o600)
            receipt=base/'receipt.json';receipt.write_text(json.dumps({'format':'collect.selfhost.cold-backup.v1','all_services_stopped':True,'controller_fenced':True}))
            real_open=os.open
            def checked_open(path,flags,*args,**kwargs):
                if path==archive:self.assertTrue(flags&os.O_NONBLOCK)
                return real_open(path,flags,*args,**kwargs)
            with patch('scripts.self_hosted.recovery.local_docker'),patch('scripts.self_hosted.recovery.os.open',side_effect=checked_open):
                with self.assertRaisesRegex(ValueError,'Exact complete cold backup receipt required'):
                    restore(archive,receipt,identity,base/'destination')
            self.assertFalse((base/'destination').exists())

    def test_consumer_spawn_failure_reaps_decryptor_and_closes_pipe(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory).resolve();archive=base/'archive';archive.write_bytes(b'synthetic')
            lock=json.loads((Path(__file__).resolve().parents[2]/'deploy/self-hosted/images.lock.json').read_text())
            receipt={'helper_image':lock['services']['web']['reference'],'profile':{'id':'synthetic'}}
            original_popen=subprocess.Popen;started=[]
            def fail_consumer(args,**kwargs):
                if args[0]=='age':
                    proc=original_popen([sys.executable,'-c','import time; time.sleep(60)'],stdin=kwargs['stdin'],stdout=kwargs['stdout'],stderr=kwargs['stderr'])
                    started.append(proc);return proc
                raise OSError('synthetic consumer spawn failure')
            with archive.open('rb') as stream,patch('scripts.self_hosted.recovery.subprocess.run') as run,patch('scripts.self_hosted.recovery.subprocess.Popen',side_effect=fail_consumer):
                run.return_value.stdout=b''
                with self.assertRaisesRegex(OSError,'synthetic consumer spawn failure'):
                    _restore_verified_archive(stream,receipt,base/'identity',base/'destination',docker='synthetic-docker',max_bytes=1024,max_files=10)
            self.assertEqual(len(started),1)
            self.assertIsNotNone(started[0].poll())
            self.assertTrue(started[0].stdout.closed)
            self.assertFalse((base/'destination'/'restore-receipt.json').exists())

    def test_restore_cleanup_failure_still_reaps_other_child_and_keeps_error_context(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory).resolve();archive=base/'archive';archive.write_bytes(b'synthetic')
            lock=json.loads((Path(__file__).resolve().parents[2]/'deploy/self-hosted/images.lock.json').read_text())
            receipt={'helper_image':lock['services']['web']['reference'],'profile':{'id':'synthetic'}}
            original_popen=subprocess.Popen;started=[];terminate_patch=None
            def synthetic_child(args,**kwargs):
                nonlocal terminate_patch
                self.assertIn(args[0],('age','synthetic-docker'))
                proc=original_popen([sys.executable,'-c','import time; time.sleep(60)'],stdin=kwargs.get('stdin'),stdout=kwargs.get('stdout'),stderr=kwargs.get('stderr'))
                started.append(proc)
                if args[0]=='synthetic-docker':
                    terminate_patch=patch.object(proc,'terminate',side_effect=OSError('synthetic first cleanup failure'));terminate_patch.start()
                return proc
            try:
                with archive.open('rb') as stream,patch('scripts.self_hosted.recovery.subprocess.run') as run,patch('scripts.self_hosted.recovery.subprocess.Popen',side_effect=synthetic_child),patch('scripts.self_hosted.recovery.tarfile.open',side_effect=ValueError('synthetic tar failure')):
                    run.return_value.stdout=b''
                    with self.assertRaisesRegex(RuntimeError,'Restore pipeline cleanup unconfirmed') as captured:
                        _restore_verified_archive(stream,receipt,base/'identity',base/'destination',docker='synthetic-docker',max_bytes=1024,max_files=10)
                self.assertEqual(len(started),2)
                self.assertIsInstance(captured.exception.__cause__,OSError)
                self.assertIsInstance(captured.exception.__cause__.__context__,ValueError)
                self.assertEqual(str(captured.exception.__cause__.__context__),'synthetic tar failure')
                self.assertIsNotNone(started[0].poll(),'decryptor must be reaped despite consumer cleanup failure')
                self.assertIsNone(started[1].poll(),'consumer cleanup is unconfirmed until the fixture reaps it')
                self.assertTrue(started[0].stdout.closed)
                self.assertTrue((base/'destination').is_dir())
                self.assertEqual(len(list(base.glob('destination.restore-*.log'))),1)
                self.assertFalse((base/'destination'/'restore-receipt.json').exists())
            finally:
                if terminate_patch is not None:terminate_patch.stop()
                for proc in started:
                    if proc.poll() is None:proc.kill()
                    proc.wait(timeout=5)
                    for pipe in (proc.stdin,proc.stdout,proc.stderr):
                        if pipe is not None and not pipe.closed:pipe.close()

    def test_success_returns_digest_of_the_held_ciphertext(self):
        with tempfile.TemporaryDirectory() as directory:
            partial=Path(directory).resolve()/'backup.partial';output=Path(directory).resolve()/'backup.age'
            partial.write_bytes(b'encrypted backup')
            with partial.open('rb') as source:
                digest,size,_=promote_backup_no_replace(partial,output,source.fileno())
            self.assertEqual((digest,size),(hashlib.sha256(b'encrypted backup').hexdigest(),16))
            self.assertEqual(output.read_bytes(),b'encrypted backup')
            self.assertTrue(partial.exists())
            self.assertEqual(partial.stat().st_ino,output.stat().st_ino)

    def test_group_writable_destination_is_refused_before_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            output_dir=Path(directory).resolve()/'shared';output_dir.mkdir(mode=0o700)
            _require_private_backup_directory(output_dir)
            output_dir.chmod(0o770)
            with self.assertRaises(ValueError):_require_private_backup_directory(output_dir)

    def test_backup_receipt_requests_durability_without_changing_restore_default(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory).resolve()
            with patch('scripts.self_hosted.recovery._fsync_directory') as sync:
                write_private(root/'restore.json',{'kind':'restore'})
                sync.assert_not_called()
                write_private(root/'backup.json',{'kind':'backup'},durable=True)
                sync.assert_called_once_with(root)
            self.assertEqual((root/'backup.json').stat().st_mode&0o777,0o600)

    def test_stage_is_not_unlinked_after_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            partial=Path(directory).resolve()/'backup.partial';output=Path(directory).resolve()/'backup.age'
            partial.write_bytes(b'encrypted backup')
            with partial.open('rb') as source,patch.object(Path,'unlink',side_effect=AssertionError('must not unlink')):
                promote_backup_no_replace(partial,output,source.fileno())
            self.assertEqual(partial.read_bytes(),b'encrypted backup')

    def test_destination_created_after_preflight_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            partial=Path(directory).resolve()/'backup.partial';output=Path(directory).resolve()/'backup.age'
            partial.write_bytes(b'encrypted backup');output.write_bytes(b'another owner\'s file')
            with partial.open('rb') as source:
                with self.assertRaises(FileExistsError):promote_backup_no_replace(partial,output,source.fileno())
            self.assertEqual(output.read_bytes(),b'another owner\'s file')
            self.assertEqual(partial.read_bytes(),b'encrypted backup')

    def test_existing_destination_symlink_is_not_followed(self):
        with tempfile.TemporaryDirectory() as directory:
            partial=Path(directory).resolve()/'backup.partial';output=Path(directory).resolve()/'backup.age';other=Path(directory).resolve()/'other'
            partial.write_bytes(b'encrypted backup');other.write_bytes(b'unrelated');output.symlink_to(other)
            with partial.open('rb') as source:
                with self.assertRaises(FileExistsError):promote_backup_no_replace(partial,output,source.fileno())
            self.assertEqual(other.read_bytes(),b'unrelated')
            self.assertEqual(partial.read_bytes(),b'encrypted backup')

    def test_no_atomic_link_support_fails_without_publishing(self):
        with tempfile.TemporaryDirectory() as directory:
            partial=Path(directory).resolve()/'backup.partial';output=Path(directory).resolve()/'backup.age'
            partial.write_bytes(b'encrypted backup')
            with partial.open('rb') as source,patch('scripts.self_hosted.recovery.os.link',side_effect=OSError(errno.EOPNOTSUPP,'unsupported')):
                with self.assertRaises(OSError):promote_backup_no_replace(partial,output,source.fileno())
            self.assertEqual(partial.read_bytes(),b'encrypted backup')
            self.assertFalse(output.exists())

    def test_source_replaced_by_symlink_before_link_is_not_receipted(self):
        with tempfile.TemporaryDirectory() as directory:
            partial=Path(directory).resolve()/'backup.partial';output=Path(directory).resolve()/'backup.age';other=Path(directory).resolve()/'other'
            partial.write_bytes(b'encrypted backup');other.write_bytes(b'unrelated')
            real_link=os.link
            def change_source(src,dst,**kwargs):
                partial.unlink();partial.symlink_to(other);real_link(src,dst,**kwargs)
            with partial.open('rb') as source,patch('scripts.self_hosted.recovery.os.link',side_effect=change_source):
                with self.assertRaises(ValueError):promote_backup_no_replace(partial,output,source.fileno())
            self.assertEqual(other.read_bytes(),b'unrelated')
            self.assertFalse(Path(str(output)+'.json').exists())

    def test_source_replaced_by_other_inode_before_link_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            partial=Path(directory).resolve()/'backup.partial';output=Path(directory).resolve()/'backup.age';real_link=os.link
            partial.write_bytes(b'encrypted backup')
            def change_source(src,dst,**kwargs):
                partial.unlink();partial.write_bytes(b'unrelated');real_link(src,dst,**kwargs)
            with partial.open('rb') as source,patch('scripts.self_hosted.recovery.os.link',side_effect=change_source):
                with self.assertRaises(ValueError):promote_backup_no_replace(partial,output,source.fileno())
            self.assertEqual(partial.read_bytes(),b'unrelated')
            self.assertFalse(Path(str(output)+'.json').exists())

    def test_output_replaced_after_link_preserves_partial_and_other_file(self):
        with tempfile.TemporaryDirectory() as directory:
            partial=Path(directory).resolve()/'backup.partial';output=Path(directory).resolve()/'backup.age'
            partial.write_bytes(b'encrypted backup');real_link=os.link
            def change_output(src,dst,**kwargs):
                real_link(src,dst,**kwargs);output.unlink();output.write_bytes(b'unrelated')
            with partial.open('rb') as source,patch('scripts.self_hosted.recovery.os.link',side_effect=change_output):
                with self.assertRaises(ValueError):promote_backup_no_replace(partial,output,source.fileno())
            self.assertEqual(partial.read_bytes(),b'encrypted backup')
            self.assertEqual(output.read_bytes(),b'unrelated')
            self.assertFalse(Path(str(output)+'.json').exists())

    def test_directory_fsync_failure_retains_the_partial(self):
        with tempfile.TemporaryDirectory() as directory:
            partial=Path(directory).resolve()/'backup.partial';output=Path(directory).resolve()/'backup.age'
            partial.write_bytes(b'encrypted backup')
            with partial.open('rb') as source,patch('scripts.self_hosted.recovery._fsync_directory',side_effect=OSError(errno.EIO,'sync failed')):
                with self.assertRaises(OSError):promote_backup_no_replace(partial,output,source.fileno())
            self.assertEqual(partial.read_bytes(),b'encrypted backup')
            self.assertFalse(Path(str(output)+'.json').exists())

    def test_backup_pipeline_preserves_new_destination_and_never_receipts_it(self):
        # Controlled helpers only: no Docker service, real key or production data.
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory).resolve();release=base/'release';release.mkdir();(release/'private').mkdir()
            (release/'images.lock.json').write_text('{}')
            bindir=base/'bin';bindir.mkdir();docker=bindir/'synthetic-docker';age=bindir/'age'
            docker.write_text('#!/bin/sh\nprintf synthetic-archive\n');docker.chmod(0o700)
            age.write_text('#!/bin/sh\ncat\n');age.chmod(0o700)
            class SyntheticOperator:
                root=release
                profile={'id':'synthetic'}
                meta={'profile_sha256':'a'*64,'source_sha256':'b'*64}
                def __init__(self):self.docker=str(docker)
                def docker_preflight(self):return {'services':{'web':{'image':'synthetic'}}}
                def sql(self,_query):return b''
                def compose(self,*_args,**_kwargs):return b''
                def run(self,*_args,**_kwargs):return b''
            output=base/'backup.age';real_link=os.link
            def occupy_destination(src,dst,**kwargs):
                if Path(dst)==output:output.write_bytes(b'another actor\'s file')
                return real_link(src,dst,**kwargs)
            with patch.dict(os.environ,{'PATH':str(bindir)+':'+os.environ.get('PATH','')}),patch('scripts.self_hosted.recovery.os.link',side_effect=occupy_destination):
                with self.assertRaises(FileExistsError):backup(SyntheticOperator(),output,'age1'+'a'*58)
            self.assertEqual(output.read_bytes(),b'another actor\'s file')
            self.assertEqual([p.read_bytes() for p in base.glob('backup.age.partial-*')],[b'synthetic-archive'])
            self.assertFalse(Path(str(output)+'.json').exists())

    def test_backup_pipeline_success_receipts_held_ciphertext(self):
        # Controlled subprocesses model a local backup, not encryption or Docker qualification.
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory).resolve();release=base/'release';release.mkdir();(release/'private').mkdir()
            (release/'images.lock.json').write_text('{}')
            bindir=base/'bin';bindir.mkdir();docker=bindir/'synthetic-docker';age=bindir/'age'
            docker.write_text('#!/bin/sh\nprintf synthetic-archive\n');docker.chmod(0o700)
            age.write_text('#!/bin/sh\ncat\n');age.chmod(0o700)
            class SyntheticOperator:
                root=release
                profile={'id':'synthetic'}
                meta={'profile_sha256':'a'*64,'source_sha256':'b'*64}
                def __init__(self):self.docker=str(docker)
                def docker_preflight(self):return {'services':{'web':{'image':'synthetic'}}}
                def sql(self,_query):return b''
                def compose(self,*_args,**_kwargs):return b''
                def run(self,*_args,**_kwargs):return b''
            output=base/'backup.age'
            with patch.dict(os.environ,{'PATH':str(bindir)+':'+os.environ.get('PATH','')}):
                result=backup(SyntheticOperator(),output,'age1'+'a'*58)
            receipt=json.loads(Path(str(output)+'.json').read_text())
            self.assertEqual(receipt['ciphertext_sha256'],hashlib.sha256(output.read_bytes()).hexdigest())
            self.assertEqual(receipt['ciphertext_bytes'],len(output.read_bytes()))
            retained=base/result['staged_hardlink_retained']
            self.assertEqual(retained.stat().st_ino,output.stat().st_ino)
            self.assertFalse(receipt['restore_tested'])

    def test_backup_cleanup_reaps_spawned_children_on_pipeline_failure(self):
        # Real sleeping local child processes; operator and transport are fake.
        # No Docker, SQL server, service stop, credentials or provider is used.
        for failure in ('encryptor-spawn','pipe-close','wait-interrupted'):
            with self.subTest(failure=failure),tempfile.TemporaryDirectory() as directory:
                base=Path(directory).resolve();release=base/'release';release.mkdir();(release/'private').mkdir()
                class SyntheticOperator:
                    root=release;docker='synthetic-docker'
                    profile={'id':'synthetic'};meta={'profile_sha256':'a'*64,'source_sha256':'b'*64}
                    def docker_preflight(self):return {'services':{'web':{'image':'synthetic'}}}
                    def sql(self,_query):return b''
                    def compose(self,*_args,**_kwargs):return b''
                    def run(self,*_args,**_kwargs):return b''
                original_popen=subprocess.Popen;children=[]
                class CloseFault:
                    def __init__(self,pipe):self.pipe=pipe;self.failed=False
                    def fileno(self):return self.pipe.fileno()
                    @property
                    def closed(self):return self.pipe.closed
                    def close(self):
                        if not self.failed:self.failed=True;raise OSError('synthetic pipe close failure')
                        self.pipe.close()
                def spawn(args,**kwargs):
                    if len(children)==1 and failure=='encryptor-spawn':raise OSError('synthetic encryptor spawn failure')
                    child=original_popen([sys.executable,'-c','import time; time.sleep(60)'],**kwargs)
                    children.append(child)
                    if len(children)==1 and failure=='pipe-close':child.stdout=CloseFault(child.stdout)
                    if len(children)==2 and failure=='wait-interrupted':
                        wait=child.wait;first=True
                        def interrupt_once(*args,**kwargs):
                            nonlocal first
                            if first:first=False;raise InterruptedError('synthetic interruption')
                            return wait(*args,**kwargs)
                        child.wait=interrupt_once
                    return child
                with patch('scripts.self_hosted.recovery.subprocess.Popen',side_effect=spawn):
                    with self.assertRaisesRegex(OSError,'synthetic'):
                        backup(SyntheticOperator(),base/'backup.age','age1'+'a'*58)
                self.assertEqual(len(children),1 if failure=='encryptor-spawn' else 2)
                for child in children:self.assertIsNotNone(child.poll())
                self.assertTrue(children[0].stdout.closed)
                self.assertEqual(len(list(base.glob('backup.age.partial-*'))),1)
                self.assertFalse((base/'backup.age').exists())
                self.assertFalse((base/'backup.age.json').exists())
                self.assertEqual(len(list((release/'private').glob('backup-*.log'))),1)

    def test_backup_rejects_invalid_pipeline_timeout_before_operator_actions(self):
        for value in (0,-1,True,604801,1.5,None,'5'):
            with self.subTest(value=value),tempfile.TemporaryDirectory() as directory:
                # An object with no operator methods makes any accidental
                # preflight, SQL or service operation fail this assertion.
                with self.assertRaisesRegex(ValueError,'pipeline timeout'):
                    backup(object(),Path(directory)/'backup.age','age1'+'a'*58,pipeline_timeout_seconds=value)

    def test_backup_pipeline_deadline_preserves_partial_and_reaps_children(self):
        # The operator and transports are synthetic: only local Python child
        # processes run, with no Docker, SQL, service or provider access.
        for delayed in ('encryptor','producer'):
            with self.subTest(delayed=delayed),tempfile.TemporaryDirectory() as directory:
                base=Path(directory).resolve();release=base/'release';release.mkdir();(release/'private').mkdir()
                class SyntheticOperator:
                    root=release;docker='synthetic-docker'
                    profile={'id':'synthetic'};meta={'profile_sha256':'a'*64,'source_sha256':'b'*64}
                    def docker_preflight(self):return {'services':{'web':{'image':'synthetic-image'}}}
                    def sql(self,_query):return b''
                    def compose(self,*_args,**_kwargs):return b''
                    def run(self,*_args,**_kwargs):return b''
                original_popen=subprocess.Popen;children=[];wait_budgets=[]
                def spawn(args,**kwargs):
                    script='import time;time.sleep(60)' if len(children)==0 or delayed=='encryptor' else 'import time;time.sleep(.6)'
                    child=original_popen([sys.executable,'-c',script],**kwargs);children.append(child)
                    real_wait=child.wait
                    def record_wait(*args,**kw):
                        timeout=kw.get('timeout')
                        if timeout is not None and timeout<=1:wait_budgets.append(timeout)
                        return real_wait(*args,**kw)
                    child.wait=record_wait
                    return child
                try:
                    with patch('scripts.self_hosted.recovery.subprocess.Popen',side_effect=spawn):
                        with self.assertRaisesRegex(RuntimeError,'backup timed out') as error:
                            backup(SyntheticOperator(),base/'backup.age','age1'+'a'*58,pipeline_timeout_seconds=1)
                    self.assertIsInstance(error.exception.__cause__,subprocess.TimeoutExpired)
                    self.assertEqual(len(children),2)
                    for child in children:self.assertIsNotNone(child.poll())
                    self.assertTrue(children[0].stdout.closed)
                    self.assertEqual(len(list(base.glob('backup.age.partial-*'))),1)
                    self.assertFalse((base/'backup.age').exists())
                    self.assertFalse((base/'backup.age.json').exists())
                    self.assertEqual(len(list((release/'private').glob('backup-*.log'))),1)
                    if delayed=='producer':
                        self.assertGreaterEqual(len(wait_budgets),2)
                        self.assertLess(wait_budgets[1],wait_budgets[0]-.3)
                finally:
                    for child in children:
                        if child.poll() is None:child.kill();child.wait()

    def test_failed_encryptor_reaps_stalled_producer_without_waiting_for_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory).resolve();release=base/'release';release.mkdir();(release/'private').mkdir()
            class SyntheticOperator:
                root=release;docker='synthetic-docker'
                profile={'id':'synthetic'};meta={'profile_sha256':'a'*64,'source_sha256':'b'*64}
                def docker_preflight(self):return {'services':{'web':{'image':'synthetic-image'}}}
                def sql(self,_query):return b''
                def compose(self,*_args,**_kwargs):return b''
                def run(self,*_args,**_kwargs):return b''
            original_popen=subprocess.Popen;children=[]
            def spawn(args,**kwargs):
                script='import time;time.sleep(60)' if not children else 'raise SystemExit(7)'
                child=original_popen([sys.executable,'-c',script],**kwargs);children.append(child);return child
            try:
                with patch('scripts.self_hosted.recovery.subprocess.Popen',side_effect=spawn):
                    with self.assertRaisesRegex(RuntimeError,'backup unconfirmed') as error:
                        backup(SyntheticOperator(),base/'backup.age','age1'+'a'*58,pipeline_timeout_seconds=2)
                self.assertNotIsInstance(error.exception.__cause__,subprocess.TimeoutExpired)
                self.assertEqual(len(children),2)
                for child in children:self.assertIsNotNone(child.poll())
                self.assertTrue(children[0].stdout.closed)
                self.assertEqual(len(list(base.glob('backup.age.partial-*'))),1)
                self.assertFalse((base/'backup.age').exists())
                self.assertFalse((base/'backup.age.json').exists())
                self.assertEqual(len(list((release/'private').glob('backup-*.log'))),1)
            finally:
                for child in children:
                    if child.poll() is None:child.kill();child.wait()

    def test_pipeline_cleanup_kills_child_that_ignores_termination(self):
        child=subprocess.Popen([sys.executable,'-u','-c',
            'import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print("ready",flush=True); time.sleep(60)'],stdout=subprocess.PIPE)
        try:
            self.assertEqual(child.stdout.readline(),b'ready\n')
            real_wait=child.wait
            def shortened_wait(timeout=None):return real_wait(timeout=.2 if timeout==10 else timeout)
            with patch.object(child,'wait',side_effect=shortened_wait):_cleanup_pipeline(child)
            self.assertIsNotNone(child.returncode)
            self.assertLess(child.returncode,0)
            self.assertTrue(child.stdout.closed)
        finally:
            if child.poll() is None:child.kill();child.wait()

    def test_pipeline_cleanup_reports_failure_and_still_reaps_other_child(self):
        children=[subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)']) for _ in range(2)]
        try:
            with patch.object(children[0],'terminate',side_effect=PermissionError('synthetic termination refusal')):
                with self.assertRaisesRegex(RuntimeError,'Backup pipeline cleanup unconfirmed') as result:
                    try:raise OSError('original pipeline failure')
                    finally:_cleanup_pipeline(*children)
            self.assertIsInstance(result.exception.__cause__,PermissionError)
            self.assertIsInstance(result.exception.__cause__.__context__,OSError)
            self.assertIn('original pipeline failure',str(result.exception.__cause__.__context__))
            self.assertIsNotNone(children[1].poll())
        finally:
            for child in children:
                if child.poll() is None:child.kill();child.wait()

    def test_unsupported_publication_is_refused_before_stopping_services(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory).resolve();release=base/'release';release.mkdir();output=base/'backup.age'
            class SyntheticOperator:
                root=release
                stopped=False
                def docker_preflight(self):return {'services':{'web':{'image':'synthetic'}}}
                def sql(self,_query):raise AssertionError('must not reach controller')
                def compose(self,*_args,**_kwargs):self.stopped=True;raise AssertionError('must not stop services')
            op=SyntheticOperator()
            with patch('scripts.self_hosted.recovery.os.link',side_effect=OSError(errno.EOPNOTSUPP,'unsupported')):
                with self.assertRaises(OSError):backup(op,output,'age1'+'a'*58)
            self.assertFalse(op.stopped)
            self.assertFalse(output.exists())
            self.assertEqual(len(list(base.glob('.collect-backup-probe-*'))),1)

    def test_synthetic_backup_receipt_is_accepted_by_restore(self):
        # Fake tar transport and age identity; this checks the local receipt and
        # extraction contract, not Docker, encryption or production recovery.
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory).resolve();release=base/'release';release.mkdir();(release/'private').mkdir();(release/'data').mkdir()
            (release/'data'/'record').write_bytes(b'synthetic record')
            (release/'private'/'stack.env').write_text('COLLECT_RELEASE_ROOT='+json.dumps(str(release))+'\n')
            (release/'images.lock.json').write_text('{}')
            lock=json.loads((Path(__file__).resolve().parents[2]/'deploy/self-hosted/images.lock.json').read_text())
            helper=lock['services']['web']['reference']
            bindir=base/'bin';bindir.mkdir();docker=bindir/'synthetic-docker';age=bindir/'age'
            docker.write_text('#!'+sys.executable+'\n'+'''import sys,tarfile
args=sys.argv[1:]
if args and args[0]=='ps':sys.exit(0)
mount=args[args.index('--mount')+1]
source=mount.split('src=',1)[1].split(',dst=',1)[0]
if '--create' in args:
 with tarfile.open(fileobj=sys.stdout.buffer,mode='w|') as archive:archive.add(source,arcname='.')
elif '--extract' in args:
 # Docker closes container stdin unless interactive mode is requested. Model
 # this behavior so a valid Python pipe cannot hide a missing Docker flag.
 if '--interactive' not in args and '-i' not in args:sys.exit(19)
 with tarfile.open(fileobj=sys.stdin.buffer,mode='r|') as archive:archive.extractall(source)
else:sys.exit(2)
''');docker.chmod(0o700)
            age.write_text('#!/bin/sh\ncat\n');age.chmod(0o700)
            class SyntheticOperator:
                root=release
                profile={'id':'synthetic'}
                meta={'profile_sha256':'a'*64,'source_sha256':'b'*64}
                def __init__(self):self.docker=str(docker)
                def docker_preflight(self):return {'services':{'web':{'image':helper}}}
                def sql(self,_query):return b''
                def compose(self,*_args,**_kwargs):return b''
                def run(self,*_args,**_kwargs):return b''
            identity=base/'identity';identity.write_text('synthetic');identity.chmod(0o600)
            output=base/'backup.age';destination=base/'restored'
            with patch.dict(os.environ,{'PATH':str(bindir)+':'+os.environ.get('PATH','')}),patch('scripts.self_hosted.recovery.local_docker'),patch('scripts.self_hosted.recovery.Operator',return_value=SyntheticOperator()),patch('scripts.self_hosted.recovery.seal_configuration'):
                saved=backup(SyntheticOperator(),output,'age1'+'a'*58)
                result=restore(output,Path(str(output)+'.json'),identity,destination,docker=str(docker))
            self.assertEqual((destination/'data'/'record').read_bytes(),b'synthetic record')
            self.assertEqual(result['status'],'restored_not_started')
            self.assertEqual(result['ciphertext_sha256'],saved['ciphertext_sha256'])
            self.assertFalse(result['provider_activation'])

            # Replace only the archive pathname after its receipt has been
            # validated. The decryptor must consume the verified open file,
            # not the new path occupant.
            original_popen=subprocess.Popen
            replacement=base/'replacement';replacement.write_bytes(b'unrelated bytes')
            replaced_destination=base/'restored-after-path-replacement'
            def replace_before_decrypt(args,**kwargs):
                if args[0]=='age' and '--decrypt' in args:
                    os.replace(replacement,output)
                return original_popen(args,**kwargs)
            with patch.dict(os.environ,{'PATH':str(bindir)+':'+os.environ.get('PATH','')}),patch('scripts.self_hosted.recovery.local_docker'),patch('scripts.self_hosted.recovery.Operator',return_value=SyntheticOperator()),patch('scripts.self_hosted.recovery.seal_configuration'),patch('scripts.self_hosted.recovery.subprocess.Popen',side_effect=replace_before_decrypt):
                replaced=restore(output,Path(str(output)+'.json'),identity,replaced_destination,docker=str(docker))
            self.assertEqual((replaced_destination/'data'/'record').read_bytes(),b'synthetic record')
            self.assertEqual(replaced['ciphertext_sha256'],saved['ciphertext_sha256'])
            self.assertEqual(output.read_bytes(),b'unrelated bytes')

            # A mutation to the held inode itself must not produce a restore
            # receipt. Its extracted target remains stopped and unconfirmed.
            stage=base/saved['staged_hardlink_retained'];changed_destination=base/'restored-after-inplace-change'
            def change_before_decrypt(args,**kwargs):
                if args[0]=='age' and '--decrypt' in args:
                    with stage.open('r+b') as stream:
                        data=stream.read();position=data.index(b'synthetic record')
                        stream.seek(position);stream.write(b'S')
                return original_popen(args,**kwargs)
            with patch.dict(os.environ,{'PATH':str(bindir)+':'+os.environ.get('PATH','')}),patch('scripts.self_hosted.recovery.local_docker'),patch('scripts.self_hosted.recovery.Operator',return_value=SyntheticOperator()),patch('scripts.self_hosted.recovery.seal_configuration'),patch('scripts.self_hosted.recovery.subprocess.Popen',side_effect=change_before_decrypt):
                with self.assertRaisesRegex(ValueError,'Archive changed during restore'):
                    restore(stage,Path(str(output)+'.json'),identity,changed_destination,docker=str(docker))
            self.assertFalse((changed_destination/'restore-receipt.json').exists())


if __name__=='__main__':unittest.main()

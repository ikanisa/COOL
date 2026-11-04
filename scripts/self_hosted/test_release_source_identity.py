"""Synthetic release-source checks; no Docker, recovery or live deployment."""
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from scripts.self_hosted.prepare import CONFIGURATION_FILES,seal_configuration
from scripts.self_hosted.release_operator import Operator
from scripts.supabase.deployment_profile import profile_sha256


class ReleaseSourceIdentity(unittest.TestCase):
    def setUp(self):
        self.area=tempfile.TemporaryDirectory()
        self.addCleanup(self.area.cleanup)
        self.parent=Path(self.area.name).resolve()
        self.root=self.parent/'release';self.root.mkdir()
        self.source=self.root/'source';self.source.mkdir()
        self.upstream=self.root/'upstream';self.upstream.mkdir()
        self.outside=self.parent/'outside';self.outside.mkdir()
        self.sentinel=self.outside/'sentinel';self.sentinel.write_bytes(b'outside evidence')
        self.commit='a'*40
        self.profile={'format':'collect.deployment.v1','id':'synthetic','mode':'self_hosted',
            'environment':'qualification','supabase_origin':'https://identity.example',
            'admin_origin':'https://admin.example','public_origin':'https://public.example',
            'member_api_origin':'https://api.example','google_callback_origin':'https://api.example'}
        self.upstream_files={
            'volumes/api/envoy/lds.template.yaml':b'synthetic envoy configuration\n',
            'volumes/db/jwt.sql':b'-- synthetic initialization SQL\n',
        }
        for name,data in self.upstream_files.items():
            self._write(self.upstream/name,data)
            self._write(self.source/'deploy/self-hosted/upstream'/name,data)
        self.lock={'format':'collect.selfhost.upstream.v1','commit':self.commit,
            'files':[{'path':name,'sha256':hashlib.sha256(data).hexdigest()}
                     for name,data in sorted(self.upstream_files.items())]}
        self.lock_path=self.source/'deploy/self-hosted/upstream.lock.json'
        self._write(self.lock_path,json.dumps(self.lock,sort_keys=True).encode())
        self._write(self.source/'supabase/functions/fixture.js',b'export const fixture = true;\n')
        self._refresh_manifest_and_receipt()

    @staticmethod
    def _write(path,data):
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(data)

    def _refresh_manifest_and_receipt(self):
        files=[]
        for path in sorted(self.source.rglob('*')):
            if path.is_file():
                data=path.read_bytes()
                files.append({'path':path.relative_to(self.source).as_posix(),'bytes':len(data),
                    'sha256':hashlib.sha256(data).hexdigest()})
        digest=hashlib.sha256(json.dumps(files,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        (self.root/'source-manifest.json').write_text(json.dumps({'format':'collect.selfhost.source.v1','sha256':digest,'files':files}))
        meta={'format':'collect.selfhost.release.v1','profile':self.profile,
            'profile_sha256':profile_sha256(self.profile),'source_sha256':digest,'upstream_commit':self.commit}
        for name in CONFIGURATION_FILES:
            path=self.root/name;path.parent.mkdir(parents=True,exist_ok=True)
            if not path.exists():path.write_text('{}')
            if name.startswith('private/'):path.chmod(0o600)
        (self.root/'release.json').write_text(json.dumps(meta))
        seal_configuration(self.root)

    def assert_refused_before_docker(self,message):
        with patch('scripts.self_hosted.release_operator.subprocess.run') as run:
            with self.assertRaisesRegex(ValueError,'^'+message+'$'):
                Operator(self.root)
            run.assert_not_called()
        self.assertEqual(self.sentinel.read_bytes(),b'outside evidence')

    def test_existing_receipt_and_matching_runtime_copy_are_accepted(self):
        receipt=self.root/'private/configuration.json';before=receipt.read_bytes()
        with patch('scripts.self_hosted.release_operator.subprocess.run') as run:
            operator=Operator(self.root)
            run.assert_not_called()
        self.assertEqual(operator.meta['upstream_commit'],self.commit)
        self.assertEqual(receipt.read_bytes(),before)

    def test_changed_mounted_envoy_configuration_is_refused(self):
        (self.upstream/'volumes/api/envoy/lds.template.yaml').write_bytes(b'changed')
        self.assert_refused_before_docker('Source file changed')

    def test_missing_mounted_database_initialization_file_is_refused(self):
        (self.upstream/'volumes/db/jwt.sql').unlink()
        self.assert_refused_before_docker('Source file inventory changed')

    def test_extra_runtime_file_is_refused(self):
        self._write(self.upstream/'unexpected',b'not in the reviewed lock')
        self.assert_refused_before_docker('Unexpected source file')

    def test_source_and_runtime_directory_symlinks_are_refused(self):
        for tree in (self.source,self.upstream):
            link=tree/'unlisted-link';link.symlink_to(self.outside,target_is_directory=True)
            with self.subTest(tree=tree.name):self.assert_refused_before_docker('Source links and special files are refused')
            link.unlink()

    def test_expected_runtime_file_symlink_is_refused(self):
        path=self.upstream/'volumes/db/jwt.sql';path.unlink();path.symlink_to(self.sentinel)
        self.assert_refused_before_docker('Source links and special files are refused')

    @unittest.skipUnless(hasattr(os,'mkfifo'),'FIFO creation unavailable')
    def test_source_and_runtime_fifos_are_refused_without_opening(self):
        for tree in (self.source,self.upstream):
            fifo=tree/'unlisted-fifo';os.mkfifo(fifo)
            with self.subTest(tree=tree.name):self.assert_refused_before_docker('Source links and special files are refused')
            fifo.unlink()

    def test_lock_must_be_manifest_bound(self):
        manifest_path=self.root/'source-manifest.json'
        manifest=json.loads(manifest_path.read_text())
        manifest['files']=[item for item in manifest['files'] if item['path']!='deploy/self-hosted/upstream.lock.json']
        manifest['sha256']=hashlib.sha256(json.dumps(manifest['files'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
        manifest_path.write_text(json.dumps(manifest))
        meta=json.loads((self.root/'release.json').read_text());meta['source_sha256']=manifest['sha256']
        (self.root/'release.json').write_text(json.dumps(meta));seal_configuration(self.root)
        self.assert_refused_before_docker('Source-bound upstream lock required')

    def test_source_manifest_symlink_is_refused_without_following(self):
        manifest=self.root/'source-manifest.json';manifest.unlink();manifest.symlink_to(self.sentinel)
        self.assert_refused_before_docker('Physical bounded source manifest required')

    @unittest.skipUnless(hasattr(os,'mkfifo'),'FIFO creation unavailable')
    def test_source_manifest_fifo_is_refused_without_opening(self):
        manifest=self.root/'source-manifest.json';manifest.unlink();os.mkfifo(manifest)
        self.assert_refused_before_docker('Physical bounded source manifest required')

    def test_oversized_source_manifest_is_refused_before_reading(self):
        manifest=self.root/'source-manifest.json'
        manifest.write_bytes(b'x'*65)
        with patch('scripts.self_hosted.release_operator._MAX_SOURCE_MANIFEST_BYTES',64), \
             patch('scripts.self_hosted.release_operator.os.open') as opened:
            self.assert_refused_before_docker('Physical bounded source manifest required')
            opened.assert_not_called()

    def test_directory_count_and_depth_are_bounded(self):
        for name in ('_MAX_SOURCE_DIRECTORIES','_MAX_SOURCE_DEPTH'):
            with self.subTest(limit=name),patch('scripts.self_hosted.release_operator.'+name,1):
                self.assert_refused_before_docker('Source directory budget exceeded')

    def test_lock_must_match_the_release_commit(self):
        self.lock_path.write_text(json.dumps({**self.lock,'commit':'b'*40}))
        self._refresh_manifest_and_receipt()
        self.assert_refused_before_docker('Exact source-bound upstream lock required')

    def test_each_locked_runtime_file_requires_a_manifest_bound_source(self):
        (self.source/'deploy/self-hosted/upstream/volumes/db/jwt.sql').unlink()
        self._refresh_manifest_and_receipt()
        self.assert_refused_before_docker('Upstream source identity mismatch')

    def test_oversized_manifest_entry_is_refused_before_tree_walk(self):
        manifest_path=self.root/'source-manifest.json';manifest=json.loads(manifest_path.read_text())
        manifest['files'][0]['bytes']=8*1024*1024+1
        manifest['sha256']=hashlib.sha256(json.dumps(manifest['files'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
        manifest_path.write_text(json.dumps(manifest))
        meta=json.loads((self.root/'release.json').read_text());meta['source_sha256']=manifest['sha256']
        (self.root/'release.json').write_text(json.dumps(meta));seal_configuration(self.root)
        with patch('scripts.self_hosted.release_operator._verify_physical_tree') as walk:
            self.assert_refused_before_docker('Unique bounded source inventory required')
            walk.assert_not_called()

    def test_unsafe_or_duplicate_locked_paths_are_refused(self):
        for entries,message in (([{'path':'../outside','sha256':'a'*64}],'Safe relative source path required'),
                                ([{'path':'/absolute','sha256':'a'*64}],'Safe relative source path required'),
                                ([self.lock['files'][0],self.lock['files'][0]],'Unique upstream inventory required')):
            with self.subTest(entries=entries):
                lock={**self.lock,'files':entries}
                self.lock_path.write_text(json.dumps(lock,sort_keys=True))
                self._refresh_manifest_and_receipt()
                self.assert_refused_before_docker(message)


if __name__=='__main__':
    unittest.main()

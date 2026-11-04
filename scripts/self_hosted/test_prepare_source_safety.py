"""Synthetic source-export checks; no live preparation or provider calls."""
import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

from scripts.self_hosted import prepare as module
from scripts.self_hosted.release_operator import Operator


class PreparationSourceSafety(unittest.TestCase):
    def setUp(self):
        self.area=tempfile.TemporaryDirectory();self.addCleanup(self.area.cleanup)
        self.base=Path(self.area.name).resolve();self.root=self.base/'checkout';self.root.mkdir()
        self.outside=self.base/'outside';self.outside.mkdir()
        self.sentinel=self.outside/'sentinel';self.sentinel.write_bytes(b'outside evidence')
        self.vendor=self.root/module._VENDOR_ROOT
        self.vendor_files={
            'compose.json':b'{"services":{}}\n',
            'volumes/api/entrypoint.sh':b'#!/bin/sh\nexit 0\n',
        }
        self.sources={
            'supabase/functions/main.js':b'export const value = 1;\n',
            'deploy/self-hosted/generate-keys.mjs':b'// synthetic, never executed\n',
        }
        for name,data in self.vendor_files.items():self._write(self.vendor/name,data)
        for name,data in self.sources.items():self._write(self.root/name,data)
        (self.vendor/'volumes/api/entrypoint.sh').chmod(0o755)
        self.vendor.chmod(0o750);(self.vendor/'volumes').chmod(0o751)
        (self.vendor/'empty').mkdir();(self.vendor/'empty').chmod(0o711)
        self.lock={'format':'collect.selfhost.upstream.v1',
            'commit':'bc27d2661edd09a5d0b8d76ce33da6d4071a756e',
            'files':[{'path':name,'sha256':hashlib.sha256(data).hexdigest()}
                     for name,data in sorted(self.vendor_files.items())]}
        self.images={'format':'collect.selfhost.images.v1','upstream_commit':self.lock['commit'],
            'services':{'synthetic':{'reference':'example.invalid/synthetic@sha256:'+'a'*64}}}
        self._write(self.root/module._VENDOR_LOCK,json.dumps(self.lock,sort_keys=True).encode())
        self._write(self.root/module._IMAGE_LOCK,json.dumps(self.images,sort_keys=True).encode())
        self.names=('supabase/functions',module._VENDOR_ROOT,module._VENDOR_LOCK,module._IMAGE_LOCK,
                    'deploy/self-hosted/generate-keys.mjs')

    @staticmethod
    def _write(path,data):
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)

    def capture(self):
        return module._capture_inputs(self.root,self.names)

    def assert_unchanged(self,snapshot):
        with patch.object(module,'SOURCE_ROOTS',self.names):module._assert_source_unchanged(self.root,snapshot)

    def test_v1_manifest_and_staged_vendor_modes_match_captured_bytes(self):
        snapshot=self.capture();self.assertEqual(module.verify_vendor(snapshot=snapshot),self.images)
        self.assertEqual(module.verify_vendor(root=self.root),self.images)
        expected={**self.sources,
            **{module._VENDOR_ROOT+'/'+name:data for name,data in self.vendor_files.items()},
            module._VENDOR_LOCK:json.dumps(self.lock,sort_keys=True).encode(),
            module._IMAGE_LOCK:json.dumps(self.images,sort_keys=True).encode()}
        records=[{'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
                 for name,data in sorted(expected.items())]
        encoded=json.dumps(records,sort_keys=True,separators=(',',':')).encode()
        self.assertEqual(snapshot['manifest'],{'format':'collect.selfhost.source.v1','files':records,
            'sha256':hashlib.sha256(encoded).hexdigest()})
        with patch.object(module,'SOURCE_ROOTS',self.names):
            self.assertEqual(module.source_manifest(self.root),snapshot['manifest'])
        output=self.base/'release';output.mkdir();module._stage_inputs(output,snapshot)
        self.assert_unchanged(snapshot)
        for name,data in expected.items():self.assertEqual((output/'source'/name).read_bytes(),data)
        for name,data in self.vendor_files.items():self.assertEqual((output/'upstream'/name).read_bytes(),data)
        for name in ('','volumes','empty','volumes/api/entrypoint.sh'):
            self.assertEqual(stat.S_IMODE((output/'upstream'/name).stat().st_mode),
                             stat.S_IMODE((self.vendor/name).stat().st_mode))
        self.assertEqual(stat.S_IMODE((output/'source/supabase/functions/main.js').stat().st_mode),0o644)
        self.assertEqual(self.sentinel.read_bytes(),b'outside evidence')

    def test_vendor_links_are_refused_even_with_an_excluded_name(self):
        for name in ('unlisted-link','tests'):
            link=self.vendor/name;link.symlink_to(self.outside,target_is_directory=True)
            with self.subTest(name=name),self.assertRaises(ValueError):self.capture()
            link.unlink()
        self.assertEqual(self.sentinel.read_bytes(),b'outside evidence')

    def test_source_root_and_ancestor_links_are_refused(self):
        source=self.root/'supabase/functions';saved=self.root/'supabase/functions-saved';source.rename(saved)
        source.symlink_to(self.outside,target_is_directory=True)
        with self.assertRaises(ValueError):self.capture()
        source.unlink();saved.rename(source)
        ancestor=self.root/'supabase';saved=self.root/'supabase-saved';ancestor.rename(saved)
        ancestor.symlink_to(self.outside,target_is_directory=True)
        with self.assertRaises(ValueError):self.capture()
        ancestor.unlink();saved.rename(ancestor)
        self.assertEqual(self.sentinel.read_bytes(),b'outside evidence')

    def test_excluded_source_link_is_skipped_without_exporting_it(self):
        before=self.capture()['manifest']
        (self.root/'supabase/functions/node_modules').symlink_to(self.outside,target_is_directory=True)
        snapshot=self.capture();self.assertEqual(snapshot['manifest'],before)
        output=self.base/'release';output.mkdir();module._stage_inputs(output,snapshot)
        self.assertFalse((output/'source/supabase/functions/node_modules').exists())
        self.assertEqual(self.sentinel.read_bytes(),b'outside evidence')

    @unittest.skipUnless(hasattr(os,'mkfifo'),'FIFO creation unavailable')
    def test_included_source_and_vendor_fifos_are_refused(self):
        for directory in (self.root/'supabase/functions',self.vendor):
            fifo=directory/'synthetic-fifo';os.mkfifo(fifo)
            with self.subTest(directory=directory),self.assertRaisesRegex(ValueError,'Source links and special files are refused'):
                self.capture()
            fifo.unlink()

    def test_source_replacement_after_capture_refuses_without_copying_target(self):
        snapshot=self.capture();source=self.root/'supabase/functions/main.js'
        source.unlink();source.symlink_to(self.sentinel)
        output=self.base/'release';output.mkdir();module._stage_inputs(output,snapshot)
        with self.assertRaises(ValueError):self.assert_unchanged(snapshot)
        self.assertEqual((output/'source/supabase/functions/main.js').read_bytes(),self.sources['supabase/functions/main.js'])
        self.assertEqual(self.sentinel.read_bytes(),b'outside evidence')

    def test_same_size_source_change_after_capture_is_refused(self):
        snapshot=self.capture();source=self.root/'supabase/functions/main.js'
        source.write_bytes(b'x'*len(self.sources['supabase/functions/main.js']))
        output=self.base/'release';output.mkdir();module._stage_inputs(output,snapshot)
        with self.assertRaisesRegex(ValueError,'Release source changed during export'):self.assert_unchanged(snapshot)
        self.assertEqual((output/'source/supabase/functions/main.js').read_bytes(),self.sources['supabase/functions/main.js'])

    def test_tampered_capture_buffer_is_refused_before_its_file_is_written(self):
        name='supabase/functions/main.js';original=self.sources[name]
        for index,data in enumerate((b'x'*len(original),b'short')):
            with self.subTest(length=len(data)):
                snapshot=self.capture();snapshot['content'][name]=data
                output=self.base/('release-'+str(index));output.mkdir()
                with self.assertRaisesRegex(ValueError,'Captured source identity changed'):
                    module._stage_inputs(output,snapshot)
                self.assertFalse((output/'source'/name).exists())
        self.assertEqual(self.sentinel.read_bytes(),b'outside evidence')

    def test_same_inode_change_during_capture_is_refused(self):
        source=self.root/'supabase/functions/main.js';inode=source.stat().st_ino
        original_read=os.read;changed=False
        def changing_read(fd,size):
            nonlocal changed
            if not changed and os.fstat(fd).st_ino==inode:
                changed=True;source.write_bytes(b'z'*len(self.sources['supabase/functions/main.js']))
            return original_read(fd,size)
        with patch.object(module.os,'read',side_effect=changing_read):
            with self.assertRaisesRegex(ValueError,'Source file changed'):self.capture()
        self.assertTrue(changed)

    def test_existing_destination_or_destination_link_is_never_overwritten(self):
        snapshot=self.capture();output=self.base/'release';output.mkdir()
        (output/'source').symlink_to(self.outside,target_is_directory=True)
        with self.assertRaises(FileExistsError):module._stage_inputs(output,snapshot)
        self.assertEqual(self.sentinel.read_bytes(),b'outside evidence')
        (output/'source').unlink();module._stage_inputs(output,snapshot)
        with self.assertRaises(FileExistsError):module._stage_inputs(output,snapshot)
        self.assertEqual((output/'source/supabase/functions/main.js').read_bytes(),self.sources['supabase/functions/main.js'])

    def test_vendor_lock_refuses_missing_extra_duplicate_and_unsafe_paths(self):
        original=self.lock['files'];valid=original[0]
        cases=([valid],original+[{'path':'extra','sha256':'a'*64}],
               original+[valid],[{'path':'../outside','sha256':'a'*64}])
        for entries in cases:
            with self.subTest(entries=entries):
                self._write(self.root/module._VENDOR_LOCK,json.dumps({**self.lock,'files':entries}).encode())
                with self.assertRaises(ValueError):module.verify_vendor(snapshot=self.capture())
        self.assertEqual(self.sentinel.read_bytes(),b'outside evidence')

    def test_source_size_and_directory_budgets_refuse_before_export(self):
        with patch.object(module,'_SOURCE_FILE_LIMIT',4):
            with self.assertRaisesRegex(ValueError,'Invalid release source size'):
                module._capture_inputs(self.root,('supabase/functions',))
        with patch.object(module,'_SOURCE_DIRECTORY_COUNT',0):
            with self.assertRaisesRegex(ValueError,'Source directory budget exceeded'):
                module._capture_inputs(self.root,('supabase/functions',))

    def test_staged_key_and_compose_consumers_use_captured_inputs(self):
        profile={'format':'collect.deployment.v1','id':'synthetic','mode':'self_hosted',
            'environment':'qualification','supabase_origin':'https://identity.example',
            'member_api_origin':'https://api.example','admin_origin':'https://admin.example',
            'public_origin':'https://public.example','google_callback_origin':'https://api.example'}
        profile_path=self.base/'profile.json';profile_path.write_text(json.dumps(profile))
        output=self.base/'release';calls=[]
        keys={key:'synthetic-'+key for key in module.PRIVATE_KEYS}
        keys.update({'SUPABASE_PUBLISHABLE_KEY':'synthetic-public','SUPABASE_SECRET_KEY':'synthetic-secret',
                     'COLLECT_EDGE_PASSWORD':'synthetic-edge','COLLECT_SMS_EDGE_PASSWORD':'synthetic-sms'})
        def key_generator(argv,**_kwargs):
            calls.append(argv);self.assertEqual(Path(argv[1]),output/'source/deploy/self-hosted/generate-keys.mjs')
            self.assertEqual(Path(argv[1]).read_bytes(),self.sources['deploy/self-hosted/generate-keys.mjs'])
            Path(argv[2]).write_text(json.dumps(keys));Path(argv[2]).chmod(0o600)
        def tls(directory):
            directory.mkdir();(directory/'ca.crt').write_text('synthetic-ca');(directory/'server.crt').write_text('synthetic-cert')
        compose={'services':{'synthetic':{}}}
        before=os.umask(0o077);os.umask(before)
        try:
            with patch.object(module,'ROOT',self.root),patch.object(module,'SOURCE_ROOTS',self.names), \
                 patch.object(module,'frontend_inventory',return_value={'sha256':'b'*64,'complete':True}), \
                 patch.object(module,'tls_keys',side_effect=tls), \
                 patch.object(module.subprocess,'run',side_effect=key_generator), \
                 patch.object(module,'build_compose',return_value=compose) as build:
                result=module.prepare(profile_path,output,tls_mode='internal')
                operator=Operator(output)
                self.assertEqual(operator.meta['source_sha256'],result['source_sha256'])
                self.assertEqual(operator.meta['state'],'prepared_not_started')
        finally:os.umask(before)
        self.assertEqual(len(calls),1);self.assertEqual(result['services'],1)
        build.assert_called_once_with(profile,self.images,upstream_compose=self.vendor_files['compose.json'])
        self.assertEqual(json.loads((output/'compose.json').read_text()),compose)
        self.assertEqual(self.sentinel.read_bytes(),b'outside evidence')

    def test_changed_source_refuses_before_key_or_tls_consumers(self):
        profile={'format':'collect.deployment.v1','id':'synthetic','mode':'self_hosted',
            'environment':'qualification','supabase_origin':'https://identity.example',
            'member_api_origin':'https://api.example','admin_origin':'https://admin.example',
            'public_origin':'https://public.example','google_callback_origin':'https://api.example'}
        profile_path=self.base/'profile.json';profile_path.write_text(json.dumps(profile))
        output=self.base/'release';stage=module._stage_inputs
        def stage_then_change(destination,snapshot):
            stage(destination,snapshot)
            path=self.root/'supabase/functions/main.js';path.write_bytes(b'x'*len(self.sources['supabase/functions/main.js']))
        before=os.umask(0o077);os.umask(before)
        try:
            with patch.object(module,'ROOT',self.root),patch.object(module,'SOURCE_ROOTS',self.names), \
                 patch.object(module,'frontend_inventory',return_value={'sha256':'b'*64,'complete':True}), \
                 patch.object(module,'_stage_inputs',side_effect=stage_then_change), \
                 patch.object(module.subprocess,'run') as node,patch.object(module,'tls_keys') as tls:
                with self.assertRaisesRegex(ValueError,'Release source changed during export'):
                    module.prepare(profile_path,output,tls_mode='internal')
                node.assert_not_called();tls.assert_not_called()
        finally:os.umask(before)
        self.assertEqual((output/'source/supabase/functions/main.js').read_bytes(),self.sources['supabase/functions/main.js'])
        self.assertFalse((output/'private').exists())
        self.assertEqual(self.sentinel.read_bytes(),b'outside evidence')


if __name__=='__main__':
    unittest.main()

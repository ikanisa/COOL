"""Actual isolated TEST certificate validation; no retained cert/key/runtime is read."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import unittest
from unittest.mock import patch

from scripts.self_hosted import prepare as module
from scripts.self_hosted.configure import read_env
from scripts.self_hosted import test_prepare_source_safety as source_fixture
from scripts.self_hosted import test_prepare_retained_keys as key_fixture
from scripts.self_hosted import test_retained_database_tls as tls_fixture


@unittest.skipUnless(shutil.which('openssl') and shutil.which('node'), 'Host certificate/crypto tools unavailable')
class RetainedDatabaseTLSPreparation(unittest.TestCase):
    command=staticmethod(tls_fixture.ActualOpenSSLCertificates.command)

    @classmethod
    def setUpClass(cls):
        # Reuse the maintained, real self-issued TEST CA/leaf fixture only.
        tls_fixture.ActualOpenSSLCertificates.setUpClass.__func__(cls)
        cls.crypto_base=cls.base
        cls.keys=key_fixture.synthetic_keys()

    def setUp(self):
        self.fixture=source_fixture.PreparationSourceSafety('test_v1_manifest_and_staged_vendor_modes_match_captured_bytes')
        self.fixture.setUp();self.addCleanup(self.fixture.doCleanups)
        self.base=self.fixture.base
        self.private=self.base/'tls-input-private';self.private.mkdir(mode=0o700)
        self.directory=self.private/'db-tls';self.directory.mkdir(mode=0o700)
        self.install('ca.crt',self.ca/'ca.crt')
        self.install('server.crt',self.crypto_base/'valid.crt')
        self.install('server.key',self.crypto_base/'test-server.key')
        # The fresh producer leaves public issuance evidence here. It must not
        # enter the runtime copy, and the original CA signing key stays outside.
        (self.directory/'server.csr').write_bytes(b'isolated TEST CSR evidence')
        (self.directory/'server.csr').chmod(0o600)
        self.keymap=self.private/'keys.json';self.keymap.write_text(json.dumps(self.keys));self.keymap.chmod(0o600)
        self.profile={'format':'collect.deployment.v1','id':'retained-tls-fixture','mode':'self_hosted',
            'environment':'qualification','supabase_origin':'https://identity.example',
            'member_api_origin':'https://api.example','admin_origin':'https://admin.example',
            'public_origin':'https://public.example','google_callback_origin':'https://api.example'}
        self.profile_path=self.base/'profile.json';self.profile_path.write_text(json.dumps(self.profile))
        self.output=self.base/'release'

    def install(self,name,source):
        shutil.copyfile(source,self.directory/name);(self.directory/name).chmod(0o600)

    def hashes(self):
        return {name:hashlib.sha256((self.directory/name).read_bytes()).hexdigest()
                for name in ('ca.crt','server.crt','server.key')}

    def prepare(self,*,stage_hook=None):
        original_run=subprocess.run;calls=[]
        def readonly_crypto(argv,**kwargs):
            if not (argv[:3]==['node','--input-type=module','-e'] or
                    argv[0]=='openssl' and argv[1] in ('x509','pkey','verify')):
                self.fail('Retained artifact preparation must not generate credentials or invoke runtime tools')
            calls.append(argv[:2]);return original_run(argv,**kwargs)
        previous=os.umask(0o077);os.umask(previous)
        try:
            with patch.object(module,'ROOT',self.fixture.root),patch.object(module,'SOURCE_ROOTS',self.fixture.names), \
                 patch.object(module,'frontend_inventory',return_value={'sha256':'b'*64,'complete':True}), \
                 patch.object(module,'build_compose',return_value={'services':{}}), \
                 patch.object(module,'tls_keys') as generator,patch.object(module.subprocess,'run',side_effect=readonly_crypto):
                if stage_hook is None:
                    result=module.prepare(self.profile_path,self.output,tls_mode='internal',retained_keys_file=self.keymap,
                                          retained_db_tls_directory=self.directory)
                else:
                    with patch.object(module.RetainedDatabaseTLS,'stage',stage_hook):
                        result=module.prepare(self.profile_path,self.output,tls_mode='internal',retained_keys_file=self.keymap,
                                              retained_db_tls_directory=self.directory)
                generator.assert_not_called()
        finally:os.umask(previous)
        return result,calls

    def test_capture_is_redacted_and_does_not_claim_crypto_before_validation(self):
        captured=module.read_retained_db_tls(self.directory)
        self.assertTrue(captured.hashes==self.hashes())
        self.assertTrue((self.directory/'server.key').read_text() not in repr(captured))
        self.assertFalse(captured.receipt()['validated_chain_time_db_san_and_key'])

    def test_actual_test_chain_reused_exactly_without_ca_or_key_generation(self):
        before=self.hashes();keymap=hashlib.sha256(self.keymap.read_bytes()).hexdigest()
        result,calls=self.prepare()
        target=self.output/'private/db-tls'
        self.assertEqual(set(p.name for p in target.iterdir()),{'ca.crt','server.crt','server.key'})
        for name,value in before.items():
            self.assertEqual(hashlib.sha256((target/name).read_bytes()).hexdigest(),value)
            self.assertEqual(stat.S_IMODE((target/name).stat().st_mode),0o600)
        self.assertEqual(stat.S_IMODE(target.stat().st_mode),0o700)
        self.assertEqual(self.hashes(),before)
        self.assertEqual(hashlib.sha256(self.keymap.read_bytes()).hexdigest(),keymap)
        self.assertEqual(read_env(self.output/'private/functions.env')['COLLECT_DB_CA_PEM'],(self.directory/'ca.crt').read_text().strip())
        meta=json.loads((self.output/'release.json').read_bytes())
        self.assertEqual(meta['retained_db_tls']['files_sha256'],before)
        self.assertEqual(meta['retained_db_tls']['source_directory'],str(self.directory))
        self.assertFalse(meta['retained_db_tls']['ca_private_key_copied'])
        self.assertTrue(meta['retained_db_tls']['validated_chain_time_db_san_and_key'])
        self.assertFalse(result['started']);self.assertFalse(result['retained_db_tls']['generated'])
        self.assertTrue((self.output/'private/configuration.json').exists())
        self.assertTrue(any(call==['openssl','verify'] for call in calls))
        self.assertFalse((self.output/'private/db-ca').exists())

    def test_wrong_san_cn_only_wrong_ca_or_private_key_never_seals_artifact(self):
        scenarios=[('server.crt',self.crypto_base/'wrong-san.crt'),('server.crt',self.crypto_base/'cn-only.crt'),
                   ('ca.crt',self.other/'ca.crt'),('server.key',self.other/'ca.key')]
        for index,(name,source) in enumerate(scenarios):
            self.install('ca.crt',self.ca/'ca.crt');self.install('server.crt',self.crypto_base/'valid.crt')
            self.install('server.key',self.crypto_base/'test-server.key');self.install(name,source)
            self.output=self.base/('refused-'+str(index))
            with self.assertRaisesRegex(ValueError,'TLS validation failed'):self.prepare()
            self.assertFalse((self.output/'release.json').exists())
            self.assertFalse((self.output/'private/configuration.json').exists())

    def test_duplicate_certificate_pem_is_refused_by_real_crypto_boundary(self):
        path=self.directory/'ca.crt';path.write_bytes(path.read_bytes()*2)
        with self.assertRaisesRegex(ValueError,'TLS validation failed'):self.prepare()
        self.assertFalse((self.output/'release.json').exists())

    def test_source_drift_after_capture_is_refused_despite_valid_staged_chain(self):
        original=module.RetainedDatabaseTLS.stage
        def stage_then_change(captured,destination):
            original(captured,destination);self.install('ca.crt',self.other/'ca.crt')
        with self.assertRaisesRegex(ValueError,'TLS source changed'):self.prepare(stage_hook=stage_then_change)
        self.assertFalse((self.output/'release.json').exists())

    def test_files_and_both_directory_permissions_are_strict(self):
        path=self.directory/'ca.crt';path.chmod(0o644)
        with self.assertRaises(ValueError):module.read_retained_db_tls(self.directory)
        path.chmod(0o600);self.directory.chmod(0o755)
        with self.assertRaises(ValueError):module.read_retained_db_tls(self.directory)
        self.directory.chmod(0o700);self.private.chmod(0o755)
        with self.assertRaises(ValueError):module.read_retained_db_tls(self.directory)

    def test_other_owner_hardlink_symlink_and_fifo_are_refused(self):
        original_stat=os.stat
        def other_owner(path,*args,**kwargs):
            value=original_stat(path,*args,**kwargs)
            if path=='server.key' and kwargs.get('dir_fd') is not None:
                fields=list(value);fields[4]=os.geteuid()+1;return os.stat_result(fields)
            return value
        with patch.object(module.os,'stat',side_effect=other_owner):
            with self.assertRaises(ValueError):module.read_retained_db_tls(self.directory)
        hard=self.directory/'key-copy';os.link(self.directory/'server.key',hard)
        with self.assertRaises(ValueError):module.read_retained_db_tls(self.directory)
        hard.unlink();link=self.directory/'unused-link';link.symlink_to(self.directory/'server.key')
        with self.assertRaises(ValueError):module.read_retained_db_tls(self.directory)
        link.unlink();fifo=self.directory/'pipe';os.mkfifo(fifo,0o600)
        with self.assertRaises(ValueError):module.read_retained_db_tls(self.directory)

    def test_directory_symlink_bounds_and_ca_signing_key_are_refused(self):
        alias=self.private/'alias';alias.symlink_to(self.directory,target_is_directory=True)
        with self.assertRaises(ValueError):module.read_retained_db_tls(alias)
        (self.directory/'ca.key').write_bytes(b'synthetic prohibited signing key placeholder')
        with self.assertRaises(ValueError):module.read_retained_db_tls(self.directory)
        (self.directory/'ca.key').unlink();(self.directory/'server.crt').write_bytes(b'x'*65537)
        with self.assertRaises(ValueError):module.read_retained_db_tls(self.directory)

    def test_captured_stage_cannot_overwrite_an_existing_directory(self):
        captured=module.read_retained_db_tls(self.directory);target=self.base/'existing';target.mkdir(mode=0o700)
        sentinel=target/'server.key';sentinel.write_bytes(b'preserved synthetic bytes')
        with self.assertRaises(FileExistsError):captured.stage(target)
        self.assertEqual(sentinel.read_bytes(),b'preserved synthetic bytes')

    def test_invalid_input_refuses_before_source_export_or_key_generation(self):
        (self.directory/'ca.crt').chmod(0o644)
        with patch.object(module,'_capture_inputs') as capture,patch.object(module.subprocess,'run') as command:
            with self.assertRaises(ValueError):
                module.prepare(self.profile_path,self.output,retained_db_tls_directory=self.directory)
        capture.assert_not_called();command.assert_not_called();self.assertFalse(self.output.exists())

    def test_private_tls_input_cannot_be_included_in_public_release_source(self):
        private=self.fixture.root/'supabase/functions/private';private.mkdir(mode=0o700)
        target=private/'db-tls';target.mkdir(mode=0o700)
        for name in ('ca.crt','server.crt','server.key'):
            shutil.copyfile(self.directory/name,target/name);(target/name).chmod(0o600)
        self.directory=target
        with self.assertRaisesRegex(ValueError,'cannot be exported as release source'):self.prepare()
        self.assertFalse(self.output.exists())


if __name__=='__main__':unittest.main()

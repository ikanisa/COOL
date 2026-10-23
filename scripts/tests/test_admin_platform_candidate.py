import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import struct
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


candidate = module('platform_candidate', ROOT / 'scripts/admin_platform_candidate.py')
policy = module('ci_policy', ROOT / 'scripts/qa/collect_ci_policy.py')


class PlatformCandidateTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name).resolve()
        for name in candidate.INPUTS + candidate.SUPABASE_INPUTS:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('isolated identity fixture input\n')
        # The workflow uses the same reviewed source-input selector as verify.
        (self.root / 'scripts/admin_platform_candidate.py').write_bytes(
            (ROOT / 'scripts/admin_platform_candidate.py').read_bytes())
        (self.root / candidate.SUPABASE_WRANGLER).write_bytes(
            (ROOT / candidate.SUPABASE_WRANGLER).read_bytes())
        (self.root / '.gitignore').write_text('build/\n')
        for args in (['init', '--quiet'], ['add', '.'],
                     ['-c', 'user.name=Identity fixture', '-c', 'user.email=fixture@example.invalid',
                      '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'local fixture']):
            subprocess.run(['git', *args], cwd=self.root, check=True, capture_output=True)
        self.commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=self.root, text=True).strip()
        self.build = self.root / 'build/web'
        self.build.mkdir(parents=True)
        for name in candidate.REQUIRED - {'custom-sw.js', 'version.json'}:
            path = self.build / name
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text('fixture artifact role: ' + name)
        (self.build / 'custom-sw.js').write_text(
            'const CACHE_NAME = "collect-admin-fixture";\n'
            'const CACHE_URLS = ["./"];\nconst CACHE_HASHES = {"./":"fixture"};\n')
        (self.build / 'version.json').write_text(json.dumps({
            'source_commit': self.commit, 'source_dirty': False,
            'backend': 'cloudflare', 'authentication': 'email_otp_cookie_with_totp',
            'minimum_core_schema_migration': '0017_admin_email_otp.sql',
            'financial_model': 'canonical_evidence_ledger', 'financial_contract_version': 2,
        }))
        workflow = policy.read_workflow(ROOT / '.github/workflows/ci.yml')
        producer = next(s['run'] for s in workflow['jobs']['admin-web-build']['steps']
                        if s.get('name') == 'Bind shipping PWA artifact to the clean workflow commit')
        self.producer = producer
        result = subprocess.run(['bash', '-e', '-c', producer], cwd=self.root,
                                env={**os.environ, 'GITHUB_SHA': self.commit, 'COLLECT_BACKEND':'cloudflare'}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.receipt = self.root / 'build/admin-platform-pwa-artifact.json'

    def verify(self):
        return candidate.verify(self.build, self.receipt, self.commit, self.root, backend='cloudflare')

    def test_actual_producer_receipt_verifies_without_claiming_hosted_acceptance(self):
        value = self.verify()
        self.assertEqual(value['source_commit'], self.commit)
        self.assertIs(value['hosted_deployment_verified'], False)

    def test_producer_and_consumer_ignore_only_filesystem_metadata_preserving_app_links(self):
        metadata=self.build/'assets/._lazy.txt';metadata.parent.mkdir(parents=True);metadata.write_bytes(b'preserved resource fork')
        links=self.build/'.well-known/assetlinks.json';links.parent.mkdir(exist_ok=True);links.write_text('[]')
        result=subprocess.run(['bash','-e','-c',self.producer],cwd=self.root,
                              env={**os.environ,'GITHUB_SHA':self.commit,'COLLECT_BACKEND':'cloudflare'},capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        receipt=json.loads(self.receipt.read_text())
        self.assertNotIn('assets/._lazy.txt',receipt['files'])
        self.assertIn('.well-known/assetlinks.json',receipt['files'])
        self.verify()
        self.assertEqual(metadata.read_bytes(),b'preserved resource fork')
        links.write_text('[{"changed":"binding"}]')
        with self.assertRaises(ValueError):self.verify()

    def test_required_app_links_cannot_be_missing_before_receipt_generation(self):
        for name in ['.well-known/assetlinks.json','.well-known/apple-app-site-association']:
            path=self.build/name;original=path.read_bytes();path.unlink()
            result=subprocess.run(['bash','-e','-c',self.producer],cwd=self.root,
                                  env={**os.environ,'GITHUB_SHA':self.commit,'COLLECT_BACKEND':'cloudflare'},capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('missing a required artifact role',result.stderr)
            with self.assertRaises(ValueError):self.verify()
            path.write_bytes(original)

    def test_artifact_bytes_additions_and_missing_roles_are_rejected(self):
        path = self.build / 'main.dart.js'
        original = path.read_bytes()
        path.write_bytes(original + b'changed')
        with self.assertRaises(ValueError):
            self.verify()
        path.write_bytes(original)
        extra = self.build / 'unbound.js'
        extra.write_text('unbound')
        with self.assertRaises(ValueError):
            self.verify()
        extra.unlink()
        path.unlink()
        with self.assertRaises(ValueError):
            self.verify()

    def test_wrong_commit_source_inputs_and_symbolic_artifacts_are_rejected(self):
        with self.assertRaises(ValueError):
            candidate.verify(self.build, self.receipt, '0' * 40, self.root, backend='cloudflare')
        path = self.root / 'pubspec.lock'
        original = path.read_bytes()
        path.write_text('different compiler inputs')
        with self.assertRaises(ValueError):
            self.verify()
        path.write_bytes(original)
        (self.build / 'alias.js').symlink_to(self.build / 'main.dart.js')
        with self.assertRaises(ValueError):
            self.verify()

    def test_new_direct_builder_and_transport_dependencies_are_source_bound(self):
        for name in ('scripts/supabase/admin_build_config.py', 'deploy/platform-admin/src/supabase-transport.js'):
            path = self.root / name
            original = path.read_bytes()
            path.write_bytes(original + b'changed direct dependency\n')
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.verify()
            path.write_bytes(original)

    def test_self_consistent_old_transport_or_financial_model_is_rejected(self):
        version_path = self.build / 'version.json'
        original = version_path.read_bytes()
        original_receipt = self.receipt.read_bytes()
        for key, value in [('authentication', 'email'),
                           ('authentication', 'password_cookie_with_totp'),
                           ('minimum_core_schema_migration', '0015_momo_gateway_allocation.sql'),
                           ('financial_model', 'legacy_core'),
                           ('financial_contract_version', 1), ('financial_contract_version', 2.0)]:
            with self.subTest(key=key, value=value):
                version = json.loads(original)
                version[key] = value
                version_path.write_text(json.dumps(version))
                receipt = json.loads(original_receipt)
                receipt['files']['version.json'] = {
                    'sha256': hashlib.sha256(version_path.read_bytes()).hexdigest(),
                    'bytes': version_path.stat().st_size,
                }
                receipt['artifact_manifest_sha256'] = hashlib.sha256(json.dumps(
                    receipt['files'], sort_keys=True, separators=(',', ':')).encode()).hexdigest()
                self.receipt.write_text(json.dumps(receipt))
                with self.assertRaises(ValueError):
                    self.verify()
        version_path.write_bytes(original)
        self.receipt.write_bytes(original_receipt)

    def test_identity_receipt_cannot_claim_hosted_verification_or_duplicate_fields(self):
        original = self.receipt.read_text()
        receipt = json.loads(original)
        receipt['hosted_deployment_verified'] = True
        self.receipt.write_text(json.dumps(receipt))
        with self.assertRaises(ValueError):
            self.verify()
        self.receipt.write_text(original.replace('{', '{"source_dirty":true,', 1))
        with self.assertRaises(ValueError):
            self.verify()

    def supabase_receipt(self, *, default_backend=False):
        path = self.build / 'version.json'
        version = json.loads(path.read_text())
        migration = self.root / candidate.SUPABASE_INPUTS[1]
        version.update({'backend':'supabase', 'authentication':'supabase_auth_cookie_with_email_verification',
                        'minimum_core_schema_migration':migration.name,
                        'supabase_project_ref':'rrlduytparvsjfmegalh',
                        'supabase_schema_sha256':hashlib.sha256(migration.read_bytes()).hexdigest(),
                        'admin_transport':'same_origin_static_proxy',
                        'legacy_data_import_required':True, 'supabase_qualification_complete':False})
        chain = [{'name': source.name, 'sha256': hashlib.sha256(source.read_bytes()).hexdigest()}
                 for source in sorted((self.root / 'supabase/migrations').glob('*.sql'))]
        version.update({'supabase_migrations':chain, 'supabase_migration_chain_sha256':hashlib.sha256(
            json.dumps(chain,sort_keys=True,separators=(',',':')).encode()).hexdigest()})
        path.write_text(json.dumps(version))
        env = {**os.environ, 'GITHUB_SHA': self.commit}
        if default_backend:
            env.pop('COLLECT_BACKEND', None)
        else:
            env['COLLECT_BACKEND'] = 'supabase'
        result = subprocess.run(['bash','-e','-c',self.producer],cwd=self.root,
                                env=env,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)

    def test_ordinary_producer_and_consumer_default_to_supabase(self):
        with self.assertRaises(ValueError):
            candidate.verify(self.build, self.receipt, self.commit, self.root)
        self.supabase_receipt(default_backend=True)
        value = candidate.verify(self.build, self.receipt, self.commit, self.root)
        self.assertIs(value['hosted_deployment_verified'], False)
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/admin_platform_candidate.py'),
                                 '--build-root', str(self.build), '--receipt', str(self.receipt),
                                 '--commit', self.commit], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_workflow_producer_rejects_retired_supabase_authenticator_metadata(self):
        self.supabase_receipt()
        path = self.build / 'version.json'
        version = json.loads(path.read_text())
        version['authentication'] = 'supabase_auth_cookie_with_totp'
        path.write_text(json.dumps(version))
        result = subprocess.run(['bash', '-e', '-c', self.producer], cwd=self.root,
                                env={**os.environ, 'GITHUB_SHA': self.commit, 'COLLECT_BACKEND': 'supabase'},
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Supabase candidate lacks exact project, migration and qualification identity', result.stderr)

    def test_receipt_must_explicitly_identify_its_backend(self):
        receipt = json.loads(self.receipt.read_text())
        del receipt['backend']
        self.receipt.write_text(json.dumps(receipt))
        with self.assertRaises(ValueError):
            self.verify()

    def test_actual_supabase_producer_binds_backend_and_migration_without_hosted_claim(self):
        self.supabase_receipt()
        value = candidate.verify(self.build,self.receipt,self.commit,self.root,backend='supabase')
        self.assertIs(value['hosted_deployment_verified'],False)
        with self.assertRaises(ValueError):
            self.verify()
        (self.root / candidate.SUPABASE_INPUTS[1]).write_text('changed migration source')
        with self.assertRaises(ValueError):
            candidate.verify(self.build,self.receipt,self.commit,self.root,backend='supabase')

    def test_migration_inventory_ignores_only_structural_metadata(self):
        expected = candidate.migration_paths(self.root)
        metadata = self.root / 'supabase/migrations/._20261020134444_collect_curated_platform_baseline.sql'
        valid = struct.pack('>II16sHIII', 0x00051607, 0x00020000, b'\0' * 16, 1, 9, 38, 4) + b'fork'
        metadata.write_bytes(valid)
        self.assertEqual(candidate.migration_paths(self.root), expected)
        self.assertEqual(metadata.read_bytes(), valid)
        for malformed in [b'pretend metadata', valid[:30], valid[:34] + struct.pack('>I', 5) + valid[38:]]:
            metadata.write_bytes(malformed)
            with self.subTest(malformed=malformed), self.assertRaises(ValueError):
                candidate.migration_paths(self.root)
        metadata.unlink()
        metadata.symlink_to(expected[0])
        with self.assertRaises(ValueError):
            candidate.migration_paths(self.root)
        metadata.unlink()
        invalid = self.root / 'supabase/migrations/unversioned.sql'
        invalid.write_text('select 3;')
        with self.assertRaises(ValueError):
            candidate.migration_paths(self.root)
        invalid.unlink()
        additional = self.root / 'supabase/migrations/20261020135932_collect_link.sql'
        additional.symlink_to(expected[0])
        with self.assertRaises(ValueError):
            candidate.migration_paths(self.root)

    def test_supabase_receipt_binds_cloudflare_frontend_runtime(self):
        self.supabase_receipt()
        receipt = json.loads(self.receipt.read_text())
        self.assertEqual(receipt['hosting'], candidate.hosting_profile('supabase'))
        self.assertTrue({'deploy/platform-admin/src/index.js',
                         'deploy/platform-admin/src/supabase-transport.js',
                         candidate.SUPABASE_WRANGLER}.issubset(receipt['input_sha256']))
        self.assertNotIn('deploy/platform-admin/wrangler.jsonc', receipt['input_sha256'])
        self.assertFalse(any(name.startswith('deploy/platform-supabase-free/')
                             for name in receipt['input_sha256']))
        for name in candidate.SUPABASE_INPUTS:
            path = self.root / name
            original = path.read_bytes()
            path.write_bytes(original + b'changed host or schema\n')
            with self.subTest(name=name), self.assertRaises(ValueError):
                candidate.verify(self.build,self.receipt,self.commit,self.root,backend='supabase')
            path.write_bytes(original)

    def test_supabase_rejects_stale_netlify_or_legacy_hosting_identity(self):
        self.supabase_receipt()
        original = self.receipt.read_bytes()
        for hosting in [None, {'provider': 'netlify', 'configuration': 'deploy/platform-supabase-free/netlify.toml'},
                        candidate.hosting_profile('cloudflare')]:
            receipt = json.loads(original)
            receipt['hosting'] = hosting
            self.receipt.write_text(json.dumps(receipt))
            with self.subTest(hosting=hosting), self.assertRaises(ValueError):
                candidate.verify(self.build, self.receipt, self.commit, self.root)
        self.receipt.write_bytes(original)

    def test_supabase_rejects_legacy_or_netlify_input_manifest(self):
        self.supabase_receipt()
        original = self.receipt.read_bytes()
        for stale in ['deploy/platform-admin/wrangler.jsonc', 'deploy/platform-supabase-free/netlify.toml']:
            receipt = json.loads(original)
            del receipt['input_sha256'][candidate.SUPABASE_WRANGLER]
            receipt['input_sha256'][stale] = '0' * 64
            self.receipt.write_text(json.dumps(receipt))
            with self.subTest(stale=stale), self.assertRaises(ValueError):
                candidate.verify(self.build, self.receipt, self.commit, self.root)
        self.receipt.write_bytes(original)

    def test_supabase_profile_cannot_silently_select_the_legacy_backend(self):
        self.supabase_receipt()
        profile = self.root / candidate.SUPABASE_WRANGLER
        value = json.loads(profile.read_text())
        value['vars']['COLLECT_BACKEND'] = 'cloudflare'
        profile.write_text(json.dumps(value))
        with self.assertRaises(ValueError):
            candidate.verify(self.build, self.receipt, self.commit, self.root)
        with self.assertRaises(ValueError):
            candidate.source_inputs(self.root, 'supabase')

    def test_additive_migration_is_bound_and_post_build_changes_are_rejected(self):
        additional = self.root / 'supabase/migrations/20261020135932_collect_runtime_role_and_function_paths.sql'
        additional.write_text('-- additive fixture\nselect 2;\n')
        subprocess.run(['git','add','.'],cwd=self.root,check=True,capture_output=True)
        subprocess.run(['git','-c','user.name=Identity fixture','-c','user.email=fixture@example.invalid',
                        '-c','commit.gpgsign=false','commit','--quiet','-m','additive fixture'],
                       cwd=self.root,check=True,capture_output=True)
        self.commit = subprocess.check_output(['git','rev-parse','HEAD'],cwd=self.root,text=True).strip()
        version_path = self.build / 'version.json'
        version = json.loads(version_path.read_text())
        version['source_commit'] = self.commit
        version_path.write_text(json.dumps(version))
        self.supabase_receipt()
        candidate.verify(self.build,self.receipt,self.commit,self.root,backend='supabase')
        receipt = json.loads(self.receipt.read_text())
        self.assertIn(additional.relative_to(self.root).as_posix(),receipt['input_sha256'])
        additional.write_text('-- changed additive fixture\nselect 3;\n')
        with self.assertRaises(ValueError):
            candidate.verify(self.build,self.receipt,self.commit,self.root,backend='supabase')
        additional.unlink()
        with self.assertRaises(ValueError):
            candidate.verify(self.build,self.receipt,self.commit,self.root,backend='supabase')

    def test_qualification_metadata_cannot_become_a_clean_shipping_candidate(self):
        self.supabase_receipt()
        candidate.verify(self.build, self.receipt, self.commit, self.root)
        self.assertEqual(subprocess.check_output(['git', 'status', '--porcelain'],
                                                cwd=self.root, text=True), '')
        path = self.build / 'version.json'
        original_version = path.read_bytes()
        original_receipt = self.receipt.read_bytes()
        for markers in [{'qualification_complete': False}, {'qualification_complete': True},
                        {'qualification_complete': None},
                        {'purpose': 'qualification'}, {'environment': 'qualification'},
                        {'admin_origin': 'https://admin-supabase-qa.collect.ikanisa.com'},
                        {'shipping_candidate': False},
                        {'purpose': 'qualification', 'environment': 'qualification',
                         'shipping_candidate': False, 'qualification_complete': False,
                         'admin_origin': 'https://admin-supabase-qa.collect.ikanisa.com'}]:
            version = json.loads(original_version)
            version.update(markers)
            path.write_text(json.dumps(version))
            receipt = json.loads(original_receipt)
            receipt['files']['version.json'] = {
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'bytes': path.stat().st_size,
            }
            receipt['artifact_manifest_sha256'] = hashlib.sha256(json.dumps(
                receipt['files'], sort_keys=True, separators=(',', ':')).encode()).hexdigest()
            self.receipt.write_text(json.dumps(receipt))
            self.assertIs(version['source_dirty'], False)
            self.assertEqual(version['source_commit'], self.commit)
            with self.subTest(markers=markers), self.assertRaises(ValueError):
                candidate.verify(self.build, self.receipt, self.commit, self.root)
        path.write_bytes(original_version)
        self.receipt.write_bytes(original_receipt)

    def test_supabase_self_consistent_wrong_project_or_qualification_claim_is_rejected(self):
        self.supabase_receipt()
        path = self.build / 'version.json'
        original_version = path.read_bytes()
        original_receipt = self.receipt.read_bytes()
        for key,value in [('supabase_project_ref','another-project'),('supabase_qualification_complete',True),
                          ('supabase_schema_sha256','0'*64),('legacy_data_import_required',False)]:
            version=json.loads(original_version);version[key]=value;path.write_text(json.dumps(version))
            receipt=json.loads(original_receipt)
            receipt['files']['version.json']={'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size}
            receipt['artifact_manifest_sha256']=hashlib.sha256(json.dumps(receipt['files'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
            self.receipt.write_text(json.dumps(receipt))
            with self.subTest(key=key),self.assertRaises(ValueError):
                candidate.verify(self.build,self.receipt,self.commit,self.root,backend='supabase')
        path.write_bytes(original_version);self.receipt.write_bytes(original_receipt)


if __name__ == '__main__':
    unittest.main()

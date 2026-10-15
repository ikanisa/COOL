"""Adversarial local release gates against real source/artifact verifiers.

Synthetic sealed files exercise preflight decisions; they are not Flutter builds,
hosted/provider/device evidence or release authorization. No external tools run.
"""
from contextlib import redirect_stdout
from copy import deepcopy
import hashlib
from io import StringIO
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import admin_cloudflare_source as source
import admin_cloudflare_artifact as artifact
import admin_cloudflare_preflight as preflight


HEADERS = """/*
  X-Frame-Options: DENY
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer
  X-Robots-Tag: noindex, nofollow
  Content-Security-Policy: default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; font-src 'self' data:; connect-src 'self'; manifest-src 'self'; worker-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'; upgrade-insecure-requests
/
  Cache-Control: no-store
/index.html
  Cache-Control: no-store
/flutter_bootstrap.js
  Cache-Control: no-cache
/custom-sw.js
  Cache-Control: no-cache
/flutter_service_worker.js
  Cache-Control: no-cache
/main.dart.js
  Cache-Control: no-cache
/version.json
  Cache-Control: no-cache
"""


class PreflightTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        # macOS exposes /var through a system symlink. Fixtures supply its real
        # /private/var location; production input links remain rejected.
        self.root = Path(self.temporary.name).resolve()
        self.build = self.root / 'build/admin-cloudflare'
        self.source_manifest = self.root / 'build/admin-cloudflare-source.json'
        self.artifact_manifest = self.root / 'build/admin-cloudflare-artifact.json'
        self.config_path = self.root / 'deploy/admin.cloudflare.wrangler.jsonc'
        self.target = 'https://admin-preview.collect.ikanisa.com'
        for name in source.SOURCE_DIRS:
            (self.root / name).mkdir(parents=True, exist_ok=True)
        for name in source.SOURCE_FILES:
            self.write(name, 'fixture source input\n')
        self.write('pubspec.yaml', 'name: collect_app\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n')
        self.write('deploy/admin-api/src/worker.mjs', 'export default {fetch() {}};\n')
        self.write('deploy/admin-api/src/observability.mjs',
                   (SCRIPTS.parent / 'deploy/admin-api/src/observability.mjs').read_text())
        self.write('scripts/templates/admin_cloudflare_retirement_worker.js',
                   (SCRIPTS / 'templates/admin_cloudflare_retirement_worker.js').read_text())
        self.write('deploy/admin-api/migrations/' + preflight.MINIMUM_MIGRATION, 'CREATE TABLE fixture(id TEXT);\n')
        self.config = {
            'name': 'collect-admin-cloudflare', 'account_id': preflight.ACCOUNT_ID,
            'main': 'admin-api/src/worker.mjs', 'workers_dev': False, 'preview_urls': False,
            'routes': [{'pattern': 'admin-preview.collect.ikanisa.com', 'custom_domain': True}],
            'vars': {'ADMIN_ORIGIN': self.target, 'ENVIRONMENT': 'production', 'GATEWAY_ALLOWED_IDENTITIES': '[]'},
            'd1_databases': [{'binding': 'ADMIN_DB', 'database_name': 'collect-admin-accounts',
                              'database_id': preflight.DATABASE_ID, 'migrations_dir': 'admin-api/migrations'}],
            'r2_buckets': [{'binding': key, 'bucket_name': value} for key, value in preflight.PRIVATE_BUCKETS.items()],
            'send_email': [{'name': 'EMAIL', 'allowed_sender_addresses': ['info@ikanisa.com']}],
            'assets': {'directory': '../build/admin-cloudflare', 'binding': 'ASSETS',
                       'not_found_handling': 'single-page-application',
                       'run_worker_first': ['/api/admin/*', '/api/gateway', '/api/gateway/*']},
            'observability': {'enabled': True, 'redact_query_string': True,
                              'logs': {'enabled': True, 'invocation_logs': False}},
        }
        self.config_path.write_text(json.dumps(self.config))
        self.build.mkdir(parents=True, exist_ok=True)
        self.output('main.dart.js', 'console.info("synthetic emitted main");\n')
        self.output('index.html', '<base href="./"><script src="flutter_bootstrap.js" async></script>')
        template = (SCRIPTS.parent / 'web/flutter_bootstrap.js').read_text()
        bootstrap = template.replace('{{flutter_js}}', '// synthetic loader fixture')
        bootstrap = bootstrap.replace('{{flutter_build_config}}',
                                      '_flutter.buildConfig = {"useLocalCanvasKit":true,"builds":[{"mainJsPath":"main.dart.js"}]};')
        self.output('flutter_bootstrap.js', bootstrap.replace('__COLLECT_ADMIN_ASSET_BASE__', './'))
        self.output('_headers', HEADERS)
        self.output('robots.txt', 'User-agent: *\nDisallow: /\n')
        local_font = {'asset': 'assets/typefaces/Inter-Variable.ttf'}
        self.output('assets/FontManifest.json', json.dumps([
            {'family': 'Inter', 'fonts': [local_font]},
            {'family': 'Roboto', 'fonts': [local_font]},
        ]))
        self.output('assets/assets/typefaces/Inter-Variable.ttf', 'synthetic local font fixture')
        self.output('assets/AssetManifest.bin', 'fixture')
        self.output('assets/AssetManifest.bin.json', '{}')
        retirement = (SCRIPTS / 'templates/admin_cloudflare_retirement_worker.js').read_text()
        self.output('custom-sw.js', retirement)
        self.output('flutter_service_worker.js', retirement)
        self.version = {'backend': 'cloudflare', 'source_release_status': artifact.CANDIDATE_STATUS,
                        'operational_migration_complete': False, 'offline_account_data_available': False,
                        'minimum_core_schema_migration': preflight.MINIMUM_MIGRATION}
        self.seal()

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def output(self, name, content):
        return self.write('build/admin-cloudflare/' + name, content)

    def seal(self):
        self.config_path.write_text(json.dumps(self.config))
        value = source.inputs(self.root, dependency_roots=[])
        value.update(source_commit='a' * 40, source_dirty=True)
        source.write_json(self.source_manifest, value)
        self.version.update({key: value[key] for key in ('source_commit', 'source_dirty', 'source_manifest_sha256')})
        self.version['main_dart_js_sha256'] = hashlib.sha256((self.build / 'main.dart.js').read_bytes()).hexdigest()
        self.output('version.json', json.dumps(self.version))
        artifact.record_artifact(self.build, self.source_manifest, self.artifact_manifest)

    def report(self, **kwargs):
        arguments = dict(build_root=self.build, source_manifest=self.source_manifest,
                         artifact_manifest=self.artifact_manifest, config=self.config_path,
                         target_origin=self.target, source_root=self.root)
        arguments.update(kwargs)
        return preflight.evaluate_preflight(**arguments)

    def failed(self, report, key):
        self.assertEqual('fail', report['local_status'], report)
        self.assertTrue(any(item['key'] == key and item['status'] == 'fail'
                            for item in report['local_checks']), report)
        self.assertFalse(report['release_admissible'])
        self.assertEqual(1, preflight.preflight_exit_code(report))

    def test_sealed_candidate_pass_is_never_hosted_or_release_acceptance(self):
        report = self.report()
        self.assertEqual('pass', report['local_status'], report)
        self.assertEqual(0, preflight.preflight_exit_code(report))
        self.assertFalse(report['release_admissible'])
        self.assertFalse(report['hosted_acceptance_verified'])
        self.assertFalse(report['compiler_dependency_resolution_verified'])
        self.assertEqual('unaccepted', report['identity_policy']['status'])
        self.assertEqual('unverified', report['private_storage']['hosted_privacy_status'])
        self.assertEqual([key for key, _, _ in preflight.HOSTED_GATES], [gate['key'] for gate in report['hosted_gates']])
        self.assertTrue(all(gate['status'] == 'unverified' for gate in report['hosted_gates']))

    def test_release_refuses_even_matching_candidate_and_invented_attestation(self):
        self.config['release_admissible'] = True
        self.config['hosted_acceptance_verified'] = True
        self.seal()
        report = self.report(release=True)
        self.assertEqual('pass', report['local_status'], report)
        self.assertEqual(99, preflight.preflight_exit_code(report))
        self.assertFalse(report['release_admissible'])
        self.assertIn('Authoritative external acceptance', report['release_refusal'])

    def test_post_build_verification_never_runs_tools_or_network(self):
        with patch('subprocess.run', side_effect=AssertionError('no tools')), \
                patch('subprocess.check_output', side_effect=AssertionError('no tools')), \
                patch('socket.socket', side_effect=AssertionError('no network')):
            self.assertEqual('pass', self.report()['local_status'])

    def test_source_drift_and_new_input_fail_real_closure_verifier(self):
        self.write('lib/new_current_input.dart', 'changed\n')
        self.failed(self.report(), 'frozen_source')

    def test_output_tamper_or_unsealed_extra_file_fails_real_artifact_verifier(self):
        self.output('main.dart.js', 'tampered')
        self.failed(self.report(), 'exact_artifact')
        self.seal()
        self.output('unsealed.js', 'extra output')
        self.failed(self.report(), 'exact_artifact')

    def test_manifest_digest_traversal_and_duplicate_records_fail(self):
        baseline = json.loads(self.source_manifest.read_text())
        for change in ('digest', 'traversal', 'duplicate'):
            with self.subTest(change=change):
                value = deepcopy(baseline)
                if change == 'digest':
                    value['source_manifest_sha256'] = '0' * 64
                elif change == 'traversal':
                    value['files'][0]['path'] = '../escape'
                else:
                    value['files'].append(value['files'][-1])
                self.source_manifest.write_text(json.dumps(value))
                self.failed(self.report(), 'frozen_source')
        self.source_manifest.write_text(json.dumps(baseline))

    def test_linked_input_and_build_ancestor_are_rejected(self):
        alias = self.root / 'source-link.json'
        alias.symlink_to(self.source_manifest)
        self.failed(self.report(source_manifest=alias), 'physical_inputs')
        build_alias = self.root / 'build-link'
        build_alias.symlink_to(self.build.parent, target_is_directory=True)
        self.failed(self.report(build_root=build_alias / self.build.name), 'physical_inputs')

    def test_noncanonical_targets_never_echo_credentials(self):
        for target in ('https://user:SECRET@example.com', self.target + '/', self.target + '?token=SECRET',
                       'http://admin-preview.collect.ikanisa.com', self.target + ':443', '//example.com'):
            with self.subTest(target=target):
                report = self.report(target_origin=target)
                self.failed(report, 'target_origin')
                self.assertNotIn('SECRET', json.dumps(report))

    def test_custom_domain_admin_origin_and_target_must_all_match(self):
        self.config['routes'][0]['pattern'] = 'admin.collect.ikanisa.com'
        self.seal()
        self.failed(self.report(), 'custom_domain_origin')
        self.config['routes'][0]['pattern'] = 'admin-preview.collect.ikanisa.com'
        self.config['vars']['ADMIN_ORIGIN'] = 'https://admin.collect.ikanisa.com'
        self.seal()
        self.failed(self.report(), 'custom_domain_origin')

    def test_assets_wrong_directory_binding_or_api_precedence_are_rejected(self):
        baseline = deepcopy(self.config['assets'])
        for key, value in (('directory', '../build/web'), ('binding', 'PUBLIC_ASSETS'),
                           ('run_worker_first', ['/api/admin/*'])):
            with self.subTest(key=key):
                self.config['assets'] = dict(baseline, **{key: value})
                self.seal()
                self.failed(self.report(), 'assets_binding_path')

    def test_exact_account_database_and_binding_prevent_lookalike_targets(self):
        self.config['account_id'] = 'b' * 32
        self.seal()
        self.failed(self.report(), 'configuration_source_binding')
        self.config['account_id'] = preflight.ACCOUNT_ID
        for field, value in (('binding', 'DB'), ('database_id', '11111111-1111-4111-8111-111111111111'),
                             ('database_name', 'collect-admin-accounts-copy')):
            with self.subTest(field=field):
                self.config['d1_databases'][0][field] = value
                self.seal()
                self.failed(self.report(), 'database_migration_binding')

    def test_stale_minimum_migration_fails_even_consistent_artifact(self):
        old = '0007_email_only_dispatch.sql'
        self.write('deploy/admin-api/migrations/' + old, 'CREATE TABLE older(id TEXT);')
        self.version['minimum_core_schema_migration'] = old
        self.seal()
        self.failed(self.report(), 'database_migration_binding')

    def test_minimum_migration_missing_after_freeze_fails_closed(self):
        (self.root / 'deploy/admin-api/migrations' / preflight.MINIMUM_MIGRATION).unlink()
        self.failed(self.report(), 'frozen_source')

    def test_private_bucket_identity_and_public_exposure_options_fail(self):
        self.config['r2_buckets'][0]['public_url'] = 'https://public.example.com'
        self.seal()
        self.failed(self.report(), 'private_payload_bindings')
        del self.config['r2_buckets'][0]['public_url']
        self.config['r2_buckets'][1]['bucket_name'] = 'collect-public-assets'
        self.seal()
        self.failed(self.report(), 'private_payload_bindings')

    def test_wrong_or_broad_email_sender_fails(self):
        self.config['send_email'][0]['allowed_sender_addresses'].append('other@example.com')
        self.seal()
        self.failed(self.report(), 'email_sender')

    def test_narrow_gateway_pairs_are_configured_but_never_live_accepted(self):
        pair = {'app_id': 'app.cool.mobile.gateway', 'signing_certificate_sha256': 'a' * 64}
        self.config['vars']['GATEWAY_ALLOWED_IDENTITIES'] = json.dumps([pair])
        self.seal()
        report = self.report()
        self.assertEqual('pass', report['local_status'], report)
        self.assertEqual('configured_not_hosted_accepted', report['identity_policy']['status'])
        self.assertFalse(report['identity_policy']['hosted_acceptance_verified'])
        self.assertNotIn(pair['signing_certificate_sha256'], json.dumps(report))
        for invalid in ([pair, pair], [dict(pair, app_id='*')], [dict(pair, signing_certificate_sha256='*')],
                        [dict(pair, signing_certificate_sha256='A' * 64)], {'approved': True}):
            with self.subTest(invalid=invalid):
                self.config['vars']['GATEWAY_ALLOWED_IDENTITIES'] = json.dumps(invalid)
                self.seal()
                self.failed(self.report(), 'gateway_identity_policy')

    def test_observability_requires_redaction_no_invocation_and_closed_logger(self):
        self.config['observability']['logs']['invocation_logs'] = True
        self.seal()
        self.failed(self.report(), 'redacted_observability')
        self.config['observability']['logs']['invocation_logs'] = False
        self.write('deploy/admin-api/src/worker.mjs', 'console.error(request);\n')
        self.seal()
        self.failed(self.report(), 'redacted_observability')
        self.assertNotIn('request', json.dumps(self.report()).split('local_checks')[0])

    def test_thirdparty_or_duplicate_csp_and_account_cache_escape_fail(self):
        for headers in (HEADERS.replace("connect-src 'self'", "connect-src 'self' https://external.example.com"),
                        HEADERS.replace("object-src 'none'", "connect-src *; object-src 'none'"),
                        HEADERS + '/api/admin/*\n  Cache-Control: public, max-age=600\n'):
            with self.subTest(headers=headers):
                self.output('_headers', headers)
                self.seal()
                self.failed(self.report(), 'same_origin_no_offline_accounts')

    def test_retired_supabase_and_activated_offline_worker_fail(self):
        self.output('main.dart.js', 'fetch("https://retired.supabase.co/rest/v1");')
        self.seal()
        self.failed(self.report(), 'same_origin_no_offline_accounts')
        self.output('main.dart.js', 'synthetic clean main')
        bootstrap = (self.build / 'flutter_bootstrap.js').read_text()
        self.output('flutter_bootstrap.js', bootstrap.replace('__COLLECT_ADMIN_SW_VERSION__', 'active-version'))
        self.seal()
        self.failed(self.report(), 'same_origin_no_offline_accounts')

    def test_engine_fallback_requires_exact_local_inter_alias(self):
        for fonts in ([], [{'family': 'Inter', 'fonts': [{'asset': 'assets/typefaces/Inter-Variable.ttf'}]}],
                      [{'family': 'Inter', 'fonts': [{'asset': 'assets/typefaces/Inter-Variable.ttf'}]},
                       {'family': 'Roboto', 'fonts': [{'asset': 'https://external.example/font.ttf'}]}]):
            with self.subTest(fonts=fonts):
                self.output('assets/FontManifest.json', json.dumps(fonts))
                self.seal()
                self.failed(self.report(), 'same_origin_no_offline_accounts')

    def test_inert_compiler_worker_parameter_is_not_an_enabled_app_worker(self):
        bootstrap = (self.build / 'flutter_bootstrap.js').read_text()
        compiler = 'class Loader { async load({serviceWorkerSettings:e,...rest}) {} }\n'
        self.output('flutter_bootstrap.js', compiler + bootstrap)
        self.seal()
        self.assertEqual('pass', self.report()['local_status'])
        self.output('flutter_bootstrap.js', compiler + bootstrap.replace(
            '_flutter.loader.load({',
            '_flutter.loader.load({serviceWorkerSettings:{serviceWorkerVersion:"enabled"},'))
        self.seal()
        self.failed(self.report(), 'same_origin_no_offline_accounts')

    def test_workers_must_equal_frozen_retirement_not_fetch_cache_code(self):
        for name in ('custom-sw.js', 'flutter_service_worker.js'):
            with self.subTest(name=name):
                self.output(name, "self.addEventListener('fetch', e => caches.open('accounts'));")
                self.seal()
                self.failed(self.report(), 'same_origin_no_offline_accounts')
                self.output(name, (SCRIPTS / 'templates/admin_cloudflare_retirement_worker.js').read_text())

    def test_both_retirement_update_urls_require_mutable_cache_fences(self):
        for route in ('/custom-sw.js', '/flutter_service_worker.js'):
            with self.subTest(route=route):
                self.output('_headers', HEADERS.replace(
                    route + '\n  Cache-Control: no-cache\n',
                    route + '\n  Cache-Control: public, max-age=31536000, immutable\n'))
                self.seal()
                self.failed(self.report(), 'same_origin_no_offline_accounts')

    def test_jsonc_comments_preserve_urls_and_duplicate_keys_fail(self):
        text = json.dumps(self.config)
        self.config_path.write_text('// local config\n' + text[:-1] + ', /* trailing */ }')
        value = source.inputs(self.root, dependency_roots=[])
        value.update(source_commit='a' * 40, source_dirty=True)
        source.write_json(self.source_manifest, value)
        self.version.update({key: value[key] for key in ('source_commit', 'source_dirty', 'source_manifest_sha256')})
        self.output('version.json', json.dumps(self.version))
        artifact.record_artifact(self.build, self.source_manifest, self.artifact_manifest)
        self.assertEqual('pass', self.report()['local_status'])
        self.config_path.write_text('{"vars":{},"vars":{"password":"SECRET"}}')
        report = self.report()
        self.failed(report, 'configuration_jsonc')
        self.assertNotIn('SECRET', json.dumps(report))

    def test_malformed_config_shapes_fail_closed_with_all_hosted_gates(self):
        for value in ([], {'vars': []}, {'vars': None}):
            with self.subTest(value=value):
                self.config_path.write_text(json.dumps(value))
                # Shape is evaluated only after byte identity succeeds.
                frozen = source.inputs(self.root, dependency_roots=[])
                frozen.update(source_commit='a' * 40, source_dirty=True)
                source.write_json(self.source_manifest, frozen)
                self.version.update({key: frozen[key] for key in ('source_commit', 'source_dirty', 'source_manifest_sha256')})
                self.output('version.json', json.dumps(self.version))
                artifact.record_artifact(self.build, self.source_manifest, self.artifact_manifest)
                report = self.report(release=True)
                self.assertEqual('fail', report['local_status'])
                self.assertEqual(99, preflight.preflight_exit_code(report))
                self.assertEqual(6, len(report['hosted_gates']))

    def test_cli_writes_bounded_report_and_refuses_release_without_mutating_inputs(self):
        before = {path: path.read_bytes() for path in (self.source_manifest, self.artifact_manifest, self.config_path)}
        destination = self.root / '.cache/preflight.json'
        args = ['--build-root', str(self.build), '--source-manifest', str(self.source_manifest),
                '--artifact-manifest', str(self.artifact_manifest), '--config', str(self.config_path),
                '--target-origin', self.target, '--output', str(destination)]
        with redirect_stdout(StringIO()):
            self.assertEqual(0, preflight.main(args, source_root=self.root))
            self.assertEqual(99, preflight.main(args + ['--release'], source_root=self.root))
        report = json.loads(destination.read_text())
        self.assertEqual('release', report['mode'])
        self.assertFalse(report['release_admissible'])
        self.assertEqual(before, {path: path.read_bytes() for path in before})

    def test_cli_refuses_output_inside_source_build_or_unrelated_file(self):
        for destination in (self.build / 'new-report.json', self.root / 'lib/new-report.json', self.config_path):
            with self.subTest(destination=destination):
                with self.assertRaises(ValueError):
                    preflight._write_report(destination, self.report(), [self.build, self.root / 'lib', self.config_path])
                if destination != self.config_path:
                    self.assertFalse(destination.exists())
        unrelated = self.root / '.cache/unrelated.json'
        unrelated.parent.mkdir()
        unrelated.write_text('[]')
        with self.assertRaises(ValueError):
            preflight._write_report(unrelated, self.report(), [])
        self.assertEqual('[]', unrelated.read_text())


if __name__ == '__main__':
    unittest.main()

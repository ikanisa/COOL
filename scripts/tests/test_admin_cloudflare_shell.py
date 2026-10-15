"""Public shell generator contracts; no compiler, browser, provider or network."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import admin_cloudflare_shell as shell


class ShellTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        self.build = Path(temp.name).resolve()
        self.template = SCRIPTS / 'templates/admin_cloudflare_shell_worker.js'
        for name, body in {'index.html': '<title>Collect Admin</title>', 'main.dart.js': 'public JS',
                           'flutter_bootstrap.js': '_flutter.buildConfig = {"builds":[{"renderer":"canvaskit"}]};', 'manifest.json': '{}',
                           'version.json': json.dumps({'offline_shell_available': True, 'offline_account_data_available': False}),
                           'assets/NOTICES': 'public licenses', 'assets/example.png': 'unused mobile artwork',
                           'assets/FontManifest.json': '[{"family":"Inter","fonts":[{"asset":"fonts/Inter.ttf"}]}]',
                           'assets/fonts/Inter.ttf': 'public font',
                           'assets/AssetManifest.bin': 'public runtime manifest',
                           'assets/AssetManifest.bin.json': '{}',
                           'assets/assets/brand/collect_runtime/app_icons/app-icon-rule.png': 'own logo',
                           'canvaskit/canvaskit.wasm': 'public engine', 'icons/icon.png': 'own public icon',
                           'api/admin/account.json': 'must not enter shell',
                           'custom-sw.js': 'retirement only', '_headers': 'server control only'}.items():
            p = self.build / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(body)
        for name in shell.ENGINE_FILES:
            p = self.build / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text('public renderer')

    def test_generated_allowlist_contains_only_known_public_paths_and_matches_bytes(self):
        data = shell.generate_shell(self.build, self.template)
        urls = {row['url'] for row in data['assets']}
        self.assertIn('./', urls); self.assertIn('./assets/fonts/Inter.ttf', urls)
        self.assertNotIn('./assets/example.png', urls)
        self.assertNotIn('./api/admin/account.json', urls)
        self.assertNotIn('./custom-sw.js', urls); self.assertNotIn('./_headers', urls)
        self.assertNotIn('./' + shell.WORKER, urls)
        self.assertEqual(data, shell.verify_shell(self.build, self.template))
        self.assertEqual(1, (self.build / 'flutter_bootstrap.js').read_text().count(shell.REGISTRATION))
        self.assertEqual(data, shell.generate_shell(self.build, self.template), 'generation is stable')

    def test_any_public_asset_change_or_worker_tamper_fails_verification(self):
        shell.generate_shell(self.build, self.template)
        (self.build / 'main.dart.js').write_text('new build')
        with self.assertRaisesRegex(ValueError, 'do not match'):
            shell.verify_shell(self.build, self.template)
        shell.generate_shell(self.build, self.template)
        (self.build / shell.WORKER).write_text('self.skipWaiting()')
        with self.assertRaisesRegex(ValueError, 'do not match'):
            shell.verify_shell(self.build, self.template)

    def test_new_assets_and_template_change_cache_identity_without_circular_hashing(self):
        original = shell.generate_shell(self.build, self.template)
        (self.build / 'icons/new.png').write_text('new public install icon')
        newer = shell.generate_shell(self.build, self.template)
        self.assertNotEqual(original['cache_name'], newer['cache_name'])
        changed = self.build / 'template.js'
        changed.write_bytes(self.template.read_bytes() + b'\n// Changed worker implementation\n')
        implementation = shell.generate_shell(self.build, changed)
        self.assertNotEqual(newer['cache_name'], implementation['cache_name'])

    def test_api_or_foreign_manifest_injection_cannot_match_generated_worker(self):
        data = shell.generate_shell(self.build, self.template)
        for url in ['./api/admin/auth/session', 'https://external.example/private']:
            injected = {**data, 'assets': [*data['assets'], {'url': url, 'sha256': hashlib.sha256(b'private').hexdigest()}]}
            (self.build / shell.MANIFEST).write_text(json.dumps(injected))
            with self.assertRaisesRegex(ValueError, 'do not match'):
                shell.verify_shell(self.build, self.template)

    def test_private_data_availability_is_never_enabled_by_shell_generation(self):
        (self.build / 'version.json').write_text(json.dumps({'offline_shell_available': True, 'offline_account_data_available': True}))
        with self.assertRaisesRegex(ValueError, 'distinct'):
            shell.generate_shell(self.build, self.template)

    def test_symlinked_asset_or_invalid_registration_is_rejected(self):
        linked = self.build / 'assets/linked.png'; linked.symlink_to(self.build / 'index.html')
        with self.assertRaisesRegex(ValueError, 'Linked'):
            shell.generate_shell(self.build, self.template)
        linked.unlink()
        (self.build / 'flutter_bootstrap.js').write_text('_flutter.buildConfig = {"builds":[{"renderer":"canvaskit"}]};\n// BEGIN COLLECT CLOUDFLARE PUBLIC SHELL tampered')
        with self.assertRaisesRegex(ValueError, 'registration'):
            shell.generate_shell(self.build, self.template)

    def test_unused_renderer_and_artwork_do_not_expand_the_offline_download(self):
        before = shell.generate_shell(self.build, self.template)
        for name in ['canvaskit/skwasm.wasm', 'canvaskit/experimental_webparagraph/canvaskit.wasm',
                     'assets/assets/photos/mobile.png', 'canvaskit/canvaskit.js.symbols']:
            p = self.build / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text('unused bytes')
        after = shell.generate_shell(self.build, self.template)
        self.assertEqual(before, after)
        bootstrap = self.build / 'flutter_bootstrap.js'
        bootstrap.write_text(bootstrap.read_text().replace('"renderer":"canvaskit"', '"renderer":"skwasm"'))
        with self.assertRaisesRegex(ValueError, 'renderer'):
            shell.generate_shell(self.build, self.template)


if __name__ == '__main__':
    unittest.main()

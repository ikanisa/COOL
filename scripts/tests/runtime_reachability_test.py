#!/usr/bin/env python3
"""Reachability regressions: conditional branches and evidence-only code survive."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'qa/runtime_reachability.py'
spec = importlib.util.spec_from_file_location('collect_reachability', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReachabilityTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        for name in ['test', 'tool', 'integration_test']:
            (self.root / name).mkdir()
        self.write('lib/main.dart', "import 'stub.dart'\n if (dart.library.html) 'web.dart';\nimport 'shared/models/collect_group_cover.dart';")
        self.write('lib/main_admin.dart', "import 'parts.dart';")
        self.write('lib/main_public.dart', "import 'stub.dart';")
        self.write('lib/main_gateway.dart', "import 'gateway/gateway_app.dart';")
        self.write('lib/gateway/gateway_app.dart', "import 'gateway_platform.dart';")
        self.write('lib/gateway/gateway_platform.dart', 'class GatewayPlatform {}')
        self.write('lib/stub.dart', 'class Stub {}')
        self.write('lib/web.dart', 'class Web {}')
        self.write('lib/parts.dart', "part 'child.dart';")
        self.write('lib/child.dart', "part of 'parts.dart';")
        self.write('lib/shared/models/collect_group_cover.dart', "String get asset => 'assets/group_covers/rwanda/covers/$id.webp';")
        self.write('pubspec.yaml', 'dependencies:\n  flutter: {sdk: flutter}\n  cupertino_icons: ^1.0.9\nflutter:\n  assets:\n    - assets/group_covers/rwanda/covers/one.webp\n    - assets/group_covers/rwanda/thumbs/one.webp\n')
        self.write('pubspec.lock', 'fixture')
        self.write('analysis_options.yaml', 'fixture')
        self.write('scripts/qa/runtime_reachability.py', SCRIPT.read_text())
        self.write('assets/group_covers/rwanda/catalog.v1.json', json.dumps({'assets': [{'id': 'one', 'planned_files': {'cover': 'assets/group_covers/rwanda/covers/one.webp', 'thumbnail': 'assets/group_covers/rwanda/thumbs/one.webp'}}]}))
        self.write('assets/group_covers/rwanda/covers/one.webp', 'synthetic fixture')
        self.write('assets/group_covers/rwanda/thumbs/one.webp', 'synthetic fixture')

    def tearDown(self):
        self.temp.cleanup()

    def write(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    def test_multiline_conditional_imports_and_parts_are_all_reachable(self):
        report = module.collect(self.root)
        self.assertEqual([], report['runtime_unreachable'])
        self.assertEqual([], report['missing_local_directives'])

    def test_evidence_only_helper_is_not_authorized_for_automatic_deletion(self):
        self.write('lib/evidence_helper.dart', 'class Helper {}')
        self.write('test/helper_test.dart', "import 'package:collect_app/evidence_helper.dart';")
        report = module.collect(self.root)
        self.assertEqual([{'path': 'lib/evidence_helper.dart', 'evidence_reachable': True, 'sha256': module.sha(self.root / 'lib/evidence_helper.dart')}], report['runtime_unreachable'])

    def test_missing_import_fails_closed(self):
        self.write('lib/stub.dart', "export 'missing.dart';")
        report = module.collect(self.root)
        self.assertEqual('fail', report['status'])
        self.assertEqual('missing_local_source', report['missing_local_directives'][0]['reason'])

    def test_existing_vendor_auth_fixture_is_evidence_reachable(self):
        self.write('third_party/gotrue/test/synthetic_jwt.dart', 'String jwt() => "synthetic";')
        self.write('test/auth_fixture_test.dart', "import '../third_party/gotrue/test/synthetic_jwt.dart';")
        report = module.collect(self.root)
        self.assertEqual([], report['missing_local_directives'])
        self.assertIn('third_party/gotrue/test/synthetic_jwt.dart', report['source_sha256'])

    def test_absent_vendor_auth_fixture_still_fails_closed(self):
        self.write('test/auth_fixture_test.dart', "import '../third_party/gotrue/test/missing.dart';")
        report = module.collect(self.root)
        self.assertEqual('fail', report['status'])
        self.assertEqual('missing_local_source', report['missing_local_directives'][0]['reason'])

    def test_native_gateway_only_graph_is_a_declared_runtime_root(self):
        report = module.collect(self.root)
        self.assertIn('lib/main_gateway.dart', report['runtime_roots'])
        self.assertEqual([], report['runtime_unreachable'])
        self.assertEqual(report['runtime_source_count'], report['reachable_runtime_source_count'])

    def test_absent_declared_gateway_entrypoint_fails_closed(self):
        (self.root / 'lib/main_gateway.dart').unlink()
        report = module.collect(self.root)
        self.assertEqual('fail', report['status'])
        self.assertEqual(['lib/main_gateway.dart'], report['missing_runtime_roots'])

    def test_dynamic_allowlisted_assets_are_preserved(self):
        report = module.collect(self.root)
        self.assertEqual([], report['unresolved_bundled_assets'])
        self.assertTrue(all('runtime_catalog_allowlist' in row['reachability'] for row in report['assets']))

    def test_bundle_only_provenance_is_flagged_for_review(self):
        path = self.root / 'pubspec.yaml'
        path.write_text(path.read_text().replace('assets/group_covers/rwanda/covers/one.webp', 'assets/group_covers/rwanda/covers/'))
        self.write('assets/group_covers/rwanda/covers/PROMPTS.json', '{}')
        report = module.collect(self.root)
        self.assertEqual(['assets/group_covers/rwanda/covers/PROMPTS.json'], report['unresolved_bundled_assets'])

    def test_implicit_cupertino_font_dependency_is_preserved(self):
        row = next(row for row in module.collect(self.root)['dependencies'] if row['name'] == 'cupertino_icons')
        self.assertTrue(row['implicit_use'])
        self.assertFalse(row['removal_authorized'])


if __name__ == '__main__':
    unittest.main()

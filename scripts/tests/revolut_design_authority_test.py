#!/usr/bin/env python3
"""Regression checks for conflicting design references and authority drift."""
import copy
import hashlib
import importlib.util
import json
import struct
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    'authority', REPO / 'scripts/qa/revolut_design_authority.py'
)
authority = importlib.util.module_from_spec(spec)
spec.loader.exec_module(authority)


class AuthorityTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'repo'
        self.skill = Path(self.temp.name) / 'skill'
        self.root.mkdir()
        (self.skill / 'references').mkdir(parents=True)
        (self.skill / 'SKILL.md').write_text('Selected sole authority\n')
        self.adapter = json.loads(
            (REPO / 'docs/release/revolut-design/authority.json').read_text()
        )
        for relative, key in [('SKILL.md', 'authority_sha256')]:
            self.adapter[key] = hashlib.sha256(
                (self.skill / relative).read_bytes()
            ).hexdigest()
        self.write('AGENTS.md', '`revolut-design` is the sole design authority.\n')
        self.save_adapter()

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def save_adapter(self):
        self.write('docs/release/revolut-design/authority.json', json.dumps(self.adapter))

    def test_generated_cache_results_do_not_declare_a_product_authority(self):
        self.write('.cache/current/final-verification-inputs.json',
                   '{"design_authority":"pass"}')
        self.write('.cache/current/money-columns-proof.json',
                   '{"design_authority":"revolut-design@jean-bosco-skills current installed entrypoint"}')
        self.assertEqual('pass', authority.check(self.root, self.skill)['status'])

    def test_cache_instruction_documents_still_receive_authority_checks(self):
        self.write('.cache/current/AGENTS.md', '{"design_authority":"competing"}')
        self.assertEqual('fail', authority.check(self.root, self.skill)['status'])

    def test_saved_verification_status_is_evidence_and_preserves_other_checks(self):
        self.write('docs/evidence.json', '{"verification":{"design_authority":"passed"}}')
        self.assertEqual('pass', authority.check(self.root, self.skill)['status'])
        self.write('docs/evidence.json', '{"verification":{"design_authority":"passed"},"nested":{"design_authority":"competing"}}')
        self.assertIn('competing_reference_declarations_present',
                      authority.check(self.root, self.skill)['failures'])
        self.write('docs/evidence.json', '{"verification":{"design_authority":"competing"}}')
        self.assertEqual('fail', authority.check(self.root, self.skill)['status'])

    def test_clean_scope_never_claims_visual_acceptance(self):
        result = authority.check(self.root, self.skill)
        self.assertEqual('pass', result['status'])
        self.assertEqual('unverified', result['visual_acceptance'])

    def test_alternative_authority_fails(self):
        self.write('docs/rogue.json', '{"design_authority":"generated-mockup"}')
        self.assertIn('competing_reference_declarations_present',
                      authority.check(self.root)['failures'])

    @staticmethod
    def metadata_fixture():
        finder_info = bytes(32)
        resource_fork = b'{"design_authority":"competing"}'
        header = struct.pack('>II16sH', 0x00051607, 0x00020000, b'Mac OS X        ', 2)
        entries = struct.pack('>IIIIII', 9, 50, len(finder_info),
                              2, 50 + len(finder_info), len(resource_fork))
        return header + entries + finder_info + resource_fork

    def test_valid_appledouble_metadata_is_not_an_instruction(self):
        relative = 'docs/._authority.json'
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = self.metadata_fixture()
        path.write_bytes(payload)
        self.assertTrue(authority.appledouble_sidecar(path))
        result = authority.check(self.root)
        self.assertEqual('pass', result['status'])
        self.assertEqual([relative], result['ignored_appledouble_sidecars'])
        self.assertEqual('unverified', result['visual_acceptance'])
        self.assertEqual(payload, path.read_bytes())

    def test_metadata_name_does_not_exempt_utf8_reference(self):
        relative = 'docs/._rogue.json'
        self.write(relative, '{"design_authority":"competing"}')
        self.assertFalse(authority.appledouble_sidecar(self.root / relative))
        result = authority.check(self.root)
        self.assertEqual('fail', result['status'])
        self.assertEqual([], result['ignored_appledouble_sidecars'])
        self.assertIn(relative + ':design_authority', result['competing_declarations'])

    def test_binary_header_without_sidecar_name_keeps_reference_checks(self):
        relative = 'docs/authority.json'
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(self.metadata_fixture())
        self.assertFalse(authority.appledouble_sidecar(path))
        self.assertEqual('fail', authority.check(self.root)['status'])

    def test_malformed_sidecar_keeps_fail_closed_reference_checks(self):
        relative = 'docs/._malformed.json'
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        malformed = bytearray(self.metadata_fixture())
        struct.pack_into('>I', malformed, 30, 0)  # Entry data overlaps its header.
        path.write_bytes(malformed)
        self.assertFalse(authority.appledouble_sidecar(path))
        result = authority.check(self.root)
        self.assertEqual('fail', result['status'])
        self.assertEqual([], result['ignored_appledouble_sidecars'])
        self.assertIn(relative + ':design_authority', result['competing_declarations'])
        path.write_bytes(bytes(malformed[:10]) + b'\xff')
        self.assertFalse(authority.appledouble_sidecar(path))
        self.assertIn('unreadable_reference:' + relative,
                      authority.check(self.root)['failures'])

    def test_ignored_retired_export_is_not_missed(self):
        path = '.cache/export/docs/admin/ADMIN_DESIGN_QA_2026-09-03.md'
        self.write(path, 'Legacy generated benchmark')
        self.assertEqual([path], authority.check(self.root)['retired_references'])

    def inert_package_link(self):
        base = 'docs/release/preparation/negative-fixtures/attempt/test_package'
        self.write(base + '/external/pubspec.yaml', 'name: external\n')
        link = self.root / base / 'owned/pubspec.yaml'
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(link.parent.parent / 'external/pubspec.yaml')
        return link

    def test_cached_traversal_keeps_hidden_exports_and_prunes_only_existing_boundaries(self):
        self.write('.ignored-export/nested/notes.json',
                   '{"design_authority":"competing"}')
        self.write('build/design-qa.md', 'Generated build output')
        outside = Path(self.temp.name) / 'outside'
        outside.mkdir()
        (outside / 'design-qa.md').write_text('Outside directory alias')
        (self.root / 'docs/alias').symlink_to(outside, target_is_directory=True)
        result = authority.check(self.root, self.skill)
        self.assertIn('.ignored-export/nested/notes.json:design_authority',
                      result['competing_declarations'])
        self.assertEqual([], result['retired_references'])
        self.assertTrue((self.root / 'docs/alias').is_symlink())

    def test_approved_inert_fixture_accepts_restored_root_alias_identity(self):
        link = self.inert_package_link()
        alias = Path(self.temp.name) / 'restored-root'
        alias.symlink_to(self.root, target_is_directory=True)
        link.unlink()
        link.symlink_to(alias / link.parent.parent.relative_to(self.root) / 'external/pubspec.yaml')
        before = str(link.readlink())
        result = authority.check(self.root)
        self.assertEqual('pass', result['status'])
        self.assertEqual([link.relative_to(self.root).as_posix()], result['inert_package_fixture_links'])
        self.assertEqual(before, str(link.readlink()))
        self.assertEqual('unverified', result['visual_acceptance'])

    def test_inert_fixture_rejects_different_file_with_same_content(self):
        link = self.inert_package_link()
        self.write('docs/same-content.yaml', 'name: external\n')
        link.unlink()
        link.symlink_to(self.root / 'docs/same-content.yaml')
        result = authority.check(self.root)
        self.assertEqual('fail', result['status'])
        self.assertEqual([], result['inert_package_fixture_links'])

    def test_inert_fixture_rejects_alias_escape_and_file_link_chain(self):
        link = self.inert_package_link()
        outside = Path(self.temp.name) / 'outside.yaml'
        outside.write_text('name: external\n')
        link.unlink()
        link.symlink_to(outside)
        self.assertEqual('fail', authority.check(self.root)['status'])
        chain = self.root / 'docs/fixture-chain.yaml'
        chain.symlink_to(link.parent.parent / 'external/pubspec.yaml')
        link.unlink()
        link.symlink_to(chain)
        self.assertEqual('fail', authority.check(self.root)['status'])

    def test_design_skill_reintroduction_fails(self):
        self.write('docs/plan.md', 'Follow adaptive-product-design.')
        self.assertIn('competing_reference_declarations_present',
                      authority.check(self.root)['failures'])

    def test_skill_revision_drift_fails(self):
        for relative in ['SKILL.md']:
            with self.subTest(relative=relative):
                before = (self.skill / relative).read_text()
                (self.skill / relative).write_text('Changed without review')
                self.assertIn('authority_revision_changed:' + relative,
                              authority.check(self.root, self.skill)['failures'])
                (self.skill / relative).write_text(before)

    def test_platform_reference_cannot_be_redirected(self):
        self.adapter['surface_references']['admin'] = ['docs/mockup.md']
        self.save_adapter()
        self.assertIn('invalid_platform_reference_adapter',
                      authority.check(self.root)['failures'])

    def test_missing_surface_fails(self):
        saved = copy.deepcopy(self.adapter)
        for key, value, failure in [
            ('scope', ['member_app'], 'incomplete_surface_scope'),
        ]:
            with self.subTest(key=key):
                self.adapter = copy.deepcopy(saved)
                self.adapter[key] = value
                self.save_adapter()
                self.assertIn(failure, authority.check(self.root)['failures'])

    def test_product_evidence_and_toolkit_names_are_allowed(self):
        self.write('docs/evidence.md', 'Flutter Material/Cupertino controls. Historical widget capture.')
        self.write('docs/evidence.json', '{"design_authority":"revolut-design"}')
        self.assertEqual('pass', authority.check(self.root)['status'])

    def package_link_fixture(self):
        base = 'docs/release/evidence/negative-fixtures/attempt1/package-link'
        self.write(base + '/external/pubspec.yaml', 'name: external\n')
        link = self.root / base / 'owned/pubspec.yaml'
        link.parent.mkdir()
        link.symlink_to(link.parent.parent / 'external/pubspec.yaml')
        return link

    def test_retained_inert_package_refusal_link_preserves_evidence(self):
        link = self.package_link_fixture()
        result = authority.check(self.root)
        self.assertEqual('pass', result['status'])
        self.assertEqual([link.relative_to(self.root).as_posix()],
                         result['inert_package_fixture_links'])
        self.assertTrue(link.is_symlink())

    def test_fixture_link_with_design_declaration_still_fails(self):
        link = self.package_link_fixture()
        (link.parent.parent / 'external/pubspec.yaml').write_text(
            'name: external\ndesign_authority: competing\n')
        result = authority.check(self.root)
        self.assertEqual([], result['inert_package_fixture_links'])
        self.assertIn(link.relative_to(self.root).as_posix() + ':symlinked_reference',
                      result['competing_declarations'])

    def test_fixture_link_cannot_point_outside_its_physical_case(self):
        link = self.package_link_fixture()
        self.write('docs/outside.yaml', 'name: external\n')
        link.unlink()
        link.symlink_to(self.root / 'docs/outside.yaml')
        self.assertEqual('fail', authority.check(self.root)['status'])

    def test_normal_reference_link_has_no_fixture_exemption(self):
        self.write('docs/package/pubspec.yaml', 'name: external\n')
        link = self.root / 'docs/pubspec.yaml'
        link.symlink_to(self.root / 'docs/package/pubspec.yaml')
        self.assertEqual('fail', authority.check(self.root)['status'])

    def backend_link(self, payload='{"scope":"receipt_successor_approval"}'):
        name = 'successor_approval_read.json'
        self.write('test/fixtures/' + name, payload)
        link = self.root / '.cache/case/validation-app/test/fixtures' / name
        link.parent.mkdir(parents=True)
        link.symlink_to(self.root / 'test/fixtures' / name)
        return link

    def test_exact_backend_alias_is_retained_and_inspected(self):
        link = self.backend_link()
        result = authority.check(self.root)
        self.assertEqual('pass', result['status'])
        self.assertEqual([link.relative_to(self.root).as_posix()],
                         result['retained_backend_fixture_links'])
        self.assertTrue(link.is_symlink())
        self.assertEqual('unverified', result['visual_acceptance'])

    def test_backend_alias_does_not_hide_competing_declarations(self):
        self.backend_link('{"design_authority":"competing"}')
        self.assertEqual('fail', authority.check(self.root)['status'])

    def test_backend_alias_cannot_escape_or_chain(self):
        link = self.backend_link()
        self.write('docs/elsewhere.json', '{}')
        link.unlink()
        link.symlink_to(self.root / 'docs/elsewhere.json')
        self.assertEqual('fail', authority.check(self.root)['status'])
        original = self.root / 'test/fixtures' / link.name
        original.unlink()
        original.symlink_to(self.root / 'docs/elsewhere.json')
        link.unlink()
        link.symlink_to(original)
        self.assertEqual('fail', authority.check(self.root)['status'])

    def test_backend_alias_requires_finite_valid_object_and_known_name(self):
        link = self.backend_link()
        target = self.root / 'test/fixtures' / link.name
        for payload in ['not json', '[]', '{"padding":"' + 'x' * 65536 + '"}']:
            target.write_text(payload)
            self.assertEqual('fail', authority.check(self.root)['status'])
        target.write_text('{}')
        unknown = link.parent / 'design-reference.json'
        unknown.symlink_to(target)
        self.assertEqual('fail', authority.check(self.root)['status'])


if __name__ == '__main__':
    unittest.main()

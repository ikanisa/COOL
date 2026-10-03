#!/usr/bin/env python3
"""Regression checks for conflicting design references and authority drift."""
import copy
import hashlib
import importlib.util
import json
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

    def test_clean_scope_never_claims_visual_acceptance(self):
        result = authority.check(self.root, self.skill)
        self.assertEqual('pass', result['status'])
        self.assertEqual('unverified', result['visual_acceptance'])

    def test_alternative_authority_fails(self):
        self.write('docs/rogue.json', '{"design_authority":"generated-mockup"}')
        self.assertIn('competing_reference_declarations_present',
                      authority.check(self.root)['failures'])

    def test_ignored_retired_export_is_not_missed(self):
        path = '.cache/export/docs/admin/ADMIN_DESIGN_QA_2026-09-03.md'
        self.write(path, 'Legacy generated benchmark')
        self.assertEqual([path], authority.check(self.root)['retired_references'])

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

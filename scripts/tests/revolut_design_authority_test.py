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
        (self.skill / 'references/mobile-design-100.md').write_text('Mandatory acceptance\n')
        self.adapter = json.loads(
            (REPO / 'docs/release/revolut-design/authority.json').read_text()
        )
        for relative, key in [
            ('SKILL.md', 'authority_sha256'),
            ('references/mobile-design-100.md', 'mobile_acceptance_rule_sha256'),
        ]:
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

    def test_skill_and_acceptance_rule_revision_drift_fail(self):
        for relative in ['SKILL.md', 'references/mobile-design-100.md']:
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

    def test_missing_surface_or_mobile_rule_fails(self):
        saved = copy.deepcopy(self.adapter)
        for key, value, failure in [
            ('scope', ['member_app'], 'incomplete_surface_scope'),
            ('mobile_acceptance_rule', 'optional', 'missing_mobile_acceptance_rule'),
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


if __name__ == '__main__':
    unittest.main()

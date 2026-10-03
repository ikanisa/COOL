#!/usr/bin/env python3
"""Pure exact-admission fixtures. No Gradle, APP, process or cache action."""
import copy
import importlib.util
import json
from pathlib import Path
import types
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('probe_override_fixture', HERE / 'android_build_overlay.py')
OVERLAY = importlib.util.module_from_spec(spec)
spec.loader.exec_module(OVERLAY)
ORIGINAL = json.loads((HERE.parent / 'early-build-overlay-recovery4/reviewed-verification-plan.json').read_text())
REPLACEMENT = json.loads((HERE / 'reviewed-verification-plan.json').read_text())
SELECTED = json.loads((HERE / 'root-admission-template.json').read_text())['default_proguard_probe_override']


class ProbeOverrideFixtures(unittest.TestCase):
    def setUp(self):
        self.plan = copy.deepcopy(REPLACEMENT)
        self.selector = copy.deepcopy(SELECTED)
        self.original = copy.deepcopy(ORIGINAL)
        self.reads = []
        self.driver = types.SimpleNamespace(
            RELEASE=HERE.parents[1],
            APP=Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1/app-source'),
            document=lambda path, digest: self.reads.append(('plan', path, digest)) or self.plan,
            plain_read=lambda path, digest: self.reads.append(('init', path, digest)) or b'pure fixture',
        )

    def validate(self):
        return OVERLAY.validate_probe_override(self.driver, self.selector, self.original)

    def test_explicit_exact_override_changes_only_init_script_argument(self):
        self.assertEqual(self.validate(), REPLACEMENT)
        changed = [i for i, (before, after) in enumerate(zip(ORIGINAL['argv'], REPLACEMENT['argv'])) if before != after]
        self.assertEqual(changed, [ORIGINAL['argv'].index('--init-script') + 1])
        self.assertEqual(len(self.reads), 2)
        self.assertEqual(self.reads[0][1:], (SELECTED['plan']['path'], SELECTED['plan']['sha256']))
        self.assertEqual(self.reads[1][1:], (SELECTED['init_script']['path'], SELECTED['init_script']['sha256']))
        self.assertEqual(self.plan['deadline_seconds'], 300)

    def test_no_selector_preserves_original_plan_without_any_override_reads(self):
        self.assertEqual(OVERLAY.validate_probe_override(self.driver, None, self.original), ORIGINAL)
        self.assertEqual(self.reads, [])

    def test_wrong_plan_hash_is_refused_before_read(self):
        self.selector['plan']['sha256'] = '0' * 64
        with self.assertRaises(ValueError): self.validate()
        self.assertEqual(self.reads, [])

    def test_wrong_init_hash_is_refused_before_read(self):
        self.selector['init_script']['sha256'] = '0' * 64
        with self.assertRaises(ValueError): self.validate()
        self.assertEqual(self.reads, [])

    def test_another_script_path_is_refused_before_read(self):
        self.selector['init_script']['path'] = '/tmp/unreviewed-init.gradle'
        with self.assertRaises(ValueError): self.validate()
        self.assertEqual(self.reads, [])

    def test_extra_selector_key_is_refused(self):
        self.selector['optional_script'] = self.selector['init_script']
        with self.assertRaises(ValueError): self.validate()

    def test_extra_argument_is_refused(self):
        self.plan['argv'].insert(-1, '--rerun-tasks')
        with self.assertRaises(ValueError): self.validate()

    def test_changed_offline_flag_is_refused(self):
        self.plan['argv'][self.plan['argv'].index('--offline')] = '--refresh-dependencies'
        with self.assertRaises(ValueError): self.validate()

    def test_duplicate_init_script_is_refused(self):
        self.plan['argv'][-1:-1] = ['--init-script', SELECTED['init_script']['path']]
        with self.assertRaises(ValueError): self.validate()

    def test_changed_task_is_refused(self):
        self.plan['argv'][-1] = ':app:bundleProductionRelease'
        with self.assertRaises(ValueError): self.validate()

    def test_changed_cwd_is_refused(self):
        self.plan['cwd'] = str(HERE)
        with self.assertRaises(ValueError): self.validate()

    def test_changed_finite_bound_is_refused(self):
        self.plan['deadline_seconds'] = 301
        with self.assertRaises(ValueError): self.validate()

    def test_additional_plan_metadata_is_refused(self):
        self.plan['skip_failure_guard'] = True
        with self.assertRaises(ValueError): self.validate()

    def test_original_plan_with_another_script_is_refused(self):
        self.original['argv'][self.original['argv'].index('--init-script') + 1] = '/tmp/other.gradle'
        with self.assertRaises(ValueError): self.validate()


if __name__ == '__main__':
    unittest.main(verbosity=2)

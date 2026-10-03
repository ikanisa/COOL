#!/usr/bin/env python3
"""Real synthetic source/index/path mutations; no real app, SDK or build execution."""
import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import types
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
FIXTURES = HERE / 'negative-fixtures/snapshot-attempt3'
ORIGINAL = HERE.parent / 'kotlin-sdk-native-consumer-preparation1'
REPO = HERE.parents[3]


def module(name):
    spec = importlib.util.spec_from_file_location('snapshot_test_' + name, HERE / (name + '.py'))
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


fence = module('source_fence')
controller = module('run_native_consumer')
exporter = fence.module(REPO / 'scripts/qa/collect_release_candidate.py', 'snapshot_test_exporter')


class SourceMutation(unittest.TestCase):
    def setUp(self):
        self.root = FIXTURES / self._testMethodName
        self.root.mkdir(parents=True, mode=0o700)
        self.source = self.root / 'source'
        self.source.mkdir(mode=0o700)
        self.git('init', '-q')
        self.git('config', 'user.email', 'synthetic@example.invalid')
        self.git('config', 'user.name', 'Synthetic Guard Fixture')
        for name in sorted(exporter.REQUIRED | {'scripts/qa/collect_release_candidate.py', '.gitignore'}):
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((REPO / name).read_bytes() if name == 'scripts/qa/collect_release_candidate.py' else
                             b'**/.cache/\n' if name == '.gitignore' else b'synthetic source fixture\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'Synthetic admission fixture')

    def git(self, *args):
        return subprocess.check_output(['/usr/bin/git', *args], cwd=self.source,
                                       env={'PATH': '/usr/bin:/bin', 'GIT_OPTIONAL_LOCKS': '0', 'LC_ALL': 'C'},
                                       stderr=subprocess.DEVNULL, timeout=20)

    def capture(self):
        return fence.capture(self.source, seconds=20)

    def reject_drift(self, before):
        with self.assertRaisesRegex(ValueError, 'drift'):
            fence.compare(before, self.capture())

    def test_exact_stable_source_capture_passes_without_held_claim(self):
        first = self.capture(); fence.compare(first, self.capture())
        self.assertFalse(first['source_scope_held_for_strict_export'])
        self.assertFalse(first['source_lock_attested'])
        self.assertFalse(first['transient_write_and_restore_absence_attested'])
        self.assertFalse(first['production_release_approval'])
        self.assertEqual(len(first['source_files_identity']), len(exporter.REQUIRED | {'scripts/qa/collect_release_candidate.py', '.gitignore'}))

    def test_same_bytes_atomic_replacement_restored_mtime_refused(self):
        before = self.capture(); path = self.source / 'lib/main.dart'; row = path.stat()
        temporary = path.with_suffix('.replacement'); temporary.write_bytes(path.read_bytes())
        os.utime(temporary, ns=(row.st_atime_ns, row.st_mtime_ns)); temporary.replace(path)
        self.reject_drift(before)

    def test_content_write_restore_and_mtime_restore_refused_by_ctime(self):
        before = self.capture(); path = self.source / 'lib/main.dart'; row = path.stat(); body = path.read_bytes()
        path.write_bytes(body + b'transient synthetic change'); path.write_bytes(body)
        os.utime(path, ns=(row.st_atime_ns, row.st_mtime_ns))
        self.reject_drift(before)

    def test_selected_byte_change_refused(self):
        before = self.capture(); (self.source / 'lib/main.dart').write_bytes(b'changed bytes\n')
        self.reject_drift(before)

    def test_selected_mode_change_refused(self):
        before = self.capture(); (self.source / 'lib/main.dart').chmod(0o600)
        self.reject_drift(before)

    def test_untracked_selected_membership_change_refused(self):
        before = self.capture(); (self.source / 'lib/added.dart').write_bytes(b'new source\n')
        self.reject_drift(before)

    def test_missing_indexed_file_reappearance_refused(self):
        path = self.source / 'lib/absent.dart'; path.write_bytes(b'indexed original\n'); self.git('add', 'lib/absent.dart')
        path.unlink(); before = self.capture(); path.write_bytes(b'indexed original\n')
        self.reject_drift(before)

    def test_excluded_upstream_fixture_change_refused(self):
        path = self.source / 'third_party/fork/test/auth_fixture.dart'; path.parent.mkdir(parents=True)
        path.write_bytes(b'excluded fixture original\n'); before = self.capture()
        self.assertIn('third_party/fork/test/auth_fixture.dart', before['excluded_upstream_fixture_identity'])
        path.write_bytes(b'excluded fixture changed\n'); self.reject_drift(before)

    def test_excluded_upstream_fixture_indexed_absence_change_refused(self):
        path = self.source / 'third_party/fork/test/absent.dart'; path.parent.mkdir(parents=True)
        path.write_bytes(b'fixture original\n'); self.git('add', 'third_party/fork/test/absent.dart')
        path.unlink(); before = self.capture(); path.write_bytes(b'fixture original\n'); self.reject_drift(before)

    def test_ignored_cache_is_outside_selected_source_fence(self):
        before = self.capture(); path = self.source / 'lib/.cache/ignored'
        path.parent.mkdir(); path.write_bytes(b'ignored cache generation\n')
        fence.compare(before, self.capture())

    def test_git_index_identity_change_refused_without_payload_change(self):
        before = self.capture(); self.git('update-index', '--assume-unchanged', 'lib/main.dart')
        self.reject_drift(before)

    def test_head_commit_change_refused(self):
        before = self.capture(); self.git('commit', '--allow-empty', '-qm', 'Synthetic concurrent commit')
        self.reject_drift(before)

    def test_selected_hardlink_refused(self):
        path = self.source / 'lib/main.dart'; os.link(path, self.root / 'hardlink')
        with self.assertRaisesRegex(ValueError, 'exclusive safe regular'):
            self.capture()

    def test_source_parent_symlink_refused(self):
        path = self.source / 'lib'; alternate = self.root / 'lib-alternate'; path.rename(alternate); path.symlink_to(alternate)
        with self.assertRaises(ValueError):
            self.capture()

    def test_index_symlink_refused(self):
        path = self.source / '.git/index'; alternate = self.root / 'index-alternate'; path.rename(alternate); path.symlink_to(alternate)
        with self.assertRaisesRegex(ValueError, 'link ancestor'):
            self.capture()

    def test_exporter_tamper_refused_before_loading_modified_module(self):
        path = self.source / 'scripts/qa/collect_release_candidate.py'; path.write_text('raise RuntimeError("unreviewed executable")\n')
        with self.assertRaisesRegex(ValueError, 'reviewed strict exporter bytes'):
            self.capture()

    def test_source_fence_deadline_and_headroom_refused(self):
        with self.assertRaisesRegex(ValueError, 'deadline'):
            fence.capture(self.source, seconds=0)
        with self.assertRaisesRegex(ValueError, 'headroom'):
            fence.capture(self.source, floor=2**63)

    def test_in_capture_source_mutation_refused(self):
        real_stable = fence.stable; changed = False
        def mutate(path):
            nonlocal changed
            result = real_stable(path)
            if Path(path) == self.source / 'lib/main.dart' and not changed:
                changed = True; Path(path).write_bytes(b'concurrent synthetic mutation\n')
            return result
        with mock.patch.object(fence, 'stable', mutate), self.assertRaisesRegex(ValueError, 'during capture'):
            self.capture()

    def test_capture_cli_and_exact_binding_verify_write_exclusive_evidence(self):
        binding = self.root / 'source-fence.json'; output = self.root / 'verified.json'
        with mock.patch('sys.argv', ['source_fence.py', 'capture', '--root', str(self.source), '--output', str(binding)]):
            self.assertEqual(fence.main(), 0)
        digest = hashlib.sha256(binding.read_bytes()).hexdigest()
        with mock.patch('sys.argv', ['source_fence.py', 'verify', '--root', str(self.source), '--binding', str(binding),
                                    '--binding-sha256', digest, '--output', str(output)]):
            self.assertEqual(fence.main(), 0)
        self.assertEqual(binding.read_bytes(), output.read_bytes())
        with mock.patch('sys.argv', ['source_fence.py', 'capture', '--root', str(self.source), '--output', str(output)]), self.assertRaisesRegex(ValueError, 'absent'):
            fence.main()

    def test_wrong_binding_hash_refused_without_pass_evidence(self):
        binding = self.root / 'source-fence.json'; fence.save(binding, self.capture()); output = self.root / 'refused.json'
        with mock.patch('sys.argv', ['source_fence.py', 'verify', '--root', str(self.source), '--binding', str(binding),
                                    '--binding-sha256', '0'*64, '--output', str(output)]), self.assertRaisesRegex(ValueError, 'fence file changed'):
            fence.main()
        self.assertFalse(output.exists())

    def test_actual_capture_child_and_process_receipt_have_distinct_paths(self):
        output = self.root / 'source-fence-before-capture.json'
        command = [sys.executable, '-I', '-B', str(HERE/'source_fence.py'), 'capture',
                   '--root', str(self.source), '--output', str(output)]
        record = controller.run_process(self.root, 'source-fence-before', command, 20, HERE,
                                        {'PATH': '/usr/bin:/bin', 'GIT_OPTIONAL_LOCKS': '0', 'LC_ALL': 'C'})
        self.assertEqual(record['exit_code'], 0)
        self.assertTrue(record['owned_process_group_absent'])
        receipt = self.root / 'source-fence-before.json'
        self.assertEqual(json.loads(receipt.read_text())['argv'], command)
        self.assertEqual(json.loads(output.read_text())['kind'], 'strict_current_source_identity_fence')
        self.assertNotEqual(output, receipt)


class SnapshotAdmission(unittest.TestCase):
    def setUp(self):
        self.root = FIXTURES / self._testMethodName
        self.root.mkdir(parents=True, mode=0o700)
        self.auth = self.root / 'root-review'; self.auth.mkdir(mode=0o700)
        self.base = self.root / 'native'; self.base.mkdir(mode=0o700)
        self.app = self.base / 'app-source'
        self.binding = self.auth / 'source-fence.json'; self.binding.write_text('{}\n')
        prior = self.base / '.control/startup/terminal.json'; prior.parent.mkdir(parents=True)
        prior.write_text(json.dumps({'stage': 'startup', 'stage_pass': True}))
        self.document = {'errors': [], 'packet_manifest_sha256': '1'*64, 'checked_packet_leaves': 2,
                         'execution_stage_admissions': {'app-export': True}, 'current_source_export_authorized': True,
                         'strict_current_source_comparison_required': True, 'private_snapshot_exclusive': True,
                         'source_scope_held_for_strict_export': False, 'source_lock_attested': False,
                         'transient_write_and_restore_absence_attested': False,
                         'required_source_fence_sha256': hashlib.sha256(self.binding.read_bytes()).hexdigest(),
                         'required_predecessor_terminal_sha256': hashlib.sha256(prior.read_bytes()).hexdigest()}

    def authorize(self, stage='app-export', child=False):
        receipt = self.auth / (stage+'-admission.json'); receipt.write_text(json.dumps(self.document))
        args = argparse.Namespace(stage=stage, foundation_child=child, prepared_manifest_sha256='1'*64,
                                  root_review_sha256=hashlib.sha256(receipt.read_bytes()).hexdigest())
        with mock.patch.object(controller, 'AUTH_DIR', self.auth), mock.patch.object(controller, 'SOURCE_FENCE', self.binding), \
             mock.patch.object(controller, 'BASE', self.base), mock.patch.object(controller, 'packet', return_value={'files': {'a': 'x', 'b': 'y'}}) as packets:
            result = controller.authorization(args)
        self.assertEqual(packets.call_count, 4)
        return result

    def test_honest_strict_source_comparison_admission_passes(self):
        self.authorize()

    def test_source_lock_or_transient_absence_attestation_refused(self):
        for field in ('source_scope_held_for_strict_export', 'source_lock_attested', 'transient_write_and_restore_absence_attested'):
            with self.subTest(field=field):
                self.document[field] = True
                with self.assertRaisesRegex(ValueError, 'disclose absence'):
                    self.authorize()
                self.document[field] = False

    def test_required_comparison_and_private_destination_admission_missing_refused(self):
        for field in ('current_source_export_authorized', 'strict_current_source_comparison_required', 'private_snapshot_exclusive'):
            with self.subTest(field=field):
                self.document[field] = False
                with self.assertRaisesRegex(ValueError, 'strict snapshot admission'):
                    self.authorize()
                self.document[field] = True

    def test_wrong_or_missing_source_fence_digest_refused(self):
        for value in (None, '0'*64, 'invalid'):
            self.document['required_source_fence_sha256'] = value
            with self.assertRaisesRegex(ValueError, 'source identity/index/membership/fixture fence'):
                self.authorize()

    def test_actual_predecessor_mutation_refused(self):
        path = self.base / '.control/startup/terminal.json'; path.write_text(json.dumps({'stage': 'startup', 'stage_pass': False}))
        with self.assertRaisesRegex(ValueError, 'predecessor terminal'):
            self.authorize()

    def test_prior_or_next_stage_and_foundation_child_refused(self):
        for stage in ('foundation', 'sdk-lock', 'startup', 'app-lock', 'native'):
            with self.assertRaisesRegex(ValueError, 'only app-export'):
                self.authorize(stage=stage)
        with self.assertRaisesRegex(ValueError, 'only app-export'):
            self.authorize(child=True)

    def test_existing_or_symlink_candidate_destination_refused(self):
        fence.private_destination(self.app, self.base)
        self.app.mkdir(mode=0o700)
        with self.assertRaisesRegex(ValueError, 'must be absent'):
            fence.private_destination(self.app, self.base)
        self.app.rmdir(); self.app.symlink_to(self.root/'missing')
        with self.assertRaisesRegex(ValueError, 'must be absent'):
            fence.private_destination(self.app, self.base)

    def test_nonprivate_root_or_candidate_refused(self):
        self.base.chmod(0o755)
        with self.assertRaisesRegex(ValueError, 'owner-only mode'):
            fence.private_destination(self.app, self.base)
        self.base.chmod(0o700); self.app.mkdir(mode=0o755)
        with self.assertRaisesRegex(ValueError, 'remain private'):
            fence.private_candidate(self.app, self.base)

    def test_private_candidate_hardlink_and_symlink_refused(self):
        self.app.mkdir(mode=0o700); source = self.app/'source'; source.write_bytes(b'private synthetic snapshot\n')
        fence.private_candidate(self.app, self.base); os.link(source, self.root/'outside-alias')
        with self.assertRaisesRegex(ValueError, 'independently owned'):
            fence.private_candidate(self.app, self.base)
        (self.root/'outside-alias').unlink(); source.unlink(); source.symlink_to(self.root/'absent')
        with self.assertRaisesRegex(ValueError, 'safe regular'):
            fence.private_candidate(self.app, self.base)

    def test_exact_commands_preserved_and_drift_mode_or_deadline_mutation_refused(self):
        config = json.loads((HERE/'proposed-commands.json').read_text())
        validate = lambda: fence.validate_commands(config, ORIGINAL, HERE, REPO, controller.BASE,
                                                   controller.SDK, controller.APP, controller.AUTH_DIR)
        validate()
        config['commands']['app-export']['argv'].append('--retain-source-drift')
        with self.assertRaisesRegex(ValueError, 'invariant changed'):
            validate()
        config['commands']['app-export']['argv'].pop(); config['commands']['app-export']['deadline_seconds'] = 301
        with self.assertRaisesRegex(ValueError, 'invariant changed'):
            validate()

    def test_private_environment_or_resource_floor_mutation_refused(self):
        for field, value in (('live_free_floor_bytes', 0), ('minimum_free_bytes', 0),
                             ('environment_exact', {'PATH': '/usr/bin'}), ('Python_SHA256', '0'*64)):
            config = json.loads((HERE/'proposed-commands.json').read_text()); config[field] = value
            with self.assertRaisesRegex(ValueError, 'invariant changed'):
                fence.validate_commands(config, ORIGINAL, HERE, REPO, controller.BASE, controller.SDK, controller.APP, controller.AUTH_DIR)

    def test_preparation_packet_leaf_tamper_refused(self):
        packet = self.root/'packet'; packet.mkdir(); leaf = packet/'leaf'; leaf.write_bytes(b'exact leaf\n')
        manifest = packet/'packet-files.json'; manifest.write_text(json.dumps({'files': {'leaf': hashlib.sha256(leaf.read_bytes()).hexdigest()}}))
        expected = hashlib.sha256(manifest.read_bytes()).hexdigest(); controller.packet(packet, expected)
        leaf.write_bytes(b'tampered leaf\n')
        with self.assertRaisesRegex(ValueError, 'packet leaf changed'):
            controller.packet(packet, expected)

    def test_unexpected_configuration_or_nonadmission_flag_change_refused(self):
        for field, value in (('unreviewed_config', True), ('all_flavors_ABI_followthrough_open', False)):
            config = json.loads((HERE/'proposed-commands.json').read_text()); config[field] = value
            with self.assertRaisesRegex(ValueError, 'only declared snapshot admission fields'):
                fence.validate_commands(config, ORIGINAL, HERE, REPO, controller.BASE, controller.SDK, controller.APP, controller.AUTH_DIR)


if __name__ == '__main__':
    unittest.main(verbosity=2)

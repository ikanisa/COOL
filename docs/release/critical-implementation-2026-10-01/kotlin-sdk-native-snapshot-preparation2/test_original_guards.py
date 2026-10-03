#!/usr/bin/env python3
"""Real local rejection fixtures only; never run SDK/pub/Gradle or expand SDK."""
import hashlib
import importlib.util
import io
import json
import os
import stat
import types
import time
import subprocess
import sys
import unittest
import unittest.mock as mock
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent / 'kotlin-sdk-native-consumer-preparation1'
FIXTURES = Path(__file__).resolve().parent / 'negative-fixtures/regression-attempt1'


def module(file, name):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result)
    return result


metadata = module('publisher_metadata.py', 'test_metadata')
guards = module('consumer_guards.py', 'test_guards')
controller = module('run_native_consumer.py', 'test_controller')
validator = module('verify_native_consumer_source.py', 'test_validator')
patcher = module('apply_native_consumer_cumulative8.py', 'test_patcher')


class Preparation(unittest.TestCase):
    def setUp(self):
        self.root = (FIXTURES / self._testMethodName).resolve()
        self.root.mkdir(parents=True)

    def file(self, name, body=b'fixture\n'):
        path = self.root / name; path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body); return path

    def test_real_descriptor_mutation_rejected(self):
        path = self.file('source'); original_fdopen = os.fdopen
        class Stream:
            def __init__(self, inner): self.inner = inner; self.once = False
            def __enter__(self): self.inner.__enter__(); return self
            def __exit__(self, *args): return self.inner.__exit__(*args)
            def fileno(self): return self.inner.fileno()
            def read(self, size):
                value = self.inner.read(size)
                if not value and not self.once:
                    self.once = True; path.write_bytes(b'actual mutated FD contents\n')
                return value
        with mock.patch.object(metadata.os, 'fdopen', side_effect=lambda *a, **k: Stream(original_fdopen(*a, **k))):
            with self.assertRaises(ValueError): metadata.stable_read(path)
        self.assertEqual(path.read_bytes(), b'actual mutated FD contents\n')

    def test_real_identical_byte_named_leaf_swap_rejected(self):
        path = self.file('source'); before = path.stat(); body = path.read_bytes(); original_fdopen = os.fdopen
        class Stream:
            def __init__(self, inner): self.inner = inner; self.once = False
            def __enter__(self): self.inner.__enter__(); return self
            def __exit__(self, *args): return self.inner.__exit__(*args)
            def fileno(self): return self.inner.fileno()
            def read(self, size):
                result = self.inner.read(size)
                if not result and not self.once:
                    self.once = True; path.rename(path.with_name('original-open-inode'))
                    path.write_bytes(body); os.chmod(path, stat.S_IMODE(before.st_mode))
                    os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))
                return result
        with mock.patch.object(metadata.os, 'fdopen', side_effect=lambda *a, **k: Stream(original_fdopen(*a, **k))):
            with self.assertRaises(ValueError): metadata.stable_read(path)
        self.assertEqual(path.read_bytes(), body); self.assertNotEqual(path.stat().st_ino, before.st_ino)

    def test_symlink_and_hardlink_input_rejected(self):
        path = self.file('source'); link = self.root / 'alias'; link.symlink_to(path)
        with self.assertRaises(ValueError): metadata.stable_read(link)
        os.link(path, self.root / 'shared-inode')
        with self.assertRaises(ValueError): metadata.stable_read(path)

    def synthetic_four(self):
        files = {}
        for index, (name, (date, _, _)) in enumerate(metadata.FILES.items()):
            body = ('SYNTHETIC NONEXECUTABLE TIMESTAMP FIXTURE ' + str(index)).encode()
            self.file(name, body); files[name] = (date, len(body), hashlib.sha256(body).hexdigest())
        return files

    def archive(self, files, drift=None):
        path = self.root / 'synthetic-four-metadata.zip'
        with zipfile.ZipFile(path, 'w') as out:
            for name, (date, _, _) in files.items():
                info = zipfile.ZipInfo('flutter/' + name, tuple(date))
                if name == drift: info.date_time = (*date[:-1], date[-1] + 2)
                out.writestr(info, (self.root / name).read_bytes())
        return path

    def test_exact_four_timestamp_restoration_preserves_real_bytes(self):
        files = self.synthetic_four(); archive = self.archive(files)
        with mock.patch.object(metadata, 'FILES', files), mock.patch.object(metadata, 'ROOT', self.root):
            before = {name: (self.root / name).read_bytes() for name in files}
            result = metadata.restore_after_separate_authorization(self.root, archive)
            self.assertFalse(result['authored_bytes_changed'])
            for name, (date, _, _) in files.items():
                self.assertEqual((self.root / name).read_bytes(), before[name])
                self.assertEqual((self.root / name).stat().st_mtime_ns, metadata.timestamp_ns(date))
            self.assertLess((self.root / 'packages/flutter_tools/pubspec.yaml').stat().st_mtime_ns,
                            (self.root / 'packages/flutter_tools/pubspec.lock').stat().st_mtime_ns)

    def test_actual_ZIP_timestamp_drift_rejected_before_write(self):
        files = self.synthetic_four(); archive = self.archive(files, 'packages/flutter_tools/pubspec.lock')
        before = {name: (self.root / name).stat().st_mtime_ns for name in files}
        with mock.patch.object(metadata, 'FILES', files), mock.patch.object(metadata, 'ROOT', self.root):
            with self.assertRaises(ValueError): metadata.restore_after_separate_authorization(self.root, archive)
        self.assertEqual(before, {name: (self.root / name).stat().st_mtime_ns for name in files})

    def test_stamp_byte_drift_rejected_without_inventing_stamp(self):
        files = self.synthetic_four(); archive = self.archive(files)
        (self.root / 'bin/cache/flutter_tools.stamp').write_bytes(b'arbitrary fake compile key')
        with mock.patch.object(metadata, 'FILES', files), mock.patch.object(metadata, 'ROOT', self.root):
            with self.assertRaises(ValueError): metadata.restore_after_separate_authorization(self.root, archive)

    def test_actual_publisher_central_metadata_positive_read_only(self):
        archive = Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/public-artifacts/flutter_macos_arm64_3.44.4-stable.zip')
        result = metadata.exact_archive_timestamp_policy(archive)
        self.assertEqual(len(result['restored_paths_exact']), 4)
        self.assertFalse(result['publisher_timezone_attested'])

    def test_actual_reviewed_eight_RAM_delta_and_byte_drift(self):
        pristine = Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/flutter-3.44.4-authenticated-foundation-batch1')
        _, _, preview = validator.anchors()
        for name in preview['files']: self.file(name, (pristine / name).read_bytes())
        _, result = patcher.prepare_ram_delta(self.root)
        self.assertEqual(len(result), 8)
        target = next(iter(result)); path = self.root / target
        path.write_bytes(path.read_bytes() + b'\nreal unreviewed source drift\n')
        with self.assertRaises(ValueError): patcher.prepare_ram_delta(self.root)

    def app_fixture(self):
        app = self.root / 'app'; app.mkdir()
        files = {}
        for name, body in [('pubspec.lock', b'actual locked fixture\n'), ('lib/main.dart', b'actual source fixture\n'), ('LICENSE', b'fixture retained license\n')]:
            path = app / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(body)
            files[name] = {'sha256': hashlib.sha256(body).hexdigest(), 'bytes': len(body), 'mode': stat.S_IMODE(path.stat().st_mode)}
        canonical = (json.dumps(files, sort_keys=True, separators=(',', ':')) + '\n').encode()
        manifest = {'kind': 'unapproved_collect_source_export', 'retain_source_drift': False,
                    'capture_classification': 'strict_unapproved_source_export',
                    'approvals': {name: False for name in ('trusted_source_verified', 'reviewed', 'frozen', 'owner_approved', 'signed', 'production_release_accepted')},
                    'source_files': files, 'file_count': len(files), 'source_manifest_sha256': hashlib.sha256(canonical).hexdigest()}
        (app / '.collect-release-candidate.json').write_text(json.dumps(manifest))
        return app

    def test_authored_source_and_lock_byte_drift_rejected(self):
        app = self.app_fixture()
        with mock.patch.object(guards, 'APP', app):
            guards.app_readback('app-export')
            (app / 'pubspec.lock').write_bytes(b'changed actual lock contents\n')
            with self.assertRaises(ValueError): guards.app_readback('app-locked', hashlib.sha256((app / '.collect-release-candidate.json').read_bytes()).hexdigest())
            with self.assertRaises(ValueError): guards.require_lock(app / 'pubspec.lock', '0' * 64)

    def test_actual_license_loss_rejected(self):
        app = self.app_fixture(); (app / 'LICENSE').unlink()
        with mock.patch.object(guards, 'APP', app):
            with self.assertRaises(FileNotFoundError): guards.app_readback('built', hashlib.sha256((app / '.collect-release-candidate.json').read_bytes()).hexdigest())

    def test_unlisted_source_and_generated_symlink_rejected(self):
        app = self.app_fixture(); rogue = app / 'lib/rogue.dart'; rogue.write_bytes(b'actual extra source')
        with mock.patch.object(guards, 'APP', app):
            with self.assertRaises(ValueError): guards.app_readback('app-locked', hashlib.sha256((app / '.collect-release-candidate.json').read_bytes()).hexdigest())
            rogue.unlink(); (app / '.dart_tool').mkdir(); (app / '.dart_tool/external').symlink_to(self.root)
            with self.assertRaises(ValueError): guards.app_readback('app-locked', hashlib.sha256((app / '.collect-release-candidate.json').read_bytes()).hexdigest())

    def test_actual_package_binding_to_shared_or_remote_root_rejected(self):
        owned = self.root / 'owned'; owned.mkdir(); (owned / 'pubspec.yaml').write_text('name: owned')
        config = self.file('config.json', json.dumps({'configVersion': 2, 'packages': [{'name': 'owned', 'rootUri': owned.as_uri()}]}).encode())
        guards.package_config(config, (owned,))
        external = self.root / 'external'; external.mkdir(); (external / 'pubspec.yaml').write_text('name: external')
        config.write_text(json.dumps({'configVersion': 2, 'packages': [{'name': 'external', 'rootUri': external.as_uri()}]}))
        with self.assertRaises(ValueError): guards.package_config(config, (owned,))
        config.write_text(json.dumps({'configVersion': 2, 'packages': [{'name': 'remote', 'rootUri': 'https://example.invalid/source'}]}))
        with self.assertRaises(ValueError): guards.package_config(config, (owned,))

    def test_duplicate_JSON_metadata_and_packageUri_escape_rejected(self):
        path = self.file('duplicates.json', b'{"configVersion":2,"configVersion":3}')
        with self.assertRaises(ValueError): guards.read_json(path)
        owned = self.root / 'owned'; owned.mkdir(); (owned / 'pubspec.yaml').write_text('name: owned')
        path.write_text(json.dumps({'configVersion': 2, 'packages': [{'name': 'owned', 'rootUri': owned.as_uri(), 'packageUri': '../'}]}))
        with self.assertRaises(ValueError): guards.package_config(path, (owned,))

    def test_startup_upgrade_and_wrong_engine_rejected(self):
        valid = {'frameworkVersion': '3.44.4', 'frameworkRevision': guards.COMMIT,
                 'engineRevision': guards.ENGINE, 'dartSdkVersion': '3.12.2'}
        guards.startup_version(json.dumps(valid), '')
        with self.assertRaises(ValueError): guards.startup_version(json.dumps(valid), 'Building flutter tool...')
        valid['dartSdkVersion'] = '3.12.20'
        with self.assertRaises(ValueError): guards.startup_version(json.dumps(valid), '')
        valid['dartSdkVersion'] = '3.12.2'
        valid['engineRevision'] = '0' * 40
        with self.assertRaises(ValueError): guards.startup_version(json.dumps(valid), '')

    def test_protected_actual_mtime_and_identical_leaf_swap_rejected(self):
        path = self.file('protected'); st = path.lstat()
        row = {'device': st.st_dev, 'inode': st.st_ino, 'size': st.st_size, 'mode': st.st_mode,
               'nlink': st.st_nlink, 'mtime_ns': st.st_mtime_ns, 'ctime_ns': st.st_ctime_ns}
        baseline = self.file('protected-original-metadata.json', json.dumps({'paths': {str(path): row}}).encode())
        with mock.patch.object(controller, 'HERE', self.root):
            controller.protected_metadata()
            os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns + 2000000000))
            with self.assertRaises(ValueError): controller.protected_metadata()
            os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns)); path.rename(self.root / 'original-protected')
            path.write_bytes(b'fixture\n'); os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns))
            with self.assertRaises(ValueError): controller.protected_metadata()

    def test_actual_nonzero_process_and_timeout_fail_closed(self):
        failed = controller.run_process(self.root, 'nonzero', [sys.executable, '-I', '-B', '-c', 'raise SystemExit(7)'], 5, self.root, {'PATH': '/usr/bin:/bin'}, floor=0)
        self.assertEqual(failed['exit_code'], 7); self.assertFalse(failed['timed_out'])
        with self.assertRaises(ValueError): controller.require_pass(failed)
        timed = controller.run_process(self.root, 'deadline', [sys.executable, '-I', '-B', '-c', 'import time; time.sleep(30)'], 1, self.root, {'PATH': '/usr/bin:/bin'}, floor=0)
        self.assertTrue(timed['timed_out']); self.assertTrue(timed['owned_process_group_absent'])
        with self.assertRaises(ValueError): controller.require_pass(timed)

    def test_actual_missing_executable_retains_failure_receipt(self):
        argv = [str(self.root / 'actual-absent-executable')]
        with self.assertRaises(FileNotFoundError):
            controller.run_process(self.root, 'actual-launch-failure', argv, 5, self.root, {'PATH': '/usr/bin:/bin'}, floor=0)
        record = json.loads((self.root / 'actual-launch-failure.json').read_text())
        self.assertEqual(record['argv'], argv); self.assertFalse(record['spawned']); self.assertIsNone(record['exit_code'])
        self.assertEqual(record['actual_controller_error']['type'], 'FileNotFoundError')
        with self.assertRaises(ValueError): controller.require_pass(record)

    def test_actual_headroom_failure_distinct_from_timeout(self):
        result = controller.run_process(self.root, 'headroom', [sys.executable, '-I', '-B', '-c', 'import time; time.sleep(30)'], 10, self.root, {'PATH': '/usr/bin:/bin'}, floor=10**22)
        self.assertTrue(result['headroom_failure']); self.assertFalse(result['timed_out'])
        self.assertTrue(result['owned_process_group_absent'])
        with self.assertRaises(ValueError): controller.require_pass(result)

    def test_recomputed_current_manifest_cannot_replace_original_export(self):
        app = self.app_fixture(); path = app / '.collect-release-candidate.json'
        baseline = hashlib.sha256(path.read_bytes()).hexdigest()
        document = json.loads(path.read_text()); source = app / 'pubspec.lock'
        source.write_bytes(b'actual changed lock with recomputed manifest')
        document['source_files']['pubspec.lock'].update(sha256=hashlib.sha256(source.read_bytes()).hexdigest(), bytes=source.stat().st_size)
        canonical = (json.dumps(document['source_files'], sort_keys=True, separators=(',', ':')) + '\n').encode()
        document['source_manifest_sha256'] = hashlib.sha256(canonical).hexdigest(); path.write_text(json.dumps(document))
        with mock.patch.object(guards, 'APP', app):
            with self.assertRaises(ValueError): guards.app_readback('app-locked', baseline)
            with self.assertRaises(ValueError): guards.app_readback('app-locked')

    def test_actual_outward_package_lib_and_pubspec_symlinks_rejected(self):
        owned = self.root / 'owned'; owned.mkdir(); external = self.root / 'external'; external.mkdir()
        (owned / 'pubspec.yaml').write_text('name: owned'); (external / 'pubspec.yaml').write_text('name: external')
        (owned / 'lib').symlink_to(external, target_is_directory=True)
        config = self.file('packages.json', json.dumps({'configVersion': 2, 'packages': [{'name': 'owned', 'rootUri': owned.as_uri(), 'packageUri': 'lib/'}]}).encode())
        with self.assertRaises(ValueError): guards.package_config(config, (owned,))
        (owned / 'lib').unlink(); (owned / 'pubspec.yaml').unlink(); (owned / 'pubspec.yaml').symlink_to(external / 'pubspec.yaml')
        with self.assertRaises(ValueError): guards.package_config(config, (owned,))

    def test_actual_fast_terminal_deadline_overrun_rejected(self):
        original = controller.subprocess.Popen
        def actual_delayed_return(*args, **kwargs):
            process = original(*args, **kwargs); process.wait(timeout=5)
            time.sleep(.1); return process
        with mock.patch.object(controller.subprocess, 'Popen', side_effect=actual_delayed_return):
            result = controller.run_process(self.root, 'fast-terminal-overrun', [sys.executable, '-I', '-B', '-c', 'pass'], .05, self.root, {'PATH': '/usr/bin:/bin'}, floor=0)
        self.assertEqual(result['exit_code'], 0); self.assertTrue(result['timed_out']); self.assertTrue(result['spawned'])
        with self.assertRaises(ValueError): controller.require_pass(result)

    def test_actual_expired_deadline_refuses_child_spawn(self):
        marker = self.root / 'unallowed-spawn-marker'
        result = controller.run_process(self.root, 'expired-before-spawn', [sys.executable, '-I', '-B', '-c', 'from pathlib import Path; Path(' + repr(str(marker)) + ').write_text("spawned")'], 0, self.root, {'PATH': '/usr/bin:/bin'}, floor=0)
        self.assertFalse(result['spawned']); self.assertTrue(result['timed_out']); self.assertFalse(marker.exists())
        with self.assertRaises(ValueError): controller.require_pass(result)

    def test_exit_zero_leader_with_owned_live_child_is_rejected(self):
        code = 'import subprocess,sys; subprocess.Popen([sys.executable,"-I","-B","-c","import time; time.sleep(30)"]); raise SystemExit(0)'
        try:
            result = controller.run_process(self.root, 'residual-child', [sys.executable, '-I', '-B', '-c', code], 10, self.root, {'PATH': '/usr/bin:/bin'}, floor=0)
        except RuntimeError:
            result = json.loads((self.root / 'residual-child.json').read_text())
        self.assertEqual(result['exit_code'], 0); self.assertTrue(result['residual_process_group_required_stop'])
        with self.assertRaises(ValueError): controller.require_pass(result)

    def test_stage_receipt_path_selection_is_exact_and_immutable(self):
        for stage in controller.STAGES:
            self.assertEqual(controller.receipt_path(stage), controller.AUTH_DIR / (stage + '-admission.json'))
        for stage in ('../outside', 'sdk-lock/../../outside', 'foundation-admission.json', ''):
            with self.assertRaises(ValueError): controller.receipt_path(stage)

    def test_actual_volume_alias_and_noncanonical_source_path_rejected(self):
        physical = self.root / 'physical-volume'; physical.mkdir()
        alias = self.root / 'volume-alias'; alias.symlink_to(physical, target_is_directory=True)
        with self.assertRaises(ValueError): controller.existing_volume(alias / 'absent-child')
        self.assertEqual(controller.existing_volume(physical / 'absent-child'), physical)
        for name in ('lib//main.dart', 'lib/./main.dart', 'lib/../main.dart', 'lib/main\\file.dart', 'lib/line\nfile.dart'):
            with self.assertRaises(ValueError): guards.safe_relative(name)

    def test_wrong_metadata_destination_rejected_without_writes(self):
        files = self.synthetic_four(); archive = self.archive(files)
        before = {name: (self.root / name).stat().st_mtime_ns for name in files}
        with mock.patch.object(metadata, 'FILES', files):
            with self.assertRaises(ValueError): metadata.restore_after_separate_authorization(self.root, archive)
        self.assertEqual(before, {name: (self.root / name).stat().st_mtime_ns for name in files})

    def test_real_source_manifest_metadata_tamper_rejected(self):
        app = self.app_fixture(); path = app / '.collect-release-candidate.json'
        document = json.loads(path.read_text()); document['source_files']['LICENSE']['bytes'] += 1
        path.write_text(json.dumps(document))
        with mock.patch.object(guards, 'APP', app):
            with self.assertRaises(ValueError): guards.app_readback('app-export')

    def test_actual_unreviewed_empty_source_directory_rejected(self):
        app = self.app_fixture(); (app / 'unreviewed-empty-source').mkdir()
        with mock.patch.object(guards, 'APP', app):
            with self.assertRaises(ValueError): guards.app_readback('app-locked', hashlib.sha256((app / '.collect-release-candidate.json').read_bytes()).hexdigest())

    def test_actual_publisher_license_and_snapshot_drift_rejected(self):
        _, admission, preview = validator.anchors()
        pristine = Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/flutter-3.44.4-authenticated-foundation-batch1')
        for name in ('LICENSE', 'bin/cache/flutter_tools.snapshot'):
            path = self.file(name, (pristine / name).read_bytes()); row = admission['members']['flutter/' + name]
            validator.check_regular_bytes('flutter/' + name, path.read_bytes(), row, preview, 'startup')
            with path.open('ab') as output: output.write(b'actual unauthorized publisher byte drift')
            with self.assertRaises(ValueError): validator.check_regular_bytes('flutter/' + name, path.read_bytes(), row, preview, 'startup')

    def test_actual_unauthorized_receipt_and_receipt_drift_rejected(self):
        receipt = self.file('foundation-admission.json', json.dumps({'errors': [], 'execution_stage_admissions': {}}).encode())
        args = types.SimpleNamespace(prepared_manifest_sha256='0' * 64,
            root_review_sha256=hashlib.sha256(receipt.read_bytes()).hexdigest(), stage='foundation')
        with mock.patch.object(controller, 'AUTH_DIR', self.root), mock.patch.object(controller, 'packet', return_value={'files': {}}):
            with self.assertRaises(ValueError): controller.authorization(args)
            receipt.write_bytes(receipt.read_bytes() + b'\nactual receipt byte replacement')
            with self.assertRaises(ValueError): controller.authorization(args)

    def test_exporter_selected_SDK_launcher_never_executed(self):
        source = HERE.parent.parent.parent.parent / 'scripts/qa/collect_release_candidate.py'
        spec = importlib.util.spec_from_file_location('actual_exporter_reader', source)
        exporter = importlib.util.module_from_spec(spec); spec.loader.exec_module(exporter)
        root = self.root / 'repo'; sdk = self.root / 'sdk'; root.mkdir(); sdk.mkdir()
        (root / '.fvmrc').write_text('{"flutter":"3.44.4"}')
        (root / '.dvmrc').write_text('2.5.6\n')
        for name in exporter.LOCKS:
            path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text('fixture lock\n')
        (root / 'android/gradle/wrapper').mkdir(parents=True); (root / 'android/gradle/wrapper/gradle-wrapper.properties').write_text('fixture wrapper\n')
        path = root / 'tools/collect-notification-mcp/package.json'; path.parent.mkdir(parents=True, exist_ok=True); path.write_text('{}')
        (sdk / 'bin/cache').mkdir(parents=True); (sdk / 'bin/flutter').write_text('#! /bin/sh\nexit 99\n')
        (sdk / 'bin/cache/flutter.version.json').write_text(json.dumps({'frameworkVersion': '3.44.4', 'frameworkRevision': guards.COMMIT, 'dartSdkVersion': '3.12.2'}))
        commands = []
        def command(argv, **kwargs):
            commands.append(argv)
            if argv != ['/synthetic-node', '--version']: raise AssertionError('SDK or unexpected executable invoked')
            return 'v22.6.0\n'
        with mock.patch.object(exporter.shutil, 'which', side_effect=lambda name: '/synthetic-node' if name == 'node' else None), mock.patch.object(exporter.subprocess, 'check_output', side_effect=command):
            result = exporter.collect_toolchain(root, sdk)
        self.assertEqual(commands, [['/synthetic-node', '--version']]); self.assertEqual(result['flutter']['framework_revision'], guards.COMMIT)


if __name__ == '__main__':
    unittest.main(verbosity=2)

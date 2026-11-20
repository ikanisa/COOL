"""Focused fake-host tests. No real hdiutil/Colima/Docker/SQL mutations."""
from pathlib import Path
import contextlib
import copy
import fcntl
import hashlib
import importlib.util
import io
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('runtime_startup', ROOT / 'runtime_startup_lockaware.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class FakeHost:
    def __init__(self, fixture):
        self.f = fixture
        self.state = 'Running'
        self.mounted = True
        self.reachable = True
        self.actions = []
        self.requests = []
        self.after_action = 'success'
        self.volume_uuid = 'test-volume'
        self.foreign_image = False
        self.free_space = {fixture.s['image_path']: 2 * m.MINIMUM_FREE_BYTES,
                           fixture.s['mount_point']: 2 * m.MINIMUM_FREE_BYTES}
        self.free_space_queries = []

    def image_info(self):
        if not self.mounted:
            return {'images': []}
        s = self.f.s
        return {'images': [{'image-path': 'foreign-image' if self.foreign_image else s['image_path'],
                            'owner-uid': s['uid'], 'writeable': True,
                            'system-entities': [{'mount-point': s['mount_point']}]}]}

    def volume_info(self):
        return {'MountPoint': self.f.s['mount_point'], 'VolumeUUID': self.volume_uuid}

    def instances(self):
        s = self.f.s
        return ([{'name': s['profile'], 'status': self.state, 'runtime': 'docker', 'arch': 'aarch64'}],
                [{'name': s['lima_instance'], 'status': self.state, 'dir': s['instance_dir'], 'vmType': 'vz', 'arch': 'aarch64'}])

    def docker_get(self, path):
        self.requests.append(path)
        if not self.reachable:
            raise m.Refusal('docker_unreachable')
        return copy.deepcopy(self.f.responses[path])

    def command(self, argv, *, mutation=False, timeout=None):
        assert mutation, 'fake host only accepts expected action requests'
        self.actions.append(list(argv))
        if self.after_action in ('success', 'success_lost_ack'):
            if argv[1] == 'attach':
                self.f.stash.rename(self.f.mount)
                self.mounted = True
            elif argv[1] == 'start':
                self.state = 'Running'
                self.reachable = True
            else:
                raise AssertionError('unexpected mutation')
        if self.after_action in ('unknown', 'success_lost_ack'):
            raise m.Refusal('external_action_unconfirmed')
        return 0 if self.after_action == 'success' else 17

    def boot_id(self):
        return 'test-boot'

    def free_bytes(self, path):
        self.free_space_queries.append(path)
        if path == self.f.s['mount_point']:
            assert self.mounted, 'never measure an absent runtime filesystem'
        value = self.free_space[path]
        if isinstance(value, Exception):
            raise value
        return value

    def sleep(self, seconds):
        # ready_timeout=0 avoids real sleeps. Serve-loop sleep ends the test.
        raise KeyboardInterrupt()


class Fixture:
    def __init__(self, root):
        self.root = root
        self.mount = root / 'mount'
        self.stash = root / 'detached-files'
        image = root / 'image.sparsebundle'
        uid = os.getuid()
        for p in [image, image / 'bands', self.mount]:
            p.mkdir(mode=0o700)
        self.file(image / 'Info.plist', 'retained image')
        self.file(image / 'bands/0', 'retained bands')
        locations = {'colima_home': '.colima', 'lima_home': 'lima',
                     'profile_dir': '.colima/supabase-local',
                     'instance_dir': 'lima/colima-supabase-local',
                     'data_disk_dir': 'lima/_disks/colima-supabase-local',
                     'cache_home': 'cache', 'runtime_tmp': 'tmp', 'docker_config': 'docker-config',
                     'release_root': 'releases/test-004'}
        for rel in locations.values():
            (self.mount / rel).mkdir(mode=0o700, parents=True, exist_ok=True)
        self.s = {
            'format': m.FORMAT, 'enabled': True, 'uid': uid,
            'user_name': 'test', 'user_home': str(root), 'working_directory': str(root),
            'image_path': str(image), 'image_info_sha256': m.digest(image / 'Info.plist'),
            'mount_point': str(self.mount), 'volume_uuid': 'test-volume',
            'profile': 'supabase-local', 'lima_instance': 'colima-supabase-local',
            **{key: str(self.mount / rel) for key, rel in locations.items()},
            'docker_socket': str(self.mount / '.colima/supabase-local/docker.sock'),
            'owner_marker': str(self.mount / 'owner.json'), 'owner_marker_expected': {'profile': 'supabase-local'},
            'store_path': str(self.mount / '.colima/store.json'),
            'release_source_sha256': 'a' * 64, 'release_profile_sha256': 'b' * 64,
            'release_profile_id': 'collect-production',
            'state_path': str(root / 'state.private.json'), 'lock_path': str(root / 'owner.private.lock'),
            'event_log': str(root / 'events.private.jsonl'),
            'optional_container_starts': False, 'read_timeout_seconds': 1,
            'attach_timeout_seconds': 1, 'resume_timeout_seconds': 1, 'ready_timeout_seconds': 0,
            'probe_interval_seconds': 0, 'monitor_interval_seconds': 0,
            'resume_cooldown_seconds': 0, 'max_resumes_per_boot': 3,
            'tool_path': '/usr/bin:/bin',
        }
        for key in ('colima_binary', 'limactl_binary', 'hdiutil', 'diskutil'):
            p = root / (key + '.fake')
            self.file(p, 'fake tool ' + key)
            p.chmod(0o700)
            self.s[key] = str(p)
        self.s['binary_sha256'] = {self.s[k]: m.digest(self.s[k]) for k in ('colima_binary', 'limactl_binary', 'hdiutil', 'diskutil')}
        self.s['binary_owner_uids'] = {p: uid for p in self.s['binary_sha256']}
        self.json(self.s['owner_marker'], self.s['owner_marker_expected'])
        self.json(self.s['store_path'], {'disk_formatted': True, 'disk_runtime': 'docker'})
        self.json(Path(self.s['release_root']) / 'release.json', {'source_sha256': 'a' * 64, 'profile_sha256': 'b' * 64, 'profile': {'id': 'collect-production'}})
        conf = self.mount / '.colima/supabase-local/colima.yaml'
        self.file(conf, 'runtime: docker')
        lima = self.mount / 'lima/colima-supabase-local/lima.yaml'
        self.file(lima, 'existing: true\nssh:\n  localPort: 23456\n')
        self.s['retained_file_sha256'] = {str(conf): m.digest(conf)}
        self.s['derived_yaml'] = [{'path': str(lima), 'ignore_ssh_port': True,
                                  'sha256': m.derived_digest(lima.read_bytes(), True)}]
        cached = self.mount / 'cache/image'
        self.file(cached, 'cached image')
        self.s['cached_images'] = [{'path': str(cached), 'sha256': m.digest(cached)}]
        self.s['disks'] = []
        for p in [self.mount / 'lima/colima-supabase-local/disk', self.mount / 'lima/_disks/colima-supabase-local/datadisk']:
            self.file(p, 'retained disk')
            st = p.stat()
            self.s['disks'].append({'path': str(p), 'bytes': st.st_size, 'inode': st.st_ino})
        self.s.update(database_id='db-id', database_image_id='db-image', database_mounts=[{'Name': 'retained-db', 'RW': True}],
                      edge_id='edge-id', edge_image_id='edge-image', network_id='retained-network')
        self.s['containers'] = [{'name': 'supabase_db_local-app', 'id': 'db-id', 'image_id': 'db-image'},
                                {'name': 'supabase_edge_runtime_local-app', 'id': 'edge-id', 'image_id': 'edge-image'}]
        self.responses = {
            '/containers/json?all=1': [{'Id': x['id'], 'ImageID': x['image_id'], 'Names': ['/' + x['name']], 'State': 'running'} for x in self.s['containers']],
            '/containers/db-id/json': {'Id': 'db-id', 'Image': 'db-image', 'Mounts': self.s['database_mounts'],
                                       'Config': {'Labels': {'com.supabase.cli.project': 'local-app'}},
                                       'State': {'Running': True, 'Health': {'Status': 'healthy'}},
                                       'NetworkSettings': {'Networks': {'devctl-local-app': {'NetworkID': 'retained-network'}}}},
            '/containers/edge-id/json': {'Id': 'edge-id', 'Image': 'edge-image', 'State': {'Running': True},
                                         'Config': {'Labels': {'io.collect.retained-edge.source': 'a' * 64, 'io.collect.retained-edge.profile': 'b' * 64}}},
        }
        self.host = FakeHost(self)
        self.journal = m.Journal(self.s, self.host.boot_id())
        self.service = m.Service(self.s, self.host, self.journal)
        self.service.operation_permit = type('SyntheticPermit', (), {'arm': lambda self: None})()
        self.settings_path = root / 'settings.private.json'
        self.json(self.settings_path, self.s)

    @staticmethod
    def file(path, text):
        path = Path(path)
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        path.write_text(text)
        path.chmod(0o600)

    def json(self, path, value):
        self.file(path, json.dumps(value))

    def detach_fake(self):
        self.mount.rename(self.stash)
        self.host.mounted = False


class StartupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='fake-startup-', dir=ROOT)
        self.root = Path(self.temporary.name)
        self.f = Fixture(self.root)
        self.operation_root = self.root / 'operation-coordinator'
        m.operation_lock.initialize(self.operation_root)
        self.operation_patch = patch.object(m.operation_lock, 'DEFAULT_ROOT', self.operation_root)
        self.operation_patch.start()
        self.addCleanup(self.operation_patch.stop)

    def tearDown(self):
        self.temporary.cleanup()

    def refused(self, reason, action=None):
        with self.assertRaisesRegex(m.Refusal, '^' + reason + '$'):
            (action or (lambda: self.f.service.cycle(permit_actions=True)))()

    def test_running_retained_runtime_needs_no_mutation(self):
        self.f.service.validate_host()
        result = self.f.service.cycle(permit_actions=True)
        self.assertTrue(result['ready'])
        self.assertEqual(self.f.host.actions, [])
        self.assertTrue(all(p.startswith('/containers/') for p in self.f.host.requests))

    def test_stopped_existing_vm_resumes_once_with_context_and_config_protection(self):
        self.f.host.state = 'Stopped'
        self.f.service.cycle(permit_actions=True)
        self.assertEqual(self.f.host.actions, [[self.f.s['colima_binary'], 'start', '--profile', 'supabase-local', '--activate=false', '--save-config=false', '--template=false']])
        self.assertIsNone(self.f.journal.value['pending'])
        self.assertEqual(self.f.journal.value['resumes'], 1)
        self.f.service.cycle(permit_actions=True)
        self.assertEqual(len(self.f.host.actions), 1)

    def test_absent_image_attaches_only_known_image_then_resumes_existing_vm(self):
        self.f.detach_fake()
        self.f.host.state = 'Stopped'
        self.f.service.cycle(permit_actions=True)
        self.assertEqual(self.f.host.actions[0], [self.f.s['hdiutil'], 'attach', '-nobrowse', '-mountpoint', self.f.s['mount_point'], '-plist', self.f.s['image_path']])
        self.assertEqual(len(self.f.host.actions), 2)

    def test_foreign_image_at_mountpoint_is_never_overwritten(self):
        self.f.host.foreign_image = True
        self.refused('mountpoint_occupied_or_stale')
        self.assertEqual(self.f.host.actions, [])

    def test_stale_directory_at_unmounted_target_is_never_overwritten(self):
        self.f.detach_fake()
        self.f.mount.mkdir(mode=0o700)
        self.refused('mountpoint_occupied_or_stale')
        self.assertEqual(self.f.host.actions, [])

    def test_unexpected_volume_uuid_blocks_resume(self):
        self.f.host.volume_uuid = 'different-volume'
        self.f.host.state = 'Stopped'
        self.refused('mounted_volume_identity_mismatch')
        self.assertEqual(self.f.host.actions, [])

    def test_missing_existing_lima_metadata_blocks_fresh_vm_creation(self):
        Path(self.f.s['derived_yaml'][0]['path']).unlink()
        self.f.host.state = 'Stopped'
        self.refused('required_file_unavailable')
        self.assertEqual(self.f.host.actions, [])

    def test_derived_lima_ssh_port_can_change_after_resume_without_disabling_monitor(self):
        self.f.service.cycle(permit_actions=True)
        p = Path(self.f.s['derived_yaml'][0]['path'])
        self.f.file(p, 'existing: true\nssh:\n  localPort: 34567\n')
        self.assertTrue(self.f.service.cycle(permit_actions=True)['ready'])
        self.f.file(p, 'existing: false\nssh:\n  localPort: 34567\n')
        self.refused('derived_vm_metadata_mismatch')

    def test_unformatted_or_wrong_runtime_store_cannot_reformat_disk(self):
        for value in ({'disk_formatted': False, 'disk_runtime': 'docker'}, {'disk_formatted': True, 'disk_runtime': 'containerd'}):
            self.f.json(self.f.s['store_path'], value)
            self.f.host.state = 'Stopped'
            self.refused('retained_formatted_docker_disk_required')
        self.assertEqual(self.f.host.actions, [])

    def test_missing_cached_image_blocks_download_fallback(self):
        Path(self.f.s['cached_images'][0]['path']).unlink()
        self.f.host.state = 'Stopped'
        self.refused('required_file_unavailable')
        self.assertEqual(self.f.host.actions, [])

    def test_cached_image_symlink_escape_is_refused(self):
        cached = Path(self.f.s['cached_images'][0]['path'])
        cached.unlink()
        outside = self.root / 'outside-image'
        self.f.file(outside, 'cached image')
        cached.symlink_to(outside)
        self.refused('retained_file_escaped_mount')
        self.assertEqual(self.f.host.actions, [])

    def test_changed_cache_is_rechecked_after_prior_success(self):
        self.f.service.cycle(permit_actions=True)
        self.f.file(self.f.s['cached_images'][0]['path'], 'unexpected image')
        self.refused('required_file_content_mismatch')
        self.assertEqual(self.f.host.actions, [])

    def test_replaced_disk_same_size_still_fails_inode_binding(self):
        disk = Path(self.f.s['disks'][0]['path'])
        replacement = disk.with_suffix('.replacement')
        self.f.file(replacement, disk.read_text())
        replacement.replace(disk)
        self.refused('retained_disk_inode_mismatch')

    def test_regular_file_at_docker_socket_is_not_removed(self):
        self.f.file(self.f.s['docker_socket'], 'stale socket-like file')
        self.refused('docker_socket_is_stale_file_or_foreign')
        self.assertEqual(Path(self.f.s['docker_socket']).read_text(), 'stale socket-like file')

    def test_unknown_resume_is_journaled_and_never_replayed(self):
        self.f.host.state = 'Stopped'
        self.f.host.after_action = 'unknown'
        self.refused('runtime_ready_timeout')
        self.assertEqual(self.f.journal.value['pending'], 'resume_existing_vm')
        self.refused('previous_resume_outcome_unconfirmed')
        self.assertEqual(len(self.f.host.actions), 1)

    def test_success_after_lost_resume_ack_is_accepted_by_readback(self):
        self.f.host.state = 'Stopped'
        self.f.host.after_action = 'success_lost_ack'
        self.assertTrue(self.f.service.cycle(permit_actions=True)['ready'])
        self.assertIsNone(self.f.journal.value['pending'])
        self.assertEqual(len(self.f.host.actions), 1)

    def test_unknown_attach_is_never_replayed(self):
        self.f.detach_fake()
        self.f.host.after_action = 'unknown'
        self.refused('attach_outcome_unconfirmed')
        self.refused('previous_attach_outcome_unconfirmed')
        self.assertEqual(len(self.f.host.actions), 1)

    def test_running_vm_with_missing_docker_is_never_reset(self):
        self.f.host.reachable = False
        self.refused('runtime_ready_timeout')
        self.assertEqual(self.f.host.actions, [])

    def test_container_identity_change_is_not_repaired_by_starting_something_else(self):
        self.f.responses['/containers/json?all=1'][0]['Id'] = 'wrong-db'
        self.refused('retained_container_identity_mismatch')
        self.assertEqual(self.f.host.actions, [])

    def test_database_mount_or_network_change_is_terminal(self):
        for key, value, code in [('Mounts', [], 'retained_database_mount_identity_mismatch'), ('NetworkSettings', {}, 'retained_database_network_identity_mismatch')]:
            old = self.f.responses['/containers/db-id/json'][key]
            self.f.responses['/containers/db-id/json'][key] = value
            self.refused(code)
            self.f.responses['/containers/db-id/json'][key] = old
        self.assertEqual(self.f.host.actions, [])

    def test_release_or_edge_source_drift_is_terminal(self):
        self.f.responses['/containers/edge-id/json']['Config']['Labels']['io.collect.retained-edge.source'] = 'unknown-source'
        self.refused('retained_edge_source_mismatch')
        self.assertEqual(self.f.host.actions, [])

    def test_pending_action_survives_helper_and_host_restart(self):
        self.f.journal.begin('resume_existing_vm')
        restored = m.Journal(self.f.s, 'new-boot')
        self.assertEqual(restored.value['pending'], 'resume_existing_vm')
        self.assertEqual(restored.value['resumes'], 0)

    def test_parent_directory_sync_follows_rename_before_external_action(self):
        self.f.host.state = 'Stopped'
        events = []
        real_fsync = os.fsync
        real_replace = os.replace
        fake_command = self.f.host.command

        def sync(fd):
            events.append('directory_sync' if stat.S_ISDIR(os.fstat(fd).st_mode) else 'file_sync')
            return real_fsync(fd)

        def replace(source, destination):
            events.append('rename')
            return real_replace(source, destination)

        def command(*args, **kwargs):
            events.append('external_action')
            return fake_command(*args, **kwargs)

        with patch.object(m.os, 'fsync', side_effect=sync), patch.object(m.os, 'replace', side_effect=replace), patch.object(self.f.host, 'command', side_effect=command):
            self.f.service.cycle(permit_actions=True)
        self.assertEqual(events[:4], ['file_sync', 'rename', 'directory_sync', 'external_action'])

    def test_failed_parent_directory_sync_prevents_external_action_and_keeps_intent(self):
        self.f.host.state = 'Stopped'
        real_fsync = os.fsync

        def sync(fd):
            if stat.S_ISDIR(os.fstat(fd).st_mode):
                raise OSError('fake directory synchronization failure')
            return real_fsync(fd)

        with patch.object(m.os, 'fsync', side_effect=sync):
            self.refused('journal_directory_sync_failed')
        self.assertEqual(self.f.host.actions, [])
        restored = m.Journal(self.f.s, self.f.host.boot_id())
        self.assertEqual(restored.value['pending'], 'resume_existing_vm')
        self.f.service.journal = restored
        self.refused('previous_resume_outcome_unconfirmed')
        self.assertEqual(self.f.host.actions, [])

    def test_bounded_resume_budget_prevents_restart_loop(self):
        self.f.host.state = 'Stopped'
        self.f.journal.value['resumes'] = 3
        self.refused('resume_budget_exhausted')
        self.assertEqual(self.f.host.actions, [])

    def test_cooldown_waits_without_reinitializing_or_exiting_monitor(self):
        self.f.host.state = 'Stopped'
        self.f.s['resume_cooldown_seconds'] = 300
        self.f.journal.value['last_resume_at'] = m.time.time()
        result = self.f.service.cycle(permit_actions=True)
        self.assertEqual(result['reason'], 'resume_cooldown_active')
        self.assertEqual(self.f.host.actions, [])

    def test_check_mode_does_not_create_journal_lock_or_log(self):
        before = set(self.root.iterdir())
        with patch.object(m, 'Host', return_value=self.f.host), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(m.main(['--settings', str(self.f.settings_path), '--check']), 0)
        self.assertEqual(before, set(self.root.iterdir()))
        self.assertEqual(self.f.host.actions, [])

    def test_check_mode_does_not_resume_stopped_vm(self):
        self.f.host.state = 'Stopped'
        with patch.object(m, 'Host', return_value=self.f.host), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(m.main(['--settings', str(self.f.settings_path), '--check']), 2)
        self.assertEqual(self.f.host.actions, [])

    def test_second_owner_cannot_mutate(self):
        fd = os.open(self.f.s['lock_path'], os.O_RDWR | os.O_CREAT, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            with patch.object(m, 'Host', return_value=self.f.host), contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(m.main(['--settings', str(self.f.settings_path), '--run']), 0)
            self.assertIn('startup_owner_already_running', output.getvalue())
            self.assertEqual(self.f.host.actions, [])
        finally:
            os.close(fd)

    def test_disabled_draft_exits_without_runtime_actions(self):
        self.f.s['enabled'] = False
        self.f.json(self.f.settings_path, self.f.s)
        with patch.object(m, 'Host', return_value=self.f.host), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(m.main(['--settings', str(self.f.settings_path), '--run']), 0)
        self.assertIn('startup_service_disabled', output.getvalue())
        self.assertEqual(self.f.host.actions, [])

    def test_event_log_contains_only_fixed_metadata_and_has_bounded_rotation(self):
        self.f.service.event('retained_runtime_ready')
        value = json.loads(Path(self.f.s['event_log']).read_text())
        self.assertEqual(set(value), {'at', 'pid', 'event'})
        self.f.file(self.f.s['event_log'], 'x' * (m.MAX_LOG + 1))
        self.f.service.event('resume_budget_exhausted')
        self.assertLess(Path(self.f.s['event_log']).stat().st_size, 256)
        self.assertTrue(Path(self.f.s['event_log']).with_suffix('.previous.jsonl').exists())

    def test_real_command_wrapper_discards_mutation_output_and_sanitizes_timeout(self):
        host = m.Host(self.f.s)
        self.assertEqual(host.command([sys.executable, '-c', 'print("fake-sensitive-output")'], mutation=True), 0)
        with self.assertRaisesRegex(m.Refusal, '^external_action_unconfirmed$'):
            host.command([sys.executable, '-c', 'import time; time.sleep(5)'], mutation=True, timeout=0.02)


class FreeSpaceStartupTests(unittest.TestCase):
    setUp = StartupTests.setUp
    tearDown = StartupTests.tearDown
    refused = StartupTests.refused

    def assert_no_intent_or_action(self):
        self.assertEqual(self.f.host.actions, [])
        self.assertIsNone(self.f.journal.value['pending'])
        self.assertEqual(self.f.journal.value.get('resumes', 0), 0)
        self.assertFalse(Path(self.f.s['state_path']).exists())

    def test_running_observation_and_check_remain_available_below_reserve(self):
        self.f.host.free_space = {path: 0 for path in self.f.host.free_space}
        self.assertTrue(self.f.service.cycle(permit_actions=True)['ready'])
        with patch.object(m, 'Host', return_value=self.f.host), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(m.main(['--settings', str(self.f.settings_path), '--check']), 0)
        self.assertTrue(json.loads(output.getvalue())['ready'])
        self.assertEqual(self.f.host.free_space_queries, [])
        self.assertEqual(self.f.host.actions, [])

    def test_stopped_low_backing_refuses_before_intent_or_resume_counter(self):
        self.f.host.state = 'Stopped'
        self.f.host.free_space[self.f.s['image_path']] = m.MINIMUM_FREE_BYTES - 1
        self.refused('backing_free_space_below2gib')
        self.assert_no_intent_or_action()

    def test_stopped_low_runtime_refuses_before_intent_or_resume_counter(self):
        self.f.host.state = 'Stopped'
        self.f.host.free_space[self.f.s['mount_point']] = m.MINIMUM_FREE_BYTES - 1
        self.refused('runtime_free_space_below2gib')
        self.assertEqual(self.f.host.free_space_queries, [self.f.s['image_path'], self.f.s['mount_point']])
        self.assert_no_intent_or_action()

    def test_exact_reserve_allows_only_the_original_existing_vm_resume(self):
        self.f.host.state = 'Stopped'
        self.f.host.free_space = {path: m.MINIMUM_FREE_BYTES for path in self.f.host.free_space}
        self.assertTrue(self.f.service.cycle(permit_actions=True)['ready'])
        self.assertEqual(self.f.host.actions, [[self.f.s['colima_binary'], 'start', '--profile', 'supabase-local',
                                             '--activate=false', '--save-config=false', '--template=false']])
        self.assertEqual(self.f.journal.value['resumes'], 1)

    def test_low_backing_refuses_attach_without_measuring_unmounted_runtime(self):
        self.f.detach_fake()
        self.f.host.state = 'Stopped'
        self.f.host.free_space[self.f.s['image_path']] = m.MINIMUM_FREE_BYTES - 1
        self.refused('backing_free_space_below2gib')
        self.assertEqual(self.f.host.free_space_queries, [self.f.s['image_path']])
        self.assert_no_intent_or_action()

    def test_attach_precedes_runtime_measurement_and_low_runtime_blocks_resume(self):
        self.f.detach_fake()
        self.f.host.state = 'Stopped'
        self.f.host.free_space[self.f.s['mount_point']] = m.MINIMUM_FREE_BYTES - 1
        self.refused('runtime_free_space_below2gib')
        self.assertEqual(self.f.host.actions, [[self.f.s['hdiutil'], 'attach', '-nobrowse', '-mountpoint',
                                             self.f.s['mount_point'], '-plist', self.f.s['image_path']]])
        self.assertEqual(self.f.host.free_space_queries, [self.f.s['image_path'], self.f.s['image_path'], self.f.s['mount_point']])
        self.assertIsNone(self.f.journal.value['pending'])
        self.assertEqual(self.f.journal.value.get('resumes', 0), 0)

    def test_backing_capacity_is_freshly_rechecked_after_attach(self):
        self.f.detach_fake()
        self.f.host.state = 'Stopped'
        original = self.f.host.command
        def consume_space(*args, **kwargs):
            result = original(*args, **kwargs)
            self.f.host.free_space[self.f.s['image_path']] = m.MINIMUM_FREE_BYTES - 1
            return result
        with patch.object(self.f.host, 'command', side_effect=consume_space):
            self.refused('backing_free_space_below2gib')
        self.assertEqual(len(self.f.host.actions), 1)
        self.assertEqual(self.f.host.actions[0][1], 'attach')
        self.assertIsNone(self.f.journal.value['pending'])
        self.assertEqual(self.f.journal.value.get('resumes', 0), 0)

    def test_measurement_error_refuses_before_any_external_action(self):
        for path in [self.f.s['image_path'], self.f.s['mount_point']]:
            with self.subTest(path=path):
                self.f.host.state = 'Stopped'
                self.f.host.free_space = {p: 2 * m.MINIMUM_FREE_BYTES for p in self.f.host.free_space}
                self.f.host.free_space[path] = m.Refusal('free_space_observation_unavailable')
                self.refused('free_space_observation_unavailable')
                self.assert_no_intent_or_action()

    def test_host_measures_available_blocks_not_total_or_privileged_free(self):
        space = SimpleNamespace(f_bavail=524288, f_frsize=4096, f_bfree=999999999)
        with patch.object(m.os, 'statvfs', return_value=space) as observe:
            self.assertEqual(m.Host(self.f.s).free_bytes(self.f.s['image_path']), m.MINIMUM_FREE_BYTES)
        observe.assert_called_once_with(self.f.s['image_path'])

    def test_host_measurement_errors_and_invalid_values_fail_closed(self):
        with patch.object(m.os, 'statvfs', side_effect=OSError('private filesystem error')):
            self.refused('free_space_observation_unavailable', lambda: m.Host(self.f.s).free_bytes('synthetic-path'))
        for available, unit in [(-1, 4096), (1, 0), (True, 4096), (1, 1.5)]:
            with self.subTest(available=available, unit=unit):
                with patch.object(m.os, 'statvfs', return_value=SimpleNamespace(f_bavail=available, f_frsize=unit)):
                    self.refused('free_space_observation_invalid', lambda: m.Host(self.f.s).free_bytes('synthetic-path'))

    def test_original_pending_resume_is_reconciled_despite_low_space_without_replay(self):
        self.f.journal.begin('resume_existing_vm')
        self.f.host.free_space = {path: 0 for path in self.f.host.free_space}
        self.assertTrue(self.f.service.cycle(permit_actions=True)['ready'])
        self.assertIsNone(self.f.journal.value['pending'])
        self.assertEqual(self.f.host.actions, [])
        self.assertEqual(self.f.host.free_space_queries, [])

    def test_unknown_pending_resume_is_not_replaced_by_low_space_or_replayed(self):
        self.f.journal.begin('resume_existing_vm')
        self.f.host.state = 'Stopped'
        self.f.host.free_space = {path: 0 for path in self.f.host.free_space}
        self.refused('previous_resume_outcome_unconfirmed')
        self.assertEqual(self.f.journal.value['pending'], 'resume_existing_vm')
        self.assertEqual(self.f.host.actions, [])
        self.assertEqual(self.f.host.free_space_queries, [])

    def test_run_low_space_refusal_is_terminal_metadata_only_without_intent(self):
        self.f.host.state = 'Stopped'
        self.f.host.free_space[self.f.s['image_path']] = m.MINIMUM_FREE_BYTES - 1
        with patch.object(m, 'Host', return_value=self.f.host), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(m.main(['--settings', str(self.f.settings_path), '--run']), 0)
        self.assertEqual(json.loads(output.getvalue())['reason'], 'backing_free_space_below2gib')
        event = json.loads(Path(self.f.s['event_log']).read_text())
        self.assertEqual(set(event), {'at', 'pid', 'event'})
        self.assertEqual(event['event'], 'backing_free_space_below2gib')
        self.assertEqual(self.f.host.actions, [])
        self.assertFalse(Path(self.f.s['state_path']).exists())


class CapacityMonitoringTests(unittest.TestCase):
    tearDown = StartupTests.tearDown

    def setUp(self):
        StartupTests.setUp(self)
        self.now = 1800000000
        self.notices = []
        self.notice_status = 'submitted'
        self.f.s['capacity_monitor'] = {'enabled': True,
            'state_path': str(self.root / 'capacity.private.json'),
            'sample_interval_seconds': 60, 'max_samples': 4,
            'repeat_alert_seconds': 3600, 'notification': 'macos',
            'volumes': [{'id': 'project', 'path': '/Volumes/PRO-G40'},
                        {'id': 'runtime', 'path': '/Volumes/SupaRuntime', 'backing_group': 't7_runtime'}]}
        self.readings = {}
        self.available('project', 20 * 1024 ** 3)
        self.available('runtime', 20 * 1024 ** 3)
        self.f.json(self.f.settings_path, self.f.s)

    def available(self, name, free, *, total=100 * 1024 ** 3, device=12):
        self.readings[name] = {'id': name, 'status': m.CapacityMonitor.classify(free, total),
            'available_bytes': free, 'total_bytes': total, 'device_id': device, 'reason': None}

    def observe(self, volume):
        return copy.deepcopy(self.readings[volume['id']])

    def notify(self, sample):
        value = json.loads(Path(self.f.s['capacity_monitor']['state_path']).read_text())
        self.assertEqual(value['notification']['status'], 'dispatch_pending_or_unknown')
        self.notices.append(copy.deepcopy(sample))
        return self.notice_status

    def monitor(self):
        return m.CapacityMonitor(self.f.s, clock=lambda: self.now, observe=self.observe, notify=self.notify)

    def test_thresholds_match_health_warning_and_existing_resume_reserve(self):
        for free, total, expected in [(10*1024**3, 20*1024**3, 'healthy'),
            (10*1024**3-1, 20*1024**3, 'low'), (15*1024**3, 100*1024**3, 'healthy'),
            (15*1024**3-1, 100*1024**3, 'low'), (m.MINIMUM_FREE_BYTES, 100*1024**3, 'low'),
            (m.MINIMUM_FREE_BYTES-1, 100*1024**3, 'critical'), (0, 100*1024**3, 'critical')]:
            with self.subTest(free=free,total=total):
                self.assertEqual(m.CapacityMonitor.classify(free, total), expected)

    def test_samples_are_bounded_and_unchanged_status_is_not_written_each_loop(self):
        monitor = self.monitor(); monitor.tick(); p = monitor.path
        initial = p.read_bytes(); self.now += 30; monitor.tick()
        self.assertEqual(p.read_bytes(), initial)
        for _ in range(12):
            self.now += 60; monitor.tick()
        result = monitor.report()
        self.assertEqual(result['history_samples'], 4)
        self.assertLess(p.stat().st_size, m.MAX_CAPACITY_STATE)
        self.assertEqual(stat.S_IMODE(p.stat().st_mode), 0o600)
        self.assertFalse(self.notices)

    def test_critical_transition_is_sampled_without_waiting_for_interval(self):
        monitor = self.monitor(); monitor.tick(); self.now += 1
        self.available('project', m.MINIMUM_FREE_BYTES-1)
        result = monitor.tick()
        self.assertEqual(result['history_samples'], 2)
        self.assertEqual(result['volumes'][0]['status'], 'critical')
        self.assertEqual(len(self.notices), 1)
        self.assertEqual(result['notification']['status'], 'submitted')
        self.assertFalse(result['notification']['delivered_or_acknowledged'])
        self.assertFalse(result['authorizes_runtime_mutations'])

    def test_notice_deduplicates_across_restart_repeats_boundedly_and_reports_recovery(self):
        self.available('project', 1)
        monitor = self.monitor(); monitor.tick(); self.assertEqual(len(self.notices), 1)
        self.now += 30; monitor.tick(); self.monitor().tick()
        self.assertEqual(len(self.notices), 1)
        self.now += 3600; restarted = self.monitor(); restarted.tick()
        self.assertEqual(len(self.notices), 2)
        self.available('project', 20*1024**3); self.now += 1; restarted.tick()
        self.assertEqual(len(self.notices), 3)
        self.assertEqual(restarted.report()['status'], 'healthy')

    def test_unknown_dispatch_intent_survives_restart_without_immediate_replay(self):
        self.available('project', 1); self.notice_status = 'unknown'
        monitor = self.monitor(); monitor.tick()
        self.assertEqual(monitor.report()['notification']['status'], 'unknown')
        self.now += 60; restarted = self.monitor(); restarted.tick()
        self.assertEqual(len(self.notices), 1)
        self.assertFalse(restarted.report()['notification']['delivered_or_acknowledged'])

    def test_interrupted_dispatch_retains_intent_and_does_not_repeat_on_restart(self):
        self.available('project', 1); monitor = self.monitor()
        with patch.object(monitor, 'notify', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt): monitor.tick()
        restarted = self.monitor(); self.now += 30; restarted.tick()
        self.assertEqual(restarted.report()['notification']['status'], 'dispatch_pending_or_unknown')
        self.assertFalse(self.notices)

    def test_growth_is_observed_delta_without_forecast_or_adding_shared_backing(self):
        monitor = self.monitor(); monitor.tick(); self.now += 60
        self.available('runtime', 19*1024**3); monitor.tick()
        row = monitor.report()['volumes'][1]
        self.assertEqual(row['backing_group'], 't7_runtime')
        self.assertEqual(row['growth'], {'status':'observed','elapsed_seconds':60,
            'available_delta_bytes':-1024**3,'net_consumed_bytes':1024**3,'samples':2,'forecast':False})
        self.assertTrue(monitor.report()['capacity_is_not_additive_across_backing_groups'])
        self.assertNotIn('total_available_bytes', monitor.report())

    def test_device_change_unavailable_gap_and_clock_regression_withhold_growth(self):
        monitor = self.monitor(); monitor.tick(); self.now += 60
        self.available('runtime', 19*1024**3,device=99); monitor.tick()
        self.assertEqual(monitor.report()['volumes'][1]['growth']['status'], 'unconfirmed')
        self.now += 60; self.readings['runtime'] = dict(self.readings['runtime'], status='unavailable',
            available_bytes=None,total_bytes=None,device_id=None,reason='measurement_unavailable'); monitor.tick()
        self.now += 60; self.available('runtime',18*1024**3,device=99); monitor.tick()
        self.assertEqual(monitor.report()['volumes'][1]['growth']['status'], 'unconfirmed')
        before = monitor.path.read_bytes(); self.now -= 120
        self.assertEqual(monitor.tick()['status'], 'unconfirmed')
        self.assertEqual(monitor.path.read_bytes(), before)

    def test_status_becomes_unconfirmed_when_observer_samples_are_stale(self):
        monitor = self.monitor(); monitor.tick(); self.now += 181
        self.assertEqual(self.monitor().report()['status'], 'unconfirmed')

    def test_corrupt_oversized_or_changed_state_is_preserved_without_notification(self):
        monitor = self.monitor(); monitor.tick(); p = monitor.path
        p.write_bytes(b'not-json'); p.chmod(0o600)
        with self.assertRaises(m.Refusal): self.monitor()
        self.assertEqual(p.read_bytes(), b'not-json')
        self.now += 60
        with self.assertRaisesRegex(m.Refusal, 'capacity_state_changed'): monitor.tick()
        p.write_bytes(b' '*(m.MAX_CAPACITY_STATE+1))
        with self.assertRaisesRegex(m.Refusal, 'capacity_state_too_large'): self.monitor()
        self.assertFalse(self.notices)

    def test_symlink_and_hardlink_state_are_refused_without_touching_targets(self):
        p=Path(self.f.s['capacity_monitor']['state_path']); other=self.root/'unrelated'
        self.f.file(other,'preserve'); p.symlink_to(other)
        with self.assertRaises(m.Refusal): self.monitor()
        self.assertEqual(other.read_text(),'preserve'); p.unlink(); os.link(other,p)
        with self.assertRaises(m.Refusal): self.monitor()
        self.assertEqual(other.read_text(),'preserve')

    def test_measurement_uses_unprivileged_available_blocks_and_refuses_placeholder(self):
        p=SimpleNamespace(lstat=lambda:SimpleNamespace(st_dev=12,st_mode=stat.S_IFDIR|0o755),
            parent=SimpleNamespace(lstat=lambda:SimpleNamespace(st_dev=11)),resolve=lambda:p)
        space=SimpleNamespace(f_bavail=1,f_blocks=100,f_frsize=4096,f_bfree=999999999)
        with patch.object(m,'Path',return_value=p), patch.object(m.os,'statvfs',return_value=space):
            # Root comparison is immaterial here; different devices prove a mount.
            value=m.CapacityMonitor.observe_volume({'id':'runtime','path':'/Volumes/fake'})
        self.assertEqual(value['available_bytes'],4096)
        self.assertEqual(value['status'],'critical')
        with patch.object(m.os,'statvfs',side_effect=OSError('private-detail')):
            value=m.CapacityMonitor.observe_volume({'id':'runtime','path':str(self.root)})
        self.assertEqual(value['status'],'unavailable')
        self.assertNotIn('private-detail',json.dumps(value))

    def test_local_notification_records_only_submission_and_bounds_unknown_errors(self):
        monitor=self.monitor(); sample=monitor.sample()
        with patch.object(m.subprocess,'run',return_value=SimpleNamespace(returncode=0)) as call:
            self.assertEqual(monitor.local_notification(sample),'submitted')
            self.assertEqual(call.call_args.args[0][0],'/usr/bin/osascript')
            self.assertEqual(call.call_args.kwargs['timeout'],5)
        for error in (OSError('private'),subprocess.TimeoutExpired('private',5)):
            with patch.object(m.subprocess,'run',side_effect=error):
                self.assertEqual(monitor.local_notification(sample),'unknown')

    def test_read_only_capacity_commands_do_not_create_state_or_notify(self):
        monitor=self.monitor()
        with patch.object(m,'CapacityMonitor',return_value=monitor), patch.object(m,'Host',side_effect=AssertionError('runtime accessed')):
            for flag in ('--capacity-check','--capacity-status'):
                with self.subTest(flag=flag), contextlib.redirect_stdout(io.StringIO()) as output:
                    code=m.main(['--settings',str(self.f.settings_path),flag])
                    self.assertIn(code,(0,2));self.assertFalse(json.loads(output.getvalue())['authorizes_runtime_mutations'])
        self.assertFalse(monitor.path.exists());self.assertFalse(self.notices)

    def test_existing_runtime_check_remains_read_only_when_monitor_is_enabled(self):
        with patch.object(m,'Host',return_value=self.f.host),contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(m.main(['--settings',str(self.f.settings_path),'--check']),0)
        self.assertFalse(Path(self.f.s['capacity_monitor']['state_path']).exists())

    def test_running_watcher_collects_low_space_without_runtime_action_or_reserve_change(self):
        self.available('project',1);self.f.host.free_space={p:0 for p in self.f.host.free_space}
        monitor=self.monitor()
        with patch.object(m,'Host',return_value=self.f.host),patch.object(m,'CapacityMonitor',return_value=monitor),contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(m.main(['--settings',str(self.f.settings_path),'--run']),0)
        self.assertEqual(self.f.host.actions,[]);self.assertEqual(self.f.host.free_space_queries,[])
        self.assertEqual(m.MINIMUM_FREE_BYTES,2*1024**3)
        self.assertTrue(monitor.path.exists());self.assertEqual(len(self.notices),1)

    def test_monitor_failure_does_not_restart_or_stop_running_runtime(self):
        monitor=self.monitor()
        with patch.object(monitor,'tick',side_effect=OSError('private-detail')),patch.object(m,'Host',return_value=self.f.host),patch.object(m,'CapacityMonitor',return_value=monitor),contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(m.main(['--settings',str(self.f.settings_path),'--run']),0)
        self.assertEqual(self.f.host.actions,[])
        text=Path(self.f.s['event_log']).read_text()
        self.assertIn('capacity_monitor_unconfirmed',text);self.assertNotIn('private-detail',text)

    def test_disabled_monitor_creates_no_state_or_side_effect(self):
        self.f.s.pop('capacity_monitor');monitor=self.monitor()
        self.assertEqual(monitor.tick()['status'],'disabled');self.assertFalse(self.notices)

    def test_failed_capacity_logging_does_not_escape_the_monitor_failure_boundary(self):
        monitor=self.monitor(); original=m.Service.event
        def event(service, code):
            if code=='capacity_monitor_unconfirmed':raise OSError('full-capacity-state-volume')
            return original(service,code)
        with patch.object(monitor,'tick',side_effect=OSError('full-capacity-state-volume')),patch.object(m.Service,'event',event),patch.object(m,'Host',return_value=self.f.host),patch.object(m,'CapacityMonitor',return_value=monitor),contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(m.main(['--settings',str(self.f.settings_path),'--run']),0)
        self.assertEqual(self.f.host.actions,[])


class RuntimeRefusalMonitoringTests(unittest.TestCase):
    setUp = CapacityMonitoringTests.setUp
    tearDown = StartupTests.tearDown
    available = CapacityMonitoringTests.available
    observe = CapacityMonitoringTests.observe
    notify = CapacityMonitoringTests.notify
    monitor = CapacityMonitoringTests.monitor

    def run_monitor(self, turns=3, after_sleep=None):
        monitor = self.monitor()
        sleeps = []

        def sleep(seconds):
            sleeps.append(seconds)
            self.now += self.f.s['capacity_monitor']['sample_interval_seconds']
            if after_sleep is not None:
                after_sleep()
            if len(sleeps) >= turns:
                raise KeyboardInterrupt()

        with patch.object(m, 'Host', return_value=self.f.host), \
                patch.object(m, 'CapacityMonitor', return_value=monitor), \
                patch.object(self.f.host, 'sleep', side_effect=sleep), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(m.main(['--settings', str(self.f.settings_path), '--run']), 0)
        return monitor, sleeps, output.getvalue()

    def test_metadata_timeout_latches_runtime_but_capacity_keeps_sampling(self):
        def later_vm_stopped():
            self.f.host.state = 'Stopped'
        with patch.object(self.f.host, 'image_info', side_effect=m.Refusal('metadata_command_timeout')) as read:
            monitor, sleeps, output = self.run_monitor(after_sleep=later_vm_stopped)
        self.assertEqual(read.call_count, 1)
        self.assertEqual(len(sleeps), 3)
        self.assertEqual(len(monitor.value['history']), 3)
        self.assertEqual(monitor.value['history'][-1]['at'] - monitor.value['history'][0]['at'], 120)
        self.assertEqual(self.f.host.actions, [])
        self.assertEqual(self.f.host.requests, [])
        state = json.loads(Path(self.f.s['state_path']).read_text())
        self.assertEqual(state['runtime_refusal']['reason'], 'metadata_command_timeout')
        notice = json.loads(output)
        self.assertTrue(notice['runtime_mutations_refused'])
        self.assertTrue(notice['capacity_monitor_continues'])
        self.assertTrue(notice['requires_explicit_reconciliation'])

    def test_latch_survives_new_process_and_boot_without_coordinator_or_runtime_probe(self):
        self.f.journal.begin('resume_existing_vm')
        self.f.journal.refuse_runtime('external_action_unconfirmed')
        before = Path(self.f.s['state_path']).read_bytes()
        next_boot = m.Journal(self.f.s, 'different-boot')
        self.assertEqual(next_boot.runtime_refusal()['reason'], 'external_action_unconfirmed')
        self.assertEqual(next_boot.value['pending'], 'resume_existing_vm')
        with patch.object(m.operation_lock, 'coordinated', side_effect=AssertionError('runtime coordinator retried')), \
                patch.object(self.f.host, 'image_info', side_effect=AssertionError('runtime probed')):
            monitor, sleeps, output = self.run_monitor()
        self.assertEqual(len(sleeps), 3)
        self.assertEqual(len(monitor.value['history']), 3)
        self.assertEqual(Path(self.f.s['state_path']).read_bytes(), before)
        self.assertEqual(self.f.host.actions, [])
        self.assertEqual(json.loads(output)['reason'], 'external_action_unconfirmed')

    def test_latched_journal_prevents_begin_completion_and_direct_runtime_cycle(self):
        self.f.journal.begin('resume_existing_vm')
        self.f.journal.refuse_runtime('runtime_ready_timeout')
        before = Path(self.f.s['state_path']).read_bytes()
        for action in (lambda: self.f.journal.begin('attach_retained_image'),
                       self.f.journal.complete,
                       lambda: self.f.service.cycle(permit_actions=True)):
            with self.assertRaisesRegex(m.Refusal, '^runtime_refusal_requires_reconciliation$'):
                action()
        self.assertEqual(self.f.journal.value['pending'], 'resume_existing_vm')
        self.assertEqual(Path(self.f.s['state_path']).read_bytes(), before)
        self.assertEqual(self.f.host.actions, [])
        self.assertEqual(self.f.host.requests, [])

    def test_read_only_check_exposes_latch_without_changing_or_clearing_it(self):
        self.f.journal.refuse_runtime('metadata_command_timeout')
        before = {p: p.read_bytes() for p in self.root.iterdir() if p.is_file()}
        with patch.object(m, 'Host', return_value=self.f.host), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(m.main(['--settings', str(self.f.settings_path), '--check']), 2)
        result = json.loads(output.getvalue())
        self.assertFalse(result['ready'])
        self.assertTrue(result['runtime_mutations_refused'])
        self.assertEqual(result['reason'], 'metadata_command_timeout')
        self.assertEqual({p: p.read_bytes() for p in self.root.iterdir() if p.is_file()}, before)
        self.assertFalse(Path(self.f.s['capacity_monitor']['state_path']).exists())
        self.assertEqual(self.f.host.actions, [])
        self.assertEqual(self.f.host.requests, [])

    def test_unpersisted_latch_remains_fail_stop_not_launchd_failure_retry(self):
        monitor = self.monitor()
        with patch.object(m, 'Host', return_value=self.f.host), \
                patch.object(m, 'CapacityMonitor', return_value=monitor), \
                patch.object(self.f.host, 'image_info', side_effect=m.Refusal('metadata_command_timeout')), \
                patch.object(m.Journal, 'write', side_effect=OSError('private-disk-error')), \
                patch.object(self.f.host, 'sleep') as sleep, \
                contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(m.main(['--settings', str(self.f.settings_path), '--run']), 0)
        self.assertEqual(json.loads(output.getvalue())['reason'], 'runtime_refusal_persistence_unconfirmed')
        self.assertNotIn('private-disk-error', output.getvalue())
        sleep.assert_not_called()
        self.assertEqual(self.f.host.actions, [])

    def test_event_log_failure_does_not_stop_fenced_capacity_monitor(self):
        with patch.object(self.f.host, 'image_info', side_effect=m.Refusal('metadata_command_timeout')) as read, \
                patch.object(m.Service, 'event', side_effect=OSError('private-log-error')):
            monitor, sleeps, output = self.run_monitor()
        self.assertEqual(read.call_count, 1)
        self.assertEqual(len(monitor.value['history']), 3)
        self.assertEqual(len(sleeps), 3)
        self.assertNotIn('private-log-error', output)
        self.assertEqual(self.f.host.actions, [])

    def test_latch_does_not_turn_disabled_capacity_into_new_runtime_retry_loop(self):
        self.f.journal.refuse_runtime('metadata_command_timeout')
        self.f.s.pop('capacity_monitor')
        self.f.json(self.f.settings_path, self.f.s)
        with patch.object(m, 'Host', return_value=self.f.host), \
                patch.object(self.f.host, 'sleep') as sleep, \
                contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(m.main(['--settings', str(self.f.settings_path), '--run']), 0)
        self.assertEqual(json.loads(output.getvalue())['reason'], 'runtime_refusal_requires_reconciliation')
        sleep.assert_not_called()
        self.assertEqual(self.f.host.actions, [])


class SourceVolumeStartupTests(unittest.TestCase):
    setUp = StartupTests.setUp
    tearDown = StartupTests.tearDown
    refused = StartupTests.refused
    """Only fake source-volume availability; never a host mount/start."""
    @staticmethod
    def volume(*, mounted=True, error=None, mode=stat.S_IFDIR | 0o700):
        state = {'mounted': mounted}
        parent = SimpleNamespace(lstat=lambda: SimpleNamespace(st_mode=stat.S_IFDIR | 0o755, st_dev=11))
        def observe():
            if error is not None:
                raise error
            return SimpleNamespace(st_mode=mode, st_dev=12 if state['mounted'] else 11)
        return SimpleNamespace(lstat=observe, parent=parent), state

    def test_only_configured_external_source_volume_is_classified(self):
        self.assertEqual(m.source_volume_root('/Volumes/T7/retained/image.sparsebundle'), Path('/Volumes/T7'))
        self.assertIsNone(m.source_volume_root('/tmp/fake/retained/image.sparsebundle'))
        with self.assertRaisesRegex(m.Refusal, '^source_volume_path_invalid$'):
            m.source_volume_root('/Volumes/T7/../different/image.sparsebundle')

    def test_unmounted_or_absent_source_waits_with_no_actions_requests_or_journal(self):
        for options in ({'mounted': False}, {'error': FileNotFoundError()}):
            with self.subTest(options=options):
                volume, _ = self.volume(**options)
                pending = self.f.journal.value.copy()
                with patch.object(m, 'source_volume_root', return_value=volume):
                    result = self.f.service.cycle(permit_actions=True)
                self.assertFalse(result['ready'])
                self.assertEqual(result['reason'], 'source_volume_unavailable')
                self.assertEqual(self.f.host.actions, [])
                self.assertEqual(self.f.host.requests, [])
                self.assertEqual(self.f.journal.value, pending)
                self.assertFalse(Path(self.f.s['state_path']).exists())

    def test_run_monitor_retries_source_then_validates_existing_runtime_without_activation(self):
        volume, state = self.volume(mounted=False)
        sleeps = []
        def sleep(seconds):
            sleeps.append(seconds)
            if len(sleeps) == 1:
                self.assertEqual(self.f.host.actions, [])
                self.assertEqual(self.f.host.requests, [])
                state['mounted'] = True
            else:
                raise KeyboardInterrupt()
        with patch.object(m, 'source_volume_root', return_value=volume), patch.object(m, 'Host', return_value=self.f.host), \
                patch.object(self.f.host, 'sleep', side_effect=sleep), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(m.main(['--settings', str(self.f.settings_path), '--run']), 0)
        self.assertEqual(len(sleeps), 2)
        self.assertEqual(self.f.host.actions, [])
        self.assertTrue(self.f.host.requests)
        events = [json.loads(line)['event'] for line in Path(self.f.s['event_log']).read_text().splitlines()]
        self.assertEqual(events, ['source_volume_unavailable', 'retained_runtime_ready'])

    def test_late_source_allows_only_original_attach_then_existing_vm_resume(self):
        self.f.detach_fake()
        self.f.host.state = 'Stopped'
        volume, state = self.volume(mounted=False)
        with patch.object(m, 'source_volume_root', return_value=volume):
            self.assertFalse(self.f.service.cycle(permit_actions=True)['ready'])
            self.assertEqual(self.f.host.actions, [])
            self.assertIsNone(self.f.journal.value['pending'])
            state['mounted'] = True
            self.assertTrue(self.f.service.cycle(permit_actions=True)['ready'])
            self.assertTrue(self.f.service.cycle(permit_actions=True)['ready'])
        self.assertEqual(self.f.host.actions, [
            [self.f.s['hdiutil'], 'attach', '-nobrowse', '-mountpoint', self.f.s['mount_point'], '-plist', self.f.s['image_path']],
            [self.f.s['colima_binary'], 'start', '--profile', 'supabase-local', '--activate=false', '--save-config=false', '--template=false']])
        self.assertIsNone(self.f.journal.value['pending'])
        self.assertEqual(self.f.journal.value['resumes'], 1)

    def test_check_mode_reports_pending_without_creating_files(self):
        volume, _ = self.volume(mounted=False)
        before = set(self.root.iterdir())
        with patch.object(m, 'source_volume_root', return_value=volume), patch.object(m, 'Host', return_value=self.f.host), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(m.main(['--settings', str(self.f.settings_path), '--check']), 2)
        self.assertEqual(json.loads(output.getvalue())['reason'], 'source_volume_unavailable')
        self.assertEqual(set(self.root.iterdir()), before)
        self.assertEqual(self.f.host.actions, [])
        self.assertEqual(self.f.host.requests, [])

    def test_mounted_source_missing_image_stays_terminal_without_retry(self):
        volume, _ = self.volume()
        Path(self.f.s['image_path']).rename(self.root / 'retained-image-not-at-configured-path')
        with patch.object(m, 'source_volume_root', return_value=volume), patch.object(m, 'Host', return_value=self.f.host), \
                patch.object(self.f.host, 'sleep') as sleep, contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(m.main(['--settings', str(self.f.settings_path), '--run']), 0)
        self.assertEqual(json.loads(output.getvalue())['reason'], 'required_directory_unavailable')
        sleep.assert_not_called()
        self.assertEqual(self.f.host.actions, [])

    def test_source_permission_or_symlink_refusals_are_terminal_not_availability(self):
        for options, reason in [({'error': PermissionError()}, 'source_volume_inspection_refused'),
                                ({'mode': stat.S_IFLNK | 0o777}, 'source_volume_is_not_plain')]:
            with self.subTest(reason=reason):
                volume, _ = self.volume(**options)
                with patch.object(m, 'source_volume_root', return_value=volume):
                    self.refused(reason)
                self.assertEqual(self.f.host.actions, [])
                self.assertEqual(self.f.host.requests, [])

    def test_waiting_never_clears_or_replays_prior_unknown_action(self):
        self.f.journal.begin('resume_existing_vm')
        self.f.host.state = 'Stopped'
        volume, state = self.volume(mounted=False)
        with patch.object(m, 'source_volume_root', return_value=volume):
            self.assertFalse(self.f.service.cycle(permit_actions=True)['ready'])
            self.assertEqual(self.f.journal.value['pending'], 'resume_existing_vm')
            self.assertEqual(self.f.host.actions, [])
            state['mounted'] = True
            self.refused('previous_resume_outcome_unconfirmed')
        restored = m.Journal(self.f.s, 'next-boot')
        self.assertEqual(restored.value['pending'], 'resume_existing_vm')
        self.assertEqual(self.f.host.actions, [])


if __name__ == '__main__':
    unittest.main(verbosity=2)

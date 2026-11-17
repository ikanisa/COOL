#!/usr/bin/env python3
"""Retained SupaRuntime/Colima login recovery. No bootstrap or container writer.

Only --run can attach the one retained image or resume the one existing VM.
--check is read-only. Incomplete external actions stay pending until observed;
unknown outcomes never authorize a replay. A terminal runtime refusal is durably
latched before continuing enabled capacity monitoring; runtime recovery remains
blocked across process/host restarts until explicit operator reconciliation.
Without qualified monitoring or a durable latch, a known refusal still exits
successfully to stop restart loops.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import http.client
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import socket
import stat
import subprocess
import sys
import time
import yaml

# The production launch agent uses Python -I, which excludes this script's
# directory from sys.path. Load the protected, byte-qualified sibling by
# explicit physical path instead of relying on ambient import paths.
_coord_path = Path(__file__).resolve().parent / 'operation_lock.py'
_coord_stat = _coord_path.lstat()
if (_coord_path.resolve() != _coord_path or not stat.S_ISREG(_coord_stat.st_mode)
    or _coord_stat.st_uid != os.getuid() or _coord_stat.st_nlink != 1
    or stat.S_IMODE(_coord_stat.st_mode) != 0o600):
    raise RuntimeError('operation_coordinator_identity')
_coord_spec = importlib.util.spec_from_file_location('collect_host_operation_lock', _coord_path)
if _coord_spec is None or _coord_spec.loader is None:
    raise RuntimeError('operation_coordinator_unavailable')
operation_lock = importlib.util.module_from_spec(_coord_spec)
_coord_spec.loader.exec_module(operation_lock)

sys.dont_write_bytecode = True
FORMAT = 'collect.retained-runtime-startup.v1'
MAX_OUTPUT = 1024 * 1024
MAX_LOG = 128 * 1024
MINIMUM_FREE_BYTES = 2 * 1024 ** 3
CAPACITY_FORMAT = 'collect.retained-capacity.v1'
CAPACITY_WARN_BYTES = 10 * 1024 ** 3
CAPACITY_WARN_RATIO = .15
MAX_CAPACITY_STATE = 256 * 1024


class Refusal(RuntimeError):
    """Fixed metadata-only reason; never daemon output or credential material."""


def require(condition, code):
    if not condition:
        raise Refusal(code)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def derived_digest(raw, ignore_ssh_port=False):
    try:
        value = yaml.safe_load(raw)
        require(isinstance(value, dict), 'derived_vm_metadata_invalid')
        if ignore_ssh_port:
            ssh = value.get('ssh', {})
            require(isinstance(ssh, dict), 'derived_vm_metadata_invalid')
            ssh.pop('localPort', None)
        return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    except (ValueError, TypeError, yaml.YAMLError):
        raise Refusal('derived_vm_metadata_invalid') from None


def plain_file(path, uid, *, private=False, expected_hash=None, expected_size=None):
    p = Path(path)
    try:
        s = p.lstat()
    except OSError:
        raise Refusal('required_file_unavailable') from None
    require(stat.S_ISREG(s.st_mode) and s.st_uid == uid, 'required_file_identity_mismatch')
    require(not (s.st_mode & 0o022), 'required_file_writable_by_others')
    if private:
        require(stat.S_IMODE(s.st_mode) == 0o600, 'private_file_mode_mismatch')
    if expected_size is not None:
        require(s.st_size == expected_size, 'retained_disk_size_mismatch')
    if expected_hash is not None:
        require(digest(p) == expected_hash, 'required_file_content_mismatch')
    return p


def plain_dir(path, uid=None, *, private=False):
    p = Path(path)
    try:
        s = p.lstat()
    except OSError:
        raise Refusal('required_directory_unavailable') from None
    require(stat.S_ISDIR(s.st_mode), 'directory_is_not_plain')
    if uid is not None:
        require(s.st_uid == uid, 'directory_owner_mismatch')
    require(not (s.st_mode & 0o022), 'directory_writable_by_others')
    if private:
        require(stat.S_IMODE(s.st_mode) == 0o700, 'private_directory_mode_mismatch')
    return p


def source_volume_root(image_path):
    """Only a configured macOS external image-source volume can be pending."""
    path = Path(image_path)
    if len(path.parts) >= 3 and path.parts[:2] == ('/', 'Volumes'):
        require('..' not in path.parts, 'source_volume_path_invalid')
        return Path('/Volumes') / path.parts[2]
    return None


def source_volume_available(image_path):
    root = source_volume_root(image_path)
    if root is None:
        return True
    try:
        observed = root.lstat()
    except FileNotFoundError:
        return False
    except OSError:
        raise Refusal('source_volume_inspection_refused') from None
    require(stat.S_ISDIR(observed.st_mode), 'source_volume_is_not_plain')
    try:
        parent = root.parent.lstat()
    except OSError:
        raise Refusal('source_volume_inspection_refused') from None
    require(stat.S_ISDIR(parent.st_mode), 'source_volume_parent_is_not_plain')
    # /Volumes/<name> must be an actual mounted filesystem, not an empty
    # launch-time placeholder. Do not ask Disk Arbitration to mount it, create
    # a directory, or infer missing image/VM files on an already mounted source.
    return observed.st_dev != parent.st_dev


def read_json(path):
    try:
        return json.loads(Path(path).read_bytes())
    except (OSError, ValueError):
        raise Refusal('metadata_json_unavailable') from None


def rows(raw):
    try:
        parsed = json.loads(raw)
        return parsed if isinstance(parsed, list) else [parsed]
    except ValueError:
        try:
            return [json.loads(line) for line in raw.splitlines() if line.strip()]
        except ValueError:
            raise Refusal('instance_metadata_invalid') from None


class UnixHTTP(http.client.HTTPConnection):
    def __init__(self, path, timeout):
        super().__init__('localhost', timeout=timeout)
        self.path = path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self.path)


class Host:
    def __init__(self, settings):
        self.s = settings
        self.env = {
            'HOME': settings['user_home'], 'USER': settings['user_name'],
            'LOGNAME': settings['user_name'], 'LANG': 'en_US.UTF-8',
            'PATH': settings['tool_path'],
            'COLIMA_HOME': settings['colima_home'], 'LIMA_HOME': settings['lima_home'],
            'XDG_CACHE_HOME': settings['cache_home'],
            'DOCKER_CONFIG': settings['docker_config'],
            'COLIMA_SAVE_CONFIG': 'false',
            'TMPDIR': settings['runtime_tmp'],
        }

    def command(self, argv, *, mutation=False, timeout=None):
        # Mutation output is discarded, never sent to launchd or retained logs.
        try:
            result = subprocess.run(
                argv, env=self.env, cwd=self.s['working_directory'],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL if mutation else subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=timeout or self.s['read_timeout_seconds'],
                start_new_session=mutation, check=False,
            )
        except subprocess.TimeoutExpired:
            raise Refusal('external_action_unconfirmed' if mutation else 'metadata_command_timeout') from None
        except OSError:
            raise Refusal('external_action_unconfirmed' if mutation else 'metadata_command_unavailable') from None
        if mutation:
            # Even a nonzero exit is reconciled by observation before concluding.
            return result.returncode
        require(result.returncode == 0, 'metadata_command_refused')
        require(len(result.stdout) <= MAX_OUTPUT, 'metadata_response_too_large')
        return result.stdout

    def image_info(self):
        try:
            return plistlib.loads(self.command([self.s['hdiutil'], 'info', '-plist']))
        except (ValueError, plistlib.InvalidFileException):
            raise Refusal('image_inventory_invalid') from None

    def volume_info(self):
        try:
            return plistlib.loads(self.command([self.s['diskutil'], 'info', '-plist', self.s['mount_point']]))
        except (ValueError, plistlib.InvalidFileException):
            raise Refusal('volume_inventory_invalid') from None

    def instances(self):
        c = rows(self.command([self.s['colima_binary'], 'list', '--json']))
        l = rows(self.command([self.s['limactl_binary'], 'list', '--json', self.s['lima_instance']]))
        return c, l

    def docker_get(self, path):
        connection = UnixHTTP(self.s['docker_socket'], self.s['read_timeout_seconds'])
        try:
            connection.request('GET', path)
            response = connection.getresponse()
            body = response.read(MAX_OUTPUT + 1)
            require(len(body) <= MAX_OUTPUT, 'docker_metadata_too_large')
            require(response.status == 200, 'docker_metadata_refused')
            return json.loads(body)
        except Refusal:
            raise
        except (OSError, ValueError, http.client.HTTPException):
            raise Refusal('docker_unreachable') from None
        finally:
            connection.close()

    def boot_id(self):
        raw = self.command(['/usr/sbin/sysctl', '-n', 'kern.boottime'])
        match = re.search(rb'sec\s*=\s*(\d+)', raw)
        require(match is not None, 'boot_identity_unavailable')
        return match[1].decode('ascii')

    def free_bytes(self, path):
        try:
            space = os.statvfs(path)
        except OSError:
            raise Refusal('free_space_observation_unavailable') from None
        require(type(space.f_bavail) is int and space.f_bavail >= 0 and
                type(space.f_frsize) is int and space.f_frsize > 0,
                'free_space_observation_invalid')
        return space.f_bavail * space.f_frsize

    def sleep(self, seconds):
        time.sleep(seconds)


class Journal:
    def __init__(self, settings, boot_id):
        self.s = settings
        self.path = Path(settings['state_path'])
        if os.path.lexists(self.path):
            plain_file(self.path, settings['uid'], private=True)
            self.value = read_json(self.path)
            require(self.value.get('format') == FORMAT, 'journal_format_mismatch')
        else:
            self.value = {'format': FORMAT, 'pending': None}
        if self.value.get('boot_id') != boot_id:
            # A pending action survives a host restart and must be reconciled.
            self.value.update(boot_id=boot_id, resumes=0, last_resume_at=0)

    def runtime_refusal(self):
        refusal = self.value.get('runtime_refusal')
        require(refusal is None or isinstance(refusal, dict)
                and set(refusal) == {'reason', 'at'}
                and isinstance(refusal.get('reason'), str)
                and re.fullmatch(r'[a-z0-9_]{1,128}', refusal['reason'])
                and type(refusal.get('at')) is int and refusal['at'] >= 0,
                'runtime_refusal_metadata_invalid')
        return refusal

    def refuse_runtime(self, reason):
        # Preserve the first terminal reason and every existing pending action.
        # There is intentionally no automatic or time-based clearing path.
        if self.runtime_refusal() is None:
            self.value['runtime_refusal'] = {'reason': reason, 'at': int(time.time())}
            self.runtime_refusal()
            try:
                self.write()
            except Exception:
                raise Refusal('runtime_refusal_persistence_unconfirmed') from None

    def write(self):
        parent = plain_dir(self.path.parent, self.s['uid'], private=True)
        if os.path.lexists(self.path):
            plain_file(self.path, self.s['uid'], private=True)
        temporary = parent / ('.state-' + str(os.getpid()) + '.tmp')
        try:
            fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        except OSError:
            raise Refusal('journal_temporary_collision') from None
        try:
            with os.fdopen(fd, 'w') as handle:
                json.dump(self.value, handle, sort_keys=True)
                handle.write('\n')
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, self.path)
            try:
                directory_fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
                try:
                    os.fsync(directory_fd)
                finally:
                    os.close(directory_fd)
            except OSError:
                # A durable file alone does not make its renamed directory
                # entry durable. Refuse before any external action if the
                # containing directory cannot be synchronized as well.
                raise Refusal('journal_directory_sync_failed') from None
        finally:
            if temporary.exists():
                temporary.unlink()

    def begin(self, action):
        require(self.runtime_refusal() is None, 'runtime_refusal_requires_reconciliation')
        require(self.value.get('pending') is None, 'external_action_already_pending')
        self.value['pending'] = action
        if action == 'resume_existing_vm':
            self.value['resumes'] = self.value.get('resumes', 0) + 1
            self.value['last_resume_at'] = time.time()
        self.write()

    def complete(self):
        require(self.runtime_refusal() is None, 'runtime_refusal_requires_reconciliation')
        self.value['pending'] = None
        self.write()


class CapacityMonitor:
    """Bounded host observations, independent of runtime recovery authority.

    Local notification submission is never recipient acknowledgement. An intent
    is persisted first, so an unknown osascript outcome is not immediately replayed.
    """
    def __init__(self, settings, *, clock=None, observe=None, notify=None):
        self.settings = settings
        self.clock = clock or time.time
        self.observe = observe or self.observe_volume
        self.notify = notify or self.local_notification
        self.config = settings.get('capacity_monitor')
        require(self.config is None or isinstance(self.config, dict)
                and type(self.config.get('enabled')) is bool, 'capacity_settings_invalid')
        self.enabled = isinstance(self.config, dict) and self.config.get('enabled') is True
        self.stored_digest = None
        if not self.enabled:
            return
        c = self.config
        self.path = Path(c['state_path'])
        require(self.path.is_absolute() and self.path.parent == Path(settings['working_directory'])
                and self.path.resolve() == self.path, 'capacity_state_path_invalid')
        self.interval = c.get('sample_interval_seconds', 300)
        self.limit = c.get('max_samples', 288)
        self.repeat = c.get('repeat_alert_seconds', 21600)
        self.channel = c.get('notification', 'none')
        require(type(self.interval) is int and 60 <= self.interval <= 3600
                and type(self.limit) is int and 2 <= self.limit <= 288
                and type(self.repeat) is int and 3600 <= self.repeat <= 86400
                and self.channel in ('none', 'macos'), 'capacity_settings_invalid')
        self.volumes = c.get('volumes')
        require(isinstance(self.volumes, list) and 1 <= len(self.volumes) <= 4,
                'capacity_volumes_invalid')
        ids = set()
        for v in self.volumes:
            require(isinstance(v, dict) and isinstance(v.get('id'), str)
                    and re.fullmatch(r'[a-z0-9_]{1,32}', v['id']) and v['id'] not in ids,
                    'capacity_volume_identity_invalid')
            ids.add(v['id'])
            p = Path(v.get('path', ''))
            require(p.is_absolute() and '..' not in p.parts
                    and isinstance(v.get('backing_group', v['id']), str)
                    and re.fullmatch(r'[a-z0-9_]{1,32}', v.get('backing_group', v['id'])),
                    'capacity_volume_path_invalid')
        self.binding = hashlib.sha256(json.dumps(c, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        self.value = {'format': CAPACITY_FORMAT, 'configuration_sha256': self.binding,
                      'history': [], 'notification': {'at': None, 'signature': '', 'status': 'not_attempted'}}
        if os.path.lexists(self.path):
            self._file()
            raw = self.path.read_bytes()
            require(len(raw) <= MAX_CAPACITY_STATE, 'capacity_state_too_large')
            try:
                value = json.loads(raw)
            except ValueError:
                raise Refusal('capacity_state_invalid') from None
            require(isinstance(value, dict) and value.get('format') == CAPACITY_FORMAT
                    and value.get('configuration_sha256') == self.binding, 'capacity_state_binding_mismatch')
            history = value.get('history')
            require(isinstance(history, list) and len(history) <= self.limit, 'capacity_history_invalid')
            for sample in history:
                require(isinstance(sample, dict) and type(sample.get('at')) in (int, float)
                        and 0 <= sample['at'] < 1e12 and isinstance(sample.get('volumes'), list)
                        and {v.get('id') for v in sample['volumes'] if isinstance(v, dict)} == ids
                        and len(sample['volumes']) == len(ids), 'capacity_history_invalid')
                for v in sample['volumes']:
                    require(v.get('status') in ('healthy', 'low', 'critical', 'unavailable')
                            and all(v.get(k) is None or type(v.get(k)) is int and v[k] >= 0
                                    for k in ('available_bytes', 'total_bytes', 'device_id'))
                            and v.get('reason') in (None, 'unmounted', 'measurement_unavailable', 'measurement_invalid'),
                            'capacity_history_invalid')
                    require((v['status'] == 'unavailable' and v['available_bytes'] is None
                             and v['total_bytes'] is None and v['device_id'] is None) or
                            (v['status'] != 'unavailable' and type(v['available_bytes']) is int
                             and type(v['total_bytes']) is int and type(v['device_id']) is int
                             and 0 <= v['available_bytes'] <= v['total_bytes'] and v['total_bytes'] > 0),
                            'capacity_history_invalid')
            require([sample['at'] for sample in history] == sorted(sample['at'] for sample in history),
                    'capacity_history_time_invalid')
            notice = value.get('notification')
            require(isinstance(notice, dict) and notice.get('status') in
                    ('not_attempted', 'dispatch_pending_or_unknown', 'submitted', 'refused', 'unknown')
                    and (notice.get('at') is None or type(notice.get('at')) in (int, float)
                         and 0 <= notice['at'] < 1e12)
                    and isinstance(notice.get('signature'), str)
                    and re.fullmatch(r'[a-z0-9_:|]*', notice['signature']), 'capacity_notification_invalid')
            # Retain only the defined metadata, never arbitrary fields from a file.
            self.value['history'] = [{'at': s['at'], 'volumes': [{k: v.get(k) for k in
                ('id', 'status', 'available_bytes', 'total_bytes', 'device_id', 'reason')} for v in s['volumes']]} for s in history]
            self.value['notification'] = {k: notice.get(k) for k in ('at', 'signature', 'status')}
            self.stored_digest = hashlib.sha256(raw).hexdigest()

    def _file(self):
        plain_file(self.path, self.settings['uid'], private=True)
        require(self.path.resolve() == self.path and self.path.lstat().st_nlink == 1,
                'capacity_state_identity_invalid')

    @staticmethod
    def classify(available, total):
        if available < MINIMUM_FREE_BYTES:
            return 'critical'
        return 'low' if available < CAPACITY_WARN_BYTES or available / total < CAPACITY_WARN_RATIO else 'healthy'

    @staticmethod
    def observe_volume(volume):
        p = Path(volume['path'])
        base = {'id': volume['id'], 'available_bytes': None, 'total_bytes': None, 'device_id': None}
        try:
            st = p.lstat()
            if p.resolve() != p or not stat.S_ISDIR(st.st_mode) or p != Path('/') and st.st_dev == p.parent.lstat().st_dev:
                return dict(base, status='unavailable', reason='unmounted')
            s = os.statvfs(p)
            if not (type(s.f_bavail) is int and type(s.f_blocks) is int and type(s.f_frsize) is int
                    and s.f_frsize > 0 and 0 <= s.f_bavail <= s.f_blocks and s.f_blocks > 0):
                return dict(base, status='unavailable', reason='measurement_invalid')
            available, total = s.f_bavail * s.f_frsize, s.f_blocks * s.f_frsize
            return dict(base, available_bytes=available, total_bytes=total, device_id=st.st_dev,
                        status=CapacityMonitor.classify(available, total), reason=None)
        except OSError:
            return dict(base, status='unavailable', reason='measurement_unavailable')

    @staticmethod
    def signature(sample):
        return '|'.join(v['id'] + ':' + v['status'] for v in sample['volumes'])

    def _write(self):
        parent = plain_dir(self.path.parent, self.settings['uid'], private=True)
        if os.path.lexists(self.path):
            self._file()
            require(digest(self.path) == self.stored_digest, 'capacity_state_changed')
        else:
            require(self.stored_digest is None, 'capacity_state_removed')
        raw = (json.dumps(self.value, sort_keys=True, separators=(',', ':')) + '\n').encode()
        require(len(raw) <= MAX_CAPACITY_STATE, 'capacity_state_too_large')
        temporary = parent / ('.capacity-' + str(os.getpid()) + '-' + os.urandom(6).hex() + '.tmp')
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        try:
            with os.fdopen(fd, 'wb') as handle:
                handle.write(raw); handle.flush(); os.fsync(handle.fileno())
            os.replace(temporary, self.path)
            self.stored_digest = hashlib.sha256(raw).hexdigest()
            directory = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            if temporary.exists():
                temporary.unlink()

    def local_notification(self, sample):
        affected = [v for v in sample['volumes'] if v['status'] != 'healthy']
        message = 'Collect storage requires attention: ' + ', '.join(v['id'] + ' ' + v['status'] for v in affected) if affected else 'Collect storage measurements have recovered.'
        try:
            result = subprocess.run(['/usr/bin/osascript', '-e',
                'display notification ' + json.dumps(message) + ' with title "Collect storage"'],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=5, check=False, env={'PATH': '/usr/bin:/bin', 'LANG': 'en_US.UTF-8'})
            return 'submitted' if result.returncode == 0 else 'refused'
        except (OSError, subprocess.TimeoutExpired):
            return 'unknown'

    def sample(self):
        return {'at': self.clock(), 'volumes': [self.observe(v) for v in self.volumes]}

    def report(self, sample=None):
        if not self.enabled:
            return {'format': CAPACITY_FORMAT, 'status': 'disabled', 'authorizes_runtime_mutations': False}
        history = self.value['history']
        sample = sample or (history[-1] if history else None)
        if sample is None:
            return {'format': CAPACITY_FORMAT, 'status': 'unconfirmed', 'reason': 'no_samples', 'authorizes_runtime_mutations': False}
        now = self.clock(); age = now - sample['at']; volumes = []
        for v in sample['volumes']:
            cfg = next(cfg for cfg in self.volumes if cfg['id'] == v['id'])
            matching = []
            for previous in reversed(history):
                old = next(x for x in previous['volumes'] if x['id'] == v['id'])
                if old['device_id'] != v['device_id'] or old['total_bytes'] != v['total_bytes'] or old['status'] == 'unavailable':
                    break
                matching.append((previous['at'], old))
            growth = {'status': 'unconfirmed'}
            if v['status'] != 'unavailable' and len(matching) >= 2 and sample['at'] > matching[-1][0] and age >= 0:
                elapsed = sample['at'] - matching[-1][0]; delta = v['available_bytes'] - matching[-1][1]['available_bytes']
                growth = {'status': 'observed', 'elapsed_seconds': elapsed, 'available_delta_bytes': delta,
                          'net_consumed_bytes': max(0, -delta), 'samples': len(matching), 'forecast': False}
            volumes.append(dict(v, path=cfg['path'], backing_group=cfg.get('backing_group', cfg['id']), growth=growth))
        return {'format': CAPACITY_FORMAT, 'status': 'unconfirmed' if age < 0 or age > 3 * self.interval else
                'attention_required' if any(v['status'] != 'healthy' for v in volumes) else 'healthy',
                'sampled_at': datetime.fromtimestamp(sample['at'], timezone.utc).isoformat(), 'sample_age_seconds': age,
                'history_samples': len(history), 'max_samples': self.limit, 'sample_interval_seconds': self.interval,
                'thresholds': {'warning_free_bytes': CAPACITY_WARN_BYTES, 'warning_free_ratio': CAPACITY_WARN_RATIO,
                               'critical_free_bytes': MINIMUM_FREE_BYTES}, 'volumes': volumes,
                'notification': dict(self.value['notification'], channel=self.channel, delivered_or_acknowledged=False),
                'capacity_is_not_additive_across_backing_groups': True, 'authorizes_runtime_mutations': False}

    def tick(self):
        if not self.enabled:
            return self.report()
        current = self.sample(); history = self.value['history']; previous = history[-1] if history else None
        if previous and current['at'] < previous['at']:
            return self.report()
        changed = previous is None or self.signature(current) != self.signature(previous) or any(
            a['device_id'] != b['device_id'] or a['total_bytes'] != b['total_bytes'] for a, b in zip(current['volumes'], previous['volumes']))
        due = changed or current['at'] - previous['at'] >= self.interval
        if due:
            history.append(current); del history[:-self.limit]
        notice = self.value['notification']; signature = self.signature(current)
        attention = any(v['status'] != 'healthy' for v in current['volumes'])
        notice_due = self.channel == 'macos' and ((attention and (notice['signature'] != signature or
            notice['at'] is None or current['at'] - notice['at'] >= self.repeat)) or
            (not attention and notice['signature'] and notice['signature'] != signature))
        if notice_due:
            self.value['notification'] = {'at': current['at'], 'signature': signature, 'status': 'dispatch_pending_or_unknown'}
            self._write()
            status = self.notify(current)
            self.value['notification']['status'] = status if status in ('submitted', 'refused', 'unknown') else 'unknown'
            self._write()
        elif due:
            self._write()
        return self.report(current)


class Service:
    def __init__(self, settings, host=None, journal=None):
        self.s = settings
        self.host = host or Host(settings)
        self.journal = journal
        self.operation_permit = None
        self.last_event = None
        self.checked_files = {}

    def checked_file(self, path, expected_hash):
        p = plain_file(path, self.s['uid'])
        st = p.stat()
        identity = (st.st_ino, st.st_size, st.st_mtime_ns, st.st_ctime_ns, expected_hash)
        if self.checked_files.get(str(p)) != identity:
            require(digest(p) == expected_hash, 'required_file_content_mismatch')
            self.checked_files[str(p)] = identity
        return p

    def validate_host(self):
        s = self.s
        require(s.get('format') == FORMAT and s.get('uid') == os.getuid(), 'settings_identity_mismatch')
        require(s['profile'] == 'supabase-local' and s['lima_instance'] == 'colima-supabase-local', 'retained_profile_required')
        require(s['docker_socket'] == s['colima_home'] + '/supabase-local/docker.sock', 'docker_socket_profile_mismatch')
        root = plain_dir(s['working_directory'], s['uid'], private=True)
        for field in ('state_path', 'lock_path', 'event_log'):
            require(Path(s[field]).parent == root, 'service_state_path_mismatch')
        for path, fingerprint in s['binary_sha256'].items():
            plain_file(path, s['binary_owner_uids'][path], expected_hash=fingerprint)
            require(os.access(path, os.X_OK), 'required_binary_not_executable')
        require(s['optional_container_starts'] is False, 'container_writer_forbidden')

    def event(self, code):
        if code == self.last_event:
            return
        self.last_event = code
        path = Path(self.s['event_log'])
        if os.path.lexists(path):
            plain_file(path, self.s['uid'], private=True)
            if path.stat().st_size > MAX_LOG:
                rotated = path.with_suffix('.previous.jsonl')
                if os.path.lexists(rotated):
                    plain_file(rotated, self.s['uid'], private=True)
                os.replace(path, rotated)
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'a') as handle:
            # Only fixed event codes, timestamp and PID. No command output.
            handle.write(json.dumps({'at': int(time.time()), 'pid': os.getpid(), 'event': code}) + '\n')

    def image_state(self):
        s = self.s
        image = plain_dir(s['image_path'], s['uid'], private=True)
        plain_file(image / 'Info.plist', s['uid'], expected_hash=s['image_info_sha256'])
        bands = plain_dir(image / 'bands', s['uid'])
        require(any(bands.iterdir()), 'retained_image_bands_missing')
        found = []
        target_occupants = []
        for row in self.host.image_info().get('images', []):
            mounts = [entity.get('mount-point') for entity in row.get('system-entities', []) if entity.get('mount-point')]
            if s['mount_point'] in mounts:
                target_occupants.append(row)
            if row.get('image-path') == s['image_path']:
                found.append((row, mounts))
        require(len(found) <= 1 and len(target_occupants) <= 1, 'image_mount_ambiguous')
        if found:
            row, mounts = found[0]
            require(mounts == [s['mount_point']] and target_occupants == [row], 'retained_image_mounted_elsewhere')
            require(row.get('owner-uid') == s['uid'] and row.get('writeable') is True, 'mounted_image_owner_or_mode_mismatch')
            info = self.host.volume_info()
            require(info.get('MountPoint') == s['mount_point'] and info.get('VolumeUUID') == s['volume_uuid'], 'mounted_volume_identity_mismatch')
            plain_dir(s['mount_point'], s['uid'])
            return 'mounted'
        require(not target_occupants and not os.path.lexists(s['mount_point']), 'mountpoint_occupied_or_stale')
        return 'absent'

    def retained_files(self):
        s = self.s
        marker = read_json(plain_file(s['owner_marker'], s['uid']))
        require(marker == s['owner_marker_expected'], 'runtime_owner_marker_mismatch')
        for path in (s['colima_home'], s['lima_home'], s['profile_dir'], s['instance_dir'], s['data_disk_dir'], s['cache_home'], s['runtime_tmp'], s['docker_config']):
            plain_dir(path, s['uid'])
            require(str(Path(path).resolve()).startswith(s['mount_point'] + '/'), 'runtime_directory_escaped_mount')
        for path, fingerprint in s['retained_file_sha256'].items():
            require(str(Path(path).resolve()).startswith(s['mount_point'] + '/'), 'retained_file_escaped_mount')
            self.checked_file(path, fingerprint)
        # Colima legitimately rewrites derived YAML during an existing-VM
        # resume. Pin all semantic fields, allowing only the allocated SSH port.
        for entry in s['derived_yaml']:
            require(str(Path(entry['path']).resolve()).startswith(s['mount_point'] + '/'), 'retained_file_escaped_mount')
            p = plain_file(entry['path'], s['uid'])
            st = p.stat()
            identity = (st.st_ino, st.st_size, st.st_mtime_ns, st.st_ctime_ns, entry['sha256'])
            if self.checked_files.get('yaml:' + str(p)) != identity:
                require(derived_digest(p.read_bytes(), entry['ignore_ssh_port']) == entry['sha256'], 'derived_vm_metadata_mismatch')
                self.checked_files['yaml:' + str(p)] = identity
        for disk in s['disks']:
            require(str(Path(disk['path']).resolve()).startswith(s['mount_point'] + '/'), 'retained_file_escaped_mount')
            p = plain_file(disk['path'], s['uid'], expected_size=disk['bytes'])
            require(p.stat().st_ino == disk['inode'], 'retained_disk_inode_mismatch')
        store = read_json(plain_file(s['store_path'], s['uid']))
        require(store.get('disk_formatted') is True and store.get('disk_runtime') == 'docker', 'retained_formatted_docker_disk_required')
        for cached in s['cached_images']:
            require(str(Path(cached['path']).resolve()).startswith(s['mount_point'] + '/'), 'retained_file_escaped_mount')
            self.checked_file(cached['path'], cached['sha256'])
        if os.path.lexists(s['docker_socket']):
            mode = Path(s['docker_socket']).lstat()
            require(stat.S_ISSOCK(mode.st_mode) and mode.st_uid == s['uid'], 'docker_socket_is_stale_file_or_foreign')
        release = read_json(plain_file(Path(s['release_root']) / 'release.json', s['uid']))
        require(release.get('source_sha256') == s['release_source_sha256'] and release.get('profile_sha256') == s['release_profile_sha256'], 'retained_release_identity_mismatch')
        require(release.get('profile', {}).get('id') == s['release_profile_id'], 'retained_release_profile_mismatch')

    def vm_state(self):
        c, l = self.host.instances()
        c = [row for row in c if row.get('name') == self.s['profile']]
        l = [row for row in l if row.get('name') == self.s['lima_instance']]
        require(len(c) == len(l) == 1, 'existing_colima_lima_instance_required')
        require(c[0].get('runtime') == 'docker' and c[0].get('arch') == 'aarch64', 'colima_runtime_identity_mismatch')
        require(l[0].get('dir') == self.s['instance_dir'] and l[0].get('vmType') == 'vz' and l[0].get('arch') == 'aarch64', 'lima_instance_identity_mismatch')
        require(c[0].get('status') == l[0].get('status') and c[0].get('status') in ('Stopped', 'Running'), 'vm_state_unknown')
        return c[0]['status']

    def docker_identity(self):
        # GET only: no exec endpoint, SQL, pull, create, start, stop or reset.
        all_containers = self.host.docker_get('/containers/json?all=1')
        by_id = {item['Id']: item for item in all_containers}
        for expected in self.s['containers']:
            item = by_id.get(expected['id'])
            require(item is not None and item.get('ImageID') == expected['image_id'] and '/' + expected['name'] in item.get('Names', []), 'retained_container_identity_mismatch')
            require(item.get('State') == 'running', 'retained_container_not_running')
        db = self.host.docker_get('/containers/' + self.s['database_id'] + '/json')
        require(db.get('Id') == self.s['database_id'] and db.get('Image') == self.s['database_image_id'], 'retained_database_identity_mismatch')
        require(db.get('Config', {}).get('Labels', {}).get('com.supabase.cli.project') == 'local-app', 'retained_database_project_mismatch')
        require(db.get('Mounts') == self.s['database_mounts'], 'retained_database_mount_identity_mismatch')
        require(db.get('State', {}).get('Running') is True, 'retained_container_not_running')
        require(db.get('State', {}).get('Health', {}).get('Status') == 'healthy', 'retained_container_not_running')
        network = db.get('NetworkSettings', {}).get('Networks', {}).get('devctl-local-app', {})
        require(network.get('NetworkID') == self.s['network_id'], 'retained_database_network_identity_mismatch')
        edge = self.host.docker_get('/containers/' + self.s['edge_id'] + '/json')
        require(edge.get('Image') == self.s['edge_image_id'], 'retained_edge_image_mismatch')
        labels = edge.get('Config', {}).get('Labels', {})
        require(labels.get('io.collect.retained-edge.source') == self.s['release_source_sha256'], 'retained_edge_source_mismatch')
        require(labels.get('io.collect.retained-edge.profile') == self.s['release_profile_sha256'], 'retained_edge_profile_mismatch')
        require(edge.get('State', {}).get('Running') is True, 'retained_edge_not_running')
        return True

    def wait_ready(self):
        deadline = time.monotonic() + self.s['ready_timeout_seconds']
        while True:
            try:
                require(self.image_state() == 'mounted', 'runtime_image_not_mounted')
                require(self.vm_state() == 'Running', 'vm_not_running')
                return self.docker_identity()
            except Refusal as error:
                # Only expected startup liveness is transient. Identity failures
                # never turn into time-based retries or optional container starts.
                if str(error) not in ('docker_unreachable', 'vm_not_running', 'retained_container_not_running', 'retained_edge_not_running'):
                    raise
                if time.monotonic() >= deadline:
                    raise Refusal('runtime_ready_timeout') from None
                self.host.sleep(self.s['probe_interval_seconds'])

    def require_headroom(self, *, runtime):
        # Match the reviewed recovery reserve. A detached runtime filesystem
        # cannot be measured until its exact retained image is attached.
        require(self.host.free_bytes(self.s['image_path']) >= MINIMUM_FREE_BYTES,
                'backing_free_space_below2gib')
        if runtime:
            require(self.host.free_bytes(self.s['mount_point']) >= MINIMUM_FREE_BYTES,
                    'runtime_free_space_below2gib')

    def cycle(self, *, permit_actions):
        if self.journal is not None:
            require(self.journal.runtime_refusal() is None, 'runtime_refusal_requires_reconciliation')
        if not source_volume_available(self.s['image_path']):
            # RunAtLoad can precede the external image source. Keep the same
            # monitor owner alive without an attach/resume attempt or journal
            # change. Once available, every existing identity and pending-action
            # check below still applies; missing data on mounted media is fatal.
            require(permit_actions, 'source_volume_unavailable')
            self.event('source_volume_unavailable')
            return {'format': FORMAT, 'ready': False, 'reason': 'source_volume_unavailable'}
        image = self.image_state()
        pending = self.journal.value.get('pending') if self.journal else None
        if pending == 'attach_retained_image':
            require(image == 'mounted', 'previous_attach_outcome_unconfirmed')
            self.retained_files()
            self.journal.complete()
        elif pending == 'resume_existing_vm':
            require(image == 'mounted', 'previous_resume_outcome_unconfirmed')
            self.retained_files()
            require(self.vm_state() == 'Running', 'previous_resume_outcome_unconfirmed')
            self.wait_ready()
            self.journal.complete()
        elif pending is not None:
            raise Refusal('journal_unknown_pending_action')
        if image == 'absent':
            require(permit_actions, 'runtime_image_not_mounted')
            self.require_headroom(runtime=False)
            require(self.operation_permit is not None, 'operation_coordination_required')
            self.operation_permit.arm()
            self.journal.begin('attach_retained_image')
            self.event('attaching_retained_image')
            try:
                self.host.command([self.s['hdiutil'], 'attach', '-nobrowse', '-mountpoint', self.s['mount_point'], '-plist', self.s['image_path']], mutation=True, timeout=self.s['attach_timeout_seconds'])
            except Refusal:
                # The one original request may have succeeded despite lost ACK.
                pass
            require(self.image_state() == 'mounted', 'attach_outcome_unconfirmed')
            self.retained_files()
            self.journal.complete()
        self.retained_files()
        state = self.vm_state()
        if state == 'Stopped':
            require(permit_actions, 'retained_vm_stopped')
            require(self.journal.value.get('resumes', 0) < self.s['max_resumes_per_boot'], 'resume_budget_exhausted')
            if time.time() - self.journal.value.get('last_resume_at', 0) < self.s['resume_cooldown_seconds']:
                self.event('resume_cooldown_active')
                return {'format': FORMAT, 'ready': False, 'reason': 'resume_cooldown_active'}
            self.require_headroom(runtime=True)
            require(self.operation_permit is not None, 'operation_coordination_required')
            self.operation_permit.arm()
            self.journal.begin('resume_existing_vm')
            self.event('resuming_existing_vm')
            try:
                self.host.command([self.s['colima_binary'], 'start', '--profile', self.s['profile'], '--activate=false', '--save-config=false', '--template=false'], mutation=True, timeout=self.s['resume_timeout_seconds'])
            except Refusal:
                pass
            self.wait_ready()
            self.journal.complete()
        else:
            # A running VM with failed Docker is observed for a bounded grace
            # period. Never stop/restart/reinitialize it to force recovery.
            self.wait_ready()
        self.event('retained_runtime_ready') if permit_actions else None
        return {'format': FORMAT, 'ready': True, 'profile': self.s['profile'], 'optional_container_starts': False}


def load_settings(path):
    plain_file(path, os.getuid(), private=True)
    settings = read_json(path)
    require(settings.get('format') == FORMAT, 'settings_format_mismatch')
    return settings


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--settings', required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check', action='store_true')
    mode.add_argument('--run', action='store_true')
    mode.add_argument('--capacity-check', action='store_true', help='Read filesystem capacity once; no state write or notification')
    mode.add_argument('--capacity-status', action='store_true', help='Read bounded watcher state; no state write or notification')
    args = parser.parse_args(argv)
    service = None
    lock = None
    try:
        s = load_settings(args.settings)
        if args.capacity_check or args.capacity_status:
            monitor = CapacityMonitor(s)
            result = monitor.report(monitor.sample() if args.capacity_check and monitor.enabled else None)
            print(json.dumps(result, sort_keys=True))
            return 0 if result['status'] in ('healthy', 'disabled') else 2
        service = Service(s)
        service.validate_host()
        if args.check:
            # No lock/journal/log creation or external mutation in this mode.
            if os.path.lexists(s['state_path']):
                refusal = Journal(s, service.host.boot_id()).runtime_refusal()
                if refusal is not None:
                    print(json.dumps({'format': FORMAT, 'ready': False,
                        'reason': refusal['reason'], 'runtime_mutations_refused': True,
                        'requires_explicit_reconciliation': True}, sort_keys=True))
                    return 2
            print(json.dumps(service.cycle(permit_actions=False), sort_keys=True))
            return 0
        require(s.get('enabled') is True, 'startup_service_disabled')
        if os.path.lexists(s['lock_path']):
            plain_file(s['lock_path'], s['uid'], private=True)
        lock = os.open(s['lock_path'], os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise Refusal('startup_owner_already_running') from None
        service.journal = Journal(s, service.host.boot_id())
        capacity = None
        capacity_failed = False
        try:
            capacity = CapacityMonitor(s)
        except Exception:
            try:
                service.event('capacity_monitor_unconfirmed')
            except Exception:
                pass
            capacity_failed = True
        runtime_refusal = service.journal.runtime_refusal()
        if runtime_refusal is not None and (capacity is None or not capacity.enabled):
            raise Refusal('runtime_refusal_requires_reconciliation')
        refusal_reported = False
        while True:
            if capacity is not None:
                try:
                    capacity.tick()
                    capacity_failed = False
                except Exception:
                    if not capacity_failed:
                        try:
                            service.event('capacity_monitor_unconfirmed')
                        except Exception:
                            pass
                    capacity_failed = True
            if runtime_refusal is None:
                try:
                    try:
                        # Hold the same host lock as the deployment wrapper.
                        # A busy rotation waits; a terminal refusal never retries.
                        with operation_lock.coordinated('startup_cycle', s['profile']) as permit:
                            service.operation_permit = permit
                            service.cycle(permit_actions=True)
                    except operation_lock.OperationBusy:
                        pass
                    except (operation_lock.OperationRefused, OSError):
                        raise Refusal('operation_coordinator_unavailable') from None
                    finally:
                        service.operation_permit = None
                except Refusal as error:
                    if capacity is None or not capacity.enabled:
                        raise
                    reason = str(error)
                    if re.fullmatch(r'[a-z0-9_]{1,128}', reason) is None:
                        reason = 'runtime_safety_refusal'
                    # Failure to persist this fence remains fail-stop. A later
                    # process must never regain mutation authority implicitly.
                    service.journal.refuse_runtime(reason)
                    runtime_refusal = service.journal.runtime_refusal()
            if runtime_refusal is not None and not refusal_reported:
                try:
                    service.event(runtime_refusal['reason'])
                except Exception:
                    pass
                print(json.dumps({'format': FORMAT, 'ready': False,
                    'reason': runtime_refusal['reason'], 'runtime_mutations_refused': True,
                    'capacity_monitor_continues': bool(capacity and capacity.enabled),
                    'requires_explicit_reconciliation': True}, sort_keys=True), flush=True)
                refusal_reported = True
            service.host.sleep(s['monitor_interval_seconds'])
    except Refusal as error:
        code = str(error)
        if service is not None and args.run:
            try:
                service.event(code)
            except Exception:
                pass
        print(json.dumps({'format': FORMAT, 'ready': False, 'reason': code}), flush=True)
        # Known refusal is terminal until root reconciles it; no launchd loop.
        return 0 if args.run else 2
    except (KeyboardInterrupt, SystemExit):
        return 0
    except Exception:
        # Unexpected crashes can be restarted by launchd. Any external action
        # intent is already journaled and cannot be replayed by the new owner.
        print(json.dumps({'format': FORMAT, 'ready': False, 'reason': 'unexpected_helper_failure'}), flush=True)
        return 1
    finally:
        if lock is not None:
            os.close(lock)


if __name__ == '__main__':
    raise SystemExit(main())

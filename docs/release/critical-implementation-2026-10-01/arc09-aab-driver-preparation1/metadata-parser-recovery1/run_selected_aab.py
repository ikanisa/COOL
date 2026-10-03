#!/usr/bin/env python3
"""Root-admitted selected unsigned AAB observation; no automatic release acceptance."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import threading
import time
import types

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parents[1]
ROOT = RELEASE.parents[2]
FINAL = RELEASE / 'arc09-aab-execution-preparation2/reviewed-final'
PROPOSAL_PACKET_SHA = '6adae4733538e6af73c6ba6bb4672a3d504e149f46b5943c50192c2291171ef8'
PROPOSAL_SUM_SHA = '3ec4e4c71bb88efd0bccd227882b6c569563978fda4ba6eb6adf9aa3bede4964'
MATRIX_SHA = '8a7f527a48c91ef02bb7287c33e085cc0495d3585df2ea28af414313ba96095d'
NATIVE_PACKET_SHA = '78480a63008db7a457c554fdb1db2ae9f427b8aac06c45879cd6090f7bc7bd4e'
NATIVE_ROOT = RELEASE / 'root-native8-success-readback1'
PREP = RELEASE / 'kotlin-sdk-native-native-stage-preparation1'
ORIGINAL = RELEASE / 'kotlin-sdk-native-consumer-preparation1'
BASE = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1')
APP = BASE / 'app-source'
SDK = BASE / 'flutter'
PRIVATE_GRADLE = BASE / 'gradle-home'
HEX = re.compile('[a-f0-9]{64}')
PS = '/bin/ps'
LSOF = '/usr/sbin/lsof'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def physical(path):
    path = Path(path)
    if not path.is_absolute() or path.resolve() != path:
        raise ValueError('noncanonical physical path: ' + str(path))
    for parent in (path, *path.parents):
        if parent.is_symlink():
            raise ValueError('symbolic input ancestor')
    return path


def plain_read(path, expected=None, limit=32 * 1024**2):
    path = physical(path)
    initial = path.lstat()
    if not stat.S_ISREG(initial.st_mode) or initial.st_nlink != 1 or initial.st_size > limit:
        raise ValueError('nonexclusive or oversized regular input')
    with path.open('rb') as stream:
        opened = os.fstat(stream.fileno())
        body = stream.read(limit + 1)
        completed = os.fstat(stream.fileno())
    def identity(row):
        return (row.st_dev, row.st_ino, row.st_size, row.st_mode, row.st_nlink,
                row.st_mtime_ns, row.st_ctime_ns)
    if len(body) > limit or any(identity(row) != identity(initial) for row in
                              (opened, completed, path.lstat())):
        raise ValueError('regular input raced')
    if expected is not None and (not HEX.fullmatch(expected) or digest(body) != expected):
        raise ValueError('pinned input hash differs: ' + str(path))
    return body


def document(path, expected=None):
    return json.loads(plain_read(path, expected))


def save(path, value):
    with Path(path).open('x') as output:
        os.fchmod(output.fileno(), 0o600)
        json.dump(value, output, indent=2, sort_keys=True)
        output.write('\n'); output.flush(); os.fsync(output.fileno())


def module(path, expected, name):
    raw = plain_read(path, expected)
    value = types.ModuleType(name); value.__file__ = str(path)
    sys.modules[name] = value
    exec(compile(raw, str(path), 'exec'), value.__dict__)
    return value


def context(args):
    packet = document(FINAL / 'packet-files.json', PROPOSAL_PACKET_SHA)
    plain_read(FINAL / 'SHA256SUMS', PROPOSAL_SUM_SHA)
    if len(packet['files']) != 11:
        raise ValueError('reviewed proposal leaf count differs')
    for name, record in packet['files'].items():
        if Path(name).is_absolute() or '..' in Path(name).parts:
            raise ValueError('unsafe proposal leaf')
        raw = plain_read(FINAL / name, record['sha256'])
        if len(raw) != record['bytes'] or stat.S_IMODE((FINAL / name).stat().st_mode) != record['mode']:
            raise ValueError('reviewed proposal bytes/mode differ')
    matrix = document(FINAL / 'command-matrix.json', MATRIX_SHA)
    admission = document(args.admission, args.admission_sha256)
    if (admission.get('schema_version') != 1 or admission.get('kind') != 'root_selected_unsigned_AAB_admission'
            or admission.get('production_release_approval') is not False
            or admission.get('native_whole_pass') is not True):
        raise ValueError('root admission scope or actual native pass missing')
    plain_read(Path(__file__).resolve(), admission['driver_sha256'])
    pins = document(HERE / 'prepared-input-pins.json', admission['prepared_input_pins_sha256'])
    for name, record in pins.items():
        raw = plain_read(name, record['sha256'], 32 * 1024**2)
        if len(raw) != record['bytes'] or stat.S_IMODE(Path(name).stat().st_mode) != record['mode']:
            raise ValueError('prepared reference input differs')
    def loaded(relative, name):
        path = PREP / relative
        return module(path, pins[str(path)]['sha256'], name)
    reader = loaded('publisher_metadata.py', 'aab_exact_reader')
    guards = loaded('consumer_guards.py', 'aab_exact_guards')
    controller = loaded('run_native_consumer.py', 'aab_exact_controller')
    fence = loaded('source_fence.py', 'aab_exact_fence')
    controller.reader = lambda: reader
    controller.require_pass = guards.process_success
    guards.load_metadata = lambda: reader
    fence.metadata = lambda: reader
    config = document(PREP / 'proposed-commands.json',
                      '696a87e401485c5a86205e752aec934a29ede3ae0c3b86beee7ff7cd97501353')
    if Path(sys.executable).resolve() != Path(config['Python_executable']).resolve():
        raise ValueError('actual Python runtime differs')
    for label in ('Python', 'JDK_java', 'Node'):
        if reader.stable_read(Path(config[label + '_executable']))[0]['sha256'] != config[label + '_SHA256']:
            raise ValueError('exact runtime executable differs')
    records = {}
    native_packet = document(NATIVE_ROOT / 'packet-files.json', NATIVE_PACKET_SHA)
    native_files = {r['path']: r for r in native_packet['files']}
    if len(native_files) != 46 or len(native_packet['files']) != 46:
        raise ValueError('root actual native packet leaf set differs')
    for name, record in native_files.items():
        if Path(name).is_absolute() or '..' in Path(name).parts: raise ValueError('unsafe native packet path')
        raw = plain_read(NATIVE_ROOT / name, record['sha256'], 128 * 1024**2)
        if len(raw) != record['bytes']: raise ValueError('native packet byte count differs')
    for label, record in admission['native_evidence'].items():
        path = physical(record['path'])
        relative = path.relative_to(NATIVE_ROOT).as_posix()
        if native_files[relative]['sha256'] != record['sha256']:
            raise ValueError('actual native evidence not bound by sealed native packet')
        records[label] = json.loads(plain_read(record['path'], record['sha256'], 128 * 1024**2))
    required = {'terminal', 'command', 'root_readback', 'daemon_absence', 'JVM_classes',
                'APP_source', 'packages', 'plugins', 'SDK_before', 'SDK_after'}
    if set(records) != required:
        raise ValueError('root-held actual native evidence set differs')
    terminal = records['terminal']
    if (terminal.get('stage') != 'native' or terminal.get('stage_pass') is not True
            or terminal.get('warm_retry_script_sha256') !=
            '803bf024a36e008c390aec7bd7405836afd6831a85008bad606b0ae0e556b93c'):
        raise ValueError('actual completed warm8 native terminal absent')
    guards.process_success(records['command'])
    command = records['command']
    for label in ('stdout', 'stderr'):
        log = admission['native_logs'][label]
        plain_read(log['path'], log['sha256'])
        if log['sha256'] != command[label + '_sha256']:
            raise ValueError('actual native process/log binding differs')
    expected_native = [a for a in config['commands']['native']['argv'] if a != '--rerun-tasks']
    if (command['argv'] != expected_native or command['cwd'] != config['commands']['native']['cwd']
            or command['deadline_seconds'] != 2700):
        raise ValueError('actual native command differs')
    absence = records['daemon_absence']
    rr = records['root_readback']
    if (rr.get('status') != 'PASS'
            or rr.get('native_terminal_sha256') != admission['native_evidence']['terminal']['sha256']
            or rr.get('original_bound_seconds') != 2700
            or rr.get('actual_command_seconds') != command['actual_seconds']
            or rr.get('raw_JVM_XML_and_classes_independently_read_and_copied') is not True):
        raise ValueError('independent actual root native PASS cross-binding differs')
    if absence.get('status') != 'PASS' or not absence.get('utc'):
        raise ValueError('separate actual native daemon absence not supplied')
    daemons = admission.get('native_observed_daemons', [])
    if not daemons:
        raise ValueError('known separately grouped native daemon evidence omitted')
    observed_groups = {r['pgid']: r['state'] for r in absence.get('owned_groups', [])}
    for daemon in daemons:
        if (daemon['wrapper_pid'] != command['pid'] or daemon['pgid'] == command['pid']
                or observed_groups.get(daemon['pgid']) != 'ESRCH_absent'
                or observed_groups.get(command['pid']) != 'ESRCH_absent'
                or not daemon.get('ownership_evidence')):
            raise ValueError('native daemon independent absence/ownership binding incomplete')
        proof = daemon['ownership_evidence']
        ownership = document(proof['path'], proof['sha256'])
        if ownership.get('owned_pid') != daemon['pid'] or ownership.get('identity_verified') is not True:
            raise ValueError('native daemon exact independent ownership evidence differs')
    export = document(RELEASE / 'root-native-warm-export8-readback1/export-source-binding.json',
                      '0bad50e24b58427074045c8db05dd1e0536bccf34fccf35d4939f5ff1610070c')
    if records['APP_source'].get('export_manifest_file_sha256') != export['export_manifest_file_sha256']:
        raise ValueError('native actual APP source export differs')
    if (records['APP_source'].get('strict_source_unchanged') is not True
            or records['APP_source']['source_manifest_sha256'] != export['source_manifest_sha256']
            or rr['source_manifest_sha256'] != export['source_manifest_sha256']):
        raise ValueError('native strict APP/source independent binding differs')
    for name in ('SDK_before', 'SDK_after'):
        sdk = records[name]
        if (sdk.get('status') != 'EXACT_CANDIDATE_SOURCE_DELTA_AND_PHYSICAL_READBACK_PASS'
                or sdk.get('phase') != 'built' or sdk.get('source_entries', 0) <= 0
                or sdk.get('zero_pristine_installed_failed_candidate_shared_inodes') is not True):
            raise ValueError('actual native physical SDK source/delta guard not passed')
    if (records['SDK_before']['source_entries'] != records['SDK_after']['source_entries']
            or records['SDK_before']['allowed_source_deltas'] != records['SDK_after']['allowed_source_deltas']):
        raise ValueError('native SDK source membership or allowed source delta count differs')
    # Generated/cache identities are retained independently, including the observed engine.stamp inode change.
    if (records['packages'].get('only_exact_owned_bindings') is not True
            or not records['packages'].get('packages')
            or records['plugins'].get('only_exact_locked_plugin_roots') is not True
            or not records['plugins'].get('rows')):
        raise ValueError('actual native package/plugin binding proof missing')
    counts = records['JVM_classes']['actual_JVM_totals']
    if counts['tests'] <= 0 or any(counts[k] for k in ('failures', 'errors', 'skipped')):
        raise ValueError('genuine native JVM result missing')
    if not records['JVM_classes'].get('actual_release_classes'):
        raise ValueError('genuine native release class readback missing')
    if (rr['actual_JVM_tests'] != counts
            or rr['actual_JVM_suites'] != len(records['JVM_classes']['actual_XML_suites'])
            or rr['actual_release_classes'] != len(records['JVM_classes']['actual_release_classes'])
            or terminal['protected_after']['protected_metadata_paths_unchanged'] != rr['original_protected_paths_unchanged']):
        raise ValueError('root independent JVM/classes/protected readback differs')
    return types.SimpleNamespace(reader=reader, guards=guards, controller=controller, fence=fence,
                                 config=config, matrix=matrix, admission=admission, pins=pins,
                                 records=records, export=export)


def metadata_command(argv, deadline=None):
    remaining = 2 if deadline is None else deadline - time.monotonic()
    if remaining <= 0: raise TimeoutError('owned metadata/cleanup deadline exceeded')
    process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True)
    try:
        out, err = process.communicate(timeout=min(2, remaining))
    except BaseException:
        try: os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError: pass
        grace = 5 if deadline is None else max(.01, min(5, deadline - time.monotonic()))
        process.communicate(timeout=grace)
        raise
    if len(out) + len(err) > 8 * 1024**2:
        raise ValueError('process metadata output bound exceeded')
    return process.returncode, out, err


def process_table(deadline=None):
    rc, out, _ = metadata_command([PS, '-axo', 'pid=,ppid=,pgid=,lstart=,command='], deadline)
    if rc:
        raise ValueError('actual process table observation failed')
    rows = {}
    for line in out.decode('utf-8', 'strict').splitlines():
        fields = line.split(None, 8)
        if len(fields) != 9:
            raise ValueError('unsupported process table row')
        pid, ppid, pgid = map(int, fields[:3])
        rows[pid] = {'pid': pid, 'ppid': ppid, 'pgid': pgid,
                     'start': ' '.join(fields[3:8]), 'command': fields[8]}
    return rows


def group_absent(pgid):
    try: os.killpg(pgid, 0)
    except ProcessLookupError: return True
    except PermissionError: return False
    return False


class DaemonTracker:
    """Observe ancestry before reparenting; adopt only exact private-home Gradle daemons."""
    def __init__(self, context, output, label):
        self.context, self.output, self.label = context, output, label
        self.baseline = process_table(); self.root = None
        self.family, self.daemons, self.unproven = {}, {}, {}
        self.error = None; self.stop = threading.Event(); self.thread = None
        self.cleanup_deadline = None
        st = physical(PRIVATE_GRADLE).stat()
        self.home_identity = (st.st_dev, st.st_ino, stat.S_IMODE(st.st_mode))

    def private_identity(self, row):
        if (not row['command'].startswith(self.context.config['JDK_java_executable'] + ' ')
                or 'org.gradle.launcher.daemon.bootstrap.GradleDaemon ' not in row['command']):
            return None
        home = physical(PRIVATE_GRADLE).stat()
        if (home.st_dev, home.st_ino, stat.S_IMODE(home.st_mode)) != self.home_identity:
            raise ValueError('private Gradle home directory identity changed')
        log = PRIVATE_GRADLE / 'daemon/9.1.0' / ('daemon-' + str(row['pid']) + '.out.log')
        if not log.exists(): return None
        physical(log); st = log.lstat()
        if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
            raise ValueError('private daemon log is aliased or special')
        rc, out, _ = metadata_command([LSOF, '-a', '-p', str(row['pid']), '-Fpin'], self.cleanup_deadline)
        if rc not in (0, 1): raise ValueError('daemon PID-specific open-file observation failed')
        inode = None; found = False
        for line in out.decode('utf-8', 'strict').splitlines():
            if line.startswith('i'): inode = line[1:]
            if line == 'n' + str(log) and inode == str(st.st_ino): found = True
        if not found:
            if row['pid'] not in process_table(self.cleanup_deadline): return None
            raise ValueError('recognized live Gradle daemon has ambiguous private-home open-file evidence')
        return {'private_gradle_home': str(PRIVATE_GRADLE), 'home_identity': self.home_identity,
                'opened_log': str(log), 'log_device': st.st_dev, 'log_inode': st.st_ino,
                'lsof_stdout_sha256': digest(out), 'retained_matching_lsof_lines':
                ['p' + str(row['pid']), 'i' + str(st.st_ino), 'n' + str(log)], 'actual_matching_lsof_fields':
                {'pid': row['pid'], 'inode': str(st.st_ino), 'name': str(log)},
                'observed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}

    def exact_wrapper_java(self, command):
        planned = [c for c in self.context.matrix['commands'] if c['label'] == self.label]
        if len(planned) != 1: return False
        jar = APP / 'android/gradle/wrapper/gradle-wrapper.jar'
        expected = (self.context.config['JDK_java_executable'] +
                    ' -Xmx64m -Xms64m -Dorg.gradle.appname=gradlew -jar ' + str(jar) +
                    ' ' + ' '.join(planned[0]['argv'][2:]))
        # ps emits the executable path containing spaces without shell quoting. Do not shlex it.
        if command != expected: return False
        for relative in ('android/gradlew', 'android/gradle/wrapper/gradle-wrapper.jar'):
            expected_source = self.context.records['APP_source']['source_files_exact'][relative]
            if len(plain_read(APP / relative, expected_source['sha256'])) != expected_source['bytes']:
                raise ValueError('exact source-bound wrapper script/JAR byte count differs')
        return True

    def refresh_session(self, pid, owned, current):
        if owned['pgid'] == current['pgid']: return
        # A fresh child may setsid once after inheriting the owned wrapper process group.
        if (pid == self.root or pid in self.baseline or owned['pgid'] != self.root
                or current['pgid'] != pid or owned['ancestry'] != [self.root, pid]
                or not all(owned[k] == current[k] for k in ('pid', 'ppid', 'start', 'command'))
                or current['ppid'] != self.root):
            raise ValueError('unbound daemon session/PID transition')
        identity = self.private_identity(current)
        if identity is None: raise ValueError('daemon session transition lacks exact private-home/log proof')
        keys = ('private_gradle_home', 'home_identity', 'opened_log', 'log_device', 'log_inode')
        for proof in (self.daemons.get(pid, {}).get('private_home_evidence'),
                      self.unproven.get(pid, {}).get('private_home_evidence')):
            if proof is not None and any(proof[k] != identity[k] for k in keys):
                raise ValueError('daemon private-home/log identity changed during setsid')
        transition = {'before_pgid': owned['pgid'], 'after_pgid': current['pgid'],
                      'PID_start_command_parent_unchanged': True,
                      'private_home_evidence': identity,
                      'observed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
        pending = self.unproven.get(pid)
        if (pending is not None and self.same(pending, owned) and pending.get('refusal') ==
                'owned-ancestry live daemon lacks exact private-home open-log identity'):
            del self.unproven[pid]
        owned.setdefault('observed_session_history', []).append(transition)
        owned['pgid'] = current['pgid']
        if pid in self.daemons:
            self.daemons[pid] = dict(owned, private_home_evidence=identity)

    @staticmethod
    def same(left, right):
        return all(left[k] == right[k] for k in ('pid', 'pgid', 'start', 'command'))

    def observe(self, finishing=False):
        table = process_table(self.cleanup_deadline)
        if self.root in table and self.root not in self.family:
            row = table[self.root]
            if self.root in self.baseline or row['ppid'] != os.getpid():
                raise ValueError('new wrapper ancestry cannot be established')
            self.family[self.root] = dict(row, ancestry=[self.root])
        # The wrapper legitimately execs Java at the same PID/start/group. Keep the actual exec history.
        for pid, owned in self.family.items():
            current = table.get(pid)
            if (current is not None and owned['pgid'] != current['pgid']
                    and 'org.gradle.launcher.daemon.bootstrap.GradleDaemon ' in current['command']):
                self.refresh_session(pid, owned, current)
            if current is not None and all(owned[k] == current[k] for k in ('pid', 'start', 'pgid')):
                if owned['command'] != current['command'] and pid not in self.daemons:
                    if pid == self.root and not self.exact_wrapper_java(current['command']):
                        raise ValueError('wrapper exec transition is not the pinned Java Gradle wrapper')
                    owned.setdefault('observed_exec_history', []).append(
                        {'before': owned['command'], 'after': current['command']})
                    owned['command'] = current['command']
        for _ in range(32):
            added = False
            for pid, row in table.items():
                parent = self.family.get(row['ppid'])
                if pid in self.family or pid in self.baseline or parent is None: continue
                if row['ppid'] not in table or not self.same(parent, table[row['ppid']]): continue
                self.family[pid] = dict(row, ancestry=parent['ancestry'] + [pid]); added = True
            if not added: break
        if len(self.family) > 2048: raise ValueError('owned ancestry record bound exceeded')
        for pid, row in table.items():
            if self.stop.is_set() and not finishing: break
            if pid in self.baseline: continue
            identity = self.private_identity(row)
            if identity is None:
                if (pid in self.family and row['command'].startswith(self.context.config['JDK_java_executable'] + ' ')
                        and 'org.gradle.launcher.daemon.bootstrap.GradleDaemon ' in row['command']
                        and pid in process_table(self.cleanup_deadline)):
                    self.unproven[pid] = dict(row, refusal='owned-ancestry live daemon lacks exact private-home open-log identity')
                continue
            own = self.family.get(pid)
            if own is None or not self.same(own, row):
                self.unproven[pid] = dict(row, private_home_evidence=identity)
            else:
                self.daemons.setdefault(pid, dict(own, private_home_evidence=identity))
                pending = self.unproven.get(pid)
                if (pending is not None and self.same(pending, row)
                        and pending.get('refusal') ==
                        'owned-ancestry live daemon lacks exact private-home open-log identity'):
                    del self.unproven[pid]
                if len(self.daemons) > 8: raise ValueError('observed owned daemon bound exceeded')
        return table

    def register(self, process):
        self.root = process.pid
        def monitor():
            try:
                while not self.stop.is_set():
                    self.observe(); self.stop.wait(.25)
            except BaseException as error:
                self.error = {'type': type(error).__name__, 'error': str(error)}
        self.thread = threading.Thread(target=monitor, daemon=True); self.thread.start()

    def finish(self):
        self.cleanup_deadline = time.monotonic() + 30
        self.stop.set(); results = []; required_stop = False; late = []
        joined = False
        try:
            if self.thread: self.thread.join(timeout=10)
            joined = not self.thread or not self.thread.is_alive()
            if not joined: raise ValueError('daemon observer did not finish within bound')
            self.observe(finishing=True)
            adopted_ids = set(self.daemons)
            def verified(adopted, row):
                actual = self.private_identity(row)
                keys = ('private_gradle_home', 'home_identity', 'opened_log', 'log_device', 'log_inode')
                return self.same(adopted, row) and actual is not None and all(
                    actual[k] == adopted['private_home_evidence'][k] for k in keys)
            for pid, adopted in list(self.daemons.items()):
                cleanup = []; limit = min(self.cleanup_deadline, time.monotonic() + 5)
                while time.monotonic() < limit and pid in process_table(self.cleanup_deadline): time.sleep(.1)
                table = process_table(self.cleanup_deadline)
                if pid in table:
                    if not verified(adopted, table[pid]):
                        raise ValueError('owned daemon identity changed before any signal')
                    required_stop = True
                    for sig in (signal.SIGTERM, signal.SIGKILL):
                        table = process_table(self.cleanup_deadline)
                        if pid not in table: break
                        if not verified(adopted, table[pid]):
                            raise ValueError('daemon PID reused or private-home/log binding lost')
                        # PID-only signal never kills an unverified member of the separate group.
                        os.kill(pid, sig); cleanup.append({'signal': sig.name, 'identity_verified': True})
                        limit = min(self.cleanup_deadline, time.monotonic() + 5)
                        while time.monotonic() < limit and pid in process_table(self.cleanup_deadline): time.sleep(.1)
                table = process_table(self.cleanup_deadline)
                results.append({'daemon': adopted, 'cleanup': cleanup, 'PID_absent': pid not in table,
                                'PGID_absent': group_absent(adopted['pgid'])})
            self.observe(finishing=True)
            late = sorted(set(self.daemons) - adopted_ids)
            if late: raise ValueError('late observed daemon lacks completed independent absence proof')
        except BaseException as error:
            self.error = {'type': type(error).__name__, 'error': str(error), 'previous_observer_error': self.error}
        result = {'wrapper_pid': self.root, 'observed_new_daemons': results,
                  'observed_ancestry': list(self.family.values()) if joined else None,
                  'unproven_private_home_daemons': list(self.unproven.values()) if joined else None,
                  'late_observed_daemon_ids': late, 'observer_error': self.error,
                  'separate_daemon_required_stop': required_stop,
                  'owned_daemons_absent': joined and self.error is None and not self.unproven and not late
                  and len(results) == len(self.daemons) and all(x['PID_absent'] and x['PGID_absent'] for x in results),
                  'wrapper_group_does_not_prove_daemon_absence': True,
                  'observation_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
        result['spontaneous_daemon_shutdown'] = bool(result['owned_daemons_absent'] and not required_stop)
        save(self.output / (self.label + '.daemon-readback.json'), result)
        return result


def guard_phase(ctx, output, phase):
    checker_path = ORIGINAL / 'verify_native_consumer_source.py'
    checker = module(checker_path, ctx.pins[str(checker_path)]['sha256'], 'aab_SDK_checker')
    if phase == 'failure':
        diagnostics = {}
        for label, read in [('SDK-source', lambda: checker.verify('built')),
                            ('APP-source', lambda: ctx.guards.app_readback('built', ctx.export['export_manifest_file_sha256'])),
                            ('protected', ctx.controller.protected_metadata)]:
            try:
                observation = read(); save(output / (label + '-failure.json'), observation)
                diagnostics[label] = {'readback_completed': True}
            except BaseException as error:
                diagnostics[label] = {'readback_completed': False, 'error_type': type(error).__name__, 'actual_error': str(error)}
        save(output / 'failure-diagnostic-summary.json', diagnostics)
        return
    sdk = checker.verify('built')
    save(output / ('SDK-source-' + phase + '-built.json'), sdk)
    app = ctx.guards.app_readback('built', ctx.export['export_manifest_file_sha256'])
    save(output / ('APP-source-' + phase + '.json'), app)
    ctx.guards.require_lock(APP / 'pubspec.lock', ctx.export['original_app_lock_sha256'])
    ctx.guards.require_lock(SDK / 'packages/flutter_tools/pubspec.lock', ctx.guards.SDK_LOCK)
    expected_gradle = ctx.pins[str(ROOT / 'android/app/gradle.lockfile')]['sha256']
    ctx.guards.require_lock(APP / 'android/app/gradle.lockfile', expected_gradle)
    packages = ctx.guards.package_config(APP / '.dart_tool/package_config.json', (SDK, APP, BASE / 'pub-cache'))
    plugins = ctx.guards.plugin_metadata(APP / '.flutter-plugins-dependencies')
    save(output / ('actual-app-packages-' + phase + '.json'), packages)
    save(output / ('actual-plugin-bindings-' + phase + '.json'), plugins)
    protected = ctx.controller.protected_metadata()
    source = Path(ctx.config['raw_published_Gradle_ZIP_source'])
    destination = PRIVATE_GRADLE / ctx.config['raw_Gradle_ZIP_owned_relative_destination']
    rows = [ctx.reader.stable_read(path)[0] for path in (source, destination)]
    if (any((r['sha256'], r['bytes']) != (ctx.config['raw_Gradle_ZIP_SHA256'], ctx.config['raw_Gradle_ZIP_bytes'])
            for r in rows) or (rows[0]['device'], rows[0]['inode']) == (rows[1]['device'], rows[1]['inode'])):
        raise ValueError('published and exclusive owned raw Gradle ZIP binding differs')
    save(output / ('guard-' + phase + '.json'), {'SDK_PASS': True, 'APP_PASS': True,
         'protected': protected, 'raw_Gradle_ZIP': rows, 'production_release_approval': False})


def copied_aab(ctx, source, output):
    deadline = time.monotonic() + 120
    source = physical(source); initial = source.lstat()
    if not stat.S_ISREG(initial.st_mode) or initial.st_nlink != 1 or initial.st_size > 1024**3:
        raise ValueError('selected AAB source identity or byte bound invalid')
    def identity(row):
        return (row.st_dev, row.st_ino, row.st_size, row.st_mode, row.st_nlink,
                row.st_mtime_ns, row.st_ctime_ns)
    def bound():
        import shutil
        if time.monotonic() >= deadline or shutil.disk_usage(output.parent).free < ctx.controller.LIVE_FLOOR:
            raise ValueError('selected AAB whole copy/hash deadline or headroom failure')
    def hashed(stream):
        total = 0; h = hashlib.sha256(); stream.seek(0)
        while True:
            bound(); chunk = stream.read(1024**2)
            if not chunk: return total, h.hexdigest()
            total += len(chunk); h.update(chunk)
            if total > 1024**3: raise ValueError('AAB hash read exceeded byte bound')
    fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
    sha = hashlib.sha256(); copied = 0
    with os.fdopen(fd, 'rb') as input_, output.open('x+b') as target:
        if identity(os.fstat(input_.fileno())) != identity(initial):
            raise ValueError('actual source FD differs from named initial AAB')
        os.fchmod(target.fileno(), 0o600)
        for chunk in iter(lambda: input_.read(1024**2), b''):
            bound()
            target.write(chunk); sha.update(chunk); copied += len(chunk)
            if copied > initial.st_size: raise ValueError('AAB copy grew beyond bound source')
        target.flush(); os.fsync(target.fileno())
        source_hash = hashed(input_); copy_hash = hashed(target)
        after = os.fstat(input_.fileno())
        if (identity(initial) != identity(after) or identity(source.lstat()) != identity(initial)
                or source_hash != copy_hash or source_hash != (copied, sha.hexdigest())
                or copied != initial.st_size):
            raise ValueError('held FD/named/source/copy AAB byte or identity drift')
        os.fchmod(target.fileno(), 0o400); target_identity = os.fstat(target.fileno())
        if (target_identity.st_dev, target_identity.st_ino) == (initial.st_dev, initial.st_ino):
            raise ValueError('AAB copy shares writable source inode')
        if identity(output.lstat()) != identity(target_identity): raise ValueError('AAB copy named leaf drift')
    def record(row):
        return {'sha256': source_hash[1], 'bytes': row.st_size, 'device': row.st_dev,
                'inode': row.st_ino, 'mode': stat.S_IMODE(row.st_mode), 'nlink': row.st_nlink,
                'mtime_ns': row.st_mtime_ns, 'ctime_ns': row.st_ctime_ns}
    return {'source': record(initial), 'copy': record(target_identity), 'held_source_FD_verified': True,
            'source_rehash_and_copy_rehash_equal': True, 'copy_mode_read_only': True,
            'whole_copy_hash_bound_seconds': 120}


def extract_graph(log, output, configuration):
    raw = plain_read(log, limit=32 * 1024**2).decode('utf-8', 'strict')
    start, end = 'COLLECT_RUNTIME_GRAPH_BEGIN', 'COLLECT_RUNTIME_GRAPH_END'
    if (raw.count(start) != 1 or raw.count(end) != 1 or raw.index(start) >= raw.index(end)
            or 'COLLECT_UNRESOLVED_DEPENDENCIES_BEGIN' in raw):
        raise ValueError('canonical graph marker or unresolved dependency failure')
    graph = json.loads(raw.split(start)[1].split(end)[0].strip())
    if graph['configuration'] != configuration or not all(k in graph for k in ('components', 'edges', 'artifacts')):
        raise ValueError('wrong canonical graph schema/configuration')
    save(output, graph)


def validate_runtime_reuse(ctx, data):
    """Pure semantic qualification of root-held completed work; failed driver stays failed."""
    rr, command = data['root_readback'], data['command']
    if (rr['status'] != 'successful_runtime_graph_independent_scope_readback_failed_whole_driver_preserved'
            or rr['original_monitor_failure_preserved'] is not True
            or rr['AAB_built'] is not False or rr['ARC09_closed'] is not False
            or rr['production_release_approval'] is not False or rr['matching_live_process_rows']):
        raise ValueError('root-held completed runtime scope/absence review differs')
    ctx.guards.process_success(command)
    ctx.guards.process_success(data['source_fence_command'])
    ctx.guards.process_success(data['failure_guard_command'])
    ctx.guards.forbid_upgrade_branch(data['stdout'], data['stderr'])
    planned = ctx.matrix['commands'][0]
    if (command['argv'] != planned['argv'] or command['cwd'] != planned['cwd']
            or command['deadline_seconds'] != planned['deadline_seconds']
            or command['exit_code'] != rr['runtime_exit_code']
            or command['actual_seconds'] != rr['runtime_seconds']):
        raise ValueError('completed canonical runtime command differs')
    terminal = data['terminal']
    if terminal['status'] != 'fail' or terminal['ARC09_closed'] is not False:
        raise ValueError('old whole driver failure must be retained')
    graph = data['graph']
    if (graph['configuration'] != 'productionReleaseRuntimeClasspath'
            or len(graph['components']) != rr['components'] or len(graph['edges']) != rr['edges']
            or len(graph['artifacts']) != rr['artifacts']):
        raise ValueError('completed canonical runtime graph readback differs')
    before = data['source_fence_before']
    if before['source_manifest_sha256'] != ctx.export['source_manifest_sha256']:
        raise ValueError('old runtime input source fence differs')
    app, sdk, protected = data['APP_source_failure'], data['SDK_source_failure'], data['protected_failure']
    if (app['strict_source_unchanged'] is not True
            or app['source_manifest_sha256'] != ctx.export['source_manifest_sha256']
            or app['export_manifest_file_sha256'] != ctx.export['export_manifest_file_sha256']
            or app['source_files_exact'] != ctx.records['APP_source']['source_files_exact']):
        raise ValueError('old runtime actual APP failure readback differs')
    reference = ctx.records['SDK_after']
    if (sdk['status'] != 'EXACT_CANDIDATE_SOURCE_DELTA_AND_PHYSICAL_READBACK_PASS'
            or sdk['phase'] != 'built' or sdk['source_entries'] != reference['source_entries']
            or sdk['allowed_source_deltas'] != reference['allowed_source_deltas']
            or sdk['zero_pristine_installed_failed_candidate_shared_inodes'] is not True):
        raise ValueError('old runtime actual SDK failure readback differs')
    if (protected['protected_metadata_paths_unchanged'] !=
            ctx.records['root_readback']['original_protected_paths_unchanged']
            or protected['no_original_metadata_restoration_performed'] is not True):
        raise ValueError('old runtime actual protected failure readback differs')
    old_monitor = terminal['daemon_receipts'][0]
    family = {r['pid']: r for r in old_monitor['observed_ancestry']}
    wrapper = command['pid']
    if wrapper not in family: raise ValueError('old wrapper actual ancestry missing')
    owned = [r for r in old_monitor['unproven_private_home_daemons']
             if r.get('private_home_evidence') and r['pid'] in family
             and family[r['pid']]['ancestry'] == [wrapper, r['pid']]
             and r['ppid'] == wrapper and r['pgid'] == r['pid']
             and all(family[r['pid']][k] == r[k] for k in ('pid', 'ppid', 'start', 'command'))]
    if len(owned) != 1: raise ValueError('old separate daemon actual ownership scope differs')
    daemon = owned[0]
    proof = daemon['private_home_evidence']
    if (proof['private_gradle_home'] != str(PRIVATE_GRADLE)
            or proof['opened_log'] != str(PRIVATE_GRADLE / 'daemon/9.1.0' / ('daemon-' + str(daemon['pid']) + '.out.log'))
            or proof['actual_matching_lsof_fields'] !=
            {'pid': daemon['pid'], 'inode': str(proof['log_inode']), 'name': proof['opened_log']}):
        raise ValueError('old separate daemon exact private log evidence differs')
    expected_absence = {('pid', wrapper), ('pgid', wrapper), ('pid', daemon['pid']), ('pgid', daemon['pgid'])}
    absence = rr['independent_absence']
    if (len(absence) != len(expected_absence)
            or {(r['kind'], r['id']) for r in absence} != expected_absence
            or any(r['state'] != 'ESRCH_absent' for r in absence)):
        raise ValueError('old runtime independent PID/group absence incomplete')
    return {'completed_runtime_graph_reused': True, 'old_whole_driver_remains_failed': True,
            'components': len(graph['components']), 'edges': len(graph['edges']),
            'artifacts': len(graph['artifacts']), 'wrapper_PID': wrapper, 'daemon_PID': daemon['pid'],
            'APP_source_SDK_source_and_protected_failure_values_independently_checked': True}


def reuse_runtime_graph(ctx, output):
    deadline = time.monotonic() + 30
    supplied = ctx.admission['runtime_graph_reuse']
    expected = {'root_readback', 'failed_packet', 'terminal', 'command', 'stdout', 'stderr', 'graph',
                'APP_source_failure', 'SDK_source_failure', 'protected_failure', 'source_fence_before',
                'source_fence_command', 'failure_guard_command'}
    if set(supplied) != expected: raise ValueError('completed runtime reuse bindings incomplete')
    def read(label):
        if time.monotonic() >= deadline: raise TimeoutError('completed runtime reuse whole30-second read bound')
        return plain_read(supplied[label]['path'], supplied[label]['sha256'])
    raw = {label: read(label) for label in expected}
    data = {k: (v.decode('utf-8', 'strict') if k in ('stdout', 'stderr') else json.loads(v))
            for k, v in raw.items()}
    rr = data['root_readback']
    links = {'terminal': 'driver_terminal_sha256', 'failed_packet': 'failed_output_packet_sha256',
             'command': 'runtime_command_sha256', 'stdout': 'runtime_stdout_sha256',
             'stderr': 'runtime_stderr_sha256', 'graph': 'runtime_graph_sha256'}
    for label, field in links.items():
        if digest(raw[label]) != rr[field]: raise ValueError('root reusable runtime evidence binding differs')
    packet_root = Path(supplied['failed_packet']['path']).parent
    packet = data['failed_packet']['files']
    if len(packet) != 25: raise ValueError('preserved failed packet leaf count differs')
    for label in expected - {'root_readback', 'failed_packet', 'graph'}:
        relative = Path(supplied[label]['path']).relative_to(packet_root).as_posix()
        record = packet[relative]
        if (record['sha256'] != digest(raw[label]) or record['bytes'] != len(raw[label])
                or stat.S_IMODE(Path(supplied[label]['path']).stat().st_mode) != record['mode']):
            raise ValueError('old reusable runtime input not bound by sealed failed packet')
    result = validate_runtime_reuse(ctx, data)
    graph_text = data['stdout']; start, end = 'COLLECT_RUNTIME_GRAPH_BEGIN', 'COLLECT_RUNTIME_GRAPH_END'
    if (graph_text.count(start) != 1 or graph_text.count(end) != 1 or graph_text.index(start) >= graph_text.index(end)
            or 'COLLECT_UNRESOLVED_DEPENDENCIES_BEGIN' in graph_text
            or json.loads(graph_text.split(start)[1].split(end)[0].strip()) != data['graph']):
        raise ValueError('old stdout canonical graph does not equal independently extracted graph')
    for label, filename in [('graph', 'production-runtime-graph.json'),
                            ('command', 'production-runtime-graph-observation.json'),
                            ('stdout', 'production-runtime-graph-observation.stdout'),
                            ('stderr', 'production-runtime-graph-observation.stderr')]:
        if time.monotonic() >= deadline: raise TimeoutError('completed runtime reuse copy bound')
        with (output / filename).open('xb') as stream:
            os.fchmod(stream.fileno(), 0o600); stream.write(raw[label]); stream.flush(); os.fsync(stream.fileno())
    result['exact_root_binding_inputs'] = supplied
    save(output / 'runtime-graph-reuse.json', result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--admission', type=Path, required=True)
    parser.add_argument('--admission-sha256', required=True)
    parser.add_argument('--guard-phase', choices=('before', 'after', 'failure'))
    args = parser.parse_args(); ctx = context(args)
    output = Path(ctx.admission['output'])
    if (output.parent != RELEASE or not output.name.startswith('arc09-')
            or output.resolve() != output or output.is_symlink()):
        raise ValueError('fresh repository-contained ARC09 output required')
    if args.guard_phase:
        if not output.is_dir(): raise ValueError('parent-owned output absent')
        destination = output / 'failure-diagnostics' if args.guard_phase == 'failure' else output
        guard_phase(ctx, destination, args.guard_phase); return
    output.mkdir(mode=0o700)
    started = time.monotonic(); whole = started + ctx.matrix['scheduling_envelope']['proposed_finite_whole_seconds']
    env = ctx.config['environment_exact']; daemon_receipts = []
    native_pins = dict(ctx.admission['native_evidence'])
    try:
        table = process_table()
        for daemon in ctx.admission['native_observed_daemons']:
            if daemon['pid'] in table or not group_absent(daemon['pgid']):
                raise ValueError('prior actual native daemon is not independently absent now')
        # Refuse an existing live Gradle daemon bound to the exact private home; never stop it.
        probe = DaemonTracker(ctx, output, 'preflight')
        for row in table.values():
            if probe.private_identity(row) is not None:
                raise ValueError('private Gradle home already has a live daemon')
        def invoke(label, argv, seconds, cwd, gradle=False):
            if time.monotonic() + seconds + 30 > whole:
                raise ValueError('finite whole envelope cannot admit next original command bound')
            tracker = DaemonTracker(ctx, output, label) if gradle else None
            original = ctx.controller.subprocess
            if tracker:
                def popen(*a, **kw):
                    child = subprocess.Popen(*a, **kw)
                    try:
                        tracker.register(child)
                    except BaseException as registration_error:
                        cleanup = {'spawned_pid': child.pid, 'registration_error': str(registration_error)}
                        try:
                            cleanup['exit_code'] = ctx.controller.stop_group(child)
                            cleanup['owned_wrapper_group_absent'] = group_absent(child.pid)
                        except BaseException as cleanup_error:
                            cleanup['cleanup_error'] = str(cleanup_error)
                        tracker.error = cleanup
                        save(output / (label + '.spawn-failure.json'), cleanup)
                        raise
                    return child
                ctx.controller.subprocess = types.SimpleNamespace(Popen=popen, TimeoutExpired=subprocess.TimeoutExpired)
            record = None
            daemon_result = None
            try:
                record = ctx.controller.run_process(output, label, argv, seconds, cwd, env)
            finally:
                ctx.controller.subprocess = original
                if tracker:
                    daemon_result = tracker.finish(); daemon_receipts.append(daemon_result)
            ctx.guards.process_success(record)
            if tracker and not daemon_result['owned_daemons_absent']:
                raise ValueError('separate owned daemon absence failed; exact observation retained')
            ctx.guards.forbid_upgrade_branch((output / (label + '.stdout')).read_text(),
                                            (output / (label + '.stderr')).read_text())
            return record
        def guards(phase):
            argv = [ctx.config['Python_executable'], '-I', '-B', str(PREP / 'source_fence.py'), 'verify',
                    '--root', str(ROOT), '--binding', str(RELEASE / 'root-native-warm-retry-review8/source-fence.json'),
                    '--binding-sha256', ctx.export['source_fence_sha256'],
                    '--output', str(output / ('source-fence-' + phase + '.json'))]
            invoke('source-fence-' + phase + '-command', argv, 300, PREP)
            argv = [ctx.config['Python_executable'], '-I', '-B', str(Path(__file__).resolve()),
                    '--admission', str(args.admission), '--admission-sha256', args.admission_sha256,
                    '--guard-phase', phase]
            invoke('combined-guard-' + phase + '-command', argv, 300, HERE)
        save(output / 'root-admission-captured.json', ctx.admission)
        guards('before')
        planned = ctx.matrix['commands']; original_output = ctx.matrix['output_directory_proposal']
        reuse_runtime_graph(ctx, output)
        for command in planned[1:3]:
            argv = [token.replace(original_output, str(output)) for token in command['argv']]
            invoke(command['label'], argv, command['deadline_seconds'], command['cwd'], True)
            if command is planned[1]:
                extract_graph(output / (command['label'] + '.stdout'), output / 'production-compile-graph.json',
                              'productionReleaseCompileClasspath')
        source = BASE / 'native-build/app/outputs/bundle/productionRelease/app-production-release.aab'
        copy = output / 'app-production-release.aab'
        save(output / 'AAB-copy-readback.json', copied_aab(ctx, source, copy))
        for command in planned[3:6]:
            argv = [token.replace(original_output, str(output)) for token in command['argv']]
            for name in ('production-observed-sbom.cdx.json', 'production-observed-inventory.json'):
                if command is planned[3] and (output / name).exists():
                    raise ValueError('preserve prior SBOM output rather than overwrite')
            invoke(command['label'], argv, command['deadline_seconds'], command['cwd'])
        guards('after')
        template = document(FINAL / 'artifact-bindings-template.json')
        template['inputs'] = []
        selected = {'root_native_admission': ('native-build', args.admission),
                    'export_manifest': ('source', APP / '.collect-release-candidate.json'),
                    'export_binding': ('source', RELEASE / 'root-native-warm-export8-readback1/export-source-binding.json'),
                    'SDK_before': ('sdk', output / 'SDK-source-before-built.json'),
                    'SDK_after': ('sdk', output / 'SDK-source-after-built.json'),
                    'APP_before': ('source', output / 'APP-source-before.json'),
                    'APP_after': ('source', output / 'APP-source-after.json'),
                    'pub_lock': ('lock', APP / 'pubspec.lock'),
                    'gradle_lock': ('lock', APP / 'android/app/gradle.lockfile'),
                    'packages': ('packages', output / 'actual-app-packages-after.json'),
                    'plugins': ('packages', output / 'actual-plugin-bindings-after.json'),
                    'runtime_graph': ('graph', output / 'production-runtime-graph.json'),
                    'compile_graph': ('graph', output / 'production-compile-graph.json'),
                    'observed_SBOM': ('dependency-inventory', output / 'production-observed-sbom.cdx.json'),
                    'observed_inventory': ('dependency-inventory', output / 'production-observed-inventory.json'),
                    'completed_build': ('build', output / 'production-release-aab.json')}
        for name, (role, path) in selected.items():
            template['inputs'].append({'label': name, 'role': role, 'path': str(path),
                                       'sha256': ctx.reader.stable_read(path)[0]['sha256']})
        for name, record in native_pins.items():
            template['inputs'].append({'label': 'native_' + name, 'role': 'native-proof',
                                      'path': record['path'], 'sha256': record['sha256']})
        for font in template['fonts']:
            font['sha256'] = ctx.reader.stable_read(Path(font['path']))[0]['sha256']
        save(output / 'artifact-bindings.json', template)
        aab_hash = ctx.reader.stable_read(copy)[0]['sha256']
        binding_hash = ctx.reader.stable_read(output / 'artifact-bindings.json')[0]['sha256']
        command = planned[6]
        argv = [token.replace(original_output, str(output)) for token in command['argv']]
        argv[argv.index('--aab') + 1] = str(copy)
        argv[argv.index('--aab-sha256') + 1] = aab_hash
        argv[argv.index('--bindings-sha256') + 1] = binding_hash
        invoke(command['label'], argv, command['deadline_seconds'], command['cwd'])
        if document(output / 'aab-readback.json')['status'] != 'pass':
            raise ValueError('actual archive reader did not pass')
        context(args)  # Current immutable admission, preparation references and runtime pins reread.
        for record in native_pins.values(): plain_read(record['path'], record['sha256'])
        save(output / 'terminal.json', {'status': 'pass', 'selected_local_AAB_observation_pass': True,
             'elapsed_seconds': time.monotonic() - started, 'whole_bound_seconds': whole - started,
             'AAB_sha256': aab_hash, 'bindings_sha256': binding_hash, 'daemon_receipts': daemon_receipts,
             'complete_package_SBOM_verified': False, 'signature_or_unsignedness_verified': False,
             'font_rights_verified': False, 'ARC09_closed': False, 'production_release_approval': False})
    except BaseException as error:
        diagnostics = {}
        remaining = whole - time.monotonic() - 30
        if remaining > 0:
            diagnostic = output / 'failure-diagnostics'; diagnostic.mkdir(mode=0o700)
            command = [ctx.config['Python_executable'], '-I', '-B', str(Path(__file__).resolve()),
                       '--admission', str(args.admission), '--admission-sha256', args.admission_sha256,
                       '--guard-phase', 'failure']
            try:
                diagnostics['process'] = ctx.controller.run_process(diagnostic, 'actual-failure-guard-command',
                    command, min(300, remaining), HERE, env)
            except BaseException as diagnostic_error:
                diagnostics['diagnostic_error'] = {'type': type(diagnostic_error).__name__, 'error': str(diagnostic_error)}
        else:
            diagnostics['finite_remaining_budget_exhausted'] = True
        save(output / 'terminal.json', {'status': 'fail', 'error_type': type(error).__name__,
             'actual_error': str(error), 'partial_failure_preserved': True,
             'daemon_receipts': daemon_receipts, 'bounded_failure_diagnostics': diagnostics,
             'elapsed_seconds': time.monotonic() - started,
             'offline_failure_does_not_create_new_user_permission_requirement': True,
             'root_may_assess_authorized_public_provenance_acquisition': True,
             'production_release_approval': False, 'ARC09_closed': False})
        raise


if __name__ == '__main__':
    main()

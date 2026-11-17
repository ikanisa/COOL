#!/usr/bin/env python3
"""Interrupt an owned synthetic PostgreSQL fixture; never inspect other clusters."""
import json
import os
from contextlib import contextmanager
from pathlib import Path
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

HERE = Path(__file__).resolve().parent.parent


class ParentInterrupted(KeyboardInterrupt):
    def __init__(self, signum):
        self.signum = signum


def interrupt_parent(signum, _frame):
    # Only the first interruption should initiate teardown. In particular, a
    # repeated CI cancellation must not interrupt the fixture's stop/verify path.
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    raise ParentInterrupted(signum)


def stop_owned_fixture(proc, timeout=25):
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    try:
        _, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        # No cleanup is claimed if the task-owned process group had to be killed.
        print('owned test process did not exit after TERM; forcing its group to stop', file=sys.stderr)
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        _, stderr = proc.communicate(timeout=5)
    if stderr:
        print(stderr, end='', file=sys.stderr)


@contextmanager
def owned_process_session(args, *, env, cleanup_timeout=25):
    # No signal can land between starting the detached process and entering its
    # cleanup block. Restore the child's mask before exec so TERM/INT reach it.
    old_mask = signal.pthread_sigmask(signal.SIG_BLOCK, (signal.SIGTERM, signal.SIGINT))
    try:
        proc = subprocess.Popen(args, cwd=HERE, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, start_new_session=True,
                                preexec_fn=lambda: signal.pthread_sigmask(signal.SIG_SETMASK, old_mask))
        try:
            signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)
            yield proc
        finally:
            stop_owned_fixture(proc, timeout=cleanup_timeout)
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)


class OwnedClusterCancellation(unittest.TestCase):
    def test_term_and_int_stop_only_the_owned_cluster(self):
        with tempfile.TemporaryDirectory(prefix='collect-sms-cancel-test-') as tmp:
            runner = Path(tmp) / 'fake-deno'
            runner.write_text('#!/bin/bash\nprintf "READY %s\\n" "$MANAGED_SMS_FIXTURE_SOCKET"\nexec /bin/sleep 60\n')
            runner.chmod(0o700)
            for sig in (signal.SIGTERM, signal.SIGINT):
              for send_group in (False, True):
                with self.subTest(sig=sig, send_group=send_group):
                    env = dict(os.environ, COLLECT_SMS_TEST_DENO_BIN=str(runner))
                    task_dir = None
                    try:
                        with owned_process_session(['/bin/bash', 'test/run-local-postgres.sh'], env=env) as proc:
                            ready, _, _ = select.select([proc.stdout], [], [], 30)
                            self.assertTrue(ready, 'owned fixture never reached the test runner')
                            line = proc.stdout.readline().strip()
                            self.assertTrue(line.startswith('READY /'), 'owned fixture returned no readiness marker')
                            socket = Path(line.removeprefix('READY '))
                            task_dir = socket.parent
                            self.assertTrue(task_dir.name.startswith('collect-managed-sms-'))
                            self.assertTrue((task_dir / 'data' / 'postmaster.pid').is_file())
                            if send_group:
                                os.killpg(proc.pid, sig)
                            else:
                                os.kill(proc.pid, sig)
                            _, stderr = proc.communicate(timeout=25)
                            self.assertEqual(proc.returncode, 128 + sig, stderr)
                            self.assertFalse(task_dir.exists(), 'owned fixture did not remove its confirmed-stopped cluster')
                    finally:
                        # Never remove an unconfirmed server's directory in a test cleanup.
                        if task_dir is not None and task_dir.exists():
                            print('owned test cluster retained for inspection:', task_dir)

    def test_parent_term_cleans_its_detached_fixture(self):
        for send_group in (False, True):
            with self.subTest(send_group=send_group):
                self.check_parent_term_cleans_its_detached_fixture(send_group)

    def check_parent_term_cleans_its_detached_fixture(self, send_group):
        # Hold the existing TERM case at its first signal, after its real fresh
        # cluster is ready, then interrupt the Python parent itself. This uses no
        # network or existing database and does not alter the test's fixture code.
        bootstrap = '''
import json, os, runpy, signal, sys
from pathlib import Path
original_kill = os.kill
def hold_first_fixture_signal(pid, signum):
    frame = sys._getframe(1)
    if frame.f_code.co_name == "test_term_and_int_stop_only_the_owned_cluster":
        Path(os.environ["COLLECT_SMS_PARENT_PROBE_MARKER"]).write_text(json.dumps({
            "fixture_pid": pid, "task_dir": str(frame.f_locals["task_dir"])}))
        while True:
            signal.pause()
    return original_kill(pid, signum)
os.kill = hold_first_fixture_signal
path = sys.argv[1]
sys.argv = [path, "OwnedClusterCancellation.test_term_and_int_stop_only_the_owned_cluster"]
runpy.run_path(path, run_name="__main__")
'''
        with tempfile.TemporaryDirectory(prefix='collect-sms-parent-signal-test-') as tmp:
            marker = Path(tmp) / 'ready.json'
            env = dict(os.environ, COLLECT_SMS_PARENT_PROBE_MARKER=str(marker))
            fixture_pid = None
            task_dir = None
            try:
                with owned_process_session(
                    [sys.executable, '-c', bootstrap, str(Path(__file__).resolve())],
                    env=env, cleanup_timeout=45,
                ) as parent:
                    deadline = time.monotonic() + 30
                    while not marker.is_file() and time.monotonic() < deadline and parent.poll() is None:
                        time.sleep(0.05)
                    self.assertTrue(marker.is_file(), 'parent never reached its active fixture')
                    record = json.loads(marker.read_text())
                    fixture_pid = int(record['fixture_pid'])
                    task_dir = Path(record['task_dir'])
                    self.assertTrue(task_dir.name.startswith('collect-managed-sms-'))
                    self.assertTrue((task_dir / 'data' / 'postmaster.pid').is_file())
                    if send_group:
                        os.killpg(parent.pid, signal.SIGTERM)
                    else:
                        os.kill(parent.pid, signal.SIGTERM)
                    _, stderr = parent.communicate(timeout=35)
                    self.assertEqual(parent.returncode, 128 + signal.SIGTERM, stderr)
                    self.assertFalse(task_dir.exists(), 'parent TERM left its owned fixture behind')
            finally:
                # If the regression fails, try the captured fixture's own group;
                # never remove an unconfirmed server directory ourselves.
                if fixture_pid is not None and task_dir is not None and task_dir.exists():
                    try:
                        if os.getsid(fixture_pid) == fixture_pid and os.getpgid(fixture_pid) == fixture_pid:
                            os.killpg(fixture_pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    deadline = time.monotonic() + 25
                    while task_dir.exists() and time.monotonic() < deadline:
                        time.sleep(0.05)
                    if task_dir.exists():
                        print('owned parent-test cluster retained for inspection:', task_dir)

    def test_unconfirmed_start_or_stop_retains_evidence(self):
        # Fake binaries never launch a server or send a signal. Their synthetic
        # PID is this test process, so an accidental OS kill would fail the test.
        with tempfile.TemporaryDirectory(prefix='collect-sms-mock-pg-') as tmp:
            tools = Path(tmp) / 'bin'
            tools.mkdir()
            init = tools / 'initdb'
            init.write_text('#!/bin/bash\nif [ "$1" = --version ]; then echo "initdb (PostgreSQL) 17.1"; exit; fi\nmkdir -p "$2"\n')
            ctl = tools / 'pg_ctl'
            ctl.write_text('#!/bin/bash\nif [ "${@: -1}" = start ]; then\n if [ "$FAKE_MODE" = startup ]; then exit 1; fi\n printf "%s\\n%s\\n" "$FAKE_PID" "$2" > "$2/postmaster.pid"; exit 0\nfi\nexit 1\n')
            psql = tools / 'psql'
            psql.write_text('#!/bin/bash\nexit 0\n')
            runner = Path(tmp) / 'fake-deno'
            runner.write_text('#!/bin/bash\nprintf "READY %s\\n" "$MANAGED_SMS_FIXTURE_SOCKET"\nexit 0\n')
            for path in (init, ctl, psql, runner):
                path.chmod(0o700)
            for mode in ('startup', 'stop'):
                with self.subTest(mode=mode):
                    env = dict(os.environ, COLLECT_SMS_TEST_PG_BIN=str(tools), COLLECT_SMS_TEST_DENO_BIN=str(runner),
                               FAKE_MODE=mode, FAKE_PID=str(os.getpid()))
                    result = subprocess.run(['/bin/bash', 'test/run-local-postgres.sh'], cwd=HERE, env=env,
                                            capture_output=True, text=True, timeout=15)
                    self.assertEqual(result.returncode, 1)
                    self.assertIn('unconfirmed; retained ', result.stderr)
                    path = Path(result.stderr.strip().split(' retained ')[-1])
                    self.assertTrue(path.name.startswith('collect-managed-sms-'))
                    self.assertTrue(path.is_dir())
                    try:
                        if mode == 'stop':
                            self.assertEqual((path / 'data' / 'postmaster.pid').read_text().splitlines()[0], str(os.getpid()))
                    finally:
                        # All binaries above are test-owned stubs and spawned no server.
                        shutil.rmtree(path)

if __name__ == '__main__':
    signal.signal(signal.SIGTERM, interrupt_parent)
    signal.signal(signal.SIGINT, interrupt_parent)
    try:
        unittest.main()
    except ParentInterrupted as exc:
        raise SystemExit(128 + exc.signum)

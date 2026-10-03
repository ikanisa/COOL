"""Actual local pipes and Python children only; no SQL, Docker or provider calls."""
from pathlib import Path
import errno
import importlib.util
import os
import sys
import tempfile
import time
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


r = load('proposed_io_runner', HERE / 'rehearsal.py')
baseline = load('retained_io_runner', HERE.parent / 'ordinary-recovery-replay-preparation4/rehearsal.py')
OBSERVED = []
BODY = b'B' + b'synthetic-pipe-body' * 32768
PRESSURE_CHILD = (
    'import sys,time;time.sleep(.15);first=sys.stdin.buffer.read(4096);'
    'time.sleep(.15);rest=sys.stdin.buffer.read();data=first+rest;'
    'payload=data.lstrip(b"P");sys.stdout.buffer.write(payload);'
    'sys.stderr.write(str(len(data)-len(payload)))')


class PipeIOTests(unittest.TestCase):
    def child_capture(self, module, children):
        real_popen = module.subprocess.Popen

        def spawn(*args, **kwargs):
            child = real_popen(*args, **kwargs)
            children.append(child)
            return child
        return mock.patch.object(module.subprocess, 'Popen', spawn)

    def pressure(self, module, children, observations):
        real_write = module.os.write
        observations.update(prefill_bytes=0, write_eagain=0, actual_shortwrites=0, broken_pipe=0)
        filled = False

        def write(fd, data):
            nonlocal filled
            if not children or children[-1].stdin is None or fd != children[-1].stdin.fileno():
                return real_write(fd, data)
            if not filled:
                # A competing writer fills the actual nonblocking stdin pipe
                # after selector readiness. The child discards this known prefix.
                while observations['prefill_bytes'] < 1024**2:
                    try:
                        observations['prefill_bytes'] += real_write(fd, b'P' * 1024)
                    except BlockingIOError as error:
                        if error.errno not in (errno.EAGAIN, errno.EWOULDBLOCK):
                            raise
                        break
                else:
                    raise AssertionError('bounded fixture failed to create pipe backpressure')
                filled = True
            try:
                written = real_write(fd, data)
            except BlockingIOError as error:
                observations['write_eagain'] += 1
                observations['errno'] = error.errno
                raise
            except BrokenPipeError:
                observations['broken_pipe'] += 1
                raise
            if 0 < written < len(data):
                observations['actual_shortwrites'] += 1
            return written
        return mock.patch.object(module.os, 'write', write)

    def cleaned(self, children):
        self.assertTrue(children)
        self._child_completion = []
        for child in children:
            self.assertIsNotNone(child.returncode)
            self.assertTrue(all(stream is None or stream.closed for stream in (child.stdin, child.stdout, child.stderr)))
            with self.assertRaises(ProcessLookupError):
                os.killpg(child.pid, 0)
            self._child_completion.append(dict(pid=child.pid, returncode=child.returncode,
                streams_closed=True, process_group_absent=True))

    def test_real_stdin_backpressure_and_kernel_shortwrites_preserve_exact_body(self):
        with tempfile.TemporaryDirectory() as tmp:
            children = []; observed = {'case': self._testMethodName}
            runner = r.Runner(Path(tmp), time.monotonic() + 5)
            with self.child_capture(r, children), self.pressure(r, children, observed):
                answer = runner.call([sys.executable, '-I', '-B', '-c', PRESSURE_CHILD], BODY, timeout=3)
            self.assertEqual(answer.returncode, 0)
            self.assertEqual(answer.stdout, BODY)
            self.assertEqual(int(answer.stderr), observed['prefill_bytes'])
            self.assertGreater(observed['write_eagain'], 0)
            self.assertGreater(observed['actual_shortwrites'], 0)
            self.assertEqual(runner.records[0]['input_sha256'], r.sha(BODY))
            self.assertEqual(runner.records[0]['stdout_sha256'], r.sha(BODY))
            self.cleaned(children)
            observed.update(exact_body=True, process_group_absent=True, child_completion=self._child_completion, record=runner.records[0])
            OBSERVED.append(observed)

    def test_retained_original_runner_refuses_same_actual_backpressure(self):
        with tempfile.TemporaryDirectory() as tmp:
            children = []; observed = {'case': self._testMethodName}
            runner = baseline.Runner(Path(tmp), time.monotonic() + 5)
            with self.child_capture(baseline, children), self.pressure(baseline, children, observed):
                with self.assertRaises(BlockingIOError) as caught:
                    runner.call([sys.executable, '-I', '-B', '-c', PRESSURE_CHILD], BODY, timeout=3)
            self.assertIn(caught.exception.errno, (errno.EAGAIN, errno.EWOULDBLOCK))
            self.assertGreater(observed['write_eagain'], 0)
            self.assertEqual(runner.records[0]['status'], 'refused')
            self.cleaned(children)
            observed.update(original_failure_observed=True, process_group_absent=True, child_completion=self._child_completion, record=runner.records[0])
            OBSERVED.append(observed)

    def test_real_stdout_readiness_race_retries_without_losing_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            children = []; observed = {'case': self._testMethodName, 'read_eagain': 0}
            runner = r.Runner(Path(tmp), time.monotonic() + 5)
            real_read = r.os.read; pending = None; raced = False

            def read(fd, count):
                nonlocal pending, raced
                if not children or fd != children[-1].stdout.fileno():
                    return real_read(fd, count)
                if pending is not None:
                    value, pending = pending, None
                    return value
                if not raced:
                    pending = real_read(fd, count)
                    self.assertEqual(pending, b'ready')
                    raced = True
                    try:
                        real_read(fd, count)
                    except BlockingIOError as error:
                        observed['read_eagain'] += 1
                        observed['errno'] = error.errno
                        raise
                    raise AssertionError('actual stdout pipe did not create readiness race')
                return real_read(fd, count)

            code = 'import sys,time;sys.stdout.buffer.write(b"ready");sys.stdout.flush();time.sleep(.2);sys.stdout.buffer.write(b"tail")'
            with self.child_capture(r, children), mock.patch.object(r.os, 'read', read):
                answer = runner.call([sys.executable, '-I', '-B', '-c', code], timeout=2)
            self.assertEqual(answer.stdout, b'readytail')
            self.assertEqual(observed['read_eagain'], 1)
            self.cleaned(children)
            observed.update(exact_output=True, process_group_absent=True, child_completion=self._child_completion, record=runner.records[0])
            OBSERVED.append(observed)

    def test_backpressured_stdin_timeout_retains_deadline_and_group_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            children = []; observed = {'case': self._testMethodName}
            deadline = time.monotonic() + 2
            runner = r.Runner(Path(tmp), deadline)
            start = time.monotonic()
            with self.child_capture(r, children), self.pressure(r, children, observed):
                with self.assertRaisesRegex(r.Refused, 'BOUNDED_TOOL_DEADLINE'):
                    runner.call([sys.executable, '-I', '-B', '-c', 'import time;time.sleep(3)'], BODY, timeout=.15)
            self.assertEqual(runner.deadline, deadline)
            self.assertLess(time.monotonic() - start, 1)
            self.assertGreater(observed['write_eagain'], 0)
            self.assertEqual(runner.records[0]['input_sha256'], r.sha(BODY))
            self.cleaned(children)
            observed.update(process_group_absent=True, child_completion=self._child_completion, record=runner.records[0])
            OBSERVED.append(observed)

    def test_early_child_exit_preserves_brokenpipe_and_nonzero_exit_contract(self):
        for check in (False, True):
            with self.subTest(check=check), tempfile.TemporaryDirectory() as tmp:
                children = []; observed = {'case': self._testMethodName, 'check': check}
                runner = r.Runner(Path(tmp), time.monotonic() + 5)
                code = 'import sys,time;time.sleep(.15);sys.stderr.write("early-exit");sys.exit(7)'
                with self.child_capture(r, children), self.pressure(r, children, observed):
                    if check:
                        with self.assertRaisesRegex(r.Refused, 'TOOL_FAILED'):
                            runner.call([sys.executable, '-I', '-B', '-c', code], BODY, check=check, timeout=2)
                    else:
                        answer = runner.call([sys.executable, '-I', '-B', '-c', code], BODY, check=check, timeout=2)
                        self.assertEqual(answer.returncode, 7)
                        self.assertEqual(answer.stderr, b'early-exit')
                self.assertGreater(observed['write_eagain'], 0)
                self.assertGreater(observed['broken_pipe'], 0)
                self.assertEqual(runner.records[0]['exit_code'], 7)
                self.cleaned(children)
                observed.update(process_group_absent=True, child_completion=self._child_completion, record=runner.records[0])
                OBSERVED.append(observed)

    def test_other_io_errors_remain_fatal_and_cleanup_is_preserved(self):
        for operation, error in [('read', OSError(errno.EIO, 'injected fatal IO')), ('write', BlockingIOError(errno.EINPROGRESS, 'injected non-retry IO'))]:
            with self.subTest(operation=operation), tempfile.TemporaryDirectory() as tmp:
                children = []; observed = {'case': self._testMethodName, 'operation': operation, 'errno': error.errno}
                runner = r.Runner(Path(tmp), time.monotonic() + 5)
                original = getattr(r.os, operation)

                def failing(fd, value):
                    if not children:
                        return original(fd, value)
                    stream = children[-1].stdout if operation == 'read' else children[-1].stdin
                    if stream is not None and fd == stream.fileno():
                        raise error
                    return original(fd, value)

                code = 'import sys,time;sys.stdout.write("ready");sys.stdout.flush();time.sleep(3)'
                with self.child_capture(r, children), mock.patch.object(r.os, operation, failing):
                    with self.assertRaises(OSError) as caught:
                        runner.call([sys.executable, '-I', '-B', '-c', code], BODY if operation == 'write' else None, timeout=2)
                self.assertEqual(caught.exception.errno, error.errno)
                self.assertEqual(runner.records[0]['status'], 'refused')
                self.cleaned(children)
                observed.update(process_group_absent=True, child_completion=self._child_completion, record=runner.records[0])
                OBSERVED.append(observed)


if __name__ == '__main__':
    unittest.main(verbosity=2)

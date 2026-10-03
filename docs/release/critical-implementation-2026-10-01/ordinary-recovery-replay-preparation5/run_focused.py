"""Run only the two affected original Runner tests and six focused IO cases."""
from pathlib import Path
import importlib.util
import json
import sys
import unittest

HERE = Path(__file__).resolve().parent
PYTHON = '/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3'
if sys.executable != PYTHON or not sys.flags.isolated or not sys.dont_write_bytecode:
    raise ValueError('Exact absolute isolated Python required')


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


original = load('unchanged_original_tests', HERE / 'test_rehearsal.py')
focused = load('focused_io_tests', HERE / 'test_runner_io.py')
suite = unittest.TestSuite([
    unittest.defaultTestLoader.loadTestsFromTestCase(original.RunnerTests),
    unittest.defaultTestLoader.loadTestsFromTestCase(focused.PipeIOTests),
])
outcome = unittest.TextTestRunner(verbosity=2).run(suite)
with (HERE / 'actual-io-observations.json').open('x') as stream:
    stream.write(json.dumps(dict(test_count=outcome.testsRun, failures=len(outcome.failures), errors=len(outcome.errors),
        observations=focused.OBSERVED, old_SQL_tests_executed=False, docker_executed=False), indent=2) + '\n')
sys.exit(0 if outcome.wasSuccessful() else 1)

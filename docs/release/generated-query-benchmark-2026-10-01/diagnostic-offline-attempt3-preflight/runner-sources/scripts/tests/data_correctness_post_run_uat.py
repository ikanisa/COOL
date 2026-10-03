#!/usr/bin/env python3
"""Read-only completion proof for a finished data gate whose drift recorder failed.

The original failure remains intact. No test, SQL, provider or browser is run.
Only a missing original source input after all four successful commands permits
this proof, and every export/tool/log/machine receipt must still match.
"""
import argparse
import json
from pathlib import Path
import sys

from roster_fresh_auth_gate import ROOT, hashes, machine_summary, sha, source_files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prior', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    release = ROOT / 'docs/release/data-correctness-2026-09-30'
    prior = args.prior.resolve(strict=True)
    output = args.output.resolve()
    if not prior.is_relative_to(release) or not output.is_relative_to(release):
        parser.error('Local data release packets are required')
    output.mkdir(parents=True, exist_ok=False)
    original = prior / 'validation.json'
    inputs_path = prior / 'inputs.json'
    captured = {'validation.json': sha(original), 'inputs.json': sha(inputs_path)}
    result = {'status': 'fail', 'whole_system_acceptance': False,
              'sql_executed_here': False, 'provider_calls': False,
              'tests_executed_here': False, 'browser_executed_here': False,
              'completion_script_sha256': sha(Path(__file__).resolve()),
              'source_packet': str(prior.relative_to(ROOT)),
              'original_failure_preserved': False}
    try:
        script = Path(__file__).resolve()
        (output / 'completion-script.py').write_bytes(script.read_bytes())
        if sha(output / 'completion-script.py') != result['completion_script_sha256']:
            raise RuntimeError('Completion source changed during capture')
        original_result = json.loads(original.read_text())
        inputs = json.loads(inputs_path.read_text())
        error = original_result.get('error', '')
        prefix = "FileNotFoundError: [Errno 2] No such file or directory: '"
        if original_result['status'] != 'fail' or not error.startswith(prefix) or not error.endswith("'"):
            raise RuntimeError('Only the retained missing-source drift recording failure is eligible')
        missing = Path(error[len(prefix):-1])
        if not missing.is_relative_to(ROOT) or str(missing.relative_to(ROOT)) not in inputs['source']:
            raise RuntimeError('The original failure is not a captured source input')
        commands = original_result.get('commands', [])
        if [c['name'] for c in commands] != ['toolchain', 'analysis', 'vm', 'browser']:
            raise RuntimeError('All four original commands are required')
        for receipt in commands:
            if (receipt['exit_code'] != 0 or receipt['timed_out']
                    or not receipt['parent_exit_confirmed'] or receipt['termination_errors']):
                raise RuntimeError('Every original command must be terminal and successful')
            for stream in ['stdout', 'stderr']:
                name = receipt['name'] + '.' + stream
                captured[name] = sha(prior / name)
                if captured[name] != receipt[stream + '_sha256']:
                    raise RuntimeError('Original command output changed: ' + name)
        summaries = {}
        for name in ['vm', 'browser']:
            machine = prior / (name + '.machine.jsonl')
            captured[machine.name] = sha(machine)
            summary = machine_summary(machine)
            if summary != original_result[name]:
                raise RuntimeError('Original machine-event summary changed: ' + name)
            if (not summary['runner_completed_successfully'] or summary['passed'] <= 0
                    or summary['failed'] or summary['errors'] or summary['skipped']):
                raise RuntimeError('Successful, complete, unskipped actual tests are required')
            summaries[name] = summary
        export = prior / 'source-export'
        if inputs['export'] != hashes([export / name for name in inputs['export']], export):
            raise RuntimeError('Immutable export inputs changed')
        if not all(Path(name).is_file() and sha(Path(name)) == value
                   for name, value in inputs['sdk_and_browser'].items()):
            raise RuntimeError('Bound SDK/browser inputs changed')
        scope = inputs.get('actual_sql_history_scope')
        if scope:
            receipts = prior / 'actual-history-sql'
            if sha(receipts / 'result.json') != scope['result_sha256']:
                raise RuntimeError('Captured SQL result changed')
            for name, value in scope['artifact_sha256'].items():
                if sha(receipts / name) != value:
                    raise RuntimeError('Captured SQL artifact changed: ' + name)
            if sha(export / '.qa_actual_history_defines.json') != scope['define_file_sha256']:
                raise RuntimeError('Captured actual SQL decoder define changed')
            retained = scope.get('retained_unsafe_scope')
            if retained and sha(receipts / 'retained-unsafe-result.json') != retained['result_sha256']:
                raise RuntimeError('Retained negative SQL receipt changed')
        # Use the gate that was copied before execution to declare its static
        # inputs. The current recorder may itself have changed since that copy.
        bound_gate = export / 'scripts/tests/data_correctness_gate.py'
        if sha(bound_gate) != inputs['source']['scripts/tests/data_correctness_gate.py']:
            raise RuntimeError('Original source-bound gate changed')
        live_files = set(source_files()) | {ROOT / name for name in inputs['declared_static_test_inputs']}
        live_files.add(ROOT / 'scripts/tests/data_correctness_gate.py')
        live = hashes(sorted(p for p in live_files if p.is_file()), ROOT)
        before = inputs['source']
        changed = sorted(name for name in set(before) | set(live)
                         if before.get(name) != live.get(name))
        if not changed:
            raise RuntimeError('Expected recorded source drift is absent')
        for name, value in captured.items():
            if sha(prior / name) != value:
                raise RuntimeError('Original evidence changed during completion: ' + name)
        if sha(script) != result['completion_script_sha256']:
            raise RuntimeError('Completion source changed during verification')
        result.update(status='pass', acceptance_scope='immutable_completed_client_commands',
                      commands=commands, **summaries, actual_sql_history_scope=scope,
                      inputs_sha256=captured['inputs.json'], export_unchanged=True,
                      sdk_and_browser_unchanged=True, current_source_acceptance=False,
                      live_source_drift=changed,
                      live_source_removed=sorted(set(before) - set(live)),
                      live_source_added=sorted(set(live) - set(before)),
                      original_failure_preserved=True, original_failure=error,
                      original_status='fail', original_evidence_sha256=captured,
                      source_file_count=len(before), export_file_count=len(inputs['export']))
        (output / 'live-source-readback.json').write_text(json.dumps(live, indent=2) + '\n')
        result['live_source_readback_sha256'] = sha(output / 'live-source-readback.json')
    except Exception as exc:
        result['error'] = type(exc).__name__ + ': ' + str(exc)
    (output / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result.get(key) for key in [
        'status', 'current_source_acceptance', 'original_failure_preserved',
        'live_source_removed', 'live_source_added', 'error']}, indent=2))
    return 0 if result['status'] == 'pass' else 1


if __name__ == '__main__':
    sys.exit(main())

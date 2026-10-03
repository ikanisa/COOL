#!/usr/bin/env python3
"""Continue only post-VM stages of an unchanged, timed-out Auth export.

The original failed packet stays intact. Successful machine VM events, every
copied input, static SQL receipts, SDK inputs and current-source drift are bound
again. No database, hosted service or provider is contacted.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys
import traceback

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prior', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--flutter', required=True, type=Path)
    parser.add_argument('--node', default='node')
    args = parser.parse_args()
    prior = args.prior.resolve(strict=True)
    packet = args.output.resolve()
    if not prior.is_relative_to(ROOT / 'docs/release') or not packet.is_relative_to(ROOT / 'docs/release'):
        parser.error('Repository release packets are required')
    packet.mkdir(parents=True, exist_ok=False)
    export = prior / 'source-export'
    spec = importlib.util.spec_from_file_location('bound_auth_gate', export / 'scripts/tests/roster_fresh_auth_gate.py')
    gate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gate)
    # Current source is inspected, while executable fixture/SDK inputs come only
    # from the already copied packet.
    gate.ROOT = ROOT
    inputs = json.loads((prior / 'inputs.json').read_text())
    original = json.loads((prior / 'validation.json').read_text())
    machine = gate.machine_summary(prior / 'tests.machine.jsonl')
    commands = original['commands']
    if not (original['status'] == 'fail' and len(commands) == 3
            and [c['name'] for c in commands] == ['toolchain', 'tests', 'analysis']
            and all(c['exit_code'] == 0 for c in commands[:2])
            and commands[-1]['timed_out'] and commands[-1]['exit_code'] == 124
            and machine == original['machine_summary']
            and machine['runner_completed_successfully'] and machine['passed'] == original['test_count']
            and not any(machine[k] for k in ['failed', 'errors', 'unfinished', 'event_errors'])
            and gate.actual_sql149_test_passed(machine)):
        raise RuntimeError('Prior packet is not an accepted VM run followed only by an analysis timeout')
    for c in commands:
        for stream in ('stdout', 'stderr'):
            if gate.sha(prior / f"{c['name']}.{stream}") != c[f'{stream}_sha256']:
                raise RuntimeError('Prior command output changed')
    export_before = inputs['export']
    sdk_before = inputs['sdk_library_inputs']
    if gate.hashes([export / p for p in export_before], export) != export_before:
        raise RuntimeError('Prior copied source/dependency inputs changed')
    if {p: gate.sha(Path(p)) for p in sdk_before} != sdk_before:
        raise RuntimeError('SDK inputs changed since successful VM execution')
    receipt = prior / 'actual-sql149.stdout'
    receipt_result = prior / 'actual-sql149.result.json'
    binding = original['actual_sql149_receipt_input']
    if gate.sha(receipt) != binding['stdout_sha256'] or gate.sha(receipt_result) != binding['result_sha256']:
        raise RuntimeError('Actual149 static receipts changed')
    evidence = {
        'prior_validation_sha256': gate.sha(prior / 'validation.json'),
        'prior_inputs_sha256': gate.sha(prior / 'inputs.json'),
        'prior_machine_events_sha256': gate.sha(prior / 'tests.machine.jsonl'),
        'continuation_source_sha256': gate.sha(Path(__file__)),
        'bound_gate_source_sha256': gate.sha(export / 'scripts/tests/roster_fresh_auth_gate.py'),
        'original_analysis_timeout_seconds': 120,
        'new_analysis_timeout_seconds': 600,
        'vm_reexecuted': False,
        'prior_failure_preserved': True,
    }
    (packet / 'inputs.json').write_text(json.dumps(evidence, indent=2) + '\n')
    flutter = args.flutter.resolve(strict=True)
    dart = flutter.parent / 'cache/dart-sdk/bin/dart'
    fixture = packet / 'browser-auth-fixture.js'
    browser_packet = packet / 'browser'
    normal_packet = packet / 'normal-admin-browser'
    normal_web = packet / 'normal-admin-web'
    environment = os.environ.copy()
    environment.update(COLLECT_AUTH_REFERENCE_PACKET=str(browser_packet),
                       COLLECT_AUTH_REFERENCE_BUNDLE=str(fixture),
                       COLLECT_ROSTER_BROWSER_PACKET=str(normal_packet),
                       COLLECT_ROSTER_BROWSER_WEB=str(normal_web),
                       COLLECT_ROSTER_BROWSER_SQL_RECEIPTS=str(receipt))
    steps = [
        ('analysis', [str(dart), 'analyze', *gate.OWNED_ANALYSIS], 600),
        ('browser-compile', [str(dart), 'compile', 'js', '-O2',
                            'tool/qa/browser_auth_reference_fixture.dart', '-o', str(fixture)], 600),
        ('browser', [args.node, 'scripts/qa/browser_auth_reference/validate.mjs'], 180),
        ('normal-browser-build', [str(flutter), 'build', 'web', '--no-pub',
                                 '--no-web-resources-cdn', '--no-wasm-dry-run', '--target',
                                 'tool/qa/roster_fresh_auth_browser_fixture.dart', '--output', str(normal_web)], 900),
        ('normal-browser', [args.node, 'scripts/qa/browser_auth_reference/roster_dialog.mjs'], 240),
    ]
    completed = []
    web_before = None
    for name, argv, limit in steps:
        result = gate.command(name, argv, export, packet, environment=environment, timeout=limit)
        completed.append(result)
        print(json.dumps(result), flush=True)
        if name == 'normal-browser-build' and result['exit_code'] == 0:
            web_before = gate.hashes(sorted(p for p in normal_web.rglob('*') if p.is_file()), normal_web)
        if result['exit_code'] != 0:
            break
    browser = json.loads((browser_packet / 'report.json').read_text()) if (browser_packet / 'report.json').exists() else None
    normal = json.loads((normal_packet / 'report.json').read_text()) if (normal_packet / 'report.json').exists() else None
    export_after = gate.hashes([export / p for p in export_before], export)
    sdk_after = {p: gate.sha(Path(p)) for p in sdk_before}
    root_after = gate.hashes(gate.source_files(), ROOT)
    web_after = gate.hashes(sorted(p for p in normal_web.rglob('*') if p.is_file()), normal_web) if normal_web.is_dir() else None
    unchanged = (export_after == export_before and sdk_after == sdk_before
                 and gate.sha(prior / 'validation.json') == evidence['prior_validation_sha256']
                 and gate.sha(prior / 'inputs.json') == evidence['prior_inputs_sha256']
                 and gate.sha(prior / 'tests.machine.jsonl') == evidence['prior_machine_events_sha256']
                 and gate.sha(Path(__file__)) == evidence['continuation_source_sha256'])
    accepted = (len(completed) == len(steps) and all(c['exit_code'] == 0 for c in completed)
                and unchanged and browser is not None and browser['status'] == 'pass'
                and browser['bundle_unchanged'] and normal is not None and normal['status'] == 'pass'
                and normal['sql149_receipt_unchanged'] and web_before is not None and web_before == web_after)
    result = dict(evidence, status='pass' if accepted else 'fail', commands=completed,
        prior_packet=str(prior), test_count=machine['passed'], machine_summary=machine,
        immutable_export_unchanged=export_after == export_before,
        sdk_libraries_unchanged=sdk_after == sdk_before, all_bound_inputs_unchanged=unchanged,
        live_source_unchanged=inputs['source'] == root_after,
        live_source_drift=[p for p in sorted(set(inputs['source']) | set(root_after))
                           if inputs['source'].get(p) != root_after.get(p)],
        browser_report_sha256=gate.sha(browser_packet / 'report.json') if browser else None,
        normal_admin_browser_report_sha256=gate.sha(normal_packet / 'report.json') if normal else None,
        normal_admin_web_inputs=web_before, normal_admin_web_unchanged=web_before is not None and web_before == web_after,
        actual_sql149_receipts_verified=True, actual_sql149_receipt_input=binding,
        normal_admin_recovery_browser_verified=bool(accepted),
        database_calls=0, hosted_calls=0, provider_calls=0, whole_L01_complete=False,
        scope='Same unchanged Auth14 export: accepted VM machine events plus independently continued analysis and real Chrome/production Admin loopback browser stages; current live drift retained')
    (packet / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ('status', 'test_count', 'all_bound_inputs_unchanged', 'live_source_unchanged')}), flush=True)
    return 0 if accepted else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception:
        if '--output' in sys.argv:
            packet = Path(sys.argv[sys.argv.index('--output') + 1]).resolve()
            if packet.is_relative_to(ROOT / 'docs/release') and packet.is_dir():
                (packet / 'setup-error.txt').write_text(traceback.format_exc())
                if not (packet / 'validation.json').exists():
                    (packet / 'validation.json').write_text(json.dumps({'status': 'fail', 'phase': 'setup',
                        'database_calls': 0, 'hosted_calls': 0, 'provider_calls': 0}, indent=2) + '\n')
        raise

#!/usr/bin/env python3
"""Run actual Edge HTTP handlers against loopback-only synthetic dependencies."""
import datetime
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def partial_progress(stdout):
    records, truncated = [], False
    for line in stdout.splitlines():
        if not line.startswith('QA_EDGE_PROGRESS='):
            continue
        try:
            records.append(json.loads(line.removeprefix('QA_EDGE_PROGRESS=')))
        except json.JSONDecodeError:
            truncated = True
    return records, truncated


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: run_edge_http_uat.py NEW_EVIDENCE_DIRECTORY')
    output = pathlib.Path(sys.argv[1]).resolve()
    if output.exists() or not output.is_relative_to(ROOT / '.cache'):
        raise SystemExit('New evidence directory under this repository .cache required')
    output.mkdir(mode=0o700, parents=True)
    paths = [*sorted((ROOT / 'supabase/functions').rglob('*.ts')),
             ROOT / 'supabase/config.toml', ROOT / '.dvmrc',
             ROOT / 'scripts/qa/edge_http_runtime_uat.ts', ROOT / 'scripts/qa/run_edge_http_uat.py',
             ROOT / 'Makefile', ROOT / '.github/workflows/ci.yml']
    hashes = lambda: {str(p.relative_to(ROOT)): digest(p) for p in paths}
    sources = None
    report = {'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'status': 'fail', 'final_acceptance': False,
              'environment': 'loopback_only_synthetic_dependencies_no_inherited_credentials'}
    stdout, stderr = '', ''
    try:
        sources = hashes()
        report['source_inputs'] = sources
        snapshots = output / 'source-snapshots'
        for source in paths:
            target = snapshots / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
        selected = os.environ.get('DENO_BIN') or shutil.which('deno')
        if not selected:
            raise RuntimeError('Deno unavailable; use the .dvmrc runtime on PATH or set DENO_BIN')
        binary = pathlib.Path(selected).resolve()
        info = json.loads(subprocess.check_output([str(binary), 'info', '--json'], text=True, timeout=10))
        pin = (ROOT / '.dvmrc').read_text().strip()
        if info.get('denoVersion') != pin:
            raise RuntimeError('Deno must exactly match .dvmrc')
        report['runtime'] = {'path': str(binary), 'sha256': digest(binary), 'pinned_version': pin}
        command = [str(binary), 'run', '--check', '--no-config', '--no-lock', '--cached-only', '--no-prompt',
                   '--allow-env', '--allow-net=127.0.0.1',
                   '--deny-net=graph.facebook.com,oauth2.googleapis.com,playintegrity.googleapis.com,fcm.googleapis.com,api.push.apple.com,api.sandbox.push.apple.com,api.openai.com',
                   '--allow-read=supabase/functions,supabase/config.toml', 'scripts/qa/edge_http_runtime_uat.ts']
        report['command'] = command
        # The child cannot inherit hosted keys, provider accounts, or dotenv files.
        env = {'PATH': os.defpath, 'DENO_DIR': info['denoDir'],
               'NO_COLOR': '1', 'DENO_NO_UPDATE_CHECK': '1'}
        completed = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=60)
        stdout, stderr = completed.stdout, completed.stderr
        report['exit_code'] = completed.returncode
        reports = [line.removeprefix('QA_EDGE_REPORT=') for line in stdout.splitlines() if line.startswith('QA_EDGE_REPORT=')]
        if len(reports) != 1:
            raise RuntimeError('Exactly one completed HTTP runtime report required')
        result = json.loads(reports[0])
        if not isinstance(result, dict) or not isinstance(result.get('checks'), list):
            raise RuntimeError('Structured HTTP runtime checks required')
        if any(not isinstance(check, dict) or not isinstance(check.get('label'), str)
               for check in result['checks']):
            raise RuntimeError('Labeled HTTP runtime checks required')
        report['runtime_result'] = result
        checks = report['runtime_result'].get('checks', [])
        if not checks or any(check.get('status') != 'pass' for check in checks):
            raise RuntimeError('Nonempty passing HTTP checks required')
        report['status'] = 'pass' if completed.returncode == 0 and report['runtime_result']['status'] == 'pass' else 'fail'
    except subprocess.TimeoutExpired as error:
        stdout = error.stdout.decode() if isinstance(error.stdout, bytes) else error.stdout or ''
        stderr = error.stderr.decode() if isinstance(error.stderr, bytes) else error.stderr or ''
        report.update(status='fail', error=f'Deno command exceeded {error.timeout} seconds')
    except Exception as error:
        report.update(status='fail', error=str(error))
    finally:
        (output / 'stdout.log').write_text(stdout)
        (output / 'stderr.log').write_text(stderr)
        if 'runtime_result' not in report:
            report['partial_progress'], report['partial_progress_truncated'] = partial_progress(stdout)
        try:
            report['source_inputs_unchanged'] = sources is not None and sources == hashes()
        except OSError as error:
            report['source_inputs_unchanged'] = False
            report['source_verification_error'] = str(error)
        if not report['source_inputs_unchanged']:
            report['status'] = 'fail'
            report.setdefault('error', 'Source inputs changed during HTTP execution')
        report.update(finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                      stdout_sha256=digest(output / 'stdout.log'), stderr_sha256=digest(output / 'stderr.log'))
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    checks = report.get('runtime_result', {}).get('checks', [])
    print(json.dumps({'status': report['status'], 'checks': len(checks),
                      'failures': [r['label'] for r in checks if r['status'] != 'pass'],
                      'error': report.get('error'), 'report': str(output / 'report.json')}))
    return 0 if report['status'] == 'pass' else 1


if __name__ == '__main__':
    sys.exit(main())

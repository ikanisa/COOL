#!/usr/bin/env python3
"""Non-mutating Collect Admin source/SDK qualification runner.

This tool does not sign off financial security, deployment, accessibility,
installed-PWA or production runtime. It never sends requests to a live service.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REQUIRED_FILES = (
    'lib/admin/core/cloudflare_admin_sms_pages.dart',
    'lib/admin/core/cloudflare_admin_sms_ui.dart',
    'lib/admin/core/admin_receipt_presentation.dart',
    'test/admin/admin_revolut_receipts_uiux_test.dart',
)
MANUAL_GATES = (
    'Authenticated owner/reviewer/denied/revoked role and redaction UAT',
    '320/390/768/1024/1440 responsive screenshot comparison and 200% zoom',
    'Keyboard and assistive technology task validation',
    'Installed PWA offline/reconnect/update/shortcut recovery on target OS',
    'Financial command idempotency, audit evidence and uncertain outcomes',
    'Deployed source hash, backend contracts and production operator sign-off',
    'Field Web Vitals and representative task timing',
)

def make_check(name: str, status: str, detail: str = '') -> dict:
    return {'name': name, 'status': status, 'detail': detail}

def command_check(root: Path, name: str, argv: list[str], *, missing: str | None = None) -> dict:
    if missing:
        return make_check(name, 'blocked', missing)
    try:
        run = subprocess.run(argv, cwd=root, capture_output=True, text=True,
                             timeout=120, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return make_check(name, 'blocked', type(exc).__name__)
    # Log only the last few diagnostics, never dump secrets or full record data.
    output = (run.stdout + '\n' + run.stderr).strip().splitlines()
    detail = f'exit={run.returncode}; tail=' + ' | '.join(output[-4:])[:650]
    return make_check(name, 'passed' if run.returncode == 0 else 'failed', detail)

def inspect(root: Path, *, sdk: bool = False, artifact_dir: Path | None = None) -> dict:
    checks = []
    missing = [name for name in REQUIRED_FILES if not (root / name).is_file()]
    checks.append(make_check('required source files', 'passed' if not missing else 'failed',
                             ', '.join(missing)))
    checks.append(command_check(root, 'B05-B08 source contracts',
        [sys.executable, 'scripts/tests/admin_revolut_b05_b08_contract_test.py'],
        missing=None if (root / 'scripts/tests/admin_revolut_b05_b08_contract_test.py').is_file() else 'test file unavailable'))
    checks.append(command_check(root, 'B01-B04 source contracts',
        [sys.executable, 'scripts/tests/admin_revolut_uiux_contract_test.py'],
        missing=None if (root / 'scripts/tests/admin_revolut_uiux_contract_test.py').is_file() else 'existing source-contract suite not provided in this patch'))
    checks.append(command_check(root, 'admin build script syntax',
        ['bash', '-n', 'scripts/admin_pwa_release_build.sh'],
        missing=None if (root / 'scripts/admin_pwa_release_build.sh').is_file() else 'Admin build script is in the full repository, not this source patch'))
    if sdk:
        flutter = shutil.which('flutter')
        dart = shutil.which('dart')
        checks.append(command_check(root, 'Dart formatting',
            [dart or 'dart', 'format', '--output=none', '--set-exit-if-changed',
             *REQUIRED_FILES[:3], REQUIRED_FILES[3]],
            missing=None if dart else 'Dart SDK is unavailable'))
        checks.append(command_check(root, 'Flutter analyzer',
            [flutter or 'flutter', 'analyze', '--fatal-infos'],
            missing=None if flutter else 'Flutter SDK is unavailable'))
        checks.append(command_check(root, 'Flutter receipt widget tests',
            [flutter or 'flutter', 'test', 'test/admin/admin_revolut_receipts_uiux_test.dart',
             'test/admin/cloudflare_admin_sms_test.dart'],
            missing=None if flutter else 'Flutter SDK is unavailable'))
    else:
        checks.extend(make_check(name, 'unverified', 'Run with --sdk on the prepared Flutter workspace')
            for name in ('Dart formatting', 'Flutter analyzer', 'Flutter receipt widget tests'))
    if artifact_dir:
        for label, gate in [('PWA manifest', 'admin_pwa_manifest_gate.sh'),
                            ('PWA static hosting', 'admin_pwa_hosting_gate.sh')]:
            script = root / 'scripts' / gate
            if not script.is_file() or not artifact_dir.is_dir():
                checks.append(make_check(label, 'blocked', 'release gate or compiled web assets unavailable'))
            else:
                # Existing gate scripts take ADMIN_PWA_BUILD_DIR. Do not run any build.
                import os
                env = dict(os.environ, ADMIN_PWA_BUILD_DIR=str(artifact_dir))
                try:
                    r = subprocess.run(['bash', str(script)], cwd=root, env=env,
                        capture_output=True, text=True, timeout=120, check=False)
                    checks.append(make_check(label, 'passed' if r.returncode == 0 else 'failed',
                        f'exit={r.returncode}; static-artifact-only result'))
                except (OSError, subprocess.TimeoutExpired):
                    checks.append(make_check(label, 'blocked', 'gate could not execute'))
    else:
        checks.append(make_check('PWA artifact/hosting gates', 'unverified',
            'No compiled Admin web artifact supplied'))
    checks.extend(make_check(gate, 'requires_external_acceptance', 'No automated sign-off from this runner')
                  for gate in MANUAL_GATES)
    hashes = {f: hashlib.sha256((root / f).read_bytes()).hexdigest()
              for f in REQUIRED_FILES if (root / f).is_file()}
    return {
        'scope': 'Collect Admin B05-B08 source and optional SDK checks',
        'executed_at_utc': datetime.now(timezone.utc).isoformat(),
        'source_hashes': hashes,
        'checks': checks,
        'release_ready': False,  # external gates remain independent and mandatory
        'release_verdict': 'NOT ACCEPTED: complete hosted/visual/security/PWA evidence is required',
    }

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    ap.add_argument('--sdk', action='store_true', help='Run available Dart/Flutter tests; no build/deploy')
    ap.add_argument('--artifact-dir', type=Path, help='Existing Admin web build for read-only static gates')
    ap.add_argument('--report', type=Path, help='Write JSON report to this path')
    args = ap.parse_args()
    result = inspect(args.root.resolve(), sdk=args.sdk,
                     artifact_dir=args.artifact_dir.resolve() if args.artifact_dir else None)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 1 if any(x['status'] == 'failed' for x in result['checks']) else 0
if __name__ == '__main__':
    raise SystemExit(main())
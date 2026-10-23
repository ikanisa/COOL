#!/usr/bin/env python3
"""Capture current local release checks and validate separately supplied acceptance."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOTS = ('lib/', 'deploy/', 'scripts/', '.github/', 'android/', 'ios/', 'web/', 'test/', 'integration_test/', 'fastlane/', 'third_party/', 'supabase/', 'tools/')
SOURCE_FILES = {'pubspec.yaml', 'pubspec.lock', 'Makefile', '.fvmrc', '.env.example', 'Gemfile', 'Gemfile.lock', 'AGENTS.md'}
GENERATED = {'node_modules', 'Pods', '.cache', '.dart_tool', '.gradle', '.wrangler', 'build', '__pycache__', '.symlinks'}
# The newly included current roots use the reviewed candidate export's known
# private/configuration and generated-output boundaries. Existing roots retain
# their historical identity rules; names such as auth/token/secret source are
# never inferred to be private from wording alone.
CURRENT_SOURCE_ROOTS = {'supabase', 'tools'}
CURRENT_PRIVATE_NAMES = {
    'key.properties', 'local.properties', 'google-services.json', 'GoogleService-Info.plist',
    'Generated.xcconfig', 'MapsKeys.xcconfig', 'flutter_export_environment.sh',
    '.flutter-plugins-dependencies', 'credentials.json', 'service-account.json',
}
CURRENT_GENERATED_PARTS = {
    'node_modules', 'Pods', '.symlinks', '.gradle', '.kotlin', '.dart_tool',
    '.pub-cache', '.pub', '.swiftpm', '.build', '.git', '.cache', '.wrangler',
    'build', 'coverage', 'output', 'failures', '__pycache__', 'DerivedData', '.temp',
}
CURRENT_PRIVATE_OR_OUTPUT_SUFFIXES = {
    '.jks', '.keystore', '.p12', '.pfx', '.p8', '.pem', '.key', '.mobileprovision',
    '.apk', '.aab', '.ipa', '.class', '.pyc', '.log', '.dump', '.sql.gz',
    '.csv', '.tsv', '.xlsx', '.xls', '.pdf', '.zip', '.tar', '.gz', '.bak', '.old',
}


def current_source_excluded(path):
    if path.parts[0] not in CURRENT_SOURCE_ROOTS:
        return False
    return (path.name in CURRENT_PRIVATE_NAMES
            or (path.name.startswith('.env') and path.name != '.env.example')
            or path.name.startswith('GoogleService-Info-')
            or any(part in CURRENT_GENERATED_PARTS or part.startswith('build_stale_')
                   or part.endswith('.dSYM') for part in path.parts)
            or path.suffix.lower() in CURRENT_PRIVATE_OR_OUTPUT_SUFFIXES)

REQUIRED_HOSTED_CHECKS = ('hosted_authentication', 'hosted_authorization', 'financial_reconciliation', 'provider_delivery', 'backup_restore')
REQUIRED_COMMANDS = (
    ('source_integrity', ['bash', 'scripts/source_integrity_gate.sh', '--json']),
    ('design_authority', ['python3', 'scripts/qa/revolut_design_authority.py', '--json']),
    ('secret_scan', ['bash', 'scripts/release_secret_scan.sh']),
    ('ci_policy', ['python3', 'scripts/qa/collect_ci_policy.py']),
    ('qa_tooling', ['make', 'qa-tooling-test']),
    ('flutter_verify', ['make', 'verify']),
    ('supabase_tests', ['make', 'supabase-test']),
    ('notification_source', ['bash', 'scripts/notification_readiness_gate.sh']),
    ('mobile_release', ['bash', 'scripts/flutter_mobile_release_gate.sh', '--json']),
    ('admin_manifest', ['bash', 'scripts/admin_pwa_manifest_gate.sh', '--json']),
    ('admin_hosting', ['bash', 'scripts/admin_pwa_hosting_gate.sh', '--json']),
    ('admin_live', ['bash', 'scripts/admin_pwa_live_gate.sh', '--json']),
    ('uat_evidence', ['bash', 'scripts/uat_evidence_gate.sh', '--json']),
    ('uat_signoff', ['bash', 'scripts/uat_signoff_gate.sh', '--json']),
    ('release_approvals', ['bash', 'scripts/release_approval_evidence_gate.sh', '--json']),
    ('artifact_manifest', ['bash', 'scripts/release_artifact_manifest.sh', '--json']),
    ('worktree_review', ['bash', 'scripts/release_worktree_review_gate.sh', '--json']),
    ('hosted_acceptance', ['python3', 'scripts/qa/release_evidence.py', 'current-platform', '--json']),
)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def source_manifest(root=ROOT):
    names = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
    result = {}
    for name in sorted(set(names)):
        p = Path(name)
        if not name or not (name in SOURCE_FILES or name.startswith(SOURCE_ROOTS)) or any(x in GENERATED for x in p.parts) or current_source_excluded(p):
            continue
        path = root / name
        if not path.exists():
            continue
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError('Source inventory includes a non-regular or external path')
        result[name] = sha(path)
    return result

def manifest_sha(manifest):
    return hashlib.sha256(json.dumps(manifest, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

def read_json(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 16*1024*1024:
        raise ValueError('Required regular evidence JSON is missing or too large')
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError('Evidence JSON must be an object')
    return value

def hosted_acceptance(root=ROOT, path=None):
    """Historical Cloudflare record reader; cannot approve current Supabase release."""
    path = Path(path or os.environ.get('CLOUDFLARE_PLATFORM_ACCEPTANCE_JSON', root / 'docs/release/CLOUDFLARE_PLATFORM_ACCEPTANCE.json'))
    blockers = []
    try:
        evidence = read_json(path)
        if evidence.get('backend') != 'cloudflare' or evidence.get('status') != 'pass' or evidence.get('fixture') is True:
            blockers.append('hosted_acceptance_not_passed')
        expires = datetime.fromisoformat(evidence.get('expires_at', '').replace('Z', '+00:00'))
        if expires.tzinfo is None or expires <= datetime.now(timezone.utc):
            blockers.append('hosted_acceptance_expired')
        if evidence.get('source_manifest_sha256') != manifest_sha(source_manifest(root)):
            blockers.append('hosted_acceptance_source_changed')
        checks = evidence.get('checks', {})
        for name in REQUIRED_HOSTED_CHECKS:
            check = checks.get(name, {})
            reference = check.get('evidence', {})
            reference_path = Path(reference.get('path', ''))
            if not reference_path.is_absolute():
                reference_path = path.parent / reference_path
            if (check.get('status') != 'pass' or not reference.get('path') or reference_path.is_symlink()
                    or not reference_path.is_file() or sha(reference_path) != reference.get('sha256')):
                blockers.append(name)
    except (OSError, ValueError, TypeError, AttributeError):
        blockers.append('hosted_acceptance_missing_or_invalid')
    return {'backend': 'cloudflare', 'scope_classification': 'historical_cloudflare_only',
            'current_supabase_release_accepted': False, 'status': 'blocked' if blockers else 'pass',
            'decision': 'NO-GO' if blockers else 'GO', 'blocker_keys': sorted(set(blockers)),
            'evidence_path': str(path),
            'scope': 'Current source/hash/expiry and supplied acceptance record validation; no hosted or provider execution by this gate'}

def current_hosted_acceptance():
    # No current hosted receipt contract is accepted by this source cleanup.
    # A separate owner-reviewed Supabase contract must retain all five controls.
    return {'backend': 'supabase', 'status': 'blocked', 'decision': 'NO-GO',
            'blocker_keys': ['current_supabase_hosted_acceptance_pending'],
            'required_checks': list(REQUIRED_HOSTED_CHECKS),
            'scope': 'Current Supabase hosted acceptance is pending; no legacy or local pass substitutes for it'}


def bundle_path():
    explicit = os.environ.get('RELEASE_EVIDENCE_BUNDLE_DIR') or os.environ.get('QA_UAT_BUNDLE_DIR')
    if explicit:
        return Path(explicit)
    candidates = sorted((ROOT / '.cache/repo_wide_qa_uat').glob('*/summary.json'))
    return candidates[-1].parent if candidates else ROOT / '.cache/repo_wide_qa_uat/missing'

def index(bundle):
    failures = list(current_hosted_acceptance()['blocker_keys'])
    try:
        summary = read_json(bundle / 'summary.json')
        if summary.get('backend') != 'supabase':
            failures.append('current_backend_not_supabase')
        if summary.get('fixture') is True or summary.get('source_sha256') != source_manifest():
            failures.append('source_changed_or_fixture')
        commands = summary.get('commands', {})
        for name, _ in REQUIRED_COMMANDS:
            item = commands.get(name, {})
            log = bundle / item.get('file', '')
            if not log.resolve().is_relative_to(bundle.resolve()) or not log.is_file() or log.is_symlink() or sha(log) != item.get('sha256'):
                failures.append(name + '_evidence_missing_or_changed')
            if item.get('status') != 'pass' or item.get('exit_code') != 0:
                failures.append(name)
        if summary.get('status') != 'pass' or summary.get('release_status', {}).get('decision') != 'GO':
            failures.append('release_not_approved')
    except (OSError, ValueError, TypeError, AttributeError):
        failures.append('release_bundle_missing_or_invalid')
    return {'backend': 'supabase', 'status': 'blocked' if failures else 'pass', 'decision': 'NO-GO' if failures else 'GO',
            'bundle_dir': str(bundle), 'blocker_keys': sorted(set(failures)),
            'scope': 'Hash-bound current commands and separately approved hosted/device/provider/artifact evidence'}

def run(bundle):
    if bundle.exists():
        raise ValueError('Evidence output must be a new directory')
    before = source_manifest()
    bundle.mkdir(parents=True)
    commands = {}
    for name, command in REQUIRED_COMMANDS:
        log = bundle / (name + '.txt')
        with log.open('wb') as handle:
            result = subprocess.run(command, cwd=ROOT, stdout=handle, stderr=subprocess.STDOUT, check=False)
        commands[name] = {'file': log.name, 'sha256': sha(log), 'exit_code': result.returncode,
                          'status': 'pass' if result.returncode == 0 else 'blocked' if result.returncode == 99 else 'fail'}
    status_call = subprocess.run(['bash', 'scripts/release_status.sh', '--json'], cwd=ROOT, capture_output=True, text=True, check=False)
    try:
        release = json.loads(status_call.stdout) if status_call.returncode == 0 else {}
    except ValueError:
        release = {}
    failed = [name for name, value in commands.items() if value['status'] != 'pass']
    failed.extend(current_hosted_acceptance()['blocker_keys'])
    if source_manifest() != before:
        failed.append('source_changed_during_checks')
    if release.get('decision') != 'GO' or release.get('blocker_keys'):
        failed.append('release_status')
    summary = {'generated_at': datetime.now(timezone.utc).isoformat(), 'backend': 'supabase',
               'status': 'blocked' if failed else 'pass', 'decision': 'NO-GO' if failed else 'GO',
               'blocker_keys': failed, 'commands': commands, 'source_sha256': before, 'release_status': release}
    (bundle / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    result = index(bundle)
    (bundle / 'evidence_index.json').write_text(json.dumps(result, indent=2) + '\n')
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('run', 'index', 'packet', 'platform', 'current-platform', 'source-identity'))
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    try:
        if args.mode == 'source-identity':
            result = {'source_manifest_sha256': manifest_sha(source_manifest())}
        elif args.mode == 'platform':
            result = hosted_acceptance()
        elif args.mode == 'current-platform':
            result = current_hosted_acceptance()
        elif args.mode == 'run':
            selected = os.environ.get('QA_UAT_BUNDLE_DIR')
            bundle = Path(selected) if selected else ROOT / '.cache/repo_wide_qa_uat' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
            result = run(bundle)
        else:
            result = index(bundle_path())
            if args.mode == 'packet':
                result['required_approvals'] = ['product_signoff', 'android_sms_access_uat', 'android_release_signing_review', 'ios_release_scope', 'release_owner_signoff']
                result['required_final_commands'] = ['make repo-wide-qa-uat', 'make release-evidence-index-json', 'make release-status-json', 'make release-go-preflight']
        if args.json or args.mode in ('platform', 'current-platform', 'source-identity'):
            print(json.dumps(result, indent=2))
        else:
            print('Release evidence: ' + result['status'])
            for key in result.get('blocker_keys', []):
                print('- ' + key)
        return 0 if result.get('status', 'pass') == 'pass' else 99
    except (OSError, ValueError, subprocess.SubprocessError):
        print(json.dumps({'status': 'blocked', 'blocker_keys': ['release_evidence_input_or_execution_error']}))
        return 99

if __name__ == '__main__':
    raise SystemExit(main())

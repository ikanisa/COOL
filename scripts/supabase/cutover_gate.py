"""Validate source-bound supplied migration acceptance; never changes routing."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import subprocess
import sys

PROJECT = 'rrlduytparvsjfmegalh'
REQUIRED = ('schema', 'handlers', 'data', 'objects', 'authentication', 'authorization',
            'financial', 'providers', 'native', 'ai', 'privacy', 'recovery', 'operations', 'clients')
SOURCE_PATHS = ('supabase', 'scripts', 'tools', 'lib', 'deploy', 'android', 'ios', 'web', 'test',
                'integration_test', 'third_party', '.github', 'pubspec.yaml', 'pubspec.lock',
                'Makefile', '.fvmrc', '.env.example', 'AGENTS.md')
IGNORED = {'node_modules', '.cache', 'build', '.dart_tool', '.gradle', 'Pods', '.symlinks', '__pycache__', '.wrangler'}

def source_identity(root):
    names = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', *SOURCE_PATHS], cwd=root).decode().split('\0')
    manifest = {}
    for name in sorted(set(names)):
        if not name or any(x in IGNORED or x.startswith('._') for x in Path(name).parts):
            continue
        path = root / name
        if not path.exists():
            continue
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError('nonregular_source')
        manifest[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    if not manifest or not any(n.startswith('supabase/migrations/') for n in manifest):
        raise ValueError('missing_supabase_source')
    return hashlib.sha256(json.dumps(manifest, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

def read_record(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 4 * 1024 * 1024:
        raise ValueError('invalid_evidence_file')
    def unique(pairs):
        result = {}
        for k, v in pairs:
            if k in result:
                raise ValueError('duplicate_evidence_key')
            result[k] = v
        return result
    value = json.loads(path.read_text(), object_pairs_hook=unique)
    if not isinstance(value, dict):
        raise ValueError('invalid_evidence_record')
    return value

def acceptance(record_path, source_sha256, now=None):
    now = now or datetime.now(timezone.utc)
    blockers = []
    try:
        record = read_record(record_path)
        if record.get('project_ref') != PROJECT or record.get('backend') != 'supabase':
            blockers.append('wrong_backend_or_project')
        if record.get('fixture') is not False or record.get('status') != 'pass':
            blockers.append('nonproduction_or_unaccepted_evidence')
        if record.get('source_sha256') != source_sha256:
            blockers.append('source_changed')
        expiry = datetime.fromisoformat(record.get('expires_at', '').replace('Z', '+00:00'))
        if expiry.tzinfo is None or expiry <= now:
            blockers.append('evidence_expired')
        if record.get('data_mismatches') != 0 or record.get('object_mismatches') != 0:
            blockers.append('unreconciled_data_or_objects')
        if record.get('writer_authority') != 'supabase_only':
            blockers.append('single_writer_not_proven')
        if record.get('recovery_strategy') not in ('tested_reverse_delta', 'accepted_tested_forward_only'):
            blockers.append('postwrite_recovery_not_accepted')
        checks = record.get('checks', {})
        for name in REQUIRED:
            check = checks.get(name, {})
            ref = check.get('evidence', {})
            path = Path(ref.get('path', ''))
            if not path.is_absolute():
                path = record_path.parent / path
            if (check.get('status') != 'pass' or check.get('fixture') is not False
                    or not ref.get('path') or path.is_symlink() or not path.is_file()
                    or hashlib.sha256(path.read_bytes()).hexdigest() != ref.get('sha256')):
                blockers.append(name + '_unverified')
        owner = record.get('release_owner', {})
        if owner.get('decision') != 'approve' or not owner.get('identity') or owner.get('source_sha256') != source_sha256:
            blockers.append('release_owner_not_approved')
    except (OSError, ValueError, TypeError, AttributeError):
        blockers.append('missing_or_invalid_acceptance')
    return {'backend': 'supabase', 'project_ref': PROJECT, 'decision': 'NO-GO' if blockers else 'GO',
            'blockers': sorted(set(blockers)), 'routing_changed': False,
            'scope': 'Verifies supplied evidence hashes and current source; does not execute hosted/device/provider checks'}

def main():
    root = Path(__file__).resolve().parents[2]
    if len(sys.argv) == 2 and sys.argv[1] == 'source-identity':
        print(json.dumps({'source_sha256': source_identity(root)}))
        return 0
    if len(sys.argv) != 2:
        raise ValueError('supply_acceptance_path_or_source_identity')
    result = acceptance(Path(sys.argv[1]), source_identity(root))
    print(json.dumps(result, indent=2))
    return 0 if result['decision'] == 'GO' else 1

if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError):
        print(json.dumps({'decision': 'NO-GO', 'blockers': ['source_or_arguments_invalid'], 'routing_changed': False}))
        sys.exit(1)

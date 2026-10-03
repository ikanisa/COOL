"""Run only existing Automations/PWA cases in the source06-derived work copy."""
import sys
sys.dont_write_bytecode = True

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[5]
TESTS = ('test/admin_automations_test.dart', 'test/admin_pwa_test.dart')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--workspace', required=True, type=Path)
    parser.add_argument('--manifest-sha256', required=True)
    parser.add_argument('--packet', required=True, type=Path)
    args = parser.parse_args()
    candidate, work, packet = args.candidate.resolve(), args.workspace.resolve(), args.packet.resolve()
    if work == ROOT or ROOT in work.parents or candidate == work or candidate in work.parents:
        raise RuntimeError('Regression workspace must be an isolated derived copy.')
    packet.mkdir(parents=True, exist_ok=True)
    tools = {'regression_runner': Path(__file__).resolve(),
             'source_exporter': ROOT / 'scripts/qa/collect_release_candidate.py'}
    tool_bytes = {name: path.read_bytes() for name, path in tools.items()}
    tool_hashes = {name: hashlib.sha256(raw).hexdigest() for name, raw in tool_bytes.items()}
    for name, raw in tool_bytes.items():
        (packet / (name + '-used.py')).write_bytes(raw)
    (packet / 'regression-tool-provenance-before.json').write_text(json.dumps(tool_hashes, indent=2) + '\n')
    spec = importlib.util.spec_from_file_location('collect_regression_candidate', tools['source_exporter'])
    exporter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(exporter)
    source = exporter.verify_candidate(candidate, expected_manifest_sha256=args.manifest_sha256)
    if source['status'] != 'pass':
        raise exporter.ReleaseError('CANDIDATE_READBACK_REQUIRED')
    manifest_raw, _ = exporter.regular_bytes(work, exporter.MANIFEST)
    if exporter.sha(manifest_raw) != args.manifest_sha256:
        raise exporter.ReleaseError('CANDIDATE_MANIFEST_HASH_CHANGED')
    manifest = json.loads(manifest_raw)

    def source_binding():
        observed = {}
        for name, expected in manifest['source_files'].items():
            raw, mode = exporter.regular_bytes(work, name)
            actual = {'sha256': exporter.sha(raw), 'bytes': len(raw), 'mode': mode}
            if actual != expected:
                raise exporter.ReleaseError('CANDIDATE_BUILD_SOURCE_CHANGED', [name])
            observed[name] = actual
        return exporter.sha(exporter.canonical(observed))

    before = source_binding()
    sdk = Path(manifest['toolchain']['flutter']['sdk_path'])
    metadata = json.loads((sdk / 'bin/cache/flutter.version.json').read_text())
    if (metadata['frameworkVersion'] != manifest['toolchain']['flutter']['pin']
            or metadata['frameworkRevision'] != manifest['toolchain']['flutter']['framework_revision']
            or exporter.sha((sdk / 'bin/flutter').read_bytes()) != manifest['toolchain']['flutter']['launcher_sha256']):
        raise exporter.ReleaseError('CANDIDATE_FLUTTER_PIN_MISMATCH')
    configuration = work / '.dart_tool/package_config.json'
    package_hash = exporter.sha(configuration.read_bytes())
    command = [str(sdk / 'bin/flutter'), 'test', '--no-pub', '--reporter', 'expanded', *TESTS]
    environment = {name: os.environ[name] for name in ('PATH', 'HOME', 'TMPDIR', 'LANG', 'LC_ALL') if name in os.environ}
    environment.update({'PUB_CACHE': str(ROOT / '.cache/pub-cache-hygiene-20260930'),
                        'FLUTTER_SUPPRESS_ANALYTICS': 'true', 'CI': 'true'})
    started = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    try:
        result = subprocess.run(command, cwd=work, env=environment, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=240, check=False)
    except subprocess.TimeoutExpired as error:
        result = subprocess.CompletedProcess(command, 124, (error.stdout or b'') + b'\nBounded regression timeout.\n')
    exporter.screen_credentials(result.stdout, 'admin06-scoped-regression.log')
    packet.mkdir(parents=True, exist_ok=True)
    (packet / 'admin06-scoped-regression.log').write_bytes(result.stdout)
    after = source_binding()
    if package_hash != exporter.sha(configuration.read_bytes()):
        raise exporter.ReleaseError('CANDIDATE_PACKAGE_BINDING_CHANGED')
    final = exporter.verify_candidate(candidate, expected_manifest_sha256=args.manifest_sha256)
    if final['status'] != 'pass':
        raise exporter.ReleaseError('CANDIDATE_READBACK_REQUIRED')
    tools_after = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in tools.items()}
    tool_stable = tools_after == tool_hashes
    completion = b'All tests passed!' in result.stdout
    passed = result.returncode == 0 and completion and tool_stable
    receipt = {
        'status': 'pass' if passed else 'failed_or_incomplete', 'command': command,
        'exit_code': result.returncode, 'started_at_utc': started,
        'completion_marker': completion,
        'finished_at_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'workspace': str(work), 'candidate': str(candidate),
        'candidate_manifest_sha256': args.manifest_sha256,
        'test_inputs': {name: manifest['source_files'][name] for name in TESTS},
        'all_selected_inputs_before_sha256': before, 'all_selected_inputs_after_sha256': after,
        'all_selected_source_files_unchanged': before == after,
        'six_lock_inputs': manifest['toolchain']['lock_sha256'],
        'package_config_sha256': package_hash, 'pinned_flutter': manifest['toolchain']['flutter'],
        'pristine_candidate_final_readback': final,
        'log_sha256': exporter.sha(result.stdout),
        'tool_hashes_before': tool_hashes, 'tool_hashes_after': tools_after,
        'tool_bytes_unchanged': tool_stable,
        'new_tests_added': 0, 'otp_requests': 0, 'provider_sends': 0, 'hosted_mutations': 0,
        'whole_source_acceptance': False, 'production_ready': False,
        'scope': 'Only existing Automations/PWA regression in the exact source06-derived copy; '
                 'policy/audit/link checks remain separate scopes.',
    }
    (packet / 'admin06-scoped-regression.result.json').write_bytes(exporter.canonical(receipt))
    print(json.dumps({name: receipt[name] for name in ('status', 'exit_code', 'candidate_manifest_sha256', 'all_selected_source_files_unchanged', 'production_ready')}))
    return 0 if passed else 2


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        report = {'status': 'blocked', 'reason_code': getattr(error, 'code', 'ADMIN_REGRESSION_FAILED'),
                  'affected_source_paths': getattr(error, 'paths', []), 'credential_values_reported': False,
                  'production_ready': False}
        Path(__file__).with_name('admin06-scoped-regression-blocked.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report))
        raise SystemExit(2)

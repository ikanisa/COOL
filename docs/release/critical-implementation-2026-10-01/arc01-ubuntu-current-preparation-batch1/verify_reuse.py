#!/usr/bin/env python3
"""Read back exact valid task-owned dependencies; do not bootstrap or format."""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

OUT = Path(__file__).resolve().parent
BOUNDARY = json.loads((OUT / 'preparation-attempt1/private-boundary.json').read_text())
PRIOR = Path(BOUNDARY['prior_sealed_packet'])
CURRENT = json.loads((OUT / 'source-export-attempt1/source-inventory.json').read_text())
PREVIOUS = json.loads((PRIOR / 'source-export-attempt1/source-inventory.json').read_text())
PUB = json.loads((PRIOR / 'pub-bootstrap-attempt1/result.json').read_text())
SDK = Path(BOUNDARY['reusable_authenticated_runtime_root']) / 'flutter'
SDK_EXPECTED = json.loads((PRIOR / 'sdk-extraction-attempt1/result.json').read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


actual_sdk = {path: sha(SDK / path) for path in SDK_EXPECTED['sdk_file_sha256']}
revision = subprocess.check_output(['git', '-C', str(SDK), 'rev-parse', 'HEAD'], timeout=15).decode().strip()
dependencies = set(PREVIOUS['local_dependency_input_paths']) | {'.fvmrc', 'pubspec.yaml', 'pubspec.lock'}
drift = {path: {'previous': PREVIOUS['copied_input_sha256'].get(path),
               'new': CURRENT['copied_input_sha256'].get(path)} for path in sorted(dependencies)
         if PREVIOUS['copied_input_sha256'].get(path) != CURRENT['copied_input_sha256'].get(path)}
new_dependencies = sorted(set(CURRENT['local_dependency_input_paths']) - set(PREVIOUS['local_dependency_input_paths']))
old_private = Path(json.loads((PRIOR / 'preparation-attempt1/private-boundary.json').read_text())['private_root'])
actual_config = sha(old_private / 'checkout/.dart_tool/package_config.json')
cache_receipt = OUT / 'reusable-private-pub-cache-readback.json'
cache = json.loads(cache_receipt.read_text())
eligible = (actual_sdk == SDK_EXPECTED['sdk_file_sha256']
            and revision == SDK_EXPECTED['sdk_git_revision']
            and not drift and not new_dependencies
            and actual_config == PUB['package_config_sha256'])
new_checkout = Path(BOUNDARY['private_root']) / 'checkout'
receipt = {
    'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'status': 'CURRENT_SOURCE_PREPARED_FINAL_CAPTURE_AND_MAKE_HELD',
    'reuse_eligible_for_exact_existing_sdk_and_canonical_pub_inputs': eligible,
    'SDK_expected_sha256': SDK_EXPECTED['sdk_file_sha256'], 'SDK_current_sha256': actual_sdk,
    'SDK_expected_git_revision': SDK_EXPECTED['sdk_git_revision'], 'SDK_current_git_revision': revision,
    'SDK_scripts_executed_again': False,
    'prior_canonical_pub_result_sha256': sha(PRIOR / 'pub-bootstrap-attempt1/result.json'),
    'actual_existing_generated_package_config_sha256': actual_config,
    'expected_existing_generated_package_config_sha256': PUB['package_config_sha256'],
    'dependency_input_paths_compared': len(dependencies), 'dependency_input_drift': drift,
    'new_local_dependency_input_paths': new_dependencies,
    'private_pub_cache_file_count': len(cache['files_sha256']),
    'private_pub_cache_link_count': len(cache['links']),
    'private_pub_cache_readback_sha256': sha(cache_receipt),
    'source_inputs': len(CURRENT['copied_input_sha256']),
    'applicable_dart_count': len(CURRENT['applicable_formatter_paths']),
    'capture_at_utc': CURRENT['at_utc'],
    'captured_default_route_test_sha256': CURRENT['copied_input_sha256'].get('test/features/privacy/privacy_default_route_integration_test.dart'),
    'new_current_checkout_has_no_Git_yet': not (new_checkout / '.git').exists(),
    'new_current_checkout_has_no_generated_package_config': not (new_checkout / '.dart_tool/package_config.json').exists(),
    'reused_generated_package_config_copied': False, 'canonical_pub_repeated': False,
    'make_executed': False, 'root_or_private_source_formatted': False, 'current_root_acceptance': False,
    'hold': 'Parent requires final default-route test source freeze and safe other-chat owner integration of3 real formatter gaps before final capture/Make.',
}
(OUT / 'reuse-eligibility-and-hold.json').write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
print(json.dumps({key: receipt[key] for key in ['reuse_eligible_for_exact_existing_sdk_and_canonical_pub_inputs',
      'dependency_input_paths_compared', 'private_pub_cache_file_count', 'private_pub_cache_link_count',
      'source_inputs', 'applicable_dart_count', 'capture_at_utc', 'captured_default_route_test_sha256',
      'make_executed']}, indent=2))

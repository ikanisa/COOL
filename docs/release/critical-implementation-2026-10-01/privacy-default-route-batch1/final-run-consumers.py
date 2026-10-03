#!/usr/bin/env python3
"""Capture focused maintained consumers without changing their source or gates."""
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
FLUTTER = Path('/Volumes/PRO-G40/Development/Flutter/flutter')
TESTS = [
    'test/features/privacy/privacy_default_route_integration_test.dart',
    'test/features/privacy/privacy_request_screen_test.dart',
    'test/features/privacy/privacy_logout_integration_test.dart',
    'test/shared/repository_session_fencing_test.dart',
    'test/features/auth_route_accessibility_regression_test.dart',
    'test/core/route_inventory_contract_test.dart',
    'test/connection_recovery_screen_test.dart',
    'test/connection_recovery_screens_test.dart',
    'test/features/shared_chrome_accessibility_test.dart',
    'test/features/member_data_unknown_states_test.dart',
]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def identities():
    files = list(ROOT.joinpath('lib').rglob('*.dart'))
    files += list(ROOT.joinpath('test/fixtures').rglob('*.dart'))
    files += [ROOT / t for t in TESTS]
    files += [ROOT / 'test/features/mobile_completion_test.dart',
              ROOT / 'test/features/security_hub_header_test.dart',
              ROOT / 'test/features/privacy/privacy_test_support.dart',
              ROOT / 'pubspec.yaml', ROOT / 'pubspec.lock',
              ROOT / '.dart_tool/package_config.json', ROOT / 'analysis_options.yaml',
              ROOT / 'content/product/collect_capabilities.json',
              ROOT / 'docs/release/public-website-current-content-contract.json',
              ROOT / 'AGENTS.md', ROOT / 'Makefile',
              ROOT / 'scripts/qa/revolut_design_authority.py',
              ROOT / 'docs/release/revolut-design/authority.json',
              Path(__file__).resolve()]
    files += list(ROOT.joinpath('assets/typefaces').rglob('*'))
    files += [FLUTTER / p for p in [
        'bin/flutter', 'bin/cache/dart-sdk/bin/dart',
        'bin/cache/flutter_tools.snapshot',
        'bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot',
        'bin/cache/artifacts/engine/darwin-x64/flutter_tester',
        'bin/cache/artifacts/engine/common/flutter_patched_sdk/platform_strong.dill',
        'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        'packages/flutter/pubspec.yaml', 'packages/flutter_test/pubspec.yaml',
    ]]
    files += list(FLUTTER.joinpath('packages/flutter/lib').rglob('*.dart'))
    files += list(FLUTTER.joinpath('packages/flutter_test/lib').rglob('*.dart'))
    skill = Path('/Volumes/PRO-G40/Application Data/Codex/Codex-Home/skills/revolut-design')
    files += [skill / 'SKILL.md'] + list(skill.joinpath('references').rglob('*.md'))
    config = json.loads((ROOT / '.dart_tool/package_config.json').read_text())
    selected = {'supabase_flutter', 'supabase', 'gotrue', 'postgrest', 'realtime_client',
                'riverpod', 'state_notifier', 'flutter_riverpod', 'go_router', 'http'}
    for package in config['packages']:
        if package['name'] in selected:
            uri = package['rootUri']
            location = Path(unquote(urlparse(uri).path)) if uri.startswith('file:') else (ROOT / '.dart_tool' / uri).resolve()
            files += list(location.joinpath('lib').rglob('*.dart'))
            files += [location / 'pubspec.yaml']
    result = {}
    for path in sorted(set(files)):
        if path.is_dir():
            continue
        if not path.is_file():
            raise FileNotFoundError(path)
        result[str(path)] = digest(path)
    return result

mode, attempt = sys.argv[1:3]
destination = PACKET / attempt
destination.mkdir(exist_ok=False)
if mode == 'analyzer':
    command = [str(FLUTTER / 'bin/flutter'), 'analyze', '--no-pub',
               'lib/app/router.dart', 'lib/shared/repositories/collect_repository.dart',
               'lib/shared/widgets/screen_scaffold.dart', 'lib/features/privacy',
               'lib/features/settings/security_hub_header.dart',
               'test/features/privacy', 'test/shared/repository_session_fencing_test.dart',
               'test/features/auth_route_accessibility_regression_test.dart',
               'test/core/route_inventory_contract_test.dart']
elif mode == 'cohort':
    command = [str(FLUTTER / 'bin/flutter'), 'test', '--no-pub', '--reporter', 'expanded', *TESTS]
elif mode == 'affected_security':
    command = [str(FLUTTER / 'bin/flutter'), 'test', '--no-pub', '--reporter', 'expanded',
               'test/features/shared_chrome_accessibility_test.dart',
               'test/features/security_hub_header_test.dart',
               'test/features/privacy/privacy_default_route_integration_test.dart']
elif mode == 'stale_home':
    command = [str(FLUTTER / 'bin/flutter'), 'test', '--no-pub', '--reporter', 'expanded',
               'test/features/mobile_completion_test.dart', '--plain-name',
               'home labels restored cache as offline saved data']
elif mode == 'authority':
    command = ['make', 'revolut-design-authority']
else:
    raise ValueError(mode)
before = identities()
(destination / 'sources-before.json').write_text(json.dumps(before, indent=2) + '\n')
start = datetime.now(timezone.utc).isoformat()
with (destination / 'actual.log').open('wb') as log:
    process = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
after = identities()
(destination / 'sources-after.json').write_text(json.dumps(after, indent=2) + '\n')
receipt = {'started_at': start, 'completed_at': datetime.now(timezone.utc).isoformat(),
           'mode': mode, 'command': command, 'exit_code': process.returncode,
           'input_count': len(before), 'source_before_after_equal': before == after,
           'changed_inputs': [p for p in sorted(set(before) | set(after)) if before.get(p) != after.get(p)],
           'actual_log_sha256': digest(destination / 'actual.log'),
           'approval': False, 'authority_hygiene_is_visual_acceptance': False}
(destination / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt))
print((destination / 'actual.log').read_text()[-2200:])

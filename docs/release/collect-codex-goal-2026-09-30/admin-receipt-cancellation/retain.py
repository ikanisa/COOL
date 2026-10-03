"""Retain this bounded source/evidence set; never exports a release candidate."""
from pathlib import Path
import datetime
import hashlib
import json

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent

paths = set()
for pattern in (
    'lib/admin/core/admin_receipt_cancel*.dart',
    'test/admin_receipt_cancel*_test.dart',
    'contracts/collect-safe-receipt-action-v1*',
    'lib/app/theme/*.dart',
    'docs/release/collect-codex-goal-2026-09-30/safe-receipt-actions/backend-uat/observed-*.json',
):
    paths.update(ROOT.glob(pattern))
for relative in (
    'lib/admin/core/admin_investigation_view.dart',
    'lib/admin/core/admin_repository_base.dart',
    'lib/admin/core/admin_runtime.dart',
    'lib/admin/shared/components/admin_status_chip.dart',
    'lib/admin/core/admin_display_formatters.dart',
    'lib/admin/admin_shell.dart',
    'test/admin_action_session_test.dart',
    'test/admin_investigation_view_test.dart',
    'test/fixtures/admin_investigation_v1.json',
    'supabase/migrations/20261001000519_safe_unstarted_receipt_cancel.sql',
    'pubspec.lock',
    'pubspec.yaml',
):
    paths.add(ROOT / relative)

existing = PACKET / 'source-manifest.json'
if existing.exists():
    old = json.loads(existing.read_text())
    expected = {row['path']: row['sha256'] for row in old['files']}
    current = {source.relative_to(ROOT).as_posix():
               hashlib.sha256(source.read_bytes()).hexdigest()
               for source in paths}
    if current != expected:
        raise RuntimeError('Retained source differs. Use a new evidence packet; '
                           'do not overwrite this binding.')

rows = []
for source in sorted(paths):
    relative = source.relative_to(ROOT)
    original = source.read_bytes()
    digest = hashlib.sha256(original).hexdigest()
    target = PACKET / 'source' / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(original)
    if (hashlib.sha256(source.read_bytes()).hexdigest() != digest
            or hashlib.sha256(target.read_bytes()).hexdigest() != digest):
        raise RuntimeError(f'Source changed or readback failed: {relative}')
    rows.append({
        'path': relative.as_posix(), 'sha256': digest, 'bytes': len(original),
        'copy_path': target.relative_to(PACKET).as_posix(),
        'source_mtime_utc': datetime.datetime.fromtimestamp(
            source.stat().st_mtime, datetime.timezone.utc).isoformat(),
    })

manifest = {
    'captured_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'mode': 'scoped_current_source_binding',
    'whole_checkout_atomic_freeze': False,
    'complete_compilation_dependency_closure': False,
    'reviewed_production_freeze': False,
    'capture_readback': 'pass', 'files': rows,
    'context': 'Cancellation implementation and current shared integration, '
               'test helpers, product adapters, sealed contract/SQL and actual '
               'retained fixtures. Source05 does not contain this UI.',
}
(PACKET / 'source-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')

validation = {
    'scoped_vm_tests': {
        'status': 'pass', 'passed': 94, 'failed': 0,
        'files': {'models': 30, 'sdk': 9, 'card': 36, 'existing_investigation': 19},
        'raw_log': 'scoped-tests-final.log',
    },
    'isolated_chrome_storage': {
        'status': 'pass', 'passed': 1, 'failed': 0,
        'raw_log': 'browser-storage.log', 'full_reload_real_auth_e2e': False,
    },
    'analysis': {'status': 'pass', 'files': 13, 'issues': 0,
                 'raw_log': 'analysis-final.log'},
    'sole_design_authority': {'status': 'pass', 'raw_log': 'design-authority-final.log',
                              'visual_fidelity_certified': False},
    'capture_inspection': {
        'status': 'inspected', 'synthetic': True,
        'files': ['receipt-cancellation-dark-synthetic.png',
                  'receipt-cancellation-light-synthetic.png'],
        'desktop_pixels': [1440, 2200], 'bundled_fonts_and_logo': True,
        'visible_desktop_overflow': False,
        'actual_state': 'Independent cancellation eligibility; joined investigation unavailable',
    },
    'accessibility_responsive': {
        'dark_light_320px_2x_text_widget_tests': 'pass',
        'explicit_reason_dialog': 'pass', 'keyboard_escape': 'pass',
        'deployed_screen_reader': 'unverified',
    },
    'backend_scoped_cases': {
        'passed': 147, 'packet': '../safe-receipt-actions/README.md',
        'backend_reexecuted_by_ui_slice': False,
        'whole_hosted_chain_acceptance': False,
    },
    'auth_persistence': {
        'persistSession': False, 'storage': 'EmptyLocalStorage',
        'checkpoint': 'owner/project/purpose-bound sessionStorage only',
        'real_email_sign_in_after_browser_reload': 'unverified',
    },
    'reviewed_production_freeze': False, 'whole_C13_C23_acceptance': False,
    'source05_contains_slice': False,
    'failed_attempts_preserved': [
        'analysis-attempt1.log', 'analysis-attempt2.log', 'analysis-attempt3.log',
        'tests-attempt1.log', 'card-attempt2.log', 'scoped-tests-attempt3.log',
        'scoped-tests-attempt4.log',
    ],
}
assert 'All tests passed!' in (PACKET / validation['scoped_vm_tests']['raw_log']).read_text()
assert 'All tests passed!' in (PACKET / validation['isolated_chrome_storage']['raw_log']).read_text()
assert 'No issues found!' in (PACKET / validation['analysis']['raw_log']).read_text()
assert '[revolut-design-authority] pass' in (PACKET / 'design-authority-final.log').read_text()
(PACKET / 'validation.json').write_text(json.dumps(validation, indent=2) + '\n')

retained = [p for p in sorted(PACKET.rglob('*'))
            if p.is_file() and p.name != 'MANIFEST.sha256'
            and '__pycache__' not in p.parts]
(PACKET / 'MANIFEST.sha256').write_text(''.join(
    f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(PACKET).as_posix()}\n'
    for p in retained
))
print('Scoped source/readback files:', len(rows))
print('Retained packet files:', len(retained))
print('MANIFEST SHA256:', hashlib.sha256((PACKET / 'MANIFEST.sha256').read_bytes()).hexdigest())

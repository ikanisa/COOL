#!/usr/bin/env python3
"""Local-only source-bound Dart/UI/SQL-output decoder checks; no service calls."""
from pathlib import Path
import datetime, hashlib, json, subprocess
ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
FLUTTER = '/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter'
SOURCES = [
 'lib/admin/core/admin_roster_import.dart', 'lib/admin/core/admin_roster_models.dart',
 'lib/admin/core/admin_roster_dialog.dart', 'test/admin_roster_import_test.dart',
 'test/admin_roster_dialog_test.dart', 'test/admin_roster_sql_receipts_test.dart',
 'test/support/admin_roster_fixture.dart', 'lib/admin/core/roster_file_parser.dart',
 'lib/admin/core/roster_xlsx_preflight.dart', 'test/admin_roster_file_parser_test.dart',
 'test/admin_roster_xlsx_preflight_test.dart', 'pubspec.yaml', 'pubspec.lock',
 'docs/admin/ROSTER_IMPORT_PROVENANCE_CONTRACT.md',
 'supabase/migrations/20260930100000_roster_import_provenance.sql',
 'docs/release/roster-import-provenance-2026-09-30/receipts142.stdout',
 'assets/typefaces/Inter-Variable.ttf', 'assets/typefaces/AeonikPro-Regular.ttf',
 'lib/app/theme/collect_theme.dart', 'lib/app/theme/collect_typography.dart',
 'lib/app/theme/collect_spacing.dart', 'lib/app/theme/collect_motion.dart',
 'lib/shared/widgets/collect_state_panels.dart',
]
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def snapshot(): return {p: digest(ROOT / p) for p in SOURCES}
result = {'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'source_hashes_before': snapshot(), 'commands': [],
 'database_calls': False, 'provider_calls': False, 'hosted_calls': False,
 'sql_input': 'Root-executed rollback fixture stdout; read from disk only.'}
commands = [
 ('runtime', [FLUTTER, '--version', '--machine']),
 ('recovery-tests', [FLUTTER, 'test', '--no-pub', '--reporter', 'expanded',
  '--dart-define=ROSTER_SQL_RECEIPTS='+str(ROOT/'docs/release/roster-import-provenance-2026-09-30/receipts142.stdout'),
  '--dart-define=CAPTURE_ROSTER_RECOVERY_EVIDENCE=true', '--update-goldens',
  'test/admin_roster_import_test.dart', 'test/admin_roster_dialog_test.dart',
  'test/admin_roster_sql_receipts_test.dart']),
 ('xlsx-regression', [FLUTTER, 'test', '--no-pub', '--reporter', 'expanded',
  'test/admin_roster_file_parser_test.dart', 'test/admin_roster_xlsx_preflight_test.dart']),
 ('analyze', [FLUTTER, 'analyze', '--no-pub', *SOURCES[:6]]),
]
for name, argv in commands:
 with (OUT/(name+'.stdout')).open('w') as stdout, (OUT/(name+'.stderr')).open('w') as stderr:
  completed = subprocess.run(argv, cwd=ROOT, stdout=stdout, stderr=stderr)
 result['commands'].append({'name':name, 'argv':argv, 'exit_code':completed.returncode,
  'stdout_sha256':digest(OUT/(name+'.stdout')), 'stderr_sha256':digest(OUT/(name+'.stderr'))})
 print(name, completed.returncode, flush=True)
 if completed.returncode: break
result['source_hashes_after'] = snapshot()
result['source_unchanged'] = result['source_hashes_before'] == result['source_hashes_after']
result['completed_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
result['passed'] = len(result['commands']) == len(commands) and all(c['exit_code']==0 for c in result['commands']) and result['source_unchanged']
(OUT/'validation.json').write_text(json.dumps(result, indent=2)+'\n')
raise SystemExit(0 if result['passed'] else 1)

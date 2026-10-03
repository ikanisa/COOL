import hashlib
import json
import pathlib
import shutil
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(__file__).resolve().parent
PACKETS = ROOT / '.cache/receipt-successor-workflows-20261001'
BASE = PACKETS / 'accepted-successor-execution-read-admin-current1'
DELTA = PACKETS / 'accepted-successor-execution-access-denial-current1'
BACKEND = PACKETS / 'accepted-successor-execution-read-backend-current1'

def sha(p):
    with p.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

for packet, expected in [(BASE, '7544c5cdd15606e03ce42246fbf227f148d8a6b637025741e4c96498e2924e71'),
                         (DELTA, '19d240d01bc1c13ca9bd40bde9e37d6a26df052d0e06da20fd8dbdc69ae5023a')]:
    assert sha(packet / 'MANIFEST.json') == expected
    members = json.loads((packet / 'MANIFEST.json').read_text())['members']
    assert all(sha(packet / p) == h for p, h in members.items())

verification = json.loads((BASE / 'VERIFICATION.json').read_text())
canonical = verification['canonical_bindings']
assert len(canonical) == 181
assert all(sha(ROOT / p) == h for p, h in canonical.items())
sources = {p: BASE / p for p in verification['source_bindings']}
assert all(sha(p) == verification['source_bindings'][n] for n, p in sources.items())
binding = json.loads((DELTA / 'DELTA_BINDING.json').read_text())
for n, v in binding['modified_product_files'].items():
    assert sha(sources[n]) == v['accepted_predecessor_sha256']
    sources[n] = DELTA / n
    assert sha(sources[n]) == v['corrected_sha256']
for n, h in binding['new_test'].items():
    sources[n] = DELTA / n
    assert sha(sources[n]) == h

sql = 'supabase/migrations/20261002044000_receipt_successor_execution_investigation.sql'
sources[sql] = BACKEND / sql
assert sha(sources[sql]) == 'f082950cbc11766d336e514ebde35c1c3407d32118c5d0faf8ef5d8e27a67230'
assert all(not (ROOT / n).exists() for n in sources)

parent = 'lib/admin/core/admin_receipt_successor_view.dart'
original = (ROOT / parent).read_text()
updated = original.replace("import 'admin_receipt_successor_controller.dart';",
    "import 'admin_receipt_successor_controller.dart';\nimport 'admin_receipt_successor_sdk.dart';\nimport 'admin_receipt_successor_execution_host.dart';\nimport 'admin_receipt_successor_execution_sdk.dart';")
updated = updated.replace('  String? _seenReceipt;', '  String? _seenReceipt;\n  String? _selectedApprovalId;')
updated = updated.replace('old.canRead != widget.canRead)',
    'old.canRead != widget.canRead ||\n        old.canManage != widget.canManage)')
updated = updated.replace('      _history.clear();', '      _history.clear();\n      _selectedApprovalId = null;')
needle = "    } catch (_) {\n      if (mounted && generation == _generation) {\n        setState(() => _error = 'More receipt history could not be loaded.');\n      }"
replacement = """    } catch (failure) {
      if (mounted && generation == _generation) {
        final denied = executionAccessDenied(failure) ||
            failure is AdminReceiptSuccessorRejected &&
                failure.code == '42501';
        setState(() {
          if (denied) {
            _generation++;
            _closure = null;
            _inspection = null;
            _history.clear();
            _selectedApprovalId = null;
            _next = null;
            _historyBusy = false;
          }
          _error = denied
              ? 'Current receipt review access is denied. Refresh after restoring access.'
              : 'More receipt history could not be loaded.';
        });
      }"""
assert updated.count(needle) == 1
updated = updated.replace(needle, replacement)
needle = "                    if (widget.canManage && item.status != 'revoked')"
selector = """                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: () => setState(() {
                          _selectedApprovalId = _selectedApprovalId == item.id
                              ? null
                              : item.id;
                        }),
                        child: Text(
                          _selectedApprovalId == item.id
                              ? 'Close investigation'
                              : 'Investigate execution',
                        ),
                      ),
                    ),
"""
assert updated.count(needle) == 1
updated = updated.replace(needle, selector + needle)
needle = '            if (_next != null)'
detail = """            if (_selectedApprovalId != null &&
                _history.any((item) => item.id == _selectedApprovalId)) ...[
              const SizedBox(height: 16),
              AdminReceiptSuccessorExecutionHost(
                key: ValueKey((widget.outboxId, _selectedApprovalId)),
                approvalId: _selectedApprovalId!,
                primaryReceiptId: widget.outboxId,
              ),
            ],
"""
assert updated.count(needle) == 1
updated = updated.replace(needle, detail + needle)
private = OUT / 'source' / parent
private.parent.mkdir(parents=True, exist_ok=True)
private.write_text(updated)
preserved = OUT / 'originals' / parent
preserved.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(ROOT / parent, preserved)
assert sha(ROOT / parent) == sha(preserved)
before = {str(p.relative_to(ROOT)): sha(p) for p in sorted((ROOT / 'supabase/migrations').glob('*.sql'))}
assert len(before) == 207
sources[parent] = private
association = {n: {'source': str(p.relative_to(ROOT)), 'sha256': sha(p)} for n, p in sources.items()}
(OUT / 'plan.json').write_text(json.dumps(association, indent=2) + '\n')
for n, p in sources.items():
    target = ROOT / n
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(p, target)
assert all(sha(ROOT / n) == d['sha256'] for n, d in association.items())
after = {str(p.relative_to(ROOT)): sha(p) for p in sorted((ROOT / 'supabase/migrations').glob('*.sql'))}
assert len(after) == 208 and all(after[n] == h for n, h in before.items())
assert len({pathlib.Path(n).name.split('_', 1)[0] for n in after}) == 208
result = {'status': 'integrated', 'at': datetime.now(timezone.utc).isoformat(),
          'files': association, 'preserved_originals': {parent: sha(preserved)},
          'previous_migrations': before, 'migration_count': len(after),
          'scope': 'Exact reviewed two-read SQL440 and corrected five-module Admin investigation; one selected approval; canonical caller checks pending; no hosted/device/send acceptance'}
(OUT / 'canonical-source-association.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'status': result['status'], 'integrated_files': len(sources), 'migration_count': len(after)}))

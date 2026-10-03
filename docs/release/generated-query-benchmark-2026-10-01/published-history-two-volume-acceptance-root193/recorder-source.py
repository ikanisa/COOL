#!/usr/bin/env python3
"""Bind two independently completed generated-volume proofs without rewriting failures."""
from pathlib import Path
import hashlib,json,datetime as dt
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');BASE=ROOT/'docs/release/generated-query-benchmark-2026-10-01';OUT=BASE/'published-history-two-volume-acceptance-root193'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
sources=[(1000,BASE/'published-global-history-attempt3-frozen177-execution'),(10000,BASE/'published-global-history-attempt4-frozen177-volume10000')]
comparison=BASE/'current21-index-candidate-attempt3-root-title-lookup/result.json';cmp=json.loads(comparison.read_bytes());assert cmp['status']=='pass_scoped'
migration=ROOT/'supabase/migrations/20261001095000_member_history_global_keyset_indexes.sql';rows=[];bound={};execution=None
for count,packet in sources:
 overall=json.loads((packet/'result.json').read_bytes());volume=packet/f'volume-{count}'/'result.json';d=json.loads(volume.read_bytes());summary=next(r for r in overall['volume_results']if r['volume']==count)
 assert d['status']==summary['status']=='pass_scoped' and summary['passed']==146 and summary['failed']==0
 assert sha(volume)==summary['result_sha256'] and d['all_source_tables_catalog_cron_preserved'] and d['isolated_database_removed']
 assert overall['published_migration_sha256']==sha(migration) and overall['required_history_inputs_unchanged']
 assert overall['accepted_comparison_sha256']==sha(comparison) and not overall['migration_source_drift']
 assert set(overall['source_input_drift'])<= {'supabase/migrations/20261001100000_receipt_financial_policy.sql'}
 if execution is None:execution=overall['frozen_execution_migration_inputs']
 assert execution==overall['frozen_execution_migration_inputs']
 windows_path=packet/f'volume-{count}'/'published-current/results.json';windows=json.loads(windows_path.read_bytes());assert len(windows)==108
 baseline=json.loads((comparison.parent/f'volume-{count}'/'baseline/results.json').read_bytes());benefits=[]
 for sort in ['newest','oldest','highest','lowest']:
  for depth in ['first','middle','deep']:
   key=f'history-{sort}-all-{depth}';b=baseline[key]['page'];a=windows[key]['page'];assert a['payment_rows_examined']<b['payment_rows_examined']/2 and a['root_hits']<b['root_hits'];benefits.append(dict(sort=sort,depth=depth,baseline_rows=b['payment_rows_examined'],published_rows=a['payment_rows_examined'],baseline_buffers=b['root_hits'],published_buffers=a['root_hits']))
 for p in [packet/'result.json',volume,windows_path,packet/f'volume-{count}'/'queue-intent-measurements.json']:
  bound[str(p.relative_to(ROOT))]=sha(p)
 rows.append(dict(volume=count,passed=146,failed=0,history_windows=108,benefits=benefits,source_preserved=True,clone_removed=True,original_overall_status=overall['status'],original_overall_failure_retained=True))
assert not OUT.exists();OUT.mkdir(mode=0o700);(OUT/'recorder-source.py').write_bytes(Path(__file__).read_bytes())
result=dict(status='pass_scoped',kind='published_history_two_genuine_generated_volumes',captured_at=dt.datetime.now(dt.timezone.utc).isoformat(),passed=292,failed=0,volumes=rows,bound_packets_sha256=bound,comparison_sha256=sha(comparison),published_migration_sha256=sha(migration),frozen_execution_migration_inputs=execution,frozen_migration_count=len(execution),current_receipt_policy_accepted=False,whole_current_checkout_accepted=False,latency_slo_claimed=False,full_exact_summary_scan_removed=False,scope='Current published history optimization and scoped recent-intent/notification APIs on the identical frozen177 reviewed execution set. Each independently generated volume has all146 checks and preserved shared database. Earlier setup/session-ID collision failure and later peer receipt policy delta remain separate.')
(OUT/'validation.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
(OUT/'README.md').write_text('''# Published history optimization — two-volume local acceptance

The additive migration `20261001095000_member_history_global_keyset_indexes.sql` now has actual public-API acceptance at both 1,000 and 10,000 genuinely posted payments: **292 checks, zero failures in these accepted volume sections**. The original combined run remains failed because its second clone reused a session ID; the 10,000-only retry fixes the fixture reset and retains its independent cleanup proof.

Each volume checks 108 history windows across four sorts, nine authorization/filter scopes and three depths. Twelve global windows per volume scan less than half the baseline payment rows and use strictly fewer buffers. All fields, totals, masked private titles, deterministic ties, revisions and cursor semantics are independently checked against actual generated rows. Concurrent cursor cases cover all four sorts. Four invalid foreign-key configurations must refuse migration and roll back.

Recent intents preserve exact pending counts while returning bounded owned rows; notification sorts/page depths retain exact totals and deterministic rows. A rollback-only queue deletion verifies known zero and restores all data. Full exact-summary scans remain necessary; no latency SLO or provider performance is inferred from these local runs.

The frozen execution set contains 177 migrations. A later peer receipt-policy edit is expressly dated and unaccepted by this packet. Shared 154/153-table source/catalog/cron data was preserved; each task-owned clone was removed. The JSON manifest records every evidence hash and individual scan/buffer comparison. This is query-specific acceptance, not whole repository or production acceptance.
''')
print(json.dumps({'status':'pass_scoped','volumes':[1000,10000],'passed':292,'failed':0,'frozen_migration_count':len(execution)}))

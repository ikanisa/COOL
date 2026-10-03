import json,hashlib,datetime
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');P=ROOT/'docs/release/local-progress-2026-09-30/current177-root-checkpoint3';assert not P.exists();P.mkdir();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
paths=['generated-query-benchmark-2026-10-01/published-history-two-volume-acceptance-root193/validation.json','local-database-runtime-2026-09-30/ordinary-installer-current177-attempt5-final-policy/result.json','local-database-runtime-2026-09-30/staged-bundle154-attempt24-current23-final-policy/result.json','local-progress-2026-09-30/accepted-qa-publication-root194/validation.json','asset-build-hygiene-2026-09-30/ios-warning-source-review-root190-current127/review.json','final-local-flutter-2026-10-01/current-final-set-attempt1/validation.json','gateway-reduced-motion-2026-10-01/root216-current-regressions/validation.json','gateway-reduced-motion-2026-10-01/root224-current-format/validation.json','visual-regression-review-2026-10-01/root211-reviewed-candidates/validation.json','visual-regression-review-2026-10-01/root211-reviewed-candidates/publication.json','local-browser-lifecycle-2026-09-30/current-email-memory-auth-root218-attempt17/validation.json','native-gateway-observation-2026-10-01/current-pure-jvm-root210/validation.json','native-gateway-observation-2026-10-01/flavor-boundary-relocation-root206.json','native-gateway-observation-2026-10-01/hardware-compatibility-root216.json','local-progress-2026-09-30/current177-browser-closure-root222/validation.json']
rows=[]
for name in paths:
 p=ROOT/'docs/release'/name;v=json.loads(p.read_bytes());rows.append(dict(path=str(p.relative_to(ROOT)),sha256=sha(p),observed_status=v.get('status',v.get('scope')),scope=v.get('scope')))
reg=json.loads((ROOT/'docs/release/local-implementation-register-2026-09-30.json').read_text());out=dict(captured_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),source_migrations=177,installed_migrations=154,installed_tables=153,staged_sources=23,local_closed=reg['locally_closed_goal_items'],local_open=[v['id']for v in reg['items']if v['status']!='complete'],production_decision='NO-GO',proofs=rows,running=['Current production unsigned artifact/JVM/manifest/package proof: root197 actual-native4','Current Gateway API24-compatible conditional hardware build/lint/JVM: root197 actual-native6-current-gateway'],scope='Current checkpoint; exact cited completed proofs bound. Running tests are not claimed passed and may update after this checkpoint. No production acceptance.')
(P/'proof-index.json').write_text(json.dumps(out,indent=2,sort_keys=True)+'\n');(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
(P/'checkpoint.md').write_text('''# Current local implementation checkpoint

The register is revision13: **7 local criteria closed, 17 open**. L18 is now
closed against actual current normal Admin/Public production entrypoints, all26
checks and all16 lifecycle cases. The original24 local and102 production criteria
are preserved. All101 original open production criteria remain open: **NO-GO**.

## Completed verification

- Current177 ordinary installer:32 checks/354 clean+populated migration executions,
  NOSUPERUSER/no direct cron DML,18 predecessor projections preserved, both owned
  containers removed. Current23-stage clone:86 checks,26 protected private tables,
  exact shared154/153-table/catalog/cron state preserved.
- Published history at1,000 and10,000 actual postings:146 checks per volume,
  292 total. Global scan/buffer benefits, all sort/scope/depth windows, real
  pending-intent/notification paging, queue shrink and concurrent cursors pass.
  Original failed second-volume setup and peer-policy dating remain retained.
- Flutter179 completed4450 pass/17 failed/0 skipped/0 unfinished. Its omitted
  inputs, Gateway motion/typography, exact endpoint inventory and fixture scan
  findings are corrected. Current complete affected12-file selection passes167
  with no failures/skips/unfinished; three public-SDK Auth fixture cases and
  fatal whole analysis pass. Current502-file app/test/tool formatting passes.
  This is affected-file acceptance; the old full suite is not rewritten as a
  current complete-source success.
- Five intentional golden differences were individually opened/reviewed. The
  fresh candidates match reviewed pixels exactly; only those five captures and
  manifest were published. All14 checks/13 captures pass; eight images and
  tolerance remain unchanged. Regression captures are not design comparators.
  Sole design-authority check passes; native Revolut fidelity is not certified.
- Current actual Chrome/PWA:26 checks/all16 cases, distinct Admin/Public builds,
  email memory sessions, reference-only bookmarks, reload, real tabs, departure,
  logout/A-B-A, warm/failed updates, legacy cache deletion and installed offline
  signed-out PWA pass. Exact consumed source and executable bytes are stable.
  Package QA fixtures remain outside this compiler footprint; full exported
  inventory and every unrelated change are separately retained.
- Gateway pure JVM:48 cases pass, including9 new freshness/SIM-change/stale
  callback/expiry/permission-departure/clock-rollback cases. Privileged Gateway
  implementation and its tests now belong only to the internal_gateway flavor.
  Production full native lint passes after this separation. Current native
  flavored artifacts and SDK/JVM/permission integration remain running.
- iOS127 actual unsigned generic arm64 compilation and199-file postbuild proof
  remain accepted at their captured source. Review190 individually reconciles
  23 warning strings/19 primary/4 duplicate presentations. Later source changes
  date whole-source currentness; no signing/device/store claim is made.
- QA harness publication194 binds the executed history and exact11-endpoint
  HTTP corrections.400 Edge units/86 actual HTTP checks and146 MCP tests remain
  accepted in their separately stated source scopes.

## Next required work

Finish actual current production/Gateway native JVM, APK identity/signature,
permissions and per-warning review; generate/reproduce observed compile/runtime
SBOMs from those exports. Reconcile each original local criterion with complete
current scope, finish missing Admin/roster/authorization/data/control coverage,
and bind final source and integrated handover.17 local criteria remain open.

All dirty source and prior failures remain preserved. The shared database still
has154 installed migrations;23 source migrations are staged, not deployed.
This checkpoint and source tests do not certify hosted/provider/device/font
rights/signing/store/owner approval or production readiness.
''');print('CHECKPOINT',len(rows),len(out['local_open']))

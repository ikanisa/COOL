import json,hashlib
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');P=ROOT/'docs/release/admin-full-coverage-2026-09-30/full179-current-client-scope-root226';A=ROOT/'docs/release/final-local-flutter-2026-10-01/current-final-set-attempt1';B=ROOT/'docs/release/gateway-reduced-motion-2026-10-01/root216-current-regressions';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();assert not P.exists();P.mkdir();(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
def completed(packet,prefix):
 suites={};started={};finished={};rows={}
 for line in (packet/('vm.machine.jsonl'if packet==A else'tests.machine.jsonl')).read_text().splitlines():
  r=json.loads(line)
  if r['type']=='suite':suites[r['suite']['id']]=r['suite'].get('path','')
  if r['type']=='testStart':started[r['test']['id']]=r['test']
  if r['type']=='testDone':
   assert r['testID']not in finished;finished[r['testID']]=r
 for i,v in finished.items():
  t=started[i];n=(suites.get(t.get('suiteID'))or t.get('root_url')or t.get('url','')).removeprefix('file://').removeprefix(prefix)
  if not n.startswith('test/admin_')or v.get('hidden'):continue
  row=rows.setdefault(n,[]);row.append(dict(name=t['name'],result=v['result'],skipped=bool(v.get('skipped'))))
 return rows
baseline=completed(A,'/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt179-full-flutter/');revised=completed(B,'/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-root216-current-regressions/');before=json.loads((A/'source-before.json').read_text());current=json.loads((B/'source-before.json').read_text());latest={}
for n,rows in baseline.items():
 assert before[n]==current[n]==sha(ROOT/n),n
 assert rows and all(v['result']=='success'and not v['skipped']for v in rows),n
 latest[n]=dict(packet='full179',cases=rows,source_sha256=before[n])
for n,rows in revised.items():
 assert current[n]==sha(ROOT/n)and rows and all(v['result']=='success'and not v['skipped']for v in rows),n
 latest[n]=dict(packet='root216',cases=rows,source_sha256=current[n])
expected={str(p.relative_to(ROOT))for p in (ROOT/'test').glob('admin_*_test.dart')};assert set(latest)==expected,(sorted(expected-set(latest)),sorted(set(latest)-expected))
# Gateway has a separate entrypoint and is the only changed production Dart
# file since full179. Bind every other production library, assets, fixture,
# local fork runtime and package/toolchain declaration; no server claim.
def consumed(n):
 if n.startswith('lib/gateway/'):return False
 return n.startswith(('lib/','assets/','licenses/','test/support/'))or(n.startswith('third_party/')and '/test/'not in n and '/tests/'not in n and '/example/'not in n and '/examples/'not in n and '/docs/'not in n)or n in {'pubspec.yaml','pubspec.lock','.fvmrc','analysis_options.yaml'}
inputs={n:h for n,h in before.items()if consumed(n)};assert {n for n in before if consumed(n)}=={n for n in current if consumed(n)};drift={n:dict(baseline=h,current=current.get(n),checkout=sha(ROOT/n))for n,h in inputs.items()if h!=current.get(n)or h!=sha(ROOT/n)};assert not drift,sorted(drift)
(P/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n');(P/'per-file-cases.json').write_text(json.dumps(latest,indent=2)+'\n');total=sum(len(v['cases'])for v in latest.values());(P/'validation.json').write_text(json.dumps(dict(status='pass',current_admin_test_files=len(latest),passing_cases=total,failed=0,skipped=0,source_input_count=len(inputs),source_drift=drift,whole_criteria_closed=[],original_full_suite_status=json.loads((A/'validation.json').read_text())['machine_summary']['runner_completed_successfully'],parent_full_suite_sha256=sha(A/'validation.json'),changed_file_packet_sha256=sha(B/'validation.json'),scope='All current Admin-named client test files, immutable current non-Gateway production Dart/assets/fork runtime/fixture inputs, plus new receipt-v2 cases. Original full179 failures retained. No current server/catalog acceptance, exhaustive route/action state completeness, external package authenticity, device or whole L03/L04/L05 closure is inferred.'),indent=2)+'\n');print('CURRENT ADMIN CLIENT SCOPE',len(latest),total,flush=True)

#!/usr/bin/env python3
"""Review only five current candidates in an isolated export, before publication."""
import os,json,hashlib,shutil,subprocess,time
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');BASE=ROOT/'docs/release/gateway-reduced-motion-2026-10-01/root203-current-golden-review';OUT=ROOT/'docs/release/visual-regression-review-2026-10-01/root211-reviewed-candidates';EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-root203-current-golden-review');SDK=ROOT/'.cache/flutter-sdk-isolated-final-source-root191'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
assert not OUT.exists();OUT.mkdir(parents=True,mode=0o700);(OUT/'runner-source.py').write_bytes(Path(__file__).read_bytes())
r=json.loads((BASE/'validation.json').read_text());rows=json.loads((BASE/'candidate-review-byte-comparison.json').read_text());assert len(rows)==5 and all(v['same_rendered_bytes']for v in rows);assert r['observed_failure_images']==r['expected_review_set'] and r['machine_summary']['passed']==9 and r['machine_summary']['errors']==5 and r['machine_summary']['unfinished']==[] and not r['export_drift'] and not r['source_drift']
# The broad pre-review runner incorrectly compared the unfinished list to an
# integer and retained inherited motion labels. This readback accepts only the
# thirteen actual renders and the exact five differences, with no motion claim.
save(OUT/'pre-review-readback.json',dict(expected_observed_five_differences=True,all_thirteen_candidates_present=len(list((BASE/'candidates').glob('*.png')))==13,original_broad_validation_status=r['status'],original_status_retained=True,incorrect_inherited_motion_labels_excluded=True,golden_acceptance_before_review=False))
source=json.loads((BASE/'source-before.json').read_text());inputs={n:h for n,h in source.items()if n.startswith(('lib/','assets/','web/','licenses/'))or(n.startswith('third_party/')and '/test/'not in n and '/example/'not in n and '/.dart_tool/'not in n)or n in {'pubspec.yaml','pubspec.lock','.fvmrc','test/goldens/collect_core_surfaces_golden_test.dart','test/goldens/goldens_fixture_repository.dart'}}
for n,h in inputs.items():assert sha(ROOT/n)==h and sha(EXPORT/n)==h,n
save(OUT/'render-inputs-before.json',inputs);old=OUT/'retained-baselines-before';old.mkdir()
for row in rows:
 n=row['name']+'.png';baseline=EXPORT/'test/goldens/baselines'/n;candidate=BASE/'candidates'/n;assert sha(baseline)==row['baseline_sha256']and sha(candidate)==row['current_candidate_sha256'];shutil.copy2(baseline,old/n);shutil.copy2(candidate,baseline)
manifest=EXPORT/'test/goldens/GOLDEN_MANIFEST.sha256';shutil.copy2(manifest,old/manifest.name);manifest.write_text(''.join(sha(p)+'  '+str(p.relative_to(EXPORT))+'\n'for p in sorted((EXPORT/'test/goldens/baselines').glob('*.png'))));save(OUT/'reviewed-five-byte-bindings.json',rows)
env={k:v for k,v in os.environ.items()if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}};env.update(CI='true',FLUTTER_SUPPRESS_ANALYTICS='true',PUB_CACHE=str(ROOT/'.cache/pub-cache-hygiene-20260930'));argv=[str(SDK/'bin/flutter'),'test','--no-pub','--concurrency=1','--reporter=expanded','--file-reporter=json:'+str(OUT/'tests.machine.jsonl'),'test/goldens/collect_core_surfaces_golden_test.dart'];start=time.monotonic()
with(OUT/'tests.log').open('wb')as log:r=subprocess.run(argv,cwd=EXPORT,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=600)
import sys;sys.path.insert(0,str(ROOT/'scripts/tests'));import admin_read_gateway_gate as G
summary=G.machine_summary(OUT/'tests.machine.jsonl');after={n:sha(ROOT/n)for n in inputs};drift={n:dict(before=h,after=after[n])for n,h in inputs.items()if h!=after[n]};save(OUT/'render-inputs-after.json',after)
passed=r.returncode==0 and summary['passed']==14 and summary['errors']==summary['failed']==summary['skipped']==0 and summary['unfinished']==[] and not drift
save(OUT/'validation.json',dict(status='pass'if passed else'fail',exit_code=r.returncode,machine_summary=summary,elapsed_seconds=round(time.monotonic()-start,2),source_drift=drift,baseline_update_count=5,unchanged_baseline_count=8,precision_tolerance_unchanged=0.0005,root_baselines_published=False,design_fidelity_or_owner_acceptance=False,scope='Implementing-agent review of intentional product/layout changes and thirteen isolated regression captures; no native/design/store/production acceptance',parent_pre_review_sha256=sha(BASE/'validation.json'),test_log_sha256=sha(OUT/'tests.log')))
print('REVIEWED GOLDENS',passed,flush=True);raise SystemExit(0 if passed else 1)

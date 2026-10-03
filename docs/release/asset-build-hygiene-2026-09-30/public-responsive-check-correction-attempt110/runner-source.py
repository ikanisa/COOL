import hashlib,json,os,subprocess,shutil,datetime
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-responsive-check-correction-attempt110'
BUILD=ROOT/'.cache/public-website-build-attempt109'
TOOL=ROOT/'scripts/public_website_quality_gate.sh'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before=TOOL.read_bytes();P.mkdir(exist_ok=False);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes());(P/'quality-gate-before.sh').write_bytes(before)
shutil.copy2(ROOT/'docs/release/public-website-content-baseline.json',P/'historical-baseline-before.json')
needle=b'responsive_components_ok = stylesheet.include?("grid-template-columns:minmax(0,1fr)") &&\n  stylesheet.include?("overflow-wrap:anywhere") &&\n  stylesheet.include?("prefers-reduced-motion:reduce") &&\n  stylesheet.include?("forced-colors:active") &&\n  stylesheet.include?(".mobile-menu-actions")'
assert before.count(needle)==1 and TOOL.read_bytes()==before
replacement=b'responsive_media_css = stylesheet.gsub(%r{/\\*.*?\\*/}m, "")\nresponsive_components_ok = stylesheet.include?("grid-template-columns:minmax(0,1fr)") &&\n  stylesheet.include?("overflow-wrap:anywhere") &&\n  responsive_media_css.match?(/@media\\s*\\(\\s*prefers-reduced-motion\\s*:\\s*reduce\\s*\\)/) &&\n  responsive_media_css.match?(/@media\\s*\\(\\s*forced-colors\\s*:\\s*active\\s*\\)/) &&\n  stylesheet.include?(".mobile-menu-actions")'
TOOL.write_bytes(before.replace(needle,replacement));current=sha(TOOL)
original=(BUILD/'revolut.css').read_text()
assert '@media (prefers-reduced-motion: reduce)' in original and '@media (forced-colors: active)' in original
cases=[('actual-current-spaced-css',original,True),('valid-extra-css-whitespace',original.replace('@media (prefers-reduced-motion: reduce)','@media  ( \n prefers-reduced-motion \t : reduce \n )').replace('@media (forced-colors: active)','@media ( \n forced-colors : active )'),True),('wrong-reduced-motion-value',original.replace('prefers-reduced-motion: reduce','prefers-reduced-motion: no-preference'),False),('wrong-forced-colors-value',original.replace('forced-colors: active','forced-colors: none'),False),('comment-only-correct-queries',original.replace('prefers-reduced-motion: reduce','prefers-reduced-motion: no-preference').replace('forced-colors: active','forced-colors: none')+'\n/* @media(prefers-reduced-motion:reduce){} @media(forced-colors:active){} */',False)]
results=[]
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
for name,css,expected in cases:
 destination=ROOT/'.cache'/('public-responsive-check-attempt110-'+name);assert not destination.exists();shutil.copytree(BUILD,destination)
 (destination/'revolut.css').write_text(css)
 env['PUBLIC_BUILD_DIR']=str(destination)
 r=subprocess.run(['bash',str(TOOL),'--json'],cwd=ROOT,env=env,capture_output=True,timeout=180)
 (P/(name+'.stdout')).write_bytes(r.stdout);(P/(name+'.stderr')).write_bytes(r.stderr)
 document=json.loads(r.stdout);checks={q['id']:q for q in document['checks']};target=checks['responsive_layout_and_route_variation']
 assert (target['status']=='pass')==expected,name
 assert checks['pre_audit_content_parity']['status']=='fail','Historical review boundary unexpectedly bypassed'
 failures=[q['id'] for q in document['checks'] if q['status']!='pass']
 assert set(failures)==({'pre_audit_content_parity'} if expected else {'pre_audit_content_parity','responsive_layout_and_route_variation'}),failures
 results.append({'case':name,'expected_responsive_pass':expected,'actual_responsive_status':target['status'],'preserved_historical_baseline_failure':True,'exit_code':r.returncode,'stdout_sha256':sha(P/(name+'.stdout')),'stderr_sha256':sha(P/(name+'.stderr'))})
 print('CASE PASS',name,flush=True)
assert sha(TOOL)==current and sha(ROOT/'docs/release/public-website-content-baseline.json')==sha(P/'historical-baseline-before.json')
(P/'validation.json').write_text(json.dumps({'status':'pass','checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'cases':results,'prior_gate_sha256':sha(P/'quality-gate-before.sh'),'current_gate_sha256':current,'scope':'Actual full local quality-gate runs prove existing valid media-query whitespace passes, wrong values and commented-only queries fail; historical visible-content mismatch remains explicit. No CSS/product/reference/owner-approval change.'},indent=2)+'\n')
print('PUBLIC RESPONSIVE STRUCTURAL CHECK CORRECTION PASS',len(results),flush=True)

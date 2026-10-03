import hashlib,json,os,subprocess,time,datetime
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-website-rebuild-attempt109'
BUILD=ROOT/'.cache/public-website-build-attempt109'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert not BUILD.exists() and json.loads((ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-media-publication-attempt106/publication.json').read_text())['status']=='pass'
P.mkdir(exist_ok=False);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
def inputs():
 names={'scripts/public_static_site_build.rb','scripts/public_app_media.rb','scripts/public_photography.rb','scripts/public_website_quality_gate.sh','scripts/qa/asset_manifest_integrity.rb','pubspec.yaml','assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256'}
 for directory in ['web/public','content/legal','assets/brand/collect_runtime/app_icons','assets/typefaces']:
  for p in (ROOT/directory).rglob('*'):
   if p.is_file():assert not p.is_symlink();names.add(p.relative_to(ROOT).as_posix())
 return {n:sha(ROOT/n) for n in sorted(names)}
before=inputs();(P/'source-before.json').write_text(json.dumps(before,indent=2,sort_keys=True)+'\n')
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}};env['PUBLIC_BUILD_DIR']=str(BUILD)
commands=[]
def run(name,args):
 print('START',name,flush=True);start=time.monotonic()
 with (P/(name+'.stdout')).open('wb') as out,(P/(name+'.stderr')).open('wb') as err:r=subprocess.run(args,cwd=ROOT,env=env,stdout=out,stderr=err)
 commands.append({'name':name,'command':args,'exit_code':r.returncode,'elapsed_seconds':round(time.monotonic()-start,2),'stdout_sha256':sha(P/(name+'.stdout')),'stderr_sha256':sha(P/(name+'.stderr'))})
 (P/'execution.json').write_text(json.dumps({'status':'running' if r.returncode==0 else 'fail','commands':commands},indent=2)+'\n');print('END',name,r.returncode,flush=True);assert r.returncode==0,name
run('public-static-build',['ruby','scripts/public_static_site_build.rb'])
run('public-quality-gate',['bash','scripts/public_website_quality_gate.sh','--json'])
run('sole-design-authority',['make','revolut-design-authority'])
manifest=json.loads((ROOT/'web/public/app-screens/manifest.json').read_text())
checks={}
for row in manifest['screens']:
 matches=list(BUILD.rglob(row['file']));assert len(matches)==1,'Missing or duplicate built preview '+row['id']
 assert sha(matches[0])==row['sha256']
 checks[row['id']]={'build_path':matches[0].relative_to(BUILD).as_posix(),'sha256':sha(matches[0]),'original_png_bytes_preserved':True}
artifacts={p.relative_to(BUILD).as_posix():sha(p) for p in sorted(BUILD.rglob('*')) if p.is_file() and not p.is_symlink()}
(P/'build-manifest.json').write_text(json.dumps(artifacts,indent=2,sort_keys=True)+'\n')
after=inputs();assert before==after,'Actual static website source changed during build/quality checks'
quality=json.loads((P/'public-quality-gate.stdout').read_text())
(P/'verification.json').write_text(json.dumps({'status':'pass','completed_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'commands':commands,'source_inputs':len(before),'source_inputs_unchanged':True,'source_before_sha256':sha(P/'source-before.json'),'build':str(BUILD),'build_file_count':len(artifacts),'build_manifest_sha256':sha(P/'build-manifest.json'),'built_reviewed_previews':checks,'quality_receipt':quality,'scope':'Fresh local static build and actual quality/link/preview byte-copy checks; sole-design hygiene only, no hosted availability or comprehensive visual release acceptance.'},indent=2)+'\n')
print('PUBLIC WEBSITE REBUILD PASS',len(artifacts),flush=True)

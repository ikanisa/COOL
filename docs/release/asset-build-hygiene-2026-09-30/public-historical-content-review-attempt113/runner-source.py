import hashlib,json,subprocess,tarfile,io,os,time
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-historical-content-review-attempt113'
SOURCE=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt113-historical-public-content')
BUILD=SOURCE/'historical-public-build'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
commit=subprocess.check_output(['git','rev-parse','f0b8b37a^{commit}'],cwd=ROOT,text=True).strip()
paths=['scripts/public_static_site_build.rb','scripts/public_app_media.rb','content/legal','web/public','lib','assets','licenses','android/app/src','ios/Runner','pubspec.yaml','pubspec.lock']
paths=[n for n in paths if subprocess.check_output(['git','ls-tree','--name-only',commit,'--',n],cwd=ROOT).strip()]
P.mkdir(exist_ok=False);SOURCE.mkdir(exist_ok=False);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
raw=subprocess.check_output(['git','archive',commit,'--',*paths],cwd=ROOT)
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:') as archive:
 for item in archive.getmembers():
  assert item.isdir() or item.isfile(),'Unsupported archive object'
  assert not Path(item.name).is_absolute() and '..' not in Path(item.name).parts
 archive.extractall(SOURCE,filter='data')
inputs={p.relative_to(SOURCE).as_posix():sha(p) for p in sorted(SOURCE.rglob('*')) if p.is_file()}
(P/'historical-source.json').write_text(json.dumps({'git_commit':commit,'archive_sha256':hashlib.sha256(raw).hexdigest(),'source_sha256':inputs,'scope':'Historical product-content evidence reconstructed in an isolated ignored cache; no historical source/design is restored to active repository authority.'},indent=2)+'\n')
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}};env['PUBLIC_BUILD_DIR']=str(BUILD)
print('START exact historical local static builder',flush=True)
with (P/'historical-build.stdout').open('wb') as out,(P/'historical-build.stderr').open('wb') as err:r=subprocess.run(['ruby','scripts/public_static_site_build.rb'],cwd=SOURCE,env=env,stdout=out,stderr=err)
receipt={'status':'pass' if r.returncode==0 else 'fail','command':['ruby','scripts/public_static_site_build.rb'],'exit_code':r.returncode,'historical_git_commit':commit,'source':str(SOURCE),'build':str(BUILD),'stdout_sha256':sha(P/'historical-build.stdout'),'stderr_sha256':sha(P/'historical-build.stderr'),'all_retained_historical_sources_unchanged':all(sha(SOURCE/n)==h for n,h in inputs.items()),'scope':'Historical source-only local HTML reconstruction for exact old visible-content baseline comparison, no production/native/design acceptance.'}
(P/'execution.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('END historical build',r.returncode,flush=True)
raise SystemExit(r.returncode)

import hashlib,json,os,subprocess
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
BASE=ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-historical-content-review-attempt113'
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-historical-content-review-attempt119'
prior=json.loads((BASE/'historical-source.json').read_text());SOURCE=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt113-historical-public-content')
BUILD=SOURCE/'.cache/historical-public-build-attempt119';sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
assert not BUILD.exists() and all(sha(SOURCE/n)==h for n,h in prior['source_sha256'].items())
P.mkdir(exist_ok=False);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}};env['PUBLIC_BUILD_DIR']=str(BUILD)
with (P/'historical-build.stdout').open('wb') as out,(P/'historical-build.stderr').open('wb') as err:r=subprocess.run(['ruby','scripts/public_static_site_build.rb'],cwd=SOURCE,env=env,stdout=out,stderr=err)
(P/'execution.json').write_text(json.dumps({'status':'pass' if r.returncode==0 else 'fail','exit_code':r.returncode,'source':str(SOURCE),'build':str(BUILD),'source_manifest_sha256':sha(BASE/'historical-source.json'),'source_git_commit':prior['git_commit'],'source_unchanged':all(sha(SOURCE/n)==h for n,h in prior['source_sha256'].items()),'stdout_sha256':sha(P/'historical-build.stdout'),'stderr_sha256':sha(P/'historical-build.stderr'),'scope':'Unmodified exact historical source with a valid isolated ignored output directory; content reconstruction only, not active design authority or production acceptance.'},indent=2)+'\n')
print('EXACT HISTORICAL HTML RECONSTRUCTION',r.returncode,flush=True);raise SystemExit(r.returncode)

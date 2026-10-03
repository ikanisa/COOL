import hashlib,json,subprocess,os,datetime
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/sdk-isolation-attempt136'
SOURCE=ROOT/'.cache/flutter-sdk-isolated-asset-attempt23'
SDK=ROOT/'.cache/flutter-sdk-isolated-asset-attempt136'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert not SDK.exists();P.mkdir(exist_ok=False);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
accepted=json.loads((ROOT/'docs/release/asset-build-hygiene-2026-09-30/local-source-acceptance-attempt83/sdk-isolation.json').read_text())['critical_sha256']
critical=sorted(accepted)
assert len(critical)==4
observed={n:sha(SOURCE/n) for n in critical};assert observed==accepted
with (P/'copy.stdout').open('wb') as out,(P/'copy.stderr').open('wb') as err:code=subprocess.run(['cp','-cR',str(SOURCE),str(SDK)],stdout=out,stderr=err).returncode
assert code==0
assert observed=={n:sha(SDK/n) for n in critical}=={n:sha(SOURCE/n) for n in critical}
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}};env.update({'CI':'true','FLUTTER_SUPPRESS_ANALYTICS':'true'})
with (P/'version.stdout').open('wb') as out,(P/'version.stderr').open('wb') as err:code=subprocess.run([str(SDK/'bin/flutter'),'--version','--machine'],env=env,stdout=out,stderr=err).returncode
assert code==0
version=json.loads((P/'version.stdout').read_text());assert version['frameworkVersion']=='3.44.4' and version['frameworkRevision']=='ad70ec4617166f1c38e5d2bfd388af71fda14f06' and version['dartSdkVersion']=='3.12.2'
assert observed=={n:sha(SDK/n) for n in critical}
(P/'validation.json').write_text(json.dumps({'status':'pass','critical_sha256':observed,'version':version,'source_sdk':str(SOURCE),'clone_sdk':str(SDK),'copy_exit_code':0,'observed_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'Independent APFS SDK clone for Gateway compilation; exact pinned version and critical executable/snapshot bytes match the already inspected SDK23. No complete SDK/toolchain/cache attestation.'},indent=2)+'\n')
print('PINNED GATEWAY SDK128 PREFLIGHT PASS',flush=True)

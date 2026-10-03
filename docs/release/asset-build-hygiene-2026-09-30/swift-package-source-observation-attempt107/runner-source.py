import hashlib,json,os,subprocess,datetime
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt100-ios')
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/swift-package-source-observation-attempt107'
LOCK=EXPORT/'ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved'
CACHE=EXPORT/'build/ios/SourcePackages/checkouts'
sha=lambda b:hashlib.sha256(b).hexdigest()
mode=os.environ.get('COLLECT_SPM_OBSERVATION_PHASE','during_build')
assert mode in {'during_build','after_build'}
if mode=='during_build':
 P.mkdir(exist_ok=False);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
else:
 assert P.is_dir() and not (P/'after_build.json').exists()
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
def git(p,*args):return subprocess.check_output(['git','-C',str(p),*args],env=env)
pins=json.loads(LOCK.read_text())['pins'];observed={}
for pin in pins:
 identity=pin['identity'];checkout=CACHE/identity
 assert checkout.is_dir() and checkout.resolve()==checkout and checkout.is_relative_to(CACHE)
 head=git(checkout,'rev-parse','HEAD').decode().strip();assert head==pin['state']['revision'],identity
 status=git(checkout,'status','--porcelain=v1','--untracked-files=all');assert not status,'Dirty or untracked package input: '+identity
 rows=git(checkout,'ls-files','--stage','-z').split(b'\0');files={}
 for row in rows:
  if not row:continue
  header,name=row.split(b'\t',1);file_mode,oid,stage=header.decode().split();assert stage=='0'
  n=os.fsdecode(name);path=checkout/n;assert not n.startswith('/') and '..' not in Path(n).parts
  if file_mode=='120000':
   assert path.is_symlink();target=os.readlink(path);data=os.fsencode(target)
   resolved=path.resolve(strict=True);assert resolved.is_relative_to(checkout) and resolved.is_file()
   kind={'symlink':target,'resolved_target_sha256':sha(resolved.read_bytes())}
  else:
   assert file_mode in {'100644','100755'} and path.is_file() and not path.is_symlink(),n
   data=path.read_bytes();kind={'mode':file_mode}
  assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==oid,'Pinned git blob differs: '+identity+'/'+n
  files[n]={'sha256':sha(data),'bytes':len(data),'git_blob':oid,**kind}
 assert head==git(checkout,'rev-parse','HEAD').decode().strip() and not git(checkout,'status','--porcelain=v1','--untracked-files=all')
 observed[identity]={'revision':head,'version':pin['state'].get('version'),'files':files}
 print('BOUND',identity,len(files),flush=True)
report={'status':'pass','phase':mode,'observed_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'package_lock_sha256':sha(LOCK.read_bytes()),'package_count':len(observed),'tracked_file_count':sum(len(x['files']) for x in observed.values()),'packages':observed,'scope':'Actual cached Swift package checkout tracked bytes and modes are SHA-256 bound and verified against every exact locked Git blob; symlinks resolve inside the package, dirty and nonignored untracked inputs are refused. Initial observation occurs after Xcode launch, so no prelaunch byte-map claim; no complete Xcode/SDK/ignored-cache attestation.'}
if mode=='after_build':
 prior=json.loads((P/'during_build.json').read_text());assert prior['packages']==observed and prior['package_lock_sha256']==report['package_lock_sha256']
 report['during_and_after_input_maps_unchanged']=True;report['during_build_receipt_sha256']=sha((P/'during_build.json').read_bytes())
(P/(mode+'.json')).write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print('SPM ACTUAL PINNED BYTE OBSERVATION PASS',report['package_count'],report['tracked_file_count'],flush=True)

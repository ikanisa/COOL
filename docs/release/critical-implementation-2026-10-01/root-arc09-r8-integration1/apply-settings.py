from pathlib import Path
import datetime,hashlib,json,os,signal,time
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
BASE=Path(__file__).resolve().parent
APP=Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1/app-source')
PREP=ROOT/'docs/release/critical-implementation-2026-10-01/arc09-r8-9.1.29-preparation1'
NAME='android/settings.gradle.kts'
OLD='3c06abd940c572639def32654d82f851002cf8ed23f4cdac4416e97fc5bd862d'
NEW='4e28cd700c06e79ddaa3a7ea03f92db887f4a16a51d2db45c4783e0bae657c5a'
def sha(body):return hashlib.sha256(body).hexdigest()
def canonical(value):return (json.dumps(value,sort_keys=True,separators=(',',':'))+'\n').encode()
def read(path):
    assert path.resolve()==path and path.is_file() and not path.is_symlink()
    before=path.stat()
    with os.fdopen(os.open(path,os.O_RDONLY|os.O_NOFOLLOW),'rb') as f:
        held=os.fstat(f.fileno());assert (held.st_dev,held.st_ino)==(before.st_dev,before.st_ino)
        body=f.read();after=os.fstat(f.fileno())
    now=path.stat()
    identity=lambda s:(s.st_dev,s.st_ino,s.st_size,s.st_mode,s.st_mtime_ns,s.st_ctime_ns)
    assert identity(before)==identity(after)==identity(now)
    return body,{'bytes':len(body),'sha256':sha(body),'mode':before.st_mode&0o777}
def preserve(path,name):
    body,metadata=read(path);target=BASE/'before'/name;target.parent.mkdir(parents=True,exist_ok=True)
    with target.open('xb') as f:f.write(body);f.flush();os.fsync(f.fileno())
    os.chmod(target,0o400);return body,metadata
def replace(path,body,mode):
    tmp=path.with_name(path.name+'.r8-integration-tmp');assert not tmp.exists()
    with tmp.open('xb') as f:os.fchmod(f.fileno(),mode);f.write(body);f.flush();os.fsync(f.fileno())
    os.replace(tmp,path)
def expired(*_):raise TimeoutError('300-second integration bound')
signal.signal(signal.SIGALRM,expired);signal.alarm(300);started=time.monotonic()
manifest_path=APP/'.collect-release-candidate.json'
old_manifest,manifest_metadata=read(manifest_path)
assert sha(old_manifest)=='5901e79105f0aa6727bd3931b284c00e2d8b58dabfa3aa344841ab273a0336b7'
manifest=json.loads(old_manifest);rows=manifest['source_files']
assert len(rows)==manifest['file_count']==2561 and sha(canonical(rows))==manifest['source_manifest_sha256']
assert manifest['approvals']=={k:False for k in ('trusted_source_verified','reviewed','frozen','owner_approved','signed','production_release_accepted')}
assert manifest['capture_classification']=='strict_unapproved_source_export'
for name,row in rows.items():
    assert not Path(name).is_absolute() and '..' not in Path(name).parts
    assert read(APP/name)[1]==row,name
proposal,proposal_metadata=read(PREP/'proposed'/NAME)
assert proposal_metadata['sha256']==NEW and len(proposal)==1163
saved=[]
for label,owner in [('maintained',ROOT),('privateAPP',APP)]:
    before,metadata=preserve(owner/NAME,label+'/'+NAME)
    assert metadata=={'bytes':840,'sha256':OLD,'mode':0o700}
    saved.append((label,owner,before,metadata))
preserve(manifest_path,'privateAPP/.collect-release-candidate.json')
for label,owner,before,metadata in saved:
    assert read(owner/NAME)[0]==before
    replace(owner/NAME,proposal,metadata['mode']);assert read(owner/NAME)[1]=={'bytes':1163,'sha256':NEW,'mode':0o700}
new_rows={name:dict(row) for name,row in rows.items()};new_rows[NAME]={'bytes':1163,'sha256':NEW,'mode':0o700}
for name,row in new_rows.items():assert read(APP/name)[1]==row,name
new_manifest={**manifest,'source_files':new_rows,'source_manifest_sha256':sha(canonical(new_rows)),
    'captured_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
assert new_manifest['approvals']==manifest['approvals']
replace(manifest_path,canonical(new_manifest),manifest_metadata['mode'])
record={'kind':'actual_reviewed_R8_settings_overlay_after_Android2','captured_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'actual_seconds':time.monotonic()-started,'deadline_seconds':300,
    'changed_settings':{'path':NAME,'archived_before':{'bytes':840,'sha256':OLD,'mode':0o700},'actual_after':new_rows[NAME]},
    'previous_APP_manifest_sha256':sha(old_manifest),'current_APP_manifest':{'path':str(manifest_path),'sha256':sha(read(manifest_path)[0])},
    'current_APP_source_manifest_sha256':new_manifest['source_manifest_sha256'],'source_file_count':2561,
    'unchanged_rows_since_Android2':2560,'unchanged_archived_rows_after_Android3':2558,
    'original_native_test_scope_reused_without_whole_current_native_claim':True,
    'R8_AGP_provider_verified':False,'production_release_approval':False,'source_lock_attested':False}
with (BASE/'settings-overlay-readback.json').open('x') as f:json.dump(record,f,indent=2,sort_keys=True);f.write('\n')
signal.alarm(0);print(json.dumps(record))

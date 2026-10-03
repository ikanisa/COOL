from pathlib import Path
import base64, datetime, hashlib, json, os, signal, subprocess, time, zipfile
ROOT=Path(__file__).resolve().parent
OUT=Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/r8-9.1.29-publisher-acquisition1')
URL='https://storage.googleapis.com/r8-releases/raw/com/android/tools/r8/9.1.29/r8-9.1.29.jar'
JAVA=Path('/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def save(name,obj):
    with (ROOT/name).open('x') as f:json.dump(obj,f,indent=2,sort_keys=True);f.write('\n')
def deadline(*_):raise TimeoutError('60-second validation bound exceeded')
signal.signal(signal.SIGALRM,deadline);signal.alarm(60);started=time.monotonic()
assert (ROOT/'failure.json').exists()
meta=json.loads((OUT/'curl.stdout').read_bytes());command=json.loads((ROOT/'command.json').read_bytes())
assert command['exit_code']==0 and meta['http_code']==200 and meta['ssl_verify_result']==0 and meta['url_effective']==URL
jar=OUT/'r8-9.1.29.jar';assert jar.is_file() and not jar.is_symlink()
before=jar.stat();raw=jar.read_bytes();digest=hashlib.sha256(raw).hexdigest()
assert len(raw)==56139715 and hashlib.md5(raw).hexdigest()=='60e153b8c1dba4d97e9b1ef2d75c2e61'
headers=(OUT/'r8.headers').read_text()
assert 'x-goog-generation: 1770813549786388' in headers
assert 'md5='+base64.b64encode(bytes.fromhex(hashlib.md5(raw).hexdigest())).decode() in headers
assert 'crc32c=wwtxyA==' in headers
with zipfile.ZipFile(jar) as z:
    names=z.namelist();assert len(names)==len(set(names))
    assert all(not n.startswith('/') and '..' not in Path(n).parts for n in names)
    assert z.testzip() is None and 'com/android/tools/r8/R8.class' in names
    members=len(names)
assert sha(JAVA)=='2ac3dc4814f66521692d2099674c523afd486e3378bf285c57d96040c6472dd4'
argv=[str(JAVA),'-cp',str(jar),'com.android.tools.r8.R8','--version'];t=time.monotonic()
p=subprocess.run(argv,capture_output=True,timeout=5)
(OUT/'version.stdout').write_bytes(p.stdout);(OUT/'version.stderr').write_bytes(p.stderr)
save('version-command.json',{'argv':argv,'exit_code':p.returncode,'deadline_seconds':5,'actual_seconds':time.monotonic()-t,'stdout_sha256':sha(OUT/'version.stdout'),'stderr_sha256':sha(OUT/'version.stderr')})
assert p.returncode==0 and p.stdout.decode().startswith('R8 9.1.29 ')
after=jar.stat();assert (before.st_ino,before.st_size,before.st_mtime_ns)==(after.st_ino,after.st_size,after.st_mtime_ns)
assert sha(jar)==digest
r={'status':'PASS','validation_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
   'actual_validation_seconds':time.monotonic()-started,'validation_bound_seconds':60,
   'artifact_coordinate':'com.android.tools:r8:9.1.29','path':str(jar),'sha256':digest,
   'sha1':hashlib.sha1(raw).hexdigest(),'bytes':len(raw),'publisher_md5':hashlib.md5(raw).hexdigest(),
   'publisher_generation':'1770813549786388','TLS_verify_result':0,'HTTP_code':200,
   'effective_URL':URL,'jar_CRC_all_members_pass':True,'jar_members':members,
   'version':p.stdout.decode().strip(),'initial_failed_header_assertion_preserved':True,
   'failure_cause':'Mistyped Base64 literal in the root validation script; actual MD5 and generation match publisher headers.',
   'acquisition_command_sha256':sha(ROOT/'command.json'),'headers_sha256':sha(OUT/'r8.headers'),
   'gradle_cache_populated':False,'actual_AGP_classloader_provider_verified':False,
   'licence_acceptance':False,'production_release_approval':False}
save('readback.json',r)
for leaf in OUT.iterdir():os.chmod(leaf,0o400)
signal.alarm(0);print(json.dumps(r))

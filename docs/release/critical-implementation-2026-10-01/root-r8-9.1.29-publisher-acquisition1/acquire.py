from pathlib import Path
import datetime, hashlib, json, os, subprocess, time, zipfile

ROOT=Path(__file__).resolve().parent
OUT=Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/r8-9.1.29-publisher-acquisition1')
URL='https://storage.googleapis.com/r8-releases/raw/com/android/tools/r8/9.1.29/r8-9.1.29.jar'
JAVA='/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java'
def save(name,obj):
    path=ROOT/name
    with path.open('x') as f:json.dump(obj,f,indent=2,sort_keys=True);f.write('\n')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
assert not OUT.exists()
OUT.mkdir(mode=0o700)
argv=['/usr/bin/curl','--proto','=https','--tlsv1.2','--location','--max-redirs','2',
      '--connect-timeout','10','--max-time','120','--max-filesize','60000000',
      '--fail','--silent','--show-error','--dump-header',str(OUT/'r8.headers'),
      '--output',str(OUT/'r8-9.1.29.jar'),'--write-out','%{json}',URL]
started=datetime.datetime.now(datetime.timezone.utc).isoformat();t=time.monotonic()
try:
    p=subprocess.run(argv,capture_output=True,timeout=125)
    (OUT/'curl.stdout').write_bytes(p.stdout);(OUT/'curl.stderr').write_bytes(p.stderr)
    command={'argv':argv,'exit_code':p.returncode,'deadline_seconds':125,
             'actual_seconds':time.monotonic()-t,'started_at_utc':started,
             'stdout_sha256':sha(OUT/'curl.stdout'),'stderr_sha256':sha(OUT/'curl.stderr')}
    save('command.json',command)
    assert p.returncode==0,'Artifact acquisition failed'
    meta=json.loads(p.stdout);jar=OUT/'r8-9.1.29.jar'
    assert meta['http_code']==200 and meta['ssl_verify_result']==0 and meta['url_effective']==URL
    assert jar.is_file() and not jar.is_symlink()
    raw=jar.read_bytes()
    assert len(raw)==56139715
    assert hashlib.md5(raw).hexdigest()=='60e153b8c1dba4d97e9b1ef2d75c2e61'
    headers=(OUT/'r8.headers').read_text()
    assert '1770813549786388' in headers and 'YOFTuMHbpNl+mR7y11wuYQ==' in headers
    with zipfile.ZipFile(jar) as z:
        names=z.namelist();assert len(names)==len(set(names))
        assert all(not n.startswith('/') and '..' not in Path(n).parts for n in names)
        assert z.testzip() is None
        assert 'com/android/tools/r8/R8.class' in names
        members=len(names)
    assert sha(Path(JAVA))=='2ac3dc4814f66521692d2099674c523afd486e3378bf285c57d96040c6472dd4'
    version_argv=[JAVA,'-cp',str(jar),'com.android.tools.r8.R8','--version']
    tv=time.monotonic();v=subprocess.run(version_argv,capture_output=True,timeout=5)
    (OUT/'version.stdout').write_bytes(v.stdout);(OUT/'version.stderr').write_bytes(v.stderr)
    save('version-command.json',{'argv':version_argv,'exit_code':v.returncode,
         'deadline_seconds':5,'actual_seconds':time.monotonic()-tv,
         'stdout_sha256':sha(OUT/'version.stdout'),'stderr_sha256':sha(OUT/'version.stderr')})
    assert v.returncode==0 and v.stdout.decode().startswith('R8 9.1.29 ')
    record={'status':'PASS','artifact_coordinate':'com.android.tools:r8:9.1.29',
            'path':str(jar),'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),
            'publisher_md5':hashlib.md5(raw).hexdigest(),'publisher_generation':'1770813549786388',
            'TLS_verify_result':meta['ssl_verify_result'],'HTTP_code':meta['http_code'],
            'effective_URL':meta['url_effective'],'jar_CRC_all_members_pass':True,'jar_members':members,
            'version':v.stdout.decode().strip(),'gradle_cache_populated':False,
            'actual_AGP_classloader_provider_verified':False,'licence_acceptance':False,
            'production_release_approval':False}
    save('readback.json',record)
    for leaf in OUT.iterdir():os.chmod(leaf,0o400)
    print(json.dumps(record))
except BaseException as e:
    save('failure.json',{'type':type(e).__name__,'error':str(e),'actual_seconds':time.monotonic()-t})
    raise

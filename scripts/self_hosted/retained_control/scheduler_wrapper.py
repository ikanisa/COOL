#!/usr/bin/env python3
"""Run the sealed scheduler once and retain only its latest sanitized result."""
import argparse,hashlib,json,os,re,selectors,signal,stat,subprocess,sys,time,urllib.parse,uuid
from pathlib import Path

SOURCE_SHA256='f691215e0df1ce7400d0d83115132744fb1f308e58cc40d75d532ed740f890ee'
PROFILE_SHA256='18f9b92d996651911d57693b7ba7e3c1c782c85cf17142983f2061ea592de5c1'
SCRIPT_SHA256='bdaedf11432f928b86ff56876f6d092917845eca13eb07d6dc0dcf0f8e9594c8'
RELEASES=Path('/Volumes/SupaRuntime/collect-production/releases')
BASE=RELEASES/'testing-candidate-033-member-only'
PRODUCTION=RELEASES/'production-20261113-001'
FORMAT='collect.scheduler-tick.v1'

def private_file(path):
 p=Path(path);s=p.lstat()
 if p.resolve()!=p or not stat.S_ISREG(s.st_mode) or s.st_uid!=os.getuid() or s.st_nlink!=1 or stat.S_IMODE(s.st_mode)!=0o600:raise ValueError('scheduler_private_file')
 return p

def receipt_directory(path):
 p=Path(path);s=p.lstat()
 if p.resolve()!=p or not stat.S_ISDIR(s.st_mode) or s.st_uid!=os.getuid() or stat.S_IMODE(s.st_mode)!=0o700:raise ValueError('scheduler_private_directory')
 return p

def metadata(release,endpoint,lock):
 release=Path(release);lock=Path(lock)
 if not release.is_absolute() or release not in (BASE,PRODUCTION) or release.resolve(strict=True)!=release or release.parent!=RELEASES:raise ValueError('scheduler_release')
 script=release/'source/scripts/self_hosted/burimunsi_scheduler.py'
 if script.is_symlink() or hashlib.sha256(script.read_bytes()).hexdigest()!=SCRIPT_SHA256:raise ValueError('scheduler_source_changed')
 meta=json.loads((release/'release.json').read_bytes())
 if meta.get('source_sha256')!=SOURCE_SHA256 or meta.get('profile_sha256')!=PROFILE_SHA256:raise ValueError('scheduler_release_source')
 config=private_file(release/'private/configuration.json');config_sha=hashlib.sha256(config.read_bytes()).hexdigest()
 expected=release/'private/native-scheduler/tick.lock';folder=receipt_directory(expected.parent)
 if lock!=expected:raise ValueError('scheduler_lock_binding')
 private_file(lock)
 u=urllib.parse.urlsplit(endpoint)
 if u.scheme!='http' or u.hostname!='127.0.0.1' or u.username is not None or u.password is not None or u.port is None or u.path!='/functions/v1/collect-jobs' or u.query or u.fragment:raise ValueError('scheduler_endpoint')
 return script,folder,config_sha

def capture(argv,timeout=140):
 process=subprocess.Popen(argv,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,start_new_session=True)
 data=bytearray();sel=selectors.DefaultSelector();sel.register(process.stdout,selectors.EVENT_READ);deadline=time.monotonic()+timeout
 try:
  while sel.get_map():
   remaining=deadline-time.monotonic()
   if remaining<=0:raise TimeoutError('scheduler_tick_timeout')
   for key,_ in sel.select(min(.25,remaining)):
    chunk=os.read(key.fileobj.fileno(),4097-len(data))
    if not chunk:sel.unregister(key.fileobj);continue
    data.extend(chunk)
    if len(data)>4096:raise ValueError('scheduler_tick_output_too_large')
  remaining=deadline-time.monotonic()
  if remaining<=0:raise TimeoutError('scheduler_tick_timeout')
  return process.wait(timeout=remaining),bytes(data)
 finally:
  sel.close();process.stdout.close()
  if process.poll() is None:
   try:os.killpg(process.pid,signal.SIGTERM)
   except ProcessLookupError:pass
   try:process.wait(timeout=5)
   except subprocess.TimeoutExpired:
    try:os.killpg(process.pid,signal.SIGKILL)
    except ProcessLookupError:pass
    process.wait(timeout=5)

def save(folder,record):
 path=folder/'last-tick.private.json'
 if os.path.lexists(path):
  old=json.loads(private_file(path).read_bytes())
  if old.get('format')!=FORMAT:raise ValueError('scheduler_receipt_owner')
 temp=folder/('tick-'+uuid.uuid4().hex+'.private.tmp')
 fd=os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
 with os.fdopen(fd,'w') as f:json.dump(record,f,sort_keys=True,separators=(',',':'));f.write('\n');f.flush();os.fsync(f.fileno())
 os.replace(temp,path)
 fd=os.open(folder,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
 try:os.fsync(fd)
 finally:os.close(fd)

def run(release,endpoint,lock,*,runner=capture):
 script,folder,configuration=metadata(release,endpoint,lock);start=time.time_ns();status='unconfirmed';exit_code=1
 try:
  code,raw=runner([sys.executable,'-I','-B',str(script),'--release',str(release),'--endpoint',endpoint,'--lock',str(lock)])
  value=json.loads(raw)
  if code==0 and value.get('status')=='complete' and value.get('source_sha256')==SOURCE_SHA256:status='complete';exit_code=0
  elif code==0 and value=={'status':'already_running'}:status='busy';exit_code=0
 except (OSError,ValueError,TypeError,AttributeError,TimeoutError,subprocess.SubprocessError,json.JSONDecodeError):pass
 save(folder,{'format':FORMAT,'status':status,'source_sha256':SOURCE_SHA256,'configuration_sha256':configuration,'scheduler_script_sha256':SCRIPT_SHA256,'started_ns':start,'finished_ns':time.time_ns(),'run_id':str(uuid.uuid4())})
 return exit_code

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--release',type=Path,required=True);p.add_argument('--endpoint',required=True);p.add_argument('--lock',type=Path,required=True);a=p.parse_args()
 try:raise SystemExit(run(a.release,a.endpoint,a.lock))
 except (OSError,ValueError,TypeError,json.JSONDecodeError):raise SystemExit(1)

if __name__=='__main__':main()

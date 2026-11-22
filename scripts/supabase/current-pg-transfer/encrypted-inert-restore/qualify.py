#!/usr/bin/env python3
"""Synthetic-only macOS encrypted-image and owned PostgreSQL restore exercise.

No archive path, source URL, credentials or snapshot can be supplied. This is
not a production archive restore command. Preserve an owned scratch directory
if an operation or cleanup cannot be confirmed.
"""
import json
import os
import pathlib
import plistlib
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time

BASE=pathlib.Path('/private/tmp')
HERE=pathlib.Path(__file__).resolve().parent
NODE='/Volumes/PRO-G40/Development/Node/bin/node'
DEFAULT_PG='/Volumes/PRO-G40/Development/Supabase/Qwen-Validation/cache/stack/slim-services/postgres/17.11.0.004-r1/darwin-arm64/bin'
ENV={'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','LC_ALL':'C'}

class Refused(Exception): pass
def require(condition, code):
 if not condition: raise Refused(code)
def invoke(args, *, secret=None, timeout=30, env=None):
 try:
  result=subprocess.run(args,input=secret,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout,env=env or ENV)
 except (OSError,subprocess.TimeoutExpired) as e: raise Refused('command_unconfirmed') from e
 require(result.returncode==0,'command_failed')
 return result.stdout
def plist(args, *, secret=None, timeout=30):
 try: return plistlib.loads(invoke(args,secret=secret,timeout=timeout))
 except (ValueError,TypeError) as e: raise Refused('invalid_image_metadata') from e
def attached_device(info,image,mount):
 """Return one exact device/mount binding; reject ambiguous or foreign records."""
 require(isinstance(info,dict) and isinstance(info.get('images'),list),'invalid_image_metadata')
 matches=[item for item in info['images'] if isinstance(item,dict) and item.get('image-path')==str(image)]
 require(len(matches)==1 and isinstance(matches[0].get('system-entities'),list),'image_identity_unconfirmed')
 entries=[e for e in matches[0]['system-entities'] if isinstance(e,dict) and e.get('mount-point')==str(mount)]
 require(len(entries)==1 and re.fullmatch(r'/dev/disk[0-9]+s[0-9]+',entries[0].get('dev-entry','')) is not None,'mount_identity_unconfirmed')
 return entries[0]['dev-entry']
def image_info(): return plist(['/usr/bin/hdiutil','info','-plist'])
def is_detached(info,image):
 require(isinstance(info,dict) and isinstance(info.get('images'),list),'invalid_image_metadata')
 return not any(isinstance(x,dict) and x.get('image-path')==str(image) for x in info['images'])
def pid_matches(path,pid,data,port,sock):
 try: lines=path.read_text().splitlines()
 except (OSError,UnicodeError):return False
 return len(lines)>=5 and lines[0]==str(pid) and lines[1]==str(data) and lines[3]==str(port) and lines[4]==str(sock)
def is_alive(pid):
 try:os.kill(pid,0);return True
 except ProcessLookupError:return False
 except PermissionError:return True
def write_all(fd,value):
 offset=0
 while offset<len(value):
  written=os.write(fd,memoryview(value)[offset:])
  if written<=0:raise OSError('short_write')
  offset+=written
def physical_executable(path):
 p=pathlib.Path(path);return p.is_absolute() and p.resolve()==p and p.is_file() and os.access(p,os.X_OK)
def checked_bins():
 pg=pathlib.Path(os.environ.get('COLLECT_SYNTHETIC_PG_BIN',DEFAULT_PG))
 require(pg.is_absolute() and pg.resolve()==pg and pg.is_dir(),'pg_bin_invalid')
 for name in ('initdb','postgres','pg_ctl','pg_isready'):
  require(physical_executable(pg/name),'pg_binary_invalid')
 version=invoke([str(pg/'postgres'),'--version'],timeout=5).decode('ascii','strict')
 require(re.search(r'\bPostgreSQL\)? 17\.',version) is not None,'pg17_required')
 require(physical_executable(NODE),'node_invalid')
 return pg
def interrupt(_signum,_frame):raise InterruptedError('synthetic_interrupted')

def main():
 require(sys.platform=='darwin' and os.geteuid()!=0 and len(sys.argv)==1,'synthetic_macos_only')
 require(BASE.resolve()==BASE and BASE.is_dir() and shutil.disk_usage(BASE).free>=2*1024**3,'scratch_unavailable')
 require(os.environ.get('COLLECT_ENCRYPTED_FIXTURE_TEST_PAUSE','') in ('','after_pg_ready'),'invalid_test_setting')
 require(os.environ.get('COLLECT_ENCRYPTED_FIXTURE_TEST_FAIL','') in ('','after_pg_ready') and not
  (os.environ.get('COLLECT_ENCRYPTED_FIXTURE_TEST_FAIL') and os.environ.get('COLLECT_ENCRYPTED_FIXTURE_TEST_PAUSE')),'invalid_test_setting')
 pg=checked_bins();os.umask(0o077)
 root=pathlib.Path(tempfile.mkdtemp(prefix='collect-encrypted-inert-',dir=str(BASE)))
 root_stat=root.lstat();require(root.resolve()==root and root_stat.st_uid==os.getuid() and root_stat.st_mode&0o777==0o700,'scratch_identity_unconfirmed')
 image=root/'fixture.sparseimage';mount=root/'mount';mount.mkdir(mode=0o700)
 data=mount/'data';sock=mount/'socket';log=mount/'postgres.log';pwfile=mount/'init-password'
 image_pass=bytearray(secrets.token_hex(32).encode('ascii')+b'\0')
 db_password=bytearray(secrets.token_hex(32).encode('ascii'))
 cluster='collect_inert_'+secrets.token_hex(12)
 device=None;server=None;server_log=None;start_attempted=False;attach_attempted=False;disk_inflight=None
 init_attempted=False;initialized=False;started=False;stop_confirmed=False;detach_confirmed=False
 completed=False;interrupted=False;reason=None;node_result=None;stage='image_create'
 handlers={s:signal.signal(s,interrupt) for s in (signal.SIGTERM,signal.SIGINT)}
 try:
  disk_inflight='image_create';invoke(['/usr/bin/hdiutil','create','-size','256m','-type','SPARSE','-fs','APFS','-encryption','AES-256','-stdinpass','-volname','CollectSyntheticRestore',str(image)],secret=image_pass,timeout=60);disk_inflight=None
  st=image.lstat();require(st.st_uid==os.getuid() and st.st_nlink==1 and image.resolve()==image and image.is_file() and not image.is_symlink(),'image_identity_unconfirmed')
  stage='image_verify';details=plist(['/usr/bin/hdiutil','imageinfo','-plist','-stdinpass',str(image)],secret=image_pass,timeout=30)
  backing=details.get('Backing Store Information',{})
  require(details.get('Format')=='SPRS' and backing.get('Class Name')=='CEncryptedEncoding' and backing.get('Encryption')=='AES-256','image_encryption_unconfirmed')
  stage='image_attach';attach_attempted=True
  disk_inflight='image_attach';attached=plist(['/usr/bin/hdiutil','attach','-plist','-nobrowse','-stdinpass','-mountpoint',str(mount),str(image)],secret=image_pass,timeout=60);disk_inflight=None
  device=attached_device({'images':[{'image-path':str(image),'system-entities':attached.get('system-entities')}]},image,mount)
  require(attached_device(image_info(),image,mount)==device,'mount_identity_unconfirmed')
  require(mount.stat().st_dev!=root.stat().st_dev,'mount_not_distinct')
  sock.mkdir(mode=0o700)
  fd=os.open(pwfile,os.O_CREAT|os.O_EXCL|os.O_WRONLY|getattr(os,'O_NOFOLLOW',0),0o600)
  password_line=bytearray(db_password);password_line.append(10)
  try:write_all(fd,password_line);os.fsync(fd)
  finally:password_line[:]=b'\0'*len(password_line);os.close(fd)
  env={**ENV,'TMPDIR':str(mount)}
  stage='initdb';init_attempted=True;invoke([str(pg/'initdb'),'-D',str(data),'--username=collect_inert_fixture','--auth-local=reject','--auth-host=scram-sha-256','--pwfile',str(pwfile),'--encoding=UTF8','--no-instructions'],timeout=60,env=env)
  initialized=True;pwfile.unlink()
  with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as probe:
   probe.bind(('127.0.0.1',0));port=probe.getsockname()[1]
  stage='postgres_start';server_log=open(log,'ab',buffering=0);os.chmod(log,0o600);start_attempted=True
  server=subprocess.Popen([str(pg/'postgres'),'-D',str(data),'-k',str(sock),'-p',str(port),'-c','listen_addresses=127.0.0.1','-c','unix_socket_permissions=0700','-c','cluster_name='+cluster],stdin=subprocess.DEVNULL,stdout=server_log,stderr=server_log,env=env)
  deadline=time.monotonic()+25
  while time.monotonic()<deadline and server.poll() is None:
   ready=subprocess.run([str(pg/'pg_isready'),'-h','127.0.0.1','-p',str(port),'-U','collect_inert_fixture','-d','postgres','-t','1','-q'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=3,env=env)
   if ready.returncode==0 and pid_matches(data/'postmaster.pid',server.pid,data,port,sock):started=True;break
   time.sleep(0.1)
  require(started,'postgres_start_unconfirmed')
  if os.environ.get('COLLECT_ENCRYPTED_FIXTURE_TEST_PAUSE')=='after_pg_ready':
   os.write(2,b'COLLECT_SYNTHETIC_ENCRYPTED_READY\n')
   while True:signal.pause()
  if os.environ.get('COLLECT_ENCRYPTED_FIXTURE_TEST_FAIL')=='after_pg_ready':raise Refused('synthetic_injected_failure')
  request=bytearray(json.dumps({'port':port,'password':db_password.decode('ascii'),'data':str(data),'cluster':cluster},separators=(',',':')).encode('utf8'))
  stage='fixture_restore';
  try:
   node_output=invoke([NODE,str(HERE/'restore-fixture.mjs')],secret=request,timeout=90,env=env)
  finally:request[:]=b'\0'*len(request)
  node_result=json.loads(node_output)
  require(node_result=={'format':'collect.encrypted-inert.synthetic.v1','synthetic':True,'real_archive_read':False,'tables':1,'rows':1,'native_cells_verified':True,'production_restore_authority':False},'fixture_result_unconfirmed')
  completed=True
 except InterruptedError:
  interrupted=True;reason='synthetic_interrupted'
 except (Refused,OSError,ValueError,subprocess.TimeoutExpired) as e:
  reason=str(e) if isinstance(e,Refused) else 'synthetic_qualification_unconfirmed'
 finally:
  for s,h in handlers.items():signal.signal(s,signal.SIG_IGN)
  if server is not None:
   if server.poll() is None:server.send_signal(signal.SIGINT)
   try:code=server.wait(timeout=15)
   except subprocess.TimeoutExpired:
    server.kill();server.wait(timeout=5);code=None
   if server_log:server_log.close()
   if code==0 and server.pid and not is_alive(server.pid) and initialized and not (data/'postmaster.pid').exists():
    try:
     status=subprocess.run([str(pg/'pg_ctl'),'-D',str(data),'status'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=5,env={**ENV,'TMPDIR':str(mount)})
     stop_confirmed=status.returncode==3
    except (OSError,subprocess.TimeoutExpired):stop_confirmed=False
  else:stop_confirmed=not start_attempted and (not init_attempted or initialized)
  if device and stop_confirmed and disk_inflight is None:
   try:
    require(attached_device(image_info(),image,mount)==device,'mount_identity_changed')
    invoke(['/usr/bin/hdiutil','detach',device],timeout=30)
    detach_confirmed=is_detached(image_info(),image) and mount.stat().st_dev==root.stat().st_dev
   except (Refused,OSError):detach_confirmed=False
  elif not attach_attempted and disk_inflight is None:detach_confirmed=True
  image_pass[:]=b'\0'*len(image_pass);db_password[:]=b'\0'*len(db_password)
  for s,h in handlers.items():signal.signal(s,h)
 cleanup_confirmed=stop_confirmed and detach_confirmed
 if cleanup_confirmed and (completed or interrupted):
  current=root.lstat()
  require(root.resolve()==root and current.st_dev==root_stat.st_dev and current.st_ino==root_stat.st_ino and not root.is_symlink(),'scratch_identity_changed')
  shutil.rmtree(root)
  require(not root.exists(),'scratch_cleanup_unconfirmed')
  result={'format':'collect.encrypted-inert.synthetic-qualification.v1','status':'passed' if completed else 'interrupted',
   'synthetic':True,'real_archive_read':False,'aes256_image_verified':True,'owned_postgres_stopped':True,
   'owned_image_detached':True,'owned_scratch_removed':True,'native_cells_verified':bool(completed),
   'production_restore_authority':False,'whole_system_recovery':False}
  print(json.dumps(result,separators=(',',':')),flush=True)
  return 0 if completed else 1
 result={'format':'collect.encrypted-inert.synthetic-qualification.v1','status':'unconfirmed',
  'code':reason or 'cleanup_unconfirmed','stage':stage,'preserved_synthetic_root':str(root),'owned_postgres_stopped':stop_confirmed,
  'owned_image_detached':detach_confirmed,'disk_operation_unconfirmed':disk_inflight is not None,'real_archive_read':False}
 try:
  current=root.lstat();require(root.resolve()==root and current.st_dev==root_stat.st_dev and current.st_ino==root_stat.st_ino and not root.is_symlink(),'scratch_identity_changed')
  fd=os.open(root/'RECOVERY.json',os.O_CREAT|os.O_EXCL|os.O_WRONLY|getattr(os,'O_NOFOLLOW',0),0o600)
  try:write_all(fd,(json.dumps(result,separators=(',',':'))+'\n').encode('utf8'));os.fsync(fd)
  finally:os.close(fd)
  fd=os.open(root,os.O_RDONLY|getattr(os,'O_NOFOLLOW',0))
  try:os.fsync(fd)
  finally:os.close(fd)
 except (OSError,Refused):result['diagnostic_write_unconfirmed']=True
 print(json.dumps(result,separators=(',',':')),flush=True)
 return 1

if __name__=='__main__':
 try:sys.exit(main())
 except (Refused,OSError,ValueError) as e:
  print(json.dumps({'status':'refused','code':str(e) if isinstance(e,Refused) else 'synthetic_qualification_unconfirmed','real_archive_read':False}),flush=True)
  sys.exit(1)

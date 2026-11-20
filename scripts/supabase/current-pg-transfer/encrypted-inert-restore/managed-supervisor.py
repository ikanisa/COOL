#!/usr/bin/env python3
"""Managed component encrypted-image local inert restore; never changes production.

Real capture mode requires independent pins and is not run by this test suite.
Preserve the owned scratch directory whenever cleanup cannot be confirmed.
"""
import argparse
import hashlib
import json
import os
import pathlib
import plistlib
import re
import select
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
REPO=HERE.parents[3]
PINS=None
BASE_FILES=[]
COMPONENT=None
EXPECTED={
 'auth':{'result':'452674e3d5e5b0aeb601d82ef7a54360f04bb6c5d723d4fff84af78fb3ab554f',
  'result_path':'/Users/jeanbosco/Library/Application Support/Collect-Cloud-Recovery/production-metadata-20261113-122116/auth-ciphertext/capture-20261113/RESULT.json',
  'copy':'/Volumes/T7/Collect-Cloud-Recovery/production-auth-20261113/auth.encrypted.archive.json',
  'ciphertext':'b5f60e2ab6153d93eeaed42a6176e968e0af7ed778b7866d1e0d7c0dd4b1405d',
  'snapshot':'5b47c4fb6230c819e0bbbbf644c73d06ca7dd34286c21a160952cd2a651a90e2'},
 'storage':{'result':'a4d02e403e80b6ee75f8194fe636f4b59e0e949c5ab0c64977cc46e20fb42a01',
  'result_path':'/Users/jeanbosco/Library/Application Support/Collect-Cloud-Recovery/production-metadata-20261113-122116/storage-v2-ciphertext/capture-20261113/RESULT.json',
  'copy':'/Volumes/T7/Collect-Cloud-Recovery/production-storage-metadata-20261113/storage-metadata.encrypted.archive.json',
  'ciphertext':'63e01bc62cc07d46db3537d52dad43ee9352d6212c2aa883eef62905c9405977',
  'snapshot':'337de2b96f9172ac4f20d016a70fcea3a7a604b165a8ef7893db8beca6d62c1e'}}
def configure(component):
 global COMPONENT,PINS,BASE_FILES
 require(component in ('auth','storage'),'component_invalid')
 COMPONENT=component
 PINS=HERE/('AUTH-SOURCE-PINS.json' if component=='auth' else 'STORAGE-SOURCE-PINS.json')
 component_dir='managed-auth-archive' if component=='auth' else 'managed-storage-archive-v2'
 entry='auth.mjs' if component=='auth' else 'storage.mjs'
 BASE_FILES=['scripts/supabase/current-pg-transfer/encrypted-inert-restore/managed-supervisor.py',
  'scripts/supabase/current-pg-transfer/encrypted-inert-restore/'+component+'-managed-restore.py',
  'scripts/supabase/current-pg-transfer/encrypted-inert-restore/managed-capture.mjs',
  'scripts/supabase/current-archive/bundle.mjs','scripts/supabase/current-archive/codec.mjs',
  'scripts/supabase/current-archive/restore.mjs','scripts/supabase/current-archive/sql.mjs',
  'scripts/supabase/package.json','scripts/supabase/package-lock.json']
 BASE_FILES+=['scripts/supabase/'+component_dir+'/'+n for n in (entry,'counts.mjs','REFERENCE.json','native-definition.mjs')]
PACKAGES=['pg','pg-connection-string','pg-pool','pg-protocol','pg-types','pgpass','pg-cloudflare',
 'pg-int8','postgres-array','postgres-bytea','postgres-date','postgres-interval','split2','xtend']

class Refused(Exception): pass
defer_interrupt=False
interrupt_pending=False
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
def file_sha(path):
 p=pathlib.Path(path);st=p.lstat()
 require(p.is_absolute() and p.resolve()==p and p.is_file() and not p.is_symlink() and st.st_nlink==1,'source_path_invalid')
 h=hashlib.sha256()
 with p.open('rb') as f:
  for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
 after=p.lstat();require((st.st_dev,st.st_ino,st.st_size,st.st_mtime_ns,st.st_ctime_ns)==
  (after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns,after.st_ctime_ns),'source_changed')
 return h.hexdigest()
def verify_binary(path,pins):
 binary=str(path)
 require(binary in pins and physical_executable(binary) and file_sha(binary)==pins[binary],'binary_pin_changed')
def source_paths():
 require(REPO.is_absolute() and REPO.resolve()==REPO,'source_root_invalid')
 paths=list(BASE_FILES)
 for name in PACKAGES:
  package=REPO/'scripts/supabase/node_modules'/name
  require(package.is_dir() and not package.is_symlink() and package.resolve()==package,'dependency_missing')
  for parent,dirs,files in os.walk(package,followlinks=False):
   require(all(not (pathlib.Path(parent)/d).is_symlink() for d in dirs),'dependency_symlink')
   for name2 in files:
    p=pathlib.Path(parent)/name2
    require(not p.is_symlink() and p.is_file(),'dependency_symlink')
    paths.append(str(p.relative_to(REPO)))
 return sorted(paths)
def verify_sources(expected,pg):
 require(re.fullmatch(r'[a-f0-9]{64}',expected or '') is not None and PINS.is_file() and not PINS.is_symlink(),'source_pin_required')
 data=PINS.read_bytes();require(len(data)<=1024*1024 and hashlib.sha256(data).hexdigest()==expected,'source_manifest_changed')
 try:pins=json.loads(data)
 except (ValueError,UnicodeDecodeError) as e:raise Refused('source_manifest_invalid') from e
 require(isinstance(pins,dict) and set(pins)=={'format','files','binaries'} and pins['format']=='collect.encrypted-inert.source-pins.v1' and
  isinstance(pins['files'],dict) and sorted(pins['files'])==source_paths() and isinstance(pins['binaries'],dict),'source_manifest_invalid')
 for name in sorted(pins['files']):
  require(re.fullmatch(r'[a-f0-9]{64}',pins['files'][name] or '') is not None and file_sha(REPO/name)==pins['files'][name],'source_changed')
 binaries=[NODE]+[str(pg/name) for name in ('initdb','postgres','pg_ctl','pg_isready')]
 require(sorted(pins['binaries'])==sorted(binaries),'binary_pin_changed')
 for binary in binaries:verify_binary(binary,pins['binaries'])
 return pins['binaries']
def checked_bins():
 pg=pathlib.Path(os.environ.get('COLLECT_SYNTHETIC_PG_BIN',DEFAULT_PG))
 require(pg.is_absolute() and pg.resolve()==pg and pg.is_dir(),'pg_bin_invalid')
 for name in ('initdb','postgres','pg_ctl','pg_isready'):
  require(physical_executable(pg/name),'pg_binary_invalid')
 require(physical_executable(NODE),'node_invalid')
 return pg
def check_pg_version(pg,pins):
 postgres=pg/'postgres'
 verify_binary(postgres,pins)
 version=invoke([str(postgres),'--version'],timeout=5).decode('ascii','strict')
 verify_binary(postgres,pins)
 require(re.search(r'\bPostgreSQL\)? 17\.',version) is not None,'pg17_required')
def interrupt(_signum,_frame):
 global interrupt_pending
 if defer_interrupt:interrupt_pending=True
 else:raise InterruptedError('restore_interrupted')

class PrivateArgumentParser(argparse.ArgumentParser):
 def error(self,_message):raise Refused('invalid_arguments')

def parse_args():
 parser=PrivateArgumentParser(add_help=False)
 parser.add_argument('--synthetic',action='store_true')
 parser.add_argument('--real-capture',action='store_true')
 parser.add_argument('--source-manifest-sha256',required=True)
 parser.add_argument('--capture-result')
 parser.add_argument('--capture-result-sha256')
 parser.add_argument('--ciphertext-copy')
 parser.add_argument('--ciphertext-sha256')
 parser.add_argument('--snapshot-sha256')
 try:args=parser.parse_args()
 except SystemExit as e:raise Refused('invalid_arguments') from e
 require(args.synthetic != args.real_capture,'invalid_arguments')
 if args.synthetic:require(all(x is None for x in (args.capture_result,args.capture_result_sha256,args.ciphertext_copy,args.ciphertext_sha256,args.snapshot_sha256)),'invalid_arguments')
 else:
  require(all(isinstance(x,str) and pathlib.Path(x).is_absolute() and str(pathlib.Path(x))==x and len(x)<=4096 for x in (args.capture_result,args.ciphertext_copy)) and
   all(re.fullmatch(r'[a-f0-9]{64}',x or '') is not None for x in (args.capture_result_sha256,args.ciphertext_sha256,args.snapshot_sha256)),'invalid_arguments')
 return args

def main(component):
 global defer_interrupt,interrupt_pending
 configure(component)
 require(sys.platform=='darwin' and os.geteuid()!=0,'macos_only')
 args=parse_args()
 if args.real_capture:
  require(args.capture_result==EXPECTED[component]['result_path'] and args.capture_result_sha256==EXPECTED[component]['result'] and args.ciphertext_copy==EXPECTED[component]['copy'] and
   args.ciphertext_sha256==EXPECTED[component]['ciphertext'] and args.snapshot_sha256==EXPECTED[component]['snapshot'],'capture_pin_mismatch')
 forbidden=re.compile(r'^(?:PG[A-Z0-9_]*|NODE_OPTIONS|NODE_PATH|NODE_EXTRA_CA_CERTS|NODE_TLS_REJECT_UNAUTHORIZED|PYTHONPATH|PYTHONHOME|SSL_[A-Z0-9_]*|OPENSSL_[A-Z0-9_]*|LD_[A-Z0-9_]*|DYLD_[A-Z0-9_]*)$',re.I)
 require(not any(forbidden.match(k) for k in os.environ),'unclean_environment')
 require(BASE.resolve()==BASE and BASE.is_dir() and shutil.disk_usage(BASE).free>=2*1024**3,'scratch_unavailable')
 pause=os.environ.get('COLLECT_ENCRYPTED_CAPTURE_TEST_PAUSE','');tamper=os.environ.get('COLLECT_ENCRYPTED_CAPTURE_TEST_TAMPER','')
 require(pause in ('','before_node_spawn','after_snapshot') and tamper in ('','result','receipt','ciphertext','key','snapshot') and
  not(pause and tamper) and (args.synthetic or not(pause or tamper)),'invalid_test_setting')
 pg=checked_bins();binary_pins=verify_sources(args.source_manifest_sha256,pg)
 check_pg_version(pg,binary_pins);os.umask(0o077)
 root=pathlib.Path(tempfile.mkdtemp(prefix='collect-encrypted-managed-',dir=str(BASE)))
 root_stat=root.lstat();require(root.resolve()==root and root_stat.st_uid==os.getuid() and root_stat.st_mode&0o777==0o700,'scratch_identity_unconfirmed')
 image=root/'archive-restore.sparseimage';mount=root/'mount';mount.mkdir(mode=0o700)
 data=mount/'data';sock=mount/'socket';log=mount/'postgres.log';pwfile=mount/'init-password'
 image_pass=bytearray(secrets.token_hex(32).encode('ascii')+b'\0')
 db_password=bytearray(secrets.token_hex(32).encode('ascii'))
 cluster='collect_inert_'+secrets.token_hex(12)
 device=None;server=None;server_log=None;node_child=None;node_stopped=True;start_attempted=False;attach_attempted=False;disk_inflight=None
 init_attempted=False;initialized=False;started=False;image_verified=False;stop_confirmed=False;detach_confirmed=False
 completed=False;interrupted=False;reason=None;node_result=None;child_stage=None;child_code=None;stage='image_create'
 handlers={s:signal.signal(s,interrupt) for s in (signal.SIGTERM,signal.SIGINT)}
 try:
  disk_inflight='image_create';invoke(['/usr/bin/hdiutil','create','-size','1g','-type','SPARSE','-fs','APFS','-encryption','AES-256','-stdinpass','-volname','CollectEncryptedArchiveRestore',str(image)],secret=image_pass,timeout=60);disk_inflight=None
  st=image.lstat();require(st.st_uid==os.getuid() and st.st_nlink==1 and image.resolve()==image and image.is_file() and not image.is_symlink(),'image_identity_unconfirmed')
  stage='image_verify';details=plist(['/usr/bin/hdiutil','imageinfo','-plist','-stdinpass',str(image)],secret=image_pass,timeout=30)
  backing=details.get('Backing Store Information',{})
  require(details.get('Format')=='SPRS' and backing.get('Class Name')=='CEncryptedEncoding' and backing.get('Encryption')=='AES-256','image_encryption_unconfirmed')
  image_verified=True
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
  stage='initdb';verify_binary(pg/'initdb',binary_pins);verify_binary(pg/'postgres',binary_pins)
  init_attempted=True;invoke([str(pg/'initdb'),'-D',str(data),'--username=collect_inert_fixture','--auth-local=reject','--auth-host=scram-sha-256','--pwfile',str(pwfile),'--encoding=UTF8','--no-instructions'],timeout=60,env=env)
  initialized=True;pwfile.unlink()
  with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as probe:
   probe.bind(('127.0.0.1',0));port=probe.getsockname()[1]
  stage='postgres_start';verify_binary(pg/'postgres',binary_pins)
  server_log=open(log,'ab',buffering=0);os.chmod(log,0o600);start_attempted=True
  defer_interrupt=True
  try:
   server=subprocess.Popen([str(pg/'postgres'),'-D',str(data),'-k',str(sock),'-p',str(port),'-c','listen_addresses=127.0.0.1','-c','unix_socket_permissions=0700','-c','cluster_name='+cluster,
    '-c','log_statement=none','-c','log_min_duration_statement=-1','-c','log_min_error_statement=panic','-c','log_parameter_max_length=0','-c','log_parameter_max_length_on_error=0'],
    stdin=subprocess.DEVNULL,stdout=server_log,stderr=server_log,env=env)
  finally:defer_interrupt=False
  if interrupt_pending:raise InterruptedError('restore_interrupted')
  deadline=time.monotonic()+25
  while time.monotonic()<deadline and server.poll() is None:
   verify_binary(pg/'pg_isready',binary_pins)
   ready=subprocess.run([str(pg/'pg_isready'),'-h','127.0.0.1','-p',str(port),'-U','collect_inert_fixture','-d','postgres','-t','1','-q'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=3,env=env)
   if ready.returncode==0 and pid_matches(data/'postmaster.pid',server.pid,data,port,sock):started=True;break
   time.sleep(0.1)
  require(started,'postgres_start_unconfirmed')
  stage='source_recheck';verify_sources(args.source_manifest_sha256,pg)
  request=bytearray(json.dumps({'port':port,'password':db_password.decode('ascii'),'data':str(data),'cluster':cluster,
   'mode':'synthetic' if args.synthetic else 'real','component':component,'resultPath':args.capture_result,'resultSha':args.capture_result_sha256,
   'copyPath':args.ciphertext_copy,'archiveSha':args.ciphertext_sha256,'snapshotSha':args.snapshot_sha256,
   'tamper':tamper,'pause':pause if pause=='after_snapshot' else ''},separators=(',',':')).encode('utf8'))
  stage='capture_restore';
  try:
   verify_binary(NODE,binary_pins)
   defer_interrupt=True
   try:
    if pause=='before_node_spawn':
     os.write(2,b'COLLECT_SYNTHETIC_ARCHIVE_SPAWN_READY\n')
     while not interrupt_pending:time.sleep(0.05)
    node_child=subprocess.Popen([NODE,str(HERE/'managed-capture.mjs')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
   finally:defer_interrupt=False
   node_stopped=False
   if interrupt_pending:raise InterruptedError('restore_interrupted')
   node_child.stdin.write(request);node_child.stdin.close();node_child.stdin=None
   if pause:
    ready,_,_=select.select([node_child.stderr],[],[],90)
    require(bool(ready) and node_child.stderr.readline()==b'COLLECT_SYNTHETIC_CAPTURE_AUTHENTICATED\n','capture_pause_unconfirmed')
    os.write(2,b'COLLECT_SYNTHETIC_ARCHIVE_AUTHENTICATED\n')
    while True:signal.pause()
   try:node_output,node_error=node_child.communicate(timeout=300)
   except subprocess.TimeoutExpired as e:raise Refused('restore_timeout_unconfirmed') from e
   node_stopped=True
   if node_child.returncode!=0 and args.synthetic:
    matched=re.fullmatch(rb'ENCRYPTED_INERT_RESTORE_REFUSED:(input|cluster|capture|ciphertext|authentication|restore|roundtrip)(?::([A-Z][A-Z0-9_]{0,79}))?\n',node_error)
    if matched:
     child_stage=matched.group(1).decode('ascii')
     if matched.group(2):child_code=matched.group(2).decode('ascii')
   require(node_child.returncode==0,'capture_restore_refused')
  finally:request[:]=b'\0'*len(request)
  node_result=json.loads(node_output)
  require(isinstance(node_result,dict) and set(node_result)=={'format','status','mode','component','capture_result_sha256','tables','rows','native_cells_verified','production_restore_authority','whole_system_recovery'} and
   node_result['format']=='collect.managed-capture.inert-restore.v1' and node_result['component']==component and node_result['status']=='verified' and
   node_result['mode']==('synthetic' if args.synthetic else 'real') and re.fullmatch(r'[a-f0-9]{64}',node_result['capture_result_sha256'] or '') and
   type(node_result['tables']) is int and 1<=node_result['tables']<=256 and type(node_result['rows']) is int and 0<=node_result['rows']<=50000 and
   node_result['native_cells_verified'] is True and node_result['production_restore_authority'] is False and node_result['whole_system_recovery'] is False and
   (args.synthetic or node_result['capture_result_sha256']==args.capture_result_sha256),'capture_result_unconfirmed')
  stage='source_postcheck';verify_sources(args.source_manifest_sha256,pg)
  completed=True
 except InterruptedError:
  interrupted=True;reason='restore_interrupted'
 except (Refused,OSError,ValueError,subprocess.TimeoutExpired) as e:
  reason=str(e) if isinstance(e,Refused) else 'restore_unconfirmed'
 finally:
  for s,h in handlers.items():signal.signal(s,signal.SIG_IGN)
  if node_child is not None and node_child.poll() is None:
   node_child.terminate()
   try:node_child.wait(timeout=10);node_stopped=True
   except subprocess.TimeoutExpired:
    node_child.kill();node_child.wait(timeout=5);node_stopped=False
  elif node_child is not None:node_stopped=True
  if server is not None:
   if server.poll() is None:server.send_signal(signal.SIGINT)
   try:code=server.wait(timeout=15)
   except subprocess.TimeoutExpired:
    server.kill();server.wait(timeout=5);code=None
   if server_log:server_log.close()
   if code==0 and server.pid and not is_alive(server.pid) and initialized and not (data/'postmaster.pid').exists():
    try:
     verify_binary(pg/'pg_ctl',binary_pins)
     status=subprocess.run([str(pg/'pg_ctl'),'-D',str(data),'status'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=5,env={**ENV,'TMPDIR':str(mount)})
     stop_confirmed=status.returncode==3
    except (Refused,OSError,subprocess.TimeoutExpired):stop_confirmed=False
  else:stop_confirmed=not start_attempted and (not init_attempted or initialized)
  if device and stop_confirmed and node_stopped and disk_inflight is None:
   try:
    require(attached_device(image_info(),image,mount)==device,'mount_identity_changed')
    invoke(['/usr/bin/hdiutil','detach',device],timeout=30)
    detach_confirmed=is_detached(image_info(),image) and mount.stat().st_dev==root.stat().st_dev
   except (Refused,OSError):detach_confirmed=False
  elif not attach_attempted and disk_inflight is None:detach_confirmed=True
  image_pass[:]=b'\0'*len(image_pass);db_password[:]=b'\0'*len(db_password)
  for s,h in handlers.items():signal.signal(s,h)
 cleanup_confirmed=node_stopped and stop_confirmed and detach_confirmed
 if cleanup_confirmed and (completed or interrupted):
  current=root.lstat()
  require(root.resolve()==root and current.st_dev==root_stat.st_dev and current.st_ino==root_stat.st_ino and not root.is_symlink(),'scratch_identity_changed')
  shutil.rmtree(root)
  require(not root.exists(),'scratch_cleanup_unconfirmed')
  result={'format':'collect.managed-capture.supervisor.v1','component':component,'status':'passed' if completed else 'interrupted',
   'mode':'synthetic' if args.synthetic else 'real','aes256_image_verified':image_verified,'owned_child_stopped':True,'owned_postgres_stopped':True,
   'owned_image_detached':True,'owned_scratch_removed':True,'native_cells_verified':bool(completed),
   'production_restore_authority':False,'whole_system_recovery':False}
  if completed:result.update({'capture_result_sha256':node_result['capture_result_sha256'],'tables':node_result['tables'],'rows':node_result['rows']})
  print(json.dumps(result,separators=(',',':')),flush=True)
  return 0 if completed else 1
 result={'format':'collect.managed-capture.supervisor.v1','component':component,'status':'unconfirmed','mode':'synthetic' if args.synthetic else 'real',
  'code':reason or 'cleanup_unconfirmed','stage':stage,'preserved_root':str(root),'owned_postgres_stopped':stop_confirmed,
  'owned_child_stopped':node_stopped,'owned_image_detached':detach_confirmed,'disk_operation_unconfirmed':disk_inflight is not None}
 if child_stage:result['synthetic_child_stage']=child_stage
 if child_code:result['synthetic_child_code']=child_code
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

def run(component):
 try:sys.exit(main(component))
 except (Refused,OSError,ValueError) as e:
  print(json.dumps({'status':'refused','code':str(e) if isinstance(e,Refused) else 'restore_unconfirmed'}),flush=True)
  sys.exit(1)

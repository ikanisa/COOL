"""Private proposal: copy only the root-qualified67 exact publisher JAR blobs."""
import argparse,datetime,hashlib,json,os,re,stat,sys,time,types,unicodedata
from pathlib import Path
HERE=Path(__file__).resolve().parent
RELEASE=HERE.parent
PRIVATE=Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1')
POOL=PRIVATE/'gradle-home/caches/modules-2/files-2.1'
INTAKE=Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/lint32-selected-publisher-binaries1')
COMPILER=('com.android.tools.external.com-intellij','kotlin-compiler','32.0.1')
RECOVERY_BODY=Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/lint32-selected-publisher-kotlin-compiler-recovery1/body')
ACTUAL=RELEASE/'root-lint32-combined-publisher-binaries1/readback.json'
ACTUAL_SHA='8b6caf02f7ed28afab84d95c7668ff712ffebe4e45652f5057f5a91ae0798e06'
OLD=INTAKE/'readback.json'
OLD_SHA='a1f97ca1a72ccf76b73fe7945c66144286e452f85d3fca37e6fb4dbe2c1ff67b'
RECOVERY=RELEASE/'root-lint32-kotlin-compiler-binary-recovery1/readback.json'
RECOVERY_SHA='3143b0a358b20d1b3a21a7aee52fbe15e688a8c0c5fa110f277b58ffebbab9b1'
DRIVER=RELEASE/'arc09-aab-driver-preparation1/argv-unavailable-recovery3/run_selected_aab.py'
DRIVER_SHA='76f587c54d8cfcb91d0ce584f4ee69ac99905b1ad313402ac2c82ce2fa6ed4f8'
READER=RELEASE/'kotlin-sdk-native-native-stage-preparation1/publisher_metadata.py'
READER_SHA='c21a475eae55b78997dbd944e6c97de1bd8e1df92f4f8696ede8ece198140b25'
PLAN=RELEASE/'arc09-lint32-binary-acquisition-preparation1/plan.json'
PLAN_SHA='690a27a55f7d0ffbedfdcdc48e0977dc8366b6e52049f0b3542ae4d6a02f9593'
sha=lambda body:hashlib.sha256(body).hexdigest()

def module(path,expected,name):
 raw=path.read_bytes()
 if sha(raw)!=expected:raise ValueError('Reviewed helper changed')
 loaded=types.ModuleType(name);loaded.__file__=str(path);exec(compile(raw,str(path),'exec'),loaded.__dict__);return loaded
reader=module(READER,READER_SHA,'held_source_policy')
identity=reader.identity

def due(deadline):
 if time.monotonic()>=deadline:raise TimeoutError('180-second admission work bound')

def safe_regular(path):
 path=Path(path)
 if not path.is_absolute() or path.resolve()!=path:raise ValueError('Symlink/nonphysical input')
 before=path.lstat()
 if not stat.S_ISREG(before.st_mode) or before.st_nlink!=1 or before.st_mode&(stat.S_ISUID|stat.S_ISGID):raise ValueError('Aliased/special source')
 return before

def held_digest(path,deadline,algorithms=('sha256','sha1')):
 before=safe_regular(path)
 if before.st_size>128*1024**2:raise ValueError('Exact JAR reader bound')
 fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW)
 try:
  if identity(os.fstat(fd))!=identity(before):raise ValueError('Source changed before FD read')
  digests={name:hashlib.new(name) for name in algorithms};total=0
  while True:
   due(deadline);chunk=os.read(fd,1024**2)
   if not chunk:break
   total+=len(chunk)
   for digest in digests.values():digest.update(chunk)
  if identity(os.fstat(fd))!=identity(before) or identity(path.lstat())!=identity(before):raise ValueError('Source changed during held read')
  os.lseek(fd,0,os.SEEK_SET)
  return {'path':path,'fd':fd,'stat':before,'bytes':total,'hashes':{name:d.hexdigest() for name,d in digests.items()}}
 except BaseException:os.close(fd);raise

def check_source(source):
 if identity(os.fstat(source['fd']))!=identity(source['stat']) or identity(source['path'].lstat())!=identity(source['stat']):raise ValueError('Held source replaced/modified')

def verify_source(source,artifact,item):
 if source['bytes']!=artifact['bytes'] or source['hashes']['sha256']!=artifact['sha256'] or source['hashes']['sha1']!=artifact['sha1']:raise ValueError('Actual publisher artifact bytes/digests differ')
 if item['publisher_declared_size'] is not None and source['bytes']!=item['publisher_declared_size']:raise ValueError('Publisher module size differs')
 if any(source['hashes'][name]!=value.lower() for name,value in item['publisher_declared_hashes'].items()):raise ValueError('Publisher module digest differs')

def alias_check(parent,name):
 aliases=[p.name for p in parent.iterdir() if unicodedata.normalize('NFC',p.name).casefold()==unicodedata.normalize('NFC',name).casefold()]
 if aliases and aliases!=[name]:raise ValueError('Destination case/Unicode alias')

def directory(path):
 if path.resolve()!=path or path.is_symlink() or not path.is_dir():raise ValueError('Nonphysical destination directory')
 return path.stat()

def destination(item,source,pool=POOL):
 c=item['coordinate'];parts=[c['group'],c['name'],c['version'],source['hashes']['sha1'],item['publisher_filename']]
 if any(not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._+-]*',p) or p in ('.','..') for p in parts) or not re.fullmatch('[0-9a-f]{40}',parts[3]) or not parts[-1].endswith('.jar'):raise ValueError('Unsafe exact blob coordinate/filename')
 leaf=pool.joinpath(*parts)
 if leaf.resolve()!=leaf:raise ValueError('Destination physical path differs')
 return leaf

def prevalidate_destination(target,source,deadline,pool=POOL):
 due(deadline);directory(pool);current=pool
 for part in target.relative_to(pool).parts[:-1]:
  if current.exists():alias_check(current,part)
  current=current/part
  if current.exists():directory(current)
 if target.parent.exists():alias_check(target.parent,target.name)
 if not target.exists():
  if target.is_symlink():raise ValueError('Dangling destination alias')
  return {'kind':'absent','path':str(target)}
 existing=held_digest(target,deadline)
 try:
  if existing['bytes']!=source['bytes'] or any(existing['hashes'][a]!=source['hashes'][a] for a in ('sha256','sha1')):raise ValueError('Existing destination mismatch; no overwrite permitted')
  return {'kind':'exact-existing','path':str(target),'stat_identity':identity(existing['stat']),'bytes':existing['bytes'],'sha256':existing['hashes']['sha256'],'sha1':existing['hashes']['sha1']}
 finally:os.close(existing['fd'])

def copy_held(source,target,expected,deadline,pool=POOL):
 due(deadline);check_source(source)
 if expected['kind']=='exact-existing':
  now=prevalidate_destination(target,source,deadline,pool)
  if now!=expected:raise ValueError('Existing reuse identity changed')
  return {'action':'reused-exact-existing','target':str(target),'after':now}
 # Held directory FDs prevent a replaced ancestor from redirecting an exclusive copy.
 dirflags=os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW;fd=os.open(pool,dirflags);parents=[(pool,fd,os.fstat(fd))];current=pool;out=None
 try:
  for part in target.relative_to(pool).parts[:-1]:
   due(deadline);directory(current);alias_check(current,part)
   try:os.mkdir(part,mode=0o755,dir_fd=fd)
   except FileExistsError:pass
   nextfd=os.open(part,dirflags,dir_fd=fd);current=current/part;st=os.fstat(nextfd);parents.append((current,nextfd,st))
   if identity(current.stat())!=identity(st):raise ValueError('Destination directory FD/name differs')
   fd=nextfd
  alias_check(current,target.name)
  out=os.open(target.name,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o644,dir_fd=fd);created=os.fstat(out);total=0
  os.fchmod(out,0o644);os.lseek(source['fd'],0,os.SEEK_SET)
  while True:
   due(deadline);check_source(source);chunk=os.read(source['fd'],1024**2)
   if not chunk:break
   offset=0
   while offset<len(chunk):
    due(deadline);n=os.write(out,chunk[offset:])
    if n<=0:raise OSError('Zero-progress blob write')
    offset+=n;total+=n
  check_source(source);due(deadline);os.fsync(out);st=os.fstat(out)
  if st.st_nlink!=1 or stat.S_IMODE(st.st_mode)!=0o644 or (st.st_dev,st.st_ino)!=(created.st_dev,created.st_ino) or total!=source['bytes']:raise ValueError('New blob FD identity/mode/bytes differ')
  if identity(target.lstat())!=identity(st):raise ValueError('New blob named leaf changed')
  os.close(out);out=None;due(deadline);os.fsync(fd)
  for path,parentfd,original in parents:
   currentst=directory(path)
   if (currentst.st_dev,currentst.st_ino)!=(original.st_dev,original.st_ino) or (os.fstat(parentfd).st_dev,os.fstat(parentfd).st_ino)!=(original.st_dev,original.st_ino):raise ValueError('Destination ancestor replaced')
  after=held_digest(target,deadline)
  try:
   if after['bytes']!=source['bytes'] or any(after['hashes'][a]!=source['hashes'][a] for a in ('sha256','sha1')):raise ValueError('Copied blob posthash differs')
   return {'action':'created-exclusive-blob','target':str(target),'bytes':after['bytes'],'sha256':after['hashes']['sha256'],'sha1':after['hashes']['sha1'],'mode':stat.S_IMODE(after['stat'].st_mode),'exclusive_nlink':after['stat'].st_nlink}
  finally:os.close(after['fd'])
 finally:
  if out is not None:os.close(out)
  for _,parentfd,_ in reversed(parents):os.close(parentfd)

def save(path,record):
 with path.open('x') as f:json.dump(record,f,indent=2,sort_keys=True);f.write('\n');f.flush();os.fsync(f.fileno())

def read_pinned(path,expected):
 proof,body=reader.stable_read(path,True)
 if proof['sha256']!=expected:raise ValueError('Pinned document hash differs')
 return json.loads(body),proof

def inactive(driver,config,output,deadline):
 # The reviewed tracker is used read-only; no refresh thread, signal, Gradle or stop API.
 tracker=driver.DaemonTracker(types.SimpleNamespace(config=config),output,'admission-no-spawn');tracker.cleanup_deadline=deadline;rows=driver.process_table(deadline);active=[]
 for row in rows.values():
  if tracker.private_identity(row) is not None:active.append(row)
  command=row['command']
  if str(PRIVATE/'app-source/android/gradle/wrapper/gradle-wrapper.jar') in command or ('gradle' in command.lower() and (str(PRIVATE/'gradle-home') in command or str(PRIVATE/'app-source') in command) and row['pid']!=os.getpid()):active.append(row)
 record={'observed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'active_private_Gradle_rows':active,'process_table_count':len(rows),'private_Gradle_active':bool(active),'observer_error':None,'root_serialization_required_between_observations':True}
 return record

def observe_inactive(observations,driver,config,output,deadline):
 try:record=inactive(driver,config,output,deadline)
 except BaseException as error:
  observations.append({'observed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'private_Gradle_active':None,'observer_error':{'type':type(error).__name__,'error':str(error)},'absence_not_established':True});raise
 observations.append(record)
 if record['private_Gradle_active']:raise ValueError('Private Gradle process active; no stop attempted')

def key(row):return tuple(row['coordinate'][k] for k in ('group','name','version'))

def qualify(readback,plan):
 if readback['kind']!='root_combined_actual_publisher_intake_66_verified_plus_one_recovery' or readback['status']!='PASS_PUBLISHER_JAR_INTAKE_ONLY' or any(readback[k] is not True for k in ('owned_processes_absent','owned_lifecycle_complete','all_owned_groups_absent')) or readback['unreaped_or_unqualified_owned_groups'] or readback['full_graph_admission'] is not False or readback['shared_Gradle_cache_writes']!=0 or readback['plan_sha256']!=PLAN_SHA:raise ValueError('Actual combined acquisition state incomplete')
 old,_=read_pinned(OLD,OLD_SHA);recovery,_=read_pinned(RECOVERY,RECOVERY_SHA)
 if readback['original_acquisition']['path']!=str(OLD) or readback['original_acquisition']['sha256']!=OLD_SHA or readback['original_acquisition']['status']!='FAIL_OR_INCOMPLETE' or readback['original_acquisition']['original_failure_preserved'] is not True or readback['single_recovery']['path']!=str(RECOVERY) or readback['single_recovery']['sha256']!=RECOVERY_SHA:raise ValueError('Preserved actual phases differ')
 if old['status']!='FAIL_OR_INCOMPLETE' or old['all_owned_groups_absent'] is not True or old['owned_processes_absent'] is not True or recovery['status']!='PASS_SINGLE_PUBLISHER_JAR_INTAKE_ONLY' or recovery['owned_group_absent'] is not True or recovery['errors'] or recovery['full_graph_admission'] is not False or recovery['shared_Gradle_cache_writes']!=0:raise ValueError('Actual separate phase lifecycle differs')
 artifacts=readback['artifacts'];items=plan['items'];bykey={key(r):r for r in artifacts};oldkey={key(r):r for r in old['artifacts']}
 if len(artifacts)!=67 or len(items)!=67 or len(bykey)!=67 or set(bykey)!={key(r) for r in items}:raise ValueError('Exact67 selected artifacts required')
 for item in items:
  k=key(item);artifact=bykey[k]
  if artifact!=(recovery['artifact'] if k==COMPILER else oldkey[k]):raise ValueError('Combined actual artifact diverged from pinned separate phase')
  if artifact['complete'] is not True or artifact['publisher_SHA1_verified'] is not True or artifact['errors'] or artifact['filename']!=item['publisher_filename'] or artifact['publisher_URL']!=item['publisher_binary_URL'] or artifact['selected_owner']!=item['actual_selected_variant']['owner'] or (artifact['type'],artifact['extension'],artifact['classifier'])!=('jar','jar',None) or artifact['module_declared_hashes']!=item['publisher_declared_hashes'] or artifact['module_declared_size']!=item['publisher_declared_size']:raise ValueError('Exact publisher artifact qualification differs')
  path=Path(artifact['body_path'])
  if k==COMPILER:
   if path!=RECOVERY_BODY:raise ValueError('Wrong exact compiler recovery body')
  elif path.parent.parent.parent!=INTAKE or path.name!='body' or path.parent.parent.name!='requests' or not re.fullmatch('[0-9]{4}',path.parent.name):raise ValueError('Wrong owned original body leaf')
 return bykey

def preparation_inputs(preparation,deadline):
 for row in preparation['inputs']:
  due(deadline);proof,_=reader.stable_read(Path(row['path']))
  if proof['sha256']!=row['sha256'] or proof['bytes']!=row['bytes']:raise ValueError('Exact preparation input drift')

def main():
 p=argparse.ArgumentParser();p.add_argument('--actual-readback',type=Path,required=True);p.add_argument('--actual-readback-sha256',required=True);p.add_argument('--plan-sha256',required=True);p.add_argument('--preparation-sha256',required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--preflight-only',action='store_true');a=p.parse_args();started=time.monotonic();deadline=started+180
 preparation,_=read_pinned(HERE/'inputs.json',a.preparation_sha256)
 if a.plan_sha256!=PLAN_SHA or a.actual_readback!=ACTUAL or a.actual_readback_sha256!=ACTUAL_SHA:raise ValueError('Reviewed exact plan/combined intake pin differs')
 if Path(sys.executable).resolve()!=Path(preparation['Python']['path']).resolve():raise ValueError('Pinned Python executable differs')
 preparation_inputs(preparation,deadline);readback,_=read_pinned(ACTUAL,ACTUAL_SHA);plan,_=read_pinned(PLAN,PLAN_SHA);bykey=qualify(readback,plan)
 output=a.output
 if not output.is_absolute() or output.resolve()!=output or output.parent!=(HERE if a.preflight_only else RELEASE) or output.exists():raise ValueError('Fresh physical owned output required')
 output.mkdir(mode=0o700);held=[];attempts=[];actions=[];errors=[];observations=[];all_inputs_unchanged=False
 try:
  driver=module(DRIVER,DRIVER_SHA,'qualified_daemon_observer');config,_=read_pinned(RELEASE/'kotlin-sdk-native-native-stage-preparation1/proposed-commands.json',preparation['config_sha256'])
  observe_inactive(observations,driver,config,output,deadline);destinations=set();inode_set=set();total=0
  for item in plan['items']:
   due(deadline);artifact=bykey[key(item)];source=held_digest(Path(artifact['body_path']),deadline,tuple({'sha256','sha1',*item['publisher_declared_hashes']}));held.append(source);verify_source(source,artifact,item);inode=(source['stat'].st_dev,source['stat'].st_ino)
   if inode in inode_set:raise ValueError('Source alias across artifacts')
   inode_set.add(inode);total+=source['bytes']
   if total>512*1024**2:raise ValueError('Total admission source byte bound')
   target=destination(item,source)
   if str(target).casefold() in destinations:raise ValueError('Duplicate destination alias')
   destinations.add(str(target).casefold());expected=prevalidate_destination(target,source,deadline);source.update(item=item,artifact=artifact,target=target,expected_destination=expected)
  if total!=readback['complete_JAR_bytes']:raise ValueError('Combined67 physical byte total differs')
  save(output/'prevalidation.json',{'status':'PASS_ALL67_BEFORE_ANY_CACHE_WRITE','sources':[{'coordinate':s['item']['coordinate'],'source':str(s['path']),'bytes':s['bytes'],'hashes':s['hashes'],'identity':identity(s['stat']),'destination':s['expected_destination']} for s in held],'total_bytes':total,'all_actual_sources_held_FD':True,'actual_readback_sha256':ACTUAL_SHA,'plan_sha256':PLAN_SHA})
  observe_inactive(observations,driver,config,output,deadline)
  if not a.preflight_only:
   for index,source in enumerate(held):
    due(deadline);check_source(source);attempt={'index':index,'coordinate':source['item']['coordinate'],'source':str(source['path']),'destination':str(source['target']),'expected':source['expected_destination']};attempts.append(attempt);save(output/('attempt-'+str(index).zfill(2)+'.json'),attempt)
    result=copy_held(source,source['target'],source['expected_destination'],deadline);actions.append(result);save(output/('admitted-'+str(index).zfill(2)+'.json'),result)
  observe_inactive(observations,driver,config,output,deadline)
  for source in held:check_source(source)
  preparation_inputs(preparation,deadline);read_pinned(HERE/'inputs.json',a.preparation_sha256);all_inputs_unchanged=True
 except BaseException as error:errors.append({'type':type(error).__name__,'error':str(error)})
 finally:
  # Deadline-independent diagnostic work is metadata-only and at most67 lstat calls.
  # Never re-read JAR bodies outside the180-second work bound, and never delete partials.
  partial=[]
  for attempted in attempts:
   target=Path(attempted['destination'])
   try:
    st=target.lstat();completed=next((r for r in actions if r['target']==str(target)),None);partial.append({'path':str(target),'lstat_identity':identity(st),'mode':stat.S_IMODE(st.st_mode),'bytes_at_final_lstat':st.st_size,'corresponding_action_complete':completed is not None,'completed_after_hash_evidence':completed,'uncompleted_leaf_hash_not_claimed':completed is None})
   except FileNotFoundError:partial.append({'path':str(target),'exists_at_final_lstat':False})
   except BaseException as error:partial.append({'path':str(target),'error':str(error)})
  for source in held:os.close(source['fd'])
  passed=not errors and all_inputs_unchanged and (a.preflight_only or len(actions)==67)
  save(output/'readback.json',{'schema_version':1,'status':('PASS_ALL67_NO_CACHE_WRITE_PREFLIGHT' if a.preflight_only else 'PASS_STANDARD_VERIFIED_BLOB_COPY_ONLY') if passed else 'FAIL_OR_INCOMPLETE','actual_seconds':time.monotonic()-started,'work_seconds':180,'actual_readback_sha256':ACTUAL_SHA,'plan_sha256':PLAN_SHA,'preparation_sha256':a.preparation_sha256,'preflight_only':a.preflight_only,'all67_inputs_unchanged':all_inputs_unchanged,'actual_attempts':attempts,'actual_actions':actions,'actual_partial_manifest':partial,'errors':errors,'Gradle_process_observations':observations,'only_standard_files2_1_JAR_blob_destinations_written':True,'existing_mismatches_not_overwritten_or_deleted':True,'metadata_POM_version_dependency_source_writes':False,'full_graph_admission':False,'normal_full_Gradle_artifact_components_edges_POM_variant_comparison_required':True,'lint_AAB_license_release_claim':False})
 return 1 if errors else 0
if __name__=='__main__':raise SystemExit(main())

"""One exact unedited QA39 on the prepared pinned Linux runtime; local synthetic scope."""
from pathlib import Path
import hashlib,json,os,stat,time,types,datetime
HERE=Path(__file__).resolve().parent
RELEASE=HERE.parent
PREP=RELEASE/'pg39-linux-runtime-preparation2'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def load(path,digest,name):
 raw=path.read_bytes()
 if path.resolve()!=path or hashlib.sha256(raw).hexdigest()!=digest:raise ValueError('module identity differs')
 m=types.ModuleType(name);m.__file__=str(path);exec(compile(raw,str(path),'exec'),m.__dict__);return m
m=load(PREP/'prepare_runtime.py','5a9227329c2c675ea3a07e919895cb94312b94d50e46b52b6e143a3ab7267034','linux_inventory')
m.OUT=HERE
c=load(RELEASE/'kotlin-sdk-native-native-stage-preparation1/run_native_consumer.py','167d48b4e756043a87621feffcabccb41aca108232cfb943914b69fc5b090fe7','bounded_linux_run')
metadata=load(RELEASE/'kotlin-sdk-native-consumer-preparation1/publisher_metadata.py','c21a475eae55b78997dbd944e6c97de1bd8e1df92f4f8696ede8ece198140b25','linux_reader')
c.reader=lambda:metadata
manifest=json.loads((PREP/'packet-files.json').read_bytes())
if sha(PREP/'packet-files.json')!='3c37a165364ca5422e9a3d9101f135454718034fef13607de679df1e99213b43':raise ValueError('preparation differs')
for row in manifest['files']:
 p=PREP/row['path']
 if p.resolve()!=p or sha(p)!=row['sha256'] or p.stat().st_size!=row['bytes']:raise ValueError('preparation leaf differs')
p=PREP/'root-owned-qa39-proposal.json'
if sha(p)!='5918a959a48b17b9ddfb4ae3cb89e148232b3a944e03fca7e6e86e83fa005121':raise ValueError('proposal differs')
proposal=json.loads(p.read_bytes());argv=proposal['argv']
index=next(i for i,x in enumerate(argv)if x.startswith('--tmpfs='));argv[index]=argv[index].replace(':rw,nosuid',':rw,exec,nosuid')
output=Path(proposal['output_directory_to_create_exclusive_0700']);runtime=output.parent/'usr-local';source=output.parent/'source'
expected=json.loads((PREP/'source-before.json').read_bytes());expected_runtime=json.loads((PREP/'runtime-copied-inventory.json').read_bytes())
expected_images=json.loads((PREP/'images-before.stdout').read_bytes())
errors=[];process=None;cleanup_verified=False;owned_id=None;started=time.monotonic();cleanup_deadline=None
def emit(name,value):m.emit(HERE/name,value)
def run(name,args,seconds=15,required=True):
 if cleanup_deadline is not None:
  remaining=cleanup_deadline-time.monotonic()
  if remaining<=0:raise TimeoutError('cleanup30 bound reached')
  seconds=min(seconds,remaining)
 result=c.run_process(HERE,name,args,seconds,m.ROOT,dict(os.environ))
 if required and(result['exit_code']!=0 or not result['owned_process_group_absent'] or result['timed_out']):raise ValueError(name+' failed')
 return result

def observations(label):
 current=m.current_inputs()
 if current!=expected:raise ValueError('maintained source differs')
 for row in expected:
  p=source/row['path'];info=p.lstat()
  if not stat.S_ISREG(info.st_mode) or info.st_nlink!=1 or(sha(p),info.st_size,stat.S_IMODE(info.st_mode))!=(row['sha256'],row['bytes'],row['mode']):raise ValueError('captured source differs')
 observed=m.host_runtime_inventory(runtime)
 if observed!=expected_runtime:raise ValueError('runtime differs')
 run('images-'+label,[m.DOCKER,'image','inspect',m.PY_IMAGE,m.BASE_IMAGE])
 images=json.loads((HERE/('images-'+label+'.stdout')).read_bytes())
 if images!=expected_images:raise ValueError('image identity/platform/layers differ')
 emit('source-'+label+'.json',current)
 emit('runtime-'+label+'.json',{'exact_entries':len(observed),'unchanged':True})
try:
 if os.path.lexists(output):raise ValueError('output already exists')
 r=run('container-preabsence',[m.DOCKER,'inspect','--type=container',proposal['container_name']],required=False)
 if r['exit_code']==0 or not r['owned_process_group_absent']:raise ValueError('proposed container already exists/absence unknown')
 observations('before');output.mkdir(mode=0o700)
 emit('admitted-command.json',{'argv':argv,'original39_unedited':True,'tmpfs_exec_for_original_shebang_fixtures':True,'runtime_and_sources_readonly':True,'deadline_seconds':120,'cleanup_seconds':30,'shipping_acceptance':False})
 process=run('actual39',argv,120)
 raw=(HERE/'actual39.stderr').read_text()
 if 'Ran 39 tests in ' not in raw or not raw.rstrip().endswith('OK'):raise ValueError('all39 unittest completion absent')
except BaseException as error:
 errors.append({'phase':'execution','type':type(error).__name__,'message':str(error)})
finally:
 cleanup_deadline=time.monotonic()+30
 try:
  r=run('container-final-inspect',[m.DOCKER,'inspect','--type=container',proposal['container_name']],required=False)
  if r['exit_code']==0:
   data=json.loads((HERE/'container-final-inspect.stdout').read_bytes())[0]
   if data['Name']!='/'+proposal['container_name'] or data['Config']['Image']!=m.BASE_IMAGE or data['Config'].get('Labels',{}).get('com.collect.pg39.owner')!='root-pg39-linux-execution1':raise ValueError('container owner differs')
   owned_id=data['Id']
   emit('actual-container-state.json',{'id':owned_id,'image':data['Image'],'state':data['State'],'label':data['Config']['Labels']})
   if data['State']['Running'] or data['State']['ExitCode']!=0:errors.append({'phase':'container_completion','state':data['State']})
   run('container-remove',[m.DOCKER,'rm','-f',owned_id],10)
  r=run('container-postabsence',[m.DOCKER,'inspect','--type=container',proposal['container_name']],required=False)
  if r['exit_code']==0 or not r['owned_process_group_absent']:raise ValueError('container absence not proven')
  cleanup_verified=True
  observations('after')
 except BaseException as error:errors.append({'phase':'cleanup_readback','type':type(error).__name__,'message':str(error)})
if time.monotonic()-started>150:errors.append({'phase':'whole_deadline','message':'whole150 exceeded'})
terminal={'status':'pass'if not errors else'failed','errors':errors,'actual_tests':39 if process and not errors else None,'source_and_runtime_before_after_unchanged':not errors,'owned_container_removed_and_absent':cleanup_verified,'owned_id':owned_id,'whole_seconds':time.monotonic()-started,'finished_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'macOS_failures_resolved':False,'shipping_adapter_acceptance':False,'production_release_approval':False}
emit('terminal.json',terminal)
files=[{'path':str(p.relative_to(HERE)),'sha256':sha(p),'bytes':p.stat().st_size}for p in sorted(HERE.rglob('*'))if p.is_file()]
emit('packet-files.json',{'files':files})
print(json.dumps(terminal));raise SystemExit(0 if not errors else 1)

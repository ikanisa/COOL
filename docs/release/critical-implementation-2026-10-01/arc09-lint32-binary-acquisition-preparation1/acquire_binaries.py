"""Private reviewed proposal: publisher JAR intake only, no shared cache admission."""
import argparse,concurrent.futures,datetime,hashlib,json,os,re,signal,stat,subprocess,sys,threading,time,urllib.parse,zipfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
PYTHON=Path('/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3')
REPOS=('https://dl.google.com/dl/android/maven2/','https://repo.maven.apache.org/maven2/')
MAX_JAR=128*1024**2;TOTAL=512*1024**2;META=65536;OVERHEAD=3*META;WORK=180;CLEANUP=2;REQUEST=30
sha=lambda b:hashlib.sha256(b).hexdigest()

def stable(path,expected=None,max_bytes=8*1024**2):
 path=Path(path)
 if path.resolve()!=path or not path.is_file() or path.is_symlink():raise ValueError('Nonphysical regular input')
 before=path.stat()
 if before.st_size>max_bytes:raise ValueError('Input bound')
 with os.fdopen(os.open(path,os.O_RDONLY|os.O_NOFOLLOW),'rb') as f:
  held=os.fstat(f.fileno());raw=f.read(max_bytes+1);after=os.fstat(f.fileno())
 identity=lambda s:(s.st_dev,s.st_ino,s.st_size,s.st_mode,s.st_mtime_ns,s.st_ctime_ns)
 if identity(before)!=identity(held) or identity(before)!=identity(after) or identity(before)!=identity(path.stat()) or len(raw)>max_bytes:raise ValueError('Input changed during read')
 if expected is not None and sha(raw)!=expected:raise ValueError('Input SHA256 differs: '+str(path))
 return raw

def save(path,obj):
 with path.open('x') as f:json.dump(obj,f,indent=2,sort_keys=True);f.write('\n');f.flush();os.fsync(f.fileno())

def record(path):
 raw=stable(path,max_bytes=MAX_JAR);return {'path':str(path),'bytes':len(raw),'sha256':sha(raw)}

def safe_item(item):
 c=item['coordinate'];name=item['publisher_filename']
 for k in ['group','name','version']:
  if re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*',c[k]) is None or 'SNAPSHOT' in c[k].upper():raise ValueError('Unsafe/nonfixed coordinate')
 expected=c['name']+'-'+c['version']+'.jar'
 if name!=expected or '/' in name or '\\' in name or len(name)>200:raise ValueError('Unexpected filename/classifier')
 suffix=c['group'].replace('.','/')+'/'+c['name']+'/'+c['version']+'/'+name
 if not any(item['publisher_binary_URL']==repo+suffix for repo in REPOS):raise ValueError('Unsafe binary URL or coordinate')
 if item['publisher_binary_SHA1_sidecar_URL']!=item['publisher_binary_URL']+'.sha1':raise ValueError('Unexpected sidecar URL')
 if item['actual_selected_variant']['owner']!=':'.join(c[k] for k in ['group','name','version']):raise ValueError('Actual selected owner mismatch')
 if item['source_kind'] not in ['publisher_selected_module_variant','verified_official_module404_standard_Maven_Gradle9.1_unclassified_JAR_contract']:raise ValueError('Unsupported proof kind')
 size=item['publisher_declared_size']
 if size is not None and (type(size) is not int or size<1 or size>MAX_JAR):raise ValueError('Declared size outside intake bound')
 for algorithm,value in item['publisher_declared_hashes'].items():
  if algorithm not in ['sha1','sha256','sha512','md5'] or re.fullmatch('[0-9a-fA-F]{'+str(hashlib.new(algorithm).digest_size*2)+'}',value) is None:raise ValueError('Unsupported hash declaration')

def checksum(raw,URL):
 text=raw.decode('ascii').strip()
 if re.fullmatch('[0-9a-fA-F]{40}',text):return text.lower()
 match=re.fullmatch(r'([0-9a-fA-F]{40})[ \t]+([^\r\n]+)',text)
 expected=urllib.parse.urlsplit(URL).path
 if not match or not match.group(2).endswith(expected) or '/maven2/' not in expected:raise ValueError('SHA1 sidecar format/path mismatch')
 path=match.group(2)
 if path.endswith(' '+expected) or '..' in path.split('/') or '\x00' in path:raise ValueError('Unsafe named SHA1 sidecar')
 return match.group(1).lower()

def content_length(headers,actual):
 values=[v for k,v in headers if k.lower()=='content-length']
 if len(values)!=1 or re.fullmatch('[0-9]+',values[0]) is None or int(values[0])!=actual:raise ValueError('Content-Length absent/ambiguous/differs')
 if any(k.lower()=='content-encoding' and v.lower() not in ['identity'] for k,v in headers):raise ValueError('Encoded artifact response unsupported')
 if any(k.lower()=='transfer-encoding' for k,v in headers):raise ValueError('Transfer encoding unsupported for exact intake')
 return actual

def verify_jar(path,deadline):
 crc_bytes=0
 with zipfile.ZipFile(path) as jar:
  entries=jar.infolist()
  if not entries or len(entries)>200000:raise ValueError('JAR entry bound')
  names=set()
  total=sum(i.file_size for i in entries)
  if total>2*1024**3:raise ValueError('JAR inflated size bound')
  for info in entries:
   if time.monotonic()>=deadline:raise TimeoutError('Global180-second verification deadline')
   name=info.filename
   if name in names or name.startswith('/') or '\\' in name or '\x00' in name or any(s in ['.','..'] for s in name.split('/')) or re.match(r'^[A-Za-z]:',name):raise ValueError('Unsafe/duplicate JAR member')
   names.add(name);mode=(info.external_attr>>16)&0o170000
   if mode==stat.S_IFLNK or info.flag_bits&1:raise ValueError('JAR symlink/encryption unsupported')
   if info.is_dir():continue
   with jar.open(info) as stream:
    while True:
     if time.monotonic()>=deadline:raise TimeoutError('Global180-second CRC deadline')
     chunk=stream.read(65536)
     if not chunk:break
     crc_bytes+=len(chunk)
 return {'entries':len(entries),'uncompressed_bytes':total,'CRC_bytes_read':crc_bytes,'all_entries_CRC_verified':True,'safe_paths_no_extraction':True}

class Budget:
 def __init__(self,deadline):self.deadline=deadline;self.condition=threading.Condition();self.used=0;self.reserved=0
 def reserve(self,size):
  with self.condition:
   while self.used+self.reserved+size>TOTAL:
    remaining=self.deadline-time.monotonic()
    if remaining<=0:raise TimeoutError('180-second intake budget wait')
    if self.reserved==0:raise ValueError('512MiB total intake budget exhausted')
    self.condition.wait(timeout=min(0.1,remaining))
   if time.monotonic()>=self.deadline:raise TimeoutError('180-second request admission deadline')
   self.reserved+=size
 def release(self,reservation,actual):
  with self.condition:
   if actual>reservation or actual<0:raise ValueError('Observed intake exceeds exact reservation')
   self.reserved-=reservation;self.used+=actual;self.condition.notify_all()
   if self.used+self.reserved>TOTAL:raise ValueError('512MiB global intake exceeded')

class Intake:
 def __init__(self,output,deadline,worker_sha):self.output=output;self.deadline=deadline;self.worker_sha=worker_sha;self.budget=Budget(deadline);self.lock=threading.Lock();self.next=0;self.active={};self.requests=[]
 def request(self,URL,max_bytes):
  reservation=max_bytes+OVERHEAD;self.budget.reserve(reservation)
  with self.lock:self.next+=1;n=self.next
  folder=self.output/'requests'/str(n).zfill(4);folder.mkdir(mode=0o700);body=folder/'body';argv=[str(PYTHON),'-I','-B',str(HERE/'request_worker.py'),'--url',URL,'--body',str(body),'--max-bytes',str(max_bytes),'--seconds',str(min(REQUEST,max(0.001,self.deadline-time.monotonic())))];p=None;raw=b'';errors=b'';timed=False;t=time.monotonic();actual=0
  try:
   stable(HERE/'request_worker.py',self.worker_sha)
   p=subprocess.Popen(argv,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True,env={'PATH':'/usr/bin:/bin','LC_ALL':'C'})
   with self.lock:self.active[p.pid]=p
   try:raw,errors=p.communicate(timeout=max(0.001,min(REQUEST,self.deadline-time.monotonic())))
   except subprocess.TimeoutExpired:
    timed=True
    try:os.killpg(p.pid,signal.SIGTERM)
    except ProcessLookupError:pass
    cleanup_deadline=time.monotonic()+CLEANUP
    try:raw,errors=p.communicate(timeout=min(1,max(0.001,cleanup_deadline-time.monotonic())))
    except subprocess.TimeoutExpired:
     try:os.killpg(p.pid,signal.SIGKILL)
     except ProcessLookupError:pass
     try:raw,errors=p.communicate(timeout=max(0.001,cleanup_deadline-time.monotonic()))
     except subprocess.TimeoutExpired as failed:raw=failed.output or b'';errors=failed.stderr or b''
   absent=False
   try:os.killpg(p.pid,0)
   except ProcessLookupError:absent=True
   if len(raw)>OVERHEAD or len(errors)>META:raise ValueError('Transport receipt output bound')
   try:transport=json.loads(raw) if raw else None
   except (ValueError,TypeError):transport=None
   size=body.stat().st_size if body.exists() else 0
   actual=size+(transport.get('HTTP_header_bytes',META) if transport else META)+min(len(raw)+len(errors),2*META)
   if size>max_bytes:raise ValueError('Request body outside bound')
   receipt={'request':n,'URL':URL,'argv':argv,'owned_PID_PGID':p.pid,'owned_group_absent':absent,'owned_wrapper_reaped':p.poll() is not None,'exit_code':p.returncode,'timed_out':timed,'actual_seconds':time.monotonic()-t,'request_seconds':REQUEST,'separate_reap_seconds':CLEANUP,'transport':transport,'stdout_sha256':sha(raw),'stderr_sha256':sha(errors),'body':record(body) if body.exists() else None,'observed_intake_bytes':actual}
   save(folder/'receipt.json',receipt)
   with self.lock:self.requests.append(receipt)
   if timed or p.returncode or not absent or not transport or transport['error'] or not transport.get('curl_child_reaped',False) or transport['HTTP_status']!=200 or transport['curl_exit_code']!=0:raise ValueError('HTTP request failed; preserved exact receipt')
   content_length(transport['headers'],size)
   return receipt,body
  finally:
   with self.lock:
    if p is not None and p.poll() is not None:
     try:os.killpg(p.pid,0)
     except ProcessLookupError:self.active.pop(p.pid,None)
   # Charge partial body/header intake even when JSON/output validation failed.
   partial_size=body.stat().st_size if body.exists() else 0
   actual=max(actual,partial_size+min(META,OVERHEAD)+min(len(raw)+len(errors),2*META))
   self.budget.release(reservation,actual)
 def item(self,item):
  result={'coordinate':item['coordinate'],'URL':item['publisher_binary_URL'],'status':'FAIL_OR_INCOMPLETE','errors':[],'binary_admission_to_shared_cache':False}
  try:
   side,path=self.request(item['publisher_binary_SHA1_sidecar_URL'],META);expected=checksum(stable(path,max_bytes=META),item['publisher_binary_URL']);result['publisher_SHA1']=expected;result['SHA1_request']=side['request']
   if item['publisher_declared_hashes'].get('sha1',expected).lower()!=expected:raise ValueError('Publisher module SHA1 differs from sidecar')
   binary,path=self.request(item['publisher_binary_URL'],MAX_JAR);result['binary_request']=binary['request'];size=path.stat().st_size;result['body']={'path':str(path),'bytes':size,'hashes':{'sha256':binary['body']['sha256']}}
   if item['publisher_declared_size'] is not None and size!=item['publisher_declared_size']:raise ValueError('Publisher module size mismatch')
   algorithms={'sha1','sha256',*item['publisher_declared_hashes']};digests={name:hashlib.new(name) for name in algorithms}
   with path.open('rb') as stream:
    while True:
     if time.monotonic()>=self.deadline:raise TimeoutError('Global180-second digest deadline')
     part=stream.read(1024*1024)
     if not part:break
     for digest in digests.values():digest.update(part)
   values={name:digest.hexdigest() for name,digest in digests.items()};result['body']['hashes']=values
   if values['sha1']!=expected or any(values[name]!=value.lower() for name,value in item['publisher_declared_hashes'].items()):raise ValueError('Publisher artifact digest mismatch')
   jar_proof=verify_jar(path,self.deadline);result.update(status='PASS_PUBLISHER_JAR_INTAKE_ONLY',safe_JAR=jar_proof,proof=item['proof'],full_Gradle_graph_compare_still_required=True)
  except BaseException as error:
   result['errors'].append({'type':type(error).__name__,'error':str(error)})
   with self.lock:partial=next((r for r in reversed(self.requests) if r['URL']==item['publisher_binary_URL'] and r.get('body')),None)
   if partial and 'body' not in result:result['body']={'path':partial['body']['path'],'bytes':partial['body']['bytes'],'hashes':{'sha256':partial['body']['sha256']}}
  save(self.output/(item['coordinate']['group']+'__'+item['coordinate']['name']+'__'+item['coordinate']['version']+'.json'),result)
  return result

def main():
 p=argparse.ArgumentParser();p.add_argument('--plan-sha256',required=True);p.add_argument('--source-fences-sha256',required=True);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
 if Path(sys.executable).resolve()!=PYTHON.resolve():raise ValueError('Pinned Python differs')
 fences=json.loads(stable(HERE/'source-fences.json',a.source_fences_sha256));assert stable(PYTHON,fences['Python_SHA256'],8*1024**2)
 for r in fences['inputs']:stable(r['path'],r['sha256'],max(8*1024**2,r['bytes']))
 plan=json.loads(stable(HERE/'plan.json',a.plan_sha256));graph=json.loads(stable(plan['actual_metadata3_graph']['path'],plan['actual_metadata3_graph']['sha256']));facts=json.loads(stable(plan['sealed_binary_facts']['path'],plan['sealed_binary_facts']['sha256']));
 if plan['counts']!={'unique_JARs':67,'module_declared':7,'Maven_fallback':60,'selected_modules':69,'excluded_duplicate_or_POM_components':2} or len(plan['items'])!=67 or len({r['publisher_binary_URL'] for r in plan['items']})!=67:raise ValueError('Exact67-item plan differs')
 if not graph['complete_selected_tooling_metadata'] or graph['complete_selected_tooling_graph'] or graph['errors']:raise ValueError('Current selected metadata state differs')
 selected={r['id']:r for r in graph['components'] if r['kind']=='module'}
 for item in plan['items']:
  safe_item(item);name=':'.join(item['coordinate'][k] for k in ['group','name','version'])
  if selected[name]['selected_variants']!=[item['actual_selected_variant']]:raise ValueError('Actual selected variant differs')
 output=a.output;parent=Path('/Users/jeanbosco/Library/Caches/COOL-ARC09')
 if not output.is_absolute() or output.resolve()!=output or output.parent!=parent or not output.name.startswith('lint32-selected-publisher-binaries') or output.exists():raise ValueError('Fresh exact internal output leaf required')
 output.mkdir(mode=0o700);(output/'requests').mkdir(mode=0o700);started=time.monotonic();deadline=started+WORK;worker_sha=next(r['sha256'] for r in fences['inputs'] if r['path']==str(HERE/'request_worker.py'));intake=Intake(output,deadline,worker_sha)
 results=[]
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
  futures=[executor.submit(intake.item,item) for item in plan['items']]
  for f in concurrent.futures.as_completed(futures):results.append(f.result())
 for r in fences['inputs']:stable(r['path'],r['sha256'],max(8*1024**2,r['bytes']))
 owned_complete=not intake.active and intake.budget.reserved==0
 artifacts=[]
 for result in results:
  item=next(i for i in plan['items'] if i['coordinate']==result['coordinate']);body=result.get('body',{});hashes=body.get('hashes',{})
  artifacts.append({'coordinate':result['coordinate'],'filename':item['publisher_filename'],'body_path':body.get('path'),'sha256':hashes.get('sha256'),'sha1':hashes.get('sha1'),'bytes':body.get('bytes'),'publisher_URL':result['URL'],'publisher_SHA1_verified':result['status']=='PASS_PUBLISHER_JAR_INTAKE_ONLY','complete':result['status']=='PASS_PUBLISHER_JAR_INTAKE_ONLY','errors':result['errors'],'selected_owner':item['actual_selected_variant']['owner'],'type':'jar','extension':'jar','classifier':None,'module_declared_hashes':item['publisher_declared_hashes'],'module_declared_size':item['publisher_declared_size'],'proof':item['proof']})
 save(output/'readback.json',{'schema_version':1,'artifacts':artifacts,'requests':len(intake.requests),'body_bytes':sum((r.get('body') or {}).get('bytes',0) for r in intake.requests),'owned_processes_absent':all(r['owned_group_absent'] for r in intake.requests),'full_graph_admission':False,'status':'PASS_PUBLISHER_JAR_INTAKE_ONLY' if owned_complete and all(r['status']=='PASS_PUBLISHER_JAR_INTAKE_ONLY' for r in results) else 'FAIL_OR_INCOMPLETE','actual_seconds':time.monotonic()-started,'work_bound_seconds':WORK,'separate_owned_reap_seconds':CLEANUP,'max_parallel_workers':4,'owned_lifecycle_complete':owned_complete,'unreaped_or_unqualified_owned_groups':list(intake.active),'plan_sha256':a.plan_sha256,'source_fences_sha256':a.source_fences_sha256,'bounded_intake_charge_bytes':intake.budget.used,'intake_charge_includes_conservative_header_and_receipt_allowance':True,'max_total_HTTP_intake_bytes':TOTAL,'request_receipts':intake.requests,'results':results,'all_owned_groups_absent':all(r['owned_group_absent'] for r in intake.requests),'shared_Gradle_cache_writes':0,'full_Gradle_graph_lint_AAB_license_or_release_pass':False})
 return 0 if owned_complete and all(r['status']=='PASS_PUBLISHER_JAR_INTAKE_ONLY' for r in results) else 1
if __name__=='__main__':raise SystemExit(main())

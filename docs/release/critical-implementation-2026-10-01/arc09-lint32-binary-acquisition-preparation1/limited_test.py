import contextlib,copy,hashlib,importlib.util,io,json,os,stat,struct,sys,tempfile,threading,time,unittest,zipfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('private_binary_controller',HERE/'acquire_binaries.py');c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
PLAN=json.loads((HERE/'plan.json').read_text())
class Checks(unittest.TestCase):
 def test_exact_plan_and_Maven_contract(self):
  self.assertEqual(len(PLAN['items']),67);self.assertEqual(len({i['publisher_binary_URL'] for i in PLAN['items']}),67)
  for i in PLAN['items']:c.safe_item(i)
  fall=[i for i in PLAN['items'] if i['source_kind'].startswith('verified')];self.assertEqual(len(fall),60)
  self.assertEqual({i['coordinate']['name'] for i in fall if i['proof']['packaging_declared']=='bundle'},{'failureaccess','jimfs'})
  self.assertFalse(any(i['coordinate']['name'] in ['kotlinx-coroutines-core','kotlinx-coroutines-bom'] for i in PLAN['items']))
 def test_checksum_plain_and_named_GNU_formats(self):
  digest='a'*40
  for item in PLAN['items']:
   URL=item['publisher_binary_URL'];self.assertEqual(c.checksum((digest+'\n').encode(),URL),digest);self.assertEqual(c.checksum((digest+'  /home/maven/repository-staging/to-ibiblio'+c.urllib.parse.urlsplit(URL).path+'\n').encode(),URL),digest)
  for name in ['javax.inject','kxml2']:
   item=next(i for i in PLAN['items'] if i['coordinate']['name']==name);self.assertEqual(c.checksum((digest+'  /home/maven/repository-staging/to-ibiblio'+c.urllib.parse.urlsplit(item['publisher_binary_URL']).path).encode(),item['publisher_binary_URL']),digest)
  URL=PLAN['items'][0]['publisher_binary_URL']
  for raw in [b'invalid',b'a'*40+b' /other/artifact.jar',b'a'*40+b' /other.jar\n'+b'b'*40,b'a'*40+b' ../maven2/other.jar']:
   with self.assertRaises(ValueError):c.checksum(raw,URL)
 def test_URL_classifier_coordinate_and_hash_guards(self):
  good=PLAN['items'][0]
  for modified in [good|{'publisher_binary_URL':'https://evil.example/file.jar'},good|{'publisher_filename':'../foo.jar'},good|{'publisher_filename':good['publisher_filename'].replace('.jar','-sources.jar')},good|{'publisher_declared_size':True},good|{'publisher_declared_size':c.MAX_JAR+1},good|{'publisher_declared_hashes':{'sha1':'invalid'}}]:
   with self.assertRaises(ValueError):c.safe_item(modified)
 def test_ContentLength_and_encoding(self):
  self.assertEqual(c.content_length([['content-length','10']],10),10)
  for headers in [[],[['Content-Length','9']],[['content-length','10'],['content-length','10']],[['content-length','10'],['content-encoding','gzip']],[['content-length','10'],['transfer-encoding','chunked']]]:
   with self.assertRaises(ValueError):c.content_length(headers,10)
 def test_global_budget_reservation_and_deadline(self):
  b=c.Budget(time.monotonic()+2);b.reserve(c.TOTAL);self.assertEqual(b.reserved,c.TOTAL);b.release(c.TOTAL,c.TOTAL);self.assertEqual(b.used,c.TOTAL)
  with self.assertRaises(ValueError):b.reserve(1)
  b=c.Budget(time.monotonic()-1)
  with self.assertRaises(TimeoutError):b.reserve(1)
  b=c.Budget(time.monotonic()+2);b.reserve(1)
  with self.assertRaises(ValueError):b.release(1,2)
 def test_safe_JAR_and_CRC_corruption(self):
  with tempfile.TemporaryDirectory(dir=HERE/'fixtures') as temp:
   good=Path(temp)/'good.jar'
   with zipfile.ZipFile(good,'w',compression=zipfile.ZIP_STORED) as j:j.writestr('META-INF/MANIFEST.MF','Manifest-Version: 1.0\n');j.writestr('fixture/Marker.class',b'HELLO_CRC_FIXTURE')
   proof=c.verify_jar(good,time.monotonic()+5);self.assertTrue(proof['all_entries_CRC_verified']);self.assertEqual(proof['entries'],2)
   corrupted=Path(temp)/'bad.jar';raw=good.read_bytes();corrupted.write_bytes(raw.replace(b'HELLO_CRC_FIXTURE',b'BROKE_CRC_FIXTURE'))
   with self.assertRaises(zipfile.BadZipFile):c.verify_jar(corrupted,time.monotonic()+5)
   with self.assertRaises(TimeoutError):c.verify_jar(good,time.monotonic()-1)
 def test_JAR_path_duplicate_and_symlink_guards(self):
  with tempfile.TemporaryDirectory(dir=HERE/'fixtures') as temp:
   for index,name in enumerate(['../evil.class','/absolute.class','x\\evil.class','C:/evil.class']):
    p=Path(temp)/str(index)
    with zipfile.ZipFile(p,'w') as j:j.writestr(name,'x')
    with self.assertRaises(ValueError):c.verify_jar(p,time.monotonic()+5)
   p=Path(temp)/'link'
   with zipfile.ZipFile(p,'w') as j:
    i=zipfile.ZipInfo('link');i.create_system=3;i.external_attr=(stat.S_IFLNK|0o777)<<16;j.writestr(i,'target')
   with self.assertRaises(ValueError):c.verify_jar(p,time.monotonic()+5)
 def test_streamed_curl_worker_with_fake_process(self):
  spec=importlib.util.spec_from_file_location('private_request_worker',HERE/'request_worker.py');w=importlib.util.module_from_spec(spec);spec.loader.exec_module(w)
  class Fake:
   def __init__(self,data):self.stdout=io.BytesIO(data);self.stderr=io.BytesIO(b'');self.pid=987654;self.returncode=0
   def wait(self,timeout=None):return 0
   def poll(self):return self.returncode
   def terminate(self):self.returncode=-15
   def kill(self):self.returncode=-9
  with tempfile.TemporaryDirectory(dir=HERE/'fixtures') as temp:
   target=Path(temp)/'body';URL=PLAN['items'][0]['publisher_binary_URL'];oldArgv=sys.argv;oldPopen=w.subprocess.Popen;seen=[]
   def fake(*args,**kw):seen.append((args,kw));return Fake(b'HTTP/2 200\r\ncontent-length: 4\r\n\r\nDATA')
   try:
    w.subprocess.Popen=fake;sys.argv=['worker','--url',URL,'--body',str(target),'--max-bytes','4','--seconds','1'];out=io.StringIO()
    with contextlib.redirect_stdout(out):self.assertEqual(w.main(),0)
    receipt=json.loads(out.getvalue());self.assertEqual(target.read_bytes(),b'DATA');self.assertEqual(receipt['HTTP_body_bytes'],4);a=seen[0][0][0];self.assertEqual(a[1],'--disable');self.assertIn('--proxy',a);self.assertNotIn('--location',a);self.assertEqual(seen[0][1]['env'].get('HOME'),None)
    target=Path(temp)/'oversize';sys.argv=['worker','--url',URL,'--body',str(target),'--max-bytes','3','--seconds','1'];out=io.StringIO()
    with contextlib.redirect_stdout(out):self.assertEqual(w.main(),1)
    self.assertLessEqual(target.stat().st_size,3);self.assertIn('byte bound',json.loads(out.getvalue())['error']['error'])
   finally:w.subprocess.Popen=oldPopen;sys.argv=oldArgv
class ArtifactChecks(unittest.TestCase):
 def test_publisher_hash_size_crc_and_partial_failure_receipts(self):
  with tempfile.TemporaryDirectory(dir=HERE/'fixtures') as temp:
   temp=Path(temp);jar=temp/'fixture.jar'
   with zipfile.ZipFile(jar,'w',compression=zipfile.ZIP_STORED) as j:j.writestr('META-INF/MANIFEST.MF','Manifest-Version: 1.0\n')
   raw=jar.read_bytes();sha1=hashlib.sha1(raw).hexdigest();sha256=hashlib.sha256(raw).hexdigest();side=temp/'fixture.sha1';side.write_text(sha1+'\n')
   for index,mutation in enumerate([{}, {'publisher_declared_size':len(raw)+1},{'publisher_declared_hashes':{'sha256':'a'*64}},{'publisher_declared_hashes':{'sha1':'b'*40}}]):
    output=temp/str(index);output.mkdir();item=copy.deepcopy(PLAN['items'][0]);item.update(publisher_declared_size=len(raw),publisher_declared_hashes={'sha1':sha1,'sha256':sha256});item.update(mutation);intake=c.Intake(output,time.monotonic()+5,hashlib.sha256((HERE/'request_worker.py').read_bytes()).hexdigest());calls=[]
    def fixture_request(URL,max_bytes):
     calls.append(URL)
     return ({'request':len(calls),'body':{'path':str(jar),'bytes':len(raw),'sha256':sha256}},side if URL.endswith('.sha1') else jar)
    intake.request=fixture_request;result=intake.item(item)
    if index==0:
     self.assertEqual(result['status'],'PASS_PUBLISHER_JAR_INTAKE_ONLY');self.assertEqual(result['body']['hashes']['sha1'],sha1);self.assertTrue(result['safe_JAR']['all_entries_CRC_verified'])
    else:
     self.assertEqual(result['status'],'FAIL_OR_INCOMPLETE');self.assertTrue(result['errors'])
     if index<3:self.assertEqual(result['body']['bytes'],len(raw))
     if index==3:self.assertEqual(len(calls),1)
    self.assertFalse(result['binary_admission_to_shared_cache'])

class CleanupChecks(unittest.TestCase):
 def test_parent_unreaped_group_preserved_after_bounded_TERM_KILL(self):
  class Hung:
   pid=876543;returncode=None
   def communicate(self,timeout=None):
    self_timeouts.append(timeout)
    if timeout is None:raise AssertionError('Unbounded communicate')
    raise c.subprocess.TimeoutExpired('fixture',timeout)
   def poll(self):return None
  with tempfile.TemporaryDirectory(dir=HERE/'fixtures') as temp:
   output=Path(temp);(output/'requests').mkdir();self_timeouts=[];signals=[];oldPopen=c.subprocess.Popen;oldKill=c.os.killpg
   try:
    c.subprocess.Popen=lambda *a,**kw:Hung();c.os.killpg=lambda p,s:signals.append((p,s));intake=c.Intake(output,time.monotonic()+30,hashlib.sha256((HERE/'request_worker.py').read_bytes()).hexdigest())
    with self.assertRaises(ValueError):intake.request(PLAN['items'][0]['publisher_binary_SHA1_sidecar_URL'],c.META)
    self.assertIn(876543,intake.active);self.assertEqual(intake.budget.reserved,0);self.assertGreater(intake.budget.used,0);self.assertEqual(len(self_timeouts),3);self.assertLessEqual(self_timeouts[1],1);self.assertLessEqual(self_timeouts[2],2);self.assertIn((876543,c.signal.SIGTERM),signals);self.assertIn((876543,c.signal.SIGKILL),signals)
    receipt=json.loads(next((output/'requests').glob('*/receipt.json')).read_text());self.assertFalse(receipt['owned_wrapper_reaped']);self.assertFalse(receipt['owned_group_absent']);self.assertTrue(receipt['timed_out'])
   finally:c.subprocess.Popen=oldPopen;c.os.killpg=oldKill
 def test_worker_unreaped_curl_recorded_without_unbounded_wait(self):
  spec=importlib.util.spec_from_file_location('private_unreaped_request',HERE/'request_worker.py');w=importlib.util.module_from_spec(spec);spec.loader.exec_module(w)
  timeouts=[]
  class Hung:
   pid=765432;returncode=None
   def __init__(self):self.stdout=io.BytesIO(b'HTTP/2 200\r\ncontent-length: 1\r\n\r\nX');self.stderr=io.BytesIO(b'')
   def wait(self,timeout=None):
    timeouts.append(timeout)
    if timeout is None:raise AssertionError('Unbounded wait')
    raise w.subprocess.TimeoutExpired('fixture',timeout)
   def poll(self):return None
   def terminate(self):pass
   def kill(self):pass
  with tempfile.TemporaryDirectory(dir=HERE/'fixtures') as temp:
   oldPopen=w.subprocess.Popen;oldArgv=sys.argv
   try:
    w.subprocess.Popen=lambda *a,**kw:Hung();sys.argv=['worker','--url',PLAN['items'][0]['publisher_binary_URL'],'--body',str(Path(temp)/'body'),'--max-bytes','1','--seconds','1'];out=io.StringIO()
    with contextlib.redirect_stdout(out):self.assertEqual(w.main(),1)
    receipt=json.loads(out.getvalue());self.assertFalse(receipt['curl_child_reaped']);self.assertIn('remains unreaped',receipt['error']['error']);self.assertTrue(all(t is not None and t<=2 for t in timeouts));self.assertGreaterEqual(len(timeouts),3)
   finally:w.subprocess.Popen=oldPopen;sys.argv=oldArgv
if __name__=='__main__':unittest.main(verbosity=2)


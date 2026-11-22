#!/usr/bin/env python3
import pathlib,tempfile,unittest,datetime as dt,hashlib,copy
from release_gate import validate,safe_file,Blocked
class GateTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.tmp.name);self.now=dt.datetime.now(dt.timezone.utc);self.sha='a'*40
  (self.root/'test.log').write_text('test evidence')
  evidence={'path':'test.log','sha256':hashlib.sha256((self.root/'test.log').read_bytes()).hexdigest(),'source_commit':self.sha}
  self.doc={'schema_version':1,'source_commit':self.sha,'gates':[{'id':f'G{i}','status':'passed','performed_by':'reviewer','approved_by':'approver','verified_at':self.now.isoformat(),'execution_verified':True,'evidence':[evidence.copy()]}for i in range(6)]}
 def tearDown(self): self.tmp.cleanup()
 def errors(self):return validate(self.doc,self.root,self.sha,self.now)
 def test_consistent_schema(self): self.assertEqual(self.errors(),[])
 def test_missing_gate(self): self.doc['gates'].pop();self.assertTrue(self.errors())
 def test_duplicate_gate(self):self.doc['gates'][1]['id']='G0';self.assertTrue(self.errors())
 def test_commit_mismatch(self):self.doc['source_commit']='b'*40;self.assertTrue(self.errors())
 def test_pending_not_pass(self):self.doc['gates'][0]['status']='pending';self.assertTrue(self.errors())
 def test_no_empty_evidence(self):self.doc['gates'][0]['evidence']=[];self.assertTrue(self.errors())
 def test_hash_mismatch(self):self.doc['gates'][0]['evidence'][0]['sha256']='b'*64;self.assertTrue(self.errors())
 def test_stale(self):self.doc['gates'][0]['verified_at']=(self.now-dt.timedelta(days=4)).isoformat();self.assertTrue(self.errors())
 def test_future(self):self.doc['gates'][0]['verified_at']=(self.now+dt.timedelta(hours=1)).isoformat();self.assertTrue(self.errors())
 def test_self_approval(self):self.doc['gates'][0]['approved_by']='reviewer';self.assertTrue(self.errors())
 def test_authored_not_executed(self):self.doc['gates'][1]['execution_verified']=False;self.assertTrue(self.errors())
 def test_path_escape(self):self.doc['gates'][0]['evidence'][0]['path']='../test.log';self.assertTrue(self.errors())
 def test_symlink_refused(self): (self.root/'link').symlink_to(self.root/'test.log');self.assertRaises(Blocked,safe_file,self.root,'link')
if __name__=='__main__':unittest.main(verbosity=2)

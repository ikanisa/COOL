"""Private filesystem failure fixtures; never touch shared cache or real intake."""
import hashlib,os,stat,time,types,unittest
from pathlib import Path
from unittest.mock import patch
HERE=Path(__file__).resolve().parent
raw=(HERE/'admit_verified_blobs.py').read_bytes();m=types.ModuleType('admission_fixture_subject');m.__file__=str(HERE/'admit_verified_blobs.py');exec(compile(raw,m.__file__,'exec'),m.__dict__)
class AdmissionFilesystemFixtures(unittest.TestCase):
 def setUp(self):
  self.root=HERE/'fixtures'/self._testMethodName;self.root.mkdir();self.pool=self.root/'pool';self.pool.mkdir();self.source=self.root/'body';self.source.write_bytes(b'publisher jar fixture bytes '*100);self.deadline=time.monotonic()+10;self.item={'coordinate':{'group':'org.example','name':'fixture','version':'1.0'},'publisher_filename':'fixture-1.0.jar','publisher_declared_hashes':{},'publisher_declared_size':None};self.held=m.held_digest(self.source,self.deadline);self.target=m.destination(self.item,self.held,self.pool)
 def tearDown(self):os.close(self.held['fd'])
 def make_target(self,body):self.target.parent.mkdir(parents=True);self.target.write_bytes(body)
 def test_wrong_actual_hash_refuses_before_copy(self):
  artifact={'bytes':self.held['bytes'],'sha1':self.held['hashes']['sha1'],'sha256':'0'*64}
  with self.assertRaisesRegex(ValueError,'digests differ'):m.verify_source(self.held,artifact,self.item)
  self.assertEqual(list(self.pool.iterdir()),[])
 def test_wrong_module_hash_refuses_before_copy(self):
  item={**self.item,'publisher_declared_hashes':{'sha256':'0'*64}};artifact={'bytes':self.held['bytes'],**self.held['hashes']}
  with self.assertRaisesRegex(ValueError,'module digest'):m.verify_source(self.held,artifact,item)
  self.assertEqual(list(self.pool.iterdir()),[])
 def test_hardlinked_source_refused(self):
  alias=self.root/'hardlink';os.link(self.source,alias)
  with self.assertRaisesRegex(ValueError,'Aliased'):m.held_digest(alias,self.deadline)
  self.assertEqual(list(self.pool.iterdir()),[])
 def test_symlink_source_refused(self):
  alias=self.root/'symlink';alias.symlink_to(self.source)
  with self.assertRaisesRegex(ValueError,'Symlink'):m.held_digest(alias,self.deadline)
  self.assertEqual(list(self.pool.iterdir()),[])
 def test_case_alias_refuses_before_directory_creation(self):
  (self.pool/'ORG.EXAMPLE').mkdir()
  with self.assertRaisesRegex(ValueError,'alias'):m.prevalidate_destination(self.target,self.held,self.deadline,self.pool)
  self.assertEqual([p.name for p in self.pool.iterdir()],['ORG.EXAMPLE'])
 def test_existing_mismatch_preserves_bytes_and_identity(self):
  self.make_target(b'existing wrong bytes');before=m.identity(self.target.stat())
  with self.assertRaisesRegex(ValueError,'no overwrite'):m.prevalidate_destination(self.target,self.held,self.deadline,self.pool)
  self.assertEqual(self.target.read_bytes(),b'existing wrong bytes');self.assertEqual(m.identity(self.target.stat()),before)
 def test_exact_existing_reuse_preserves_inode_and_mode(self):
  self.make_target(self.source.read_bytes());self.target.chmod(0o600);before=m.identity(self.target.stat());expected=m.prevalidate_destination(self.target,self.held,self.deadline,self.pool);result=m.copy_held(self.held,self.target,expected,self.deadline,self.pool)
  self.assertEqual(result['action'],'reused-exact-existing');self.assertEqual(m.identity(self.target.stat()),before)
 def test_exclusive_copy_has_exact_hashes_mode_and_no_alias(self):
  expected=m.prevalidate_destination(self.target,self.held,self.deadline,self.pool);result=m.copy_held(self.held,self.target,expected,self.deadline,self.pool)
  self.assertEqual(result['action'],'created-exclusive-blob');self.assertEqual(self.target.read_bytes(),self.source.read_bytes());self.assertEqual(result['sha256'],self.held['hashes']['sha256']);self.assertEqual(result['sha1'],self.held['hashes']['sha1']);self.assertEqual(stat.S_IMODE(self.target.stat().st_mode),0o644);self.assertEqual(self.target.stat().st_nlink,1)
 def test_destination_race_never_overwrites(self):
  expected=m.prevalidate_destination(self.target,self.held,self.deadline,self.pool);self.make_target(b'other writer leaf');before=m.identity(self.target.stat())
  with self.assertRaises(FileExistsError):m.copy_held(self.held,self.target,expected,self.deadline,self.pool)
  self.assertEqual(self.target.read_bytes(),b'other writer leaf');self.assertEqual(m.identity(self.target.stat()),before)
 def test_source_change_after_prevalidation_refuses(self):
  expected=m.prevalidate_destination(self.target,self.held,self.deadline,self.pool);self.source.write_bytes(b'changed publisher body')
  with self.assertRaisesRegex(ValueError,'modified'):m.copy_held(self.held,self.target,expected,self.deadline,self.pool)
  self.assertEqual(list(self.pool.iterdir()),[])
 def test_partial_write_failure_retained_unadmitted(self):
  expected=m.prevalidate_destination(self.target,self.held,self.deadline,self.pool);real_write=os.write;calls=[]
  def fail_after_prefix(fd,body):
   calls.append(1)
   if len(calls)>1:raise OSError('simulated disk error after prefix')
   return real_write(fd,body[:16])
  with patch.object(m.os,'write',side_effect=fail_after_prefix):
   with self.assertRaisesRegex(OSError,'simulated disk'):m.copy_held(self.held,self.target,expected,self.deadline,self.pool)
  self.assertEqual(self.target.read_bytes(),self.source.read_bytes()[:16]);self.assertEqual(self.target.stat().st_nlink,1);self.assertEqual(stat.S_IMODE(self.target.stat().st_mode),0o644)
if __name__=='__main__':unittest.main(verbosity=2)

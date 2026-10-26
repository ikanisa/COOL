import pathlib,tempfile,unittest
from admin_headers import plan,install,POLICY,PolicyConflict
class Headers(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=pathlib.Path(self.temp.name)
  (self.root/'index.html').write_text('fixture');(self.root/'main.dart.js').write_text('fixture')
 def test_new_policy(self):self.assertTrue(install(self.root));self.assertEqual((self.root/'_headers').read_text(),POLICY)
 def test_repeat_no_write(self):install(self.root);stamp=(self.root/'_headers').stat().st_mtime_ns;self.assertFalse(install(self.root));self.assertEqual(stamp,(self.root/'_headers').stat().st_mtime_ns)
 def test_plan_read_only(self):self.assertTrue(plan(self.root));self.assertFalse((self.root/'_headers').exists())
 def test_existing_policy_preserved(self):
  (self.root/'_headers').write_text("/*\n Content-Security-Policy: default-src 'none'\n")
  with self.assertRaises(PolicyConflict):install(self.root)
  self.assertIn("default-src 'none'",(self.root/'_headers').read_text())
 def test_empty_existing_requires_review(self):
  (self.root/'_headers').write_text('')
  with self.assertRaises(PolicyConflict):install(self.root)
 def test_missing_index(self):
  (self.root/'index.html').unlink()
  with self.assertRaises(PolicyConflict):plan(self.root)
 def test_missing_bundle(self):
  (self.root/'main.dart.js').unlink()
  with self.assertRaises(PolicyConflict):plan(self.root)
 def test_no_header_symlink(self):
  (self.root/'_headers').symlink_to(self.root/'index.html')
  with self.assertRaises(PolicyConflict):install(self.root)
 def test_no_build_symlink(self):
  folder=self.root/'link';folder.symlink_to(self.root,target_is_directory=True)
  with self.assertRaises(PolicyConflict):install(folder)
 def test_cache_not_stored(self):self.assertIn('Cache-Control: no-store',POLICY)
 def test_frame_protection(self):self.assertIn("frame-ancestors 'none'",POLICY)
 def test_no_script_eval_policy_invention(self):self.assertNotIn('unsafe-eval',POLICY);self.assertNotIn('script-src',POLICY)
if __name__=='__main__':unittest.main(verbosity=2)

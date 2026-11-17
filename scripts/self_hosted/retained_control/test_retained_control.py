"""Exercise installed-form retained controls in a private synthetic directory."""
import os,shutil,subprocess,sys,tempfile,unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parent
SOURCES=('operation_lock.py','operator_wrapper.py','runtime_startup_lockaware.py',
         'scheduler_wrapper.py','scheduler_evidence.py','rotation_coordinator.py','guard_core.py')
FIXTURES={'shared_lock_checks.py':'test_shared_operation_lock.py',
          'startup_checks.py':'test_runtime_startup_lockaware.py',
          'scheduler_receipt_checks.py':'test_scheduler_receipt.py'}

class RetainedControlTests(unittest.TestCase):
 def test_private_installed_form(self):
  with tempfile.TemporaryDirectory(dir='/private/tmp') as directory:
   root=Path(directory).resolve()
   for name in SOURCES:
    shutil.copyfile(ROOT/name,root/name);(root/name).chmod(0o600)
   for source,target in FIXTURES.items():
    shutil.copyfile(ROOT/'fixtures'/source,root/target);(root/target).chmod(0o600)
   # The receipt verifier normally imports a protected live-guard module.
   # This synthetic fixture supplies only its public source identity/reader.
   stub=root/'candidate_guard.py';stub.write_text("from pathlib import Path\nSOURCE='f691215e0df1ce7400d0d83115132744fb1f308e58cc40d75d532ed740f890ee'\ndef private(p): return Path(p).read_bytes()\n");stub.chmod(0o600)
   result=subprocess.run([sys.executable,'-I','-B','-m','unittest','discover','-s',str(root),'-p','test_*.py','-q'],cwd=root,capture_output=True,text=True,timeout=60,env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1'})
   self.assertEqual(result.returncode,0,result.stdout+result.stderr)
   self.assertIn('OK',result.stderr)

if __name__=='__main__':unittest.main()

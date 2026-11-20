import hashlib,json,os,sys,tempfile,time,unittest
from pathlib import Path
from unittest.mock import patch
import candidate_guard as c
import scheduler_evidence as evidence
import scheduler_wrapper as wrapper

class SchedulerReceiptTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory(dir='/private/tmp');self.addCleanup(self.tmp.cleanup)
  self.root=Path(self.tmp.name).resolve();self.release=self.root/'production';self.release.mkdir()
  script=self.release/'source/scripts/self_hosted/burimunsi_scheduler.py';script.parent.mkdir(parents=True);script.write_bytes(b'synthetic sealed scheduler')
  private=self.release/'private';private.mkdir(mode=0o700);folder=private/'native-scheduler';folder.mkdir(mode=0o700)
  self.lock=folder/'tick.lock';self.lock.write_bytes(b'');self.lock.chmod(0o600)
  config=private/'configuration.json';config.write_bytes(b'synthetic configuration');config.chmod(0o600)
  self.config=hashlib.sha256(config.read_bytes()).hexdigest()
  (self.release/'release.json').write_text(json.dumps({'source_sha256':c.SOURCE,'profile_sha256':wrapper.PROFILE_SHA256}))
  self.endpoint='http://127.0.0.1:55101/functions/v1/collect-jobs';self.receipt=folder/'last-tick.private.json'
  self.patches=[patch.object(wrapper,'RELEASES',self.root),patch.object(wrapper,'BASE',self.release),patch.object(wrapper,'PRODUCTION',self.release),patch.object(wrapper,'SCRIPT_SHA256',hashlib.sha256(script.read_bytes()).hexdigest())]
  for p in self.patches:p.start();self.addCleanup(p.stop)
 def launch(self,runs=1,exit_code=0,active=0):
  return ('\truns = '+str(runs)+'\n\tlast exit code = '+str(exit_code)+'\n\tactive count = '+str(active)+'\n'+str(self.release)+'\n/synthetic/scheduler_wrapper.py\n').encode()
 def valid(self,after,stdout=None):
  return evidence.complete_receipt(self.receipt,configuration=self.config,after_ns=after,launch_stdout=stdout or self.launch(),release=self.release,wrapper=Path('/synthetic/scheduler_wrapper.py'))
 def test_success_is_bound_to_configuration_and_a_new_natural_run(self):
  before=time.time_ns()
  result=wrapper.run(self.release,self.endpoint,self.lock,runner=lambda _: (0,json.dumps({'status':'complete','source_sha256':c.SOURCE}).encode()))
  self.assertEqual(result,0);self.assertTrue(self.valid(before));self.assertEqual(self.receipt.stat().st_mode&0o777,0o600)
  self.assertFalse(self.valid(time.time_ns()+1));self.assertFalse(self.valid(before,self.launch(runs=0)));self.assertFalse(self.valid(before,self.launch(exit_code=1)))
  self.assertFalse(evidence.complete_receipt(self.receipt,configuration='wrong',after_ns=before,launch_stdout=self.launch(),release=self.release,wrapper=Path('/synthetic/scheduler_wrapper.py')))
 def test_busy_or_failed_ticks_do_not_count_as_completion(self):
  before=time.time_ns()
  self.assertEqual(wrapper.run(self.release,self.endpoint,self.lock,runner=lambda _:(0,b'{"status":"already_running"}')),0)
  self.assertFalse(self.valid(before))
  self.assertEqual(wrapper.run(self.release,self.endpoint,self.lock,runner=lambda _:(1,b'private failure')),1)
  self.assertFalse(self.valid(before));self.assertNotIn('private failure',self.receipt.read_text())
 def test_wrong_source_or_profile_refused_before_runner(self):
  (self.release/'release.json').write_text(json.dumps({'source_sha256':c.SOURCE,'profile_sha256':'wrong'}))
  with self.assertRaises(ValueError):wrapper.run(self.release,self.endpoint,self.lock,runner=lambda _:self.fail('runner invoked'))
 def test_unowned_existing_receipt_not_replaced(self):
  self.receipt.write_text('{"format":"unrelated"}');self.receipt.chmod(0o600)
  with self.assertRaises(ValueError):wrapper.run(self.release,self.endpoint,self.lock,runner=lambda _:(0,b'{}'))
  self.assertIn('unrelated',self.receipt.read_text())
 def test_capture_limits_output_and_stops_child(self):
  with self.assertRaises(ValueError):wrapper.capture([sys.executable,'-c',"import os,time;os.write(1,b'x'*5000);time.sleep(30)"],timeout=3)
  with self.assertRaises(TimeoutError):wrapper.capture([sys.executable,'-c','import time;time.sleep(30)'],timeout=.2)

if __name__=='__main__':unittest.main()

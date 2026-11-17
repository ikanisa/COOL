import json,os,plistlib,signal,subprocess,sys,tempfile,unittest,uuid
from pathlib import Path
from unittest.mock import patch
import operation_lock as op
import operator_wrapper as wrapper
import rotation_coordinator as rotation


class SharedOperationLockTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory(dir='/private/tmp');self.addCleanup(self.tmp.cleanup)
  self.root=Path(self.tmp.name).resolve()/'coordinator';op.initialize(self.root)
 def test_competing_process_and_monitor_wait_then_resume(self):
  callback=[]
  with op.Coordinator(self.root):
   self.assertFalse(op.monitor_cycle(lambda:callback.append('ran'),root=self.root))
   code="import operation_lock as m,sys\ntry:m.Coordinator(sys.argv[1])\nexcept m.OperationBusy:sys.exit(0)\nsys.exit(1)"
   p=subprocess.run([sys.executable,'-B','-c',code,str(self.root)],capture_output=True,timeout=5)
   self.assertEqual(p.returncode,0)
  self.assertTrue(op.monitor_cycle(lambda:callback.append('ran'),root=self.root))
  self.assertEqual(callback,['ran'])
 def test_preflight_failure_does_not_leave_active_marker(self):
  with self.assertRaises(ValueError):
   with op.coordinated('operator_test','synthetic',root=self.root):raise ValueError('before action')
  with op.Coordinator(self.root) as c:self.assertIsNone(c.active())
 def test_uncertain_action_leaves_marker_and_blocks_all_others(self):
  with self.assertRaises(RuntimeError):
   with op.coordinated('operator_test','synthetic',root=self.root) as p:
    p.arm();raise RuntimeError('unknown')
  with op.Coordinator(self.root) as c:
   marker=c.active();self.assertEqual(marker['kind'],'operator_test')
   with self.assertRaises(op.OperationRefused):c.complete({**marker,'operation':str(uuid.uuid4())})
  self.assertFalse(op.monitor_cycle(lambda:self.fail('monitor acted'),root=self.root))
  with self.assertRaises(op.OperationBusy):
   with op.coordinated('other','synthetic',root=self.root):pass
  with op.Coordinator(self.root) as c:c.complete(marker)
  self.assertTrue(op.monitor_cycle(lambda:None,root=self.root))
 def test_process_death_preserves_marker_after_kernel_lock_releases(self):
  code="import operation_lock as m,sys,uuid\ng=m.Coordinator(sys.argv[1]);g.begin(str(uuid.uuid4()),'rotation','a'*64);print('ready',flush=True);sys.stdin.read()"
  child=subprocess.Popen([sys.executable,'-B','-c',code,str(self.root)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
  try:
   self.assertEqual(child.stdout.readline().strip(),'ready');os.kill(child.pid,signal.SIGKILL);child.wait(timeout=5)
   with op.Coordinator(self.root) as c:self.assertEqual(c.active()['kind'],'rotation')
   with self.assertRaises(op.OperationBusy):
    with op.coordinated('operator_other','synthetic',root=self.root):pass
  finally:
   if child.poll() is None:child.kill();child.wait(timeout=5)
   if child.stdin:child.stdin.close()
   if child.stdout:child.stdout.close()
 def test_wrapper_holds_lock_through_child_and_clears_on_success(self):
  events=[]
  class Child:
   pid=123
   def wait(self,timeout):
    with self_test.assertRaises(op.OperationBusy):op.Coordinator(self_test.root)
    events.append('child-waited');return 0
  self_test=self
  with patch.object(wrapper,'checked_adoption'),patch.object(wrapper,'checked_release',return_value=Path('/synthetic/release')):
   result=wrapper.invoke('retained_edge',Path('/synthetic/release'),root=self.root,process=lambda *a,**k:Child())
  self.assertTrue(result['complete']);self.assertEqual(events,['child-waited'])
  with op.Coordinator(self.root) as c:self.assertIsNone(c.active())
 def test_wrapper_failure_leaves_durable_marker(self):
  class Child:
   pid=123
   def wait(self,timeout):return 1
  with patch.object(wrapper,'checked_adoption'),patch.object(wrapper,'checked_release',return_value=Path('/synthetic/release')):
   with self.assertRaises(wrapper.OutcomeUnconfirmed):wrapper.invoke('retained_edge',Path('/synthetic/release'),root=self.root,process=lambda *a,**k:Child())
  with op.Coordinator(self.root) as c:self.assertEqual(c.active()['kind'],'operator_retained_edge')
 def test_generic_stack_creation_is_not_exposed(self):
  for action in ('start_private','provision_runtime_roles','publish'):
   with self.subTest(action=action):
    with self.assertRaises(ValueError):wrapper.child_command(action,Path('/synthetic/release'))
 def test_legacy_startup_refuses_wrapper_after_bootstrap_rollback(self):
  settings=self.root/'settings';settings.write_text(json.dumps({'enabled':True,'release_root':str(wrapper.BASE),'release_source_sha256':wrapper.SOURCE_SHA256}));settings.chmod(0o600)
  plist=self.root/'startup.plist';script=self.root/'runtime_startup.py'
  def write(entry):
   plist.write_bytes(plistlib.dumps({'Label':'com.ikanisa.collect.runtime-startup','RunAtLoad':True,'ProgramArguments':['python',str(entry),'--settings',str(settings),'--run']}));plist.chmod(0o600)
  with patch.object(wrapper,'START_PLIST',plist),patch.object(wrapper,'START_SCRIPT',script):
   write(script);wrapper.checked_adoption()
   write(self.root/'legacy.py')
   with self.assertRaisesRegex(ValueError,'lock_aware_startup_not_adopted'):wrapper.checked_adoption()
 def test_rotation_holds_one_lock_and_rollback_clears_matching_marker(self):
  class Guard:
   manifest={'fence_operation':str(uuid.uuid4()),'rollback_fence_operation':str(uuid.uuid4())};manifest_hash='a'*64
   journal=type('Journal',(),{'exists':lambda self,name:False})()
   def __init__(self):self.phases=[]
   def step(self,phase):
    self.phases.append(phase)
    with self_test.assertRaises(op.OperationBusy):op.Coordinator(self_test.root)
    if phase=='drain':raise RuntimeError('synthetic uncertain phase')
   def rollback(self):return {'complete':True}
   def reconcile(self):return {'mutation':False}
  self_test=self;g=Guard()
  with self.assertRaises(RuntimeError):rotation.run_all(g,root=self.root)
  self.assertEqual(g.phases[:2],['plan','stop_scheduler'])
  self.assertEqual(rotation.reconcile(g,root=self.root),{'mutation':False})
  self.assertTrue(rotation.rollback(g,root=self.root)['complete'])
  with op.Coordinator(self.root) as c:self.assertIsNone(c.active())
 def test_repeated_completed_rollback_creates_no_new_marker(self):
  class Journal:
   def exists(self,name):return name in ('final-result.json','rollback-intent.json','rollback-result.json')
   def pending(self):return []
  class Guard:
   manifest={'fence_operation':str(uuid.uuid4()),'rollback_fence_operation':str(uuid.uuid4())};manifest_hash='a'*64;journal=Journal()
   def rollback(self):raise AssertionError('replayed')
  with self.assertRaisesRegex(op.OperationRefused,'rotation_rollback_one_use'):rotation.rollback(Guard(),root=self.root)
  with op.Coordinator(self.root) as c:self.assertIsNone(c.active())
 def test_already_acquired_owner_is_held_through_all_rotation_phases(self):
  class Guard:
   manifest={'fence_operation':str(uuid.uuid4()),'rollback_fence_operation':str(uuid.uuid4())};manifest_hash='a'*64
   def __init__(self):self.phases=[]
   def step(self,phase):
    self.phases.append(phase)
    with self_test.assertRaises(op.OperationBusy):op.Coordinator(self_test.root)
  self_test=self;g=Guard()
  with op.Coordinator(self.root) as owner:self.assertTrue(rotation.run_locked(g,owner)['complete'])
  self.assertEqual(g.phases[0],'plan');self.assertEqual(g.phases[-1],'final')
  with op.Coordinator(self.root) as c:self.assertIsNone(c.active())
 def test_symlinked_or_insecure_lock_file_is_refused(self):
  lock=self.root/'operation.lock';lock.chmod(0o644)
  with self.assertRaises(op.OperationRefused):op.Coordinator(self.root)
  lock.chmod(0o600);lock.unlink();lock.symlink_to('/dev/null')
  with self.assertRaises(op.OperationRefused):op.Coordinator(self.root)

if __name__=='__main__':unittest.main()

#!/usr/bin/env python3
"""Synthetic-only safety and native encrypted-image checks (macOS)."""
import importlib.util
import json
import os
import pathlib
import selectors
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

HERE=pathlib.Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('collect_encrypted_qualify',HERE/'qualify.py')
q=importlib.util.module_from_spec(spec);spec.loader.exec_module(q)
IMAGE=pathlib.Path('/private/tmp/collect-encrypted-inert-fixture/fixture.sparseimage')
MOUNT=pathlib.Path('/private/tmp/collect-encrypted-inert-fixture/mount')

def info(device='/dev/disk24s1',mount=str(MOUNT),image=str(IMAGE)):
 return {'images':[{'image-path':image,'system-entities':[{'dev-entry':'/dev/disk24'},
  {'dev-entry':device,'mount-point':mount}]}]}

class IdentityTests(unittest.TestCase):
 def test_only_one_exact_owned_image_and_mounted_slice_is_accepted(self):
  self.assertEqual(q.attached_device(info(),IMAGE,MOUNT),'/dev/disk24s1')
  for v in [info(image='/private/tmp/different.sparseimage'),info(mount='/Volumes/other'),
            info(device='/dev/disk24'),info(device='/dev/disk24s1/other'),{'images':[]},
            {'images':[info()['images'][0],info()['images'][0]]},
            {'images':[{'image-path':str(IMAGE),'system-entities':[{'dev-entry':'/dev/disk24s1','mount-point':str(MOUNT)},
              {'dev-entry':'/dev/disk25s1','mount-point':str(MOUNT)}]}]}]:
   with self.subTest(v=v),self.assertRaises(q.Refused):q.attached_device(v,IMAGE,MOUNT)
  self.assertTrue(q.is_detached({'images':[]},IMAGE))
  self.assertFalse(q.is_detached(info(),IMAGE))

 def test_pid_file_must_match_owned_process_data_port_and_socket(self):
  with tempfile.TemporaryDirectory(prefix='collect-inert-pid-',dir='/private/tmp') as d:
   file=pathlib.Path(d)/'pid';data=pathlib.Path(d)/'data';sock=pathlib.Path(d)/'socket'
   file.write_text('42\n'+str(data)+'\n1234\n55001\n'+str(sock)+'\n')
   self.assertTrue(q.pid_matches(file,42,data,55001,sock))
   for pid,expected_data,port,expected_sock in [(43,data,55001,sock),(42,data/'other',55001,sock),
    (42,data,55002,sock),(42,data,55001,sock/'other')]:
    self.assertFalse(q.pid_matches(file,pid,expected_data,port,expected_sock))

 def test_cli_rejects_unrequested_modes_before_allocating_image(self):
  result=subprocess.run([sys.executable,str(HERE/'qualify.py'),'--real'],capture_output=True,text=True,timeout=15)
  self.assertNotEqual(result.returncode,0)
  self.assertEqual(json.loads(result.stdout)['code'],'synthetic_macos_only')

@unittest.skipUnless(sys.platform=='darwin','requires macOS hdiutil and PostgreSQL 17')
class NativeFixtureTests(unittest.TestCase):
 def env(self):
  return {'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','LC_ALL':'C',
          'COLLECT_SYNTHETIC_PG_BIN':os.environ.get('COLLECT_SYNTHETIC_PG_BIN',q.DEFAULT_PG)}

 def test_synthetic_restore_uses_encrypted_image_and_removes_owned_resources(self):
  result=subprocess.run([sys.executable,str(HERE/'qualify.py')],env=self.env(),capture_output=True,text=True,timeout=120)
  self.assertEqual(result.returncode,0,result.stdout)
  self.assertEqual(json.loads(result.stdout),{'format':'collect.encrypted-inert.synthetic-qualification.v1','status':'passed',
   'synthetic':True,'real_archive_read':False,'aes256_image_verified':True,'owned_postgres_stopped':True,
   'owned_image_detached':True,'owned_scratch_removed':True,'native_cells_verified':True,
   'production_restore_authority':False,'whole_system_recovery':False})

 def test_term_after_owned_server_ready_stops_and_detaches_before_cleanup(self):
  env={**self.env(),'COLLECT_ENCRYPTED_FIXTURE_TEST_PAUSE':'after_pg_ready'}
  child=subprocess.Popen([sys.executable,str(HERE/'qualify.py')],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
  try:
   with selectors.DefaultSelector() as sel:
    sel.register(child.stderr,selectors.EVENT_READ)
    events=sel.select(timeout=90)
    self.assertTrue(events,'synthetic fixture never reported ready')
    self.assertEqual(child.stderr.readline().strip(),'COLLECT_SYNTHETIC_ENCRYPTED_READY')
   child.send_signal(signal.SIGTERM)
   stdout,stderr=child.communicate(timeout=45)
   self.assertNotEqual(child.returncode,0,stderr)
   result=json.loads(stdout)
   self.assertEqual(result['status'],'interrupted')
   self.assertTrue(result['owned_postgres_stopped'])
   self.assertTrue(result['owned_image_detached'])
   self.assertTrue(result['owned_scratch_removed'])
   self.assertFalse(result['real_archive_read'])
  finally:
   if child.poll() is None:
    child.kill();child.wait(timeout=10)

 def test_failure_preserves_synthetic_evidence_even_after_confirmed_detach(self):
  env={**self.env(),'COLLECT_ENCRYPTED_FIXTURE_TEST_FAIL':'after_pg_ready'}
  result=subprocess.run([sys.executable,str(HERE/'qualify.py')],env=env,capture_output=True,text=True,timeout=120)
  self.assertNotEqual(result.returncode,0)
  receipt=json.loads(result.stdout)
  self.assertEqual(receipt['code'],'synthetic_injected_failure')
  self.assertTrue(receipt['owned_postgres_stopped']);self.assertTrue(receipt['owned_image_detached'])
  root=pathlib.Path(receipt['preserved_synthetic_root'])
  self.assertTrue(root.name.startswith('collect-encrypted-inert-') and root.parent==pathlib.Path('/private/tmp') and root.resolve()==root)
  self.assertEqual(root.stat().st_uid,os.getuid());self.assertTrue((root/'fixture.sparseimage').is_file())
  evidence=root/'RECOVERY.json';self.assertEqual(evidence.stat().st_mode&0o777,0o600)
  self.assertEqual(json.loads(evidence.read_text()),receipt)
  # Test-owned synthetic artifacts may be removed only after the supervisor
  # confirmed the exact PostgreSQL and image cleanup.
  shutil.rmtree(root)

if __name__=='__main__':unittest.main()

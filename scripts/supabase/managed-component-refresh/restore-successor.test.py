"""Synthetic-only qualification of the refreshed local inert restore selector."""
import hashlib
import importlib.util
import json
import os
import pathlib
import select
import signal
import subprocess
import tempfile
import unittest

HERE=pathlib.Path(__file__).resolve().parent
SPEC=importlib.util.spec_from_file_location('collect_refresh_restore',HERE/'restore-successor.py')
S=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(S)
ENV={'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','LC_ALL':'C','PYTHONDONTWRITEBYTECODE':'1'}
def sha(raw):return hashlib.sha256(raw).hexdigest()
def write(path,obj):
 raw=(json.dumps(obj,sort_keys=True,separators=(',',':'))+'\n').encode();path.write_bytes(raw);path.chmod(0o600);return sha(raw)
def command(component,*extra):
 pin=sha((HERE/'RESTORE-SOURCE-PINS.json').read_bytes())
 return [S.PYTHON,'-I',str(HERE/'restore-successor.py'),'--component',component,'--source-pins-sha256',pin,*extra]
def fixture(root,component):
 base=root/'private';base.mkdir(mode=0o700);t7=root/'t7';t7.mkdir(mode=0o700)
 count=base/'count';count.mkdir(mode=0o700);plan_dir=base/'plan';plan_dir.mkdir(mode=0o700);result_dir=base/'result';result_dir.mkdir(mode=0o700)
 counts_sha=write(count/'COUNTS.json',{'synthetic_count':0});canonical='c'*64
 count_record={'format':'collect.managed-component-preflight.result.v1','project_ref':S.PROJECT,'component':component,'metadata_only':True,'real_data_capture':False,
               'canonical_counts_sha256':canonical,'counts_file_sha256':counts_sha}
 count_sha=write(count/'RESULT.json',count_record);plan={'format':'collect.managed-component-capture.offline-plan.v1','project_ref':S.PROJECT,'component':component,
  'source_pins_sha256':S.PLAN_SOURCE,'request_read_only':True,'plan_only':True,'capture_dispatched':False,'full_recovery_acceptance':False,
  'preflight_result_path':str(count/'RESULT.json'),'preflight_result_sha256':count_sha,'counts_path':str(count/'COUNTS.json'),'counts_file_sha256':counts_sha,
  'canonical_counts_sha256':canonical,'query_sha256':'d'*64,'reference_sha256':'e'*64}
 plan_sha=write(plan_dir/'PLAN.json',plan)
 claim={'format':'collect.managed-component-capture.count-claim.v1','component':component,'execution_mode':'live','live_source_pins_sha256':S.LIVE_SOURCE,
  'plan_path':str(plan_dir/'PLAN.json'),'plan_sha256':plan_sha,'count_result_sha256':count_sha,'query_sha256':'d'*64,'automatic_retry':False}
 claim_sha=write(count/'CAPTURE-ONCE.json',claim)
 outcome={'format':'collect.managed-component-capture.outcome.v1','component':component,'execution_mode':'live','outcome':'COMPLETED','plan_sha256':plan_sha,
  'provider_query_attempted':True,'transport_query_attempted':True,'automatic_retry':False,'full_recovery_acceptance':False}
 outcome_sha=write(plan_dir/'OUTCOME.json',outcome)
 ciphertext=b'synthetic ciphertext only';copy=t7/'archive';copy.write_bytes(ciphertext);copy.chmod(0o600);cipher_sha=sha(ciphertext)
 receipt={'format':'collect.managed-auth.encrypted-write-receipt.v1' if component=='auth' else 'collect.managed-storage.metadata.encrypted-write-receipt.v1',
  'project_ref':S.PROJECT,'authenticated_readback':True,'full_recovery_acceptance':False,'automatic_retry':False,
  'native_rollback_command_complete_observed':False,'query_sha256':'d'*64,'counts_preflight_sha256':canonical,'reference_sha256':'e'*64,
  'archive_sha256':cipher_sha,'archive_bytes':len(ciphertext),'snapshot_sha256':'f'*64,'rows':1,'tables':27 if component=='auth' else 10}
 if component=='auth':receipt.update(managed_auth_data_included=True,storage_included=False,operational_auth_restored=False)
 else:receipt.update(storage_metadata_included=True,object_bodies_included=False,operational_storage_restored=False)
 result_sha=write(result_dir/'RESULT.json',receipt)
 selection={'format':'collect.managed-component-refresh.restore-selection.v1','component':component,'project_ref':S.PROJECT,
  'plan_path':str(plan_dir/'PLAN.json'),'plan_sha256':plan_sha,'outcome_sha256':outcome_sha,'count_claim_sha256':claim_sha,
  'result_path':str(result_dir/'RESULT.json'),'result_sha256':result_sha,'ciphertext_copy':str(copy),'ciphertext_sha256':cipher_sha,'snapshot_sha256':'f'*64}
 return selection,base,t7

class SelectorTests(unittest.TestCase):
 def test_both_synthetic_receipt_chains_and_ciphertext_are_bound(self):
  for component in ('auth','storage'):
   with self.subTest(component=component),tempfile.TemporaryDirectory(prefix='collect-restore-select-',dir='/private/tmp') as d:
    selection,base,t7=fixture(pathlib.Path(d),component);result=S.validate_selection(selection,component,base,t7)
    self.assertEqual(result['result'],selection['result_sha256']);self.assertEqual(result['ciphertext'],selection['ciphertext_sha256'])
    (t7/'archive').write_bytes(b'changed synthetic ciphertext')
    with self.assertRaises(S.Refused):S.validate_selection(selection,component,base,t7)
 def test_refuses_tampering_missing_outcome_bad_modes_and_duplicate_keys(self):
  for attack in ('outcome','claim','receipt','private_mode','outside','duplicate'):
   with self.subTest(attack=attack),tempfile.TemporaryDirectory(prefix='collect-restore-select-',dir='/private/tmp') as d:
    selection,base,t7=fixture(pathlib.Path(d),'auth')
    if attack=='outcome':(base/'plan'/'OUTCOME.json').write_text('{"outcome":"COMPLETED","outcome":"COMPLETED"}')
    if attack=='claim':(base/'count'/'CAPTURE-ONCE.json').unlink()
    if attack=='receipt':selection['result_sha256']='0'*64
    if attack=='private_mode':(base/'plan'/'PLAN.json').chmod(0o644)
    if attack=='outside':selection['ciphertext_copy']='/private/tmp/outside-synthetic'
    if attack=='duplicate':
     path=base/'plan'/'OUTCOME.json';path.write_text('{"outcome":"COMPLETED","outcome":"COMPLETED"}');selection['outcome_sha256']=sha(path.read_bytes())
    with self.assertRaises((S.Refused,OSError)):S.validate_selection(selection,'auth',base,t7)
 def test_unisolated_python_bad_pin_and_unexpected_environment_refuse(self):
  cmd=command('auth','--synthetic')
  p=subprocess.run([cmd[0],*cmd[2:]],env=ENV,capture_output=True,timeout=20)
  self.assertNotEqual(p.returncode,0);self.assertEqual(json.loads(p.stdout)['code'],'trusted_isolated_python_required')
  bad=cmd.copy();bad[bad.index('--source-pins-sha256')+1]='0'*64
  p=subprocess.run(bad,env=ENV,capture_output=True,timeout=20);self.assertNotEqual(p.returncode,0);self.assertEqual(json.loads(p.stdout)['code'],'source_manifest_changed')
  p=subprocess.run(cmd,env={**ENV,'NODE_DEBUG':'http'},capture_output=True,timeout=20);self.assertNotEqual(p.returncode,0);self.assertEqual(json.loads(p.stdout)['code'],'unclean_environment')
 def test_native_encrypted_image_roundtrips_both_synthetic_components(self):
  for component,tables in [('auth',27),('storage',10)]:
   with self.subTest(component=component):
    p=subprocess.run(command(component,'--synthetic'),env=ENV,capture_output=True,timeout=150)
    value=json.loads(p.stdout);self.assertEqual(p.returncode,0,value);self.assertEqual(p.stderr,b'')
    self.assertEqual((value['status'],value['component'],value['tables'],value['rows']),('passed',component,tables,1))
    for field in ('aes256_image_verified','owned_child_stopped','owned_postgres_stopped','owned_image_detached','owned_scratch_removed','native_cells_verified'):self.assertTrue(value[field],value)
    self.assertFalse(value['production_restore_authority']);self.assertFalse(value['whole_system_recovery'])
 def test_controlled_interruption_confirms_owned_cleanup(self):
  p=subprocess.Popen(command('auth','--synthetic'),env={**ENV,'COLLECT_ENCRYPTED_CAPTURE_TEST_PAUSE':'before_node_spawn'},stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  try:
   ready,_,_=select.select([p.stderr],[],[],90);self.assertTrue(ready);self.assertEqual(p.stderr.readline(),b'COLLECT_SYNTHETIC_ARCHIVE_SPAWN_READY\n')
   p.send_signal(signal.SIGTERM);out,err=p.communicate(timeout=40)
  finally:
   if p.poll() is None:p.kill();p.wait(timeout=10)
  self.assertNotEqual(p.returncode,0);self.assertEqual(err,b'');value=json.loads(out);self.assertEqual(value['status'],'interrupted')
  for field in ('owned_child_stopped','owned_postgres_stopped','owned_image_detached','owned_scratch_removed'):self.assertTrue(value[field],value)
  self.assertFalse(value['native_cells_verified'])
if __name__=='__main__':unittest.main()

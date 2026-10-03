"""Apply only reviewed11 exact bytes after full private154 acceptance."""
from pathlib import Path
import datetime,fcntl,hashlib,importlib.util,json,os,stat,uuid
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
HERE=Path(__file__).resolve().parent
PROP=HERE.parent/'successor-observed-fixture-import-proposal1'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 plan=json.loads((PROP/'preparation-plan.json').read_bytes())
 assert sha(PROP/'packet-files.json')=='807bdc7169a82f50dfbf1ba0518e6f540cf1806874bc5357f1822d61c4b7cb9b'
 accepted=json.loads((HERE/'independent-current-readback.json').read_bytes());assert accepted['status']=='pass' and accepted['private_source_count']==154
 run=json.loads((HERE/'execution-result.json').read_bytes());assert run['status']=='pass' and run['private_source_unchanged'] and not run['root_source_drift']
 assert sha(HERE/'execution-result.json')==accepted['execution_result_sha256']
 spec=importlib.util.spec_from_file_location('preparer',PROP/'prepare_candidate.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
 mod.require_absent(plan)
 bodies={row['path']:mod.read_guard(row) for row in plan['all_read_guards']};mod.require_absent(plan)
 candidate=PROP/'candidate-stage1/source';expected=json.loads((PROP/'candidate-stage1/preparation-result.json').read_bytes())['candidate_source']
 for rel,digest in expected.items():assert sha(candidate/rel)==digest
 dest=ROOT/plan['loader_destination'];before=dest.read_bytes();before_hash=sha(dest)
 (HERE/'loader-before.ts').write_bytes(before)
 fd=os.open(dest,os.O_RDONLY|os.O_NOFOLLOW);fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
 created=[];temp=None
 try:
  mod.read_guard(plan['current_source144'][plan['loader_destination']])
  for row in plan['ten_exact_imports']:
   target=ROOT/row['destination'];body=bodies[row['original']['path']]
   assert all(bodies[c['path']]==body for c in row['corroborating_copies'])
   target.parent.mkdir(parents=True,exist_ok=True)
   for part in [target.parent,*target.parent.parents]:
    if part==ROOT:break
    assert not part.is_symlink()
   newfd=os.open(target,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o644)
   with os.fdopen(newfd,'wb') as stream:stream.write(body);stream.flush();os.fsync(stream.fileno());os.fchmod(stream.fileno(),0o644)
   assert sha(target)==row['original']['sha256'];created.append(row['destination'])
  mod.read_guard(plan['current_source144'][plan['loader_destination']])
  temp=dest.parent/('.root-successor-loader-'+uuid.uuid4().hex+'.tmp');body=bodies[plan['loader_candidate']['path']]
  tmpfd=os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,plan['current_source144'][plan['loader_destination']]['identity'][5])
  with os.fdopen(tmpfd,'wb') as stream:stream.write(body);stream.flush();os.fsync(stream.fileno());os.fchmod(stream.fileno(),plan['current_source144'][plan['loader_destination']]['identity'][5])
  mod.read_guard(plan['current_source144'][plan['loader_destination']]);os.replace(temp,dest);temp=None
  for rel,digest in expected.items():assert sha(ROOT/rel)==digest,rel
  assert mod.dynamic_membership()==sorted(plan['dynamic_membership']+created)
  owned_paths={str(dest)}|{str(ROOT/p) for p in created}
  for row in plan['all_read_guards']:
   if row['path'] not in owned_paths:mod.read_guard(row)
  result={'status':'pass','at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'reviewed_changes_applied':11,'exclusive_new_fixtures':created,'loader':{'path':plan['loader_destination'],'before_sha256':before_hash,'after_sha256':sha(dest)},'current_source154_matches_accepted_private_source':True,'current_source_after':expected,'all_other_original_read_guards_unchanged':True,'tests_reused_only_by_exact_hash_agreement':True,'acceptance':accepted['canonical_counts'],'current_SQL_executed':False,'hosted_or_provider_or_device_acceptance':False,'whole_finding_closed':False}
  (HERE/'promotion-result.json').write_text(json.dumps(result,indent=2)+'\n');(HERE/'loader-after.ts').write_bytes(dest.read_bytes())
  print(json.dumps({'status':'pass','applied':11,'source154_hashes_equal':True,'runtime_tests_repeated':0}))
 except BaseException as exc:
  (HERE/'promotion-refusal.json').write_text(json.dumps({'status':'refused','reason':str(exc),'created_paths':created,'loader_current_sha256':sha(dest),'temporary_path':str(temp) if temp else None,'rollback_not_performed':True},indent=2)+'\n');raise
 finally:fcntl.flock(fd,fcntl.LOCK_UN);os.close(fd)
if __name__=='__main__':main()

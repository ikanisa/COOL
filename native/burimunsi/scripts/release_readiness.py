#!/usr/bin/env python3
"""Evidence completeness gate; never builds, signs, deploys or authorizes money movement.
Artifact checks verify local bytes, not the truth of a human-supplied attestation.
Existing signed-APK verification and explicit release authority remain mandatory.
"""
import argparse,hashlib,json,pathlib,sys
REQUIRED={
 'source_reconciliation':'actual_working_checkout',
 'database_qualification':'real_postgresql',
 'canonical_writer':'real_collect_ledger',
 'native_staff':'built_installed_staff_apk',
 'native_receiver':'built_installed_receiver_apk',
 'phone_journeys':'physical_carrier_sim_to_ledger',
 'security_acceptance':'independent_security_assessment',
 'recovery_drill':'restoration_and_receiver_replacement',
 'signed_distribution':'verified_release_artifacts',
 'operations_authorization':'responsible_owner_authorization'
}
# Build may precede distribution and final owner authorization. Promotion may not.
BUILD_REQUIRED={k:v for k,v in REQUIRED.items() if k not in {'signed_distribution','operations_authorization'}}
BUILD_TASK_IDS={f'T{i:03}' for i in range(1,59)}
def evaluate(status,evidence,base,phase='promotion'):
 errors=[]
 if phase not in {'build','promotion'}:return {'ready':False,'errors':['Invalid phase'],'phase':phase}
 tasks=status.get('tasks',[])
 ids=[t.get('id') for t in tasks]
 if len(ids)!=65 or set(ids)!={f'T{i:03}' for i in range(1,66)}:errors.append('The complete unique 65-task register is required.')
 for t in tasks:
  # Required P1 tasks do not disappear just because they are not P0.
  if (phase=='promotion' or t.get('id') in BUILD_TASK_IDS) and t.get('production_status')!='CLOSED':errors.append(f"{t.get('id','unknown')}: production acceptance remains open")
 if status.get('version')!=evidence.get('source_version'):errors.append('Evidence/source version mismatch.')
 supplied=evidence.get('checks',{})
 for name,scope in (REQUIRED if phase=='promotion' else BUILD_REQUIRED).items():
  item=supplied.get(name,{})
  if item.get('status')!='PASS' or item.get('scope')!=scope:
   errors.append(name+': required executed evidence absent or wrong scope');continue
  raw=item.get('path')
  if not isinstance(raw,str) or not raw:errors.append(name+': artifact path missing');continue
  p=pathlib.Path(raw)
  if p.is_absolute() or '..' in p.parts:errors.append(name+': unsafe artifact path');continue
  p=base/p
  if p.is_symlink() or not p.is_file() or base.resolve() not in p.resolve().parents:
   errors.append(name+': artifact absent or outside evidence root');continue
  if hashlib.sha256(p.read_bytes()).hexdigest()!=item.get('sha256'):errors.append(name+': artifact checksum mismatch')
 return {'ready':not errors,'errors':errors,'phase':phase,'meaning':'Evidence completeness only, not authenticity, deployment or legal/release authorization.'}
def main():
 p=argparse.ArgumentParser();p.add_argument('--status',type=pathlib.Path,required=True);p.add_argument('--evidence',type=pathlib.Path,required=True);p.add_argument('--phase',choices=['build','promotion'],default='promotion');p.add_argument('--guard-evidence',type=pathlib.Path);a=p.parse_args()
 root=pathlib.Path(__file__).resolve().parents[3]
 sys.path.insert(0,str(root/'scripts'))
 from release_guard import load
 from release_guard_adapter import enforce
 result=evaluate(load(a.status),load(a.evidence),a.evidence.resolve().parent,a.phase)
 result['errors'].extend(enforce(root,'BuriMunsi',a.phase,a.guard_evidence,legacy=a.evidence,status=a.status))
 result['ready']=not result['errors'];result['production_authorized']=False
 print(json.dumps(result,indent=2));return 0 if result['ready'] else 2
if __name__=='__main__':
 try:sys.exit(main())
 except (OSError,ValueError,TypeError,KeyError,AttributeError,RecursionError) as e:print(json.dumps({'ready':False,'error':type(e).__name__}));sys.exit(2)

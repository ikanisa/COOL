#!/usr/bin/env python3
"""Evidence completeness gate; never builds, signs, deploys or authorizes money movement.
Artifact checks verify local bytes, not the truth of a human-supplied attestation.
Existing signed-APK verification and explicit release authority remain mandatory.
"""
import argparse,datetime as dt,hashlib,json,os,pathlib,re,stat,sys
from urllib.parse import urlsplit
COLLECT_CLOUD_ORIGIN='https://rrlduytparvsjfmegalh.supabase.co'
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

class CandidateRejected(ValueError):pass
def _need(value,code):
 if not value:raise CandidateRejected(code)
def _object(raw):
 _need(len(raw)<=8*1024*1024,'CANDIDATE_JSON_BOUND')
 def pairs(items):
  result={}
  for k,v in items:_need(k not in result,'CANDIDATE_DUPLICATE_FIELD');result[k]=v
  return result
 def bad(_):raise CandidateRejected('CANDIDATE_INVALID_JSON')
 value=json.loads(raw,object_pairs_hook=pairs,parse_constant=bad)
 _need(type(value) is dict,'CANDIDATE_OBJECT_REQUIRED');return value
def _keys(value,names):_need(type(value) is dict and set(value)==set(names),'CANDIDATE_FIELDS_WRONG')
def _digest(value):_need(type(value) is str and re.fullmatch('[a-f0-9]{64}',value),'CANDIDATE_DIGEST_WRONG');return value
def _physical(path,maximum=8*1024*1024):
 path=pathlib.Path(path).absolute()
 _need(path.resolve()==path and all(not p.is_symlink() for p in (path,*path.parents)),'CANDIDATE_LINK_REFUSED')
 stamp=lambda s:(s.st_dev,s.st_ino,s.st_mode,s.st_nlink,s.st_size,s.st_mtime_ns,s.st_ctime_ns)
 with os.fdopen(os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK),'rb') as stream:
  info=os.fstat(stream.fileno());_need(stat.S_ISREG(info.st_mode) and info.st_nlink==1 and 0<info.st_size<=maximum,'CANDIDATE_FILE_BOUND')
  _need(stamp(info)==stamp(path.lstat()),'CANDIDATE_FILE_CHANGED');raw=stream.read(maximum+1)
  _need(len(raw)==info.st_size and stamp(info)==stamp(os.fstat(stream.fileno()))==stamp(path.lstat()) and path.resolve()==path,'CANDIDATE_FILE_CHANGED')
 return raw
def _ref(base,ref,json_value=True):
 _keys(ref,('path','sha256'));_digest(ref['sha256'])
 name=ref['path'];_need(type(name) is str and re.fullmatch('[A-Za-z0-9_. /-]+',name) and '\\' not in name,'CANDIDATE_PATH_WRONG')
 rel=pathlib.Path(name);_need(not rel.is_absolute() and all(p not in ('..','.') for p in rel.parts),'CANDIDATE_PATH_WRONG')
 path=base/rel;raw=_physical(path,64*1024*1024 if not json_value else 8*1024*1024)
 _need(hashlib.sha256(raw).hexdigest()==ref['sha256'],'CANDIDATE_ARTIFACT_CHANGED')
 return (_object(raw) if json_value else raw),path
def _fresh(value,now):
 _need(type(value) is str and len(value)<=40,'CANDIDATE_TIME_WRONG')
 try:t=dt.datetime.fromisoformat(value.replace('Z','+00:00'))
 except ValueError:raise CandidateRejected('CANDIDATE_TIME_WRONG') from None
 _need(t.tzinfo is not None and t.utcoffset()==dt.timedelta(0) and 0<=(now-t).total_seconds()<=86400,'CANDIDATE_EVIDENCE_STALE')
 return t
def _origin(value):
 _need(type(value) is str and len(value)<=2048 and not re.search(r'[\s\\\x00-\x1f\x7f]',value),'CANDIDATE_ORIGIN_WRONG')
 u=urlsplit(value)
 _need(u.scheme=='https' and u.hostname and '.' in u.hostname and u.netloc==u.hostname and not u.path and not u.query and not u.fragment,'CANDIDATE_ORIGIN_WRONG')
 _need(len(u.hostname)<=253 and all(re.fullmatch('[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?',label) for label in u.hostname.split('.')) and
       not re.fullmatch('[0-9.]+',u.hostname),'CANDIDATE_ORIGIN_WRONG');return value
def _configuration(profile,properties):
 _keys(profile,('format','id','mode','environment','supabase_origin','member_api_origin','admin_origin','public_origin','google_callback_origin'))
 _need(profile['format']=='collect.deployment.v1' and profile['mode']=='managed' and profile['environment'] in ('production','qualification') and
       type(profile['id']) is str and re.fullmatch('[a-z][a-z0-9-]{0,62}',profile['id']),'CANDIDATE_PROFILE_WRONG')
 for k in profile:
  if k.endswith('_origin'):_origin(profile[k])
 _need(profile['supabase_origin']==profile['admin_origin']==profile['member_api_origin']==COLLECT_CLOUD_ORIGIN,'CANDIDATE_PROFILE_MISMATCH')
 _need(profile['google_callback_origin'] in (profile['admin_origin'],profile['member_api_origin']),'CANDIDATE_PROFILE_WRONG')
 fields=('collectSupabaseOrigin','collectAdminOrigin','burimunsiApiOrigin','burimunsiApiPathPrefix','collectGatewayOrigin',
         'collectPublishableKey')
 _keys(properties,fields)
 _need(all(type(v) is str for v in properties.values()),'CANDIDATE_PUBLIC_FIELDS_WRONG')
 _need(properties['collectSupabaseOrigin']==properties['burimunsiApiOrigin']==profile['supabase_origin'] and
       properties['collectAdminOrigin']==profile['admin_origin'] and properties['burimunsiApiPathPrefix'] in ('','/functions/v1/collect-api') and
       properties['collectGatewayOrigin']==profile['supabase_origin']+properties['burimunsiApiPathPrefix'],'CANDIDATE_PROFILE_MISMATCH')
 _need(re.fullmatch('sb_publishable_[A-Za-z0-9_-]{10,300}',properties['collectPublishableKey']),'CANDIDATE_PUBLIC_KEY_WRONG')
 return hashlib.sha256(json.dumps(profile,sort_keys=True,separators=(',',':')).encode()).hexdigest()

def evaluate_candidate(evidence_path,profile_path,properties,*,pipeline=None,now=None):
 """Current local compilation prerequisites, never a promotion/signing grant.
 Rechecks actual retained bytes and parsed test streams. As with the legacy
 gate, hashes establish integrity, not independent provenance/authenticity.
 """
 result={'ready':False,'phase':'testing-candidate','candidate_build_only':True,'production_authorized':False,
         'signing_authorized':False,'distribution_authorized':False,'errors':[]}
 try:
  if pipeline is None:
   import native_pipeline as pipeline
  now=now or dt.datetime.now(dt.timezone.utc)
  base=pathlib.Path(evidence_path).absolute().parent
  _need(not any(base.is_relative_to(p) for p in (pipeline.ROOT,pipeline.OVERLAY/'upstream/collect')),'CANDIDATE_EVIDENCE_INSIDE_SOURCE')
  manifest=_object(_physical(evidence_path));profile=_object(_physical(profile_path))
  _keys(manifest,('format','purpose','created_at','source_sha256','profile_sha256','properties','qualification'))
  _need(manifest['format']=='collect.burimunsi.testing-candidate.v1' and manifest['purpose']=='testing-candidate-build','CANDIDATE_PURPOSE_WRONG')
  created=_fresh(manifest['created_at'],now)
  _need(manifest['properties']==properties,'CANDIDATE_PUBLIC_PROPERTIES_MISMATCH')
  profile_sha=_configuration(profile,properties);_need(manifest['profile_sha256']==profile_sha,'CANDIDATE_PROFILE_MISMATCH')
  current=pipeline.source_fingerprint()
  for row in current['files']:_physical(pipeline.OVERLAY/row['path'],64*1024*1024)
  _need(_digest(manifest['source_sha256'])==current['sha256'],'CANDIDATE_SOURCE_CHANGED')
  q=manifest['qualification'];_keys(q,('build_result','source_fingerprint','artifacts','instrumentation_result','device_inspections','instrumentation_logs'))
  build,_=_ref(base,q['build_result']);fingerprint,_=_ref(base,q['source_fingerprint']);inventory,inventory_path=_ref(base,q['artifacts'])
  device,_=_ref(base,q['instrumentation_result'])
  _need(fingerprint==current and inventory.get('source_sha256')==current['sha256'],'CANDIDATE_SOURCE_CHANGED')
  _need(build.get('status')=='PASS' and build.get('native_build_executed') is True and build.get('apk_inspection_passed') is True and
        build.get('artifact_count')==8 and build.get('production_deployment') is False,'CANDIDATE_BUILD_NOT_QUALIFIED')
  _need(_fresh(build.get('finished_at'),now)<=created and _fresh(device.get('finished_at'),now)<=created,'CANDIDATE_TIME_WRONG')
  contracts=pipeline.test_contracts();_need(inventory.get('expected_tests_per_flavor')==contracts,'CANDIDATE_TEST_CONTRACT_CHANGED')
  rows=inventory.get('artifacts',[]);specs=pipeline.artifacts();_need(len(rows)==len(specs)==8,'CANDIDATE_ARTIFACTS_WRONG')
  native={}
  for spec in specs:
   expected={'flavor':spec.flavor,'kind':spec.kind,'test':spec.test};matches=[r for r in rows if r.get('spec')==expected]
   _need(len(matches)==1,'CANDIDATE_ARTIFACTS_WRONG');row=matches[0]
   _need(row.get('package')==spec.package and row.get('ok') is True and row.get('failures')==[],'CANDIDATE_ARTIFACTS_WRONG')
   raw,_=_ref(inventory_path.parent,{'path':row.get('path'),'sha256':row.get('sha256')},False)
   _need(len(raw)==row.get('bytes'),'CANDIDATE_ARTIFACTS_WRONG')
   if spec.kind=='qualification':
    _need(row.get('optimized_unsigned_qualification') is True and row.get('signature_verified') is False and row.get('certificate_sha256') is None,'CANDIDATE_ARTIFACTS_WRONG')
   else:_need(row.get('signature_verified') is True and _digest(row.get('certificate_sha256')),'CANDIDATE_ARTIFACTS_WRONG')
   if spec.kind=='nativeTest':native[spec.package]=row
  inspections=q['device_inspections'];_need(type(inspections) is list and len(inspections)==4,'CANDIDATE_DEVICE_INSPECTIONS_WRONG')
  seen=set()
  for ref in inspections:
   checked,_=_ref(base,ref);package=checked.get('package');_need(package in native and package not in seen,'CANDIDATE_DEVICE_INSPECTIONS_WRONG');seen.add(package)
   row=native[package]
   _need(all(checked.get(k)==row.get(k) for k in ('spec','package','bytes','sha256','certificate_sha256','signature_verified','ok','failures')),'CANDIDATE_DEVICE_INSPECTIONS_WRONG')
  for flavor in contracts:
   app=pipeline.Artifact(flavor,'nativeTest').package
   _need(native[app]['certificate_sha256']==native[app+'.test']['certificate_sha256'],'CANDIDATE_DEVICE_INSPECTIONS_WRONG')
  _need(device.get('status')=='PASS' and device.get('installation_executed') is True and device.get('instrumentation_executed') is True and
        device.get('production_deployment') is False and type(device.get('device_api')) is int and device['device_api']>=26,'CANDIDATE_DEVICE_NOT_QUALIFIED')
  cleanup=device.get('cleanup',[])
  _need(type(cleanup) is list and len(cleanup)==4 and all(r.get('removed') is True for r in cleanup) and
        {r.get('package') for r in cleanup}==set(native),'CANDIDATE_DEVICE_CLEANUP_WRONG')
  logs=q['instrumentation_logs'];_keys(logs,contracts)
  flavors=device.get('flavors',[]);_need(len(flavors)==2,'CANDIDATE_TEST_CONTRACT_CHANGED')
  for flavor,expected in contracts.items():
   text,_=_ref(base,logs[flavor],False);parsed=pipeline.parse_instrumentation(text.decode('utf8'),set(expected))
   matches=[r for r in flavors if r.get('flavor')==flavor]
   _need(parsed.get('passed') is True and len(matches)==1 and all(matches[0].get(k)==v for k,v in parsed.items()),'CANDIDATE_TEST_CONTRACT_CHANGED')
  _need(pipeline.source_fingerprint()==current,'CANDIDATE_SOURCE_CHANGED')
  result.update(ready=True,source_sha256=current['sha256'],profile_sha256=profile_sha)
 except CandidateRejected as error:result['errors']=[str(error)]
 except (OSError,ValueError,TypeError,KeyError,AttributeError,RecursionError):result['errors']=['CANDIDATE_INPUT_UNAVAILABLE']
 return result

def main():
 p=argparse.ArgumentParser();p.add_argument('--status',type=pathlib.Path);p.add_argument('--evidence',type=pathlib.Path,required=True);p.add_argument('--phase',choices=['build','promotion','testing-candidate'],default='promotion');p.add_argument('--guard-evidence',type=pathlib.Path);p.add_argument('--profile',type=pathlib.Path);a=p.parse_args()
 if a.phase=='testing-candidate':
  if a.status or a.guard_evidence or not a.profile:result={'ready':False,'errors':['CANDIDATE_INPUT_MODE_WRONG'],'production_authorized':False}
  else:
   try:properties=_object(os.environ.get('BURI_BUILD_PUBLIC_PROPERTIES','').encode())
   except (ValueError,TypeError):properties={}
   result=evaluate_candidate(a.evidence,a.profile,properties)
  print(json.dumps(result,indent=2));return 0 if result['ready'] else 2
 if a.status is None or a.profile is not None:
  print(json.dumps({'ready':False,'errors':['Legacy status required; candidate profile is a separate phase.'],'production_authorized':False}));return 2
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

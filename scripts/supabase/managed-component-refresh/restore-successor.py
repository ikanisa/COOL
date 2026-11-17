#!/usr/bin/env python3
"""Independently pinned selector for the historical encrypted-image supervisor.

No provider connection, live database operation, or real restore is performed
by synthetic tests. Real mode requires a separately pinned metadata selection.
"""
import argparse
import contextlib
import hashlib
import io
import json
import os
import pathlib
import re
import stat
import sys
import types

HERE=pathlib.Path(__file__).resolve().parent
ROOT=HERE.parents[2]
LEGACY=ROOT/'scripts/supabase/current-pg-transfer/encrypted-inert-restore'
PINS=HERE/'RESTORE-SOURCE-PINS.json'
PYTHON='/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9'
PRIVATE_BASE=pathlib.Path('/Users/jeanbosco/Library/Application Support/Collect-Cloud-Recovery/production-metadata-20261113-122116')
T7_BASE=pathlib.Path('/Volumes/T7/01 Projects/COLLECT/outputs/cloud-supabase-assessment-2026-11-14')
PROJECT='rrlduytparvsjfmegalh'
HASH=re.compile(r'^[a-f0-9]{64}$')
CORE_MANIFEST={'auth':'59749471b55e30e62e9ab1ed65bc7621bac12da36fdf3d5b3416e4107b75b0e2',
               'storage':'fed3d9911c17cb794099ebaa45fae1115558fa014da88f969b27af2abf693c3f'}
CORE_SHA='b6a76174ad4af587150f2428d41957280881a4b26e50c05233a950ea7dd088f8'
PLAN_SOURCE='00cd926d3f524334fef028458d49f6de70755f837bfb156ab17d7f5467e259b4'
LIVE_SOURCE='f8d7889c5bee8de0f873039482b377d9dc964d1e259806a2aa2cf2896d396150'
FILES=(
 'scripts/supabase/managed-component-refresh/restore-successor.py',
 'scripts/supabase/managed-component-refresh/restore-successor.test.py',
 'scripts/supabase/managed-component-refresh/RESTORE-SUCCESSOR.md',
 'scripts/supabase/current-pg-transfer/encrypted-inert-restore/managed-supervisor.py',
 'scripts/supabase/current-pg-transfer/encrypted-inert-restore/managed-capture.mjs',
 'scripts/supabase/current-pg-transfer/encrypted-inert-restore/AUTH-SOURCE-PINS.json',
 'scripts/supabase/current-pg-transfer/encrypted-inert-restore/STORAGE-SOURCE-PINS.json',
)

class Refused(Exception): pass
def need(condition,code):
 if not condition:raise Refused(code)
def sha(data):return hashlib.sha256(data).hexdigest()
def unique(pairs):
 value={}
 for key,item in pairs:
  need(key not in value,'duplicate_json_key');value[key]=item
 return value
def parse(data):
 try:return json.loads(data.decode('utf8','strict'),object_pairs_hook=unique)
 except (UnicodeError,ValueError) as e:raise Refused('json_invalid') from e
def exact(value,keys):return isinstance(value,dict) and set(value)==set(keys)
def absolute(path):
 return isinstance(path,str) and len(path)<=4096 and pathlib.Path(path).is_absolute() and str(pathlib.Path(path))==path
def under(path,root):
 try:pathlib.Path(path).relative_to(root);return pathlib.Path(path)!=root
 except ValueError:return False
def directory(path):
 p=pathlib.Path(path);s=p.lstat()
 need(p.is_absolute() and p.resolve()==p and stat.S_ISDIR(s.st_mode) and not p.is_symlink() and s.st_uid==os.getuid() and s.st_mode&0o777==0o700,'private_directory_required')
def read_stable(path,maximum,private=False):
 p=pathlib.Path(path);need(absolute(str(p)) and p.resolve()==p,'file_path_invalid')
 if private:directory(p.parent)
 before=p.lstat();need(stat.S_ISREG(before.st_mode) and not p.is_symlink() and before.st_nlink==1 and 0<=before.st_size<=maximum,'file_invalid')
 if private:need(before.st_uid==os.getuid() and before.st_mode&0o777==0o600,'private_file_required')
 fd=os.open(p,os.O_RDONLY|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_NONBLOCK',0));data=bytearray()
 identity=lambda s:(s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns,s.st_nlink,s.st_uid,s.st_mode)
 try:
  initial=os.fstat(fd);need(identity(initial)==identity(before),'file_changed')
  while len(data)<initial.st_size:
   part=os.read(fd,min(65536,initial.st_size-len(data)))
   if not part:break
   data.extend(part)
  extra=os.read(fd,1);after=os.fstat(fd);last=p.lstat()
  need(len(data)==initial.st_size and not extra and identity(after)==identity(initial)==identity(last),'file_changed')
  if private:directory(p.parent)
  return bytes(data)
 finally:data[:]=b'\0'*len(data);os.close(fd)
def pinned_json(path,digest):
 need(HASH.fullmatch(digest or '') is not None,'digest_required');raw=read_stable(path,131072,private=True)
 need(sha(raw)==digest,'pinned_file_changed');return parse(raw)
def verify_sources(expected):
 need(HASH.fullmatch(expected or '') is not None,'source_pin_required');raw=read_stable(PINS,131072)
 need(sha(raw)==expected,'source_manifest_changed');pins=parse(raw)
 need(exact(pins,('format','files','python')) and pins['format']=='collect.managed-component-refresh.restore.sources.v1' and
  isinstance(pins['files'],dict) and set(pins['files'])==set(FILES) and exact(pins['python'],('path','sha256')) and
  pins['python']['path']==PYTHON and HASH.fullmatch(pins['python']['sha256'] or '') is not None and
  sha(read_stable(PYTHON,16*1024*1024))==pins['python']['sha256'],'source_manifest_invalid')
 source=None
 for item in FILES:
  need(HASH.fullmatch(pins['files'][item] or '') is not None,'source_manifest_invalid')
  content=read_stable(ROOT/item,16*1024*1024);need(sha(content)==pins['files'][item],'source_changed')
  if item.endswith('/managed-supervisor.py'):source=content
 need(source is not None and sha(source)==CORE_SHA and sha(read_stable(LEGACY/'AUTH-SOURCE-PINS.json',131072))==CORE_MANIFEST['auth'] and
  sha(read_stable(LEGACY/'STORAGE-SOURCE-PINS.json',131072))==CORE_MANIFEST['storage'],'legacy_source_changed')
 return source

def hash_ciphertext(path,maximum=6*1024*1024):
 p=pathlib.Path(path);need(absolute(str(p)) and p.resolve()==p,'ciphertext_path_invalid');directory(p.parent)
 before=p.lstat();need(stat.S_ISREG(before.st_mode) and not p.is_symlink() and before.st_uid==os.getuid() and before.st_nlink==1 and
  before.st_mode&0o777 in (0o600,0o700) and 0<before.st_size<=maximum,'ciphertext_invalid')
 fd=os.open(p,os.O_RDONLY|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_NONBLOCK',0));h=hashlib.sha256()
 identity=lambda s:(s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns,s.st_nlink,s.st_uid,s.st_mode)
 try:
  first=os.fstat(fd);need(identity(first)==identity(before),'ciphertext_changed');total=0
  while total<first.st_size:
   chunk=os.read(fd,min(65536,first.st_size-total));need(bool(chunk),'ciphertext_changed');h.update(chunk);total+=len(chunk)
  need(not os.read(fd,1) and identity(os.fstat(fd))==identity(first)==identity(p.lstat()),'ciphertext_changed');directory(p.parent)
  return h.hexdigest(),total
 finally:os.close(fd)

SELECTION=('format','component','project_ref','plan_path','plan_sha256','outcome_sha256','count_claim_sha256',
           'result_path','result_sha256','ciphertext_copy','ciphertext_sha256','snapshot_sha256')
def validate_selection(value,component,private_base=PRIVATE_BASE,t7_base=T7_BASE):
 need(exact(value,SELECTION) and value['format']=='collect.managed-component-refresh.restore-selection.v1' and
  value['component']==component and value['project_ref']==PROJECT,'selection_invalid')
 for k in ('plan_sha256','outcome_sha256','count_claim_sha256','result_sha256','ciphertext_sha256','snapshot_sha256'):
  need(isinstance(value[k],str) and HASH.fullmatch(value[k]) is not None,'selection_invalid')
 for k in ('plan_path','result_path'):
  need(absolute(value[k]) and under(value[k],private_base),'selection_path_invalid')
 need(absolute(value['ciphertext_copy']) and under(value['ciphertext_copy'],t7_base),'selection_path_invalid')
 plan=pinned_json(value['plan_path'],value['plan_sha256']);need(isinstance(plan,dict) and plan.get('format')=='collect.managed-component-capture.offline-plan.v1' and
  plan.get('project_ref')==PROJECT and plan.get('component')==component and plan.get('source_pins_sha256')==PLAN_SOURCE and
  plan.get('request_read_only') is True and plan.get('plan_only') is True and plan.get('capture_dispatched') is False and plan.get('full_recovery_acceptance') is False,'plan_invalid')
 count_path=plan.get('preflight_result_path');need(absolute(count_path) and under(count_path,private_base) and pathlib.Path(count_path).name=='RESULT.json','plan_invalid')
 count=pinned_json(count_path,plan.get('preflight_result_sha256'))
 need(isinstance(count,dict) and count.get('format')=='collect.managed-component-preflight.result.v1' and count.get('project_ref')==PROJECT and
  count.get('component')==component and count.get('metadata_only') is True and count.get('real_data_capture') is False and
  count.get('canonical_counts_sha256')==plan.get('canonical_counts_sha256') and count.get('counts_file_sha256')==plan.get('counts_file_sha256'),'count_invalid')
 counts_path=plan.get('counts_path');need(absolute(counts_path) and pathlib.Path(counts_path).parent==pathlib.Path(count_path).parent,'count_invalid')
 pinned_json(counts_path,plan.get('counts_file_sha256'))
 count_claim=pathlib.Path(count_path).parent/'CAPTURE-ONCE.json';claim=pinned_json(count_claim,value['count_claim_sha256'])
 need(isinstance(claim,dict) and claim.get('format')=='collect.managed-component-capture.count-claim.v1' and claim.get('component')==component and
  claim.get('execution_mode')=='live' and claim.get('live_source_pins_sha256')==LIVE_SOURCE and claim.get('plan_path')==value['plan_path'] and
  claim.get('plan_sha256')==value['plan_sha256'] and claim.get('count_result_sha256')==plan.get('preflight_result_sha256') and
  claim.get('query_sha256')==plan.get('query_sha256') and claim.get('automatic_retry') is False,'claim_invalid')
 outcome=pinned_json(pathlib.Path(value['plan_path']).parent/'OUTCOME.json',value['outcome_sha256'])
 need(isinstance(outcome,dict) and outcome.get('format')=='collect.managed-component-capture.outcome.v1' and outcome.get('component')==component and
  outcome.get('execution_mode')=='live' and outcome.get('outcome')=='COMPLETED' and outcome.get('plan_sha256')==value['plan_sha256'] and
  outcome.get('provider_query_attempted') is True and outcome.get('transport_query_attempted') is True and outcome.get('automatic_retry') is False and
  outcome.get('full_recovery_acceptance') is False,'outcome_invalid')
 receipt=pinned_json(value['result_path'],value['result_sha256'])
 expected='collect.managed-auth.encrypted-write-receipt.v1' if component=='auth' else 'collect.managed-storage.metadata.encrypted-write-receipt.v1'
 need(isinstance(receipt,dict) and receipt.get('format')==expected and receipt.get('project_ref')==PROJECT and receipt.get('authenticated_readback') is True and
  receipt.get('full_recovery_acceptance') is False and receipt.get('automatic_retry') is False and receipt.get('native_rollback_command_complete_observed') is False and
  receipt.get('query_sha256')==plan.get('query_sha256') and receipt.get('counts_preflight_sha256')==plan.get('canonical_counts_sha256') and
  receipt.get('reference_sha256')==plan.get('reference_sha256') and receipt.get('archive_sha256')==value['ciphertext_sha256'] and
  receipt.get('snapshot_sha256')==value['snapshot_sha256'] and type(receipt.get('rows')) is int and 0<=receipt['rows']<=50000 and
  receipt.get('tables')==(27 if component=='auth' else 10),'receipt_invalid')
 if component=='auth':need(receipt.get('managed_auth_data_included') is True and receipt.get('storage_included') is False and receipt.get('operational_auth_restored') is False,'receipt_invalid')
 else:need(receipt.get('storage_metadata_included') is True and receipt.get('object_bodies_included') is False and receipt.get('operational_storage_restored') is False,'receipt_invalid')
 actual,size=hash_ciphertext(value['ciphertext_copy']);need(actual==value['ciphertext_sha256'] and size==receipt.get('archive_bytes'),'ciphertext_changed')
 return {'result_path':value['result_path'],'result':value['result_sha256'],'copy':value['ciphertext_copy'],
         'ciphertext':value['ciphertext_sha256'],'snapshot':value['snapshot_sha256']}

class Parser(argparse.ArgumentParser):
 def error(self,_message):raise Refused('invalid_arguments')
def args():
 parser=Parser(add_help=False);parser.add_argument('--component',choices=('auth','storage'),required=True)
 parser.add_argument('--source-pins-sha256',required=True);group=parser.add_mutually_exclusive_group(required=True)
 group.add_argument('--synthetic',action='store_true');group.add_argument('--real-capture',action='store_true')
 parser.add_argument('--selection');parser.add_argument('--selection-sha256');v=parser.parse_args()
 need((v.synthetic and v.selection is None and v.selection_sha256 is None) or
  (v.real_capture and absolute(v.selection) and HASH.fullmatch(v.selection_sha256 or '') is not None),'invalid_arguments');return v
def run():
 need(sys.flags.isolated==1 and sys.executable==PYTHON and sys.platform=='darwin' and os.geteuid()!=0,'trusted_isolated_python_required')
 v=args();allowed={'PATH','LC_ALL','PYTHONDONTWRITEBYTECODE','__CF_USER_TEXT_ENCODING'}
 if v.synthetic:allowed|={'COLLECT_ENCRYPTED_CAPTURE_TEST_PAUSE','COLLECT_ENCRYPTED_CAPTURE_TEST_TAMPER'}
 need(set(os.environ).issubset(allowed) and os.environ.get('PATH')=='/usr/bin:/bin:/usr/sbin:/sbin' and os.environ.get('LC_ALL')=='C','unclean_environment')
 os.environ.pop('__CF_USER_TEXT_ENCODING',None)
 source=verify_sources(v.source_pins_sha256);selected=None
 if v.real_capture:selected=validate_selection(pinned_json(v.selection,v.selection_sha256),v.component)
 module=types.ModuleType('collect_refresh_legacy_supervisor');module.__file__=str(LEGACY/'managed-supervisor.py')
 exec(compile(source,module.__file__,'exec'),module.__dict__)
 if selected is not None:module.EXPECTED[v.component]=selected
 sys.argv=[str(LEGACY/(v.component+'-managed-restore.py')),'--source-manifest-sha256',CORE_MANIFEST[v.component]]
 if v.synthetic:sys.argv+=['--synthetic']
 else:sys.argv+=['--real-capture','--capture-result',selected['result_path'],'--capture-result-sha256',selected['result'],
  '--ciphertext-copy',selected['copy'],'--ciphertext-sha256',selected['ciphertext'],'--snapshot-sha256',selected['snapshot']]
 captured=io.StringIO()
 try:
  with contextlib.redirect_stdout(captured):code=module.main(v.component)
 except (module.Refused,OSError,ValueError) as e:
  print(json.dumps({'status':'refused','code':str(e) if isinstance(e,module.Refused) else 'restore_unconfirmed'},separators=(',',':')));return 1
 try:
  result=json.loads(captured.getvalue());need(isinstance(result,dict),'core_result_unconfirmed')
  verify_sources(v.source_pins_sha256)
 except (Refused,OSError,ValueError):
  # Preserve any owned recovery path rather than discarding an unconfirmed core outcome.
  try:previous=json.loads(captured.getvalue())
  except (ValueError,TypeError):previous={}
  result={'status':'unconfirmed','code':'successor_postcheck_unconfirmed'}
  if isinstance(previous,dict) and isinstance(previous.get('preserved_root'),str):result['preserved_root']=previous['preserved_root']
  print(json.dumps(result,separators=(',',':')));return 1
 print(json.dumps(result,separators=(',',':')));return code
if __name__=='__main__':
 try:sys.exit(run())
 except (Refused,OSError,ValueError) as e:
  print(json.dumps({'status':'refused','code':str(e) if isinstance(e,Refused) else 'restore_unconfirmed'},separators=(',',':')));sys.exit(1)

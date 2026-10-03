from pathlib import Path
import hashlib,json,sys
base=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest={}
for line in(base/'FILES_SHA256').read_text().splitlines():
 digest,name=line.split('  ',1);path=Path(name)
 assert not path.is_absolute()and '..'not in path.parts and name not in manifest
 assert(base/path).is_file()and not(base/path).is_symlink()and sha(base/path)==digest,name
 manifest[name]=digest
actual={str(p.relative_to(base))for p in base.rglob('*')if p.is_file()}
assert actual==set(manifest)|{'FILES_SHA256'}
seal=json.loads((base/'SEAL.json').read_text())
payload={name:digest for name,digest in manifest.items()if name!='SEAL.json'}
encoded=''.join(digest+'  '+name+'\n'for name,digest in sorted(payload.items()))
assert len(payload)==seal['payload_member_count']
assert sum((base/name).stat().st_size for name in payload)==seal['payload_bytes']
assert hashlib.sha256(encoded.encode()).hexdigest()==seal['payload_manifest_sha256']
for name in payload:
 path=base/name
 if path.suffix=='.json':json.loads(path.read_text())
 else:path.read_text()
association=json.loads((base/'PROOF_ASSOCIATION.json').read_text())
assert association['private_backend']['composition']==[34,11,4]
assert association['private_backend']['composed_cases']==49
assert association['private_backend']['fresh_aggregate']==False
assert association['denial_correction']['cases']==13
assert association['Admin_predecessor']['VM_widget_cases']==17
assert association['Admin_predecessor']['Chrome_cases']==6
assert association['root_caller']['fresh_mounted_cases']==7
assert association['root_caller']['retained_affected_legacy_cases']==8
assert association['no_combined_unexecuted_aggregate']==True
assert association['full208_rehearsal_scope']=='separate_root_owned_scope'
assert association['hygiene_correction']['cases']==12
assert association['hygiene_correction']['command_exit']==0
assert association['root_caller']['fresh_aggregate_status']=='failed_due_to_then_uncorrected_hygiene'
assert association['root_caller']['retained_legacy_aggregate_status']=='failed_due_to_one_new_mount_case'
assert association['failed_mounted_aggregates']==['mounted-attempt1','mounted-attempt2','mounted-attempt3','mounted-attempt4']
assert json.loads((base/'PEER_REVIEW.json').read_text())['status']=='completed_no_concrete_defects_in_reviewed_scope'
for prefix in ['failed-root-inputs/mounted-attempt1','failed-root-inputs/mounted-attempt2','failed-root-inputs/mounted-attempt3','root-final/mounted-attempt4','root-final/hygiene-correction/current-attempt1']:
 result=json.loads((base/prefix/'result.json').read_text())
 for command in result['commands']:
  for stream in ['stdout','stderr']:
   assert sha(base/prefix/(command['name']+'.'+stream))==command[stream+'_sha256']
for prefix in ['failed-root-inputs/mounted-attempt1','failed-root-inputs/mounted-attempt2','failed-root-inputs/mounted-attempt3','root-final/mounted-attempt4']:
 assert json.loads((base/prefix/'result.json').read_text())['status']=='failed'
assert json.loads((base/'root-final/hygiene-correction/current-attempt1/result.json').read_text())['status']=='passed'
source=json.loads((base/'CURRENT_SOURCE_BINDING.json').read_text())
assert source['canonical_file_count']==16 and source['preserved_original_count']==3
for name,row in source['canonical_files'].items():assert sha(base/'source'/name)==row['sha256'],name
for name,row in source['preserved_originals'].items():assert sha(base/'originals'/name)==row['sha256'],name
if '--references'in sys.argv:
 references=json.loads((base/'REFERENCE_BINDING.json').read_text())['rows']
 for row in references:
  path=Path(row['path']);assert path.is_file()and path.stat().st_size==row['bytes']and sha(path)==row['sha256'],str(path)
print(json.dumps({'status':'verified','total_files':len(actual),'manifest_listed_members':len(manifest),'payload_members':len(payload),'files_sha256':sha(base/'FILES_SHA256'),'seal_sha256':sha(base/'SEAL.json'),'product_tests_rerun':False}))

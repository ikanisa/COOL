from pathlib import Path
import hashlib,json,sys
base=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
lines=(base/'FILES_SHA256').read_text().splitlines()
listed={}
for line in lines:
 digest,name=line.split('  ',1)
 path=Path(name)
 assert not path.is_absolute() and '..'not in path.parts and name not in listed
 assert (base/path).is_file() and not(base/path).is_symlink()
 assert sha(base/path)==digest,name
 listed[name]=digest
actual={str(p.relative_to(base))for p in base.rglob('*')if p.is_file()}
assert actual==set(listed)|{'FILES_SHA256'}
seal=json.loads((base/'SEAL.json').read_text())
payload={name:digest for name,digest in listed.items()if name!='SEAL.json'}
encoded=''.join(digest+'  '+name+'\n'for name,digest in sorted(payload.items()))
assert hashlib.sha256(encoded.encode()).hexdigest()==seal['payload_manifest_sha256']
assert len(payload)==seal['payload_member_count']
assert sum((base/name).stat().st_size for name in payload)==seal['payload_bytes']
# All included small metadata is parsed/read; no product commands, host or tests.
for name in payload:
 path=base/name
 if path.suffix=='.json':json.loads(path.read_text())
 elif path.suffix in{'.md','.py','.rb','.stdout','.stderr'}:path.read_text()
a=json.loads((base/'ROOT_SOURCE_ASSOCIATION.json').read_text())
assert a['unit_cases']==33 and a['unit_assertions']==155 and len(a['commands'])==4
assert a['SQL_checks_reused']==38 and a['selected_SQL_cohort']==205
for name,digest in a['canonical_sha256'].items():assert sha(base/'source'/name)==digest
result=json.loads((base/'selected-packet/proof/sql-attempt6/result.json').read_text())
assert result['status']=='passed'and len(result['checks'])==38 and all(x['passed']for x in result['checks'])
assert result['driver']['status']=='passed'and len(result['driver']['checks'])==30
assert result['driver']['full_data_comparison']=={'tables':272,'rows':6266,'sequences':4,'other_data':0,'all_match':True}
refs=json.loads((base/'SQL_COMMAND_REFERENCES.json').read_text())
assert refs['outer_command_count']==73 and refs['Ruby_command_count']==28
# Optional read-only association check against referenced original private artifacts.
if '--references'in sys.argv:
 binding=json.loads((base/'REFERENCE_BINDING.json').read_text())
 for row in binding['rows']:
  path=Path(row['path']);assert path.is_file() and path.stat().st_size==row['bytes']and sha(path)==row['sha256'],str(path)
print(json.dumps({'status':'verified','total_files':len(actual),'manifest_listed_members':len(listed),'payload_members':len(payload),'files_sha256':sha(base/'FILES_SHA256'),'seal_sha256':sha(base/'SEAL.json'),'product_tests_rerun':False}))

import hashlib,json,shutil
from pathlib import Path
ROOT=Path.cwd();STAGE=ROOT/'.cache/collect-native-recovery-custody-20261002';PACKET=STAGE/'check-attempt3'
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
result=json.loads((PACKET/'result.json').read_text())
if result['status']!='passed' or any(c['exit_code'] for c in result['commands']):raise SystemExit('Actual affected commands have not all passed')
if any(result[k] for k in ('canonical_changes','selected_changes','binary_changes')):raise SystemExit('Actual captured inputs drifted')
originals=json.loads((STAGE/'originals.json').read_text());owned={r['path']:r['sha256'] for r in originals}
if len(owned)!=5:raise SystemExit('Unexpected write boundary')
for rel,before in result['canonical_before_sha256'].items():
    if sha(ROOT/rel)!=before:raise SystemExit('Concurrent source change: '+rel)
for rel,digest in result['source_sha256'].items():
    if sha(Path(result['source_origin'][rel]))!=digest:raise SystemExit('Selected source changed: '+rel)
for p,digest in result['binary_sha256'].items():
    if sha(Path(p))!=digest:raise SystemExit('Runtime input changed: '+p)
for rel,before in owned.items():
    target=ROOT/rel;original=STAGE/'originals'/rel;source=STAGE/'promote'/rel
    if target.is_symlink() or original.is_symlink() or source.is_symlink():raise SystemExit('Linked write boundary')
    if sha(target)!=before or sha(original)!=before:raise SystemExit('Original source mismatch: '+rel)
    if sha(source)!=result['source_sha256'][rel]:raise SystemExit('Accepted overlay mismatch: '+rel)
rows=[]
for rel,before in owned.items():
    source=STAGE/'promote'/rel;shutil.copyfile(source,ROOT/rel)
    rows.append({'path':rel,'before_sha256':before,'after_sha256':sha(ROOT/rel)})
for rel,expected in result['source_sha256'].items():
    if sha(ROOT/rel)!=expected:raise SystemExit('Canonical submitted closure differs: '+rel)
association={'scope':result['scope'],'status':'integrated','files':rows,'result_sha256':sha(PACKET/'result.json'),'source_members':len(result['source_sha256']),'binary_members':len(result['binary_sha256']),'commands':[{k:c[k] for k in ('name','exit_code')} for c in result['commands']],'preserved_originals':5,'hosted_or_device_acceptance':False}
(STAGE/'CANONICAL_ASSOCIATION.json').write_text(json.dumps(association,indent=2)+'\n')
print(json.dumps({'status':'integrated','files':len(rows),'source_members':len(result['source_sha256']),'binary_members':len(result['binary_sha256'])}))

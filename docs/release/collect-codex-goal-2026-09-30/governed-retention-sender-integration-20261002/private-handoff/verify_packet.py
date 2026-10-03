from pathlib import Path
import argparse, hashlib, json
def digest(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest()
parser=argparse.ArgumentParser();parser.add_argument('--references',action='store_true');args=parser.parse_args()
root=Path(__file__).resolve().parent
seal=json.loads((root/'SEAL.json').read_text())
manifest=root/'FILES_SHA256'
assert digest(manifest)==seal['manifest_sha256']
listed={}
for line in manifest.read_text().splitlines():
    sha,rel=line.split('  ',1);p=root/rel
    assert p.is_file() and digest(p)==sha,rel
    listed[rel]=sha
actual={str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()}
assert actual==set(listed)|{'FILES_SHA256','SEAL.json'}
assert len(listed)==seal['listed_members'] and len(actual)==seal['total_members']
assert sum((root/p).stat().st_size for p in listed)==seal['listed_bytes']
count=0
if args.references:
    for path,binding in json.loads((root/'REFERENCES.json').read_text()).items():
        p=Path(path);assert p.is_file() and p.stat().st_size==binding['bytes'] and digest(p)==binding['sha256'],path
        count+=1
print(json.dumps({'status':'PASS','total_members':len(actual),'listed_members':len(listed),'manifest_sha256':digest(manifest),'references_verified':count}))

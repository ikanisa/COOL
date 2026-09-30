#!/usr/bin/env python3
"""Read-only full-checkout inventory. Never deletes an apparently unused asset."""
import argparse,hashlib,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[2]
r=subprocess.run(['git','ls-files','-z'],cwd=root,capture_output=True,check=True)
rows=[]
for name in r.stdout.decode().split('\0'):
    if not name:continue
    path=root/name
    if path.is_symlink() or not path.is_file():continue
    private=path.name.startswith('.env') or path.suffix.lower() in ('.jks','.keystore','.p12','.p8')
    row={'path':name,'bytes':path.stat().st_size,'classification':'private-review-required' if private else 'tracked'}
    if not private:row['sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
    rows.append(row)
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(json.dumps({'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
 'files':rows,'reachability_proven':False,'private_values_exported':False},indent=2)+'\n')

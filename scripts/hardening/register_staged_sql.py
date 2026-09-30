#!/usr/bin/env python3
"""Register staged SQL with actual CLI-generated names; never apply to a database."""
import argparse,pathlib,shutil,subprocess
p=argparse.ArgumentParser();p.add_argument('--register',action='store_true');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[2]
files=['receipt_security_v2','signed_otp_limits_v2','reconciliation_approval_v2']
if not a.register: print('CHECK ONLY: staged SQL requires full-schema review and rehearsal. Use --register only in the authorized full checkout.');raise SystemExit(0)
if not (root/'pubspec.yaml').is_file() or not (root/'supabase/migrations').is_dir(): raise SystemExit('Full checkout required')
if not shutil.which('supabase'):raise SystemExit('Pinned Supabase CLI required')
subprocess.run(['supabase','migration','new','--help'],check=True,cwd=root)
for name in files:
    before=set((root/'supabase/migrations').glob('*.sql'))
    subprocess.run(['supabase','migration','new',name],check=True,cwd=root)
    added=set((root/'supabase/migrations').glob('*.sql'))-before
    if len(added)!=1:raise SystemExit('Unexpected migration result; inspect before proceeding')
    destination=added.pop()
    if destination.stat().st_size!=0:raise SystemExit('Generated migration is not empty; refusing replacement')
    destination.write_bytes((root/'deploy/hardening'/f'{name}.sql').read_bytes())
    print(destination.relative_to(root))
print('Migration files registered only. Nothing was applied.')

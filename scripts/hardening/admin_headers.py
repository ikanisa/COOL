#!/usr/bin/env python3
"""Add conservative Admin static-asset headers, never weaken existing policy.
Read-only by default. Does not configure live hosting or clear existing service
worker caches; do not claim those release gates from this build-time helper.
"""
from __future__ import annotations
import argparse,os,pathlib,tempfile
POLICY='''/*
  Cache-Control: no-store
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer
  X-Frame-Options: DENY
  Content-Security-Policy: base-uri 'self'; object-src 'none'; frame-ancestors 'none'
'''
class PolicyConflict(ValueError): pass

def plan(directory:pathlib.Path)->bool:
    if directory.is_symlink() or not directory.is_dir():raise PolicyConflict('Build directory required')
    if any(p.is_symlink() for p in directory.parents):raise PolicyConflict('Symlink ancestor rejected')
    for name in ['index.html','main.dart.js']:
        p=directory/name
        if p.is_symlink() or not p.is_file():raise PolicyConflict('Complete Admin build required')
    target=directory/'_headers'
    if target.is_symlink():raise PolicyConflict('Symlink header policy rejected')
    if target.exists():
        if not target.is_file() or target.read_bytes()!=POLICY.encode():
            raise PolicyConflict('Existing policy requires explicit review; not overwritten')
        return False
    return True

def install(directory:pathlib.Path)->bool:
    if not plan(directory):return False
    target=directory/'_headers'
    # Exclusive create fails if another writer installs any policy concurrently.
    with target.open('xb') as handle:
        handle.write(POLICY.encode());handle.flush();os.fsync(handle.fileno())
    return True

def main():
    p=argparse.ArgumentParser();p.add_argument('directory',type=pathlib.Path);p.add_argument('--apply',action='store_true');a=p.parse_args()
    changed=install(a.directory) if a.apply else plan(a.directory)
    print(('INSTALLED' if a.apply else 'CHECK_ONLY')+(': change' if changed else ': already matches'))
if __name__=='__main__':
    try:main()
    except (PolicyConflict,OSError) as error:print('BLOCKED: '+str(error));raise SystemExit(2)

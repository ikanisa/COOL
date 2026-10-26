#!/usr/bin/env python3
"""Fail-closed release evidence validation. Never creates or approves evidence."""
from __future__ import annotations
import argparse, datetime as dt, hashlib, json, pathlib, re
GATES=('G0','G1','G2','G3','G4','G5')
class Blocked(ValueError): pass

def safe_file(root:pathlib.Path, relative:str)->pathlib.Path:
    if not isinstance(relative,str) or not relative or '\\' in relative: raise Blocked('Invalid evidence path')
    rel=pathlib.PurePosixPath(relative)
    if rel.is_absolute() or '..' in rel.parts or rel.as_posix()!=relative: raise Blocked('Unsafe evidence path')
    p=root/relative
    for part in [p,*p.parents]:
        if part==root:break
        if part.is_symlink():raise Blocked('Symlink evidence not accepted')
    if not p.is_file():raise Blocked('Evidence missing')
    return p

def validate(payload:dict, root:pathlib.Path, expected_commit:str, now:dt.datetime)->list[str]:
    errors=[]
    if not re.fullmatch(r'[a-f0-9]{40}',expected_commit):return ['Expected commit is not an exact SHA']
    if payload.get('schema_version')!=1 or payload.get('source_commit')!=expected_commit:return ['Evidence is not bound to the expected commit']
    entries=payload.get('gates')
    if not isinstance(entries,list) or len(entries)!=6:return ['Six gates are required']
    if [x.get('id') for x in entries if isinstance(x,dict)]!=list(GATES):return ['Gate IDs must be unique and ordered G0-G5']
    for item in entries:
        gate=item['id']
        try:
            if item.get('status')!='passed':raise Blocked('Not passed')
            if not item.get('performed_by') or not item.get('approved_by'):raise Blocked('Named performance and approval required')
            if item['performed_by']==item['approved_by']:raise Blocked('Independent approval required')
            time=dt.datetime.fromisoformat(item['verified_at'].replace('Z','+00:00'))
            if time.tzinfo is None or (now-time).total_seconds() < -60 or (now-time)>dt.timedelta(hours=72):raise Blocked('Evidence is stale or future-dated')
            evidence=item.get('evidence')
            if not isinstance(evidence,list) or not evidence:raise Blocked('Gate has no evidence')
            for e in evidence:
                p=safe_file(root,e['path']);sha=hashlib.sha256(p.read_bytes()).hexdigest()
                if not re.fullmatch(r'[a-f0-9]{64}',str(e.get('sha256',''))) or sha!=e['sha256']:raise Blocked('Evidence checksum mismatch')
                if e.get('source_commit')!=expected_commit:raise Blocked('Evidence artifact commit mismatch')
            if gate in ('G1','G2','G4') and item.get('execution_verified') is not True:raise Blocked('Executed integration evidence required')
        except (Blocked,ValueError,KeyError,TypeError) as e: errors.append(f'{gate}: {e}')
    return errors

def main():
    p=argparse.ArgumentParser();p.add_argument('manifest',type=pathlib.Path);p.add_argument('--expected-commit',required=True);args=p.parse_args()
    try:
        manifest=args.manifest.resolve(strict=True)
        errors=validate(json.loads(manifest.read_text()),manifest.parent,args.expected_commit,dt.datetime.now(dt.timezone.utc))
    except (OSError,ValueError,TypeError) as e:errors=[str(e)]
    print(json.dumps({'status':'BLOCKED' if errors else 'EVIDENCE_SCHEMA_PASSED','errors':errors},indent=2))
    # This is schema/consistency validation, not a signature verification or certification.
    return 2 if errors else 0
if __name__=='__main__':raise SystemExit(main())

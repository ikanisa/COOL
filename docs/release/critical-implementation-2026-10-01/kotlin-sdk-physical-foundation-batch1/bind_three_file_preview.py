#!/usr/bin/env python3
"""Read-only exact three-file patch reconstruction against physical publisher bytes."""
import hashlib
import json
import re
from pathlib import Path

HERE=Path(__file__).resolve().parent
PLAN=HERE.parent/'kotlin-sdk-candidate-plan1'
SDK=Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/flutter-3.44.4-authenticated-foundation-batch1')
sha=lambda body:hashlib.sha256(body).hexdigest()

def reconstruct(original, hunks):
    old=original.decode().splitlines(keepends=True); output=[]; cursor=0
    for header, lines in hunks:
        match=re.fullmatch(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@[^\n]*\n',header)
        if not match: raise ValueError('unsupported hunk')
        start=int(match[1])-1; old_n=int(match[2] or 1); new_n=int(match[4] or 1)
        if start < cursor: raise ValueError('overlapping/reordered hunk')
        output.extend(old[cursor:start]); cursor=start; old_count=new_count=0
        for line in lines:
            tag=line[0]; payload=line[1:]
            if tag in ' -':
                if cursor>=len(old) or old[cursor]!=payload: raise ValueError('exact original patch context drift')
                cursor+=1; old_count+=1
            if tag in ' +': output.append(payload); new_count+=1
            if tag not in ' +-': raise ValueError('unreviewed patch syntax')
        if (old_count,new_count)!=(old_n,new_n): raise ValueError('hunk byte-line counts disagree')
    output.extend(old[cursor:]); return ''.join(output).encode()

if __name__=='__main__':
    manifest=json.loads((PLAN/'packet-files.json').read_text())
    for name,digest in manifest['files'].items():
        if sha((PLAN/name).read_bytes())!=digest: raise ValueError('sealed original plan leaf drift')
    proposal=json.loads((PLAN/'proposed-delta.json').read_text()); patch=(PLAN/'proposed-collect-only-sdk.patch').read_bytes()
    if sha(patch)!=proposal['patch_sha256']: raise ValueError('reviewed patch drift')
    lines=patch.decode().splitlines(keepends=True); parsed={}; current=None; hunk=None; index=0
    while index < len(lines):
        line=lines[index]
        if line.startswith('--- a/'):
            current=line[len('--- a/'):].rstrip('\n'); index+=1
            if lines[index]!='+++ b/'+current+'\n' or current in parsed: raise ValueError('patch path pair drift')
            parsed[current]=[]; hunk=None
        elif line.startswith('@@ '):
            hunk=[line,[]]; parsed[current].append(hunk)
        else:
            if hunk is None: raise ValueError('unexpected patch content')
            hunk[1].append(line)
        index+=1
    if set(parsed)!=set(proposal['proposed_files']) or len(parsed)!=3: raise ValueError('not exact reviewed3 paths')
    admission=json.loads((HERE.parent/'kotlin-sdk-expansion-admission-batch1/exact-archive-admission.json').read_text())
    rows={}
    for name,hunks in parsed.items():
        original=(SDK/name).read_bytes(); candidate=reconstruct(original,hunks); expected=proposal['proposed_files'][name]
        source=admission['members']['flutter/'+name]['source']
        if sha(original)!=expected['before_sha256'] or sha(candidate)!=expected['proposed_after_sha256']:
            raise ValueError('reviewed exact before/after byte identities drift')
        blob=hashlib.sha1(b'blob '+str(len(original)).encode()+b'\0'+original).hexdigest()
        if blob!=source['official_git_blob_sha1']: raise ValueError('publisher original source blob drift')
        rows[name]={'actual_physical_original_sha256':sha(original),'actual_physical_original_bytes':len(original),
            'official_original_git_blob_sha1':blob,'RAM_reconstructed_reviewed_after_sha256':sha(candidate),
            'RAM_reconstructed_reviewed_after_bytes':len(candidate),'SDK_source_written':False}
    result={'status':'PHYSICAL_ORIGINALS_AND_EXACT_REVIEWED_RAM_PREVIEW_MATCH__NOT_APPLIED_NOT_COMPILED',
        'publisher_commit':'ad70ec4617166f1c38e5d2bfd388af71fda14f06','reviewed_patch_sha256':sha(patch),
        'original_plan_manifest_sha256':sha((PLAN/'packet-files.json').read_bytes()),'files':rows,
        'physical_foundation_modified':False,'SDK_executed':False,'candidate_promoted':False,'production_release_approval':False}
    (HERE/'three-file-physical-preview-binding.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'status':result['status'],'files':len(rows)}))

#!/usr/bin/env python3
"""Prepared exact-source/delta/generated-output validator; no SDK tools are run."""
import argparse
import datetime
import hashlib
import importlib.util
import json
import os
import stat
import unicodedata
import zlib
from pathlib import Path

HERE=Path(__file__).resolve().parent
CANDIDATE=Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/flutter-3.44.4-collect-kotlin-2.4.20-candidate1')
PRISTINE=Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/flutter-3.44.4-authenticated-foundation-batch1')
INSTALLED=Path('/Volumes/PRO-G40/Development/Flutter/flutter')
WRITER_SHA='c8feb963d8e7cd361c4f4d2790c03ffa01ee3f14c6e64f8f26fd1389a0e3b432'
ADMISSION_SHA='9d22ab7c56ffdeb8d0b3b9c64022bd481403f86ff449ff4c257e8124ffcc3749'
PREVIEW_SHA='e61d580116a7fb976733cbf7dc3ae6c6d3b927c5c0bb46f04511ba39e2e01f34'
GENERATED_ROOTS=('flutter/packages/flutter_tools/gradle/.gradle','flutter/packages/flutter_tools/gradle/.kotlin','flutter/packages/flutter_tools/gradle/build')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def anchors():
    writer=HERE/'authenticated_candidate_expansion.py'
    if sha(writer)!=WRITER_SHA: raise ValueError('exact reviewed derivative writer drift')
    spec=importlib.util.spec_from_file_location('exact_candidate_writer',writer)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    admission=module.exact_json(HERE.parent/'kotlin-sdk-expansion-admission-batch1/exact-archive-admission.json',ADMISSION_SHA)
    preview=module.exact_json(HERE.parent/'kotlin-sdk-physical-foundation-batch1/three-file-physical-preview-binding.json',PREVIEW_SHA)
    module.validate_exact_admission(admission)
    if len(preview['files'])!=3 or preview['reviewed_patch_sha256']!='3b1e88e8291541a4a955eebe17fb576c05e2f1ef73fcc55b68d041c04256fe68':
        raise ValueError('exact reviewed3 patch identity drift')
    return module,admission,preview


def expected_bytes(name,row,preview,phase):
    path=name.removeprefix('flutter/')
    if phase!='pristine' and path in preview['files']:
        delta=preview['files'][path]
        return delta['RAM_reconstructed_reviewed_after_bytes'],delta['RAM_reconstructed_reviewed_after_sha256']
    return row['bytes'],row['sha256']


def check_regular_bytes(name,body,row,preview,phase):
    length,digest=expected_bytes(name,row,preview,phase)
    if len(body)!=length or hashlib.sha256(body).hexdigest()!=digest:
        raise ValueError('exact candidate source/allowed-byte delta drift: '+name)


def generated_path_allowed(name,phase):
    return phase=='built' and any(name==r or name.startswith(r+'/') for r in GENERATED_ROOTS)


def verify(phase):
    if phase not in ('pristine','patched','built'):raise ValueError('unreviewed candidate source phase')
    module,admission,preview=anchors()
    helper,nodes,checkout,_,_,links=module.bindings()
    if (not CANDIDATE.is_dir() or CANDIDATE.is_symlink() or CANDIDATE.resolve()!=CANDIDATE
            or CANDIDATE==PRISTINE or CANDIDATE==INSTALLED):
        raise ValueError('candidate is not the exact new independent physical root')
    with module.deadline(300):
        actual={'flutter':CANDIDATE};pending=[CANDIDATE];aliases={}
        while pending:
            directory=pending.pop()
            with os.scandir(directory) as entries:
                for entry in entries:
                    path=Path(entry.path);name='flutter/'+str(path.relative_to(CANDIDATE))
                    helper.canonical(name)
                    alias=unicodedata.normalize('NFC',name).casefold()
                    if alias in aliases: raise ValueError('candidate case/NFC alias')
                    aliases[alias]=name;actual[name]=path
                    if len(actual)>200000:raise ValueError('candidate entry bound')
                    if stat.S_ISDIR(entry.stat(follow_symlinks=False).st_mode):pending.append(path)
        missing=set(admission['members'])-set(actual)
        extra=set(actual)-set(admission['members'])
        if missing or any(not generated_path_allowed(n,phase) for n in extra):
            raise ValueError('candidate omitted publisher member or added unreviewed source/path')
        rows={};source_seen=set();generated={};total=0
        for name,path in actual.items():
            observation=path.lstat();row=admission['members'].get(name)
            kind='directory' if stat.S_ISDIR(observation.st_mode) else 'symlink' if stat.S_ISLNK(observation.st_mode) else 'regular' if stat.S_ISREG(observation.st_mode) else 'special'
            if kind=='special':raise ValueError('candidate special file')
            if observation.st_mode & (stat.S_ISUID|stat.S_ISGID):raise ValueError('candidate special permission bits')
            if row and kind!=row['kind']:raise ValueError('candidate retained member type drift')
            if not row and (kind=='symlink' or path.name.lower()=='skill.md'):
                raise ValueError('unreviewed generated symlink/skill')
            if kind=='regular':
                if observation.st_nlink!=1:raise ValueError('candidate shares writable regular inode')
                total+=observation.st_size
                if observation.st_size>1024**3 or total>12*1024**3:raise ValueError('candidate expanded byte bound')
                for other_root in (PRISTINE,INSTALLED):
                    other=other_root/path.relative_to(CANDIDATE)
                    if other.exists() and other.is_file():
                        previous=other.stat()
                        if (observation.st_dev,observation.st_ino)==(previous.st_dev,previous.st_ino):
                            raise ValueError('candidate/pristine/installed shared inode')
                digest=hashlib.sha256();crc=0;count=0
                fd=os.open(path,os.O_RDONLY|getattr(os,'O_NOFOLLOW',0))
                with os.fdopen(fd,'rb') as stream:
                    opened=os.fstat(stream.fileno())
                    if (opened.st_dev,opened.st_ino)!=(observation.st_dev,observation.st_ino):raise ValueError('physical reader identity race')
                    for chunk in iter(lambda:stream.read(1024**2),b''):
                        count+=len(chunk);digest.update(chunk);crc=zlib.crc32(chunk,crc)
                        if count>observation.st_size:raise ValueError('candidate read byte overrun')
                if count!=observation.st_size:raise ValueError('candidate read length drift')
                actual_sha=digest.hexdigest()
                if row:
                    expected_size,expected_sha=expected_bytes(name,row,preview,phase)
                    if (count,actual_sha)!=(expected_size,expected_sha):raise ValueError('exact retained byte/delta drift: '+name)
                    if name.removeprefix('flutter/') not in preview['files'] or phase=='pristine':
                        if crc!=row['CRC']:raise ValueError('retained CRC drift')
                    if name in nodes:
                        if name.removeprefix('flutter/') not in preview['files'] or phase=='pristine':
                            module.source_identity(name,path.read_bytes(),observation.st_mode,nodes,checkout,helper)
                        source_seen.add(name)
                entry={'kind':kind,'bytes':count,'sha256':actual_sha,'CRC':crc,'mode':stat.S_IMODE(observation.st_mode),'device':observation.st_dev,'inode':observation.st_ino,'nlink':observation.st_nlink}
            elif kind=='symlink':
                if os.readlink(path)!=links[name]:raise ValueError('retained exact link drift')
                if not path.resolve(strict=True).is_relative_to(CANDIDATE):raise ValueError('candidate outward link')
                if name in nodes:source_seen.add(name)
                entry={'kind':kind,'target':os.readlink(path),'device':observation.st_dev,'inode':observation.st_ino}
            else:entry={'kind':kind,'mode':stat.S_IMODE(observation.st_mode),'device':observation.st_dev,'inode':observation.st_ino}
            if row and kind!='symlink' and stat.S_IMODE(observation.st_mode)!=row['safe_materialized_mode']:
                raise ValueError('retained member safe mode drift')
            if row:rows[name]=entry
            else:generated[name]=entry
        if source_seen!=set(nodes):raise ValueError('missing exact official source/license identity')
        return {'status':'EXACT_CANDIDATE_SOURCE_DELTA_AND_PHYSICAL_READBACK_PASS','phase':phase,'source_entries':len(source_seen),
            'allowed_source_deltas':[] if phase=='pristine' else sorted(preview['files']),
            'retained_publisher_members':len(rows),'generated_output_manifest':generated,'generated_roots_exact':GENERATED_ROOTS,
            'retained_physical_manifest':rows,'zero_pristine_installed_shared_inodes':True,'SDK_executed_by_verifier':False,
            'scope':'Exact physical/source/allowed3 delta and separately inventoried generated paths. No compiler/ABI/advisory/release acceptance.'}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase',choices=('pristine','patched','built'))
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():raise ValueError('output exists; preserve prior attempts')
    result=verify(args.phase)
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:result[k] for k in ['status','phase','source_entries','retained_publisher_members','allowed_source_deltas']}))

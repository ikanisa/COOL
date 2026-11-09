#!/usr/bin/env python3
"""Verify pinned, scoped Ed25519 producer statements using OpenSSL 3+.

No trust-on-first-use, embedded trust roots, signing keys, network or deployment.
The protected caller supplies the trust file and its independently approved hash.
This authenticates configured keys, not the truth of a producer's assertions.
"""
from __future__ import annotations
import datetime as dt
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import release_guard as g

DOMAIN = b'BuriMunsi-release-provenance-v1\x00'
SPKI_ED25519 = bytes.fromhex('302a300506032b6570032100')
MAX_TRUST_AGE = 30 * 86400
MAX_SIGNATURES = 256


def roles_for(m):
    return {'manifest'} | {'qualification:'+q['id'] for q in m['qualifications']}


def hex_bytes(value, length, code):
    g.need(type(value) is str and re.fullmatch('[0-9a-f]{'+str(length*2)+'}',value) is not None,code)
    return bytes.fromhex(value)


def statement(m, role, trust_hash, key_id, signed_at):
    """Exact bytes for an external signer; do not sign unreviewed manifests."""
    g.need(role in roles_for(m),'SIGNATURE_ROLE_UNKNOWN')
    g.digest(trust_hash);g.digest(key_id);g.instant(signed_at)
    subject=g.sha(g.canonical(m)) if role=='manifest' else next(q['result']['sha256'] for q in m['qualifications'] if role=='qualification:'+q['id'])
    return DOMAIN+g.canonical({'schema_version':1,'algorithm':'Ed25519','role':role,'key_id':key_id,
        'signed_at':signed_at,'trust_policy_sha256':trust_hash,'manifest_sha256':g.sha(g.canonical(m)),
        'subject_sha256':subject,'product':m['product'],'source_version':m['source_version'],
        'phase':m['phase'],'run_id':m['run_id'],'policy_sha256':m['policy_sha256']})


def parse_policy(raw, expected_hash, m, now):
    g.need(g.sha(raw)==g.digest(expected_hash),'TRUST_POLICY_HASH_MISMATCH')
    p=g.strict_json(raw)
    g.keys(p,{'schema_version','kind','product','phase','issued_at','expires_at','keys','roles'},'INVALID_TRUST_POLICY')
    g.need(type(p['schema_version']) is int and p['schema_version']==1 and p['kind']=='release-trust-policy','UNSUPPORTED_TRUST_POLICY')
    g.need(p['product']==m['product'] and p['phase']==m['phase'],'TRUST_POLICY_SCOPE_MISMATCH')
    issued=g.instant(p['issued_at']);expires=g.instant(p['expires_at'])
    g.need(issued<=now<expires and 0<(expires-issued).total_seconds()<=MAX_TRUST_AGE,'TRUST_POLICY_EXPIRED_OR_FUTURE')
    g.need(type(p['keys']) is list and 0<len(p['keys'])<=MAX_SIGNATURES,'TRUST_KEYS_MISSING')
    keys={};publics=set()
    for k in p['keys']:
        g.keys(k,{'id','producer_id','public_key_hex','status','not_before','not_after'},'INVALID_TRUST_KEY')
        pub=hex_bytes(k['public_key_hex'],32,'INVALID_PUBLIC_KEY')
        g.need(g.digest(k['id'])==g.sha(pub),'PUBLIC_KEY_ID_MISMATCH')
        g.need(k['id'] not in keys and pub not in publics,'DUPLICATE_TRUST_KEY');publics.add(pub)
        g.text(k['producer_id'],'INVALID_PRODUCER_ID')
        g.need(k['status'] in {'active','revoked'},'INVALID_KEY_STATUS')
        g.need(g.instant(k['not_before'])<g.instant(k['not_after']),'INVALID_KEY_WINDOW')
        keys[k['id']]=k
    expected={'manifest'} | {'qualification:'+qid for qid in g.policy(m['product'],m['phase'])['requirements']}
    g.need(roles_for(m)==expected,'PROVENANCE_ROLES_INCOMPLETE')
    g.need(type(p['roles']) is dict and set(p['roles'])==expected,'TRUST_ROLES_INCOMPLETE')
    for role,r in p['roles'].items():
        g.keys(r,{'key_ids','threshold'},'INVALID_TRUST_ROLE')
        g.need(type(r['key_ids']) is list and 0<len(r['key_ids'])<=MAX_SIGNATURES,'INVALID_ROLE_KEYS')
        g.need(all(type(k) is str and k in keys for k in r['key_ids']),'ROLE_KEY_UNKNOWN')
        g.need(len(set(r['key_ids']))==len(r['key_ids']),'DUPLICATE_ROLE_KEY')
        g.need(type(r['threshold']) is int and 1<=r['threshold']<=len({keys[k]['producer_id'] for k in r['key_ids']}),'INVALID_SIGNATURE_THRESHOLD')
    # Owner and security credentials must be separate from other producer roles.
    # Producer identity as well as key identity is checked to prevent key aliases.
    for protected in ('qualification:operations_authorization','qualification:security_acceptance','qualification:security_dependencies'):
        if protected not in p['roles']:continue
        exclusive={keys[k]['producer_id'] for k in p['roles'][protected]['key_ids']}
        for other,r in p['roles'].items():
            if other!=protected:
                g.need(not exclusive.intersection(keys[k]['producer_id'] for k in r['key_ids']),'PRODUCER_SEPARATION_REQUIRED')
    return p,keys


def openssl_path():
    # Never resolve executable names from evidence or a candidate-controlled PATH.
    candidate=shutil.which('openssl',path='/usr/bin:/bin:/usr/local/bin')
    g.need(candidate is not None,'CRYPTO_PREREQUISITE_MISSING')
    path=Path(candidate).resolve()
    g.need(path.is_file() and os.access(path,os.X_OK),'CRYPTO_PREREQUISITE_MISSING')
    return str(path)


def crypto_run(args, cwd):
    try:
        return subprocess.run(args,cwd=cwd,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,timeout=10,check=False,shell=False,
            env={'PATH':'/usr/bin:/bin:/usr/local/bin','LC_ALL':'C','OPENSSL_CONF':os.devnull})
    except (OSError,subprocess.TimeoutExpired) as exc:
        raise g.Rejected('CRYPTO_EXECUTION_BLOCKED') from exc


def verify_ed25519(public, signature, message, executable):
    g.need(len(public)==32 and len(signature)==64,'INVALID_SIGNATURE_ENCODING')
    with tempfile.TemporaryDirectory(prefix='release-signature-') as td:
        d=Path(td)
        (d/'public.der').write_bytes(SPKI_ED25519+public)
        (d/'signature.bin').write_bytes(signature);(d/'statement.bin').write_bytes(message)
        result=crypto_run([executable,'pkeyutl','-verify','-rawin','-pubin','-keyform','DER',
            '-inkey',str(d/'public.der'),'-in',str(d/'statement.bin'),'-sigfile',str(d/'signature.bin')],d)
        g.need(result.returncode==0,'SIGNATURE_INVALID_OR_CRYPTO_UNSUPPORTED')


def verify(source_root,evidence_root,m,trust_path,trust_hash,bundle_path,now=None):
    now=now or dt.datetime.now(g.UTC)
    # Explicit absolute path outside candidate/evidence. No candidate may select
    # its own trust roots, including through a symlink or an in-tree policy file.
    g.need(trust_path.is_absolute(),'TRUST_POLICY_MUST_BE_EXTERNAL')
    g.no_links(trust_path)
    for root in (source_root,evidence_root):
        g.need(not trust_path.resolve().is_relative_to(root.resolve()),'TRUST_POLICY_MUST_BE_EXTERNAL')
    trust_raw=g.read_file(trust_path.parent,trust_path.name,g.MAX_JSON)
    p,keys=parse_policy(trust_raw,trust_hash,m,now)
    bundle_raw=g.read_file(bundle_path.parent,bundle_path.name,g.MAX_JSON);g.scan(bundle_path.name,bundle_raw)
    b=g.strict_json(bundle_raw)
    g.keys(b,{'schema_version','kind','trust_policy_sha256','manifest_sha256','product','phase','source_version','run_id','signatures'},'INVALID_PROVENANCE_BUNDLE')
    g.need(type(b['schema_version']) is int and b['schema_version']==1 and b['kind']=='release-provenance','UNSUPPORTED_PROVENANCE')
    g.need(b['trust_policy_sha256']==trust_hash,'PROVENANCE_TRUST_MISMATCH')
    g.need(b['manifest_sha256']==g.sha(g.canonical(m)),'PROVENANCE_MANIFEST_MISMATCH')
    g.need(all(b[k]==m[k] for k in ('product','phase','source_version','run_id')),'PROVENANCE_SCOPE_MISMATCH')
    g.need(type(b['signatures']) is list and 0<len(b['signatures'])<=MAX_SIGNATURES,'PROVENANCE_SIGNATURES_MISSING')
    executable=openssl_path();deadline=time.monotonic()+30;seen=set();approved={r:set() for r in p['roles']};keyids={r:set() for r in p['roles']}
    for s in b['signatures']:
        g.need(time.monotonic()<deadline,'CRYPTO_TIME_BUDGET_EXCEEDED')
        g.keys(s,{'role','key_id','signed_at','signature_hex'},'INVALID_SIGNATURE_FIELDS')
        role=s['role'];kid=s['key_id']
        g.need(type(role) is str and role in p['roles'],'SIGNATURE_ROLE_UNKNOWN')
        g.need(type(kid) is str and kid in keys,'SIGNER_UNKNOWN')
        g.need((role,kid) not in seen,'DUPLICATE_SIGNATURE');seen.add((role,kid))
        g.need(kid in p['roles'][role]['key_ids'],'SIGNER_NOT_AUTHORIZED_FOR_ROLE')
        key=keys[kid];g.need(key['status']=='active','SIGNER_REVOKED')
        signed=g.fresh(s['signed_at'],now)
        g.need(g.instant(m['created_at'])<=signed and g.instant(p['issued_at'])<=signed,'SIGNATURE_PRECEDES_SUBJECT')
        g.need(g.instant(key['not_before'])<=signed<=now<g.instant(key['not_after']),'SIGNER_EXPIRED_OR_NOT_YET_VALID')
        signature=hex_bytes(s['signature_hex'],64,'INVALID_SIGNATURE_ENCODING')
        verify_ed25519(bytes.fromhex(key['public_key_hex']),signature,statement(m,role,trust_hash,kid,s['signed_at']),executable)
        g.need(time.monotonic()<deadline,'CRYPTO_TIME_BUDGET_EXCEEDED')
        approved[role].add(key['producer_id']);keyids[role].add(kid)
    for role,rule in p['roles'].items():
        g.need(len(approved[role])>=rule['threshold'],'SIGNATURE_THRESHOLD_NOT_MET')
    # Detect trust-policy or bundle mutation during subprocess verification.
    g.need(g.read_file(trust_path.parent,trust_path.name,g.MAX_JSON)==trust_raw,'TRUST_POLICY_CHANGED_DURING_VERIFICATION')
    g.need(g.read_file(bundle_path.parent,bundle_path.name,g.MAX_JSON)==bundle_raw,'PROVENANCE_CHANGED_DURING_VERIFICATION')
    return {'schema_version':1,'status':'passed','algorithm':'Ed25519','trust_policy_sha256':trust_hash,
        'manifest_sha256':b['manifest_sha256'],'provenance_sha256':g.sha(bundle_raw),'signature_count':len(seen),
        'role_count':len(approved),'roles':{r:sorted(ids) for r,ids in keyids.items()},'production_authorized':False,
        'limitation':'Configured producer signatures only; evidence truth, independent identity assurance and online revocation are external.'}

#!/usr/bin/env python3
"""Export reviewable signing payloads and assemble externally signed statements.

This tool neither creates keys nor signs evidence. It never opens a release gate.
Use a protected signer after independent review of the candidate and test records.
"""
from pathlib import Path
import argparse
import json
import sys
import release_guard as g
import release_provenance as p


def context(source,evidence,manifest,trust,trust_hash,now):
    m=g.load(manifest)
    g.need(manifest.parent.resolve()==evidence.resolve(),'MANIFEST_OUTSIDE_EVIDENCE')
    g.need(m['phase'] in {'build','promotion'},'PROVENANCE_APPLICATION_PHASE_REQUIRED')
    result=g.validate_consistency(source,evidence,m,product=m['product'],version=m['source_version'],phase=m['phase'],now=now)
    g.need(result['gate_open'],'CONSISTENCY_GATE_CLOSED')
    g.need(trust.is_absolute(),'TRUST_POLICY_MUST_BE_EXTERNAL');g.no_links(trust)
    g.need(not any(trust.resolve().is_relative_to(x.resolve()) for x in (source,evidence)),'TRUST_POLICY_MUST_BE_EXTERNAL')
    policy,keys=p.parse_policy(g.read_file(trust.parent,trust.name,g.MAX_JSON),trust_hash,m,now)
    return m,policy,keys


def outside(output,inputs):
    g.no_links(output);g.need(not output.exists(),'OUTPUT_EXISTS')
    for path in inputs:
        g.need(not output.absolute().is_relative_to(path.resolve()) and not path.resolve().is_relative_to(output.absolute()),'OUTPUT_ALIASES_INPUT')


def prepare(source,evidence,manifest,trust,trust_hash,role,key_id,output,now=None):
    now=now or g.dt.datetime.now(g.UTC)
    m,policy,keys=context(source,evidence,manifest,trust,trust_hash,now)
    g.need(role in policy['roles'],'SIGNATURE_ROLE_UNKNOWN')
    g.need(key_id in policy['roles'][role]['key_ids'],'SIGNER_NOT_AUTHORIZED_FOR_ROLE')
    key=keys[key_id];g.need(key['status']=='active','SIGNER_REVOKED')
    g.need(g.instant(key['not_before'])<=now<g.instant(key['not_after']),'SIGNER_EXPIRED_OR_NOT_YET_VALID')
    when=now.isoformat(timespec='microseconds').replace('+00:00','Z')
    raw=p.statement(m,role,trust_hash,key_id,when)
    outside(output,[source,evidence,trust]);output.mkdir(parents=True)
    g.write_new(output/'statement.bin',raw)
    request={'schema_version':1,'kind':'unsigned-signing-request','role':role,'key_id':key_id,'signed_at':when,
        'manifest_sha256':g.sha(g.canonical(m)),'trust_policy_sha256':trust_hash,'statement_sha256':g.sha(raw),
        'production_authorized':False}
    g.write_new(output/'request.json',g.pretty(request))
    return {'status':'prepared_unsigned','request':request,'gate_open':False,'production_authorized':False}


def assemble(source,evidence,manifest,trust,trust_hash,pairs,output,now=None):
    """pairs are (prepared directory, raw Ed25519 signature file)."""
    now=now or g.dt.datetime.now(g.UTC)
    g.need(0<len(pairs)<=p.MAX_SIGNATURES,'PROVENANCE_SIGNATURES_MISSING')
    m,policy,keys=context(source,evidence,manifest,trust,trust_hash,now)
    outside(output,[source,trust])
    # A new evidence/provenance.json is allowed; never replace an input file.
    inputs=[manifest,trust]+[file for directory,sig in pairs for file in (directory/'request.json',directory/'statement.bin',sig)]
    g.need(all(output.absolute()!=file.resolve() for file in inputs),'OUTPUT_ALIASES_INPUT')
    signatures=[]
    for directory,sigfile in pairs:
        r=g.load(directory/'request.json')
        g.keys(r,{'schema_version','kind','role','key_id','signed_at','manifest_sha256','trust_policy_sha256','statement_sha256','production_authorized'},'INVALID_SIGNING_REQUEST')
        g.need(type(r['schema_version']) is int and r['schema_version']==1 and r['kind']=='unsigned-signing-request' and r['production_authorized'] is False,'INVALID_SIGNING_REQUEST')
        g.need(r['manifest_sha256']==g.sha(g.canonical(m)) and r['trust_policy_sha256']==trust_hash,'SIGNING_REQUEST_BINDING_MISMATCH')
        payload=g.read_file(directory,'statement.bin',g.MAX_JSON)
        expected=p.statement(m,r['role'],trust_hash,r['key_id'],r['signed_at'])
        g.need(payload==expected and g.sha(payload)==r['statement_sha256'],'SIGNING_PAYLOAD_MISMATCH')
        signature=g.read_file(sigfile.parent,sigfile.name,64);g.need(len(signature)==64,'INVALID_SIGNATURE_ENCODING')
        signatures.append({k:r[k] for k in ('role','key_id','signed_at')}|{'signature_hex':signature.hex()})
    bundle={'schema_version':1,'kind':'release-provenance','trust_policy_sha256':trust_hash,'manifest_sha256':g.sha(g.canonical(m)),
        **{k:m[k] for k in ('product','phase','source_version','run_id')},'signatures':signatures}
    # Validate before publishing; a temporary external file is not a qualification.
    import tempfile
    with tempfile.TemporaryDirectory(prefix='provenance-assemble-') as td:
        b=Path(td)/'provenance.json';b.write_bytes(g.pretty(bundle))
        p.verify(source,evidence,m,trust,trust_hash,b,now)
        result=g.validate_consistency(source,evidence,m,product=m['product'],version=m['source_version'],phase=m['phase'],now=now)
        g.need(result['gate_open'],'EVIDENCE_CHANGED_DURING_AUTHENTICATION')
    g.write_new(output,g.pretty(bundle))
    return {'status':'assembled_verified_signatures','sha256':g.sha(g.pretty(bundle)),
        'signature_count':len(signatures),'gate_open':False,'production_authorized':False,
        'next_step':'Run release_guard validate with the same protected trust pin and exact unchanged evidence.'}


def main():
    ap=argparse.ArgumentParser(description=__doc__);sub=ap.add_subparsers(dest='action',required=True)
    for action in ('prepare','assemble'):
        a=sub.add_parser(action)
        for name in ('source','evidence-root','manifest','trust-policy','output'):a.add_argument('--'+name,type=Path,required=True)
        a.add_argument('--trust-sha256',required=True)
        if action=='prepare':a.add_argument('--role',required=True);a.add_argument('--key-id',required=True)
        else:a.add_argument('--signed',type=Path,nargs=2,action='append',required=True,metavar=('REQUEST_DIRECTORY','SIGNATURE_FILE'))
    a=ap.parse_args()
    try:
        args=(a.source,a.evidence_root,a.manifest,a.trust_policy,a.trust_sha256)
        r=prepare(*args,a.role,a.key_id,a.output) if a.action=='prepare' else assemble(*args,a.signed,a.output)
        print(json.dumps(r,sort_keys=True));return 0
    except (g.Rejected,OSError,TypeError,ValueError,KeyError,RecursionError) as exc:
        print(json.dumps({'status':'blocked','gate_open':False,'production_authorized':False,
            'errors':[str(exc) if isinstance(exc,g.Rejected) else 'PROVENANCE_EXCHANGE_FAILED']}));return 2

if __name__=='__main__':raise SystemExit(main())

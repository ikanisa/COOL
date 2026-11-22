#!/usr/bin/env python3
"""Product binding used by the patched release entrypoints; never deploys or signs."""
from pathlib import Path
import argparse
import os
import json
import re
import release_guard as g

def identity(root: Path, product: str) -> str:
    if product=='BuriMunsi':
        data=g.load(root/'release/canonical-integration-status.json')
        return g.text(data.get('version'),'SOURCE_VERSION_MISSING')
    g.need(product=='M-Money','UNKNOWN_PRODUCT')
    raw=g.read_file(root,'app/build.gradle.kts').decode('utf-8')
    versions=re.findall(r'\bversionName\s*=\s*"([^"]+)"',raw)
    g.need(len(versions)==1,'SOURCE_VERSION_AMBIGUOUS')
    return versions[0]

def enforce(root: Path,product: str,phase: str,manifest: Path|None=None,
            legacy: Path|None=None,status: Path|None=None,artifact: Path|None=None) -> list[str]:
    try:
        version=identity(root,product)
        path=manifest or root/'.release-evidence'/phase/'release-manifest.json'
        m=g.load(path)
        result=g.validate(root,path.parent,m,product=product,version=version,phase=phase,
            trust_policy=os.environ.get('RELEASE_TRUST_POLICY'),trust_sha256=os.environ.get('RELEASE_TRUST_SHA256'),
            attestations=path.parent/'provenance.json')
        if not result['gate_open']: return result['errors']
        # Bind legacy task/owner evidence without creating a circular manifest hash.
        for aid,file in [('legacy-release-evidence',legacy),('legacy-task-status',status)]:
            if file is None: continue
            records=[a for a in m['artifacts'] if a['id']==aid]
            g.need(len(records)==1,'LEGACY_EVIDENCE_BINDING_MISSING')
            supplied=g.read_file(file.parent,file.name,g.MAX_JSON)
            if product=='M-Money' and aid=='legacy-release-evidence':
                g.need(g.strict_json(supplied).get('source_tree_sha256')==result['details']['source_tree_sha256'],
                       'LEGACY_SOURCE_BINDING_MISMATCH')
            g.need(g.sha(supplied)==records[0]['file']['sha256'],'LEGACY_EVIDENCE_BINDING_MISMATCH')
            g.need(g.read_ref(path.parent,records[0]['file'])==supplied,'LEGACY_EVIDENCE_BINDING_MISMATCH')
        if artifact is not None:
            raw=g.read_file(artifact.parent,artifact.name)
            g.need(any(a['kind'] in {'apk','aab'} and a['file']['sha256']==g.sha(raw) for a in m['artifacts']),
                   'LEGACY_ARTIFACT_BINDING_MISMATCH')
        return []
    except (g.Rejected,OSError,ValueError,TypeError,KeyError,RecursionError) as exc:
        return [str(exc) if isinstance(exc,g.Rejected) else 'GUARD_INPUT_UNAVAILABLE']

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--phase',choices=['source','build'],required=True)
    p.add_argument('--manifest',type=Path)
    a=p.parse_args();root=Path(__file__).resolve().parents[1]
    product='BuriMunsi' if (root/'release/canonical-integration-status.json').exists() else 'M-Money'
    errors=enforce(root,product,a.phase,a.manifest)
    print(json.dumps({'status':'blocked' if errors else 'passed','gate_open':not errors,'phase':a.phase,
                      'errors':errors,'production_authorized':False}))
    return 2 if errors else 0

if __name__=='__main__':raise SystemExit(main())

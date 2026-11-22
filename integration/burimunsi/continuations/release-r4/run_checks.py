#!/usr/bin/env python3
"""One command: snapshot, test, bind fresh evidence, fail closed, optionally package.

No external product qualifications are generated. Output must be new and outside
this source tree. Missing/failed test execution cannot create a passed result.
"""
from pathlib import Path
import argparse
import json
import os
import platform
import subprocess
import sys
import uuid
sys.path.insert(0,str(Path(__file__).resolve().parent/'src'))
import release_guard as g
ROOT=Path(__file__).resolve().parent

def run(output,archive=None):
    g.no_links(output);g.need(not output.exists(),'OUTPUT_EXISTS')
    g.need(not output.absolute().is_relative_to(ROOT),'OUTPUT_ALIASES_INPUT')
    output.mkdir(parents=True)
    source=g.capture(ROOT,'release-safeguards',g.VERSION);sraw=g.pretty(source)
    dep=g.dependencies(source);draw=g.pretty(dep)
    # This tool has no third-party Python packages. Product dependency resolution
    # still remains unresolved; source-only packaging does not assert resolution.
    g.write_new(output/'source-manifest.json',sraw);g.write_new(output/'dependencies.json',draw)
    started=g.utcnow();command=[sys.executable,'-B','tests/run_unittest.py','--result',str(output/'unittest-counts.json')]
    try:
        process=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=120,
                               env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1'})
        raw=process.stdout+process.stderr;exit_code=process.returncode
        counts=g.load(output/'unittest-counts.json')
        actual_counts={k:counts[k] for k in ('executed','failed','skipped','blocked')}
    except (OSError,subprocess.TimeoutExpired,g.Rejected):
        raw=b'LOCAL_TEST_EXECUTION_BLOCKED\n';exit_code=2
        actual_counts={'executed':0,'failed':0,'skipped':0,'blocked':1}
    ended=g.utcnow();g.scan('guard-regression.log',raw);g.write_new(output/'guard-regression.log',raw)
    unchanged=g.source_entries(ROOT)==source['files']
    passed=exit_code==0 and unchanged and actual_counts['executed']>0 and all(actual_counts[k]==0 for k in ('failed','skipped','blocked'))
    run_id='guard-'+uuid.uuid4().hex
    result={'schema_version':1,'kind':'qualification-result','id':'guard_regression','scope':'local_release_validator_regression',
            'product':'release-safeguards','source_version':g.VERSION,'run_id':run_id,'policy_sha256':g.policy_sha('release-safeguards','source'),
            'source_tree_sha256':source['tree_sha256'],'source_manifest_sha256':g.sha(sraw),'dependency_inventory_sha256':g.sha(draw),
            'artifact_sha256s':{},'started_at':started,'completed_at':ended,'status':'passed' if passed else 'blocked',
            'executed':actual_counts['executed']>0,'exit_code':exit_code,'counts':actual_counts,'command':command,
            'log':g.ref('guard-regression.log',raw)}
    rraw=g.pretty(result);g.write_new(output/'guard-regression.json',rraw)
    manifest={'schema_version':1,'kind':'release-evidence','product':'release-safeguards','source_version':g.VERSION,'phase':'source',
              'designation':'source-only','policy_sha256':result['policy_sha256'],'run_id':run_id,'created_at':g.utcnow(),
              'source_manifest':g.ref('source-manifest.json',sraw),'dependency_inventory':g.ref('dependencies.json',draw),
              'artifacts':[],'qualifications':[{'id':'guard_regression','result':g.ref('guard-regression.json',rraw)}]}
    g.write_new(output/'release-manifest.json',g.pretty(manifest))
    gate=g.validate(ROOT,output,manifest,product='release-safeguards',version=g.VERSION,phase='source')
    summary={'schema_version':1,'validator_version':g.VERSION,'source_tree_sha256':source['tree_sha256'],
             'started_at':started,'completed_at':ended,'source_unchanged':unchanged,'tests':actual_counts,'gate':gate,
             'runtime':{'python':platform.python_version(),'implementation':platform.python_implementation(),'platform':sys.platform},
             'external_acceptance':{k:'blocked_not_executed' for k in ['android_build_and_install','physical_carrier','real_postgresql',
                   'hosted_backend','canonical_ledger','signing_and_distribution','independent_security_assessment','owner_authorization']},
             'production_authorized':False}
    g.write_new(output/'summary.json',g.pretty(summary))
    if archive is not None and gate['gate_open']:
        packaged=g.package(ROOT,output,manifest,'release-safeguards',g.VERSION,archive)
        g.write_new(output/'package-result.json',g.pretty(packaged))
        g.write_new(archive.with_suffix(archive.suffix+'.sha256'),(packaged['sha256']+'  '+archive.name+'\n').encode())
    print(json.dumps({'status':gate['status'],'tests':actual_counts,'source_tree_sha256':source['tree_sha256'],
                      'production_authorized':False,'archive':str(archive) if archive and gate['gate_open'] else None},sort_keys=True))
    return 0 if gate['gate_open'] else 2

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);p.add_argument('--archive',type=Path);a=p.parse_args()
    try:return run(a.output.absolute(),a.archive.absolute() if a.archive else None)
    except (g.Rejected,OSError,ValueError,TypeError,KeyError) as exc:
        print(json.dumps({'status':'blocked','errors':[str(exc) if isinstance(exc,g.Rejected) else 'RUNNER_FAILED'],'production_authorized':False}));return 2
if __name__=='__main__':raise SystemExit(main())

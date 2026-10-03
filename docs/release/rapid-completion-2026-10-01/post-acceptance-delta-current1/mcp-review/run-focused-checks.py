import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

P = Path(__file__).resolve().parent
E = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1')
M = E / 'tools/collect-notification-mcp'
NODE = Path('/Volumes/PRO-G40/Development/Node/bin/node')
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
binding = json.loads((P / 'source-binding.json').read_text())
assert subprocess.check_output([NODE, '--version'], text=True).strip() == 'v24.19.0'
env = {k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','TMPDIR','PATH','LANG','LC_ALL','LC_CTYPE'}}
env.update(PYTHONDONTWRITEBYTECODE='1', PYTHONUTF8='1')
deps = {name: {'version': json.loads((M / 'node_modules' / name / 'package.json').read_text())['version'],
    'metadata_sha256': sha(M / 'node_modules' / name / 'package.json')}
    for name in ['typescript','@types/node','zod','@modelcontextprotocol/server']}
assert {k:v['version'] for k,v in deps.items()} == {'typescript':'7.0.2','@types/node':'26.4.1','zod':'4.5.4','@modelcontextprotocol/server':'2.0.0'}
protected = {n:sha(E/n) for n in binding['source_sha256']}
for n in ['tools/collect-notification-mcp/scripts/prepare_unattended_launchd.py','scripts/tests/unattended_launchd_preparation_test.py',
          'tools/collect-notification-mcp/package.json','tools/collect-notification-mcp/pnpm-lock.yaml','tools/collect-notification-mcp/tsconfig.json']:
    protected[n] = sha(E/n)
(P/'runtime-binding.json').write_text(json.dumps({'node':str(NODE),'version':'v24.19.0','node_sha256':sha(NODE),
    'dependency_versions':deps,'source_before':protected,'actual_host_calls':False},indent=2,sort_keys=True)+'\n')
jobs = [
    ('typecheck',[str(NODE),'node_modules/typescript/bin/tsc','--noEmit'],M,0),
    ('affected-module',[str(NODE),'--experimental-strip-types','--test','src/unattended_scheduler_control.test.ts'],M,0),
    ('python-preparation',['/usr/bin/python3',str(E/'scripts/tests/unattended_launchd_preparation_test.py')],E,0),
    ('disable-during-admission',[str(NODE),'--experimental-strip-types','--test',str(P/'disable-during-admission-reproducer.test.ts')],M,1),
]
def run(job):
    name,argv,cwd,expected = job
    started=time.monotonic()
    with (P/(name+'.stdout')).open('wb') as out,(P/(name+'.stderr')).open('wb') as err:
        try:
            result=subprocess.run(argv,cwd=cwd,env=env,stdout=out,stderr=err,timeout=300)
            code=result.returncode
        except subprocess.TimeoutExpired:
            code=124
    return {'name':name,'argv':argv,'exit_code':code,'expected_exit_code':expected,
        'elapsed_seconds':round(time.monotonic()-started,3),'stdout_sha256':sha(P/(name+'.stdout')),'stderr_sha256':sha(P/(name+'.stderr'))}
print(json.dumps({'status':'running','pid':os.getpid(),'jobs':[x[0] for x in jobs]}),flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results=list(pool.map(run,jobs))
drift=[n for n,h in protected.items() if sha(E/n)!=h]
dependency_drift=[n for n,d in deps.items() if sha(M/'node_modules'/n/'package.json')!=d['metadata_sha256']]
checks_pass=all(x['exit_code']==x['expected_exit_code'] for x in results) and not drift and not dependency_drift
report={'status':'checks_pass_blocking_race_reproduced' if checks_pass else 'fail','commands':results,
    'source_changes':drift,'dependency_changes':dependency_drift,'unaffected_modules_reused':len(binding['unaffected_test_module_closures']),
    'prior390_proof':'docs/release/rapid-completion-2026-10-01/current-mcp-all-modules-terminal1/validation.json',
    'blocking_finding':'Durable local disable during the newly added storage-admission await is not rechecked before runner invocation.',
    'real_launchd_keychain_auth_provider_calls':False,'production_release_claim':False}
(P/'validation.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print(json.dumps(report),flush=True)

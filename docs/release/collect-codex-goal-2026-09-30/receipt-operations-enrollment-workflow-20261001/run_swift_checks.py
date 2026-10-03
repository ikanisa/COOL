#!/usr/bin/env python3
"""Explicit installed macOS SDK compilation/self-test; no Keychain calls."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, subprocess, sys
ROOT=Path(__file__).resolve().parents[4]
BASE=Path(__file__).resolve().parent
LEAF=BASE/'swift-explicit-sdk'
LEAF.mkdir(exist_ok=False)
BRIDGE=ROOT/'tools/collect-notification-mcp'
SWIFTC=Path('/Volumes/PRO-G40/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
SDK=Path('/Volumes/PRO-G40/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk')
SOURCE=BRIDGE/'src/unattended_keychain.swift'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
paths=[SOURCE,SWIFTC,SDK/'SDKSettings.json',SDK/'SDKSettings.plist',Path(__file__).resolve()]
before={str(p):sha(p)for p in paths}
(LEAF/'source.swift').write_bytes(SOURCE.read_bytes())
checks=[]
for name,cmd,bound in [('compile',[str(SWIFTC),'-sdk',str(SDK),'src/unattended_keychain.swift','-o',str(LEAF/'unattended-keychain-self-test')],90),('self-test',[str(LEAF/'unattended-keychain-self-test'),'self-test'],10)]:
    start=datetime.now(timezone.utc).isoformat()
    try:
        r=subprocess.run(cmd,cwd=BRIDGE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=bound,env={'PATH':'/usr/bin:/bin','LANG':'C'})
        output,code=r.stdout,r.returncode
    except subprocess.TimeoutExpired as e:output,code=e.stdout or b'',124
    (LEAF/f'{name}.log').write_bytes(output)
    item={'name':name,'command':cmd,'timeout_seconds':bound,'exit_code':code,'started_at':start,'completed_at':datetime.now(timezone.utc).isoformat(),'log_sha256':sha(LEAF/f'{name}.log')}
    if name=='self-test'and code==0:item['self_test']=json.loads(output)
    checks.append(item)
    if code:break
previous=BASE/'checks-affected-final'
v=json.loads((previous/'verification.json').read_text())
prior=json.loads((previous/'sources-before.json').read_text())
sources_match=all(sha(ROOT/n)==h for n,h in prior.items())
node=next(x for x in v['checks']if x['name']=='node')
node_match=node['exit_code']==0 and node['counts']=={'tests':180,'pass':180,'fail':0,'cancelled':0,'skipped':0,'todo':0}and sha(previous/'node.log')==node['log_sha256']
current_dependencies={str(p.relative_to(BRIDGE)):sha(p)for p in sorted((BRIDGE/'node_modules').rglob('*'))if p.is_file()and not p.is_symlink()}
deps_match=current_dependencies==json.loads((previous/'dependencies-before.json').read_text())
node_tool_match=sha(Path('/Volumes/PRO-G40/Development/Node/bin/node'))==v['tool_hashes_before']['node']
after={str(p):sha(p)for p in paths}
passed=len(checks)==2 and all(x['exit_code']==0 for x in checks)and checks[-1].get('self_test')=={'checks':24,'status':'pass','keychain_called':False,'key_created':False}and before==after and sources_match and node_match and deps_match and node_tool_match and not v['source_drift']and not v['dependency_drift']and v['source_copy_readback']
result={'status':'PASS'if passed else'INCOMPLETE','checks':checks,'source_sdk_compiler_before':before,'source_sdk_compiler_after':after,'source_copy_readback':sha(LEAF/'source.swift')==before[str(SOURCE)],'successful_current_node_association':{'leaf':str(previous.relative_to(ROOT)),'tests':180,'source_count':len(prior),'sources_match':sources_match,'node_log_match':node_match,'dependencies_match':deps_match,'node_tool_match':node_tool_match,'executed_again':False},'whole_current_history_aggregate':'OPEN','keychain_called':False,'real_key_created':False,'hosted_called':False}
(LEAF/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'status':result['status'],'checks':[{k:x[k]for k in('name','exit_code')}for x in checks],'self_test':checks[-1].get('self_test'),'node_source_association':sources_match}))
sys.exit(0 if passed else 1)

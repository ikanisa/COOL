import hashlib,json,os,pathlib,subprocess,time,sys
stage=pathlib.Path(__file__).resolve().parent
repo=stage.parents[1]
package=stage/'tools/collect-notification-mcp'
proof=stage/'accepted-proof-current2'
proof.mkdir(exist_ok=False)
node=pathlib.Path('/Volumes/PRO-G40/Development/Node/bin/node').resolve()
def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
    return h.hexdigest()
def entry(path):
    info=path.lstat()
    if path.is_symlink():return {'kind':'link','target':os.readlink(path),'mode':info.st_mode&0o7777}
    return {'kind':'file','sha256':sha(path),'bytes':info.st_size,'mode':info.st_mode&0o7777}
def bindings():
    result={}
    for base in [package/'src',package/'scripts',stage/'supabase',stage/'scripts/tests']:
        for root,dirs,files in os.walk(base):
            dirs[:]=sorted(d for d in dirs if d!='__pycache__')
            for name in sorted(files):
                path=pathlib.Path(root)/name
                if path.suffix!='.pyc':result['stage/'+str(path.relative_to(stage))]=entry(path)
    for name in ['package.json','pnpm-lock.yaml','tsconfig.json']:
        path=package/name;result['stage/'+str(path.relative_to(stage))]=entry(path)
    deps=(package/'node_modules').resolve()
    for root,dirs,files in os.walk(deps):
        for name in sorted(dirs+files):
            path=pathlib.Path(root)/name
            if path.is_symlink() or path.is_file():result['dependencies/'+str(path.relative_to(deps))]=entry(path)
    result['dependency-root-link']=entry(package/'node_modules')
    result['runtime/node']=entry(node)
    result['runtime/python3']=entry(pathlib.Path('/usr/bin/python3').resolve())
    result['proof/verify_current_repair.py']=entry(pathlib.Path(__file__))
    return result
before=bindings();(proof/'inputs-before.json').write_text(json.dumps(before,sort_keys=True,indent=2)+'\n')
tests=['src/unattended_enrollment_observed.test.ts']
commands=[('observed-fixture',[str(node),'--experimental-strip-types','--test','--test-concurrency=1',*tests],package),
          ('typescript',[str(node),'node_modules/typescript/bin/tsc','--noEmit'],package),
          ('preparer',['/usr/bin/python3','scripts/tests/unattended_launchd_preparation_test.py'],stage)]
results=[]
for name,command,cwd in commands:
    started=time.time()
    with (proof/(name+'.log')).open('wb') as output:
        process=subprocess.Popen(command,cwd=cwd,stdout=output,stderr=subprocess.STDOUT,env=dict(os.environ,NODE_OPTIONS='',PYTHONDONTWRITEBYTECODE='1'))
        print(json.dumps({'started':name,'pid':process.pid}),flush=True)
        code=process.wait()
    results.append({'name':name,'command':command,'cwd':str(cwd),'exit_code':code,'elapsed_seconds':time.time()-started,'log_sha256':sha(proof/(name+'.log'))})
    print(json.dumps({'completed':name,'exit_code':code}),flush=True)
    if code!=0:break
after=bindings();(proof/'inputs-after.json').write_text(json.dumps(after,sort_keys=True,indent=2)+'\n')
receipt={'contract_version':1,'status':'accepted' if len(results)==3 and all(r['exit_code']==0 for r in results) and before==after else 'rejected',
         'input_count':len(before),'inputs_unchanged':before==after,'commands':results,'family_test_files':tests,
         'live_signer_calls':0,'live_http_calls':0,'launchctl_daemon_calls':0,'canonical_source_writes':0,
         'scope':'fixture-dependency repair and types/preparer; composition with unchanged passing cases from preceding source-bound family is recorded separately',
         'export_scope':'cold local evidence only; hot records, credentials, deployment, SQL history and full operational recovery excluded'}
(proof/'receipt.json').write_text(json.dumps(receipt,sort_keys=True,indent=2)+'\n')
print(json.dumps({'status':receipt['status'],'input_count':len(before),'inputs_unchanged':before==after,'receipt':str(proof/'receipt.json')}),flush=True)
sys.exit(0 if receipt['status']=='accepted' else 1)

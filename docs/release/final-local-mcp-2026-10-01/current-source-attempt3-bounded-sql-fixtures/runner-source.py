import datetime,hashlib,json,os,pathlib,re,shutil,subprocess,time
ROOT=pathlib.Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
SOURCE=ROOT/'tools/collect-notification-mcp'
EXPORT=pathlib.Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt184-mcp')
P=ROOT/'docs/release/final-local-mcp-2026-10-01/current-source-attempt3-bounded-sql-fixtures'
NODE=pathlib.Path('/Volumes/PRO-G40/Development/Node/bin/node').resolve(strict=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert not P.exists()and not EXPORT.exists();P.mkdir(parents=True,mode=0o700);EXPORT.mkdir(parents=True)
WORK=EXPORT/'tools/collect-notification-mcp';WORK.mkdir(parents=True)
(P/'runner-source.py').write_bytes(pathlib.Path(__file__).read_bytes())
paths=[SOURCE/n for n in ['package.json','pnpm-lock.yaml','tsconfig.json','README.md']]+sorted(p for p in (SOURCE/'src').rglob('*')if p.is_file())
before={str(p.relative_to(SOURCE)):sha(p)for p in paths}
for n,digest in before.items():
 target=WORK/n;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(SOURCE/n,target);assert sha(target)==sha(SOURCE/n)==digest
shared_paths=sorted((ROOT/'supabase/functions').rglob('*.ts'))+[ROOT/'contracts/collect-shadow-supervisor-v1.lifecycle.fixture.json',ROOT/'supabase/functions/collect-receipt-supervisor/fixtures/observed-health.json']
shared_before={str(p.relative_to(ROOT)):sha(p)for p in shared_paths}
for n,digest in shared_before.items():
 target=EXPORT/n;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/n,target);assert sha(target)==sha(ROOT/n)==digest
(P/'shared-handler-source.json').write_text(json.dumps(shared_before,indent=2,sort_keys=True)+'\n')
subprocess.run(['cp','-cR',str(SOURCE/'node_modules'),str(WORK/'node_modules')],check=True)
def packages():
 return {str(p.relative_to(WORK)):sha(p)for p in (WORK/'node_modules').rglob('*')if p.is_file()and not p.is_symlink()}
package_before=packages()
(P/'source-before.json').write_text(json.dumps(before,indent=2,sort_keys=True)+'\n')
(P/'resolved-package-before.json').write_text(json.dumps(package_before,indent=2,sort_keys=True)+'\n')
(P/'runtime.json').write_text(json.dumps({'binary':str(NODE),'sha256':sha(NODE),'version':subprocess.check_output([str(NODE),'--version'],text=True).strip()},indent=2)+'\n')
env={k:v for k,v in os.environ.items()if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}};env.update(CI='true',PATH=str(NODE.parent)+':'+env['PATH'])
commands=[]
for name,argv in [('typecheck',[str(WORK/'node_modules/.bin/tsc'),'--noEmit']),('tests',[str(NODE),'--experimental-strip-types','--test','--test-reporter=tap',*sorted(str(p.relative_to(WORK))for p in (WORK/'src').glob('*.test.ts'))])]:
 print('START',name,flush=True);started=time.monotonic()
 with (P/(name+'.log')).open('wb')as out:r=subprocess.run(argv,cwd=WORK,env=env,stdout=out,stderr=subprocess.STDOUT,timeout=300)
 commands.append({'name':name,'argv':argv,'exit_code':r.returncode,'seconds':round(time.monotonic()-started,3),'log_sha256':sha(P/(name+'.log'))})
 (P/'execution.json').write_text(json.dumps({'status':'running','commands':commands},indent=2)+'\n');print('END',name,r.returncode,flush=True)
 if r.returncode:break
after={str(p.relative_to(SOURCE)):sha(p)for p in paths};export_drift={n:digest for n,digest in before.items()if sha(WORK/n)!=digest};package_after=packages()
text=(P/'tests.log').read_text()if(P/'tests.log').exists()else''
counts={label:int(match[1])for label in ['tests','pass','fail','cancelled','skipped','todo']if(match:=re.search(r'^# '+label+r' (\d+)$',text,re.M))}
passed=len(commands)==2 and all(c['exit_code']==0 for c in commands)and counts.get('pass',0)>0 and counts.get('fail')==0 and counts.get('cancelled')==0 and before==after and not export_drift and package_before==package_after and all(sha(ROOT/n)==digest and sha(EXPORT/n)==digest for n,digest in shared_before.items())
v={'status':'pass'if passed else'fail','commands':commands,'source_inputs_unchanged':before==after,'export_drift':export_drift,'resolved_package_inputs_unchanged':package_before==package_after,'shared_handler_source_unchanged':all(sha(ROOT/n)==digest and sha(EXPORT/n)==digest for n,digest in shared_before.items()),'shared_handler_source_count':len(shared_before),'source_input_count':len(before),'resolved_package_file_count':len(package_before),'test_counts':counts,'provider_credentials_supplied':False,'scope':'All current notification MCP TypeScript checks and actual loopback stdio/session/ACK/redaction/journal tests in isolated source and dependency copy; no SQL/hosted/provider/device acceptance.','completed_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
(P/'validation.json').write_text(json.dumps(v,indent=2)+'\n');print(v);raise SystemExit(0 if passed else 1)

#!/usr/bin/env python3
"""Execute affected decoders from one source/dependency-frozen private copy."""
import argparse,datetime,hashlib,json,os,pathlib,re,shutil,subprocess,sys
ROOT=pathlib.Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
STAGE=pathlib.Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
def save(p,j):p.write_text(json.dumps(j,indent=2)+'\n')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--sql-report',type=pathlib.Path,required=True);ap.add_argument('--report-dir',type=pathlib.Path,required=True);a=ap.parse_args()
 sql=a.sql_report.resolve();assert json.loads((sql/'result.json').read_text())['status']=='passed'
 report=a.report_dir.resolve();assert not report.exists();report.mkdir();runtime=report/'runtime';runtime.mkdir()
 sources={};tools={};dependencies={};links={}
 def copy(p,rel):
  b=p.read_bytes();sources[str(p)]=sha(b);dest=runtime/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b)
 for p in (ROOT/'tools/collect-notification-mcp/src').rglob('*.ts'):copy(p,p.relative_to(ROOT))
 for name in ['package.json','pnpm-lock.yaml','tsconfig.json']:
  p=ROOT/'tools/collect-notification-mcp'/name
  if p.exists():copy(p,p.relative_to(ROOT))
 for name in ['handler.ts','operations_contract.ts','operations_contract_test.ts']:copy(ROOT/'supabase/functions/collect-receipt-supervisor'/name,'supabase/functions/collect-receipt-supervisor/'+name)
 for rel in ['lib/admin/core/admin_exception_models.dart','lib/admin/core/admin_receipt_deferral_models.dart','lib/core/data/exact_json_values.dart']:
  copy(ROOT/rel,rel)
 for rel in ['tools/collect-notification-mcp/src/unattended_contract.ts','tools/collect-notification-mcp/src/unattended_source_busy.test.ts','supabase/functions/collect-receipt-supervisor/operations_contract.ts','lib/admin/core/admin_exception_models.dart','lib/admin/core/admin_receipt_deferral_models.dart','scripts/tests/admin_receipt_source_busy_test.dart']:
  copy(STAGE/rel,rel)
 proof_rel='docs/release/collect-codex-goal-2026-09-30/receipt-source-busy-20261001/accepted-sql'
 for name in ['observed-busy-ensure.json','observed-busy-admin-detail.json','observed-busy-admin-inbox.json']:copy(sql/name,proof_rel+'/'+name)
 copy(pathlib.Path(__file__),'executed-run-consumers.py')
 node=pathlib.Path('/Volumes/PRO-G40/Development/Node/bin/node').resolve();deno=pathlib.Path('/Users/jeanbosco/.local/bin/deno').resolve();dart=pathlib.Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/cache/dart-sdk/bin/dart').resolve()
 for tool in [node,deno,dart]:tools[str(tool)]=sha(tool.read_bytes())
 deps=ROOT/'tools/collect-notification-mcp/node_modules'
 (runtime/'tools/collect-notification-mcp/node_modules').symlink_to(deps,target_is_directory=True)
 # Capture the local declared dependency tree used by this exact typecheck.
 for p in deps.rglob('*'):
  if p.is_symlink():links[str(p)]=os.readlink(p)
  elif p.is_file():dependencies[str(p)]=sha(p.read_bytes())
 save(report/'frozen-inputs.json',dict(sources=sources,tools=tools,dependencies=dependencies,symlinks=links))
 results=[]
 def execute(label,command,cwd=runtime,timeout=180):
  began=now();r=subprocess.run(command,cwd=cwd,capture_output=True,text=True,timeout=timeout)
  (report/(label+'.stdout')).write_text(r.stdout);(report/(label+'.stderr')).write_text(r.stderr)
  result=dict(label=label,argv=command,cwd=str(cwd),started_at=began,finished_at=now(),exit_code=r.returncode,stdout_sha256=sha(r.stdout.encode()),stderr_sha256=sha(r.stderr.encode()));results.append(result);save(report/'commands.json',results)
  print(label+' exit '+str(r.returncode),flush=True);print(r.stdout[-3500:]+r.stderr[-3500:],flush=True)
  if r.returncode:raise RuntimeError(label+' failed')
 execute('edge',[str(deno),'test','--no-config','--cached-only','supabase/functions/collect-receipt-supervisor/operations_contract_test.ts'])
 execute('mcp',[str(node),'--experimental-strip-types','--test','tools/collect-notification-mcp/src/unattended_source_busy.test.ts'])
 execute('admin',[str(dart),'--enable-asserts','scripts/tests/admin_receipt_source_busy_test.dart',str(runtime/proof_rel)])
 tsc=deps/'typescript/bin/tsc';tools[str(tsc)]=sha(tsc.read_bytes())
 execute('mcp-typecheck',[str(node),str(tsc),'--noEmit','--target','ES2023','--module','NodeNext','--moduleResolution','NodeNext','--allowImportingTsExtensions','--strict','--noUncheckedIndexedAccess','--exactOptionalPropertyTypes','--skipLibCheck','--types','node','src/unattended_source_busy.test.ts'],runtime/'tools/collect-notification-mcp')
 current_sources=all(pathlib.Path(p).read_bytes()and sha(pathlib.Path(p).read_bytes())==s for p,s in sources.items())
 current_tools=all(sha(pathlib.Path(p).read_bytes())==s for p,s in tools.items());current_dependencies=all(sha(pathlib.Path(p).read_bytes())==s for p,s in dependencies.items())and all(os.readlink(p)==s for p,s in links.items())
 save(report/'verification.json',dict(status='passed'if current_sources and current_tools and current_dependencies else'failed',commands=results,source_unchanged=current_sources,tools_unchanged=current_tools,dependencies_unchanged=current_dependencies,source_count=len(sources),dependency_files=len(dependencies),dependency_symlinks=len(links),sql_result_sha256=sha((sql/'result.json').read_bytes()),complete_candidate=False,rendered_admin=False))
 assert current_sources and current_tools and current_dependencies
if __name__=='__main__':main()

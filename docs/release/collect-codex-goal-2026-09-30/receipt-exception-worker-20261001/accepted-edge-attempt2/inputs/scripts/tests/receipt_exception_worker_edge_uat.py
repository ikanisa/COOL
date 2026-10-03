#!/usr/bin/env python3
"""Bind the actual worker HTTP/observed-wire suite to accepted SQL inputs.

Only the real loopback handler and declared RPC transport fixtures run. No
credential, hosted connection, cron activation, device or SMS is permitted.
"""
import argparse,datetime,hashlib,json,pathlib,subprocess

ROOT=pathlib.Path(__file__).resolve().parents[2]
DENO='/Users/jeanbosco/.local/bin/deno'
def sha(b):return hashlib.sha256(b).hexdigest()
def save(path,value):path.write_text(json.dumps(value,indent=2)+'\n')
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--sql-report',required=True);parser.add_argument('--report-dir',required=True);args=parser.parse_args()
 sql=pathlib.Path(args.sql_report).resolve();report=pathlib.Path(args.report_dir).resolve();assert not report.exists();report.mkdir(parents=True);inputs=report/'inputs';inputs.mkdir()
 result=json.loads((sql/'result.json').read_text());assert result['status']=='pass'and result['sources_unchanged']and result['runner_unchanged']and result['support_unchanged']and result['target']['task_container_removed']
 for name,digest in result['migration_sha256'].items():assert sha((ROOT/'supabase/migrations'/name).read_bytes())==digest
 files=list((ROOT/'supabase/functions/collect-receipt-exception-worker').glob('*'))+[ROOT/'supabase/functions/_shared/supabase.ts',ROOT/'supabase/functions/_shared/cors.ts',pathlib.Path(__file__)]
 files=[p for p in files if p.is_file()];bodies={p:p.read_bytes()for p in files};bound={str(p.relative_to(ROOT)):sha(b)for p,b in bodies.items()}
 for p,b in bodies.items():q=inputs/p.relative_to(ROOT);q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(b)
 observed=inputs/'observed';observed.mkdir()
 for name in ['observed-worker-executed.json','observed-worker-lookup.json','observed-worker-expired-lookup.json']:
  data=(sql/name).read_bytes();(observed/name).write_bytes(data);bound['sql/'+name]=sha(data)
 captured=inputs/'supabase/functions/collect-receipt-exception-worker'
 proof=dict(status='running',started_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),sql_result_sha256=sha((sql/'result.json').read_bytes()),sources=bound,source_scope='actual new handler/index/shared service adapter plus3 actual SQL observations;16 focused+1 observed tests',hosted_used=False,device_used=False,sms_sent=False,rpc_fault_cases='declared deterministic transport stubs',http_boundary='actual loopback request',deno_version=subprocess.check_output([DENO,'--version'],text=True).strip())
 save(report/'execution-binding.json',proof)
 commands=[['check',str(captured/'index.ts')],['test','--allow-net=127.0.0.1','--allow-read='+str(observed),str(captured/'handler_test.ts'),str(captured/'observed_test.ts'),'--',str(observed)]]
 for n,command in enumerate(commands):
  r=subprocess.run([DENO,*command],text=True,capture_output=True,cwd=ROOT);(report/f'command{n}.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stdout+r.stderr
 proof.update(status='pass',checks=17,sources_unchanged=all(p.read_bytes()==b for p,b in bodies.items()),finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat());assert proof['sources_unchanged'];save(report/'result.json',proof);print(json.dumps({'status':proof['status'],'checks':17,'sources_unchanged':True}))
if __name__=='__main__':main()

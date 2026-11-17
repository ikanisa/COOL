// The old container may be stopped behind the committed source fence. Read
// Config.Env privately only from the exact recorded stopped executor; never
// restart it or print values.
import {execFileSync} from 'node:child_process';
import {lstatSync,readFileSync} from 'node:fs';
import {ROOT} from './access.mjs';

export function readSourceEnvironment(run=execFileSync){
 const data=JSON.parse(run('docker',['--context','colima-supabase-local','inspect','supabase_edge_runtime_local-app'],{encoding:'utf8',maxBuffer:8*1024*1024}));
 if(!Array.isArray(data)||data.length!==1||data[0].Name!=='/supabase_edge_runtime_local-app'||!Array.isArray(data[0].Config?.Env))throw Error('unexpected_source_container');
 const item=data[0];
 if(item.State?.Running!==true){
  const path=ROOT+'/source-executors-retired.json',s=lstatSync(path);
  if(!s.isFile()||s.isSymbolicLink()||(s.mode&0o077)!==0||s.uid!==process.getuid())throw Error('source_retirement_evidence_unavailable');
  const proof=JSON.parse(readFileSync(path,'utf8')),edge=proof.edgeStopped;
  if(!edge||edge.running!==false||edge.id!==item.Id||edge.name!==item.Name||edge.image!==item.Image||
   edge.started!==item.State?.StartedAt||edge.finished!==item.State?.FinishedAt)throw Error('source_retirement_identity_changed');
 }
 const env=Object.create(null);
 for(const line of item.Config.Env){const n=line.indexOf('=');if(n<1||Object.hasOwn(env,line.slice(0,n)))throw Error('source_environment_invalid');env[line.slice(0,n)]=line.slice(n+1);}
 return env;
}

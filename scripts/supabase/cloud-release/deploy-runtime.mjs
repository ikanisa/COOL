// Deploy the source snapshot while the Cloud database remains fenced.
import {execFileSync} from 'node:child_process';
import {readFileSync,existsSync} from 'node:fs';
import {connect,management,record,ROOT,sha} from './access.mjs';
import {inspectRuntimePlan} from './runtime-plan.mjs';
if(process.argv.length!==3||process.argv[2]!=='--deploy-held')throw Error('explicit_held_deploy_required');
if(existsSync(ROOT+'/runtime-deploy-intent.json'))throw Error('prior_deployment_requires_reconciliation');
const source=JSON.parse(execFileSync('docker',['--context','colima-supabase-local','inspect','supabase_edge_runtime_local-app'],{encoding:'utf8'}))[0];
if(source.Id!=='7fec198386959bb537a16dfb30692b3031f1f244a4616cc26449fedeeea60903'||source.State.Running)throw Error('retired_source_required');
const localEnv=Object.fromEntries(source.Config.Env.map(x=>{const i=x.indexOf('=');return[x.slice(0,i),x.slice(i+1)];}));
const prepared=await inspectRuntimePlan({localEnv});
if(prepared.check.status!=='passed'||prepared.proposal.publicView().requiredCloudSecretsMissing.length)throw Error('runtime_plan_incomplete');
const c=await connect();try{
 const state=(await c.query("select mode,epoch,source_sha256 from private.collect_fence_control where singleton")).rows[0];
 if(state.mode!=='fenced')throw Error('cloud_fence_required');
 const hold=JSON.parse(readFileSync(ROOT+'/hold-complete.json'));
 const deployed=(await management('functions')).json();
 if(deployed.length!==3||hold.after.some(f=>!deployed.some(x=>x.id===f.id&&x.slug===f.slug&&x.version===f.version&&x.ezbr_sha256===f.ezbr_sha256)))throw Error('held_function_preimage_changed');
 record('runtime-deploy-intent.json',{sourceSha256:prepared.snapshot.sourceSha,snapshot:prepared.snapshot.summary(),configuration:prepared.proposal.publicView(),typecheck:prepared.check,before:deployed,state,at:new Date().toISOString()});
 const changes=prepared.proposal.mutationBody();
 if(changes.length)await management('secrets',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(changes)});
 const metadata=(await management('secrets')).json();
 if(changes.some(x=>metadata.find(v=>v.name===x.name)?.value!==sha(x.value))||metadata.find(x=>x.name==='BURIMUNSI_DEFAULT_STAFF_PIN')?.value!==sha('1987'))throw Error('runtime_secret_readback_failed');
 record('runtime-secrets-confirmed.json',{sourceSha256:prepared.snapshot.sourceSha,changed:changes.map(x=>x.name),defaultPinConfirmed:true,at:new Date().toISOString()});
 for(const slug of ['collect-api','admin-api','collect-jobs']){
  record('runtime-'+slug+'-attempt.json',{sourceSha256:prepared.snapshot.sourceSha,at:new Date().toISOString()});
  const result=(await management('functions/deploy?slug='+slug,{method:'POST',body:prepared.snapshot.makeForm(slug)})).json();
  const readback=(await management('functions')).json().find(x=>x.slug===slug);
  if(!readback||readback.status!=='ACTIVE'||readback.verify_jwt!==false||readback.version!==result.version||readback.version<=deployed.find(x=>x.slug===slug).version||!readback.ezbr_sha256)throw Error('runtime_deployment_readback_failed');
  record('runtime-'+slug+'-complete.json',{sourceSha256:prepared.snapshot.sourceSha,function:readback,at:new Date().toISOString()});
  console.log(JSON.stringify({status:'runtime_deployed_held',slug,version:readback.version}));
 }
 const final=(await management('functions')).json();
 if(final.length!==3||(await c.query('select mode from private.collect_fence_control where singleton')).rows[0].mode!=='fenced')throw Error('runtime_final_fence_changed');
 record('runtime-deploy-complete.json',{sourceSha256:prepared.snapshot.sourceSha,functions:final,databaseHeld:true,at:new Date().toISOString()});
}finally{await c.end();}

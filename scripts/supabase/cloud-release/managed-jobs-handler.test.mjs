// Copy the real Edge tree to an owned temporary directory, apply only the
// candidate source, then run its actual handler with local dependency doubles.
import assert from 'node:assert/strict';
import {cp,mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {renderManagedJobsHandler} from './managed-jobs-handler-patch.mjs';
const r=await renderManagedJobsHandler(),dir=await mkdtemp(join(tmpdir(),'collect-managed-jobs-handler-'));
const once=(s,a,b)=>{const i=s.indexOf(a);assert(i>=0&&s.indexOf(a,i+a.length)<0);return s.slice(0,i)+b+s.slice(i+a.length);};
try{
 await cp(new URL('../../../supabase/functions',import.meta.url),join(dir,'supabase/functions'),{recursive:true});
 await cp(new URL('../../../supabase/retention-inventory.json',import.meta.url),join(dir,'supabase/retention-inventory.json'));
 const shared=join(dir,'supabase/functions/_shared');
 // The substitutions are fixture-only and never become the deployed patch.
 let serve=r.serve;
 serve=once(serve,"env.MOMO_PROCESSING_PAUSED=env.MOMO_PROCESSING_PAUSED??'true';stage='database_initialization';env.DB=new PostgresDatabase(connection(env.COLLECT_DATABASE_URL,env));await assertRuntimeDeployment(env.DB.sql,env);",
  "env.MOMO_PROCESSING_PAUSED=env.MOMO_PROCESSING_PAUSED??'true';stage='database_initialization';env.DB=globalThis.__managedJobsFixture.db;await globalThis.__managedJobsFixture.check();");
 serve=once(serve,'backend:sqlFenceBackend(env.DB.sql,fenceConnection(env.COLLECT_DATABASE_URL,env)),sourceSha256:env.BUILD_SOURCE_ID,kind:\'jobs\'',
  'backend:globalThis.__managedJobsFixture.backend,sourceSha256:env.BUILD_SOURCE_ID,kind:\'jobs\'');
 serve=once(serve,"if(managed&&!(await claimManagedJobDispatch(env.DB,input,payload,token)))return json({code:'unauthorized'},401);stage='storage_initialization';env.PRIVATE_MEDIA=new SupabaseObjectBucket(env);stage='provider_initialization';Object.assign(env,providerAdapters(env));",
  "if(managed&&!(await claimManagedJobDispatch(env.DB,input,payload,token)))return json({code:'unauthorized'},401);stage='storage_initialization';env.PRIVATE_MEDIA={};stage='provider_initialization';Object.assign(env,globalThis.__managedJobsFixture.adapters);");
 await writeFile(join(shared,'serve.js'),serve);await writeFile(join(shared,'scheduled-processing.js'),r.processing);await writeFile(join(shared,'managed-jobs-dispatch-auth.mjs'),r.auth);
 const script=String.raw`
import assert from 'node:assert/strict';
import {createScheduledHandler} from './serve.js';
import {dispatchMessage} from './managed-jobs-dispatch-auth.mjs';
const project='rrlduytparvsjfmegalh',source='a'.repeat(64),key='b'.repeat(64);
const base={APP_ENVIRONMENT:'test',SUPABASE_URL:'https://'+project+'.supabase.co',COLLECT_DATABASE_URL:'postgres://fixture:fixture@127.0.0.1:5432/fixture',
 SUPABASE_PUBLISHABLE_KEY:'synthetic-public',SUPABASE_SECRET_KEY:'synthetic-secret',BUILD_SOURCE_ID:source,COLLECT_JOB_AUTH_MODE:'supabase_dispatch_hmac_v1',COLLECT_JOB_SIGNING_KEY:key,
 COLLECT_JOB_TOKEN:'old-legacy-token',MOMO_PROCESSING_PAUSED:'true',COLLECT_JOBS_MODE:'maintenance_only'};
const tickets=new Map(),counts={work:0,cleanup:0,auto:0,ledger:0,complete:0};
globalThis.__managedJobsFixture={backend:{},async check(){},adapters:{AI:{async run(){}}},db:{setApplicationWork(){},prepare(sql){return{bind(id,s,p){return{async first(){
 const t=tickets.get(id);if(!t)return {accepted:false};if(sql.includes('collect_managed_job_claim')){if(t.claimed||JSON.stringify(t.payload)!==p)return {accepted:false};t.claimed=true;return {accepted:true};}
 if(!t.claimed||t.completed)return {accepted:false};t.completed=true;t.digest=p;counts.complete++;return {accepted:true};}};}};}}};
const opts={openWork:async()=>{counts.work++;return{async finish(){}};},reportHealth(){},cleanupDiagnostics:async()=>({status:'complete',removed:0}),
 processNativeAuto:async()=>{counts.auto++;return{status:'complete',processed:1,results:[{state:'completed',relation:'duplicate'}]};},
 processNativeSmsLedger:async()=>{counts.ledger++;return{status:'complete',processed:0,results:[]};},processNativeFinancialWork:async()=>null};
const cleanup=async()=>{counts.cleanup++;return{status:'complete',examined_limit:100,purged:0,provider_calls:0};};
const paused=async()=>({paused:true,processed:0,results:[]});
const sign=async payload=>{const k=await crypto.subtle.importKey('raw',new TextEncoder().encode(key),{name:'HMAC',hash:'SHA-256'},false,['sign']);const b=await crypto.subtle.sign('HMAC',k,new TextEncoder().encode(dispatchMessage(source,payload.dispatch_id,payload.dispatch_expires_at)));return 'Bearer '+Array.from(new Uint8Array(b),x=>x.toString(16).padStart(2,'0')).join('');};
const make=(payload,authorization)=>new Request('https://'+project+'.supabase.co/functions/v1/collect-jobs',{method:'POST',headers:{'Content-Type':'application/json',Authorization:authorization},body:JSON.stringify(payload)});
const ticket=(more={})=>{const p={dispatch_id:crypto.randomUUID(),dispatch_expires_at:Math.floor(Date.now()/1000)+60,...more};tickets.set(p.dispatch_id,{payload:p});return p;};
const digest=async r=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await r.clone().arrayBuffer())),x=>x.toString(16).padStart(2,'0')).join('');
Deno.test('managed handler verifies signatures, claims exact payload once and stores response digest',async()=>{
 let env={...base};const h=createScheduledHandler(()=>env,cleanup,paused,opts),p=ticket(),signature=await sign(p);
 assert.equal((await h(make(p,'Bearer old-legacy-token'))).status,401);assert.equal(counts.work,0);
 const altered={...p,native_sms_admission:{contract:'extra'}};assert.equal((await h(make(altered,signature))).status,401);assert.equal(counts.cleanup,0);
 const reply=await h(make(p,signature));assert.equal(reply.status,200);assert.equal(counts.cleanup,1);assert.equal(counts.complete,1);assert.equal(tickets.get(p.dispatch_id).digest,await digest(reply));
 assert.equal((await h(make(p,signature))).status,401);assert.equal(counts.cleanup,1);
 env={...base,COLLECT_JOB_AUTH_MODE:''};assert.equal((await h(make(ticket(),'Bearer old-legacy-token'))).status,401);
 env={...base,SUPABASE_URL:'https://wrong.example'};const wrong=ticket();assert.equal((await h(make(wrong,await sign(wrong)))).status,401);
});
Deno.test('native processing requires matching source, approval and model admission',async()=>{
 const approval='c'.repeat(64),admission={contract:'collect.native-sms-automation.v1',source_sha256:source,approval_sha256:approval,model_id:'fixture-model',batch_limit:1};
 const env={...base,BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'true',COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256:approval,MOMO_AI_ENABLED:'true',MOMO_AI_MODEL:'fixture-model',OPENAI_API_KEY:'fixture'};
 const h=createScheduledHandler(()=>env,cleanup,paused,opts),missing=ticket();assert.equal((await h(make(missing,await sign(missing)))).status,503);assert.equal(counts.auto,0);
 const bad=ticket({native_sms_admission:{...admission,approval_sha256:'d'.repeat(64)}});assert.equal((await h(make(bad,await sign(bad)))).status,503);assert.equal(counts.auto,0);
 const good=ticket({native_sms_admission:admission}),reply=await h(make(good,await sign(good)));assert.equal(reply.status,200);const data=await reply.clone().json();
 assert.deepEqual(data.native_sms_admission,admission);assert.equal(data.native_auto_processing.status,'complete');assert.equal(data.native_sms_ledger.status,'complete');
 assert.equal(counts.auto,1);assert.equal(counts.ledger,1);assert.equal(tickets.get(good.dispatch_id).digest,await digest(reply));
});
`;
 await writeFile(join(shared,'managed-jobs-handler-candidate.test.ts'),script);
 const cwd=join(dir,'supabase/functions'),deno=process.env.DENO_BIN??'/Users/jeanbosco/.local/bin/deno';
 for(const args of [['check','--cached-only','collect-jobs/index.ts'],['test','--no-check','--cached-only','--allow-env','_shared/managed-jobs-handler-candidate.test.ts']]){
  const result=spawnSync(deno,args,{cwd,encoding:'utf8',timeout:120000,maxBuffer:2*1024*1024});
  if(result.status!==0){process.stderr.write(result.stderr||result.stdout);throw Error('candidate_handler_fixture_failed');}
 }
 console.log(JSON.stringify({suite:'managed-jobs-handler',checks:2,edge_source:'isolated patched copy',provider_calls:0}));
}finally{await rm(dir,{recursive:true,force:true});}

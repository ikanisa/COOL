// Synthetic socket-only fixture, launched by managed-jobs-dispatch-auth.test.mjs.
// It uses the actual Edge postgres@3.4.7 adapter and the real claim helper.
import postgres from 'npm:postgres@3.4.7';
import {PostgresDatabase} from '../../../supabase/functions/_shared/postgres.js';
import {openApplicationWork} from '../../../supabase/functions/_shared/application-fence.js';
import * as release from './managed-jobs-dispatch-auth.mjs';
import * as edge from '../../../supabase/functions/_shared/managed-jobs-dispatch-auth.mjs';

const fixture=JSON.parse(Deno.env.get('COLLECT_SYNTHETIC_DRIVER_FIXTURE') ?? 'null');
if(!fixture || !/^\/(?:private\/)?tmp\/collect-pg-transfer-[A-Za-z0-9]+\/s$/.test(fixture.socket) || !Number.isInteger(fixture.port) ||
 !/^[a-f0-9]{64}$/.test(fixture.key) || fixture.source!=='a'.repeat(64) || !Array.isArray(fixture.cases) || fixture.cases.length!==4)
 throw new Error('synthetic_fixture_required');
const sql=postgres({host:fixture.socket,port:fixture.port,database:'postgres',user:'postgres',max:2,prepare:false,ssl:false});
const encoder=new TextEncoder();
try{
 let checks=0;
 for(let i=0;i<fixture.cases.length;i++){
  const entry=fixture.cases[i],module=i<2?release:edge;
  const env={COLLECT_JOB_AUTH_MODE:'supabase_dispatch_hmac_v1',SUPABASE_URL:'https://rrlduytparvsjfmegalh.supabase.co',BUILD_SOURCE_ID:fixture.source,COLLECT_JOB_SIGNING_KEY:fixture.key};
  const row={contractVersion:1,admissionId:entry.admission,sourceSha256:fixture.source,epoch:1,kind:'jobs',state:'active',mode:'open'};
  const backend={async register(){return row;},async lease(){return {row,async assert(){return row;},async release(){}};},async close(){return {...row,state:'settled',reason:'completed',externalDispatches:0,uncertainDispatches:0};},async status(){return {...row,found:true};}};
  const work=await openApplicationWork({backend,sourceSha256:fixture.source,kind:'jobs',id:entry.admission});
  const db=new PostgresDatabase(sql,{},work);
  const hmac=await crypto.subtle.importKey('raw',encoder.encode(fixture.key),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  const digest=new Uint8Array(await crypto.subtle.sign('HMAC',hmac,encoder.encode(module.dispatchMessage(fixture.source,entry.payload.dispatch_id,entry.payload.dispatch_expires_at))));
  const signature='Bearer '+Array.from(digest,value=>value.toString(16).padStart(2,'0')).join('');
  if(await module.claimManagedJobDispatch(db,env,null,signature)!==false)throw Error('null_payload_accepted');checks++;
  if(await module.claimManagedJobDispatch(db,env,{...entry.payload,unexpected:true},signature)!==false)throw Error('altered_payload_accepted');checks++;
  // The former cast lets postgres@3.4.7 turn this pre-stringified payload
  // into a JSON string. Verify that it rejects the original ticket, then that
  // the corrected helper claims that exact ticket once.
  const legacy=await db.prepare('SELECT private.collect_managed_job_claim(?::uuid,?::text,?::jsonb,?::text) AS accepted')
   .bind(entry.payload.dispatch_id,fixture.source,JSON.stringify(entry.payload),signature.slice(7)).first();
  if(legacy?.accepted!==false)throw Error('legacy_json_driver_failure_not_observed');checks++;
  if(await module.claimManagedJobDispatch(db,env,entry.payload,signature)!==true)throw Error('exact_payload_rejected');checks++;
  if(await module.claimManagedJobDispatch(db,env,entry.payload,signature)!==false)throw Error('replay_accepted');checks++;
  await work.finish();
 }
 console.log(JSON.stringify({suite:'managed-jobs-real-driver',checks,copies:2,payloads:['maintenance','native'],provider_calls:0}));
}finally{await sql.end();}

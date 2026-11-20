import assert from 'node:assert/strict';
import {createManagedSmsHandler} from '../src/handler.ts';
import {sha256} from '../../collect-sms/src/util.ts';
import type {Pool} from '../src/transactions.ts';

const token=(v:string)=>'app_'+v.repeat(64);
const good=token('a'),revoked=token('b'),unknown=token('c'),limited=token('d');
const profile={format:'collect.deployment.v1',id:'fixture-managed',mode:'managed',environment:'production',supabase_origin:'https://rrlduytparvsjfmegalh.supabase.co',member_api_origin:'https://api.example.invalid',admin_origin:'https://admin.example.invalid',public_origin:'https://www.example.invalid',google_callback_origin:'https://admin.example.invalid'};
const raw=JSON.stringify(Object.fromEntries(Object.keys(profile).sort().map(k=>[k,(profile as any)[k]])));
const env={COLLECT_SMS_MANAGED_ENABLED:'true',BUILD_SOURCE_ID:'a'.repeat(64),COLLECT_SMS_UNVERIFIED_APPROVAL_CLAIM_SHA256:'b'.repeat(64),COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:await sha256(raw),SMS_PUBLIC_ORIGIN:'https://sms.example.invalid',SMS_HYPERDRIVE:{}};
const base=env.SMS_PUBLIC_ORIGIN+'/functions/v1/collect-sms';
const ctx={waitUntil(_p:Promise<unknown>) {}};
function post(credential:string){return new Request(base+'/v1/messages',{method:'POST',headers:{authorization:'Bearer '+credential,'content-type':'application/json','idempotency-key':'fixture-key'},body:JSON.stringify({kind:'receipt',message_id:'alpha:fixture',to:'+250788123456',text:'Synthetic only',not_after:'2035-01-01T00:00:00Z'})});}
function get(credential:string){return new Request(base+'/v1/messages/alpha%3Afixture',{headers:{authorization:'Bearer '+credential}});}
async function fixture({rollbackLost=false,lookupUnconfirmed=false}:{rollbackLost?:boolean;lookupUnconfirmed?:boolean}={}){
 const entries=new Map<string,any>([
  [await sha256(good),{application_id:'alpha',allowed_kinds:'["receipt"]',scopes:'["messages:read","messages:write"]',revoked:false}],
  [await sha256(revoked),{application_id:'alpha',allowed_kinds:'["receipt"]',scopes:'["messages:read","messages:write"]',revoked:true}],
  [await sha256(limited),{application_id:'alpha',allowed_kinds:'["operation"]',scopes:'["messages:read","messages:write"]',revoked:false}],
 ]);
 const records:{id:number;sql:string}[]=[],released:number[]=[],closeStates:string[]=[];let sequence=0,stored:any=null,mutations=0;
 const pool:Pool={async reserve(){const id=++sequence;let begun=false,role='collect_sms_edge',verified=false;return {
  async unsafe(sql:string,values:unknown[]=[],options:Record<string,unknown>={}){
   records.push({id,sql});assert.deepEqual(options,{prepare:true,simple:false});
   if(sql.startsWith('BEGIN')){begun=true;return [];}
   assert.equal(begun,true);
   if(sql.includes('AS login_name'))return [{login_name:'collect_sms_edge',active_name:'collect_sms_edge',login_safe:true,role_safe:true,other_memberships:0,private_usage:false,app_usage:false,public_create:false,database_create:false}];
   if(sql==='SET LOCAL ROLE collect_sms_runtime'){role='collect_sms_runtime';return [];}
   if(sql.includes("set_config('collect.sms_verified'")){verified=true;return [];}
   if(sql.includes('AS active_name')&&sql.includes('sms_usage'))return [{active_name:role,verified:verified?'true':'false',sms_usage:true,sms_create:false,app_usage:false,private_usage:false}];
   if(sql.includes('collect_sms.work_assert_write'))return [{result:{contractVersion:1,epoch:1,mode:'open'}}];
   if(sql.includes('FROM collect_sms.applications WHERE token_hash=')){if(lookupUnconfirmed)return undefined;const row=entries.get(values[0] as string);return row&&!row.revoked?[row]:[];}
   if(sql.includes('FROM applications a JOIN messages m')){const row=entries.get(values[0] as string);return row&&!row.revoked&&stored&&stored.message_id===values[1]&&stored.application_id===row.application_id?[{...row,message_id:stored.message_id,message_application_id:stored.application_id,kind:stored.kind}]:[];}
   if(sql.includes('FROM applications WHERE token_hash=')){const row=entries.get(values[0] as string);return row&&!row.revoked?[row]:[];}
   if(sql.includes('FROM messages WHERE application_id=')&&sql.includes('idempotency_key='))return stored&&stored.application_id===values[0]&&stored.idempotency_key===values[1]?[stored]:[];
   if(sql.startsWith('INSERT INTO messages(')){
    const columns=sql.slice(sql.indexOf('(')+1,sql.indexOf(')')).split(',');stored=Object.fromEntries(columns.map((col,i)=>[col,values[i]]));
    Object.assign(stored,{state:'accepted',owner_installation_id:null,assignment_version:0,cancel_requested:0,phone_accepted_at:null});mutations++;return Object.assign([],{count:1});
   }
   if(sql.includes('FROM messages m WHERE m.message_id='))return stored&&stored.message_id===values[0]&&stored.application_id===values[1]?[stored]:[];
   if(/FROM (attempts|message_parts|device_events|audit_events) WHERE/.test(sql))return [];
   if(sql==='COMMIT'){begun=false;return [];}
   if(sql==='ROLLBACK'){if(rollbackLost)throw Error('synthetic lost rollback acknowledgement');begun=false;return [];}
   if(sql.startsWith('SET LOCAL ')||sql.includes('pg_catalog.set_config')||sql.includes('pg_advisory_xact_lock'))return [];
   throw Error('unexpected synthetic query');
  },release(){released.push(id);}};},async end(){}};
 let row:any;const backend={register:async(id:string,source:string,kind:string)=>row={contractVersion:1,admissionId:id,sourceSha256:source,kind,epoch:1,state:'active',mode:'open'},
  lease:async()=>({row,assert:async()=>row,release:async()=>{}}),
  close:async(_id:string,_ep:number,_src:string,state:string,reason:string,externalDispatches:number,uncertainDispatches:number)=>{closeStates.push(state);return {...row,state,reason,externalDispatches,uncertainDispatches};},status:async()=>({...row,found:true})};
 const handler=createManagedSmsHandler({poolFactory:()=>pool,fenceFactory:()=>backend});
 return {handler,records,released,closeStates,get mutations(){return mutations;}};
}
Deno.test('the real managed adapter permits valid receipt create and reconciliation',async()=>{
 const f=await fixture(),origin=profile.admin_origin,postRequest=post(good),getRequest=get(good);postRequest.headers.set('origin',origin);getRequest.headers.set('origin',origin);
 const created=await f.handler(postRequest,env,ctx);assert.equal(created.status,202);assert.equal(created.headers.get('access-control-allow-origin'),origin);assert.equal(f.mutations,1);
 const read=await f.handler(getRequest,env,ctx);assert.equal(read.status,200);assert.equal(read.headers.get('access-control-allow-origin'),origin);const payload=await read.json();assert.equal(payload.message.message_id,'alpha:fixture');assert.equal(payload.message.kind,'receipt');
 assert.deepEqual(f.closeStates,['settled','settled']);assert.ok(f.records.filter(x=>x.sql.includes('FROM collect_sms.applications')).length>=5);
});
Deno.test('real managed access check gives a uniform empty 404 for revoked, unknown and disallowed credentials only after rollback',async()=>{
 for(const credential of [revoked,unknown,limited])for(const request of [post,get]){
  const f=await fixture(),input=request(credential);input.headers.set('origin',profile.admin_origin);const response=await f.handler(input,env,ctx);assert.equal(response.status,404);assert.equal(await response.text(),'');assert.equal(response.headers.get('access-control-allow-origin'),profile.admin_origin);
  const denied=f.records.find(x=>x.sql.includes('FROM collect_sms.applications WHERE token_hash='))!;assert.ok(denied);assert.ok(f.records.some(x=>x.id===denied.id&&x.sql==='ROLLBACK'));assert.ok(f.released.includes(denied.id));
  assert.deepEqual(f.closeStates,['settled']);assert.equal(f.mutations,0);
 }
});
Deno.test('unconfirmed access rollback remains unavailable and the transaction is quarantined',async()=>{
 for(const request of [post,get]){
  const f=await fixture({rollbackLost:true}),input=request(revoked);input.headers.set('origin',profile.admin_origin);const response=await f.handler(input,env,ctx);assert.equal(response.status,503);assert.equal(response.headers.get('access-control-allow-origin'),profile.admin_origin);
  const denied=f.records.find(x=>x.sql.includes('FROM collect_sms.applications WHERE token_hash='))!;assert.ok(denied);assert.ok(f.records.some(x=>x.id===denied.id&&x.sql==='ROLLBACK'));assert.equal(f.released.includes(denied.id),false);
  assert.deepEqual(f.closeStates,['unresolved']);assert.equal(f.mutations,0);
 }
});
Deno.test('a malformed database lookup is uncertain rather than a confirmed credential denial',async()=>{
 for(const request of [post,get]){const f=await fixture({lookupUnconfirmed:true});const response=await f.handler(request(good),env,ctx);
  assert.equal(response.status,503);assert.deepEqual(f.closeStates,['unresolved']);assert.equal(f.mutations,0);}
});

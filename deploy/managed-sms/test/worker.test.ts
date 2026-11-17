import assert from 'node:assert/strict';
import worker from '../src/worker.ts';
import {createManagedSmsHandler} from '../src/handler.ts';
import {sha256} from '../../collect-sms/src/util.ts';
const token=(v:string)=>'app_'+v.repeat(64),a=token('a'),b=token('b'),restricted=token('c'),wrongKind=token('d'),emptyId=token('e');
const profile={format:'collect.deployment.v1',id:'fixture-managed',mode:'managed',environment:'production',supabase_origin:'https://rrlduytparvsjfmegalh.supabase.co',member_api_origin:'https://api.example.invalid',admin_origin:'https://admin.example.invalid',public_origin:'https://www.example.invalid',google_callback_origin:'https://admin.example.invalid'};
const raw=JSON.stringify(Object.fromEntries(Object.keys(profile).sort().map(k=>[k,(profile as any)[k]]))),digest=await sha256(raw);
const env={COLLECT_SMS_MANAGED_ENABLED:'true',BUILD_SOURCE_ID:'a'.repeat(64),COLLECT_SMS_UNVERIFIED_APPROVAL_CLAIM_SHA256:'b'.repeat(64),COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:digest,SMS_PUBLIC_ORIGIN:'https://sms.example.invalid',SMS_HYPERDRIVE:{}};
const base=env.SMS_PUBLIC_ORIGIN+'/functions/v1/collect-sms',future='2035-01-01T00:00:00Z';
const ctx={waitUntil(_p:Promise<unknown>) {}};
function admission(){let row:any;return {register:async(id:string,source:string,kind:string)=>row={contractVersion:1,admissionId:id,sourceSha256:source,kind,epoch:1,state:'active',mode:'open'},
 lease:async()=>({row,assert:async()=>row,release:async()=>{}}),close:async(_id:string,_ep:number,_src:string,state:string,reason:string,externalDispatches:number,uncertainDispatches:number)=>({...row,state,reason,externalDispatches,uncertainDispatches}),status:async()=>({...row,found:true})};}
async function fixture(){const tokens=new Map([[await sha256(a),{id:'alpha',scopes:['messages:read','messages:write'],kinds:['receipt']}],[await sha256(b),{id:'beta',scopes:['messages:read','messages:write'],kinds:['receipt']}],[await sha256(restricted),{id:'restricted',scopes:['messages:read'],kinds:['receipt']}],[await sha256(wrongKind),{id:'gamma',scopes:['messages:read'],kinds:['operation']}],[await sha256(emptyId),{id:'',scopes:['messages:read'],kinds:['receipt']}] ]);const rows=new Map<string,any>();let writes=0,admissions=0,ends=0,historyBatches=0;
 class DB{withApplicationWork(){return this;}prepare(query:string){let vals:any[]=[];return {bind(...v:any[]){vals=v;return this;},async first(){
  if(query.includes('FROM applications a JOIN messages m')){const principal=tokens.get(vals[0]),found=[...rows.values()].find(x=>x.message_id===vals[1]&&x.application_id===principal?.id);return found?{application_id:principal!.id,allowed_kinds:JSON.stringify(principal!.kinds),scopes:JSON.stringify(principal!.scopes),message_id:found.message_id,message_application_id:found.application_id,kind:found.kind}:null;}
  if(query.includes('FROM applications WHERE token_hash=')){const value=tokens.get(vals[0]);return value?{application_id:value.id,scopes:JSON.stringify(value.scopes),allowed_kinds:JSON.stringify(value.kinds)}:null;}
  if(query.includes('WHERE application_id=? AND idempotency_key=?'))return rows.get(vals[0]+'\0'+vals[1])??null;
  if(query.includes('FROM messages m WHERE m.message_id='))return [...rows.values()].find(x=>x.message_id===vals[0]&&x.application_id===vals[1])??null;
  throw Error('unexpected fixture query');},async all(){const row=await this.first();return {success:true,results:row?[row]:[],meta:{changes:0}};},async run(){if(!query.startsWith('INSERT INTO messages('))throw Error('unexpected fixture write');writes++;
   const [message_id,application_id,kind,to_number,text,payload_digest,request_digest,idempotency_key,priority,not_after,available_at,created_at,updated_at,campaign_id,otp_challenge_id,metadata_json,requires_fresh_decision,eligibility_until,segments_estimate]=vals;
   rows.set(application_id+'\0'+idempotency_key,{message_id,application_id,kind,to_number,text,payload_digest,request_digest,idempotency_key,priority,not_after,available_at,created_at,updated_at,campaign_id,otp_challenge_id,metadata_json,requires_fresh_decision,eligibility_until,segments_estimate,state:'accepted',cancel_requested:0,owner_installation_id:null,assignment_version:0,phone_accepted_at:null});return {success:true,results:[],meta:{changes:1}};}};}
  async batch(statements:any[]){historyBatches++;return statements.map(()=>({success:true,results:[],meta:{changes:0}}));}}
 const backend=admission(),db=new DB(),pool:any={reserve:async()=>{throw Error('unused');},end:async()=>{ends++;}};
 const handler=createManagedSmsHandler({poolFactory:()=>pool,databaseFactory:()=>db,fenceFactory:()=>({...backend,register:async(...args:any[])=>{admissions++;return (backend.register as any)(...args);}})});
 return {handler,rows,db,backend,pool,get writes(){return writes;},get admissions(){return admissions;},get ends(){return ends;},get historyBatches(){return historyBatches;}};
}
function post(credential=a,key='original-key',text='Synthetic only'){return new Request(base+'/v1/messages',{method:'POST',headers:{Authorization:'Bearer '+credential,'Content-Type':'application/json','Idempotency-Key':key},body:JSON.stringify({kind:'receipt',message_id:'alpha:fixture-message',to:'+250788123456',text,not_after:future})});}
Deno.test('production entrypoint remains closed regardless of caller-controlled configuration',async()=>{const response=await worker.fetch(post(),env,ctx);assert.equal(response.status,503);assert.equal(response.headers.get('cache-control'),'no-store');});
Deno.test('authority and route checks ignore forged forwarding headers before admission',async()=>{const f=await fixture();for(const req of [new Request('https://evil.example.invalid/functions/v1/collect-sms/v1/messages',{method:'POST',headers:{'x-forwarded-host':'sms.example.invalid','x-forwarded-proto':'https','cf-connecting-ip':'127.0.0.1'}}),new Request(env.SMS_PUBLIC_ORIGIN+'/functions/v1/collect-sms-other/v1/messages'),new Request(base+'/v1/device/jobs',{headers:{Authorization:'Bearer '+a}}),new Request(base+'/v1/messages',{method:'POST',headers:{Authorization:'Bearer device_'+('d'.repeat(64))}})]){const r=await f.handler(req,env,ctx);assert.ok([401,403,404].includes(r.status));assert.equal(r.headers.get('cache-control'),'no-store');}assert.equal(f.admissions,0);});
Deno.test('actual gateway enforces application scopes and durable message replay identity',async()=>{const f=await fixture();
 let r=await f.handler(post(),env,ctx);assert.equal(r.status,202);const first=await r.json();assert.equal(first.message_id,'alpha:fixture-message');assert.equal(f.writes,1);
 r=await f.handler(post(),env,ctx);assert.equal(r.status,202);assert.equal(f.writes,1);
 r=await f.handler(post(a,'original-key','changed'),env,ctx);assert.equal(r.status,409);assert.equal(f.writes,1);
 r=await f.handler(post(restricted,'other-key'),env,ctx);assert.equal(r.status,403);assert.equal(f.writes,1);
 r=await f.handler(new Request(base+'/v1/messages/alpha%3Afixture-message',{headers:{Authorization:'Bearer '+b}}),env,ctx);assert.equal(r.status,404);
 r=await f.handler(new Request(base+'/v1/messages/alpha%3Afixture-message',{headers:{Authorization:'Bearer '+a}}),env,ctx);assert.equal(r.status,200);assert.equal((await r.json()).message.application_id,'alpha');assert.equal(r.headers.get('cache-control'),'no-store');
});
Deno.test('non-receipt bodies, missing idempotency and cross-origin requests stop before database access',async()=>{const f=await fixture();const sample={kind:'otp',to:'+250788123456',text:'test',not_after:future};
 for(const request of [new Request(base+'/v1/messages',{method:'POST',headers:{Authorization:'Bearer '+a,'content-type':'application/json','idempotency-key':'key'},body:JSON.stringify(sample)}),new Request(base+'/v1/messages',{method:'POST',headers:{Authorization:'Bearer '+a,'content-type':'application/json'},body:JSON.stringify(sample)}),new Request(base+'/v1/messages',{method:'POST',headers:{Authorization:'Bearer '+a,'content-type':'application/json','idempotency-key':'key',origin:'https://evil.example.invalid'},body:JSON.stringify(sample)})])assert.ok([400,403].includes((await f.handler(request,env,ctx)).status));assert.equal(f.admissions,0);});
Deno.test('unknown admission or connection cleanup never becomes a success',async()=>{const f=await fixture(),unavailable=createManagedSmsHandler({poolFactory:()=>({reserve:async()=>{throw Error('unused');},end:async()=>{}}),databaseFactory:()=>({withApplicationWork(){return this;}}),fenceFactory:()=>({...admission(),register:async()=>{throw Error('unknown acknowledgement');}})});
 assert.equal((await unavailable(post(),env,ctx)).status,503);assert.equal(f.writes,0);
 const badEnd=createManagedSmsHandler({poolFactory:()=>({reserve:async()=>{throw Error('unused');},end:async()=>{throw Error('unknown close');}}),databaseFactory:()=>({withApplicationWork(){return this;}}),fenceFactory:()=>admission(),application:{fetch:async()=>Response.json({ok:true})} as any});
 assert.equal((await badEnd(post(),env,ctx)).status,503);
});
Deno.test('unconfirmed admission close returns 503 and never retries the close',async()=>{let calls=0,statusCalls=0;
 const f=admission(),handler=createManagedSmsHandler({poolFactory:()=>({reserve:async()=>{throw Error('unused');},end:async()=>{}}),databaseFactory:()=>({withApplicationWork(){return this;}}),fenceFactory:()=>({...f,close:async()=>{calls++;throw Error('ack_lost');},status:async()=>{statusCalls++;return f.status();}}),application:{fetch:async()=>Response.json({ok:true},{status:202})} as any});
 const response=await handler(post(),env,ctx);assert.equal(response.status,503);assert.equal(calls,1);assert.equal(statusCalls,1);assert.equal(response.headers.get('cache-control'),'no-store');
});
Deno.test('oversized input is refused before admission and outbound providers remain disabled',async()=>{const f=await fixture();
 const large=new Request(base+'/v1/messages',{method:'POST',headers:{Authorization:'Bearer '+a,'content-type':'application/json','idempotency-key':'key'},body:JSON.stringify({kind:'receipt',text:'x'.repeat(262144)})});
 assert.equal((await f.handler(large,env,ctx)).status,400);assert.equal(f.admissions,0);
 const handler=createManagedSmsHandler({poolFactory:()=>({reserve:async()=>{throw Error('unused');},end:async()=>{}}),databaseFactory:()=>({withApplicationWork(){return this;}}),fenceFactory:()=>admission(),application:{fetch:async(_req:any,bindings:any)=>{await bindings.FETCH('https://provider.example.invalid');return Response.json({ok:true});}} as any});
 assert.equal((await handler(post(),env,ctx)).status,503);
});

Deno.test('non-receipt, missing scope, empty and cross-app identities never return message or history',async()=>{
 const f=await fixture(),privateText='SYNTHETIC-PRIVATE-CONTENT';
 for(const kind of ['operation','campaign','otp'])f.rows.set('alpha\0'+kind,{application_id:'alpha',message_id:'alpha:'+kind,kind,text:privateText});
 f.rows.set('gamma\0receipt',{application_id:'gamma',message_id:'gamma:receipt',kind:'receipt',text:privateText});
 f.rows.set('\0empty',{application_id:'',message_id:'empty:receipt',kind:'receipt',text:privateText});
 for(const [credential,id] of [[a,'alpha:operation'],[a,'alpha:campaign'],[a,'alpha:otp'],[b,'alpha:operation'],[wrongKind,'gamma:receipt'],[emptyId,'empty:receipt']]){
  const response=await f.handler(new Request(base+'/v1/messages/'+encodeURIComponent(id),{headers:{Authorization:'Bearer '+credential}}),env,ctx);
  assert.equal(response.status,404);assert.equal((await response.text()).includes(privateText),false);assert.equal(f.historyBatches,0);
 }
});
Deno.test('unexpected receipt response kind, identity, envelope or duplicate JSON fails closed',async()=>{
 const f=await fixture();assert.equal((await f.handler(post(),env,ctx)).status,202);
 const original=await (await f.handler(new Request(base+'/v1/messages/alpha%3Afixture-message',{headers:{Authorization:'Bearer '+a}}),env,ctx)).json();
 const variants=[{...original,message:{...original.message,kind:'operation'}},{...original,message:{...original.message,application_id:'beta'}},
  {...original,message:{...original.message,message_id:'alpha:other'}},{...original,unexpected:'SYNTHETIC-PRIVATE'},
  {...original,attempts:[{message_id:'other',text:'SYNTHETIC-PRIVATE'}]},{...original,audit:[{resource_id:'other',text:'SYNTHETIC-PRIVATE'}]}];
 for(const body of variants){const handler=createManagedSmsHandler({poolFactory:()=>f.pool,databaseFactory:()=>f.db,fenceFactory:()=>f.backend,application:{fetch:async()=>Response.json(body)} as any});
  const response=await handler(new Request(base+'/v1/messages/alpha%3Afixture-message',{headers:{Authorization:'Bearer '+a}}),env,ctx);assert.equal(response.status,503);assert.equal((await response.text()).includes('SYNTHETIC-PRIVATE'),false);}
 const duplicate=JSON.stringify(original).replace('"kind":"receipt"','"kind":"operation","kind":"receipt"');
 const handler=createManagedSmsHandler({poolFactory:()=>f.pool,databaseFactory:()=>f.db,fenceFactory:()=>f.backend,application:{fetch:async()=>new Response(duplicate,{headers:{'content-type':'application/json'}})} as any});
 assert.equal((await handler(new Request(base+'/v1/messages/alpha%3Afixture-message',{headers:{Authorization:'Bearer '+a}}),env,ctx)).status,503);
});
Deno.test('aborted stalled body is canceled before any database admission',async()=>{
 const f=await fixture(),controller=new AbortController();let canceled=false;
 const stream=new ReadableStream({start(){},cancel(){canceled=true;}});
 const request=new Request(base+'/v1/messages',{method:'POST',headers:{Authorization:'Bearer '+a,'content-type':'application/json','idempotency-key':'key'},body:stream,signal:controller.signal,duplex:'half'} as any);
 const pending=f.handler(request,env,ctx);await new Promise(r=>setTimeout(r,20));controller.abort();const response=await Promise.race([pending,new Promise<never>((_,reject)=>setTimeout(()=>reject(Error('abort_timeout')),500))]);
 assert.equal(response.status,400);await Promise.resolve();assert.equal(canceled,true);assert.equal(f.admissions,0);
});
Deno.test('stalled body times out and is canceled before admission',async()=>{
 const f=await fixture();let canceled=false;const stream=new ReadableStream({start(){},cancel(){canceled=true;}});
 const request=new Request(base+'/v1/messages',{method:'POST',headers:{Authorization:'Bearer '+a,'content-type':'application/json','idempotency-key':'key'},body:stream,duplex:'half'} as any);
 const start=performance.now(),response=await f.handler(request,env,ctx);assert.equal(response.status,400);assert.ok(performance.now()-start<6000);assert.equal(canceled,true);assert.equal(f.admissions,0);
});
Deno.test('late fence close retains its pool under the background owner',async()=>{
 let closeNow!:()=>void,closeCalls=0,ends=0;const backend=admission(),original=backend.close,background:Promise<unknown>[]=[];
 const handler=createManagedSmsHandler({poolFactory:()=>({reserve:async()=>{throw Error('unused');},end:async()=>{ends++;}}),databaseFactory:()=>({withApplicationWork(){return this;}}),
  fenceFactory:()=>({...backend,close:(...args:any[])=>{closeCalls++;return new Promise(resolve=>{closeNow=()=>void (original as any)(...args).then(resolve);});}}),
  application:{fetch:async()=>Response.json({ok:true},{status:202})} as any,finishObservationMs:20,backgroundGraceMs:1000});
 const response=await handler(post(),env,{waitUntil(p){background.push(p);}});assert.equal(response.status,503);assert.equal(closeCalls,1);assert.equal(ends,0);assert.equal(background.length,1);
 closeNow();await Promise.all(background);assert.equal(ends,1);assert.equal(closeCalls,1);
});
Deno.test('background grace expiry leaves an unfinished pool quarantined',async()=>{
 let ends=0;const backend=admission(),background:Promise<unknown>[]=[];
 const handler=createManagedSmsHandler({poolFactory:()=>({reserve:async()=>{throw Error('unused');},end:async()=>{ends++;}}),databaseFactory:()=>({withApplicationWork(){return this;}}),
  fenceFactory:()=>({...backend,close:()=>new Promise(()=>{})}),application:{fetch:async()=>Response.json({ok:true},{status:202})} as any,finishObservationMs:20,backgroundGraceMs:30});
 assert.equal((await handler(post(),env,{waitUntil(p){background.push(p);}})).status,503);await Promise.all(background);assert.equal(ends,0);
});

Deno.test('authorized receipt reconciliation retains expected related history',async()=>{
 const f=await fixture();assert.equal((await f.handler(post(),env,ctx)).status,202);
 const original=await (await f.handler(new Request(base+'/v1/messages/alpha%3Afixture-message',{headers:{Authorization:'Bearer '+a}}),env,ctx)).json(),id='alpha:fixture-message';
 original.attempts=[{message_id:id,attempt_id:'attempt',installation_id:'device',parts_total:1,handoff_at:null,unknown_observed:0,failed_observed:0,aborted_before_call:0,updated_at:future}];
 original.parts=[{message_id:id,attempt_id:'attempt',part_index:0,sent_at:null,delivered_at:null,failed_at:null,sent_failed_at:null,delivery_failed_at:null,delivery_unknown_at:null,error_code:null}];
 original.history=[{event_id:'event',type:'phone_accepted',attempt_id:null,at:future,received_at:future,part_index:null,parts_total:null,error_code:null,detail_redacted_at:null,detail:{}}];
 original.audit=[{event_id:'audit',actor_type:'application',actor_id:'alpha',action:'created',resource_id:id,at:future}];
 const handler=createManagedSmsHandler({poolFactory:()=>f.pool,databaseFactory:()=>f.db,fenceFactory:()=>f.backend,application:{fetch:async()=>Response.json(original)} as any});
 const response=await handler(new Request(base+'/v1/messages/'+encodeURIComponent(id),{headers:{Authorization:'Bearer '+a}}),env,ctx);assert.equal(response.status,200);
 const payload=await response.json();assert.equal(payload.message.kind,'receipt');assert.equal(payload.history.length,1);assert.equal(payload.attempts.length,1);
 original.history.push({unrecognized:'SYNTHETIC-PRIVATE'});const rejected=await handler(new Request(base+'/v1/messages/'+encodeURIComponent(id),{headers:{Authorization:'Bearer '+a}}),env,ctx);assert.equal(rejected.status,503);assert.equal((await rejected.text()).includes('SYNTHETIC-PRIVATE'),false);
});

Deno.test('only exact allowed browser preflights reach receipt routes without admission',async()=>{
 const f=await fixture(),origin='https://admin.example.invalid';
 const preflight=(path:string,method:string,headers:string,source=origin)=>new Request(base+path,{method:'OPTIONS',headers:{origin:source,'access-control-request-method':method,'access-control-request-headers':headers}});
 for(const [path,method,headers] of [['/v1/messages','POST','authorization, content-type, idempotency-key'],['/v1/messages/alpha%3Afixture-message','GET','authorization']]){
  const response=await f.handler(preflight(path,method,headers),env,ctx);assert.equal(response.status,204);assert.equal(response.headers.get('access-control-allow-origin'),origin);
  assert.equal(response.headers.get('access-control-allow-methods'),method);assert.equal(response.headers.get('access-control-allow-headers'),headers);
  assert.equal(response.headers.get('access-control-allow-credentials'),null);assert.equal(response.headers.get('cache-control'),'no-store');assert.ok(response.headers.get('vary')?.includes('Origin'));
 }
 for(const request of [preflight('/v1/messages','GET','authorization'),preflight('/v1/messages/a','POST','authorization'),preflight('/v1/messages','POST','authorization, x-other'),preflight('/v1/messages/a','GET','idempotency-key'),preflight('/v1/messages','POST','authorization, authorization'),preflight('/v1/messages','POST','authorization','https://evil.example.invalid'),new Request(base+'/v1/messages',{method:'OPTIONS',headers:{'access-control-request-method':'POST','access-control-request-headers':'authorization','x-forwarded-host':'sms.example.invalid'}})]){
  const response=await f.handler(request,env,ctx);assert.equal(response.status,403);assert.notEqual(response.headers.get('access-control-allow-origin'),'https://evil.example.invalid');
 }
 assert.equal(f.admissions,0);
});
Deno.test('verified browser origin receives no-store CORS on early denial, success and unavailable responses',async()=>{
 const f=await fixture(),origin='https://admin.example.invalid';
 const invalid=new Request(base+'/v1/messages',{method:'POST',headers:{origin,'content-type':'application/json','idempotency-key':'key'},body:'{}'});
 const missing=await f.handler(invalid,env,ctx);assert.equal(missing.status,401);assert.equal(missing.headers.get('access-control-allow-origin'),origin);assert.equal(missing.headers.get('cache-control'),'no-store');
 const input=post();input.headers.set('origin',origin);const created=await f.handler(input,env,ctx);assert.equal(created.status,202);assert.equal(created.headers.get('access-control-allow-origin'),origin);
 const read=await f.handler(new Request(base+'/v1/messages/alpha%3Afixture-message',{headers:{origin,authorization:'Bearer '+a}}),env,ctx);assert.equal(read.status,200);assert.equal(read.headers.get('access-control-allow-origin'),origin);
 const unavailable=createManagedSmsHandler({poolFactory:()=>({reserve:async()=>{throw Error('unused');},end:async()=>{}}),databaseFactory:()=>({withApplicationWork(){return this;}}),fenceFactory:()=>({...admission(),register:async()=>{throw Error('unknown');}})});
 const failing=post();failing.headers.set('origin',origin);const failed=await unavailable(failing,env,ctx);assert.equal(failed.status,503);assert.equal(failed.headers.get('access-control-allow-origin'),origin);assert.equal(failed.headers.get('access-control-allow-credentials'),null);
});

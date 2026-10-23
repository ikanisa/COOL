import {initializeSqlFixture,finishSqlFixtureWork} from './helpers/fenced-postgres.js';
import {fencedTest} from './helpers/fenced-unit.js';
import {assert,assertEquals,assertRejects} from 'jsr:@std/assert@1.0.14';
import {cleanupExpiredGoogleFlows} from './helpers/module-auth-cleanup.js';
import {connection,PostgresDatabase} from './helpers/fenced-postgres.js';
import {exchangeGoogleFlow,GOOGLE_PROJECT_ORIGIN,GOOGLE_APPLICATION_CALLBACK} from './helpers/module-domain-google_auth.js';
import {encrypt} from './helpers/module-domain-encryption.js';

fencedTest('Google cleanup requires a bounded server budget before database access',async()=>{
 const DB={prepare(){throw new Error('No database access allowed');}};
 for(const options of [{limit:0},{limit:501},{limit:1.5},{nowEpoch:-1},{nowEpoch:NaN}]){
  await assertRejects(()=>cleanupExpiredGoogleFlows({DB},options));
 }
 await assertRejects(()=>cleanupExpiredGoogleFlows({}));
});
fencedTest('Google cleanup never claims a failed or lost SQL result completed',async()=>{
 for(const outcome of ['throw','invalid'] as const){
  const DB={prepare(){return {bind(){return {first(){if(outcome==='throw')throw new Error('synthetic-private-database-error');return 501;}};}};}};
  const error=await assertRejects(()=>cleanupExpiredGoogleFlows({DB},{limit:1}));
  assert(error instanceof Error);
  assertEquals((error as any).code,'auth_cleanup_unconfirmed');
  assertEquals(error.message.includes('synthetic-private'),false);
 }
});

const database=Deno.env.get('COLLECT_GOOGLE_TEST_DATABASE_URL');
fencedTest({name:'actual Google TTL cleanup is bounded, race-safe and preserves metadata on isolated PostgreSQL',ignore:!database,sanitizeResources:false,sanitizeOps:false,fn:async()=>{
 const url=new URL(database!);assert(['127.0.0.1','localhost'].includes(url.hostname)&&(url.port==='55439'||(Deno.env.get('COLLECT_CI_SYNTHETIC')==='true'&&['55441','55443'].includes(url.port)))&&url.pathname==='/collect_google_test','Only the separate synthetic Google fixture database is allowed');
 const sql=connection(database!),DB=new PostgresDatabase(sql),originalFetch=globalThis.fetch,originalNow=Date.now;
 let providerCalls=0,admissions=0;
 const at=Math.floor(originalNow()/1000),state=()=>crypto.randomUUID().replaceAll('-','')+'a'.repeat(11),origin='https://platform-admin.collect.ikanisa.com';
 const keys={SESSION_KEY_ID:'synthetic-cleanup-v1',SESSION_ENCRYPTION_KEY:btoa('k'.repeat(32))};
 const env=()=>({DB:new PostgresDatabase(sql),...keys,GOOGLE_AUTH_ENABLED:'true',SUPABASE_URL:GOOGLE_PROJECT_ORIGIN,COLLECT_GOOGLE_CALLBACK_URL:GOOGLE_APPLICATION_CALLBACK,ADMIN_ORIGIN:origin,SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic_cleanup_fixture'});
 const sha=async(value:string)=>[...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))].map(x=>x.toString(16).padStart(2,'0')).join('');
 const pkce=async(value:string)=>btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value))))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
 const create=async(expires:number,status='ready',payload='{"synthetic_ciphertext":"fixture-only"}',fixedId=crypto.randomUUID())=>{
  const proof=state(),nonce=state(),challenge=state(),clientState=state(),handoff=state(),operation=status==='consumed'?crypto.randomUUID():null;
  await sql`insert into app.auth_google_flows(id,state_hash,nonce,provider_verifier,client_challenge,client_state,return_origin,registration_allowed,created_at,expires_at,status,handoff_hash,consumed_operation_id,email,google_subject)values(${fixedId},${await sha(proof)},${nonce},${payload},${challenge},${clientState},${origin},0,${expires-300},${expires},${status},${await sha(handoff)},${operation},'synthetic-retention@example.test','synthetic-provider-subject')`;
  await sql`insert into private.google_flow_context(flow_id,surface,request_origin)values(${fixedId},'admin',${origin})`;
  return {id:fixedId,clientState,handoff,challenge};
 };
 const row=async(id:string)=>(await sql`select * from app.auth_google_flows where id=${id}`)[0];
 const metadata=(value:any)=>Object.fromEntries(Object.entries(value).filter(([key])=>!['provider_verifier','status'].includes(key)));
 try {
  globalThis.fetch=async()=>{providerCalls++;throw new Error('Cleanup must not contact a provider');};
  await cleanupExpiredGoogleFlows({DB},{nowEpoch:at,limit:500});
  const before=await create(at-1,'pending'),boundary=await create(at,'exchanging'),future=await create(at+1),consumed=await create(at-20,'consumed'),unknown=await create(at-10,'failed');
  const expected=new Map();for(const item of [before,boundary,future,consumed,unknown])expected.set(item.id,await row(item.id));
  // Prior fixture metadata is retained. Each fresh sweep obeys its budget.
  assertEquals((await cleanupExpiredGoogleFlows({DB},{nowEpoch:at,limit:1})).purged,1);
  assertEquals((await cleanupExpiredGoogleFlows({DB},{nowEpoch:at,limit:1})).purged,1);
  for(const item of [before,boundary]){const actual=await row(item.id);assertEquals(actual.provider_verifier,'{}');assertEquals(actual.status,'failed');assertEquals(metadata(actual),metadata(expected.get(item.id)));}
  for(const item of [future,consumed,unknown])assertEquals(await row(item.id),expected.get(item.id));
  assertEquals(providerCalls,0);
  const context=await sql`select surface,request_origin from private.google_flow_context where flow_id=${before.id}`;assertEquals(context[0].surface,'admin');assertEquals(context[0].request_origin,origin);
  assertEquals((await cleanupExpiredGoogleFlows({DB},{nowEpoch:at,limit:2})).purged,0);

  // An active exchange owns a row lock. Cleanup must skip it without waiting,
  // then leave the committed consumed state and audit identity alone.
  const owned=await create(at-5),locker=await sql.reserve();
  try {await locker`begin`;await locker`select id from app.auth_google_flows where id=${owned.id} for update`;
   const skipped=await cleanupExpiredGoogleFlows({DB},{nowEpoch:at,limit:10});assertEquals(skipped.purged,0);
   await locker`update app.auth_google_flows set status='consumed',provider_verifier='{}',consumed_operation_id=${crypto.randomUUID()} where id=${owned.id}`;await locker`commit`;
  }finally{await locker`rollback`.catch(()=>{});locker.release();}
  assertEquals((await cleanupExpiredGoogleFlows({DB},{nowEpoch:at,limit:10})).purged,0);assertEquals((await row(owned.id)).status,'consumed');

  const lost=await create(at-2,'pending');
  class LostReplyDatabase extends PostgresDatabase {
   fired=false;
   constructor(){super(sql);}
   override async execute(statement:any){const result=await super.execute(statement);if(!this.fired){this.fired=true;throw new Error('Synthetic committed cleanup reply lost');}return result;}
  }
  const lostError=await assertRejects(()=>cleanupExpiredGoogleFlows({DB:new LostReplyDatabase()},{nowEpoch:at,limit:10}));assertEquals((lostError as any).code,'auth_cleanup_unconfirmed');
  assertEquals((await row(lost.id)).provider_verifier,'{}');assertEquals((await row(lost.id)).status,'failed');assertEquals((await cleanupExpiredGoogleFlows({DB},{nowEpoch:at,limit:10})).purged,0);assertEquals(providerCalls,0);

  const auth=crypto.randomUUID(),sid=crypto.randomUUID(),claims={sub:auth,session_id:sid,role:'authenticated',aud:'authenticated',aal:'aal1',iat:at-10,exp:at+3600,iss:GOOGLE_PROJECT_ORIGIN+'/auth/v1'};
  const token=btoa('{}')+'.'+btoa(JSON.stringify(claims))+'.synthetic-not-a-hosted-signature';
  const user={id:auth,email:'synthetic-google-race@example.test',email_confirmed_at:new Date().toISOString(),identities:[{provider:'google'}]};
  globalThis.fetch=async(input:Request|string|URL,init?:RequestInit)=>{providerCalls++;const request=input instanceof Request?input:new Request(input,init);assertEquals(new URL(request.url).pathname,'/auth/v1/user');return Response.json(user);};
  const validFlow=async(expires:number)=>{
   const verifier=state(),flow=await create(expires),cipher=await encrypt({DATA_KEY_ID:keys.SESSION_KEY_ID,DATA_ENCRYPTION_KEY:keys.SESSION_ENCRYPTION_KEY},new TextEncoder().encode(JSON.stringify({access_token:token,refresh_token:'synthetic-race-refresh'})),'google-handoff:'+flow.id);
   await sql`update app.auth_google_flows set provider_verifier=${cipher},client_challenge=${await pkce(verifier)} where id=${flow.id}`;
   const request=()=>new Request(GOOGLE_PROJECT_ORIGIN+'/api/admin/auth/google/exchange',{method:'POST',headers:{Origin:origin,'Content-Type':'application/json','X-Collect-Requested-With':'collect-admin'},body:JSON.stringify({code:flow.handoff,code_verifier:verifier,client_state:flow.clientState})});
   return {...flow,request};
  };
  // Both contenders use the same deterministic server clock. Before expiry,
  // exchange wins and cleanup cannot erase an admissible payload.
  Date.now=()=>at*1000;const valid=await validFlow(at+1);
  const raced=await Promise.allSettled([exchangeGoogleFlow(valid.request(),env(),{surface:'admin',admit:async()=>{admissions++;return Response.json({admitted:true});}}),cleanupExpiredGoogleFlows({DB},{nowEpoch:at,limit:10})]);
  assertEquals(raced[0].status,'fulfilled');assertEquals(raced[1].status,'fulfilled');assertEquals(admissions,1);assertEquals((await row(valid.id)).status,'consumed');
  // At the exact expiry second, cleanup wins. Exchange cannot dispatch identity
  // or admission, revive the status or return a second legitimate result.
  const expired=await validFlow(at);const callsBefore=providerCalls;
  const expiredRace=await Promise.allSettled([exchangeGoogleFlow(expired.request(),env(),{surface:'admin',admit:async()=>{admissions++;return Response.json({admitted:true});}}),cleanupExpiredGoogleFlows({DB},{nowEpoch:at,limit:10})]);
  assertEquals(expiredRace[0].status,'rejected');assertEquals(expiredRace[1].status,'fulfilled');assertEquals(admissions,1);assertEquals(providerCalls,callsBefore);assertEquals((await row(expired.id)).status,'failed');assertEquals((await row(expired.id)).provider_verifier,'{}');
 }finally{Date.now=originalNow;globalThis.fetch=originalFetch;await finishSqlFixtureWork();await sql.end({timeout:1});}
}});

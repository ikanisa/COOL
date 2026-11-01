import assert from 'node:assert/strict';
import {dispatchAssistedSms,inspectAssistedSms,prepareAssistedSmsDispatch} from '../domain/assisted_sms_dispatch.js';
import {encrypt} from '../domain/encryption.js';
import {digest} from '../domain/core.js';
import {attestAdminEmailAccount} from '../domain/admin_email_policy.js';
import {fencedTest,fixtureEnvironment} from './helpers/fenced-unit.js';

// The production cipher, original-grant checks and fence dispatch are real.
// Conditional database result and provider HTTP are explicit boundary doubles;
// native table transitions are independently installed by notification-channels.
async function fixture(){
 const uid=()=>crypto.randomUUID(),at=Math.floor(Date.now()/1000),account={id:uid(),principal_id:uid(),auth_user_id:uid(),auth_session_id:uid(),public_id:uid(),token_hash:'b'.repeat(64),origin:'https://admin.example.invalid',auth_version:1};
 attestAdminEmailAccount(account,{contract_version:1,public_session_id:account.public_id,email_verified_at:at,proof_id:uid()});
 const row:any={attempt_id:uid(),job_id:uid(),payment_id:uid(),entry_id:uid(),collection_id:uid(),recipient_user_id:uid(),destination_revision:1,application_id:'receipt-app',not_after:new Date((at+60)*1000).toISOString(),state:'ready'};
 let current=true,posts=0,gets=0,lost=false;
 const db={prepare(sql:string){return {bind(...values:any[]){return {sql,values,async run(){assert(sql.startsWith('UPDATE app.assisted_sms_dispatches SET state='));row.state=values[0];row.provider_state=values[1];return {success:true};}};}};},async batch(statements:any[]){
  const s=statements[0];if(s.sql.startsWith('SELECT d.*'))return [{results:[{...row}]}];
  if(s.sql.startsWith('UPDATE app.assisted_sms_dispatches SET state=')){row.state=s.values[0];row.provider_state=s.values[1];return [{results:[{attempt_id:row.attempt_id}]}];}
  assert(s.sql.includes("d.state='ready'"));assert(s.sql.includes('claim.actor_email_proof_id=?'));assert(s.sql.includes('privacy_retention_barriers'));
  if(!current||row.state!=='ready')return [{results:[]}];row.state='sending';return [{results:[{attempt_id:row.attempt_id}]}];
 }};
 const env:any=fixtureEnvironment({DB:db,BUILD_SOURCE_ID:'a'.repeat(64),DATA_KEY_ID:'test',DATA_ENCRYPTION_KEY:btoa('e'.repeat(32)),COLLECT_RECEIPT_SMS_ENABLED:'true',COLLECT_RECEIPT_SMS_APPROVAL_SHA256:'b'.repeat(64),OPENSMS_RECEIPT_BASE_URL:'https://sms.example.invalid',OPENSMS_RECEIPT_APPLICATION_ID:'receipt-app',OPENSMS_RECEIPT_APPLICATION_TOKEN:'t'.repeat(48)});
 const ctx={env,account,actor:{userId:account.principal_id,sessionId:account.auth_session_id}};
 const grant=await prepareAssistedSmsDispatch(ctx,{id:row.attempt_id},{expires_seconds:at+60});
 row.grant_sha256=await digest(grant.token);row.provider_message_id='receipt-app:collect-receipt:'+row.attempt_id;
 const to='+250788000001',text='Synthetic recorded receipt',encoder=new TextEncoder();
 row.body_sha256=await digest(text);row.destination_sha256=await digest(to);
 row.body_ciphertext=await encrypt(env,encoder.encode(text),`assisted-sms-body:${row.job_id}:${row.payment_id}:${row.entry_id}`);
 row.destination_ciphertext=await encrypt(env,encoder.encode(to),`assisted-sms-destination:${row.collection_id}:${row.recipient_user_id}:1`);
 const available=new Date().toISOString(),fields=[row.provider_message_id,'receipt-app','receipt',to,text,'80',row.not_after,available,''];
 const payload=await digest('collect-sms-payload-v1\n'+fields.map(v=>`${encoder.encode(v).length}:${v}`).join(''));
 return {ctx,row,body:{attempt_id:row.attempt_id,dispatch_token:grant.token},deny(){current=false;},lose(){lost=true;},counts:()=>({posts,gets}),
  fetch:async(url:any,init:any)=>{assert(String(url).startsWith('https://sms.example.invalid/v1/messages'));if(init.method==='POST'){posts++;if(lost)throw Error('synthetic lost result');return Response.json({message_id:row.provider_message_id,state:'accepted'},{status:202});}
   gets++;return Response.json({message:{message_id:row.provider_message_id,application_id:'receipt-app',kind:'receipt',to,text,priority:80,not_after:row.not_after,available_at:available,campaign_id:null,content_redacted_at:null,state:'accepted',payload_digest:payload,updated_at:available}});
  }};
}
fencedTest('one original SMS grant dispatches at most once under concurrent callers',async()=>{
 const f=await fixture(),old=globalThis.fetch;globalThis.fetch=f.fetch;
 try{const results=await Promise.allSettled([dispatchAssistedSms(f.ctx,f.body),dispatchAssistedSms(f.ctx,f.body)]);assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(f.counts().posts,1);assert.equal(f.row.state,'accepted');await assert.rejects(dispatchAssistedSms(f.ctx,f.body));assert.equal(f.counts().posts,1);}finally{globalThis.fetch=old;}
});
fencedTest('changed final authority denies before the gateway POST',async()=>{
 const f=await fixture(),old=globalThis.fetch;globalThis.fetch=f.fetch;f.deny();
 try{await assert.rejects(dispatchAssistedSms(f.ctx,f.body));assert.equal(f.counts().posts,0);assert.equal(f.row.state,'ready');}finally{globalThis.fetch=old;}
});
fencedTest('lost SMS submission is retained unknown and reconciled by GET only',async()=>{
 const f=await fixture(),old=globalThis.fetch;globalThis.fetch=f.fetch;f.lose();
 try{const unknown=await dispatchAssistedSms(f.ctx,f.body);assert.equal(unknown.provider_accepted,false);assert.equal(f.row.state,'unknown');await assert.rejects(dispatchAssistedSms(f.ctx,f.body));const observed=await inspectAssistedSms(f.ctx,{attempt_id:f.row.attempt_id});assert.equal(observed.provider_accepted,true);assert.equal(observed.observation,null);assert.deepEqual(f.counts(),{posts:1,gets:1});}finally{globalThis.fetch=old;}
});

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture} from './admin_sms_support/fixture.mjs';
import {notificationRpc} from '../src/notifications.js';

const operation='get_current_member_payment_review_request_v1';
const claims=session=>JSON.parse(Buffer.from(session.access_token.split('.')[1],'base64url'));
const actor=session=>({userId:claims(session).sub,sessionId:claims(session).session_id});
async function setup(t){
 const f=await fixture(t,{MOMO_PROCESSING_PAUSED:'true'},{migrationsThrough:15}),account=await f.seedAccount(),owner=await f.stepUp(await f.login(account)),member=await f.seedMember();
 const group=await f.operation('groups',owner.cookie,{title:'Support recovery',slug:'support-recovery',collection_type:'ikimina',owner_user_id:member.id,receiver:{label:'Synthetic support receiver',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Generated member support recovery qualification'});assert.equal(group.status,200,JSON.stringify(group));
 const session=await f.nativeLogin(member.phone),collectionId=group.body.resource_id;
 const issued=await f.call('/v1/rpc/create_contribution_intent',{origin:'https://collect.example',headers:{Authorization:'Bearer '+session.access_token},data:{collection:collectionId,p_expected_amount_rwf:5000,p_request_id:randomUUID()}});assert.equal(issued.status,200,JSON.stringify(issued));
 const body={p_kind:'payment_review',p_collection_id:collectionId,p_intent_id:issued.body.id,p_request_id:randomUUID(),p_provider_reference:'SYNTHETIC_PRIVATE_REFERENCE_007',p_note:'SYNTHETIC_PRIVATE_NOTE_MUST_NOT_APPEAR_IN_READBACK'};
 const write=(data=body,current=session,headers={})=>f.call('/v1/rpc/create_mobile_support_request',{origin:'https://collect.example',headers:{Authorization:'Bearer '+current.access_token,...headers},data});
 const query={p_request_id:body.p_request_id,p_collection_id:collectionId,p_intent_id:issued.body.id};
 const read=(data=query,current=session)=>f.call('/v1/rpc/'+operation,{origin:'https://collect.example',headers:{Authorization:'Bearer '+current.access_token},data});
 return {f,member,owner,account,session,collectionId,intent:issued.body,body,query,write,read};
}
// Simulate the existing60second OTP cooldown elapsing; retain all issued
// challenge/history rows and exercise the normal HTTP verification flow.
async function replacementSignIn(s){await s.f.db.prepare('UPDATE auth_otp_throttles SET last_requested_at=last_requested_at-61').run();return s.f.nativeLogin(s.member.phone);}
const rowCount=async(db,table)=>(await db.prepare('SELECT count(*) AS n FROM '+table).first()).n;
async function financialRows(db){const output={};for(const table of ['payments','ledger_entries','notification_events','support_requests','request_receipts','audit_log'])output[table]=(await db.prepare('SELECT * FROM '+table).all()).results.map(row=>JSON.stringify(row)).sort();return output;}

test('replacement member sign-in reads the stable original acknowledgement without submitted private fields or loosening write replay',async t=>{
 const s=await setup(t),absent=await s.read();assert.equal(absent.status,200,JSON.stringify(absent));assert.deepEqual(absent.body,{id:s.body.p_request_id,status:'absent',collection_id:s.collectionId,intent_id:s.intent.id,financial_effects:0});
 const accepted=await s.write();assert.equal(accepted.status,200,JSON.stringify(accepted));const previous=claims(s.session),replacement=await replacementSignIn(s);assert.notEqual(claims(replacement).session_id,previous.session_id);
 await s.f.db.prepare("UPDATE auth_sessions SET revoked_at=unixepoch(),revocation_reason='synthetic_replacement_signin' WHERE id=?").bind(previous.session_id).run();
 const before=await financialRows(s.f.db),received=await s.read(s.query,replacement);assert.equal(received.status,200,JSON.stringify(received));assert.deepEqual(received.body,accepted.body);assert.deepEqual(await financialRows(s.f.db),before);
 for(const secret of [s.body.p_provider_reference,s.body.p_note,previous.session_id,s.member.id])assert.ok(!JSON.stringify(received.body).includes(secret));
 assert.equal((await s.write(s.body,replacement)).status,409,'global write receipt retains its original session binding');assert.deepEqual(await financialRows(s.f.db),before);
 assert.equal(await rowCount(s.f.db,'mutation_guards'),0);assert.equal(await rowCount(s.f.db,'momo_processing_guards'),0);
});

test('commit with a lost acknowledgement is recovered after replacement sign-in without a second support request',async t=>{
 const s=await setup(t),old=claims(s.session);
 s.f.setGate(async event=>{assert.equal(event.phase,'lost_reply');await s.f.db.prepare("UPDATE auth_sessions SET revoked_at=unixepoch(),revocation_reason='synthetic_lost_reply_replacement' WHERE id=?").bind(old.session_id).run();});
 const unknown=await s.write(s.body,s.session,{'X-Test-Pause':'lost_reply'});assert.notEqual(unknown.status,200,'the initial caller did not receive a committed acknowledgement');assert.equal(await rowCount(s.f.db,'support_requests'),1);
 const replacement=await replacementSignIn(s),received=await s.read(s.query,replacement);assert.equal(received.status,200,JSON.stringify(received));assert.equal(received.body.status,'received');assert.equal(received.body.id,s.body.p_request_id);
 assert.equal((await s.write(s.body,replacement)).status,409);assert.equal(await rowCount(s.f.db,'support_requests'),1);for(const table of ['payments','ledger_entries','notification_events'])assert.equal(await rowCount(s.f.db,table),0);
});

test('authoritative absent read permits the same original UUID/body to first commit under replacement sign-in; late original replay remains fenced',async t=>{
 const s=await setup(t),replacement=await replacementSignIn(s),absent=await s.read(s.query,replacement);assert.equal(absent.status,200);assert.equal(absent.body.status,'absent');
 const accepted=await s.write(s.body,replacement);assert.equal(accepted.status,200,JSON.stringify(accepted));assert.deepEqual((await s.read(s.query,replacement)).body,accepted.body);
 assert.equal((await s.write()).status,409);assert.equal(await rowCount(s.f.db,'support_requests'),1);assert.equal((await s.f.db.prepare('SELECT session_id FROM request_receipts WHERE user_id=? AND request_id=?').bind(s.member.id,s.body.p_request_id).first()).session_id,claims(replacement).session_id);
});

test('request read scopes actor, intent and group, hides foreign request existence, and fails closed on own conflicting identity',async t=>{
 const s=await setup(t);assert.equal((await s.write()).status,200);const other=await s.f.nativeLogin('+250788654321');
 const foreign=await s.read(s.query,other);assert.equal(foreign.status,404,JSON.stringify(foreign));assert.equal(foreign.body.id,undefined);assert.equal((await s.read({...s.query,p_intent_id:randomUUID()})).status,404);assert.equal((await s.read({...s.query,p_collection_id:randomUUID()})).status,404);
 const foreignRequest=randomUUID();await s.f.db.prepare("INSERT INTO support_requests(id,user_id,collection_id,kind,message,created_at) VALUES(?,?,?,'payment_review',?,?)").bind(foreignRequest,claims(other).sub,s.collectionId,JSON.stringify({contract_version:1,intent_id:s.intent.id,collection_id:s.collectionId,provider_reference:'FOREIGN_PRIVATE_CANARY',evidence_note:'FOREIGN_PRIVATE_NOTE'}),new Date().toISOString()).run();
 const hidden=await s.read({...s.query,p_request_id:foreignRequest});assert.equal(hidden.status,200);assert.equal(hidden.body.status,'absent');assert.ok(!JSON.stringify(hidden.body).includes('FOREIGN_PRIVATE'));
 const firstIntent=await s.f.db.prepare('SELECT * FROM payment_intents WHERE id=?').bind(s.intent.id).first(),anotherIntent=randomUUID();await s.f.db.prepare('INSERT INTO payment_intents('+Object.keys(firstIntent).join(',')+') VALUES('+Object.keys(firstIntent).map(()=>'?').join(',')+')').bind(...Object.values({...firstIntent,id:anotherIntent,request_id:randomUUID()})).run();
 const mismatch=await s.read({...s.query,p_intent_id:anotherIntent});assert.equal(mismatch.status,409);assert.equal(mismatch.body.id,undefined);
 const requestId=randomUUID();assert.equal((await s.write({p_request_id:requestId,p_kind:'support',p_message:'SYNTHETIC unrelated support request'})).status,200);const collision=await s.read({...s.query,p_request_id:requestId});assert.equal(collision.status,409);assert.equal(collision.body.id,undefined);
 for(const data of [{...s.query,p_user_id:s.member.id},{...s.query,p_session_id:claims(s.session).session_id},{...s.query,p_note:'ignored fields must never be accepted'}, {...s.query,p_request_id:'not-a-uuid'}])assert.equal((await s.read(data)).status,400);
});

for(const changed of ['session_revoked','session_expired','user_suspended','membership_inactive','group_suspended','intent_owner_changed'])test('request reconciliation checks current '+changed+' in the same read batch',async t=>{
 const s=await setup(t);assert.equal((await s.write()).status,200);const original=await financialRows(s.f.db),a=actor(s.session);let changedOnce=false;
 if(changed==='session_expired'){const stamp=Math.floor(Date.now()/1000);a.sessionId=randomUUID();await s.f.db.prepare("INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(?,?,'member',?,?,?)").bind(a.sessionId,a.userId,stamp-10,stamp-10,stamp+1).run();}
 const db={prepare:q=>s.f.db.prepare(q),batch:async statements=>{if(!changedOnce){changedOnce=true;switch(changed){
  case 'session_revoked':await s.f.db.prepare("UPDATE auth_sessions SET revoked_at=unixepoch(),revocation_reason='synthetic_lookup_revocation' WHERE id=?").bind(a.sessionId).run();break;
  case 'session_expired':await new Promise(resolve=>setTimeout(resolve,2100));break;
  case 'user_suspended':await s.f.db.prepare("UPDATE users SET access_status='suspended' WHERE id=?").bind(a.userId).run();break;
  case 'membership_inactive':await s.f.db.prepare('UPDATE memberships SET active=0 WHERE user_id=? AND collection_id=?').bind(a.userId,s.collectionId).run();break;
  case 'group_suspended':await s.f.db.prepare("UPDATE collections SET status='suspended' WHERE id=?").bind(s.collectionId).run();break;
  case 'intent_owner_changed':{const other=await s.f.seedMember({phone:'+250788654321'});await s.f.db.prepare('UPDATE payment_intents SET member_id=? WHERE id=?').bind(other.id,s.intent.id).run();break;}
 }}return s.f.db.batch(statements);}};
 await assert.rejects(notificationRpc(operation,s.query,{DB:db},a),error=>error.status===(changed.startsWith('session_')||changed==='user_suspended'?403:404));
 assert.deepEqual(await financialRows(s.f.db),original);assert.equal(await rowCount(s.f.db,'mutation_guards'),0);assert.equal(await rowCount(s.f.db,'momo_processing_guards'),0);
});

test('missing or corrupt retained support state and unknown D1 outcomes never become an absent acknowledgement',async t=>{
 const s=await setup(t);assert.equal((await s.write()).status,200);await s.f.db.prepare('DELETE FROM support_requests WHERE id=?').bind(s.body.p_request_id).run();const missing=await s.read();assert.equal(missing.status,503);assert.equal(missing.body.id,undefined);
 await s.f.db.prepare("INSERT INTO support_requests(id,user_id,collection_id,kind,message,created_at) VALUES(?,?,?,'payment_review','not-json',?)").bind(s.body.p_request_id,s.member.id,s.collectionId,new Date().toISOString()).run();const corrupt=await s.read();assert.equal(corrupt.status,503);assert.equal(corrupt.body.id,undefined);
 const sourceOnly=randomUUID();await s.f.db.prepare("INSERT INTO support_requests(id,user_id,collection_id,kind,message,created_at) VALUES(?,?,?,'payment_review',?,?)").bind(sourceOnly,s.member.id,s.collectionId,JSON.stringify({contract_version:1,intent_id:s.intent.id,collection_id:s.collectionId}),new Date().toISOString()).run();assert.equal((await s.read({...s.query,p_request_id:sourceOnly})).status,503);
 for(const failure of ['before','after']){const db={prepare:q=>s.f.db.prepare(q),batch:async statements=>{if(failure==='after')await s.f.db.batch(statements);throw new Error('SYNTHETIC_PRIVATE_DATABASE_DIAGNOSTIC');}};await assert.rejects(notificationRpc(operation,{...s.query,p_request_id:randomUUID()},{DB:db},actor(s.session)),error=>error.status===503&&error.code==='payment_review_status_unavailable'&&!error.message.includes('SYNTHETIC_PRIVATE_DATABASE_DIAGNOSTIC'));}
 for(const table of ['payments','ledger_entries','notification_events'])assert.equal(await rowCount(s.f.db,table),0);
});

test('an original request already in flight cannot duplicate a replacement retry after an absent read',async t=>{
 const s=await setup(t);let ready,release;const reached=new Promise(resolve=>{ready=resolve;}),hold=new Promise(resolve=>{release=resolve;});t.after(()=>release());
 s.f.setGate(async event=>{assert.equal(event.phase,'before_commit');ready();await hold;});
 const original=s.write(s.body,s.session,{'X-Test-Pause':'before_commit'});await reached;
 try{
  const replacement=await replacementSignIn(s),absent=await s.read(s.query,replacement);assert.equal(absent.status,200,JSON.stringify(absent));assert.equal(absent.body.status,'absent');
  const accepted=await s.write(s.body,replacement);assert.equal(accepted.status,200,JSON.stringify(accepted));release();assert.equal((await original).status,409);
  assert.deepEqual((await s.read(s.query,replacement)).body,accepted.body);assert.equal(await rowCount(s.f.db,'support_requests'),1);assert.equal((await s.f.db.prepare("SELECT count(*) AS n FROM request_receipts WHERE operation='create_mobile_support_request'").first()).n,1);
  for(const table of ['payments','ledger_entries','notification_events'])assert.equal(await rowCount(s.f.db,table),0);
 }finally{release();await original;}
});

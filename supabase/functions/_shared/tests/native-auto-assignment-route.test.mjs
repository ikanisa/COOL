// Synthetic Admin route / SQL integration: no real provider, account or data.
import {registerHooks} from 'node:module';
import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';

registerHooks({resolve(specifier,context,next){
 if(context.parentURL?.endsWith('/domain/admin_momo.js')&&specifier==='./admin_accounts.js')
  return {url:'data:text/javascript,'+encodeURIComponent(`export const accountDatabase=env=>env;export async function adminAccountSession(){}`),shortCircuit:true};
 if(context.parentURL?.endsWith('/domain/admin_momo.js')&&specifier==='./mutations.js')
  return {url:'data:text/javascript,'+encodeURIComponent(`export async function retainedResponse(){return {found:false};}
   export async function mutation(env,actor,operation,rid,source,value,writes){return globalThis.__nativeRouteMutation(operation,value,writes);}`),shortCircuit:true};
 return next(specifier,context);
}});
const {adminMomoRoute}=await import('../domain/admin_momo.js');
const managed='11111111-1111-4111-8111-111111111111',native='22222222-2222-4222-8222-222222222222',
 group='33333333-3333-4333-8333-333333333333',member='44444444-4444-4444-8444-444444444444',
 conflict='55555555-5555-4555-8555-555555555555';

function fixture(flag){
 const sqlite=new DatabaseSync(':memory:');sqlite.exec(`
  CREATE TABLE momo_transactions(id TEXT PRIMARY KEY,parse_attempt_id TEXT,version INTEGER,has_conflict INTEGER,event_kind TEXT,allocation_state TEXT,updated_at TEXT);
  CREATE TABLE sms_receipts(id TEXT PRIMARY KEY,originating_session_id TEXT,receiver_hash TEXT,body_sha256 TEXT);
  CREATE TABLE momo_transaction_sources(transaction_id TEXT,raw_sms_id TEXT,parse_attempt_id TEXT,relation TEXT);
  CREATE TABLE collections(id TEXT,status TEXT,revision INTEGER);
  CREATE TABLE memberships(collection_id TEXT,user_id TEXT,revision INTEGER,active INTEGER);
  CREATE TABLE users(id TEXT,revision INTEGER,full_name TEXT,access_status TEXT);
  CREATE TABLE momo_financial_links(transaction_id TEXT);
  CREATE TABLE momo_processing_guards(id TEXT PRIMARY KEY,passed INTEGER CHECK(passed=1));
  CREATE TABLE momo_processing_jobs(raw_sms_id TEXT,state TEXT,last_error TEXT,updated_at TEXT);
  CREATE TABLE momo_parse_attempts(id TEXT,raw_sms_id TEXT,attempt_number INTEGER,outcome TEXT,source_body_sha256 TEXT);
  INSERT INTO momo_transactions VALUES('${managed}','managed-attempt',1,0,'incoming_receipt','unallocated',NULL),('${native}','native-attempt',1,0,'incoming_receipt','unallocated',NULL);
  INSERT INTO sms_receipts VALUES('managed-source','managed-session','managed-receiver','managed-hash'),('native-source',NULL,NULL,'native-hash');
  INSERT INTO momo_parse_attempts VALUES('managed-attempt','managed-source',1,'accepted','managed-hash'),('native-attempt','native-source',1,'accepted','native-hash');
  INSERT INTO momo_transaction_sources VALUES('${managed}','managed-source','managed-attempt','accepted'),('${native}','native-source','native-attempt','accepted');`);
 let storageCalls=0,mutationCalls=0,beforeMutation=null;
 const env={BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:flag,PRIVATE_MEDIA:{put(){storageCalls++;throw Error('unexpected storage');}},
  DB:{prepare(sql){return {bind(...args){return {sql,args,first:async()=>sqlite.prepare(sql).get(...args),
   all:async()=>({results:sqlite.prepare(sql).all(...args)})}}}}}};
 const account={principal_id:member},actor={userId:member,permissions:new Set(['payments.read','payments.write','sms.extract'])};
 globalThis.__nativeRouteMutation=async(operation,value,writes)=>{
  mutationCalls++;if(beforeMutation)beforeMutation();sqlite.exec('BEGIN');
  try{for(const s of writes)sqlite.prepare(s.sql).run(...s.args);sqlite.exec('COMMIT');return value;}
  catch(error){sqlite.exec('ROLLBACK');throw error;}
 };
 async function assign(id){
  const url=new URL('https://admin.example.invalid/api/admin/momo/transactions/'+id+'/assign');
  const request=new Request(url,{method:'POST',headers:{'content-type':'application/json','Idempotency-Key':'synthetic-request-1'},
   body:JSON.stringify({group_id:group,member_id:member,expected_version:1,reason:'Synthetic route test'})});
  return adminMomoRoute(request,env,account,actor,['transactions',id,'assign'],url);
 }
 async function review(id){
  const url=new URL('https://admin.example.invalid/api/admin/momo/transactions/'+id+'/review-conflict');
  const request=new Request(url,{method:'POST',headers:{'content-type':'application/json','Idempotency-Key':'synthetic-review-1'},
   body:JSON.stringify({expected_version:1,expected_conflicting_attempt_ids:[conflict],decision:'retain_original',
    evidence_reference:'Synthetic evidence',reason:'Synthetic route test'})});
  return adminMomoRoute(request,env,account,actor,['transactions',id,'review-conflict'],url);
 }
 return {sqlite,assign,review,get storageCalls(){return storageCalls;},get mutationCalls(){return mutationCalls;},
  set beforeMutation(fn){beforeMutation=fn;}};
}

for(const flag of ['true','false'])test(`native cannot enter legacy assignment with feature flag ${flag}`,async()=>{
 const f=fixture(flag);
 try{
  await assert.rejects(f.assign(native),error=>error.status===404&&error.code==='not_found');
  assert.equal(f.storageCalls,0);
  // A genuine managed source reaches the existing destination check, rather
  // than being rejected by the new native-provenance boundary.
  await assert.rejects(f.assign(managed),error=>error.status===409&&error.code==='destination_unavailable');
  assert.equal(f.storageCalls,0);
 }finally{f.sqlite.close();}
});

for(const flag of ['true','false'])test(`legacy conflict review requires a managed accepted source with feature flag ${flag}`,async()=>{
 const f=fixture(flag);
 try{
  f.sqlite.exec(`UPDATE momo_transactions SET has_conflict=1,allocation_state='needs_review';
   INSERT INTO momo_transaction_sources VALUES('${managed}','managed-conflict','${conflict}','conflict'),
    ('${native}','native-conflict','${conflict}','conflict');`);
  await assert.rejects(f.review(native),error=>error.status===409&&error.code==='conflict_changed');
  assert.equal(f.mutationCalls,0);
  const response=await f.review(managed),body=await response.json();
  assert.equal(body.status,'needs_allocation');
  assert.equal(f.mutationCalls,1);
  const managedAfter=f.sqlite.prepare('SELECT has_conflict,allocation_state FROM momo_transactions WHERE id=?').get(managed);
  assert.equal(managedAfter.has_conflict,0);
  assert.equal(managedAfter.allocation_state,'unallocated');
  const nativeAfter=f.sqlite.prepare('SELECT has_conflict,allocation_state FROM momo_transactions WHERE id=?').get(native);
  assert.equal(nativeAfter.has_conflict,1);
  assert.equal(nativeAfter.allocation_state,'needs_review');
 }finally{f.sqlite.close();}
});

test('managed source lost before conflict mutation fails the in-transaction guard',async()=>{
 const f=fixture('true');
 try{
  f.sqlite.exec(`UPDATE momo_transactions SET has_conflict=1,allocation_state='needs_review' WHERE id='${managed}';
   INSERT INTO momo_transaction_sources VALUES('${managed}','managed-conflict','${conflict}','conflict');`);
  f.beforeMutation=()=>f.sqlite.prepare('UPDATE sms_receipts SET originating_session_id=NULL,receiver_hash=NULL WHERE id=?').run('managed-source');
  await assert.rejects(f.review(managed),/CHECK constraint failed/);
  const after=f.sqlite.prepare('SELECT has_conflict,allocation_state FROM momo_transactions WHERE id=?').get(managed);
  assert.equal(after.has_conflict,1);
  assert.equal(after.allocation_state,'needs_review');
 }finally{f.sqlite.close();}
});

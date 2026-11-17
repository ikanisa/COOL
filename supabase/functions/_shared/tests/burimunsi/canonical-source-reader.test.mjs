// Protected Storage.get/transport/protocol and AES-GCM execute here. PostgreSQL
// source/LATERAL, BFF identity and mutation guards are explicitly doubled; the
// retained native-PG fixture separately qualifies shipping SQL and permissions.
import test from 'node:test';
import assert from 'node:assert/strict';
import {storageWitnessFixture} from './storage-witness-fixture.mjs';
import {PostgresCollectSourceReader,NATIVE_SOURCE_SQL,NATIVE_CURRENT_BINDING_SQL,NATIVE_METADATA_AUTH_SQL} from '../../domain/burimunsi/postgres-source-reader.js';
import {RecordsService} from '../../domain/burimunsi/records-service.js';
import {ScopedCursor} from '../../domain/burimunsi/cursor.js';

const uuid=n=>'11111111-1111-4111-8111-'+String(n).padStart(12,'0');
async function readerFixture(sourceBody=undefined){
 const f=await storageWitnessFixture('exception',sourceBody),{state,sqlite,sql,db,authority}=f;
 const raw=sqlite.prepare('SELECT * FROM app.sms_receipts').get();
 Object.assign(state,{actor:{id:uuid(11),sessionId:uuid(12),principalUserId:'principal-1',principalSessionId:uuid(13),
  groupId:authority.groupId,role:'admin',capabilities:['records.read','sms.read'],active:true,revoked:false,
  installationId:uuid(14),installationProfile:'internal_receiver',expiresAt:state.now+100000},
  binding:{id:'current-binding',version:3,status:'active',installation_id:uuid(14),revoked_at:null,enabled:true,binding_version:3},
  source:{...raw,collection_id:authority.groupId,receiving_account_id:'wallet-1',status:'received',
   evidence_level:'client_received',created_at:'2026-11-07T08:00:01.000Z',received_at_device:'2026-11-07 08:00:00',
   association:JSON.parse(JSON.stringify(sqlite.prepare('SELECT * FROM private.burimunsi_sms_source_scopes').get())),
   duplicate:false,transaction_id:null,link_identities:[],storage_state:'committed',delete_tombstone:false,
   upload_unresolved:false,active_attempt:null},audits:[],guards:[],sharedRead:true,sharedReveal:true,commitPhase:0});
 const query=sql.unsafe;
 sql.unsafe=async(text,values=[])=>{
  if(text===NATIVE_METADATA_AUTH_SQL)return state.sharedRead?[{principal_user_id:state.actor.principalUserId,
   principal_session_id:state.actor.principalSessionId}]:[];
  if(text===NATIVE_CURRENT_BINDING_SQL)return state.binding?[structuredClone(state.binding)]:[];
  if(text.startsWith('WITH canonical AS MATERIALIZED'))return [{principal_user_id:state.actor.principalUserId,
   principal_session_id:state.actor.principalSessionId,session_user_id:state.actor.principalUserId,
   surface:'admin',expires_at:Math.floor((state.now+100000)/1000),revoked_at:null,mfa_at:null,now_ms:String(state.now)}];
  if(text.includes(NATIVE_SOURCE_SQL)){
   const selected=state.source&&!text.includes(' AND false')?[structuredClone(state.source)]:[];
   if(text.startsWith('SELECT count(*)'))return [{total:selected.length}];
   return selected;
  }
  return query(text,values);
 };
 authority.session=async()=>structuredClone(state.actor);
 db.prepare=text=>({text,bind(...values){return {text,values};}});
 db.statement=async(_sql,statement)=>{
  if(statement.text.startsWith('INSERT INTO app.mutation_guards')){
   const permission=statement.values[5];
   if(permission==='sms.read'&&!state.sharedRead||permission==='sms.reveal'&&!state.sharedReveal)throw Error('permission_required');
   state.guards.push(permission);
  }else if(statement.text.includes('INSERT INTO audit_log'))state.audits.push(statement.values);
  return {success:true,meta:{changes:1}};
 };
 const write=authority.write.bind(authority);
 authority.write=async fn=>{state.commitPhase++;return write(fn);};
 const reader=new PostgresCollectSourceReader({authority,custody:f.custody,storageWitnesses:f.storageWitnesses,clock:()=>state.now});
 const selector={id:state.actor.id,sessionId:state.actor.sessionId};
 const request={groupId:authority.groupId,id:raw.id,reason:'Investigate the retained source receipt',requestId:uuid(15)};
 return {...f,reader,selector,request,reveal:()=>reader.revealSms(selector,request)};
}
test('metadata contains no decrypted sender or excerpt and server upload time stays distinct',async t=>{
 const f=await readerFixture();t.after(()=>f.close());
 const result=await f.reader.page(f.sql,{groupId:f.authority.groupId,kind:'sms',q:'',filter:'all',limit:40},f.state.actor);
 assert.deepEqual(result.items,[{id:'raw-1',groupId:f.authority.groupId,sender:'',preview:'',
  at:'2026-11-07T08:00:01.000Z',state:'synced',transactionId:null}]);
 assert.equal(f.state.storageCalls.length,0);assert.equal(f.state.audits.length,0);
});
test('server-retained receipts do not invent an awaiting-upload queue',async t=>{
 const f=await readerFixture();t.after(()=>f.close());
 const result=await f.reader.page(f.sql,{groupId:f.authority.groupId,kind:'sms',q:'',filter:'queued',limit:40},f.state.actor);
 assert.equal(result.totalCount,0);assert.deepEqual(result.items,[]);
});
test('full-query SMS metadata snapshots never decrypt or expose body search data',async t=>{
 const f=await readerFixture();t.after(()=>f.close());
 const result=await f.reader.listingSnapshot(f.sql,f.authority.groupId,f.state.actor);
 assert.equal(result.entries.length,1);assert.equal(result.entries[0].search,'raw-1');
 assert.equal(result.entries[0].item.preview,'');assert.equal(result.entries[0].item.sender,'');
 assert.equal(Object.hasOwn(result.entries[0].item,'rawBody'),false);
 assert.equal(f.state.storageCalls.length,0);assert.equal(f.state.audits.length,0);
 f.state.sharedRead=false;
 await assert.rejects(f.reader.listingSnapshot(f.sql,f.authority.groupId,f.state.actor),/access_denied/);
});
test('explicit reveal reads protected scrubbed source outside SQL and audits before returning',async t=>{
 const f=await readerFixture();t.after(()=>f.close());
 assert.equal(f.sqlite.prepare("SELECT sealed_body FROM private.storage_payload_reservations WHERE object_key='sms/raw-1'").get().sealed_body,null);
 const result=await f.reveal();assert.equal(result.sender,'M-Money');assert.match(result.rawBody,/FT100/);
 assert.equal(f.state.commitPhase,2);assert.equal(f.state.audits.length,1);
 assert.equal(f.state.audits[0][2],'sms.capture.revealed');assert.equal(f.state.audits[0][5],f.request.requestId);
 assert.equal(JSON.parse(f.state.audits[0][6]).reason,f.request.reason);
 assert.ok(f.state.storageCalls.some(c=>c.method==='GET'));
 assert.equal(JSON.stringify(f.state.audits).includes(result.rawBody),false);
 assert.throws(()=>f.reader.detail(),/review_reason_required/);
});
test('a replaced current receiver can inspect a source associated with its original receiver',async t=>{
 const f=await readerFixture();t.after(()=>f.close());
 assert.notEqual(f.state.binding.id,f.state.source.association.binding_id);
 assert.equal((await f.reveal()).id,'raw-1');
});
for(const [name,change] of [
 ['native revocation',f=>f.state.actor.revoked=true],
 ['native role',f=>f.state.actor.role='staff'],
 ['installation',f=>f.state.actor.installationId=uuid(99)],
 ['parent session',f=>f.state.actor.principalSessionId=uuid(99)],
 ['global read permission',f=>f.state.sharedRead=false],
 ['global reveal permission',f=>f.state.sharedReveal=false],
 ['source group',f=>f.state.source.collection_id='other-group'],
 ['original source association',f=>f.state.source.association.proof_sha256='d'.repeat(64)],
 ['raw source identity',f=>f.state.source.body_sha256='e'.repeat(64)],
 ['namespace',f=>f.sqlite.prepare("UPDATE private.storage_namespace SET bucket='other'").run()],
 ['delete barrier',f=>f.sqlite.prepare("INSERT INTO private.storage_delete_intents VALUES('sms/raw-1','delete')").run()],
 ['retention barrier',f=>f.sqlite.prepare('INSERT INTO app.privacy_retention_barriers VALUES(?)').run(f.state.source.owner_user_id)],
 ['journal upload unknown',f=>f.sqlite.prepare("UPDATE private.storage_put_intents SET upload_unresolved=1 WHERE object_key='sms/raw-1'").run()],
 ['application epoch',f=>f.state.tuple[1]++],
 ['application source',f=>f.state.tuple[2]='b'.repeat(64)]
])test('in-flight reveal refuses '+name+' change',async t=>{
 const f=await readerFixture();t.after(()=>f.close());let once=false;
 f.state.onStorage=()=>{if(!once){once=true;change(f);}};
 await assert.rejects(f.reveal());assert.equal(f.state.audits.length,0);
});
test('unknown audit COMMIT returns no plaintext success and leaves no reusable disclosure',async t=>{
 const f=await readerFixture();t.after(()=>f.close());const write=f.authority.write.bind(f.authority);
 f.authority.write=async fn=>{const result=await write(fn);if(f.state.commitPhase===2)throw Error('synthetic lost COMMIT reply');return result;};
 await assert.rejects(f.reveal(),/lost COMMIT/);assert.equal(f.state.audits.length,1);
 // The operator must explicitly request another disclosure; no cached result is returned.
 f.state.actor.revoked=true;await assert.rejects(f.reveal(),/session_unavailable/);
});
test('a failed audit prevents plaintext success',async t=>{
 const f=await readerFixture();t.after(()=>f.close());const statement=f.db.statement;
 f.db.statement=async(sql,s)=>{if(s.text.includes('INSERT INTO audit_log'))throw Error('synthetic audit failure');return statement(sql,s);};
 await assert.rejects(f.reveal(),/audit failure/);
});
test('ciphertext corruption and body/object hash disagreement never audit or disclose',async t=>{
 const f=await readerFixture();t.after(()=>f.close());f.remote.get('sms/raw-1')[0]^=1;
 await assert.rejects(f.reveal());assert.equal(f.state.audits.length,0);
});
test('SMS revision changes for a new duplicate relation and source status',async t=>{
 const f=await readerFixture();t.after(()=>f.close());const first=await f.reader.revision(f.sql,f.authority.groupId,f.state.actor);
 f.state.source.duplicate=true;f.state.source.link_identities=[['transaction-1','parse-2','duplicate']];
 const second=await f.reader.revision(f.sql,f.authority.groupId,f.state.actor);assert.notEqual(first,second);
 f.state.source.status='rejected';assert.notEqual(second,await f.reader.revision(f.sql,f.authority.groupId,f.state.actor));
});
test('removed global SMS read permission denies metadata and counts without writing guards',async t=>{
 const f=await readerFixture();t.after(()=>f.close());f.state.sharedRead=false;
 await assert.rejects(f.reader.revision(f.sql,f.authority.groupId,f.state.actor),/access_denied/);
 await assert.rejects(f.reader.page(f.sql,{groupId:f.authority.groupId,kind:'sms',q:'',filter:'all',limit:40},f.state.actor),/access_denied/);
 assert.equal(f.state.guards.length,0);assert.equal(f.state.storageCalls.length,0);assert.equal(f.state.audits.length,0);
});
test('unreasoned RecordsService SMS detail never calls the raw reader',async()=>{
 let called=false;const actor={id:uuid(11),sessionId:uuid(12),groupId:'group-1',active:true,expiresAt:2000,
  role:'admin',capabilities:['sms.read'],installationId:uuid(14),installationProfile:'internal_receiver'};
 const service=new RecordsService({groupId:'group-1',clock:()=>1000,cursor:new ScopedCursor(new Uint8Array(32).fill(1)),
  store:{withReadSnapshot:fn=>fn({reloadActor:()=>actor,loadBinding:()=>({groupId:'group-1',active:true,installationId:uuid(14)}),
   readDetail:()=>{called=true;return {};}})}});
 await assert.rejects(service.detail(actor,'sms','raw-1'),/review_reason_required/);assert.equal(called,false);
});
for(const reason of ['', 'short', 'eight\ncharacters', 'review \u0085 source', 'x'.repeat(1001)])
 test('invalid disclosure reason is rejected before SQL or storage '+JSON.stringify(reason).slice(0,32),async t=>{
  const f=await readerFixture();t.after(()=>f.close());f.request.reason=reason;await assert.rejects(f.reveal(),/review_reason_required/);
  assert.equal(f.state.commitPhase,0);assert.equal(f.state.storageCalls.length,0);
 });
test('reason length uses Unicode code points',async t=>{
 const f=await readerFixture();t.after(()=>f.close());f.request.reason='📩'.repeat(8);await f.reveal();
 assert.equal(JSON.parse(f.state.audits[0][6]).reason,f.request.reason);
});
test('all 16384 UTF-8 bytes allowed by canonical capture can be disclosed unchanged',async t=>{
 const body='A'.repeat(16384),f=await readerFixture(body);t.after(()=>f.close());
 assert.equal((await f.reveal()).rawBody,body);
});
test('source body beyond canonical byte limit is refused without an audit',async t=>{
 const f=await readerFixture('é'.repeat(8193));t.after(()=>f.close());
 await assert.rejects(f.reveal(),/source_integrity_failed/);assert.equal(f.state.audits.length,0);
});

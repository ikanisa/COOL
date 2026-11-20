// Production adapters + pinned Collect AES-GCM on synthetic fixtures.
// SQL/locking are recorded, NOT executed against PostgreSQL or production data.
import test from 'node:test';import assert from 'node:assert/strict';
import {custodyFixture,namespace} from './posting-custody-fixture.mjs';
import {PostgresRetainedSources,RETAINED_SOURCE_SQL} from '../../domain/burimunsi/postgres-retained-sources.js';
import {PostgresCanonicalAdoption} from '../../domain/burimunsi/postgres-canonical-adoption.js';
import {parseReceipt,receiptFingerprint,transactionKey} from '../../domain/burimunsi/receipt.js';
const body='You have received 12,500 RWF from EXAMPLE PAYER (0780000001) at 2026-11-07 10:00:00. Balance: 30,000 RWF. FT Id: 123456.';
const profile={version:'profile-v1',offsetMinutes:120,senders:['M-Money']};
async function fixture(){const f=await custodyFixture({body}),r=f.state.row;
 const lineage={id:r.raw_sms_id,owner_user_id:r.raw_owner,object_key:r.raw_key,object_sha256:r.raw_sha256,size_bytes:r.raw_size,
 body_sha256:r.body_sha256,receiver_hash:r.receiver_hash,credential_id:r.credential_id,identity_sha256:r.identity_sha256,
 completeness:r.completeness,source_mode:r.source_mode,subscription_id:r.subscription_id,binding_id:r.job_binding,
 job_binding_version:r.job_binding_version,receiving_account_id:r.job_account,job_mode:r.job_mode,job_state:r.job_state,last_error:r.job_error,
 binding_owner:r.binding_owner,binding_version:r.binding_version,binding_status:r.binding_status,subscription_evidence:r.subscription_evidence,
 credential_revoked:r.credential_revoked,credential_binding:r.credential_binding,public_code:r.public_code,wallet_hash:r.wallet_hash,
 wallet_status:r.wallet_status,profile_status:r.profile_status,profile_version:r.profile_version,collection_id:r.collection_id,
 active_binding_id:r.job_binding,scope_binding_version:r.binding_version};
 const original=f.sql.unsafe;f.sql.unsafe=async(q,v)=>{if(q===RETAINED_SOURCE_SQL){f.state.queries.push({text:q,values:v});return [structuredClone(lineage)];}return original(q,v);};
 const sources=new PostgresRetainedSources({qualificationOnly:true,db:f.db,groupId:'group-1',namespace,decrypt:f.verifier.decrypt});
 const job=await sources.sourceForEnqueue(f.sql,'raw-1');
 return {...f,lineage,sources,job,load:()=>sources.load(f.sql,job)};
}
test('retained source decrypts under original journal custody/AAD',async()=>{const f=await fixture(),s=await f.load();assert.equal(s.body,body);assert.equal(s.sender,'M-Money');assert.equal(s.complete,true);
 assert.equal(s.subscriptionId,7);assert(f.state.queries.some(x=>x.text.includes('privacy_retention_barriers')));assert(Object.isFrozen(s));
});
for(const [field,value]of [['credential_revoked',1],['binding_status','revoked'],['active_binding_id','replacement'],['scope_binding_version',3],
 ['job_binding_version',3],['wallet_status','disabled'],['profile_status','unverified'],['source_mode','historical'],['job_mode','historical'],
 ['job_state','processing'],['last_error','momo_v2:provider_outcome_unknown'],['completeness','incomplete'],['owner_user_id','other'],
 ['receiver_hash','f'.repeat(64)],['object_key','arbitrary/key'],['subscription_id',8],['subscription_evidence','{"subscription_id":8}'],
 ['identity_sha256','f'.repeat(64)],['body_sha256','e'.repeat(64)],['public_code','not-a-route']])test('source rejects '+field,async()=>{
 const f=await fixture();f.lineage[field]=value;await assert.rejects(f.load(),e=>['source_unavailable','source_scope_changed'].includes(e.code)&&!e.message.includes(body));
});
test('retention barrier blocks source decryption',async()=>{const f=await fixture();f.state.barriers.push(f.lineage.owner_user_id);await assert.rejects(f.load(),/source_unavailable/);assert.equal(f.state.decrypts,0);});
test('deletion intent blocks source decryption',async()=>{const f=await fixture();f.state.deletions.push(f.lineage.object_key);await assert.rejects(f.load(),/source_unavailable/);});
test('scrubbed payload never falls back to unaudited bucket bytes',async()=>{const f=await fixture();f.state.journals.get('sms/raw-1').reservation.sealed_body=null;await assert.rejects(f.load(),/source_unavailable/);});
test('lineage changed during decrypt invalidates old source',async()=>{const f=await fixture();f.state.onDecrypt=()=>{f.lineage.binding_version++;};await assert.rejects(f.load());});
test('namespace changed during decrypt invalidates custody',async()=>{const f=await fixture();f.state.onDecrypt=()=>{f.state.namespace.bucket='other';};await assert.rejects(f.load());});
test('ciphertext cannot change while retaining plaintext digest claims',async()=>{const f=await fixture();f.state.journals.get('sms/raw-1').reservation.sealed_body+=' ';await assert.rejects(f.load());});
test('caller source group never grants authority',async()=>{const f=await fixture();await assert.rejects(f.sources.load(f.sql,{...f.job,groupId:'other'}),/source_scope_changed/);});
test('enqueue descriptor comes from completed canonical capture',async()=>{const f=await fixture();assert.equal(await f.sources.assertLineage(f.sql,f.job),true);
 await assert.rejects(f.sources.assertLineage(f.sql,{...f.job,sourceSha256:'a'.repeat(64)}));
});
async function adoptionFixture(){const f=await fixture(),source=await f.load(),receipt=parseReceipt(source,profile);
 const canonical={id:'transaction-1',raw_sms_id:'raw-1',parse_outcome:'accepted',profile_version:profile.version,source_body_sha256:f.job.sourceSha256,
 source_conflict:false,has_conflict:0,mode:'live',event_kind:'incoming_receipt',provider:'mtn_momo',currency:'RWF',provider_transaction_id:receipt.ftId,
 amount_minor:12500,payer_name:receipt.payerNameRaw,payer_identifier:'+250780000001',transaction_at:receipt.at};
 const state={canonical:[canonical],scope:null,outcome:[],queries:[]},original=f.sql.unsafe;
 f.sql.unsafe=async(q,v)=>{state.queries.push({q,v});
  if(q.includes('SELECT t.*,s.raw_sms_id'))return structuredClone(state.canonical);
  if(q.startsWith('INSERT INTO private.burimunsi_transaction_scopes')){state.scope??={transaction_id:v[0],collection_id:v[1],receiving_account_id:v[2],source_binding_id:v[3],source_binding_version:v[4],policy_version:v[5]};return [];}
  if(q.startsWith('SELECT * FROM private.burimunsi_transaction_scopes'))return [structuredClone(state.scope)];
  if(q.includes('SELECT t.id,t.has_conflict'))return structuredClone(state.outcome);
  return original(q,v);};
 const admission={assertInTransaction:async()=>({profile,policyVersion:'policy-1'})};
 const adopter=new PostgresCanonicalAdoption({db:f.db,groupId:'group-1',sources:f.sources,admission});
 const input={job:f.job,source,receipt,key:transactionKey(f.job.receivingAccountId,receipt),fingerprint:await receiptFingerprint(receipt)};
 return {...f,canonical,state,adopter,input,adopt:()=>adopter.ingest(f.sql,input)};
}
test('adopts existing transaction without duplicate payment/ledger writes',async()=>{const f=await adoptionFixture();
 assert.equal((await f.adopt()).transactionId,'transaction-1');assert.equal((await f.adopt()).transactionId,'transaction-1');
 const writes=f.state.queries.filter(x=>/^(INSERT|UPDATE|DELETE)/.test(x.q));assert(writes.every(x=>x.q.startsWith('INSERT INTO private.burimunsi_transaction_scopes')));
});
for(const [field,value]of [['parse_outcome','needs_review'],['source_conflict',true],['has_conflict',1],['mode','historical'],
 ['currency','USD'],['amount_minor',12501],['provider_transaction_id','other'],['payer_name','OTHER PERSON'],['payer_identifier','0780000002'],
 ['profile_version','new'],['source_body_sha256','f'.repeat(64)],['transaction_at','2026-11-07T09:00:00.000Z'],['transaction_at','bad-date']])test('canonical adoption rejects '+field+' '+value,async()=>{
 const f=await adoptionFixture();f.canonical[field]=value;await assert.rejects(f.adopt());assert.equal(f.state.scope,null);
});
for(const count of [0,2])test('adoption refuses '+count+' accepted rows',async()=>{const f=await adoptionFixture();f.state.canonical=count===0?[]:[f.canonical,{...f.canonical}];await assert.rejects(f.adopt(),/canonical_source_not_accepted/);});
test('cross-group preexisting scope cannot be relabelled',async()=>{const f=await adoptionFixture();await f.adopt();f.state.scope.collection_id='another';await assert.rejects(f.adopt(),/source_scope_changed/);assert.equal(f.state.scope.collection_id,'another');});
test('fabricated in-memory parse cannot override source truth',async()=>{const f=await adoptionFixture();f.input.receipt={...f.input.receipt,amountRwf:999};assert.equal((await f.adopt()).transactionId,'transaction-1');});
test('unallocated outcome does not fabricate a credit',async()=>{const f=await adoptionFixture();f.state.outcome=[{id:'transaction-1',has_conflict:0,source_conflict:false,allocation_state:'unallocated',status:null,ledger_entry_id:null,compensated:false}];
 const o=await f.adopter.outcome(f.sql,{groupId:'group-1',transactionId:'transaction-1'});assert.equal(o.state,'unallocated');assert.equal(o.ledgerEntryId,undefined);
});
const posted=()=>({id:'transaction-1',has_conflict:0,source_conflict:false,allocation_state:'linked',payment_group:'group-1',status:'confirmed',ledger_entry_id:'ledger-1',compensated:false,
 transaction_currency:'RWF',payment_currency:'RWF',ledger_currency:'RWF',transaction_amount:12500,payment_amount:12500,ledger_amount:12500,member_id:'member-1',beneficiary_member_id:'member-1'});
test('posted observation requires matching canonical ledger amount and member',async()=>{const f=await adoptionFixture();f.state.outcome=[posted()];
 assert.equal((await f.adopter.outcome(f.sql,{groupId:'group-1',transactionId:'transaction-1'})).ledgerEntryId,'ledger-1');
});
for(const [field,value]of [['status','reversed'],['compensated',true],['source_conflict',true],['ledger_amount',12501],['member_id','other'],['payment_currency','USD']])test('outcome rejects '+field,async()=>{const f=await adoptionFixture();
 f.state.outcome=[{...posted(),[field]:value}];await assert.rejects(f.adopter.outcome(f.sql,{groupId:'group-1',transactionId:'transaction-1'}));
});
test('multiple ledger observations cannot be called posted',async()=>{const f=await adoptionFixture();f.state.outcome=[posted(),posted()];await assert.rejects(f.adopter.outcome(f.sql,{groupId:'group-1',transactionId:'transaction-1'}));});

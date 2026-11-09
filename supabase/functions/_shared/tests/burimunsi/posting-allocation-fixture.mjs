/** TEST ONLY. Actual allocation/custody/posting SQL and AES-GCM on in-memory
 * SQLite. PostgreSQL locks are explicitly stripped. Runtime authorization,
 * verified identities, job admission and journal preparation are SYNTHETIC.
 * Do not install this schema, preparation fixture or runtime bridge in Collect.
 */
import {custodySqliteFixture} from './posting-custody-sqlite-fixture.mjs';
import {encryption,custodyFixture} from './posting-custody-fixture.mjs';
import {ids} from './posting-executor-fixture.mjs';
import {PostgresPostingAllocation} from '../../domain/burimunsi/postgres-posting-allocation.js';
import {postingPreparationIdentity,postingEvidenceDescriptor} from '../../domain/burimunsi/posting-preparation.js';
import {canonicalJson,sha256} from '../../domain/burimunsi/values.js';
import {PostgresCanonicalStore} from '../../domain/burimunsi/postgres-canonical-store.js';
import {ContributionService} from '../../domain/burimunsi/contribution-service.js';
export {ids};
export async function allocationFixture(mode='automatic'){
 const f=await custodySqliteFixture(mode),s=f.sqlite;
 s.exec(`ALTER TABLE private.burimunsi_scopes ADD COLUMN version INTEGER DEFAULT 1;
 ALTER TABLE app.collections ADD COLUMN revision INTEGER DEFAULT 1;
 ALTER TABLE app.collections ADD COLUMN receiver_display_label TEXT DEFAULT 'EXAMPLE WALLET';
 ALTER TABLE app.memberships ADD COLUMN revision INTEGER DEFAULT 1;
 ALTER TABLE app.users ADD COLUMN member_type TEXT DEFAULT 'direct';
 ALTER TABLE app.users ADD COLUMN revision INTEGER DEFAULT 1;
 ALTER TABLE app.momo_transactions ADD COLUMN transaction_at TEXT DEFAULT '2026-11-07T08:00:00.000Z';
 ALTER TABLE app.momo_transactions ADD COLUMN created_at TEXT DEFAULT '2026-11-07T08:00:01.000Z';
 ALTER TABLE app.momo_transactions ADD COLUMN payer_name TEXT DEFAULT 'EXAMPLE PAYER';
 ALTER TABLE app.momo_transactions ADD COLUMN payer_identifier TEXT DEFAULT '+250780000001';
 ALTER TABLE app.payment_evidence ADD COLUMN receiver_display_label TEXT;
 ALTER TABLE app.payment_evidence ADD COLUMN content_type TEXT;
 ALTER TABLE app.payment_evidence ADD COLUMN authenticity TEXT;
 ALTER TABLE app.payment_evidence ADD COLUMN observed_at TEXT;
 ALTER TABLE app.payment_evidence ADD COLUMN created_at TEXT;
 ALTER TABLE app.payments ADD COLUMN payer_display_name TEXT;
 ALTER TABLE app.payments ADD COLUMN created_at TEXT;
 ALTER TABLE app.momo_financial_links ADD COLUMN linked_by TEXT;
 ALTER TABLE app.momo_financial_links ADD COLUMN reason TEXT;
 ALTER TABLE app.momo_financial_links ADD COLUMN created_at TEXT;
 CREATE TABLE private.burimunsi_command_receipts(collection_id TEXT,actor_id TEXT,request_id TEXT,session_id TEXT,
  operation TEXT,fingerprint TEXT,response TEXT,created_at INTEGER,PRIMARY KEY(collection_id,actor_id,request_id));
 DELETE FROM app.payment_evidence; DELETE FROM app.payments;`);
 s.function('clock_timestamp',()=>f.state.clock??'2026-11-07T08:01:00.000Z');
 f.command.member.version=1;
 f.principal=await f.runtime.assertInTransaction(f.sql,{command:f.command,phase:'fixture_preparation'});
 delete f.principal.contractVersion;f.state.phases=[];
 f.identity=await postingPreparationIdentity(f.command,f.principal);
 const oldKey='evidence/'+ids.evidence;
 const old=s.prepare('SELECT * FROM private.storage_payload_reservations WHERE object_key=?').get(oldKey);
 const body=await f.custody.decrypt(old.sealed_body,old.aad);
 // This is synthetic preparation, NOT the missing production network preflight.
 const key=old.key_id,env=(await custodyFixture()).env;
 const descriptor=postingEvidenceDescriptor(f.identity,old.plaintext_sha256,key);
 const sourceFingerprint=await sha256(canonicalJson(descriptor));
 const sealed=await encryption.encrypt(env,body,descriptor.aad),cipherHash=await sha256(sealed);
 const custom={...descriptor.customMetadata,source_fingerprint:sourceFingerprint};
 for(const table of ['storage_put_intents','storage_objects']){
  s.prepare(`UPDATE private.${table} SET object_key=?,scope=?,sha256=?,size=?,custom_metadata=? WHERE object_key=?`)
   .run(f.identity.objectKey,JSON.stringify(descriptor.scope),cipherHash,Buffer.byteLength(sealed),JSON.stringify(custom),oldKey);
 }
 s.prepare(`UPDATE private.storage_payload_reservations SET object_key=?,source_fingerprint=?,scope=?,aad=?,sealed_body=? WHERE object_key=?`)
  .run(f.identity.objectKey,sourceFingerprint,JSON.stringify(descriptor.scope),descriptor.aad,sealed,oldKey);
 Object.assign(f.state,{allocationWrites:0,failAllocationAt:-1,failCommandReceipt:false,afterQuery:null,commitReplyLost:false,leaseLost:false});
 const bools=['has_entries','has_snapshot','has_other_reference','has_compensation','enabled','has_link','source_conflict','upload_unresolved','delete_tombstone'];
 const jsons=['scope','http_metadata','custom_metadata','response'];
 f.sql.unsafe=async(text,values=[])=>{
  f.state.queries.push({text,values});
  if(text.startsWith('SELECT pg_advisory'))return [{}]; // Not executed: no PostgreSQL lock proof.
  if(f.state.failCommandReceipt&&text.includes('INSERT INTO private.burimunsi_command_receipts'))throw Error('fixture command receipt failure');
  const allocationWrite=/^(?:INSERT INTO app\.(?:payment_evidence|payments|momo_financial_links)|UPDATE app\.momo_transactions)/.test(text);
  if(allocationWrite&&f.state.allocationWrites++===f.state.failAllocationAt)throw Error('injected allocation write failure');
  const params=[];const compiled=text.replace(/\s+FOR UPDATE(?: OF [\w,]+)?\s*$/,'').replace(/\s+FOR SHARE\s*$/,'')
    .replace(/\$(\d+)(?:::uuid|::jsonb)?/g,(_s,n)=>{const v=values[Number(n)-1];params.push(v&&typeof v==='object'?JSON.stringify(v):v);return '?';});
  const rows=s.prepare(compiled).all(...params).map(row=>{
    const out={...row};for(const k of bools)if(k in out&&out[k]!==null)out[k]=Boolean(out[k]);
    for(const k of jsons)if(k in out&&typeof out[k]==='string')out[k]=JSON.parse(out[k]);return out;
  });
  await f.state.afterQuery?.(text,values,rows);return rows;
 };
 const allocation=new PostgresPostingAllocation({db:f.db,groupId:ids.group,custody:f.custody});
 f.writer.allocation=allocation;
 const runAllocation=async()=>{s.exec('BEGIN');try{const result=await allocation.prepareInTransaction(f.sql,f.command,f.principal);s.exec('COMMIT');return result;}catch(e){s.exec('ROLLBACK');throw e;}};
 return {...f,allocation,descriptor,body:Buffer.from(body).toString('utf8'),runAllocation};
}
export function connectAllocationFlow(f){
 f.actor={id:ids.actor,sessionId:ids.session,principalUserId:ids.otherActor,groupId:ids.group,role:'staff',active:true,
  expiresAt:9999999999999,capabilities:['records.read','payments.allocate','members.enroll']};
 const authority={groupId:ids.group,session:async()=>f.actor,write:async fn=>{
  f.sqlite.exec('BEGIN');let committed=false;
  try{const result=await fn(f.sql);f.sqlite.exec('COMMIT');committed=true;
    if(f.state.commitReplyLost){f.state.commitReplyLost=false;throw Error('lost commit reply');}return result;
  }catch(e){if(!committed)f.sqlite.exec('ROLLBACK');throw e;}
 }};
 f.identities=[{id:'identity-1',memberId:ids.member,groupId:ids.group,status:'verified',authority:'collect_verified',purpose:'own_contributions',
   phone:'+250780000001',validFrom:'2026-01-01T00:00:00.000Z',validUntil:null}];
 const identities={policy:async()=>({groupId:ids.group,approvedVersion:'verified-test-v1',fullIdentityEnabled:true}),
  members:async()=>[{id:ids.member,groupId:ids.group,active:true,eligible:true}],verified:async()=>f.identities};
 const commands={postContribution:(...args)=>f.writer.postContribution(...args),createDirectMember:async()=>{throw Error('not this fixture');},setMembershipActive:async()=>{throw Error('not this fixture');},enqueueEligibleRematch:async()=>{throw Error('not this fixture');}};
 const jobs={assertPostingLease:async()=>{if(f.state.leaseLost)throw Error('lease lost');}};
 f.store=new PostgresCanonicalStore({authority,commands,identities,jobs});f.service=new ContributionService({store:f.store,groupId:ids.group});
 f.allocate=()=>f.service.allocate(f.actor,{transactionId:f.command.receiptId,memberId:ids.member,expectedVersion:3,note:'Verified original source and identity',requestId:ids.request});
 f.auto=()=>f.service.automaticallyAllocate(f.command.receiptId,ids.request,f.command.work);
 return f;
}

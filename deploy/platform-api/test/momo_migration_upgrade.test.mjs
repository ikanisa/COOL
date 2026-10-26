// Local populated-schema rehearsal only. These are synthetic identities and
// evidence on real workerd D1/R2, without provider access or release approval.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {current13Fixture} from './support/recovery13_fixture.mjs';
import {dataKeys,sha} from './support/recovery12_fixture.mjs';
import {quarantineSchemaProfiles} from '../../../scripts/cloudflare/recovery_quarantine.mjs';
import {encrypt} from '../src/encryption.js';

const require=createRequire(import.meta.url);
const {unstable_splitSqlQuery}=require(process.env.COLLECT_WRANGLER_MODULE??'wrangler');
const migrationNames=['0014_momo_pipeline.sql','0015_momo_gateway_allocation.sql'];
const migrations=await Promise.all(migrationNames.map(async name=>{
 const bytes=await readFile(new URL('../migrations/'+name,import.meta.url));
 assert.equal(sha(bytes),quarantineSchemaProfiles.candidate15.digests['migrations/'+name],name+' exact profile');
 return {name,bytes,queries:unstable_splitSqlQuery(bytes.toString())};
}));
const schemaQuery="SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*' AND name NOT IN('_cf_METADATA','_cf_KV') ORDER BY type,name";
const rows=async(db,name)=>(await db.prepare('SELECT * FROM "'+name+'"').all()).results.map(row=>JSON.stringify(row)).sort();
async function snapshot(db){
 const schema=(await db.prepare(schemaQuery).all()).results,contents={};
 for(const {name}of schema.filter(row=>row.type==='table'))contents[name]=await rows(db,name);
 return {schema,contents,sequence:await rows(db,'sqlite_sequence')};
}
async function objects(bucket){
 const page=await bucket.list();assert.equal(page.truncated,false);
 return Object.fromEntries(await Promise.all(page.objects.map(async({key})=>[key,Buffer.from(await(await bucket.get(key)).arrayBuffer()).toString('base64')])));
}
const apply=(db,migration)=>db.batch(migration.queries.map(sql=>db.prepare(sql)));
function assertPreserved(before,after,{mutableTables=[],replacedSchema=[]}={}){
 for(const [name,contents]of Object.entries(before.contents))if(!mutableTables.includes(name))assert.deepEqual(after.contents[name],contents,name+' exact predecessor rows');
 for(const row of before.schema)if(!replacedSchema.includes(row.name))assert.ok(after.schema.some(next=>JSON.stringify(next)===JSON.stringify(row)),row.name+' exact predecessor schema');
 assert.deepEqual(after.sequence,before.sequence,'sqlite_sequence exact predecessor state');
}
async function rawSource(c,label){
 const id=randomUUID(),at=new Date().toISOString(),body=Buffer.from(JSON.stringify({raw_sender:'SYNTHETIC UPGRADE',raw_body:'Retained migration source '+label})),digest=sha(body),key='synthetic-upgrade/'+id;
 const session=await c.f.db.prepare("SELECT id FROM auth_sessions WHERE user_id=? AND surface='admin' AND revoked_at IS NULL ORDER BY created_at DESC LIMIT 1").bind(c.account.userId).first();assert.ok(session);
 await c.bucket.put(key,await encrypt(dataKeys,body,`sms:${id}:${digest}`));
 await c.f.db.prepare('INSERT INTO sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)')
  .bind(id,c.account.userId,session.id,randomUUID(),digest,sha('SYNTHETIC UPGRADE RECEIVER'),key,digest,body.length,at).run();
 return {id,digest,key,at};
}
async function populated13(t){
 const c=await current13Fixture(t),db=c.f.db;
 assert.equal((await db.prepare('SELECT count(*) AS n FROM admin_account_role_capabilities').first()).n,63);
 // Live account and principal status combinations are established before the
 // migration preimage; migration backfill may not revive excluded authority.
 const active=await c.f.seedAccount({email:'upgrade-active@example.test',role:'admin'}),suspended=await c.f.seedAccount({email:'upgrade-suspended@example.test',role:'admin'}),deleted=await c.f.seedAccount({email:'upgrade-deleted@example.test',role:'admin'}),revoked=await c.f.seedAccount({email:'upgrade-revoked@example.test',role:'admin',status:'revoked'}),invited=await c.f.seedAccount({email:'upgrade-invited@example.test',role:'admin',status:'invited'}),staff=await c.f.seedAccount({email:'upgrade-staff@example.test',role:'staff'}),unlinked=await c.f.seedAccount({email:'upgrade-unlinked@example.test',role:'admin',linked:false});
 await db.prepare("UPDATE users SET access_status='suspended' WHERE id=?").bind(suspended.userId).run();
 await db.prepare("UPDATE users SET access_status='deleted' WHERE id=?").bind(deleted.userId).run();
 await db.prepare("INSERT INTO admin_grants(user_id,permission,granted_by,granted_at) VALUES(?,'sms.extract','synthetic-existing-independent-grant','2026-01-01T00:00:00.000Z')").bind(c.account.userId).run();
 const member=await db.prepare('SELECT phone FROM users WHERE id=?').bind(c.recipient).first();assert.ok(member?.phone);
 await db.prepare("UPDATE users SET momo_provider='mtn_momo',momo_number=?,country_code='RW' WHERE id=?").bind(member.phone.replace(/^\+250/,'0'),c.recipient).run();
 await db.prepare("UPDATE collections SET receiver_momo_number=?,receiver_network='mtn_momo',receiver_display_label='SYNTHETIC upgrade receiver' WHERE id=?").bind(member.phone.replace(/^\+/,''),c.smsGroup).run();
 const intents=[];
 for(const amount of [1250,2500]){
  const issued=await c.member(c.phone,'create_contribution_intent',{collection:c.smsGroup,p_expected_amount_rwf:amount,p_request_id:randomUUID()});
  assert.equal(issued.status,200,JSON.stringify(issued));assert.equal(issued.body.status,'pending');assert.ok(Date.parse(issued.body.expires_at)>Date.parse(issued.body.created_at));
  const intent=await db.prepare('SELECT * FROM payment_intents WHERE id=?').bind(issued.body.id).first();assert.equal(intent.member_id,c.recipient);
  const session=await db.prepare("SELECT user_id,surface FROM auth_sessions WHERE id=?").bind(intent.originating_session_id).first();assert.deepEqual(session,{user_id:c.recipient,surface:'member'});intents.push(intent);
 }
 // The predecessor has no uniqueness rule. Associate its already posted1250
 // payment with the actual member-issued1250 intent before taking the preimage.
 await db.prepare('UPDATE payments SET intent_id=? WHERE id=?').bind(intents[0].id,c.payments[0].id).run();
 const sources=[await rawSource(c,'live'),await rawSource(c,'unresolved')];
 assert.equal((await db.prepare('PRAGMA foreign_key_check').all()).results.length,0);
 return {...c,intents,sources,matrix:{active,suspended,deleted,revoked,invited,staff,unlinked}};
}
async function populate14(c){
 const db=c.f.db,account=randomUUID(),binding=randomUUID(),attempt=randomUUID(),transaction=randomUUID(),at=new Date().toISOString(),source=c.sources[0];
 await db.batch([
  db.prepare("INSERT INTO momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,timezone,created_at) VALUES(?,'mtn_momo','SYNTHETIC','SYNTHETIC upgrade account',?,'Africa/Kigali',?)").bind(account,sha('SYNTHETIC UPGRADE RECEIVER'),at),
  db.prepare('INSERT INTO momo_gateway_bindings(id,owner_user_id,receiving_account_id,created_at) VALUES(?,?,?,?)').bind(binding,c.account.userId,account,at),
  db.prepare("INSERT INTO momo_processing_jobs(raw_sms_id,binding_id,binding_version,receiving_account_id,mode,state,available_at,created_at,updated_at) VALUES(?,?,1,?,'live','needs_review',1700000000,?,?)").bind(source.id,binding,account,at,at),
  db.prepare("INSERT INTO momo_processing_jobs(raw_sms_id,mode,state,available_at,created_at,updated_at) VALUES(?,'historical','source_unresolved',1700000000,?,?)").bind(c.sources[1].id,at,at),
  db.prepare("INSERT INTO momo_parse_attempts(id,raw_sms_id,attempt_number,model_id,schema_version,prompt_version,parser_version,profile_version,profile_json,source_body_sha256,output_json,validation_json,outcome,created_at) VALUES(?,?,1,'SYNTHETIC saved parser','momo-extraction.v1','synthetic-v1','synthetic-v1','synthetic-v1','{}',?,NULL,'[]','accepted',?)").bind(attempt,source.id,source.digest,at),
  db.prepare("INSERT INTO momo_transactions(id,receiving_account_id,provider,provider_transaction_id,event_kind,amount_minor,currency,currency_scale,transaction_timezone,transaction_time_source,parse_attempt_id,mode,created_at,updated_at) VALUES(?,?,'mtn_momo','SYNTHETIC-001','incoming_receipt',1250,'RWF',0,'Africa/Kigali','unknown',?,'live',?,?)").bind(transaction,account,attempt,at,at),
  db.prepare("INSERT INTO momo_transaction_sources(transaction_id,raw_sms_id,parse_attempt_id,relation,created_at) VALUES(?,?,?,'accepted',?)").bind(transaction,source.id,attempt,at),
  db.prepare("INSERT INTO momo_processing_guards(id,passed) VALUES('synthetic-upgrade-preserved',1)"),
 ]);
 for(const name of ['momo_receiving_accounts','momo_gateway_bindings','momo_processing_jobs','momo_parse_attempts','momo_transactions','momo_transaction_sources','momo_processing_guards'])assert.ok((await db.prepare('SELECT count(*) AS n FROM '+name).first()).n>0,name+' populated14');
 return {account,binding,attempt,transaction};
}
function clonePayment(db,c,intentId){
 const payment=c.payments[0],evidence=randomUUID(),id=randomUUID();
 return [db.prepare('INSERT INTO payment_evidence SELECT ?,collection_id,owner_user_id,?,object_sha256,size_bytes,content_type,authenticity,NULL,receiver_momo_number,amount_minor,currency,observed_at,created_at,retained_until,legal_hold,receiver_network,receiver_display_label FROM payment_evidence WHERE id=?').bind(evidence,'synthetic-rolled-back-evidence/'+evidence,payment.evidence),
  db.prepare("INSERT INTO payments(id,collection_id,member_id,evidence_id,intent_id,amount_minor,status,created_at) VALUES(?,?,?,?,?,1250,'recorded',?)").bind(id,c.smsGroup,c.recipient,evidence,intentId,new Date().toISOString())];
}

test('exact populated13-to14-to15 preserves predecessor histories and backfills only eligible grants; intent uniqueness keeps null semantics',{timeout:180000},async t=>{
 const c=await populated13(t),db=c.f.db,before13=await snapshot(db),objects13=await objects(c.bucket);
 await apply(db,migrations[0]);const after14=await snapshot(db);assertPreserved(before13,after14);assert.deepEqual(await objects(c.bucket),objects13);
 const populated=await populate14(c),before15=await snapshot(db),objects14=await objects(c.bucket),started=Date.now();
 await assert.rejects(db.prepare('UPDATE momo_processing_jobs SET receiving_account_id=? WHERE raw_sms_id=?').bind(populated.account,c.sources[1].id).run(),/immutable_momo_source/);
 await apply(db,migrations[1]);const after15=await snapshot(db);
 assertPreserved(before15,after15,{mutableTables:['admin_account_role_capabilities','admin_grants'],replacedSchema:['momo_job_source_identity']});
 assert.deepEqual(await objects(c.bucket),objects14);
 const oldDefinitions=before15.contents.admin_account_role_capabilities,newDefinitions=after15.contents.admin_account_role_capabilities;
 assert.ok(oldDefinitions.every(row=>newDefinitions.includes(row)));assert.equal(oldDefinitions.length,63);assert.equal(newDefinitions.length,67);
 assert.deepEqual(newDefinitions.filter(row=>!oldDefinitions.includes(row)).map(row=>JSON.parse(row)).sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b))),[
  {role:'admin',permission:'sms.extract'},{role:'admin',permission:'sms.reveal'},{role:'owner',permission:'sms.extract'},{role:'owner',permission:'sms.reveal'},
 ]);
 const oldGrants=before15.contents.admin_grants,newGrants=after15.contents.admin_grants,added=newGrants.filter(row=>!oldGrants.includes(row)).map(row=>JSON.parse(row));assert.ok(oldGrants.every(row=>newGrants.includes(row)));
 assert.deepEqual(added.map(({user_id,permission,granted_by})=>({user_id,permission,granted_by})).sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b))),[
  {user_id:c.account.userId,permission:'sms.reveal',granted_by:'admin-account:'+c.account.adminId},
  {user_id:c.matrix.active.userId,permission:'sms.extract',granted_by:'admin-account:'+c.matrix.active.adminId},
  {user_id:c.matrix.active.userId,permission:'sms.reveal',granted_by:'admin-account:'+c.matrix.active.adminId},
 ].sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b))));
 for(const grant of added)assert.ok(Date.parse(grant.granted_at)>=started&&Date.parse(grant.granted_at)<=Date.now());
 for(const name of ['momo_gateway_pairings','momo_gateway_credentials','momo_gateway_captures','momo_source_resolutions','momo_financial_links','contribution_posting_snapshots'])assert.deepEqual(after15.contents[name],[],name+' has no automatic effects');
 assert.equal((await db.prepare('SELECT count(*) AS n FROM payments WHERE intent_id=?').bind(c.intents[0].id).first()).n,1);
 assert.ok((await db.prepare('SELECT count(*) AS n FROM payments WHERE intent_id IS NULL').first()).n>=2);
 // A duplicate nonnull intent is rejected with otherwise distinct payment and
 // evidence IDs, and its preceding evidence INSERT is rolled back too.
 await assert.rejects(db.batch(clonePayment(db,c,c.intents[0].id)),/UNIQUE constraint failed: payments.intent_id/);
 assert.deepEqual(await snapshot(db),after15);
 // Both nulls and another issued intent reach the deliberate final guard.
 // The guard then rolls back these constraint probes without extra money.
 await assert.rejects(db.batch([...clonePayment(db,c,null),...clonePayment(db,c,null),...clonePayment(db,c,c.intents[1].id),db.prepare("INSERT INTO momo_processing_guards(id,passed) VALUES('synthetic-semantic-probe',0)")]),/momo_processing_state/);
 assert.deepEqual(await snapshot(db),after15);
 // The replaced trigger still rejects bound-source identity changes, while
 // allowing only the reviewed historical mapping introduced by migration15.
 await assert.rejects(db.prepare('UPDATE momo_processing_jobs SET mode=\'historical\' WHERE raw_sms_id=?').bind(c.sources[0].id).run(),/immutable_momo_source/);
 await assert.rejects(db.batch([
  db.prepare('INSERT INTO momo_source_resolutions(id,raw_sms_id,receiving_account_id,source_body_sha256,reviewed_by,evidence_reference,reason,created_at) VALUES(?,?,?,?,?,?,?,?)').bind(randomUUID(),c.sources[1].id,populated.account,c.sources[1].digest,c.account.userId,'SYNTHETIC upgrade review','Controlled trigger compatibility proof',new Date().toISOString()),
  db.prepare('UPDATE momo_processing_jobs SET receiving_account_id=? WHERE raw_sms_id=?').bind(populated.account,c.sources[1].id),
  db.prepare("INSERT INTO momo_processing_guards(id,passed) VALUES('synthetic-resolution-probe',0)"),
 ]),/momo_processing_state/);
 assert.deepEqual(await snapshot(db),after15);assert.deepEqual(await objects(c.bucket),objects14);assert.equal((await db.prepare('PRAGMA foreign_key_check').all()).results.length,0);
 t.diagnostic(JSON.stringify({schema13_tables:Object.keys(before13.contents).length,schema14_tables:Object.keys(before15.contents).length,schema15_tables:Object.keys(after15.contents).length,retention_tasks:c.counts.privacy_retention_tasks,issued_intents:c.intents.length,added_grants:added.length,ledger_rows:after15.contents.ledger_entries.length,sqlite_sequence_unchanged:true,raw_and_r2_unchanged:true}));
});

test('migration15 duplicate existing nonnull intent aborts and rolls back its whole batch to exact populated14 schema, rows and grants',{timeout:180000},async t=>{
 const c=await populated13(t),db=c.f.db;await apply(db,migrations[0]);await populate14(c);
 await db.prepare('UPDATE payments SET intent_id=? WHERE id=?').bind(c.intents[0].id,c.payments[1].id).run();
 assert.equal((await db.prepare('SELECT count(*) AS n FROM payments WHERE intent_id=?').bind(c.intents[0].id).first()).n,2);
 const before=await snapshot(db),beforeObjects=await objects(c.bucket);
 await assert.rejects(apply(db,migrations[1]),/UNIQUE constraint failed: payments.intent_id/);
 assert.deepEqual(await snapshot(db),before,'all preceding DDL, trigger replacement and capability/grant inserts rolled back');
 assert.deepEqual(await objects(c.bucket),beforeObjects);assert.equal((await db.prepare('PRAGMA foreign_key_check').all()).results.length,0);
 assert.equal((await db.prepare('SELECT count(*) AS n FROM admin_account_role_capabilities').first()).n,63);
 assert.equal((await db.prepare("SELECT count(*) AS n FROM sqlite_schema WHERE name IN('one_payment_per_intent','momo_gateway_pairings','momo_gateway_credentials','momo_gateway_captures','momo_source_resolutions','momo_financial_links','contribution_posting_snapshots')").first()).n,0);
 t.diagnostic(JSON.stringify({duplicate_intent_payments:2,preserved_schema14_tables:Object.keys(before.contents).length,retention_tasks:c.counts.privacy_retention_tasks,exact_batch_rollback:true,financial_and_r2_unchanged:true}));
});

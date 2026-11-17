/** Synthetic in-memory SQLite boundary harness, NOT PostgreSQL / Collect guards.
 * Actual shared SQL and record SELECT execute; FOR UPDATE is explicitly removed
 * and positional parameters are bound for SQLite. No concurrency/RLS claim.
 * runtime/allocation/evidence below are TEST BRIDGES, not shipping integrations.
 */
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import {PostgresSharedPosting} from '../../domain/burimunsi/postgres-shared-posting.js';
import {ids} from './shared-posting-fixture.mjs';
export {ids};
const ddl=readFileSync(new URL('./sqlite/posting-fixture.sql',import.meta.url),'utf8');
export function postingFixture(mode='automatic'){
 const sqlite=new DatabaseSync(':memory:');
 sqlite.exec("ATTACH ':memory:' AS app; ATTACH ':memory:' AS private;");
 sqlite.exec(ddl.replace(/CREATE TABLE (\w+)/g,'CREATE TABLE app.$1').replace('CREATE UNIQUE INDEX one_contribution','CREATE UNIQUE INDEX app.one_contribution'));
 sqlite.exec(`ALTER TABLE app.collections ADD COLUMN status TEXT DEFAULT 'active';
 ALTER TABLE app.collections ADD COLUMN receiver_network TEXT DEFAULT 'mtn_momo';
 ALTER TABLE app.collections ADD COLUMN receiver_momo_number TEXT DEFAULT '+250780000001';
 ALTER TABLE app.payment_evidence ADD COLUMN collection_id TEXT;
 ALTER TABLE app.payment_evidence ADD COLUMN amount_minor INTEGER;
 ALTER TABLE app.payment_evidence ADD COLUMN object_key TEXT;
 ALTER TABLE app.payment_evidence ADD COLUMN object_sha256 TEXT;
 ALTER TABLE app.payment_evidence ADD COLUMN size_bytes INTEGER;
 ALTER TABLE app.momo_receiving_accounts ADD COLUMN status TEXT DEFAULT 'active';
 ALTER TABLE app.momo_receiving_accounts ADD COLUMN profile_status TEXT DEFAULT 'approved';
 ALTER TABLE app.momo_transactions ADD COLUMN amount_minor INTEGER;
 ALTER TABLE app.momo_transactions ADD COLUMN version INTEGER;
 ALTER TABLE app.momo_transactions ADD COLUMN updated_at TEXT;
 ALTER TABLE app.momo_financial_links ADD COLUMN historical_existing INTEGER DEFAULT 0;
 CREATE TABLE app.memberships(collection_id TEXT,user_id TEXT,active INTEGER,PRIMARY KEY(collection_id,user_id));
 CREATE TABLE app.users(id TEXT PRIMARY KEY,access_status TEXT);
 CREATE TABLE private.burimunsi_scopes(collection_id TEXT PRIMARY KEY,receiving_account_id TEXT,enabled BOOLEAN);
 CREATE TABLE private.burimunsi_transaction_scopes(transaction_id TEXT PRIMARY KEY,collection_id TEXT,receiving_account_id TEXT,
   source_binding_id TEXT,source_binding_version INTEGER,policy_version TEXT,native_source_id TEXT);`);
 sqlite.prepare('INSERT INTO app.collections(id,title) VALUES(?,?)').run(ids.group,'EXAMPLE GROUP');
 sqlite.prepare('INSERT INTO app.users VALUES(?,?)').run(ids.member,'active');
 sqlite.prepare('INSERT INTO app.memberships VALUES(?,?,?)').run(ids.group,ids.member,1);
 sqlite.prepare('INSERT INTO app.payment_evidence VALUES(?,?,?,?,?,?,?,?,?,?)').run(ids.evidence,'wallet-1:FT100','mtn_momo','+250780000001','RWF',ids.group,12500,'evidence/test', 'a'.repeat(64),120);
 sqlite.prepare('INSERT INTO app.payments VALUES(?,?,?,?,?,?,?,?,?,?)').run(ids.payment,ids.group,null,12500,'RWF','rwanda_momo',7,'recorded',ids.evidence,ids.intent);
 sqlite.prepare('INSERT INTO app.momo_receiving_accounts(id,provider,public_code) VALUES(?,?,?)').run('wallet-1','mtn_momo','0780000001');
 sqlite.prepare('INSERT INTO app.momo_transactions VALUES(?,?,?,?,?,?,?,?,?,?,?,?)').run('transaction-1','wallet-1','incoming_receipt','mtn_momo','RWF','FT100',0,'unallocated','live',12500,3,'2026-11-07T00:00:00.000Z');
 sqlite.prepare('INSERT INTO app.payment_intents VALUES(?,?,?)').run(ids.intent,ids.member,'pending');
 sqlite.prepare('INSERT INTO private.burimunsi_scopes VALUES(?,?,?)').run(ids.group,'wallet-1',1);
 sqlite.prepare('INSERT INTO private.burimunsi_transaction_scopes VALUES(?,?,?,?,?,?,?)').run('transaction-1',ids.group,'wallet-1','binding-1',2,'verified-test-v1',null);
 const command={groupId:ids.group,receiptId:'transaction-1',memberId:ids.member,requestId:ids.request,expectedVersion:3,mode,
  receipt:{id:'transaction-1',groupId:ids.group,receivingAccountId:'wallet-1',sourceBindingId:'binding-1',sourceBindingVersion:2,
    state:'unallocated',hasConflict:false,version:3,amountRwf:12500,currency:'RWF',providerTransactionId:'FT100'},
  member:{id:ids.member,groupId:ids.group,active:true,eligible:true}};
 if(mode==='automatic')Object.assign(command,{work:{kind:'receipt',jobId:ids.request,owner:'worker-1',leaseVersion:1},policyVersion:'verified-test-v1',identityIds:['identity-1']});
 else Object.assign(command,{actorId:ids.actor,sessionId:ids.session,actor:{principalUserId:ids.otherActor},reason:'Verified original source and identity'});
 const state={phases:[],statements:[],queries:[],allocationCalls:0,evidenceCalls:0,failAt:-1,afterAllocation:null,onProof:null,onAuthority:null};
 const sql={unsafe:async(text,values=[])=>{
   state.queries.push({text,values});
   const params=[];const compiled=text.replace(/ FOR UPDATE OF x,b,t,f,p,e,a,g,m,u\s*$/,'').replace(/\$(\d+)/g,(_s,n)=>{params.push(values[Number(n)-1]);return '?';});
   return sqlite.prepare(compiled).all(...params).map(row=>{const r={...row};for(const k of ['has_entries','has_snapshot','has_other_reference'])if(k in r)r[k]=Boolean(r[k]);return r;});
 }};
 const work={assert:async()=>{}};
 const db={applicationWork:work,prepare:text=>({bind:(...values)=>({sql:text,values})}),statement:async(tx,statement)=>{
   if(tx!==sql)throw Error('wrong test transaction');
   if(state.statements.length===state.failAt)throw Error('injected statement failure');
   state.statements.push(statement);const result=sqlite.prepare(statement.sql).run(...statement.values);
   return {success:true,results:[],meta:{changes:Number(result.changes)}};
 }};
 const runtime={assertInTransaction:async(tx,{command:cmd,phase})=>{
   if(tx!==sql)throw Error('wrong transaction');state.phases.push(phase);
   const result={contractVersion:1,groupId:cmd.groupId,receiptId:cmd.receiptId,requestId:cmd.requestId,mode:cmd.mode,
     kind:cmd.mode==='automatic'?'admitted_worker':'native_operator',actorId:ids.actor,sessionId:ids.session,
     principalUserId:ids.otherActor,principalSessionId:'00000011-1111-4111-8111-111111111111',
     ...(cmd.mode==='automatic'?{policyVersion:cmd.policyVersion}:{})};
   await state.onAuthority?.(phase,result,cmd);return result;
 }};
 const allocation={prepareInTransaction:async(tx,cmd)=>{
   if(tx!==sql||!Object.isFrozen(cmd)||!Object.isFrozen(cmd.receipt))throw Error('wrong or mutable transaction command');
   state.allocationCalls++;
   sqlite.prepare('INSERT INTO app.momo_financial_links(transaction_id,payment_id,beneficiary_member_id) VALUES(?,?,?)').run(cmd.receiptId,ids.payment,cmd.memberId);
   sqlite.prepare("UPDATE app.momo_transactions SET allocation_state='linked',version=version+1 WHERE id=?").run(cmd.receiptId);
   await state.afterAllocation?.();return {paymentId:ids.payment};
 }};
 const evidence={assertInTransaction:async(tx,descriptor)=>{
   if(tx!==sql||descriptor.objectSha256!=='a'.repeat(64))throw Error('bad source proof request');
   state.evidenceCalls++;return await state.onProof?.(descriptor)??{verified:true};
 }};
 const writer=new PostgresSharedPosting({db,groupId:ids.group,runtime,allocation,evidence});
 const snapshot=()=>['app','private'].flatMap(schema=>sqlite.prepare(`SELECT name FROM ${schema}.sqlite_master WHERE type='table' ORDER BY name`).all().map(({name})=>[schema+'.'+name,sqlite.prepare(`SELECT * FROM ${schema}.${name} ORDER BY rowid`).all()]));
 async function run(){sqlite.exec('BEGIN');try{const result=await writer.postContribution(sql,command);sqlite.exec('COMMIT');return result;}catch(e){sqlite.exec('ROLLBACK');throw e;}}
 return {sqlite,command,state,sql,db,runtime,allocation,evidence,writer,run,snapshot,close:()=>sqlite.close()};
}

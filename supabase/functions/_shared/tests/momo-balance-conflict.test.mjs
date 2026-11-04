import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {DatabaseSync} from 'node:sqlite';
import {digest} from '../domain/core.js';
import {encrypt} from '../domain/encryption.js';
import {processMomoJob} from '../domain/momo_pipeline.js';

// Invented receipts and a transient in-memory database. This exercises the real
// processing statements; it does not establish provider or PostgreSQL behavior.
const fixture=JSON.parse(await readFile(new URL('../../../../deploy/platform-api/test/fixtures/momo-synthetic.json',import.meta.url),'utf8'));
const stamp='2026-10-18T08:15:00.000Z';
const schema=`
 PRAGMA temp_store=MEMORY;
 PRAGMA journal_mode=MEMORY;
 CREATE TABLE sms_receipts(id TEXT PRIMARY KEY,body_sha256 TEXT NOT NULL,object_key TEXT NOT NULL,object_sha256 TEXT NOT NULL,size_bytes INTEGER NOT NULL);
 CREATE TABLE momo_receiving_accounts(id TEXT PRIMARY KEY,provider TEXT NOT NULL,status TEXT NOT NULL,profile_status TEXT NOT NULL,profile_version TEXT NOT NULL,profile_json TEXT NOT NULL,currency TEXT NOT NULL,timezone TEXT NOT NULL);
 CREATE TABLE momo_processing_jobs(raw_sms_id TEXT PRIMARY KEY,receiving_account_id TEXT NOT NULL,mode TEXT NOT NULL,state TEXT NOT NULL,attempt_count INTEGER NOT NULL DEFAULT 0,max_attempts INTEGER NOT NULL DEFAULT 4,available_at INTEGER NOT NULL,lease_token TEXT,lease_until INTEGER,last_error TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL);
 CREATE TABLE momo_processing_guards(id TEXT PRIMARY KEY,passed INTEGER NOT NULL CHECK(passed=1));
 CREATE TABLE momo_parse_attempts(id TEXT PRIMARY KEY,raw_sms_id TEXT NOT NULL,attempt_number INTEGER NOT NULL,model_id TEXT NOT NULL,schema_version TEXT NOT NULL,prompt_version TEXT NOT NULL,parser_version TEXT NOT NULL,profile_version TEXT NOT NULL,profile_json TEXT NOT NULL,source_body_sha256 TEXT NOT NULL,output_json TEXT,validation_json TEXT NOT NULL,outcome TEXT NOT NULL,created_at TEXT NOT NULL,UNIQUE(raw_sms_id,attempt_number));
 CREATE TABLE momo_transactions(id TEXT PRIMARY KEY,receiving_account_id TEXT NOT NULL,provider TEXT NOT NULL,provider_transaction_id TEXT NOT NULL,event_kind TEXT NOT NULL,original_transaction_id TEXT,amount_minor INTEGER NOT NULL,currency TEXT NOT NULL,currency_scale INTEGER NOT NULL,payer_name TEXT,payer_identifier TEXT,payer_last3 TEXT,transaction_at TEXT,transaction_datetime_raw TEXT,transaction_timezone TEXT NOT NULL,transaction_time_source TEXT NOT NULL,fee_minor INTEGER,wallet_balance_after_minor INTEGER,parse_attempt_id TEXT NOT NULL,mode TEXT NOT NULL,allocation_state TEXT NOT NULL DEFAULT 'unallocated',has_conflict INTEGER NOT NULL DEFAULT 0,version INTEGER NOT NULL DEFAULT 1,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,UNIQUE(provider,receiving_account_id,event_kind,provider_transaction_id));
 CREATE TABLE momo_transaction_sources(transaction_id TEXT NOT NULL,raw_sms_id TEXT NOT NULL,parse_attempt_id TEXT NOT NULL,relation TEXT NOT NULL,created_at TEXT NOT NULL,PRIMARY KEY(transaction_id,raw_sms_id,parse_attempt_id));
 CREATE TABLE audit_log(action TEXT NOT NULL,entity_type TEXT NOT NULL,entity_id TEXT,details_json TEXT NOT NULL,created_at TEXT NOT NULL);
 CREATE TABLE ledger_entries(id TEXT PRIMARY KEY,amount INTEGER NOT NULL);
 CREATE TABLE momo_financial_links(transaction_id TEXT PRIMARY KEY,payment_id TEXT NOT NULL UNIQUE);
 INSERT INTO ledger_entries VALUES('unchanged-synthetic-entry',17);
`;

function memoryDb(sqlite){
 const db={prepare(sql){return {bind(...values){
  const execute=()=>{const statement=sqlite.prepare(sql);return statement.columns().length?{results:statement.all(...values)}:{meta:statement.run(...values)};};
  return {async first(){return sqlite.prepare(sql).get(...values)??null;},async run(){return execute();},async all(){return execute();},execute};
 }};},async batch(statements){
  sqlite.exec('BEGIN IMMEDIATE');
  try{const result=statements.map(statement=>statement.execute());sqlite.exec('COMMIT');return result;}
  catch(error){sqlite.exec('ROLLBACK');throw error;}
 }};
 return db;
}

function scenario(){
 const sqlite=new DatabaseSync(':memory:');sqlite.exec(schema);
 const objects=new Map();let calls=0;
 const env={DB:memoryDb(sqlite),MOMO_PROCESSING_PAUSED:'false',DATA_KEY_ID:'synthetic',DATA_ENCRYPTION_KEY:btoa('s'.repeat(32)),
  PRIVATE_MEDIA:{async get(key){const cipher=objects.get(key);return cipher?{size:cipher.length,async text(){return cipher;}}:null;}},
  AI:{async run(){calls++;return {response:env.output};}}};
 function account(id,provider='mtn_momo'){
  sqlite.prepare('INSERT INTO momo_receiving_accounts VALUES(?,?,?,?,?,?,?,?)').run(id,provider,'active','approved','synthetic.v1',JSON.stringify(fixture.profile),'RWF','Africa/Kigali');
 }
 async function capture({accountId='account-a',balance='125,000',reference='001234567890',rawBalanceWhenOmitted=false}={}){
  const rawId=crypto.randomUUID(),key='sms/'+rawId;
  let body=fixture.body.replaceAll('001234567890',reference);
  const output=structuredClone(fixture.output);output.transaction_id_raw=reference;output.evidence.transaction_id=`Transaction ID: ${reference}`;
  if(balance===null){
   if(!rawBalanceWhenOmitted)body=body.replace(' Balance: RWF 125,000.','');
   output.wallet_balance_after_raw=null;output.evidence.wallet_balance_after=null;
  }
  else{body=body.replace('Balance: RWF 125,000',`Balance: RWF ${balance}`);output.wallet_balance_after_raw=balance;output.evidence.wallet_balance_after=`Balance: RWF ${balance}`;}
  const bytes=new TextEncoder().encode(JSON.stringify({raw_sender:fixture.sender,raw_body:body,completeness:'complete'}));
  const objectSha=await digest(bytes),cipher=await encrypt(env,bytes,`sms:${rawId}:${objectSha}`);objects.set(key,cipher);
  sqlite.prepare('INSERT INTO sms_receipts VALUES(?,?,?,?,?)').run(rawId,await digest(body),key,objectSha,bytes.length);
  sqlite.prepare('INSERT INTO momo_processing_jobs(raw_sms_id,receiving_account_id,mode,state,available_at,created_at,updated_at) VALUES(?,?,?, ?,0,?,?)').run(rawId,accountId,'live','pending',stamp,stamp);
  return {rawId,output,body};
 }
 async function process(capture){env.output=capture.output;return processMomoJob(env,capture.rawId);}
 const all=(sql,...values)=>sqlite.prepare(sql).all(...values);
 return {sqlite,account,capture,process,all,get calls(){return calls;},close(){sqlite.close();}};
}

async function pair(firstBalance,secondBalance){
 const h=scenario();h.account('account-a');
 const first=await h.capture({balance:firstBalance}),second=await h.capture({balance:secondBalance});
 const firstResult=await h.process(first),secondResult=await h.process(second);
 return {h,first,second,firstResult,secondResult};
}

test('equal balance observations are duplicate sources for one immutable transaction',async()=>{
 const {h,first,firstResult,secondResult}=await pair('125,000','125,000');
 try{
  assert.equal(firstResult.relation,'accepted');assert.equal(secondResult.relation,'duplicate');
  const [row]=h.all('SELECT * FROM momo_transactions');assert.equal(row.wallet_balance_after_minor,125000);assert.equal(row.has_conflict,0);assert.equal(row.allocation_state,'unallocated');
  assert.deepEqual(h.all('SELECT relation FROM momo_transaction_sources ORDER BY relation').map(row=>row.relation),['accepted','duplicate']);
  assert.deepEqual(h.all('SELECT outcome FROM momo_parse_attempts ORDER BY attempt_number,raw_sms_id').map(row=>row.outcome).sort(),['accepted','duplicate']);
  assert.deepEqual(await h.process(first),{state:'not_claimed'});assert.equal(h.calls,2);
  assert.equal(h.all('SELECT * FROM ledger_entries').length,1);
 }finally{h.close();}
});

for(const [first,second] of [['125,000','125,001'],['125,000',null],[null,'125,000']]){
 test(`different balance observations ${first??'missing'} and ${second??'missing'} require reconciliation`,async()=>{
  const {h,first:firstCapture,second:secondCapture,firstResult,secondResult}=await pair(first,second);
  try{
   assert.equal(firstCapture.body.includes('Balance:'),first!==null);
   assert.equal(secondCapture.body.includes('Balance:'),second!==null);
   assert.equal(firstResult.relation,'accepted');assert.equal(secondResult.relation,'conflict');assert.equal(secondResult.state,'needs_review');
   const transactions=h.all('SELECT wallet_balance_after_minor,allocation_state,has_conflict,version FROM momo_transactions');assert.equal(transactions.length,1);
   assert.equal(transactions[0].wallet_balance_after_minor,first===null?null:125000);assert.equal(transactions[0].allocation_state,'needs_review');assert.equal(transactions[0].has_conflict,1);assert.equal(transactions[0].version,2);
   assert.deepEqual(h.all('SELECT relation FROM momo_transaction_sources ORDER BY relation').map(row=>row.relation),['accepted','conflict']);
   assert.deepEqual(h.all('SELECT outcome FROM momo_parse_attempts').map(row=>row.outcome).sort(),['accepted','conflict']);
   assert.deepEqual(h.all('SELECT state FROM momo_processing_jobs').map(row=>row.state).sort(),['completed','needs_review']);
   assert.equal(h.all('SELECT amount FROM ledger_entries')[0].amount,17);
  }finally{h.close();}
 });
}

test('two absent balances and two zero balances remain distinct valid duplicate cases',async()=>{
 for(const balance of [null,'0']){
  const {h,first,second,secondResult}=await pair(balance,balance);
  try{assert.equal(first.body.includes('Balance:'),balance!==null);assert.equal(second.body.includes('Balance:'),balance!==null);assert.equal(secondResult.relation,'duplicate');assert.equal(h.all('SELECT wallet_balance_after_minor FROM momo_transactions')[0].wallet_balance_after_minor,balance===null?null:0);}
  finally{h.close();}
 }
});

test('model omission conflicts even when the balance is present in the source',async()=>{
 for(const omittedFirst of [true,false]){
  const h=scenario();h.account('account-a');
  try{
   const omitted=await h.capture({balance:null,rawBalanceWhenOmitted:true}),present=await h.capture();
   assert.match(omitted.body,/Balance: RWF 125,000\./);assert.equal(omitted.output.wallet_balance_after_raw,null);
   const first=omittedFirst?omitted:present,second=omittedFirst?present:omitted;
   assert.equal((await h.process(first)).relation,'accepted');assert.equal((await h.process(second)).relation,'conflict');
   assert.equal(h.all('SELECT has_conflict FROM momo_transactions')[0].has_conflict,1);
  }finally{h.close();}
 }
});

test('a later balance conflict retains an existing financial link and ledger',async()=>{
 const h=scenario();h.account('account-a');
 try{
  const first=await h.capture();assert.equal((await h.process(first)).relation,'accepted');
  const txId=h.all('SELECT id FROM momo_transactions')[0].id;
  h.sqlite.prepare("UPDATE momo_transactions SET allocation_state='linked',version=version+1 WHERE id=?").run(txId);
  h.sqlite.prepare('INSERT INTO momo_financial_links VALUES(?,?)').run(txId,'synthetic-payment');
  const later=await h.capture({balance:'125,001'}),result=await h.process(later);
  assert.equal(result.relation,'conflict');assert.equal(result.state,'needs_review');
  const [transaction]=h.all('SELECT allocation_state,has_conflict,version,wallet_balance_after_minor FROM momo_transactions');
  assert.equal(transaction.allocation_state,'needs_review');assert.equal(transaction.has_conflict,1);assert.equal(transaction.version,3);assert.equal(transaction.wallet_balance_after_minor,125000);
  assert.equal(h.all('SELECT payment_id FROM momo_financial_links WHERE transaction_id=?',txId)[0].payment_id,'synthetic-payment');
  assert.equal(h.all('SELECT amount FROM ledger_entries')[0].amount,17);
 }finally{h.close();}
});

test('different provider references or receiving accounts remain independent transactions',async()=>{
 const h=scenario();h.account('account-a');h.account('account-b');
 try{
  const a=await h.capture(),otherReference=await h.capture({reference:'009999999999',balance:'125,001'}),otherAccount=await h.capture({accountId:'account-b',balance:'125,001'});
  for(const capture of [a,otherReference,otherAccount])assert.equal((await h.process(capture)).relation,'accepted');
  assert.equal(h.all('SELECT * FROM momo_transactions').length,3);assert.equal(h.all('SELECT * FROM momo_transactions WHERE has_conflict<>0').length,0);
  assert.equal(h.all('SELECT amount FROM ledger_entries')[0].amount,17);
 }finally{h.close();}
});

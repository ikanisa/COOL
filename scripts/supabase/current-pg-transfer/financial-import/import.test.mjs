import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes,createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from '../../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../test-support/owned-pg17.mjs';
import {FinancialImportError,captureSyntheticFinancialPlan,importSyntheticFinancialGraph,reconcileSyntheticFinancialGraph,financialPlanDigest} from './import.mjs';
const {Client}=pg;
const ids={source:'local-owner',target:'cloud-primary',member:'beneficiary',collection:'collection-one',
 sourceAuth:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',targetAuth:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',operation:'cccccccc-cccc-4ccc-8ccc-cccccccccccc'};
const canonical=x=>Array.isArray(x)?'['+x.map(canonical).join(',')+']':x&&typeof x==='object'?'{'+Object.keys(x).sort().map(k=>JSON.stringify(k)+':'+canonical(x[k])).join(',')+'}':JSON.stringify(x);
const code=x=>e=>e instanceof FinancialImportError&&e.code===x&&!String(e).includes('sensitive-fixture');
const outputTables=['payment_evidence','payments','momo_financial_links','ledger_entries','contribution_posting_snapshots'];

test('synthetic posted financial graphs transfer atomically with cloud-primary mapping',{timeout:180000},async t=>{
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_financial_import_fixture'});
 const clients=[];
 async function connect(db='collect_financial_import_fixture',user='fixture_operator'){
  const c=new Client({host:f.socket,port:f.port,database:db,user,connectionTimeoutMillis:3000});await c.connect();clients.push(c);return c;
 }
 let admin;
 try{
  const boot=await connect('postgres','fixture_bootstrap');
  await boot.query('CREATE ROLE fixture_operator LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS');
  await boot.query('CREATE DATABASE collect_financial_import_fixture OWNER fixture_bootstrap');
  admin=await connect('collect_financial_import_fixture','fixture_bootstrap');
  const fixtureSql=await readFile(new URL('./fixture.sql',import.meta.url),'utf8');await admin.query(fixtureSql);
  await admin.query('INSERT INTO src.users VALUES($1,true),($2,true)',[ids.source,ids.member]);
  await admin.query('INSERT INTO app.users VALUES($1,true),($2,true)',[ids.target,ids.member]);
  await admin.query('INSERT INTO src.auth_users VALUES($1,true)',[ids.sourceAuth]);await admin.query('INSERT INTO auth.users VALUES($1,true)',[ids.targetAuth]);
  await admin.query('INSERT INTO src.auth_links VALUES($1,$2)',[ids.sourceAuth,ids.source]);await admin.query('INSERT INTO private.auth_links VALUES($1,$2)',[ids.targetAuth,ids.target]);
  await admin.query('INSERT INTO src.collections VALUES($1,$2)',[ids.collection,ids.source]);await admin.query('INSERT INTO app.collections VALUES($1,$2)',[ids.collection,ids.target]);
  await admin.query("INSERT INTO src.memberships VALUES('membership-one',$1,$2)",[ids.collection,ids.member]);await admin.query("INSERT INTO app.memberships VALUES('membership-one',$1,$2)",[ids.collection,ids.member]);
  await admin.query("INSERT INTO private.fixture_history_attestation VALUES($1,true,true,true,$2)",[ids.collection,'f'.repeat(64)]);
  await admin.query("INSERT INTO private.fixture_fences VALUES('source',11,'fenced'),('target',22,'fenced');INSERT INTO private.fixture_admissions VALUES('settled',0)");
  for(let i=1;i<=2;i++){
   const sms='sms-'+i,attempt='attempt-'+i,txn='txn-'+i,evidence='evidence-'+i,payment='payment-'+i,ledger='ledger-'+i;
   const body=String(i).repeat(64),smsSha=String(i+2).repeat(64),evidenceSha=body,cipher='a'.repeat(64),date=`2026-01-01T00:00:0${i}.000Z`;
   await admin.query(`INSERT INTO src.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at)
    VALUES($1,$2,NULL,$3,$4,NULL,$5,$6,10,$7)`,[sms,ids.source,'envelope-'+i,body,'sms/'+sms,smsSha,date]);
   await admin.query("INSERT INTO app.sms_receipts SELECT (jsonb_populate_record(NULL::app.sms_receipts,to_jsonb(s)||jsonb_build_object('owner_user_id',$2::text))).* FROM src.sms_receipts s WHERE id=$1",[sms,ids.target]);
   await admin.query(`INSERT INTO src.momo_parse_attempts(id,raw_sms_id,attempt_number,model_id,schema_version,prompt_version,parser_version,profile_version,profile_json,source_body_sha256,output_json,validation_json,outcome,created_at)
    VALUES($1,$2,1,'fixture','v1','v1','v1','v1','{}',$3,'{}','{}','accepted',$4)`,[attempt,sms,body,date]);
   await admin.query('INSERT INTO app.momo_parse_attempts SELECT * FROM src.momo_parse_attempts WHERE id=$1',[attempt]);
   await admin.query(`INSERT INTO src.momo_transactions(id,receiving_account_id,provider,provider_transaction_id,event_kind,amount_minor,currency,currency_scale,transaction_timezone,transaction_time_source,parse_attempt_id,mode,allocation_state,created_at,updated_at)
    VALUES($1,'account-one','mtn',NULL,'incoming_receipt',$2,'RWF',0,'Africa/Kigali','missing',$3,'historical','linked',$4,$4)`,[txn,i*1250,attempt,date]);
   await admin.query('INSERT INTO app.momo_transactions SELECT * FROM src.momo_transactions WHERE id=$1',[txn]);
   await admin.query("INSERT INTO src.momo_transaction_sources VALUES($1,$2,$3,'accepted',$4)",[txn,sms,attempt,date]);await admin.query('INSERT INTO app.momo_transaction_sources SELECT * FROM src.momo_transaction_sources WHERE transaction_id=$1',[txn]);
   await admin.query('INSERT INTO src.origins VALUES($1,$2,$3,$4,$5)',[sms,ids.collection,ids.source,body,smsSha]);await admin.query('INSERT INTO private.origins VALUES($1,$2,$3,$4,$5)',[sms,ids.collection,ids.target,body,smsSha]);
   const facts={event_kind:'incoming_receipt',payment_outcome:'successful',currency:'RWF',amount_minor:i*1250,source_mode:'catch_up',wallet_balance_after_minor:9000,
    counterparty_name:null,counterparty_identifier:null,transaction_at:null,transaction_datetime_raw:null,provider_transaction_id:null,original_transaction_id:null,fee_minor:null,transaction_time_source:null,transaction_timezone:null};
   await admin.query("INSERT INTO src.jobs VALUES($1,$2,$3,$4,'completed',$5::jsonb)",[sms,txn,ids.collection,'b'.repeat(64),JSON.stringify(facts)]);await admin.query('INSERT INTO private.jobs SELECT * FROM src.jobs WHERE source_id=$1',[sms]);
   await admin.query("INSERT INTO src.scopes VALUES($1,$2,$3,'account-one')",[sms,txn,ids.collection]);await admin.query('INSERT INTO private.scopes SELECT * FROM src.scopes WHERE source_id=$1',[sms]);
   await admin.query(`INSERT INTO src.payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,amount_minor,observed_at,created_at)
    VALUES($1,$2,$3,$4,$5,10,'application/octet-stream','operator_recorded',$6,$7,$8,$8)`,[evidence,ids.collection,ids.source,'evidence/'+evidence,evidenceSha,'sms:'+body+':'+sms,i*1250,date]);
   await admin.query("INSERT INTO src.payments(id,collection_id,member_id,evidence_id,amount_minor,status,created_at) VALUES($1,$2,$3,$4,$5,'reconciled',$6)",[payment,ids.collection,ids.member,evidence,i*1250,date]);
   await admin.query("INSERT INTO src.momo_financial_links VALUES($1,$2,$3,$4,'synthetic',0,$5)",[txn,payment,ids.member,ids.source,date]);
   await admin.query("INSERT INTO src.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES($1,$2,$3,$4,$5,'contribution',$6,$7,$8,$9)",[ledger,payment,ids.collection,ids.member,i*1250,evidence,ids.source,'request-'+i,date]);
   await admin.query('INSERT INTO src.contribution_posting_snapshots VALUES($1,$2,$3,$3,$4)',[ledger,payment,1250*i*(i+1)/2,date]);
   for(const [key,entity,purpose,plain] of [['sms/'+sms,sms,'sms_receipt',smsSha],['evidence/'+evidence,evidence,'payment_evidence',evidenceSha]]){
    const aad=(purpose==='sms_receipt'?'sms:':'evidence:')+entity+':'+plain;
    await admin.query('INSERT INTO src.object_proofs VALUES($1,$2,$3,$4,$5,$6,$7,true)',[key,ids.source,entity,purpose,plain,cipher,aad]);await admin.query('INSERT INTO private.object_proofs VALUES($1,$2,$3,$4,$5,$6,$7,true)',[key,ids.target,entity,purpose,plain,cipher,aad]);
   }
  }
  const key=randomBytes(32),request={version:'collect.synthetic-financial-import.v1',operation_id:ids.operation,collection_id:ids.collection,source_owner:ids.source,target_owner:ids.target,source_auth:ids.sourceAuth,target_auth:ids.targetAuth,source_epoch:'11',target_epoch:'22'};
  const base=()=>({mode:'synthetic',requestJson:canonical(request),key,connect:()=>connect()});
  const capture=async()=>{const x=await captureSyntheticFinancialPlan(base());return {mode:'synthetic',...x,key,connect:()=>connect()};};
  async function clear(){await admin.query('TRUNCATE app.contribution_posting_snapshots,app.ledger_entries,app.momo_financial_links,app.payments,app.payment_evidence,private.fixture_financial_receipts');}
  async function counts(){const q=await admin.query('SELECT '+outputTables.map(n=>`(SELECT count(*)::int FROM app.${n}) AS ${n}`).join(','));return Object.values(q.rows[0]);}
  await t.test('managed execution refuses before connecting',async()=>{
   let connected=false;const opts={...base(),mode:'managed',connect:()=>{connected=true;}};
   await assert.rejects(captureSyntheticFinancialPlan(opts),code('managed_execution_closed'));
   await assert.rejects(importSyntheticFinancialGraph(opts),code('managed_execution_closed'));
   await assert.rejects(reconcileSyntheticFinancialGraph(opts),code('managed_execution_closed'));assert.equal(connected,false);
  });
  await t.test('caller accessors, proxies and shared keys fail before connecting',async()=>{
   let reads=0,connected=0;const opts=base();opts.connect=()=>{connected++;};
   Object.defineProperty(opts,'requestJson',{get(){reads++;return canonical(request);},enumerable:true});
   await assert.rejects(captureSyntheticFinancialPlan(opts),code('invalid_input'));
   const proxy=new Proxy(base(),{getOwnPropertyDescriptor(){reads++;throw Error('unexpected');}});
   await assert.rejects(captureSyntheticFinancialPlan(proxy),code('invalid_input'));
   await assert.rejects(captureSyntheticFinancialPlan({...base(),key:Buffer.from(new SharedArrayBuffer(32))}),code('invalid_input'));
   assert.equal(reads,0);assert.equal(connected,0);
   const privateKey=Buffer.alloc(32,7);Object.defineProperty(privateKey,'buffer',{get(){reads++;throw Error('unexpected');}});
   const result=await captureSyntheticFinancialPlan({...base(),key:privateKey});
   assert.equal(result.writeAuthorized,false);assert.equal(reads,0);assert.equal(privateKey[0],7);
  });
  await t.test('capture pins private graph and absent receipt is never permission to retry',async()=>{
   const p=await capture();assert.equal(p.writeAuthorized,false);assert.doesNotMatch(p.planJson,/sensitive-fixture/);
   assert.deepEqual(await reconcileSyntheticFinancialGraph(p),{status:'receipt_not_visible_do_not_retry'});
   const altered=JSON.parse(p.planJson);altered.target_owner='unapproved';p.planJson=canonical(altered);
   await assert.rejects(importSyntheticFinancialGraph(p),code('invalid_input'));
  });
  await t.test('actual PostgreSQL import preserves IDs, beneficiary and original timestamps',async()=>{
   const p=await capture();assert.deepEqual(await importSyntheticFinancialGraph(p),{status:'applied',payment_count:2});
   assert.deepEqual(await counts(),[2,2,2,2,2]);
   const q=await admin.query(`SELECT e.id evidence_id,p.id payment_id,p.member_id,p.created_at,f.linked_by,l.id ledger_id,l.actor_user_id,e.owner_user_id
    FROM app.payments p JOIN app.payment_evidence e ON e.id=p.evidence_id JOIN app.momo_financial_links f ON f.payment_id=p.id JOIN app.ledger_entries l ON l.payment_id=p.id ORDER BY p.id`);
   assert.deepEqual(q.rows.map(x=>[x.evidence_id,x.payment_id,x.ledger_id]),[['evidence-1','payment-1','ledger-1'],['evidence-2','payment-2','ledger-2']]);
   assert(q.rows.every((x,i)=>x.member_id===ids.member&&x.owner_user_id===ids.target&&x.linked_by===ids.target&&x.actor_user_id===ids.target&&x.created_at===`2026-01-01T00:00:0${i+1}.000Z`));
   assert.deepEqual((await admin.query('SELECT auth_id::text,user_id FROM private.auth_links')).rows,[{auth_id:ids.targetAuth,user_id:ids.target}]);
   assert.deepEqual(await importSyntheticFinancialGraph(p),{status:'already_applied'});
   assert.deepEqual(await reconcileSyntheticFinancialGraph(p),{status:'receipt_and_postimage_verified'});await clear();
  });
  await t.test('native posting facts must agree with the linked payment and transaction',async()=>{
   const original=(await admin.query("SELECT posting_facts FROM src.jobs WHERE source_id='sms-1'")).rows[0].posting_facts;
   const cases=[['event_kind','reversal'],['payment_outcome','failed'],['currency','USD'],['amount_minor',1],
    ['amount_minor','1250'],['source_mode','live'],['wallet_balance_after_minor',null],['wallet_balance_after_minor',-1],
    ['wallet_balance_after_minor',9007199254740992],['fee_minor',-1],['counterparty_name',{}],['transaction_at',false]];
   try{
    for(const [name,bad] of cases){const value=JSON.stringify({...original,[name]:bad});
     await admin.query("UPDATE src.jobs SET posting_facts=$1::jsonb WHERE source_id='sms-1'",[value]);await admin.query("UPDATE private.jobs SET posting_facts=$1::jsonb WHERE source_id='sms-1'",[value]);
     await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'),name);
    }
    const missing={...original};delete missing.provider_transaction_id;
    await admin.query("UPDATE src.jobs SET posting_facts=$1::jsonb WHERE source_id='sms-1'",[JSON.stringify(missing)]);await admin.query("UPDATE private.jobs SET posting_facts=$1::jsonb WHERE source_id='sms-1'",[JSON.stringify(missing)]);
    await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
    await admin.query("UPDATE src.jobs SET posting_facts=jsonb_set($1::jsonb,'{amount_minor}','1250.0'::jsonb) WHERE source_id='sms-1'",[JSON.stringify(original)]);
    await admin.query("UPDATE private.jobs SET posting_facts=jsonb_set($1::jsonb,'{amount_minor}','1250.0'::jsonb) WHERE source_id='sms-1'",[JSON.stringify(original)]);
    await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
   }finally{await admin.query("UPDATE src.jobs SET posting_facts=$1::jsonb WHERE source_id='sms-1'",[JSON.stringify(original)]);await admin.query("UPDATE private.jobs SET posting_facts=$1::jsonb WHERE source_id='sms-1'",[JSON.stringify(original)]);}
  });
  await t.test('native evidence is bound to the linked SMS body and reference',async()=>{
   const wrong='9'.repeat(64),body='1'.repeat(64),aad=sha=>'evidence:evidence-1:'+sha;
   try{
    await admin.query("UPDATE src.payment_evidence SET object_sha256=$1 WHERE id='evidence-1'",[wrong]);
    await admin.query("UPDATE src.object_proofs SET plaintext_sha256=$1,aad=$2 WHERE object_key='evidence/evidence-1'",[wrong,aad(wrong)]);
    await admin.query("UPDATE private.object_proofs SET plaintext_sha256=$1,aad=$2 WHERE object_key='evidence/evidence-1'",[wrong,aad(wrong)]);
    await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
    await admin.query("UPDATE src.payment_evidence SET object_sha256=$1,external_reference='wrong' WHERE id='evidence-1'",[body]);
    await admin.query("UPDATE src.object_proofs SET plaintext_sha256=$1,aad=$2 WHERE object_key='evidence/evidence-1'",[body,aad(body)]);
    await admin.query("UPDATE private.object_proofs SET plaintext_sha256=$1,aad=$2 WHERE object_key='evidence/evidence-1'",[body,aad(body)]);
    await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
   }finally{await admin.query("UPDATE src.payment_evidence SET object_sha256=$1,external_reference=$2 WHERE id='evidence-1'",[body,'sms:'+body+':sms-1']);
    await admin.query("UPDATE src.object_proofs SET plaintext_sha256=$1,aad=$2 WHERE object_key='evidence/evidence-1'",[body,aad(body)]);
    await admin.query("UPDATE private.object_proofs SET plaintext_sha256=$1,aad=$2 WHERE object_key='evidence/evidence-1'",[body,aad(body)]);}
  });
  await t.test('snapshots require attested complete history and consistent balances and timestamps',async()=>{
   try{
    await admin.query("UPDATE private.fixture_history_attestation SET no_prior_deletions=false WHERE collection_id=$1",[ids.collection]);
    await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
    await admin.query("UPDATE private.fixture_history_attestation SET no_prior_deletions=true WHERE collection_id=$1",[ids.collection]);
    await admin.query("UPDATE src.contribution_posting_snapshots SET posted_at='2099-01-01T00:00:00.000Z' WHERE ledger_entry_id='ledger-1'");
    await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
    await admin.query("UPDATE src.contribution_posting_snapshots SET posted_at='2026-01-01T00:00:01.000Z',member_balance_after_minor=0 WHERE ledger_entry_id='ledger-1'");
    await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
    await admin.query("UPDATE src.contribution_posting_snapshots SET member_balance_after_minor=1250,group_balance_after_minor=1251 WHERE ledger_entry_id='ledger-1'");
    await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
    await admin.query("UPDATE src.ledger_entries SET posted_at='2099-01-01T00:00:00.000Z' WHERE id='ledger-1';UPDATE src.contribution_posting_snapshots SET posted_at='2099-01-01T00:00:00.000Z',group_balance_after_minor=1250 WHERE ledger_entry_id='ledger-1'");
    await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
    await admin.query("UPDATE src.ledger_entries SET posted_at='2026-02-30T00:00:00.000Z' WHERE id='ledger-1';UPDATE src.contribution_posting_snapshots SET posted_at='2026-02-30T00:00:00.000Z' WHERE ledger_entry_id='ledger-1'");
    await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
   }finally{await admin.query("UPDATE private.fixture_history_attestation SET no_prior_deletions=true WHERE collection_id=$1",[ids.collection]);
    await admin.query("UPDATE src.ledger_entries SET posted_at='2026-01-01T00:00:01.000Z' WHERE id='ledger-1'");
    await admin.query("UPDATE src.contribution_posting_snapshots SET posted_at='2026-01-01T00:00:01.000Z',member_balance_after_minor=1250,group_balance_after_minor=1250 WHERE ledger_entry_id='ledger-1'");}
  });
  await t.test('ambiguous equal ledger timestamps are refused',async()=>{
   try{await admin.query("UPDATE src.ledger_entries SET posted_at='2026-01-01T00:00:01.000Z' WHERE id='ledger-2';UPDATE src.contribution_posting_snapshots SET posted_at='2026-01-01T00:00:01.000Z' WHERE ledger_entry_id='ledger-2'");
    await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
   }finally{await admin.query("UPDATE src.ledger_entries SET posted_at='2026-01-01T00:00:02.000Z' WHERE id='ledger-2';UPDATE src.contribution_posting_snapshots SET posted_at='2026-01-01T00:00:02.000Z' WHERE ledger_entry_id='ledger-2'");}
  });
  await t.test('distinct timestamps are not assumed to be commit order',async()=>{
   try{await admin.query("UPDATE src.ledger_entries SET posted_at=CASE id WHEN 'ledger-1' THEN '2026-01-01T00:00:04.000Z' ELSE '2026-01-01T00:00:03.000Z' END;UPDATE src.contribution_posting_snapshots SET posted_at=CASE ledger_entry_id WHEN 'ledger-1' THEN '2026-01-01T00:00:04.000Z' ELSE '2026-01-01T00:00:03.000Z' END");
    assert.equal((await captureSyntheticFinancialPlan(base())).writeAuthorized,false);
   }finally{await admin.query("UPDATE src.ledger_entries SET posted_at=CASE id WHEN 'ledger-1' THEN '2026-01-01T00:00:01.000Z' ELSE '2026-01-01T00:00:02.000Z' END;UPDATE src.contribution_posting_snapshots SET posted_at=CASE ledger_entry_id WHEN 'ledger-1' THEN '2026-01-01T00:00:01.000Z' ELSE '2026-01-01T00:00:02.000Z' END");}
  });
  await t.test('member balances are evaluated per member while group balances are shared',async()=>{
   try{
    await admin.query("INSERT INTO src.users VALUES('other-beneficiary',true);INSERT INTO app.users VALUES('other-beneficiary',true)");
    await admin.query("INSERT INTO src.memberships VALUES('membership-two',$1,'other-beneficiary')",[ids.collection]);await admin.query("INSERT INTO app.memberships VALUES('membership-two',$1,'other-beneficiary')",[ids.collection]);
    await admin.query("UPDATE src.payments SET member_id='other-beneficiary' WHERE id='payment-2';UPDATE src.momo_financial_links SET beneficiary_member_id='other-beneficiary' WHERE payment_id='payment-2';UPDATE src.ledger_entries SET member_id='other-beneficiary' WHERE payment_id='payment-2';UPDATE src.contribution_posting_snapshots SET member_balance_after_minor=2500 WHERE ledger_entry_id='ledger-2'");
    assert.equal((await captureSyntheticFinancialPlan(base())).writeAuthorized,false);
    await admin.query("UPDATE src.contribution_posting_snapshots SET member_balance_after_minor=3750 WHERE ledger_entry_id='ledger-2'");
    await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
   }finally{await admin.query("UPDATE src.payments SET member_id=$1 WHERE id='payment-2'",[ids.member]);await admin.query("UPDATE src.momo_financial_links SET beneficiary_member_id=$1 WHERE payment_id='payment-2'",[ids.member]);
    await admin.query("UPDATE src.ledger_entries SET member_id=$1 WHERE payment_id='payment-2'",[ids.member]);await admin.query("UPDATE src.contribution_posting_snapshots SET member_balance_after_minor=3750 WHERE ledger_entry_id='ledger-2'");
    await admin.query("DELETE FROM src.memberships WHERE id='membership-two';DELETE FROM app.memberships WHERE id='membership-two';DELETE FROM src.users WHERE id='other-beneficiary';DELETE FROM app.users WHERE id='other-beneficiary'");}
  });
  await t.test('missing graph, changed proof and unsafe source session fail closed',async()=>{
   await admin.query("DELETE FROM src.contribution_posting_snapshots WHERE ledger_entry_id='ledger-2'");
   await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
   await admin.query("INSERT INTO src.contribution_posting_snapshots VALUES('ledger-2','payment-2',3750,3750,'2026-01-01T00:00:02.000Z')");
   await admin.query("UPDATE private.object_proofs SET verified=false WHERE purpose='payment_evidence'");
   await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
   await admin.query("UPDATE private.object_proofs SET verified=true WHERE purpose='payment_evidence'");
   await admin.query("UPDATE src.sms_receipts SET originating_session_id='old-session' WHERE id='sms-1'");
   await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
   await admin.query("UPDATE src.sms_receipts SET originating_session_id=NULL WHERE id='sms-1'");
   await admin.query("UPDATE src.momo_transactions SET event_kind='reversal' WHERE id='txn-1';UPDATE app.momo_transactions SET event_kind='reversal' WHERE id='txn-1'");
   await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
   await admin.query("UPDATE src.momo_transactions SET event_kind='incoming_receipt' WHERE id='txn-1';UPDATE app.momo_transactions SET event_kind='incoming_receipt' WHERE id='txn-1'");
   await admin.query("UPDATE src.jobs SET state='pending' WHERE source_id='sms-1';UPDATE private.jobs SET state='pending' WHERE source_id='sms-1'");
   await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
   await admin.query("UPDATE src.jobs SET state='completed' WHERE source_id='sms-1';UPDATE private.jobs SET state='completed' WHERE source_id='sms-1'");assert.deepEqual(await counts(),[0,0,0,0,0]);
  });
  await t.test('changed source, identity, unsettled admissions and open fence stop the import',async()=>{
   const p=await capture();await admin.query("UPDATE src.payments SET payer_display_name='changed' WHERE id='payment-1'");
   await assert.rejects(importSyntheticFinancialGraph(p),code('preimage_changed'));await admin.query("UPDATE src.payments SET payer_display_name='' WHERE id='payment-1'");
   await admin.query("UPDATE private.fixture_admissions SET state='active'");await assert.rejects(importSyntheticFinancialGraph(p),code('identity_or_fence_changed'));
   await admin.query("UPDATE private.fixture_admissions SET state='settled';UPDATE private.fixture_fences SET mode='open' WHERE side='target'");await assert.rejects(importSyntheticFinancialGraph(p),code('identity_or_fence_changed'));
   await admin.query("UPDATE private.fixture_fences SET mode='fenced' WHERE side='target'");await admin.query('UPDATE app.users SET active=false WHERE id=$1',[ids.target]);
   await assert.rejects(importSyntheticFinancialGraph(p),code('identity_or_fence_changed'));await admin.query('UPDATE app.users SET active=true WHERE id=$1',[ids.target]);
  });
  await t.test('a beneficiary colliding with the cloud owner is never implicitly merged',async()=>{
   await admin.query('INSERT INTO src.users VALUES($1,true)',[ids.target]);
   await admin.query("INSERT INTO src.memberships VALUES('collision-member',$1,$2)",[ids.collection,ids.target]);
   await admin.query("INSERT INTO app.memberships VALUES('collision-member',$1,$2)",[ids.collection,ids.target]);
   await admin.query("UPDATE src.payments SET member_id=$1 WHERE id='payment-1'",[ids.target]);
   await admin.query("UPDATE src.momo_financial_links SET beneficiary_member_id=$1 WHERE payment_id='payment-1'",[ids.target]);
   await admin.query("UPDATE src.ledger_entries SET member_id=$1 WHERE payment_id='payment-1'",[ids.target]);
   await assert.rejects(captureSyntheticFinancialPlan(base()),code('financial_graph_refused'));
   await admin.query("UPDATE src.payments SET member_id=$1 WHERE id='payment-1'",[ids.member]);
   await admin.query("UPDATE src.momo_financial_links SET beneficiary_member_id=$1 WHERE payment_id='payment-1'",[ids.member]);
   await admin.query("UPDATE src.ledger_entries SET member_id=$1 WHERE payment_id='payment-1'",[ids.member]);
   await admin.query("DELETE FROM src.memberships WHERE id='collision-member';DELETE FROM app.memberships WHERE id='collision-member'");
   await admin.query('DELETE FROM src.users WHERE id=$1',[ids.target]);
  });
  await t.test('schema, filtering and fence-trigger drift fail closed',async()=>{
   const p=await capture();await admin.query('ALTER TABLE app.payment_evidence ADD COLUMN unsafe_extra text');
   await assert.rejects(importSyntheticFinancialGraph(p),code('fixture_schema_changed'));await admin.query('ALTER TABLE app.payment_evidence DROP COLUMN unsafe_extra');
   await admin.query('ALTER TABLE app.payment_evidence ADD COLUMN unsafe_both text;ALTER TABLE src.payment_evidence ADD COLUMN unsafe_both text');
   await assert.rejects(importSyntheticFinancialGraph(p),code('fixture_schema_changed'));await admin.query('ALTER TABLE app.payment_evidence DROP COLUMN unsafe_both;ALTER TABLE src.payment_evidence DROP COLUMN unsafe_both');
   await admin.query('ALTER TABLE src.payments ENABLE ROW LEVEL SECURITY');await assert.rejects(importSyntheticFinancialGraph(p),code('fixture_catalog_refused'));await admin.query('ALTER TABLE src.payments DISABLE ROW LEVEL SECURITY');
   await admin.query('ALTER TABLE app.payments DISABLE TRIGGER fixture_financial_guard');await assert.rejects(importSyntheticFinancialGraph(p),code('fixture_guard_changed'));await admin.query('ALTER TABLE app.payments ENABLE ALWAYS TRIGGER fixture_financial_guard');
   await admin.query("CREATE FUNCTION private.fixture_intruder() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RETURN NULL;END$$;CREATE TRIGGER fixture_intruder BEFORE INSERT ON app.payments FOR EACH STATEMENT EXECUTE FUNCTION private.fixture_intruder()");
   await assert.rejects(importSyntheticFinancialGraph(p),code('fixture_guard_changed'));await admin.query('DROP TRIGGER fixture_intruder ON app.payments;DROP FUNCTION private.fixture_intruder()');
   await admin.query('CREATE OR REPLACE FUNCTION app.json_valid(value text) RETURNS boolean LANGUAGE plpgsql IMMUTABLE STRICT AS $$BEGIN RETURN true;END$$');
   await assert.rejects(importSyntheticFinancialGraph(p),code('fixture_guard_changed'));
   const helper=fixtureSql.match(/CREATE FUNCTION app\.json_valid\(value text\)[\s\S]*?\$\$;/)?.[0];assert(helper);
   await admin.query(helper.replace('CREATE FUNCTION','CREATE OR REPLACE FUNCTION'));
  });
  await t.test('unexpected existing target data is not merged or overwritten',async()=>{
   const p=await capture();await admin.query('BEGIN');
   try{await admin.query("SELECT set_config('collect.fixture_financial_operation','fixture-existing',true)");
    await admin.query("INSERT INTO app.payment_evidence SELECT (jsonb_populate_record(NULL::app.payment_evidence,to_jsonb(s)||jsonb_build_object('owner_user_id',$1::text))).* FROM src.payment_evidence s WHERE id='evidence-1'",[ids.target]);await admin.query('COMMIT');}
   catch(e){await admin.query('ROLLBACK');throw e;}
   await assert.rejects(importSyntheticFinancialGraph(p),code('target_financial_conflict'));assert.deepEqual(await counts(),[1,0,0,0,0]);await clear();
  });
  await t.test('a late transaction error rolls back every inserted financial row',async()=>{
   const p=await capture();p.connect=async()=>{const c=await connect(),query=c.query.bind(c);c.query=async(sql,...args)=>{if(typeof sql==='string'&&sql.startsWith('INSERT INTO app.ledger_entries'))throw Error('synthetic-late-failure');return query(sql,...args);};return c;};
   await assert.rejects(importSyntheticFinancialGraph(p),code('fixture_transaction_failed'));assert.deepEqual(await counts(),[0,0,0,0,0]);assert.equal((await admin.query('SELECT count(*)::int n FROM private.fixture_financial_receipts')).rows[0].n,0);
  });
  await t.test('lost COMMIT acknowledgement requires read-only receipt reconciliation',async()=>{
   const p=await capture();p.connect=async()=>{const c=await connect(),query=c.query.bind(c);c.query=async(sql,...args)=>{const r=await query(sql,...args);if(sql==='COMMIT')throw Error('synthetic-lost-ack');return r;};return c;};
   assert.deepEqual(await importSyntheticFinancialGraph(p),{status:'commit_unconfirmed_do_not_retry'});p.connect=()=>connect();
   await admin.query("UPDATE src.payments SET payer_display_name='source-changed-after-commit' WHERE id='payment-1'");
   assert.deepEqual(await reconcileSyntheticFinancialGraph(p),{status:'receipt_and_postimage_verified'});assert.deepEqual(await counts(),[2,2,2,2,2]);
   await admin.query("UPDATE src.payments SET payer_display_name='' WHERE id='payment-1'");await clear();
  });
  await t.test('concurrent same-plan requests serialize into one import and one replay',async()=>{
   const p=await capture(),results=await Promise.all([importSyntheticFinancialGraph(p),importSyntheticFinancialGraph(p)]);
   assert.deepEqual(results.map(x=>x.status).sort(),['already_applied','applied']);assert.deepEqual(await counts(),[2,2,2,2,2]);await clear();
  });
  await t.test('reconciliation refuses an RLS-hidden extra payment and evidence graph',async()=>{
   const p=await capture();await importSyntheticFinancialGraph(p);await admin.query('BEGIN');
   try{await admin.query("SELECT set_config('collect.fixture_financial_operation','synthetic-extra',true)");
    await admin.query("INSERT INTO app.payment_evidence SELECT (jsonb_populate_record(NULL::app.payment_evidence,to_jsonb(s)||jsonb_build_object('id','unexpected-evidence','object_key','evidence/unexpected','external_reference','synthetic-extra-reference'))).* FROM app.payment_evidence s WHERE s.id='evidence-1'");
    await admin.query("INSERT INTO app.payments SELECT (jsonb_populate_record(NULL::app.payments,to_jsonb(s)||jsonb_build_object('id','unexpected-payment','evidence_id','unexpected-evidence'))).* FROM app.payments s WHERE s.id='payment-1'");await admin.query('COMMIT');}
   catch(e){await admin.query('ROLLBACK');await clear();throw e;}
   await admin.query("ALTER TABLE app.payment_evidence ENABLE ROW LEVEL SECURITY;CREATE POLICY fixture_hide_evidence ON app.payment_evidence FOR SELECT TO fixture_operator USING (id<>'unexpected-evidence');ALTER TABLE app.payments ENABLE ROW LEVEL SECURITY;CREATE POLICY fixture_hide_payment ON app.payments FOR SELECT TO fixture_operator USING (id<>'unexpected-payment')");
   try{const viewer=await connect();assert.equal((await viewer.query('SELECT count(*)::int n FROM app.payments')).rows[0].n,2);assert.deepEqual(await counts(),[3,3,2,2,2]);
    await assert.rejects(reconcileSyntheticFinancialGraph(p),code('fixture_catalog_refused'));
   }finally{await admin.query('DROP POLICY fixture_hide_evidence ON app.payment_evidence;ALTER TABLE app.payment_evidence DISABLE ROW LEVEL SECURITY;DROP POLICY fixture_hide_payment ON app.payments;ALTER TABLE app.payments DISABLE ROW LEVEL SECURITY');await clear();}
  });
  await t.test('reconciliation refuses RLS, inheritance, ownership, privilege and target-catalog drift',async()=>{
   const p=await capture();await importSyntheticFinancialGraph(p);
   try{
    for(const table of ['app.users','auth.users','private.auth_links','app.payment_evidence','app.payments','app.momo_financial_links','app.ledger_entries','app.contribution_posting_snapshots','private.fixture_financial_receipts']){
     await admin.query(`ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY;CREATE POLICY fixture_allow ON ${table} FOR SELECT TO fixture_operator USING (true)`);
     try{await assert.rejects(reconcileSyntheticFinancialGraph(p),code('fixture_catalog_refused'),table);}
     finally{await admin.query(`DROP POLICY fixture_allow ON ${table};ALTER TABLE ${table} DISABLE ROW LEVEL SECURITY`);}
    }
    await admin.query('ALTER TABLE app.payments ADD COLUMN synthetic_extra text');
    try{await assert.rejects(reconcileSyntheticFinancialGraph(p),code('fixture_schema_changed'));}finally{await admin.query('ALTER TABLE app.payments DROP COLUMN synthetic_extra');}
    await admin.query('CREATE TABLE app.synthetic_child (LIKE app.payments INCLUDING DEFAULTS INCLUDING CONSTRAINTS);ALTER TABLE app.synthetic_child INHERIT app.payments;GRANT SELECT ON app.synthetic_child TO fixture_operator');
    try{await assert.rejects(reconcileSyntheticFinancialGraph(p),code('fixture_catalog_refused'));}finally{await admin.query('DROP TABLE app.synthetic_child');}
    await admin.query('ALTER TABLE app.payments OWNER TO fixture_operator');
    try{await assert.rejects(reconcileSyntheticFinancialGraph(p),code('fixture_catalog_refused'));}finally{await admin.query('ALTER TABLE app.payments OWNER TO fixture_bootstrap;GRANT SELECT,UPDATE,INSERT ON app.payments TO fixture_operator');}
    await admin.query('REVOKE SELECT ON app.payments FROM fixture_operator');
    try{await assert.rejects(reconcileSyntheticFinancialGraph(p),code('fixture_catalog_refused'));}finally{await admin.query('GRANT SELECT ON app.payments TO fixture_operator');}
   }finally{await clear();}
  });
  await t.test('reconciliation locks target relations before its snapshot',async()=>{
   const p=await capture();await importSyntheticFinancialGraph(p);let release,locked;
   const gate=new Promise(r=>release=r),ready=new Promise(r=>locked=r);
   p.connect=async()=>{const c=await connect(),query=c.query.bind(c);c.query=async(sql,...args)=>{const r=await query(sql,...args);if(typeof sql==='string'&&sql.startsWith('LOCK TABLE app.users,auth.users,private.auth_links')){locked();await gate;}return r;};return c;};
   const running=reconcileSyntheticFinancialGraph(p);await ready;const writer=await connect('collect_financial_import_fixture','fixture_bootstrap');
   try{await writer.query("SET lock_timeout='150ms'");await assert.rejects(writer.query('ALTER TABLE app.payments ENABLE ROW LEVEL SECURITY'),e=>e.code==='55P03');}
   finally{release();}assert.deepEqual(await running,{status:'receipt_and_postimage_verified'});await clear();
  });
  await t.test('read-only reconciliation does not depend on source-row visibility',async()=>{
   const p=await capture();await importSyntheticFinancialGraph(p);await admin.query('ALTER TABLE src.payments ENABLE ROW LEVEL SECURITY');
   try{assert.deepEqual(await reconcileSyntheticFinancialGraph(p),{status:'receipt_and_postimage_verified'});}
   finally{await admin.query('ALTER TABLE src.payments DISABLE ROW LEVEL SECURITY');await clear();}
  });
  await t.test('reconciliation sees an RLS change committed while waiting for its locks',async()=>{
   const p=await capture();await importSyntheticFinancialGraph(p);const writer=await connect('collect_financial_import_fixture','fixture_bootstrap');
   let start;const waiting=new Promise(r=>start=r);let committed=false;
   try{await writer.query('BEGIN');await writer.query('ALTER TABLE app.payments ENABLE ROW LEVEL SECURITY');
    p.connect=async()=>{const c=await connect();await c.query("SET application_name='synthetic_financial_reconcile_wait'");const query=c.query.bind(c);c.query=(sql,...args)=>{if(typeof sql==='string'&&sql.startsWith('LOCK TABLE app.users,auth.users,private.auth_links'))start();return query(sql,...args);};return c;};
    const running=reconcileSyntheticFinancialGraph(p).then(value=>({value}),error=>({error}));await waiting;let observed=false;
    for(let i=0;i<50;i++){const q=await admin.query("SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE application_name='synthetic_financial_reconcile_wait' AND wait_event_type='Lock') AS waiting");if(q.rows[0].waiting){observed=true;break;}await new Promise(r=>setTimeout(r,20));}
    assert.equal(observed,true,'reconciler did not wait for the schema lock');await writer.query('COMMIT');committed=true;
    const result=await running;assert(code('fixture_catalog_refused')(result.error));
   }finally{if(!committed)try{await writer.query('ROLLBACK');}catch{}await admin.query('ALTER TABLE app.payments DISABLE ROW LEVEL SECURITY');await clear();}
  });
  await t.test('source and identity writes block while the import holds relation locks',async()=>{
   const p=await capture();let release,locked;const gate=new Promise(r=>release=r),ready=new Promise(r=>locked=r);
   p.connect=async()=>{const c=await connect(),query=c.query.bind(c);c.query=async(sql,...args)=>{const r=await query(sql,...args);if(typeof sql==='string'&&sql.startsWith('LOCK TABLE app.payment_evidence')){locked();await gate;}return r;};return c;};
   const running=importSyntheticFinancialGraph(p);await ready;
   const writer=await connect('collect_financial_import_fixture','fixture_bootstrap');
   try{await writer.query("SET lock_timeout='150ms'");await assert.rejects(writer.query("UPDATE src.payments SET payer_display_name='blocked' WHERE id='payment-1'"),e=>e.code==='55P03');await assert.rejects(writer.query('UPDATE app.users SET active=false WHERE id=$1',[ids.target]),e=>e.code==='55P03');}
   finally{release();}assert.equal((await running).status,'applied');await clear();
  });
  await t.test('a changed target postimage refuses reconciliation',async()=>{
   const p=await capture();await importSyntheticFinancialGraph(p);await admin.query("UPDATE app.payments SET payer_display_name='changed' WHERE id='payment-1'");
   await assert.rejects(reconcileSyntheticFinancialGraph(p),code('postimage_changed'));await clear();
  });
 }finally{for(const c of clients)try{await c.end();}catch{}await f.close();}
});

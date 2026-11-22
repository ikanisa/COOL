import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import pg from '../../../node_modules/pg/lib/index.js';
import {startOwnedPg17,resolvePg17Bin} from '../../test-support/owned-pg17.mjs';

const sql=await readFile(new URL('./diagnostic.sql',import.meta.url),'utf8');
const boundary=sql.indexOf('BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;');
assert.ok(boundary>0);const preflight=sql.slice(0,boundary),transaction=sql.slice(boundary);
const fixtureSql=await readFile(new URL('./fixture.sql',import.meta.url),'utf8');
const a='10000000-0000-4000-8000-000000000001';
async function within(p,ms){let timer;try{return await Promise.race([p.then(()=>true),new Promise(resolve=>{timer=setTimeout(()=>resolve(false),ms);})]);}finally{clearTimeout(timer);}}
async function closeClient(c){const stream=c?.connection?.stream;if(!stream){await within(Promise.resolve().then(()=>c.end()).catch(()=>{}),2000);return;}
 let done;const closed=new Promise(resolve=>{done=resolve;}),listener=()=>done();stream.once('close',listener);if(stream.closed)done();
 try{const end=Promise.resolve().then(()=>c.end()).catch(()=>{});if(!await within(Promise.all([end,closed]),2000)){
  stream.destroy();if(stream.closed)done();if(!await within(Promise.all([end,closed]),2000))throw Error('owned client closure unconfirmed');}}
 finally{stream.removeListener('close',listener);}}

test('selected native source prerequisites are aggregate-only on owned PostgreSQL 17',{timeout:120000},async t=>{
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap'});
 const c=new pg.Client({host:f.socket,port:f.port,database:'postgres',user:'fixture_bootstrap',connectionTimeoutMillis:3000});c.on('error',()=>{});
 const run=async()=>{await c.query(preflight);const result=await c.query(transaction),rows=(Array.isArray(result)?result:[result]).filter(x=>x.command==='SELECT');
  assert.equal(rows.length,1);assert.equal(rows[0].rows.length,1);const x=rows[0].rows[0].observation;
  assert.doesNotMatch(JSON.stringify(x),/10000000-0000|private-(?:account|payment)|a{64}|b{64}|c{64}|d{64}/);
  assert.equal(x.write_authorized,false);assert.equal(x.importer_qualified,false);return x;};
 try{await c.connect();await c.query(fixtureSql);
  await t.test('matching selected conditions and linked receipts are counted',async()=>{
   const x=await run();assert.equal(x.scope.sms_receipts,2);assert.equal(x.scope.within_synthetic_receipt_limit,true);
   assert.equal(x.scope.receipts_with_financial_link,2);assert.equal(x.selected_fields.all_selected_fields_satisfy,2);
   assert.equal(x.selected_fields.linked_receipts_all_selected_fields_satisfy,2);assert.equal(x.selected_fields.transaction_source_id_equal,2);
   assert.equal(x.selected_fields.job_origin_fingerprint_equal,2);assert.equal(x.selected_fields.wallet_supported,2);
  });
  await t.test('psql executes precheck and transaction on one physical session',async()=>{
   const result=spawnSync(join(resolvePg17Bin(),'psql'),['-X','-h',f.socket,'-p',String(f.port),'-U','fixture_bootstrap','-d','postgres','-qAt','-v','ON_ERROR_STOP=1','-f',fileURLToPath(new URL('./diagnostic.sql',import.meta.url))],
    {encoding:'utf8',timeout:10000,env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
   assert.equal(result.status,0,'psql diagnostic must succeed on its owned socket');const observation=JSON.parse(result.stdout);
   assert.equal(observation.format,'collect.native-sms-source-selected-fields.v3');assert.equal(observation.scope.sms_receipts,2);assert.equal(observation.write_authorized,false);
  });
  await t.test('different transaction/source IDs are visible even when the graph joins',async()=>{
   const other='30000000-0000-4000-8000-000000000001';
   for(const s of ['UPDATE app.momo_transactions SET id=$2 WHERE id=$1','UPDATE app.momo_transaction_sources SET transaction_id=$2 WHERE raw_sms_id=$1','UPDATE private.burimunsi_auto_sms_jobs SET transaction_id=$2 WHERE source_id=$1','UPDATE app.momo_financial_links SET transaction_id=$2 WHERE transaction_id=$1'])await c.query(s,[a,other]);
   try{const x=await run();assert.equal(x.selected_fields.transaction_source_id_mismatch,1);assert.equal(x.selected_fields.one_or_more_selected_fields_fail,1);}
   finally{await c.query('UPDATE app.momo_transactions SET id=$1 WHERE id=$2',[a,other]);await c.query('UPDATE app.momo_transaction_sources SET transaction_id=$1 WHERE raw_sms_id=$1',[a]);await c.query('UPDATE private.burimunsi_auto_sms_jobs SET transaction_id=$1 WHERE source_id=$1',[a]);await c.query('UPDATE app.momo_financial_links SET transaction_id=$1 WHERE transaction_id=$2',[a,other]);}
  });
  await t.test('fingerprint mismatch and missing fingerprint are distinct',async()=>{
   await c.query("UPDATE private.burimunsi_auto_sms_jobs SET source_fingerprint=repeat('f',64) WHERE source_id=$1",[a]);
   try{const x=await run();assert.equal(x.selected_fields.job_origin_fingerprint_mismatch,1);assert.equal(x.selected_fields.job_origin_fingerprint_unknown,0);}
   finally{await c.query("UPDATE private.burimunsi_auto_sms_jobs SET source_fingerprint=repeat('c',64) WHERE source_id=$1",[a]);}
   await c.query('UPDATE private.burimunsi_auto_sms_jobs SET source_fingerprint=NULL WHERE source_id=$1',[a]);
   try{const x=await run();assert.equal(x.selected_fields.job_origin_fingerprint_unknown,1);assert.equal(x.selected_fields.job_origin_fingerprint_mismatch,0);}
   finally{await c.query("UPDATE private.burimunsi_auto_sms_jobs SET source_fingerprint=repeat('c',64) WHERE source_id=$1",[a]);}
  });
  await t.test('transaction conflict and nonlinked allocation are reported independently',async()=>{
   await c.query("UPDATE app.momo_transactions SET has_conflict=1,allocation_state='needs_review' WHERE id=$1",[a]);
   try{const x=await run();assert.equal(x.selected_fields.has_conflict_nonzero,1);assert.equal(x.selected_fields.allocation_not_linked,1);assert.equal(x.selected_fields.one_or_more_selected_fields_fail,1);}
   finally{await c.query("UPDATE app.momo_transactions SET has_conflict=0,allocation_state='linked' WHERE id=$1",[a]);}
  });
  await t.test('wallet missing/null differs from wrong type, negative and overflow',async()=>{
   for(const bad of ['-1','9007199254740992','1.5','"1"']){
    await c.query("UPDATE private.burimunsi_auto_sms_jobs SET posting_facts=jsonb_set(posting_facts,'{wallet_balance_after_minor}',$2::jsonb) WHERE source_id=$1",[a,bad]);
    const x=await run();assert.equal(x.selected_fields.wallet_unsupported,1);assert.equal(x.selected_fields.wallet_unknown,0);
   }
   for(const value of ['null','missing']){
    await c.query(value==='missing'?"UPDATE private.burimunsi_auto_sms_jobs SET posting_facts=posting_facts-'wallet_balance_after_minor' WHERE source_id=$1":"UPDATE private.burimunsi_auto_sms_jobs SET posting_facts=jsonb_set(posting_facts,'{wallet_balance_after_minor}','null') WHERE source_id=$1",[a]);
    const x=await run();assert.equal(x.selected_fields.wallet_unknown,1);assert.equal(x.selected_fields.wallet_unsupported,0);
   }
   await c.query("UPDATE private.burimunsi_auto_sms_jobs SET posting_facts=jsonb_set(posting_facts,'{wallet_balance_after_minor}','0') WHERE source_id=$1",[a]);
  });
  await t.test('accepted relation and parse linkage changes are identified',async()=>{
   await c.query("UPDATE app.momo_transaction_sources SET relation='conflict' WHERE raw_sms_id=$1",[a]);await c.query("UPDATE private.burimunsi_auto_sms_jobs SET attempt_id='00000000-0000-0000-0000-000000000002' WHERE source_id=$1",[a]);
   try{const x=await run();assert.equal(x.selected_fields.source_job_relation_not_accepted,1);assert.equal(x.selected_fields.attempt_or_receipt_link_mismatch,1);}
   finally{await c.query("UPDATE app.momo_transaction_sources SET relation='accepted' WHERE raw_sms_id=$1",[a]);await c.query("UPDATE private.burimunsi_auto_sms_jobs SET attempt_id='00000000-0000-0000-0000-000000000001' WHERE source_id=$1",[a]);}
  });
  await t.test('invalid source ID format and mismatched job facts remain selected failures',async()=>{
   await c.query("UPDATE private.burimunsi_auto_sms_jobs SET transaction_id='different',posting_facts=jsonb_set(posting_facts,'{source_mode}','\"catch_up\"') WHERE source_id=$1",[a]);
   try{const x=await run();assert.equal(x.selected_fields.job_transaction_mismatch,1);assert.equal(x.selected_fields.selected_job_facts_mismatch,1);assert.equal(x.selected_fields.one_or_more_selected_fields_fail,1);}
   finally{await c.query("UPDATE private.burimunsi_auto_sms_jobs SET transaction_id=$1,posting_facts=jsonb_set(posting_facts,'{source_mode}','\"live\"') WHERE source_id=$1",[a]);}
   await c.query("UPDATE app.sms_receipts SET id='synthetic-non-uuid' WHERE id=$1",[a]);
   try{const x=await run();assert.equal(x.selected_fields.source_uuid_format_unsupported,1);assert.equal(x.selected_fields.transaction_source_id_unknown,1);}
   finally{await c.query("UPDATE app.sms_receipts SET id=$1 WHERE id='synthetic-non-uuid'",[a]);}
  });
  await t.test('missing or multiple candidate paths remain unknown',async()=>{
   await c.query('INSERT INTO app.momo_transaction_sources SELECT * FROM app.momo_transaction_sources WHERE raw_sms_id=$1',[a]);
   try{const x=await run();assert.equal(x.scope.receipts_with_multiple_joined_paths,1);assert.equal(x.selected_fields.selected_fields_unknown,1);assert.equal(x.selected_fields.job_origin_fingerprint_unknown,1);}
   finally{await c.query('DELETE FROM app.momo_transaction_sources WHERE ctid IN (SELECT ctid FROM app.momo_transaction_sources WHERE raw_sms_id=$1 LIMIT 1)',[a]);}
   await c.query('DELETE FROM private.burimunsi_auto_sms_jobs WHERE source_id=$1',[a]);
   try{const x=await run();assert.equal(x.selected_fields.job_origin_fingerprint_unknown,1);assert.equal(x.selected_fields.wallet_unknown,1);assert.equal(x.selected_fields.selected_fields_unknown,1);}
   finally{await c.query(`INSERT INTO private.burimunsi_auto_sms_jobs VALUES($1,$1,repeat('c',64),'accepted','completed','successful',
    '00000000-0000-0000-0000-000000000001','private-account','{"event_kind":"incoming_receipt","payment_outcome":"successful","currency":"RWF","amount_minor":10,"source_mode":"live","wallet_balance_after_minor":0}')`,[a]);}
  });
  await t.test('financial-link absence does not imply an unknown or missing receipt',async()=>{
   await c.query('DELETE FROM app.momo_financial_links WHERE transaction_id=$1',[a]);
   try{const x=await run();assert.equal(x.scope.receipts_without_financial_link,1);assert.equal(x.selected_fields.all_selected_fields_satisfy,2);assert.equal(x.selected_fields.linked_receipts_all_selected_fields_satisfy,1);}
   finally{await c.query("INSERT INTO app.momo_financial_links VALUES($1,'private-payment-a')",[a]);}
  });
  await t.test('precheck and locked transaction must use the same database session',async()=>{
   const fresh=()=>new pg.Client({host:f.socket,port:f.port,database:'postgres',user:'fixture_bootstrap',connectionTimeoutMillis:3000});
   const one=fresh(),two=fresh();one.on('error',()=>{});two.on('error',()=>{});
   try{await one.connect();await two.connect();await one.query(preflight);
    await assert.rejects(two.query(transaction),e=>e.code==='55000'&&e.message==='native_source_session_refused');await two.query('ROLLBACK');}
   finally{await closeClient(one);await closeClient(two);}
  });
  await t.test('concurrent committed inheritance and RLS are visible after the relation lock',async()=>{
   await c.query('CREATE ROLE native_readiness_race_reader LOGIN; GRANT USAGE ON SCHEMA app,private TO native_readiness_race_reader; GRANT SELECT ON ALL TABLES IN SCHEMA app,private TO native_readiness_race_reader');
   for(const scenario of ['inheritance','row_security']){
    const reader=new pg.Client({host:f.socket,port:f.port,database:'postgres',user:'native_readiness_race_reader',connectionTimeoutMillis:3000});reader.on('error',()=>{});let pending;
    try{await reader.connect();const pid=(await reader.query('SELECT pg_backend_pid() pid')).rows[0].pid;
     await c.query('BEGIN; LOCK TABLE app.sms_receipts IN ACCESS EXCLUSIVE MODE');
     await c.query(scenario==='inheritance'?'CREATE TABLE app.sms_receipts_race_child() INHERITS(app.sms_receipts)':'ALTER TABLE app.sms_receipts ENABLE ROW LEVEL SECURITY');
     await reader.query(preflight);let settled=false;
     pending=reader.query(transaction).then(()=>({accepted:true}),error=>({error})).then(x=>(settled=true,x));
     let waiting=false;for(let i=0;i<120;i++){
      const q=await c.query("SELECT wait_event_type='Lock' AS waiting FROM pg_stat_activity WHERE pid=$1",[pid]);
      if(q.rows[0]?.waiting){waiting=true;break}if(settled)break;await new Promise(resolve=>setTimeout(resolve,25));
     }
     assert.equal(waiting,true,'diagnostic must wait for the concurrent DDL lock');await c.query('COMMIT');
     const result=await pending;assert.equal(result.accepted,undefined);assert.equal(result.error?.code,'42501');assert.equal(result.error?.message,'native_source_visibility_refused');
    }finally{
     await c.query('ROLLBACK').catch(()=>{});if(pending)await pending;await reader.query('ROLLBACK').catch(()=>{});await closeClient(reader);
     if(scenario==='inheritance')await c.query('DROP TABLE IF EXISTS app.sms_receipts_race_child');else await c.query('ALTER TABLE app.sms_receipts DISABLE ROW LEVEL SECURITY');
    }
   }
  });
  await t.test('restricted RLS, missing access, inheritance and missing columns refuse observation',async()=>{
   await c.query('CREATE ROLE native_readiness_reader; GRANT USAGE ON SCHEMA app,private TO native_readiness_reader; GRANT SELECT ON ALL TABLES IN SCHEMA app,private TO native_readiness_reader; ALTER TABLE app.sms_receipts ENABLE ROW LEVEL SECURITY; SET ROLE native_readiness_reader');
   try{await assert.rejects(run(),e=>e.code==='42501');}finally{await c.query('ROLLBACK; RESET ROLE; ALTER TABLE app.sms_receipts DISABLE ROW LEVEL SECURITY');}
   await c.query('REVOKE SELECT ON app.momo_transactions FROM native_readiness_reader; SET ROLE native_readiness_reader');
   try{await assert.rejects(run(),e=>e.code==='42501');}finally{await c.query('ROLLBACK; RESET ROLE');}
   await c.query('CREATE TABLE app.sms_receipts_child() INHERITS(app.sms_receipts)');
   try{await assert.rejects(run(),e=>e.code==='42501'&&e.message==='native_source_visibility_refused');}finally{await c.query('ROLLBACK; DROP TABLE app.sms_receipts_child');}
   await c.query('ALTER TABLE app.momo_transactions DROP COLUMN has_conflict');
   try{await assert.rejects(run(),e=>e.code==='55000'&&e.message==='native_source_columns_refused');}finally{await c.query('ROLLBACK');}
  });
 }finally{try{await closeClient(c);}finally{const closed=await f.close();assert.equal(closed.removed,true);}}
});

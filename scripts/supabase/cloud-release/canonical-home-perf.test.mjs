import assert from 'node:assert/strict';
import {performance} from 'node:perf_hooks';
import {createRequire} from 'node:module';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {PostgresRecordsStore} from '../../../supabase/functions/_shared/domain/burimunsi/postgres-records-store.js';
const pg=createRequire(import.meta.url)('pg');

async function recentSql(auto) {
  let recent;
  const sql={unsafe:async(query,args)=>{
    if(query.startsWith('SELECT coalesce(sum(amount_minor)')) return [{balance:0}];
    if(query.startsWith('SELECT coalesce(sum(c.credited_amount)')) return [{today:0}];
    if(query.includes(' AS unallocated_amount')) return [{members:0,unallocated:0,unallocated_amount:0}];
    recent={query,args}; return [];
  }};
  const store=new PostgresRecordsStore({authority:{groupId:'group',read:fn=>fn(sql),session:async()=>null},
    sourceReader:{revision:async()=>'',page:async()=>null,detail:async()=>null},
    clock:()=>Date.parse('2026-11-18T00:00:00Z'),nativeAutoRecordsEnabled:auto});
  await store.withReadSnapshot(tx=>tx.canonicalHome('group'));
  assert.ok(recent); return recent;
}

// Derive the exact prior join order from the actual current generated query;
// every field, predicate and role-aware projection is otherwise identical.
async function queryPair(auto){
 const candidate=await recentSql(auto),q=candidate.query;
 const prefix='WITH credited AS MATERIALIZED (',separator=')\n            SELECT q.*,c.credited_amount FROM credited c\n            JOIN LATERAL (',suffix=' AND t.id=c.transaction_id OFFSET 0) q ON true\n            WHERE CASE';
 assert.ok(q.startsWith(prefix));const s=q.indexOf(separator,prefix.length),e=q.indexOf(suffix,s+separator.length);assert.ok(s>0&&e>s);
 const credited=q.slice(prefix.length,s),payments=q.slice(s+separator.length,e);
 const original={...candidate,query:'SELECT q.*,c.credited_amount FROM ('+payments+') q JOIN ('+credited+') c ON c.transaction_id=q.id\n            WHERE CASE'+q.slice(e+suffix.length)};
 return {original,candidate};
}
const {original,candidate}=await queryPair(true);
const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_home_perf_fixture'});
const db=new pg.Client({host:f.socket,port:f.port,database:'postgres',user:'fixture_bootstrap'});
try {
  await db.connect();
  const identity=(await db.query("SELECT current_setting('cluster_name') name,inet_server_addr() IS NULL socket")).rows[0];
  assert.deepEqual(identity,{name:'collect_home_perf_fixture',socket:true});
  await db.query(`CREATE SCHEMA app; CREATE SCHEMA private;
   CREATE TABLE private.burimunsi_transaction_scopes(collection_id text,transaction_id text,receiving_account_id text,native_source_id text);
   CREATE TABLE app.momo_transactions(id text PRIMARY KEY,receiving_account_id text,payer_name text,payer_identifier text,
     amount_minor bigint,transaction_at text,transaction_timezone text,transaction_datetime_raw text,provider_transaction_id text,
     allocation_state text,has_conflict integer,version bigint,created_at text,event_kind text,fee_minor bigint,wallet_balance_after_minor bigint);
   CREATE TABLE app.momo_financial_links(transaction_id text,payment_id text,beneficiary_member_id text);
   CREATE TABLE app.payments(id text,collection_id text,status text,amount_minor bigint,evidence_id text,member_id text);
   CREATE TABLE app.memberships(collection_id text,user_id text);
   CREATE TABLE app.users(id text,full_name text,momo_number text);
   CREATE TABLE app.ledger_entries(payment_id text,collection_id text,kind text,amount_minor bigint,evidence_id text,member_id text);
   CREATE TABLE app.momo_transaction_sources(transaction_id text,raw_sms_id text,relation text);
   CREATE SEQUENCE private.projection_calls;
   CREATE FUNCTION private.burimunsi_auto_projection(p_source text) RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
   BEGIN
     PERFORM nextval('private.projection_calls'); PERFORM pg_sleep(0.004);
     IF current_setting('fixture.role',true)='denied' THEN RAISE EXCEPTION 'projection_denied' USING ERRCODE='42501'; END IF;
     RETURN jsonb_build_object('sourceId',p_source,'outcome','successful',
       'canReveal',current_setting('fixture.role',true)='admin',
       'facts',CASE WHEN p_source='source-1' THEN jsonb_build_object('transaction_at','2026-11-17T23:00:00Z')
         WHEN p_source='source-8' THEN jsonb_build_object('transaction_at','invalid-time') ELSE '{}'::jsonb END);
   END $$;
   INSERT INTO app.users VALUES('member','Synthetic member','0780000001');
   INSERT INTO app.memberships VALUES('group','member');
   INSERT INTO app.momo_transactions
    SELECT 'transaction-'||i,'wallet','Synthetic','masked',100+i,'2026-11-17T08:00:00Z','Africa/Kigali','synthetic','ref-'||i,
      'unallocated',0,1,'synthetic','incoming_receipt',0,NULL FROM generate_series(1,37) i;
   INSERT INTO private.burimunsi_transaction_scopes
    SELECT 'group','transaction-'||i,'wallet','source-'||i FROM generate_series(1,37) i;
   INSERT INTO app.momo_financial_links SELECT 'transaction-'||i,'payment-'||i,'member' FROM generate_series(1,11) i;
   INSERT INTO app.payments SELECT 'payment-'||i,'group','confirmed',100+i,'evidence-'||i,'member' FROM generate_series(1,11) i;
   INSERT INTO app.ledger_entries SELECT 'payment-'||i,'group','contribution',100+i,'evidence-'||i,'member' FROM generate_series(1,11) i;
   INSERT INTO app.momo_transaction_sources SELECT 'transaction-'||i,'source-'||i,'accepted' FROM generate_series(1,37) i;`);
  async function run(input,role){
    await db.query("SELECT set_config('fixture.role',$1,false)",[role]);
    await db.query('ALTER SEQUENCE private.projection_calls RESTART WITH 1');
    const start=performance.now();const rows=(await db.query(input.query,input.args)).rows;
    const elapsedMs=Math.round(performance.now()-start);
    const seq=(await db.query('SELECT last_value,is_called FROM private.projection_calls')).rows[0];
    return {rows,elapsedMs,calls:seq.is_called?Number(seq.last_value):0};
  }
  const result=[];
  for(const role of ['staff','admin']){
    const before=await run(original,role),after=await run(candidate,role);
    assert.deepEqual(after.rows,before.rows);
    assert.equal(before.rows.length,3);assert.equal(before.rows[0].id,'transaction-1');
    assert.equal(before.rows[0].native_meta.canReveal,role==='admin');
    result.push({role,rows:before.rows.length,originalProjectionCalls:before.calls,candidateProjectionCalls:after.calls,
      originalMs:before.elapsedMs,candidateMs:after.elapsedMs});
  }
  // Alter independent credit predicates; the candidate must not invent a
  // credit when a conflict, status, amount, beneficiary or lineage disagrees.
  await db.query(`UPDATE app.momo_transactions SET has_conflict=1 WHERE id='transaction-2';
   UPDATE app.ledger_entries SET amount_minor=999 WHERE payment_id='payment-3';
   UPDATE app.payments SET status='reversed' WHERE id='payment-4';
   UPDATE app.payments SET member_id='unregistered' WHERE id='payment-5';
   UPDATE app.momo_financial_links SET beneficiary_member_id='unregistered' WHERE payment_id='payment-5';
   UPDATE app.ledger_entries SET member_id='unregistered' WHERE payment_id='payment-5';
   UPDATE app.payments SET status='corrected' WHERE id='payment-6';
   INSERT INTO app.momo_financial_links VALUES('transaction-7','payment-7','member');
   UPDATE private.burimunsi_transaction_scopes SET native_source_id=NULL WHERE transaction_id='transaction-9';
   INSERT INTO private.burimunsi_transaction_scopes VALUES('different-group','transaction-10','wallet','source-10');`);
  for(const role of ['staff','admin']){
    const before=await run(original,role),after=await run(candidate,role);
    assert.deepEqual(after.rows,before.rows);
    assert.equal(before.rows[0].id,'transaction-1');
    assert.ok(after.rows.some(row=>row.id==='transaction-9'&&row.native_source_id===null));
    assert.ok(after.rows.every(row=>!['transaction-2','transaction-3','transaction-4','transaction-5',
      'transaction-6','transaction-7','transaction-8'].includes(row.id)));
    result.push({role:role+'-credit-negative-cases',rows:after.rows.length,originalProjectionCalls:before.calls,
      candidateProjectionCalls:after.calls,originalMs:before.elapsedMs,candidateMs:after.elapsedMs});
  }
  await assert.rejects(()=>run(original,'denied'),e=>e.code==='42501'&&e.message==='projection_denied');
  await assert.rejects(()=>run(candidate,'denied'),e=>e.code==='42501'&&e.message==='projection_denied');
  // The non-native mode retains exactly the same credit rows as well.
  const managed=await queryPair(false);
  const managedBefore=await run(managed.original,'staff'),managedAfter=await run(managed.candidate,'staff');
  assert.deepEqual(managedAfter.rows,managedBefore.rows);assert.equal(managedAfter.calls,0);
  result.push({role:'managed-without-native-projection',rows:managedAfter.rows.length,originalProjectionCalls:managedBefore.calls,candidateProjectionCalls:managedAfter.calls});
  // No credited records: previously projected native rows must not become credits.
  await db.query("UPDATE app.payments SET status='reversed'");
  const before=await run(original,'staff'),after=await run(candidate,'staff');
  assert.deepEqual(after.rows,before.rows);assert.equal(after.rows.length,0);
  result.push({role:'staff-no-credits',rows:0,originalProjectionCalls:before.calls,candidateProjectionCalls:after.calls,
    originalMs:before.elapsedMs,candidateMs:after.elapsedMs});
  console.log(JSON.stringify({status:'PASS',fixture:'owned-socket-only-pg17',synthetic:true,result,productionDispatched:false}));
} finally {await db.end().catch(()=>{});const x=await f.close();assert.equal(x.removed,true);}

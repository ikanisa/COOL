import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {join} from 'node:path';
import { test } from 'node:test';
import pg from '../node_modules/pg/lib/index.js';
import { startOwnedPg17 } from '../current-pg-transfer/test-support/owned-pg17.mjs';

const {Client} = pg;

const migrations = await Promise.all([
  '20261118090305_burimunsi_automatic_payment_sms.sql',
  '20261119041100_burimunsi_payment_sms_status.sql',
  '20261119114600_burimunsi_admin_sms_health.sql',
  '20261119114700_collect_payment_display_reference.sql',
].map(name => readFile(new URL('../../../supabase/migrations/' + name, import.meta.url), 'utf8')));
const id = (n) => `10000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const group = id(1), member = id(2), app = 'app_' + id(3);
const phone = '+250788000001', hash = 'a'.repeat(64);

async function fixture(t) {
  const cluster = await startOwnedPg17({prefix: 'collect-pg-transfer-', initialUser: 'collect_fixture'});
  const client = new Client({host:cluster.socket, port:cluster.port, database:'postgres', user:cluster.initialUser});
  t.after(async () => {
    try { await client.end(); } finally { await cluster.close(); }
  });
  await client.connect();
  const query = (sql, args) => client.query(sql, args);
  const db = {exec: query, query, async transaction(run) {
    await query('BEGIN');
    try { const result = await run(db); await query('COMMIT'); return result; }
    catch(error) { await query('ROLLBACK'); throw error; }
  }};
  await db.exec(`
    CREATE ROLE postgres SUPERUSER;
    SET ROLE postgres;
    CREATE ROLE collect_runtime;
    CREATE ROLE anon;
    CREATE ROLE authenticated;
    CREATE ROLE service_role;
    CREATE ROLE collect_importer;
    CREATE SCHEMA app;
    CREATE SCHEMA private;
    GRANT USAGE ON SCHEMA private TO collect_runtime, anon;
    CREATE TABLE private.collect_fence_control(singleton boolean,mode text);
    INSERT INTO private.collect_fence_control VALUES(true,'fenced');
    CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE sql AS $$SELECT$$;
    CREATE FUNCTION private.burimunsi_auto_jobs_guard() RETURNS void LANGUAGE plpgsql AS $$
    BEGIN
      IF current_setting('role',true)<>'collect_runtime' OR current_setting('test.work_kind',true) IS DISTINCT FROM 'jobs' THEN
        RAISE EXCEPTION 'jobs work required' USING ERRCODE='42501';
      END IF;
    END$$;
    CREATE FUNCTION private._collect_fence_statement() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RETURN NULL; END$$;
    CREATE FUNCTION private.managed_phone_binding(text,text,text) RETURNS boolean LANGUAGE sql AS $$SELECT false$$;
    CREATE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE
      SET search_path=pg_catalog,pg_temp AS $$SELECT '{"private_classes":[]}'::jsonb$$;
    CREATE FUNCTION private.retention_capture_inventory_v2(p_operation uuid,p_request text,p_review bigint,p_source text,p_max_rows integer DEFAULT 1000000)
      RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
      BEGIN RETURN jsonb_build_array('private:burimunsi_observation_retry_commands','managed:storage_iceberg'); END$$;
    REVOKE ALL ON FUNCTION private._retention_manifest_catalog_v2(),private.retention_capture_inventory_v2(uuid,text,bigint,text,integer) FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION private.retention_capture_inventory_v2(uuid,text,bigint,text,integer) TO collect_runtime;
    CREATE TABLE app.collections(id text PRIMARY KEY,status text);
    CREATE TABLE app.users(id text PRIMARY KEY,access_status text,member_type text,momo_number text);
    CREATE TABLE app.memberships(collection_id text,user_id text,active bigint);
    CREATE TABLE app.payments(id text PRIMARY KEY,collection_id text,member_id text,amount_minor bigint,
      currency text,status text,rail text,evidence_id text);
    CREATE TABLE app.ledger_entries(id text PRIMARY KEY,payment_id text,collection_id text,member_id text,
      kind text,amount_minor bigint,currency text,evidence_id text,posted_at text,reverses_entry_id text);
    CREATE TABLE app.contribution_posting_snapshots(payment_id text,ledger_entry_id text,posted_at text,member_balance_after_minor bigint);
    CREATE TABLE app.momo_financial_links(payment_id text,transaction_id text,beneficiary_member_id text,historical_existing bigint);
    CREATE TABLE app.momo_transactions(id text PRIMARY KEY,mode text,event_kind text,allocation_state text,has_conflict bigint,
      currency text,amount_minor bigint,receiving_account_id text,payer_identifier text,transaction_at text,
      original_transaction_id text,provider_transaction_id text,transaction_time_source text);
    CREATE TABLE private.burimunsi_transaction_scopes(transaction_id text,collection_id text,receiving_account_id text,native_source_id text,policy_version text);
    CREATE TABLE app.assisted_sms_authorizations(collection_id text,recipient_user_id text,destination_sha256 text,
      consent_revision bigint,enabled bigint,phone_verification_challenge_id text);
    CREATE TABLE app.notification_preferences(user_id text,payment_updates bigint);
    CREATE TABLE app.notification_events(id text PRIMARY KEY,user_id text,event_type text,data_json text,created_at text);
    CREATE TABLE app.privacy_retention_barriers(subject_id text);
    CREATE TABLE app.admin_grants(user_id text,permission text);
    CREATE TABLE app.admin_account_role_capabilities(role text,permission text);
    CREATE TABLE private.burimunsi_operator_approvals(collection_id text,principal_user_id text,admin_user_id text,
      active boolean,capabilities text[],phone text,role text);
    CREATE TABLE private.burimunsi_auto_sms_jobs(source_id text,collection_id text,transaction_id text,state text,
      relation text,attempt_count integer,posting_failure_count integer,posting_next_attempt_at bigint,created_at bigint);
    CREATE TABLE private.burimunsi_unresolved_observations(source_id text,collection_id text,created_at bigint);
    CREATE FUNCTION private._collect_fence_require_runtime() RETURNS void LANGUAGE plpgsql AS $$BEGIN
      IF current_setting('role',true) IS DISTINCT FROM 'collect_runtime' OR
         current_setting('test.work_kind',true) IS DISTINCT FROM 'http_admin'
      THEN RAISE EXCEPTION 'Admin runtime required' USING ERRCODE='42501'; END IF;
    END$$;
    CREATE FUNCTION private.burimunsi_managed_admin_snapshot() RETURNS TABLE(
      principal_user_id text,admin_id text,surface text,shared_role text) LANGUAGE sql
      AS $$SELECT 'principal','admin','admin','owner' WHERE current_setting('test.identity',true)='owner'$$;
    CREATE FUNCTION private.assert_actor(text,text,text,bigint,bigint) RETURNS text LANGUAGE plpgsql AS $$BEGIN
      IF NOT EXISTS(SELECT 1 FROM app.admin_grants WHERE user_id='principal' AND permission=$1)
        THEN RAISE EXCEPTION 'permission denied' USING ERRCODE='42501'; END IF;
      RETURN 'principal';
    END$$;
    CREATE FUNCTION private.burimunsi_pin_root_snapshot(text,text,text,text,text[]) RETURNS jsonb LANGUAGE sql
      AS $$SELECT '{}'::jsonb WHERE EXISTS(SELECT 1 FROM app.collections WHERE id=$1 AND status='active')$$;
    GRANT USAGE ON SCHEMA app TO collect_runtime;
    GRANT SELECT,INSERT,UPDATE ON app.payments TO collect_runtime;
    INSERT INTO app.payments(id,amount_minor) VALUES('historical-payment',1);
  `);
  for (const migration of migrations) await db.exec(migration);
  const enabledAt = new Date(Date.now() - 60_000).toISOString();
  await db.query("INSERT INTO app.collections VALUES($1,'active')", [group]);
  await db.query("INSERT INTO app.users VALUES($1,'active','direct',$2)", [member, phone]);
  await db.query('INSERT INTO app.memberships VALUES($1,$2,1)', [group, member]);
  async function record(seed, { payer = '0788 000 001', mode = 'live', age = 10_000, postedAge = 5_000 } = {}) {
    const pay = id(seed), entry = id(seed + 1), source = id(seed + 2), event = id(seed + 3);
    const observed = new Date(Date.now() - age).toISOString();
    const posted = new Date(Date.now() - postedAge).toISOString();
    await db.query("INSERT INTO app.payments VALUES($1,$2,$3,125,'RWF','reconciled','rwanda_momo','evidence')", [pay, group, member]);
    await db.query("INSERT INTO app.ledger_entries VALUES($1,$2,$3,$4,'contribution',125,'RWF','evidence',$5,NULL)", [entry, pay, group, member, posted]);
    await db.query('INSERT INTO app.contribution_posting_snapshots VALUES($1,$2,$3,765)', [pay, entry, posted]);
    await db.query('INSERT INTO app.momo_financial_links VALUES($1,$2,$3,0)', [pay, source, member]);
    await db.query(
      "INSERT INTO app.momo_transactions VALUES($1,$2,'incoming_receipt','linked',0,'RWF',125,'wallet',$3,$4,NULL,$1,'sms_body_and_provider_profile')",
      [source, mode, payer, observed],
    );
    await db.query("INSERT INTO private.burimunsi_transaction_scopes VALUES($1,$2,'wallet',$1,'native.auto.v1')", [source, group]);
    await db.query("INSERT INTO app.notification_events VALUES($1,$2,'contribution',$3,$4)", [event, member, JSON.stringify({
      payment_id: pay, collection_id: group, amount_rwf: 125, member_balance_after_contribution_rwf: 765,
      group_balance_after_contribution_rwf: 10000, group_name: 'Test savings group', posted_at: posted,
      balance_basis: 'after_this_contribution',
    }), posted]);
    return {pay, entry, posted};
  }
  function rpc(fn, parameters, casts, kind = 'jobs', role = 'collect_runtime') {
    return db.transaction(async (tx) => {
      await tx.exec(`SET LOCAL ROLE ${role}; SET LOCAL collect.edge_verified='true'; SET LOCAL test.work_kind='${kind}';`);
      const args = casts.map((cast, i) => `$${i + 1}::${cast}`).join(',');
      return (await tx.query(`SELECT private.${fn}(${args}) AS result`, parameters)).rows[0].result;
    });
  }
  return {
    db, record, cluster,
    async adminHealth(role = 'collect_runtime', kind = 'http_admin') {
      return db.transaction(async tx => {
        await tx.exec(`SET LOCAL ROLE ${role};
          SET LOCAL collect.edge_verified='true'; SET LOCAL test.work_kind='${kind}'; SET LOCAL test.identity='owner';
          SET LOCAL burimunsi.native_receipt_frame='before'; SET LOCAL burimunsi.payment_sms_frame='before';
          SET LOCAL burimunsi.observation_frame='before'; SET LOCAL burimunsi.pin_frame='before';`);
        const result=(await tx.query('SELECT private.burimunsi_admin_sms_health() AS result')).rows[0].result;
        for (const frame of ['native_receipt','payment_sms','observation','pin']) {
          const {value}=(await tx.query('SELECT current_setting($1) AS value', ['burimunsi.'+frame+'_frame'])).rows[0];
          assert.equal(value, 'before');
        }
        return result;
      });
    },
    readiness: () => rpc('burimunsi_payment_sms_readiness', [group, enabledAt, app], ['text', 'timestamptz', 'text']),
    claim: (collection = group, kind, role) => rpc('burimunsi_claim_payment_sms', [collection, enabledAt, app, 1],
      ['text', 'timestamptz', 'text', 'integer'], kind, role),
    prepare: (r, collection = group) => rpc('burimunsi_prepare_payment_sms_v2', [collection, r.attempt_id, r.claim_token, hash], ['text', 'uuid', 'uuid', 'text']),
    finish: (r, state, providerState = null) => rpc('burimunsi_finish_payment_sms', [group, r.attempt_id, r.claim_token, state, providerState, hash],
      ['text', 'uuid', 'uuid', 'text', 'text', 'text']),
  };
}

test('one canonical payment allows one armed body and GET-only reconciliation', async (t) => {
  const f = await fixture(t);
  const retention = (await f.db.query('SELECT private._retention_manifest_catalog_v2() AS catalog')).rows[0].catalog;
  assert.deepEqual(retention.private_classes.map(({relation, blocked}) => ({relation, blocked})),
    [{relation: 'private.burimunsi_payment_sms_deliveries', blocked: true}]);
  const {pay, entry, posted} = await f.record(20);
  assert.deepEqual(await f.readiness(), {contract_version: 1, eligible_count: 1, unresolved_count: 0});
  const [row] = await f.claim();
  assert.equal(row.phase, 'send');
  assert.equal(row.body_sha256, null);
  assert.equal(row.destination, phone);
  assert.equal(row.posted_reference, pay);
  assert.equal(row.posted_at, posted);
  assert.equal(row.amount_rwf, 125);
  assert.equal(row.member_balance_rwf, 765);
  assert.equal(row.message_id, app + ':buri-receipt:' + entry);
  assert.equal(row.idempotency_key, 'buri-receipt:' + entry);
  assert.equal(Date.parse(row.not_after) - Date.parse(posted), 300_000);
  assert.equal(Object.hasOwn(row, 'group_balance_rwf'), false);
  assert.deepEqual(await f.claim(), []);
  assert.equal(await f.prepare(row, id(8)), 'held');
  assert.equal(await f.prepare(row), 'prepared');
  assert.equal(await f.prepare(row), 'held');
  assert.equal(await f.finish(row, 'unknown'), true);
  await f.db.exec("UPDATE private.burimunsi_payment_sms_deliveries SET next_inspect_at=clock_timestamp()-interval '1 second'");
  const [read] = await f.claim();
  assert.equal(read.phase, 'inspect');
  assert.equal(read.attempt_id, row.attempt_id);
  assert.equal(read.message_id, row.message_id);
  assert.equal(read.destination, null);
  assert.equal(read.destination_sha256, row.destination_sha256);
  assert.equal(read.body_sha256, hash);
  assert.equal(await f.prepare(read), 'held');
  assert.equal(await f.finish(row, 'accepted', 'delivered'), false);
  assert.equal(await f.finish(read, 'accepted', 'delivered'), true);
  assert.deepEqual(await f.claim(), []);
  assert.deepEqual(await f.readiness(), {contract_version: 1, eligible_count: 0, unresolved_count: 0});
});

test('private jobs-only receipt selection rejects masked, unrelated, historical, reversed and pre-activation payments', async (t) => {
  const f = await fixture(t);
  await f.record(20, { payer: '******001' });
  await f.record(25, { payer: '+250788000099' });
  await f.record(30, { mode: 'historical' });
  await f.record(35, { age: 120_000 });
  const reversed = await f.record(40);
  await f.db.query("INSERT INTO app.ledger_entries(id,reverses_entry_id,kind) VALUES($1,$2,'reversal')", [id(99), reversed.entry]);
  assert.deepEqual(await f.claim(), []);
  assert.deepEqual(await f.claim(id(8)), []);
  await assert.rejects(f.claim(group, 'http_collect'), /jobs work required/);
  await assert.rejects(f.claim(group, 'jobs', 'anon'), /permission denied/);
  await assert.rejects(f.db.transaction(async (tx) => {
    await tx.exec('SET LOCAL ROLE collect_runtime');
    return tx.query('SELECT * FROM private.burimunsi_payment_sms_deliveries');
  }), /permission denied/);
});

test('updated member authority suppresses before POST and keeps the original receipt identity', async (t) => {
  const f = await fixture(t);
  await f.record(20);
  const [row] = await f.claim();
  await f.db.query("INSERT INTO app.assisted_sms_authorizations VALUES($1,$2,$3,1,0,NULL)", [group, member, row.destination_sha256]);
  assert.equal(await f.prepare(row), 'suppressed');
  assert.equal(await f.prepare(row), 'held');
  await f.db.query('DELETE FROM app.assisted_sms_authorizations');
  assert.deepEqual(await f.claim(), []);
  await f.record(30);
  await f.db.query('INSERT INTO app.notification_preferences VALUES($1,0)', [member]);
  assert.deepEqual(await f.claim(), []);
  await f.db.query('DELETE FROM app.notification_preferences');
  await f.db.query('INSERT INTO app.privacy_retention_barriers VALUES($1)', [member]);
  assert.deepEqual(await f.claim(), []);
  await f.db.query('DELETE FROM app.privacy_retention_barriers');
  const [original] = await f.claim();
  await f.db.query("UPDATE app.users SET momo_number='+250788000002' WHERE id=$1", [member]);
  assert.equal(await f.prepare(original), 'suppressed');
  const stored = (await f.db.query('SELECT state, body_sha256, claim_token FROM private.burimunsi_payment_sms_deliveries WHERE attempt_id=$1', [original.attempt_id])).rows[0];
  assert.deepEqual(stored, {state: 'suppressed', body_sha256: null, claim_token: null});
});


test('Admin SMS aggregates require current global and collection authority and keep postings and gateway outcomes distinct', async t => {
  const f = await fixture(t);
  await assert.rejects(f.adminHealth('anon'), /permission denied/);
  await assert.rejects(f.adminHealth('collect_runtime', 'jobs'), /Admin runtime required/);
  await assert.rejects(f.adminHealth(), /permission denied/);
  await f.db.exec("INSERT INTO app.admin_grants VALUES('principal','system_health.read'),('principal','sms.read'); INSERT INTO app.admin_account_role_capabilities VALUES('owner','sms.read')");
  assert.equal(await f.adminHealth(), null);
  await f.db.query("INSERT INTO private.burimunsi_operator_approvals VALUES($1,'principal','admin',true,ARRAY['records.read','sms.read'],NULL,'admin')", [group]);
  const {pay} = await f.record(20);
  const recorded = (await f.db.query('SELECT transaction_id FROM app.momo_financial_links WHERE payment_id=$1', [pay])).rows[0].transaction_id;
  const now = Date.now();
  await f.db.query(`INSERT INTO private.burimunsi_auto_sms_jobs VALUES
    ('posted-source',$1,$4,'completed','accepted',1,0,0,$3),
    ('retry-source',$1,NULL,'retry',NULL,2,0,0,$3),
    ('blocked-source',$1,NULL,'failed',NULL,5,0,0,$3),
    ('unrelated-source',$2,NULL,'failed',NULL,5,0,0,$3)`, [group,id(8),now-20000,recorded]);
  await f.db.query("INSERT INTO private.burimunsi_unresolved_observations VALUES('new-source',$1,$2),('posted-source',$1,$2)", [group,now-60000]);
  const [receipt] = await f.claim();
  assert.equal(await f.prepare(receipt), 'prepared');
  assert.equal(await f.finish(receipt, 'accepted','queued'), true);
  const sample = await f.adminHealth();
  assert.deepEqual({...sample.burimunsi_sms, oldest_pending_seconds: 60}, {
    pending: 1,retrying: 1,blocked: 1,unmatched: 0,posted: 1,oldest_pending_seconds: 60,
  });
  assert.ok(sample.burimunsi_sms.oldest_pending_seconds>=59);
  assert.deepEqual(sample.burimunsi_payer_sms, {pending: 0,gateway_accepted: 1,sent: 0,delivered: 0,failed: 0,unknown: 0,suppressed: 0});
  assert.equal(JSON.stringify(sample).includes(group), false);
  await f.db.exec("DELETE FROM app.admin_grants WHERE permission='sms.read'");
  assert.equal(await f.adminHealth(), null);
});

test('historical and concurrent payments get unique durable display references and preserve financial writes', async t => {
  const f=await fixture(t);
  const getReference=async id=>(await f.db.query('SELECT payment_reference FROM app.payments WHERE id=$1',[id])).rows[0].payment_reference;
  assert.match(await getReference('historical-payment'), /^[0-9]{12}$/);
  const parallel = new Client({host:f.cluster.socket, port:f.cluster.port, database:'postgres', user:f.cluster.initialUser});
  await parallel.connect();
  try {
    await parallel.query('SET ROLE collect_runtime');
    const insert='INSERT INTO app.payments(id,amount_minor) VALUES($1,1) RETURNING payment_reference';
    const [a,b]=await Promise.all([f.db.transaction(async tx=>{
      await tx.exec('SET LOCAL ROLE collect_runtime');
      return tx.query(insert,['new-payment-a']);
    }),parallel.query(insert,['new-payment-b'])]);
    const refs=[a,b].map(row=>row.rows[0].payment_reference);
    assert.ok(refs.every(value=>/^[0-9]{12}$/.test(value))); assert.notEqual(refs[0],refs[1]);
    await parallel.query("UPDATE app.payments SET status='reversed' WHERE id='new-payment-a'");
    assert.equal(await getReference('new-payment-a'), refs[0]);
    await assert.rejects(parallel.query("UPDATE app.payments SET payment_reference=DEFAULT WHERE id='new-payment-a'"), /payment_reference_immutable/);
    assert.equal(await getReference('new-payment-a'), refs[0]);
    assert.equal((await parallel.query('SELECT id FROM app.payments WHERE payment_reference=$1',[refs[1]])).rows[0].id,'new-payment-b');
  } finally {await parallel.end();}
});


test('a complete synthetic PostgreSQL restore retains display references and resumes allocation', async t => {
  const {cluster,db}=await fixture(t);
  const committed=await db.query("INSERT INTO app.payments(id,amount_minor) VALUES('restore-payment',1) RETURNING payment_reference");
  const original=committed.rows[0].payment_reference;
  const connection=['-h',cluster.socket,'-p',String(cluster.port),'-U',cluster.initialUser];
  const dump=execFileSync(join(cluster.bin,'pg_dump'),[...connection,'-d','postgres','--schema=app','--schema=private'],{env:cluster.env,maxBuffer:2**22});
  await db.exec('CREATE DATABASE payment_restore_fixture');
  execFileSync(join(cluster.bin,'psql'),[...connection,'-d','payment_restore_fixture','-Xq','-v','ON_ERROR_STOP=1'],{env:cluster.env,input:dump});
  const restore=new Client({host:cluster.socket,port:cluster.port,database:'payment_restore_fixture',user:cluster.initialUser});
  await restore.connect();
  try {
    assert.equal((await restore.query("SELECT payment_reference FROM app.payments WHERE id='restore-payment'")).rows[0].payment_reference,original);
    await restore.query('SET ROLE collect_runtime');
    assert.ok(BigInt((await restore.query("INSERT INTO app.payments(id,amount_minor) VALUES('new-payment',1) RETURNING payment_reference")).rows[0].payment_reference)>BigInt(original));
  } finally {await restore.end();}
});

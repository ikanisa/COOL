// Apply both release migrations intact to an owned database. The actor, consent
// and Storage predecessor contracts below are synthetic inputs to that schema.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';

const migrations = [
  '20261117180000_burimunsi_observation_reconcile_status.sql',
  '20261117190000_burimunsi_legacy_reconcile.sql',
];
const status = 'SELECT private.burimunsi_observation_reconcile_status() AS value';
const candidates = "SELECT private.burimunsi_observation_legacy_candidates(repeat('b',64)) AS value";

test('released reconciliation functions preserve one retained source on retry and deny ordinary database roles', async t => {
  const fixture = await startOwnedPg17({prefix: 'collect-pg-transfer-', initialUser: 'collect_fixture'});
  const db = new pg.Client({host: fixture.socket, port: fixture.port, database: 'postgres', user: fixture.initialUser});
  t.after(async () => {
    try { await db.end(); } finally { assert.equal((await fixture.close()).removed, true); }
  });
  await db.connect();
  assert.equal((await db.query('SELECT inet_server_addr() IS NULL AS owned_socket')).rows[0].owned_socket, true);
  await db.query(`
    CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role; CREATE ROLE collect_importer; CREATE ROLE collect_runtime;
    CREATE SCHEMA app; CREATE SCHEMA private;
    GRANT USAGE ON SCHEMA private TO anon, authenticated, service_role, collect_importer, collect_runtime;
    CREATE TABLE private.collect_fence_control(mode text);
    INSERT INTO private.collect_fence_control VALUES ('fenced');
    CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE plpgsql AS $$
      BEGIN IF current_user<>'collect_fixture' THEN RAISE insufficient_privilege; END IF; END $$;
    CREATE FUNCTION private.burimunsi_observation_actor(reveal boolean) RETURNS jsonb LANGUAGE plpgsql AS $$
      BEGIN
        IF current_setting('fixture.active',true) IS DISTINCT FROM 'yes'
          OR (reveal AND current_setting('fixture.reveal',true) IS DISTINCT FROM 'yes') THEN RAISE insufficient_privilege; END IF;
        RETURN jsonb_build_object('collectionId','fixture-group','accountId','10000000-0000-4000-8000-000000000001','principalUserId','owner');
      END $$;
    CREATE FUNCTION private.burimunsi_observation_consent_current() RETURNS jsonb LANGUAGE sql AS $$
      SELECT jsonb_build_object('enabled',current_setting('fixture.consent',true)='yes') $$;
    CREATE TABLE private.burimunsi_observation_requests(source_id text PRIMARY KEY,collection_id text,account_id uuid,principal_user_id text,
      installation_id uuid,grant_id uuid,grant_version bigint,request_id uuid,fingerprint text,source_key text);
    CREATE TABLE private.burimunsi_unresolved_observations(LIKE private.burimunsi_observation_requests,body_sha256 text,object_key text,object_sha256 text);
    CREATE TABLE private.storage_put_intents(object_key text PRIMARY KEY);
    CREATE TABLE private.storage_objects(object_key text PRIMARY KEY,custom_metadata jsonb);
    CREATE TABLE private.storage_payload_reservations(object_key text PRIMARY KEY,scope jsonb,aad text,plaintext_sha256 text,key_id text,
      source_fingerprint text,sealed_body text);
    CREATE TABLE private.storage_delete_intents(object_key text PRIMARY KEY);
    CREATE FUNCTION private.burimunsi_observation_storage_matches(object_name text,expected jsonb,plain_sha text) RETURNS boolean LANGUAGE sql AS $$
      SELECT EXISTS(SELECT 1 FROM private.storage_payload_reservations r JOIN private.storage_objects o USING(object_key)
        WHERE r.object_key=object_name AND r.scope=expected AND r.plaintext_sha256=plain_sha) $$;
    CREATE TABLE private.burimunsi_sms_source_scopes(source_id text,collection_id text,owner_user_id text,source_body_sha256 text,object_sha256 text);
    CREATE TABLE app.sms_receipts(id text,owner_user_id text,body_sha256 text,object_sha256 text,object_key text);
    CREATE TABLE private.collect_imported_native_history(source_id text,collection_id text,request_id uuid,
      body_sha256 text,object_sha256 text,source_fingerprint text);
    CREATE TABLE private.burimunsi_native_receipt_origins(LIKE private.burimunsi_observation_requests,body_sha256 text,object_sha256 text);
    CREATE TABLE private.collect_migration_actor_lineage(source_actor_id text,cloud_primary_id text);
    CREATE FUNCTION private.burimunsi_observation_history_own(source text) RETURNS jsonb LANGUAGE sql AS $$
      SELECT jsonb_build_object('sourceId',source_id,'requestId',request_id,'fingerprint',source_fingerprint,
        'bodySha256',body_sha256,'object_sha256',object_sha256) FROM private.collect_imported_native_history WHERE source_id=source $$;
  `);
  for (const name of migrations) {
    const source = new URL('../../../supabase/migrations/' + name, import.meta.url);
    await db.query(await readFile(source, 'utf8'));
  }
  await db.query(`
    INSERT INTO private.burimunsi_observation_requests VALUES ('source-a','fixture-group','10000000-0000-4000-8000-000000000001',
      'original-owner','20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,
      '40000000-0000-4000-8000-000000000001',repeat('f',64),NULL);
    INSERT INTO private.burimunsi_unresolved_observations SELECT q.*,repeat('b',64),'sms/source-a',repeat('c',64)
      FROM private.burimunsi_observation_requests q;
    INSERT INTO private.burimunsi_native_receipt_origins SELECT q.*,repeat('b',64),repeat('c',64) FROM private.burimunsi_observation_requests q;
    INSERT INTO private.collect_imported_native_history SELECT source_id,collection_id,request_id,repeat('b',64),repeat('c',64),fingerprint
      FROM private.burimunsi_observation_requests;
    INSERT INTO private.collect_migration_actor_lineage VALUES ('original-owner','owner');
    INSERT INTO private.storage_objects VALUES ('sms/source-a',jsonb_build_object('source_fingerprint',repeat('f',64),'key_id','fixture-key'));
    INSERT INTO private.storage_payload_reservations VALUES ('sms/source-a',jsonb_build_object('ownerId','original-owner','purpose','sms_receipt','entityId','source-a'),
      'sms:source-a:'||repeat('c',64),repeat('c',64),'fixture-key',repeat('f',64),NULL);
  `);
  const before = (await db.query('SELECT count(*)::int AS n FROM private.burimunsi_observation_requests')).rows[0].n;
  assert.equal(before, 1);
  for (const role of ['anon', 'authenticated', 'service_role', 'collect_importer']) {
    await db.query('SET ROLE ' + role);
    try {
      await assert.rejects(db.query(status), {code: '42501'});
      await assert.rejects(db.query(candidates), {code: '42501'});
    } finally { await db.query('RESET ROLE'); }
  }
  await db.query(`SET ROLE collect_runtime;
    SET fixture.active='yes'; SET fixture.consent='yes'; SET fixture.reveal='yes';
    SET burimunsi.collection_id='fixture-group'`);
  const readStatus = async () => (await db.query(status)).rows[0].value;
  const readCandidates = async () => (await db.query(candidates)).rows[0].value;
  const original = await readStatus();
  assert.equal(original.groupId, 'fixture-group');
  assert.equal(original.recordedCount, 1);
  assert.equal(original.hasRecorded, true);
  const originalCandidates = await readCandidates();
  assert.deepEqual(originalCandidates.map(row => row.sourceId), ['source-a']);
  assert.deepEqual(await readStatus(), original);
  assert.deepEqual(await readCandidates(), originalCandidates);
  await db.query("SET fixture.reveal='no'");
  await assert.rejects(readCandidates(), {code: '42501'});
  await db.query("SET fixture.consent='no'");
  await assert.rejects(readStatus(), {code: '42501'});
  await db.query("SET fixture.active='no'");
  await assert.rejects(readStatus(), {code: '42501'});
  await db.query('RESET ROLE');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM private.burimunsi_observation_requests')).rows[0].n, before);
  await t.test('qualified verified status reads only admitted collection witnesses, preserves ordinary status and denies unscoped roles', async () => {
    const functionName='private.burimunsi_observation_reconcile_verified_status()';
    const exists=async name=>(await db.query('SELECT to_regprocedure($1) IS NOT NULL AS found',[name])).rows[0].found;
    // The two released predecessors do not install a held status or a writer.
    assert.equal(await exists(functionName),false);
    assert.equal(await exists('private.burimunsi_sms_recovery_prepare(text,text,text,uuid,text,text,text,text,bigint)'),false);
    await db.query(`
      ALTER TABLE private.storage_put_intents ADD COLUMN scope jsonb,ADD COLUMN active_attempt text,ADD COLUMN upload_unresolved boolean;
      CREATE TABLE private.collect_sms_witnesses(object_key text PRIMARY KEY,collection_id text,body_sha256 text,owner_id text);
      SET fixture.active='yes';SET fixture.consent='yes';SET burimunsi.collection_id='fixture-group';
    `);
    // Exact function and grants from c454140a's candidate. This test fixture
    // is outside migrations and installs only the metadata reader on owned PG.
    const definition=await readFile(new URL('./fixtures/burimunsi-held-verified-status.sql',import.meta.url),'utf8');
    assert.equal(createHash('sha256').update(definition).digest('hex'),'2b0de380b376b15d6a4f82ea57bdbbcf7248e57615aab70a95e6f9abac3230a4');
    await db.query(definition);
    const acl=(await db.query(`SELECT CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS role,
      a.privilege_type, p.prosecdef,p.proconfig FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
      WHERE p.oid=to_regprocedure($1) ORDER BY 1`,[functionName])).rows;
    assert.deepEqual(acl.map(row=>row.role),[fixture.initialUser,'collect_runtime'].sort());
    for(const row of acl){assert.equal(row.privilege_type,'EXECUTE');assert.equal(row.prosecdef,true);
      assert.deepEqual(row.proconfig,['search_path=pg_catalog, pg_temp']);}
    const verified=async()=>(await db.query('SELECT '+functionName+' AS value')).rows[0].value;
    for(const role of ['anon','authenticated','service_role','collect_importer']){
      await db.query('SET ROLE '+role);
      try{await assert.rejects(verified(),{code:'42501'});}finally{await db.query('RESET ROLE');}
    }
    async function runtimeSnapshot(){
      await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      try{
        await db.query('SET LOCAL ROLE collect_runtime');
        return {base:await readStatus(),verified:await verified()};
      }finally{await db.query('ROLLBACK');}
    }
    const baseline=await runtimeSnapshot();
    assert.equal(baseline.verified.hasPending,false);assert.equal(baseline.verified.recordedCount,1);
    await db.query("INSERT INTO private.collect_sms_witnesses VALUES ('sms/other','another-group',repeat('b',64),'owner')");
    assert.deepEqual(await runtimeSnapshot(),baseline);
    await db.query("INSERT INTO private.collect_sms_witnesses VALUES ('sms/pending','fixture-group',repeat('c',64),'owner')");
    const observed=await runtimeSnapshot();assert.deepEqual(observed.base,baseline.base);
    assert.equal(observed.verified.hasPending,true);assert.equal(observed.verified.recordedCount,1);
    assert.notEqual(observed.verified.revision,baseline.verified.revision);
    assert.deepEqual(await runtimeSnapshot(),observed);
    for(const change of ["burimunsi.collection_id='another-group'","fixture.consent='no'","fixture.active='no'"]){
      await db.query('BEGIN READ ONLY');
      try{
        await db.query('SET LOCAL ROLE collect_runtime');await db.query('SET LOCAL '+change);
        await assert.rejects(verified(),{code:'42501'});
      }finally{await db.query('ROLLBACK');}
    }
    assert.deepEqual((await db.query(`SELECT (SELECT count(*)::int FROM private.collect_sms_witnesses) witnesses,
      (SELECT count(*)::int FROM private.burimunsi_observation_requests) requests,
      (SELECT count(*)::int FROM private.burimunsi_unresolved_observations) recorded,
      (SELECT count(*)::int FROM app.sms_receipts) canonical`)).rows[0],{witnesses:2,requests:1,recorded:1,canonical:0});
  });
});

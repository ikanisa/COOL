// Run the reviewed bootstrap SQL against a fresh socket-only PG17 with synthetic
// Cloud authority and lineage rows. Provider and deployment access are unnecessary.
import assert from 'node:assert/strict';
import {createHash, randomBytes, randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from '../node_modules/pg/lib/index.js';
import {PinHasher} from '../../../supabase/functions/_shared/domain/burimunsi/pin.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {
  applyInitialBootstrapInFencedTransaction,
  INITIAL_BOOTSTRAP_EXTRA_RELATIONS,
  prepareInitialBootstrap,
} from './initial-account-bootstrap.mjs';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const migrations = new URL('../../../supabase/migrations/', import.meta.url);

function sqlBetween(sql, start, stop) {
  const from = sql.indexOf(start);
  const to = sql.indexOf(stop, from + start.length);
  assert.ok(from >= 0 && to > from, 'expected migration fragment');
  return sql.slice(from, to);
}

async function makeFixture(client) {
  await client.query(`
    CREATE SCHEMA app;
    CREATE SCHEMA auth;
    CREATE SCHEMA private;
    CREATE TABLE app.users(id text PRIMARY KEY, access_status text, phone text, revision bigint DEFAULT 1);
    CREATE TABLE app.collections(id text PRIMARY KEY, status text);
    CREATE TABLE app.momo_receiving_accounts(id text PRIMARY KEY);
    CREATE TABLE app.momo_gateway_bindings(id text PRIMARY KEY);
    CREATE TABLE app.admin_users(id text PRIMARY KEY, email text, role text, status text, auth_version bigint DEFAULT 1);
    CREATE TABLE app.admin_principal_links(admin_user_id text PRIMARY KEY, user_id text NOT NULL);
    CREATE TABLE app.audit_log(actor_user_id text, actor_session_id text, action text, entity_type text,
      entity_id text, request_id text, details_json text, created_at text);
    CREATE TABLE auth.users(id uuid PRIMARY KEY, email text, email_confirmed_at timestamptz,
      deleted_at timestamptz, banned_until timestamptz);
    CREATE TABLE private.auth_principal_links(auth_user_id uuid PRIMARY KEY, user_id text NOT NULL);
    CREATE TABLE private.collect_owner_identity(singleton boolean PRIMARY KEY, admin_user_id text,
      principal_user_id text, owner_email text);
    CREATE TABLE private.collect_fence_control(singleton boolean PRIMARY KEY, project_ref text, mode text,
      epoch bigint, operation_id uuid, source_sha256 text);
    CREATE TABLE private.collect_fence_admissions(admission_id uuid PRIMARY KEY, epoch bigint,
      source_sha256 text, kind text, state text);
    CREATE TABLE private.burimunsi_native_receipt_origins(source_id text, collection_id text,
      principal_user_id text, account_id uuid);
    CREATE TABLE private.collect_imported_native_history(source_id text, collection_id text);
    CREATE TABLE private.collect_migration_actor_lineage(source_actor_id text, cloud_primary_id text);

    -- The fixture models unresolved admissions and the installation owner.
    -- It has no stopped admissions or runtime authority to confer.
    CREATE FUNCTION private._collect_stopped_matches(uuid,bigint,text,text) RETURNS boolean
      LANGUAGE sql AS $$ SELECT false $$;
    CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE plpgsql AS $$
    BEGIN
      IF current_user <> 'postgres' OR session_user <> 'postgres' THEN
        RAISE insufficient_privilege;
      END IF;
    END $$;
  `);
  const [operator, pin, owner] = await Promise.all([
    readFile(new URL('20261109234517_burimunsi_native_operator_schema.sql', migrations), 'utf8'),
    readFile(new URL('20261110143000_burimunsi_native_phone_pin.sql', migrations), 'utf8'),
    readFile(new URL('20261111121400_collect_protected_owner_identity.sql', migrations), 'utf8'),
  ]);
  // Exercise production table constraints and authority lookups. Whole
  // migration preconditions and the managed database are outside this fixture.
  for (const sql of [
    sqlBetween(operator, 'CREATE TABLE private.burimunsi_scopes (', 'CREATE TABLE private.burimunsi_rate_limits ('),
    sqlBetween(operator, 'CREATE TABLE private.burimunsi_operator_approvals(', 'CREATE FUNCTION private.burimunsi_operator_approval_identity()'),
    sqlBetween(pin, 'CREATE TABLE private.burimunsi_native_staff_delegations(', 'CREATE TABLE private.burimunsi_pin_session_links('),
    sqlBetween(owner, 'CREATE FUNCTION private.collect_owner_binding()', 'CREATE FUNCTION private.collect_owner_attestation()'),
    sqlBetween(pin, 'CREATE FUNCTION private.burimunsi_pin_root_snapshot(', 'CREATE OR REPLACE FUNCTION private.burimunsi_operator_is_current('),
  ]) {
    await client.query(sql);
  }
  await client.query(`
    ALTER TABLE private.burimunsi_native_staff_delegations ENABLE ROW LEVEL SECURITY;
    ALTER TABLE private.burimunsi_native_staff_delegations FORCE ROW LEVEL SECURITY;
  `);
}

const fixture = await startOwnedPg17({
  prefix: 'collect-pg-transfer-',
  initialUser: 'fixture_bootstrap',
  clusterName: 'collect_initial_account_fixture',
});
const database = 'collect_initial_account_fixture';
const connect = (user, name = database) => new pg.Client({
  host: fixture.socket, port: fixture.port, database: name, user,
});
const bootstrap = connect(fixture.initialUser, 'postgres');
const owner = connect('postgres');
const observer = connect(fixture.initialUser);
const pepper = randomBytes(32);

let phase = 'setup';
try {
  await bootstrap.connect();
  await bootstrap.query(`
    CREATE ROLE postgres LOGIN NOSUPERUSER NOBYPASSRLS;
    CREATE ROLE anon;
    CREATE ROLE authenticated;
    CREATE ROLE service_role;
    CREATE ROLE collect_runtime;
    CREATE ROLE collect_importer;
  `);
  await bootstrap.query('CREATE DATABASE collect_initial_account_fixture OWNER postgres');
  await owner.connect();
  await observer.connect();
  await makeFixture(owner);

  const groupId = 'synthetic-collection';
  const principalId = randomUUID();
  const staffPrincipalId = randomUUID();
  const adminUserId = randomUUID();
  const authId = randomUUID();
  const adminAccountId = randomUUID();
  const staffAccountId = randomUUID();
  const fenceOperationId = randomUUID();
  const sourceSha256 = 'a'.repeat(64);
  const adminPhone = '+250780000001';
  const staffPhone = '+250780000002';
  const staffPin = '4321';
  const adminPin = '7512';

  await owner.query('INSERT INTO app.users(id,access_status,phone) VALUES($1,$3,$4),($2,$3,$5)',
    [principalId, staffPrincipalId, 'active', adminPhone, staffPhone]);
  await owner.query(`
    INSERT INTO app.collections VALUES('synthetic-collection','active');
    INSERT INTO app.momo_receiving_accounts VALUES('synthetic-wallet');
    INSERT INTO private.burimunsi_scopes(collection_id,receiving_account_id,enabled,created_at)
      VALUES('synthetic-collection','synthetic-wallet',true,1);
  `);
  await owner.query(`
    INSERT INTO private.burimunsi_accounts(id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,active,created_at,updated_at)
    VALUES($1,$2,$3,$4,'Synthetic Admin','admin',ARRAY['records.read'],'{}',false,1,1),
      ($5,$2,$6,$7,'Synthetic Staff','staff',ARRAY['records.read'],'{}',false,1,1)
  `, [adminAccountId, groupId, principalId, adminPhone, staffAccountId, staffPrincipalId, staffPhone]);
  await owner.query("INSERT INTO app.admin_users(id,email,role,status) VALUES($1,'owner@example.invalid','owner','active')", [adminUserId]);
  await owner.query('INSERT INTO app.admin_principal_links VALUES($1,$2)', [adminUserId, principalId]);
  await owner.query("INSERT INTO auth.users(id,email,email_confirmed_at) VALUES($1,'owner@example.invalid',now())", [authId]);
  await owner.query('INSERT INTO private.auth_principal_links VALUES($1,$2)', [authId, principalId]);
  await owner.query("INSERT INTO private.collect_owner_identity VALUES(true,$1,$2,'owner@example.invalid')", [adminUserId, principalId]);
  await owner.query("INSERT INTO private.collect_fence_control VALUES(true,'rrlduytparvsjfmegalh','fenced',1,$1,$2)", [fenceOperationId, sourceSha256]);
  await owner.query("INSERT INTO private.burimunsi_native_receipt_origins VALUES('synthetic-origin',$1,'synthetic-actor',$2)", [groupId, adminAccountId]);
  await owner.query("INSERT INTO private.collect_imported_native_history VALUES('synthetic-origin',$1)", [groupId]);
  await owner.query("INSERT INTO private.collect_migration_actor_lineage VALUES('synthetic-actor',$1)", [principalId]);

  const pepperId = 'synthetic-pepper';
  const pepperRecord = {pepper: pepper.toString('base64'), pepperId};
  const cloudRows = [
    {name: 'BURIMUNSI_PIN_PEPPER_BASE64', value: sha(pepperRecord.pepper)},
    {name: 'BURIMUNSI_PIN_PEPPER_ID', value: sha(pepperId)},
  ];
  const args = {
    operationId: randomUUID(), fenceOperationId, epoch: 1, sourceSha256,
    authorizationSha256: 'b'.repeat(64), ownerPrincipalId: principalId, collectionId: groupId,
    adminAccountId, staffAccountId, adminPhone, staffPhone, adminPin, staffPin,
  };

  async function execute(operationId, prepared, {writeLock = true} = {}) {
    await owner.query('BEGIN');
    try {
      await owner.query("SET LOCAL lock_timeout='3s'; SET LOCAL statement_timeout='10s'; SET LOCAL row_security=on");
      await owner.query('SELECT pg_advisory_xact_lock(7346371,1)');
      if (writeLock) await owner.query('SELECT pg_advisory_xact_lock(7346371,2)');
      await owner.query("SELECT set_config('collect.graph_import_operation',$1,true)", [operationId]);
      for (const relation of INITIAL_BOOTSTRAP_EXTRA_RELATIONS) {
        await owner.query(`LOCK TABLE ${relation} IN ACCESS EXCLUSIVE MODE`);
        await owner.query(`CREATE POLICY fixture_approved_owner ON ${relation} TO postgres
          USING (session_user='postgres' AND current_setting('collect.graph_import_operation',true)<>'')
          WITH CHECK (session_user='postgres' AND current_setting('collect.graph_import_operation',true)<>'')`);
      }
      const result = await applyInitialBootstrapInFencedTransaction(owner, prepared);
      for (const relation of INITIAL_BOOTSTRAP_EXTRA_RELATIONS) {
        await owner.query(`DROP POLICY fixture_approved_owner ON ${relation}`);
      }
      await owner.query('COMMIT');
      return result;
    } catch (error) {
      await owner.query('ROLLBACK');
      throw error;
    }
  }

  const inspect = async () => (await observer.query(`
    SELECT (SELECT count(*)::int FROM private.burimunsi_accounts WHERE active) AS accounts,
      (SELECT count(*)::int FROM private.burimunsi_operator_approvals WHERE active) AS approvals,
      (SELECT count(*)::int FROM private.burimunsi_native_staff_delegations WHERE active) AS delegations,
      (SELECT count(*)::int FROM app.audit_log WHERE action='burimunsi.migration.initial_accounts' AND actor_session_id IS NULL) AS audit,
      (SELECT count(*)::int FROM private.burimunsi_device_grants WHERE active) AS grants,
      (SELECT count(*)::int FROM private.burimunsi_sessions WHERE NOT revoked) AS sessions,
      (SELECT count(*)::int FROM pg_policy WHERE polname='fixture_approved_owner') AS policies
  `)).rows[0];

  phase = 'preconditions';
  await assert.rejects(() => prepareInitialBootstrap(args, {cloudRows: [], pepperRecord}),
    {message: 'cloud_pepper_identity_unverified'});
  const ready = await prepareInitialBootstrap(args, {cloudRows, pepperRecord});
  assert.deepEqual(JSON.parse(JSON.stringify(ready)), {operationId: args.operationId, prepared: true});
  const expectedRejection = {message: 'initial_account_bootstrap_failed', code: '55000'};
  await assert.rejects(() => execute(args.operationId, ready, {writeLock: false}), expectedRejection);
  const wrongArgs = {...args, operationId: randomUUID(), adminPhone: '+250780000003'};
  const wrong = await prepareInitialBootstrap(wrongArgs, {cloudRows, pepperRecord});
  await assert.rejects(() => execute(wrongArgs.operationId, wrong), expectedRejection);
  const admission = randomUUID();
  await owner.query("INSERT INTO private.collect_fence_admissions VALUES($1,1,$2,'db','unresolved')", [admission, sourceSha256]);
  await assert.rejects(() => execute(args.operationId, ready), expectedRejection);
  await owner.query('DELETE FROM private.collect_fence_admissions WHERE admission_id=$1', [admission]);
  assert.deepEqual(await inspect(), {accounts: 0, approvals: 0, delegations: 0, audit: 0, grants: 0, sessions: 0, policies: 0});

  phase = 'bootstrap';
  assert.deepEqual(await execute(args.operationId, ready), {
    operationId: args.operationId, applied: true, credentialValuesDisclosed: false,
  });
  const expected = {accounts: 2, approvals: 1, delegations: 1, audit: 1, grants: 0, sessions: 0, policies: 0};
  assert.deepEqual(await inspect(), expected);
  const rows = (await observer.query(`
    SELECT role, phone, pin_hash, active, version, credential_version, capabilities
    FROM private.burimunsi_accounts ORDER BY role
  `)).rows;
  const hasher = new PinHasher({pepper, pepperId});
  assert.deepEqual(rows.map(row => row.role), ['admin', 'staff']);
  for (const row of rows) {
    assert.equal(row.active, true);
    assert.equal(row.version, '2');
    assert.equal(row.credential_version, '2');
    const [correct, wrongPin] = row.role === 'admin' ? [adminPin, staffPin] : [staffPin, adminPin];
    assert.equal(await hasher.verify(row.phone, correct, row.pin_hash), true);
    assert.equal(await hasher.verify(row.phone, wrongPin, row.pin_hash), false);
    assert.equal(row.capabilities.includes('staff.manage'), row.role === 'admin');
  }
  await assert.rejects(() => execute(args.operationId, ready), expectedRejection);
  assert.deepEqual(await inspect(), expected);
  console.log(JSON.stringify({status: 'PASS', fixture: 'synthetic-cloud-socket-pg17',
    oldGrantsRevived: false, productionDispatched: false}));
} catch (error) {
  const safe = (error?.message ?? '').match(/^[a-z_]{2,100}$/)?.[0] ?? 'redacted';
  const code = /^[0-9A-Z]{5}$/.test(error?.code ?? '') ? error.code : 'unavailable';
  throw Error('initial_account_fixture_failed:' + phase + ':' + safe + ':' + code);
} finally {
  pepper.fill(0);
  await Promise.all([bootstrap, owner, observer].map(client => client.end().catch(() => {})));
  assert.equal((await fixture.close()).removed, true);
}

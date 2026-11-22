import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {PostgresNativeAuthStore} from '../../../supabase/functions/_shared/domain/burimunsi/postgres-auth-store.js';
import {PostgresCanonicalStore} from '../../../supabase/functions/_shared/domain/burimunsi/postgres-canonical-store.js';
import {PostgresSmartOnboardingJournal} from '../../../supabase/functions/_shared/domain/burimunsi/smart-onboarding-journal.js';
import {verifyStaffCreatePredecessor} from './test-support/staff-create-predecessor.mjs';

const migration = name => readFile(new URL('../../../supabase/migrations/' + name, import.meta.url), 'utf8');
const schema = await migration('20261109234517_burimunsi_native_operator_schema.sql');
const start = schema.indexOf('CREATE TABLE private.burimunsi_scopes (');
const end = schema.indexOf('-- Reconciled source: receipt-jobs-proposal.sql');
assert.ok(start >= 0 && end > start);
const grants = await migration('20261120075011_burimunsi_native_journal_runtime_grants.sql');
const clock = () => 1000000;
const group = 'synthetic-group';
const otherGroup = 'other-synthetic-group';
const fixtureDigest = 'a'.repeat(64);
const unrelated = () => assert.fail('Unexpected unrelated service call');

function database(client) {
  const tx = {unsafe: async (query, params) => (await client.query(query, params)).rows};
  const context = () => client.query("SET LOCAL ROLE collect_runtime; SET LOCAL lock_timeout='750ms'");
  return {
    context, readContext: context, applicationWork: {assert: async () => {}},
    async transaction(run) {
      await client.query('BEGIN');
      try {
        const value = await run(tx);
        await client.query('COMMIT');
        return value;
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      }
    },
  };
}

test('BuriMunsi journal grants on disposable PostgreSQL 17', async t => {
  const fixture = await startOwnedPg17({prefix: 'collect-pg-transfer-', initialUser: 'collect_fixture'});
  const connect = user => new pg.Client({host: fixture.socket, port: fixture.port, database: 'postgres', user});
  const owner = connect(fixture.initialUser), edge = connect('synthetic_edge');
  t.after(async () => {
    try { await Promise.all([owner.end(), edge.end()]); } finally { await fixture.close(); }
  });
  await owner.connect();
  await owner.query(`
    CREATE ROLE postgres; CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS; CREATE ROLE collect_importer;
    CREATE ROLE collect_runtime NOLOGIN NOBYPASSRLS;
    CREATE ROLE synthetic_edge LOGIN NOINHERIT NOSUPERUSER NOBYPASSRLS;
    GRANT collect_runtime TO synthetic_edge WITH SET TRUE, INHERIT FALSE;
    CREATE ROLE inherited_runtime NOSUPERUSER NOBYPASSRLS;
    GRANT collect_runtime TO inherited_runtime WITH INHERIT TRUE;
    CREATE SCHEMA app; CREATE SCHEMA private;
    CREATE TABLE app.users(id text PRIMARY KEY, access_status text NOT NULL);
    CREATE TABLE app.collections(id text PRIMARY KEY);
    CREATE TABLE app.momo_receiving_accounts(id text PRIMARY KEY);
    CREATE TABLE app.momo_gateway_bindings(id text PRIMARY KEY);
    CREATE TABLE app.momo_transactions(id text PRIMARY KEY);
    GRANT USAGE ON SCHEMA app,private TO collect_runtime;
    GRANT SELECT ON app.users TO collect_runtime;
    CREATE TABLE private.collect_fence_control(singleton boolean PRIMARY KEY, mode text);
    INSERT INTO private.collect_fence_control VALUES(true, 'fenced');
    CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE plpgsql AS $$
      BEGIN IF current_user <> 'collect_fixture' THEN RAISE insufficient_privilege; END IF; END $$;
    CREATE FUNCTION private._collect_fence_statement() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RETURN NULL; END $$;
  `);
  await owner.query(schema.slice(start, end));
  await owner.query(`
    CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
      ON private.burimunsi_command_receipts FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
    ALTER TABLE private.burimunsi_command_receipts ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
  `);
  await owner.query(await migration('20261113130100_burimunsi_smart_onboarding_journal.sql'));
  await owner.query(await migration('20261119041000_burimunsi_ocr_disclosure_binding.sql'));
  const actorId = randomUUID(), sessionId = randomUUID(), grantId = randomUUID(), installationId = randomUUID();
  await owner.query("INSERT INTO app.users VALUES('principal','active')");
  await owner.query("INSERT INTO app.momo_receiving_accounts VALUES('wallet')");
  await owner.query('INSERT INTO app.collections VALUES($1), ($2)', [group, otherGroup]);
  await owner.query(`INSERT INTO private.burimunsi_scopes(collection_id,receiving_account_id,enabled,created_at)
    VALUES($1,'wallet',true,1),($2,'wallet',true,1)`, [group, otherGroup]);
  await owner.query(`INSERT INTO private.burimunsi_accounts(id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,created_at,updated_at)
    VALUES($1,$2,'principal','+250780000001','Fixture operator','staff',ARRAY['records.read','members.enroll'],'{}',1,1)`, [actorId, group]);
  await owner.query(`INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,created_at)
    VALUES($1,$2,$3,$4,'staff',1)`, [grantId, group, installationId, fixtureDigest]);
  await owner.query('INSERT INTO private.burimunsi_device_accounts VALUES($1,$2,$3)', [grantId, actorId, group]);
  await owner.query(`INSERT INTO private.burimunsi_sessions(id,collection_id,account_id,grant_id,installation_id,
    credential_version,grant_version,token_hash,created_at,expires_at,principal_user_id)
    VALUES($1,$2,$3,$4,$5,1,1,$6,1,2000000,'principal')`, [sessionId, group, actorId, grantId, installationId, fixtureDigest]);
  await edge.connect();
  const db = database(edge);
  const authority = new PostgresNativeAuthStore({db, groupId: group, clock, createOperatorPrincipal: unrelated});
  const canonical = new PostgresCanonicalStore({
    authority, clock, jobs: {assertPostingLease: unrelated},
    identities: {policy: unrelated, members: unrelated, verified: unrelated},
    commands: {postContribution: unrelated, createDirectMember: unrelated, setMembershipActive: unrelated, enqueueEligibleRematch: unrelated},
  });
  const command = {groupId: group, actorId, sessionId, requestId: randomUUID(), operation: 'burimunsi.enroll',
    fingerprint: fixtureDigest, response: {memberId: 'existing-member'}};
  await canonical.inMemberTransaction(async ops => {
    await ops.reloadActor(sessionId);
    await ops.retainCommand(command);
  });
  await t.test('migration requires the fence and refuses inherited update rights atomically', async () => {
    await owner.query("UPDATE private.collect_fence_control SET mode='open'");
    await assert.rejects(owner.query(grants), {code: '55000', message: 'burimunsi_journal_runtime_precondition'});
    await owner.query("ROLLBACK; UPDATE private.collect_fence_control SET mode='fenced'");
    await owner.query('CREATE ROLE prior_journal_writer; GRANT UPDATE ON private.burimunsi_audit TO prior_journal_writer; GRANT prior_journal_writer TO collect_runtime');
    await assert.rejects(owner.query(grants), {code: '55000', message: 'burimunsi_journal_unexpected_runtime_grants'});
    await owner.query('ROLLBACK; REVOKE prior_journal_writer FROM collect_runtime');
  });
  await owner.query(grants);
  await owner.query("UPDATE private.collect_fence_control SET mode='open'");

  await t.test('catalog permits only the two writable columns and denies all client roles', async () => {
    const tables = {burimunsi_audit: [], burimunsi_command_receipts: ['response'], burimunsi_rate_limits: ['attempts']};
    for (const [name, columns] of Object.entries(tables)) {
      const relation = 'private.' + name;
      const allowed = await owner.query(`SELECT attname FROM pg_attribute
        WHERE attrelid=$1::regclass AND attnum>0 AND NOT attisdropped
          AND has_column_privilege('collect_runtime',attrelid,attnum,'UPDATE') ORDER BY attname`, [relation]);
      assert.deepEqual(allowed.rows.map(row => row.attname), columns);
      for (const role of ['anon', 'authenticated', 'service_role', 'collect_importer']) {
        const result = await owner.query(`SELECT has_any_column_privilege($1,$2,'SELECT,INSERT,UPDATE,REFERENCES')
          OR has_table_privilege($1,$2,'DELETE,TRUNCATE,TRIGGER,MAINTAIN') AS admitted`, [role, relation]);
        assert.equal(result.rows[0].admitted, false, role + ' on ' + relation);
      }
    }
    for (const role of ['anon', 'authenticated', 'service_role', 'collect_importer']) {
      await owner.query('SET ROLE ' + role);
      try {
        await assert.rejects(owner.query('SELECT action FROM private.burimunsi_audit'), {code: '42501'});
      } finally { await owner.query('RESET ROLE'); }
    }
  });
  await t.test('existing commands can be locked and recovered, while their original response and identity stay fixed', async () => {
    const retained = await canonical.inMemberTransaction(async ops => {
      await ops.reloadActor(sessionId);
      return ops.retainedCommand(group, actorId, command.requestId);
    });
    assert.deepEqual(retained, {sessionId, operation: command.operation, fingerprint: fixtureDigest, response: command.response});
    await assert.rejects(authority.write(tx => tx.unsafe(`UPDATE private.burimunsi_command_receipts SET response='{}'
      WHERE request_id=$1`, [command.requestId])), {code: '42501'});
    await assert.rejects(authority.write(tx => tx.unsafe('UPDATE private.burimunsi_command_receipts SET created_at=2')), {code: '42501'});
    const copy = await authority.read(tx => authority.retained(tx, actorId, command.requestId));
    assert.deepEqual(copy, retained);
  });
  await t.test('native attempt budgets advance, stay scoped to the group and retain denied attempts', async () => {
    const bucket = [{key: 'fixture-login', limit: 1, windowMs: 60000}];
    assert.equal(await authority.consumeAttempts(bucket, clock()), true);
    assert.equal(await authority.consumeAttempts(bucket, clock()), false);
    await assert.rejects(authority.write(tx => tx.unsafe('UPDATE private.burimunsi_rate_limits SET attempts=1')), {code: '23514'});
    await assert.rejects(authority.write(tx => tx.unsafe(`INSERT INTO private.burimunsi_rate_limits
      VALUES($1,'new',1,60000,3,60001)`, [group])), {code: '23514'});
    await assert.rejects(authority.write(tx => tx.unsafe('UPDATE private.burimunsi_rate_limits SET expires_at=1')), {code: '42501'});
    await assert.rejects(authority.write(tx => tx.unsafe('DELETE FROM private.burimunsi_rate_limits')), {code: '42501'});
    await owner.query('BEGIN; SET LOCAL ROLE inherited_runtime');
    try {
      await owner.query("SELECT set_config('burimunsi.collection_id',$1,true)", [group]);
      await assert.rejects(owner.query('UPDATE private.burimunsi_rate_limits SET attempts=1'), {code: '23514'});
    } finally { await owner.query('ROLLBACK'); }
    const other = new PostgresNativeAuthStore({db, groupId: otherGroup, createOperatorPrincipal: unrelated, clock});
    assert.equal(await other.consumeAttempts(bucket, clock()), true);
    const read = store => store.read(tx => tx.unsafe('SELECT attempts::int FROM private.burimunsi_rate_limits'));
    assert.deepEqual(await read(authority), [{attempts: 2}]);
    assert.deepEqual(await read(other), [{attempts: 1}]);
  });
  await t.test('standalone native budgets advance while a financial writer holds the shared lock', async () => {
    const policy = [{key: 'fixture-admission', limit: 1, windowMs: 60000}];
    await owner.query('BEGIN');
    try {
      await owner.query('SELECT pg_catalog.pg_advisory_xact_lock(734636924058501::bigint)');
      assert.equal(await authority.consumeAttempts(policy, clock()), true);
    } finally {
      await owner.query('ROLLBACK');
    }
    assert.equal(await authority.consumeAttempts(policy, clock()), false);
  });
  await t.test('concurrent native requests charge each shared bucket once with one admission', async () => {
    const clients = Array.from({length: 8}, () => connect('synthetic_edge'));
    try {
      await Promise.all(clients.map(client => client.connect()));
      const policy = ['fixture-account', 'fixture-device', 'fixture-network'].map(key =>
        ({key, limit: 1, windowMs: 60000}));
      const stores = clients.map(client => new PostgresNativeAuthStore({
        db: database(client), groupId: group, clock, createOperatorPrincipal: unrelated,
      }));
      const admitted = await Promise.all(stores.map((store, i) =>
        store.consumeAttempts(i % 2 ? policy : [...policy].reverse(), clock())));
      assert.equal(admitted.filter(Boolean).length, 1);
      const {rows} = await owner.query(`SELECT bucket,attempts::int FROM private.burimunsi_rate_limits
        WHERE collection_id=$1 AND bucket=ANY($2::text[]) ORDER BY bucket`, [group, policy.map(rule => rule.key)]);
      assert.deepEqual(rows, policy.map(({key}) => ({bucket: key, attempts: clients.length})));
    } finally {
      await Promise.all(clients.map(client => client.end()));
    }
  });
  await t.test('a current native session can recover an encrypted preview, while expired or revoked sessions are denied', async () => {
    const env = {DATA_KEY_ID: 'synthetic-key', DATA_ENCRYPTION_KEY: Buffer.alloc(32, 7).toString('base64')};
    const journal = new PostgresSmartOnboardingJournal({authority, clock, env});
    const input = {groupId: group, actorId, sessionId, sourceSha256: 'b'.repeat(64), policySha256: 'c'.repeat(64),
      decoderBuildSha256: 'd'.repeat(64), mimeType: 'image/png', importFlowId: randomUUID(),
      ocrDisclosureVersion: 'burimunsi-ocr-disclosure-v1', proposedRequestId: randomUUID(), proposedReservationId: randomUUID()};
    const receipt = await journal.reserve(input);
    await journal.advance({receipt, sessionId, phase: 'decode'});
    await journal.advance({receipt, sessionId, phase: 'extract'});
    const preview = {sourceKind: 'image', rows: []};
    await journal.complete({receipt, sessionId, phase: 'extract', preview});
    assert.deepEqual((await journal.reserve(input)).preview, preview);
    const history = await authority.read(tx => tx.unsafe('SELECT action FROM private.burimunsi_audit ORDER BY action'));
    assert.deepEqual(history.map(row => row.action), ['burimunsi.smart_import.completed', 'burimunsi.smart_import.reserved']);
    await assert.rejects(authority.write(tx => tx.unsafe('UPDATE private.burimunsi_audit SET action=$1', ['edited'])), {code: '42501'});
    await assert.rejects(authority.write(tx => tx.unsafe(`INSERT INTO private.burimunsi_audit(id,collection_id,actor_id,action,at_ms)
      VALUES($1,$2,$3,'other',1)`, [randomUUID(), otherGroup, actorId])), {code: '42501'});
    const expired = new PostgresSmartOnboardingJournal({authority, env, clock: () => 2000000});
    await assert.rejects(expired.reserve(input), {code: 'session_unavailable'});
    await owner.query("UPDATE private.burimunsi_accounts SET capabilities=ARRAY['records.read'] WHERE id=$1", [actorId]);
    await assert.rejects(journal.reserve(input), {code: 'access_denied'});
    await owner.query('UPDATE private.burimunsi_sessions SET revoked=true WHERE id=$1', [sessionId]);
    await assert.rejects(journal.reserve(input), {code: 'session_unavailable'});
  });
  await t.test('strict HTTP recovers only the original historical Staff create on PostgreSQL', () =>
    verifyStaffCreatePredecessor({owner, db, clock, group, otherGroup, staffActorId: actorId, staffSessionId: sessionId}));
});

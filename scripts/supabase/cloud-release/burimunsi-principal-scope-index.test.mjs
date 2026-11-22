import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import pg from '../node_modules/pg/lib/index.js';
import { startOwnedPg17 } from '../current-pg-transfer/test-support/owned-pg17.mjs';

const migration = new URL(
  '../../../supabase/migrations/20261122045039_deduplicate_burimunsi_principal_scope.sql',
  import.meta.url,
);
const indexName = 'burimunsi_provisioning_one_principal_per_scope';

test('BuriMunsi removes only the duplicate index and retains the unique constraint', async t => {
  const fixture = await startOwnedPg17({
    prefix: 'collect-pg-transfer-',
    initialUser: 'collect_fixture',
    clusterName: 'collect_burimunsi_principal_scope_fixture',
  });
  const db = new pg.Client({
    host: fixture.socket, port: fixture.port, database: 'postgres', user: fixture.initialUser,
  });
  t.after(async () => {
    try {
      await db.end();
    } finally {
      assert.equal((await fixture.close()).removed, true);
    }
  });

  await db.connect();
  const sql = await readFile(migration, 'utf8');
  await db.query(`
    CREATE SCHEMA private;
    CREATE TABLE private.burimunsi_accounts (
      collection_id text NOT NULL,
      principal_user_id text NOT NULL,
      CONSTRAINT burimunsi_one_principal_per_scope UNIQUE (collection_id, principal_user_id)
    );
    CREATE UNIQUE INDEX ${indexName}
      ON private.burimunsi_accounts (collection_id, principal_user_id);
    INSERT INTO private.burimunsi_accounts VALUES ('group-one', 'principal-one');
  `);
  const indexOid = async name => (await db.query(
    'SELECT to_regclass($1::text)::oid AS oid', ['private.' + name],
  )).rows[0].oid;
  const constraintIndex = await indexOid('burimunsi_one_principal_per_scope');
  assert.ok(constraintIndex);
  assert.ok(await indexOid(indexName));

  await db.query(sql);
  assert.equal(await indexOid(indexName), null);
  assert.equal(await indexOid('burimunsi_one_principal_per_scope'), constraintIndex);
  assert.deepEqual((await db.query('TABLE private.burimunsi_accounts')).rows, [
    { collection_id: 'group-one', principal_user_id: 'principal-one' },
  ]);
  await assert.rejects(
    db.query("INSERT INTO private.burimunsi_accounts VALUES ('group-one', 'principal-one')"),
    { code: '23505', constraint: 'burimunsi_one_principal_per_scope' },
  );
  await db.query("INSERT INTO private.burimunsi_accounts VALUES ('group-two', 'principal-one')");

  await db.query(sql);
  await db.query(`CREATE INDEX ${indexName} ON private.burimunsi_accounts (principal_user_id)`);
  const differentIndex = await indexOid(indexName);
  await assert.rejects(db.query(sql), { code: '55000', message: 'burimunsi_principal_scope_index_changed' });
  await db.query('ROLLBACK');
  assert.equal(await indexOid(indexName), differentIndex);
});

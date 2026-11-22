import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import pg from '../node_modules/pg/lib/index.js';
import { startOwnedPg17 } from '../current-pg-transfer/test-support/owned-pg17.mjs';

const migrations = new URL('../../../supabase/migrations/', import.meta.url);
const helpers = ['json_each', 'json_extract', 'json_valid', 'max'];
const readHelpers = `
  SELECT p.oid, p.proname, p.prosrc, p.proowner, p.proacl::text, p.proconfig,
    p.prosecdef, p.provolatile
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'collect_sms' AND p.proname = ANY($1::text[])
  ORDER BY p.proname
`;
const exerciseHelpers = `
  SELECT collect_sms.json_valid('{"a":true}') AS valid,
    collect_sms.json_valid('{invalid') AS invalid,
    collect_sms.json_extract('{"a":{"b":"value"}}', '$.a.b') AS extracted,
    (SELECT array_agg(value) FROM collect_sms.json_each('["sms",2]')) AS items,
    collect_sms.max(7, 11)::int AS greatest
`;

test('SMS compatibility helper paths are fixed without changing gateway roles or results', async t => {
  const fixture = await startOwnedPg17({
    prefix: 'collect-pg-transfer-',
    initialUser: 'collect_fixture',
    clusterName: 'collect_sms_helper_paths_fixture',
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
  await db.query('CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;');
  await db.query(await readFile(new URL('20261101012503_collect_sms_gateway.sql', migrations), 'utf8'));

  const before = (await db.query(readHelpers, [helpers])).rows;
  assert.deepEqual(before.map(row => row.proname), helpers);
  assert.ok(before.every(row => row.proconfig === null && !row.prosecdef));
  await db.query('SET ROLE collect_sms_runtime');
  const beforeResults = (await db.query(exerciseHelpers)).rows[0];
  await db.query('RESET ROLE');

  await db.query(await readFile(new URL('20261122043731_collect_sms_helper_paths.sql', migrations), 'utf8'));
  const after = (await db.query(readHelpers, [helpers])).rows;
  assert.deepEqual(after, before.map(row => ({ ...row, proconfig: ['search_path=pg_catalog, pg_temp'] })));

  await db.query('SET ROLE collect_sms_runtime; SET search_path TO public');
  assert.deepEqual((await db.query(exerciseHelpers)).rows[0], beforeResults);
  assert.deepEqual(beforeResults, {
    valid: true, invalid: false, extracted: 'value', items: ['sms', '2'], greatest: 11,
  });

  // Existing table constraints still resolve the same helper with the gateway role.
  await db.query(`
    INSERT INTO collect_sms.applications
      (application_id, name, token_hash, allowed_kinds, scopes, created_at)
    VALUES ('fixture-app', 'Synthetic', 'fixture-hash', '["otp"]', '[]', '2026-11-22T00:00:00Z')
  `);
  await assert.rejects(
    db.query(`
      INSERT INTO collect_sms.applications
        (application_id, name, token_hash, allowed_kinds, scopes, created_at)
      VALUES ('fixture-invalid', 'Synthetic', 'invalid-fixture', '{', '[]', '2026-11-22T00:00:00Z')
    `),
    { code: '23514' },
  );
  await db.query('RESET ROLE');

  for (const role of ['anon', 'authenticated', 'service_role']) {
    await db.query('SET ROLE ' + role);
    try {
      await assert.rejects(db.query(exerciseHelpers), { code: '42501' });
    } finally {
      await db.query('RESET ROLE');
    }
  }
});

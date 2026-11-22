import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {adminRpc as supabaseRpc} from '../domain/admin.js';

// These tests exercise the real list SQL and serializer against a synthetic
// in-memory database. They do not establish PostgreSQL, HTTP, RLS, or provider behavior.
async function fixture(run) {
  const db = new DatabaseSync(':memory:');
  db.exec(`
    CREATE TABLE payment_evidence (id TEXT PRIMARY KEY, authenticity TEXT);
    CREATE TABLE payments (id TEXT PRIMARY KEY, evidence_id TEXT NOT NULL,
      status TEXT NOT NULL, payer_display_name TEXT NOT NULL, amount_minor INTEGER,
      created_at TEXT NOT NULL);
    CREATE TABLE collections (id TEXT PRIMARY KEY, title TEXT NOT NULL,
      status TEXT NOT NULL, created_at TEXT NOT NULL);
    INSERT INTO payment_evidence VALUES ('e1','operator_recorded'),
      ('e2','provider_authenticated'),('e3','operator_recorded'),('e4','operator_recorded');
    INSERT INTO payments VALUES
      ('p1','e1','confirmed','Alpha',100,'2026-01-01T00:00:01Z'),
      ('p2','e2','recorded','Beta',200,'2026-01-01T00:00:02Z'),
      ('p3','e3','reconciled','Gamma',300,'2026-01-01T00:00:03Z'),
      ('p4','e4','confirmed','Delta',400,'2026-01-01T00:00:04Z');
    INSERT INTO collections VALUES ('c1','Group one','active','2026-01-01T00:00:05Z');
  `);
  const env = {DB: {prepare(sql) { return {bind(...params) { return {
    async all() { return {results:db.prepare(sql).all(...params)}; },
    async first() { return db.prepare(sql).get(...params) ?? null; },
  }; }}; }}};
  try { await run(db, env); } finally { db.close(); }
}
const paymentsActor = {permissions:new Set(['payments.read'])};
const collectionsActor = {permissions:new Set(['collections.read'])};
// Exercise the selected Supabase runtime. The historical dual-backend test is
// preserved in the recovery snapshot; it does not establish legacy behavior.
for (const [target, adminRpc] of [['supabase',supabaseRpc]]) {
  for (const op of ['admin_list_payments','admin_list_collect_transactions']) {
    test(`${target} ${op}: linked evidence determines authenticity`, () => fixture(async (_db, env) => {
      const {value}=await adminRpc(op,{},env,paymentsActor);
      assert.equal(value.total,4);
      const items=Object.fromEntries(value.rows.map(row=>[row.id,row]));
      assert.equal(items.p1.evidence_level,'operator_recorded');
      assert.equal(items.p2.evidence_level,'provider_authenticated');
      assert.equal(items.p3.evidence_level,'operator_recorded');
      assert.equal(items.p4.evidence_level,'operator_recorded');
    }));
    test(`${target} ${op}: filter and pagination preserve count and evidence`, () => fixture(async (_db, env) => {
      const {value}=await adminRpc(op,{p_status:'confirmed',p_limit:1,p_offset:1},env,paymentsActor);
      assert.equal(value.total,2); assert.equal(value.rows.length,1);
      assert.equal(value.rows[0].id,'p1'); assert.equal(value.rows[0].evidence_level,'operator_recorded');
    }));
    test(`${target} ${op}: search preserves evidence and amount`, () => fixture(async (_db, env) => {
      const {value}=await adminRpc(op,{p_search:'Beta'},env,paymentsActor);
      assert.equal(value.total,1); assert.equal(value.rows[0].id,'p2');
      assert.equal(value.rows[0].amount,'200 RWF'); assert.equal(value.rows[0].evidence_level,'provider_authenticated');
    }));
    // The following two fixtures deliberately violate production FK/CHECK
    // constraints to ensure corrupted or unavailable evidence is never invented.
    test(`${target} ${op}: missing evidence fails closed`, () => fixture(async (db, env) => {
      db.exec("INSERT INTO payments VALUES ('pbad','absent','confirmed','Broken',1,'2026-01-01T00:00:06Z')");
      await assert.rejects(()=>adminRpc(op,{},env,paymentsActor),
        error=>error.status===503 && error.code==='invalid_source_data');
    }));
    test(`${target} ${op}: unknown authenticity fails closed`, () => fixture(async (db, env) => {
      db.exec("INSERT INTO payment_evidence VALUES ('ebad','unknown'); INSERT INTO payments VALUES ('pbad','ebad','confirmed','Broken',1,'2026-01-01T00:00:06Z')");
      await assert.rejects(()=>adminRpc(op,{},env,paymentsActor),
        error=>error.status===503 && error.code==='invalid_source_data');
    }));
  }
  test(`${target}: payments.read is required before database access`, async () => {
    const noDb={DB:{prepare(){throw new Error('database should not be reached');}}};
    await assert.rejects(()=>adminRpc('admin_list_payments',{},noDb,{permissions:new Set()}),
      error=>error.status===403 && error.code==='42501');
  });
  test(`${target}: non-payment lists retain their response shape`, () => fixture(async (_db, env) => {
    const {value}=await adminRpc('admin_list_collections',{},env,collectionsActor);
    assert.equal(value.total,1); assert.equal(value.rows[0].title,'Group one');
    assert.equal(Object.hasOwn(value.rows[0],'evidence_level'),false);
  }));
}

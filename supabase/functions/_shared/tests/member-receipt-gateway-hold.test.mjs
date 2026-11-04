import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

// Node-only import shim forbids construction of real SQL or SMTP clients.
await import('./helpers/node-postgres-import.mjs');
const {receiptFunction} = await import('../domain/receipts.js');
const {decrypt} = await import('../domain/encryption.js');

const aliases = ['ingest-client-sms', 'ingest-payment-sms'];
const user = '10000000-0000-4000-8000-000000000001';
const session = '20000000-0000-4000-8000-000000000001';
const envelope = '30000000-0000-4000-8000-000000000001';
const binding = '40000000-0000-4000-8000-000000000001';
const actor = {userId: user, sessionId: session, surface: 'member'};

function forbidNetwork(t) {
 let attempts = 0;
 t.mock.method(globalThis, 'fetch', () => {
  attempts++;
  throw Error('Network is forbidden in this synthetic fixture');
 });
 return () => assert.equal(attempts, 0);
}

function heldInput(values) {
 const reads = [];
 const body = new Proxy(values, {
  get(target, key) {
   reads.push(key);
   if (key !== 'gateway_binding_id' && key !== 'gateway_binding_version') {
    throw Error('A held request read its SMS body or native capability');
   }
   return target[key];
  },
 });
 const envTouches = [], actorTouches = [];
 const env = new Proxy({}, {get(_, key) {
  envTouches.push(key);
  throw Error('A held request accessed database, storage, capability or configuration');
 }});
 const forbiddenActor = new Proxy({}, {get(_, key) {
  actorTouches.push(key);
  throw Error('A held request accessed actor or capability data');
 }});
 return {body, env, actor: forbiddenActor, reads, envTouches, actorTouches};
}

for (const alias of aliases) test(`${alias} holds any non-null gateway binding before side effects`, async t => {
 const noNetwork = forbidNetwork(t);
 for (const [name, values] of [
  ['complete binding', {gateway_binding_id: binding, gateway_binding_version: 1}],
  ['ID only', {gateway_binding_id: binding}],
  ['version only', {gateway_binding_version: 1}],
  ['ID with null version', {gateway_binding_id: binding, gateway_binding_version: null}],
  ['null ID with version', {gateway_binding_id: null, gateway_binding_version: 1}],
  ['invalid empty ID', {gateway_binding_id: ''}],
  ['invalid zero version', {gateway_binding_version: 0}],
  ['invalid false ID', {gateway_binding_id: false}],
 ]) {
  const f = heldInput(values);
  await assert.rejects(
   () => receiptFunction(alias, f.body, f.env, f.actor),
   error => error.status === 503 && error.code === 'gateway_upload_held' &&
    !String(error.message).includes('A held request'),
   name,
  );
  assert.ok(f.reads.length > 0, name);
  assert.ok(f.reads.every(key => key === 'gateway_binding_id' || key === 'gateway_binding_version'), name);
  assert.deepEqual(f.envTouches, [], name);
  assert.deepEqual(f.actorTouches, [], name);
 }
 noNetwork();
});

test('unregistered receipt operations do not inspect a gateway request', async t => {
 const noNetwork = forbidNetwork(t);
 const f = heldInput({gateway_binding_id: binding});
 assert.deepEqual(await receiptFunction('not-a-receipt-operation', f.body, f.env, f.actor), {handled: false});
 assert.deepEqual(f.reads, []);
 assert.deepEqual(f.envTouches, []);
 assert.deepEqual(f.actorTouches, []);
 noNetwork();
});

function syntheticMemberFixture({pipeline, consent = true}) {
 const calls = [], batches = [], objects = [];
 let aiAccesses = 0;
 const allowedStatement = /^\s*(?:INSERT INTO (?:mutation_guards|request_receipts|admin_bridge_guards|sms_receipts|momo_processing_jobs|audit_log)|DELETE FROM (?:mutation_guards|admin_bridge_guards))\b/i;
 const db = {
  prepare(sql) {
   return {bind(...args) {
    const statement = {sql, args};
    calls.push(statement);
    return {...statement, async first() {
     if (/^SELECT EXISTS\(SELECT 1 FROM native_consents/i.test(sql)) {
      assert.deepEqual(args, [user, session]);
      return {allowed: consent ? 1 : 0};
     }
     if (/^SELECT \(SELECT count\(\*\) FROM sms_receipts/i.test(sql)) {
      assert.deepEqual(args, [user, user]);
      return {allowed: 1};
     }
     if (/^SELECT r\.\*,q\.body_sha256 AS request_sha256,q\.response_json FROM sms_receipts/i.test(sql)) {
      assert.deepEqual(args, [user, envelope]);
      return null;
     }
     if (/^SELECT \* FROM request_receipts WHERE user_id=\? AND request_id=\?/i.test(sql)) {
      assert.deepEqual(args, [user, envelope]);
      return null;
     }
     if (/FROM sqlite_schema WHERE type='table' AND name='momo_processing_jobs'/i.test(sql)) {
      return pipeline ? {available: 1} : null;
     }
     throw Error('Unexpected synthetic database read');
    }};
   }};
  },
  async batch(statements) {
   for (const statement of statements) assert.match(statement.sql, allowedStatement);
   batches.push(statements.map(statement => ({sql: statement.sql, args: [...statement.args]})));
   return statements.map(() => ({results: [], success: true}));
  },
 };
 const env = {
  DB: db,
  MOMO_PROCESSING_PAUSED: 'false',
  DATA_KEY_ID: 'synthetic-test-key',
  DATA_ENCRYPTION_KEY: Buffer.alloc(32, 7).toString('base64'),
  PRIVATE_MEDIA: {async put(key, cipher, options) { objects.push({key, cipher, options}); }},
 };
 Object.defineProperty(env, 'AI', {enumerable: true, get() { aiAccesses++; throw Error('Member capture must not start receipt processing'); }});
 return {env, calls, batches, objects, aiAccesses: () => aiAccesses};
}

function memberBody(bindingFields = {}) {
 return {
  client_envelope_id: envelope,
  raw_sender: 'Synthetic M-Money',
  raw_body: 'Synthetic transaction evidence 500 RWF',
  received_at_device: '2026-01-02T03:04:05.000Z',
  completeness: 'complete',
  ...bindingFields,
 };
}

function statementsFor(batch, table) {
 return batch.filter(statement => new RegExp(`^\\s*INSERT INTO ${table}\\b`, 'i').test(statement.sql));
}

for (const alias of aliases) for (const pipeline of [false, true]) {
 test(`${alias} retains unbound opted-in member capture (pipeline ${pipeline})`, async t => {
  const noNetwork = forbidNetwork(t);
  for (const [name, bindingFields] of [
   ['absent', {}],
   ['explicit null', {gateway_binding_id: null, gateway_binding_version: null}],
  ]) {
   const f = syntheticMemberFixture({pipeline});
   const body = memberBody(bindingFields);
   const result = await receiptFunction(alias, body, f.env, actor);
   assert.equal(result.handled, true, name);
   assert.equal(result.value.ok, true, name);
   assert.equal(f.aiAccesses(), 0, name);
   const receipt = result.value.receipt;
   assert.equal(receipt.contract_version, 2, name);
   assert.equal(receipt.stored, true, name);
   assert.equal(receipt.owner_user_id, user, name);
   assert.equal(receipt.client_envelope_id, envelope, name);
   assert.equal(receipt.body_sha256, createHash('sha256').update(body.raw_body).digest('hex'), name);
   assert.equal(receipt.source_provenance, 'member_device_unverified', name);
   assert.equal(receipt.receiving_source_known, false, name);
   assert.equal(receipt.financial_effects, 0, name);
   assert.equal(f.objects.length, 1, name);
   assert.equal(f.batches.length, 1, name);
   const [object] = f.objects;
   assert.equal(object.key, `sms/${receipt.raw_sms_id}`, name);
   assert.equal(object.options.scope.ownerId, user, name);
   assert.equal(object.options.scope.entityId, receipt.raw_sms_id, name);
   assert.equal(object.cipher.includes(body.raw_body), false, name);
   const clear = JSON.parse(new TextDecoder().decode(await decrypt(f.env, object.cipher, object.options.aad)));
   assert.equal(clear.raw_body, body.raw_body, name);
   assert.equal(clear.raw_sender, body.raw_sender, name);
   assert.equal(clear.receiver_momo_number, null, name);
   assert.equal(clear.source_provenance, 'member_device_unverified', name);
   assert.equal(clear.receiving_source_known, false, name);
   const [batch] = f.batches;
   assert.equal(statementsFor(batch, 'sms_receipts').length, 1, name);
   assert.equal(statementsFor(batch, 'request_receipts').length, 1, name);
   assert.equal(statementsFor(batch, 'audit_log').length, 1, name);
   assert.equal(statementsFor(batch, 'momo_processing_jobs').length, pipeline ? 1 : 0, name);
   assert.equal(batch.some(statement => /\b(?:payments|ledger_entries|native_capabilities)\b/i.test(statement.sql)), false, name);
   if (pipeline) {
    const job = statementsFor(batch, 'momo_processing_jobs')[0];
    assert.equal(job.args[0], receipt.raw_sms_id, name);
    assert.equal(job.args[1], null, name);
    assert.equal(job.args[2], null, name);
    assert.equal(job.args[6], 'source_unresolved', name);
   }
   const savedReceipt = statementsFor(batch, 'request_receipts')[0];
   assert.deepEqual(JSON.parse(savedReceipt.args[5]), result.value, name);
   assert.equal(f.calls.some(call => /\b(?:native_capabilities|native_reservations)\b/i.test(call.sql)), false, name);
  }
  noNetwork();
 });
}

test('unbound member capture still requires current-session consent', async t => {
 const noNetwork = forbidNetwork(t);
 const f = syntheticMemberFixture({pipeline: true, consent: false});
 await assert.rejects(
  () => receiptFunction('ingest-client-sms', memberBody(), f.env, actor),
  error => error.status === 403 && error.code === 'sms_access_required',
 );
 assert.equal(f.objects.length, 0);
 assert.equal(f.batches.length, 0);
 noNetwork();
});

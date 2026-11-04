import test from 'node:test';
import assert from 'node:assert/strict';

// Import the real domain dispatcher while denying SQL-driver construction.
// This fixture uses synthetic HTTP requests and an in-memory database double.
await import('./helpers/node-postgres-import.mjs');
const {default: worker} = await import('../domain/index.js');
const {momoGatewayRoute} = await import('../domain/momo_gateway.js');

const gatewayToken = 'a'.repeat(64);
const bindingId = '10000000-0000-4000-8000-000000000001';
const ownerId = '20000000-0000-4000-8000-000000000001';
const credentialId = '30000000-0000-4000-8000-000000000001';
const installationId = '40000000-0000-4000-8000-000000000001';
const syntheticText = 'synthetic-private-message-not-for-transport';

function request(path, {method = 'GET', token, body} = {}) {
 const headers = new Headers();
 if (token) headers.set('Authorization', 'Bearer ' + token);
 if (body !== undefined) headers.set('Content-Type', 'application/json');
 return new Request('https://synthetic.example.invalid' + path, {
  method, headers, ...(body === undefined ? {} : {body}),
 });
}

function prohibitNetwork(t) {
 let attempts = 0;
 t.mock.method(globalThis, 'fetch', () => { attempts++; throw Error('Network is prohibited in this fixture'); });
 return () => assert.equal(attempts, 0);
}

function heldEnvironment(setting) {
 const env = {ALLOWED_ORIGINS: '', MOMO_PROCESSING_PAUSED: setting};
 for (const key of ['DB', 'PRIVATE_MEDIA', 'AI']) {
  Object.defineProperty(env, key, {get() { throw Error(key + ' must not be used by held ingestion'); }});
 }
 return env;
}

test('gateway ingest returns a retryable refusal without reading, retaining or acknowledging SMS', async t => {
 const noNetwork = prohibitNetwork(t);
 const diagnostics = [];
 t.mock.method(console, 'error', value => diagnostics.push(String(value)));
 for (const setting of [undefined, 'true', 'false', 'TRUE']) {
  for (const token of [undefined, gatewayToken]) {
   const input = request('/v1/momo/gateway/ingest', {
    method: 'POST', token, body: JSON.stringify({raw_body: syntheticText}),
   });
   const response = await worker.fetch(input, heldEnvironment(setting), {
    waitUntil() { throw Error('Held ingestion must not start deferred work'); },
   });
   const body = await response.json();
   assert.equal(response.status, 503);
   assert.equal(body.code, 'gateway_upload_held');
   assert.equal(body.receipt, undefined);
   assert.equal(input.bodyUsed, false, 'The domain dispatcher must not read the capture body');
   assert.equal(JSON.stringify(body).includes(syntheticText), false);
   assert.match(response.headers.get('cache-control'), /no-store/);
  }
 }
 assert.equal(diagnostics.some(line => line.includes(syntheticText)), false);
 noNetwork();
});

function gatewayFixture() {
 const credential = {
  id: credentialId, binding_id: bindingId, binding_version: 1,
  owner_user_id: ownerId, receiving_account_id: '50000000-0000-4000-8000-000000000001',
  binding_created_at: '2026-01-01T00:00:00Z', subscription_evidence: '{}',
  provider: 'mtn_momo', public_code: 'synthetic', recipient_name: 'Synthetic receiver',
  currency: 'RWF', timezone: 'Africa/Kigali', last_sms_at: null,
 };
 const calls = [], batches = [];
 const DB = {
  prepare(sql) {
   return {bind(...values) {
    const statement = {sql, values, async first() {
     calls.push(sql);
     if (sql.includes('FROM momo_gateway_credentials c JOIN momo_gateway_bindings')) return credential;
     if (sql.includes('FROM momo_gateway_pairings p')) return null;
     throw Error('Unexpected synthetic read');
    }};
    return statement;
   }};
  },
  async batch(statements) {
   batches.push(statements.map(statement => statement.sql));
   return statements.map(statement => ({results: statement.sql.includes('SELECT count(*) AS n') ? [{n: 3}] : []}));
  },
 };
 return {env: {ALLOWED_ORIGINS: '', DB}, calls, batches};
}

test('pairing, status and heartbeat retain their existing route behavior', async t => {
 const noNetwork = prohibitNetwork(t), f = gatewayFixture();
 const status = await worker.fetch(request('/v1/momo/gateway/status', {token: gatewayToken}), f.env, {});
 assert.equal(status.status, 200);
 const state = await status.json();
 assert.equal(state.binding.id, bindingId);
 assert.equal(state.pending_processing, 3);

 const heartbeat = await worker.fetch(request('/v1/momo/gateway/heartbeat', {
  method: 'POST', token: gatewayToken,
  body: JSON.stringify({pending_count: 1, oldest_pending_at: null, last_sms_at: null}),
 }), f.env, {});
 assert.equal(heartbeat.status, 200);
 assert.deepEqual(await heartbeat.json(), {ok: true});

 const pair = await worker.fetch(request('/v1/momo/gateway/pair', {
  method: 'POST', body: JSON.stringify({pairing_code: 'synthetic-unissued-code', installation_id: installationId}),
 }), f.env, {});
 assert.equal(pair.status, 401);
 assert.equal((await pair.json()).code, 'pairing_unavailable');
 assert.equal(f.calls.filter(sql => sql.includes('FROM momo_gateway_credentials c JOIN momo_gateway_bindings')).length, 2);
 assert.equal(f.calls.some(sql => sql.includes('FROM momo_gateway_pairings p')), true);
 assert.equal(f.batches.length, 2);
 assert.equal(f.batches.some(batch => batch.some(sql => /(?:INSERT INTO|UPDATE)\s+(?:sms_receipts|momo_processing_jobs)\b/i.test(sql))), false);
 noNetwork();
});

test('member and outbound notification paths are not intercepted by the gateway hold', async t => {
 const noNetwork = prohibitNetwork(t);
 for (const path of ['/v1/functions/ingest-client-sms', '/v1/functions/ingest-payment-sms', '/api/admin/notification-operator']) {
  assert.equal(await momoGatewayRoute(request(path, {method: 'POST', body: '{}'}), heldEnvironment('false')), null);
 }
 const member = await worker.fetch(request('/v1/functions/ingest-client-sms', {method: 'POST', body: '{}'}), heldEnvironment('false'), {});
 assert.equal(member.status, 401, 'The member path still reaches its existing authentication boundary');
 assert.notEqual((await member.json()).code, 'gateway_upload_held');
 noNetwork();
});

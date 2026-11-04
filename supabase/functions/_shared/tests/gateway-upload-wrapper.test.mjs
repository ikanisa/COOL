import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

// Real wrapper imports with a Node-only, network-denied PostgreSQL/SMTP shim.
// Synthetic Request objects never leave this process.
await import('./helpers/node-postgres-import.mjs');
const {canonicalProfile} = await import('../deployment-profile.js');
const {createHandler} = await import('../serve.js');

const profile = {
 format: 'collect.deployment.v1', id: 'gateway-wrapper-fixture', mode: 'self_hosted',
 environment: 'qualification', supabase_origin: 'https://supabase.example.invalid',
 member_api_origin: 'https://member.example.invalid', admin_origin: 'https://admin.example.invalid',
 public_origin: 'https://public.example.invalid', google_callback_origin: 'https://member.example.invalid',
};
const rawProfile = canonicalProfile(profile);
const profileHash = createHash('sha256').update(rawProfile).digest('hex');
const syntheticMessage = 'synthetic-gateway-message-never-for-transport';
const gatewayPath = '/v1/momo/gateway/ingest';
const prefixes = ['/functions/v1/collect-api', '/collect-api'];
let fixtureNumber = 0;

function fixture(t, {functionName = 'collect-api', changes = {}} = {}) {
 const counts = {construct: 0, begin: 0, reserve: 0, admission: 0, network: 0};
 const observations = [];
 t.mock.method(globalThis, '__collectFencePostgresFixture', () => {
  counts.construct++;
  return {
   async begin() { counts.begin++; throw Error('Synthetic fixture forbids database access'); },
   async reserve() { counts.reserve++; throw Error('Synthetic fixture forbids database access'); },
  };
 });
 t.mock.method(globalThis, 'fetch', () => { counts.network++; throw Error('Synthetic fixture forbids network'); });
 const env = {
  COLLECT_DEPLOYMENT_PROFILE: rawProfile, COLLECT_DEPLOYMENT_PROFILE_SHA256: profileHash,
  APP_ENVIRONMENT: 'test', SUPABASE_URL: profile.supabase_origin,
  // A different synthetic loopback identity per fixture avoids pool reuse.
  COLLECT_DATABASE_URL: `postgres://fixture:synthetic@127.0.0.1:1/gateway_wrapper_${++fixtureNumber}`,
  SUPABASE_PUBLISHABLE_KEY: 'synthetic-public-key', SUPABASE_SECRET_KEY: 'synthetic-secret-key',
  BUILD_SOURCE_ID: 'a'.repeat(64), MOMO_PROCESSING_PAUSED: 'false', ...changes,
 };
 const handler = createHandler(functionName, () => ({...env}), {
  openWork: async () => { counts.admission++; throw Error('Synthetic fixture forbids fence admission'); },
  reportHealth: value => { observations.push(value); },
 });
 return {handler, counts, observations, setPause(value) {
  if (value === undefined) delete env.MOMO_PROCESSING_PAUSED;
  else env.MOMO_PROCESSING_PAUSED = value;
 }};
}

function makeRequest(path, {origin, method = 'POST', host = profile.supabase_origin, token = true} = {}) {
 const headers = new Headers();
 if (origin !== undefined) headers.set('Origin', origin);
 if (method === 'POST') {
  headers.set('Content-Type', 'application/json');
  if (token) headers.set('Authorization', 'Bearer ' + 'a'.repeat(64));
 }
 return new Request(host + path, {
  method, headers,
  ...(method === 'POST' ? {body: JSON.stringify({raw_body: syntheticMessage})} : {}),
 });
}

function assertNoEffects(f) {
 assert.deepEqual(f.counts, {construct: 0, begin: 0, reserve: 0, admission: 0, network: 0});
 assert.equal(JSON.stringify(f.observations).includes(syntheticMessage), false);
}

test('both self-hosted function prefixes refuse gateway uploads before runtime admission', async t => {
 const f = fixture(t);
 for (const pause of [undefined, 'true', 'false']) {
  f.setPause(pause);
  for (const prefix of prefixes) for (const host of [profile.supabase_origin, 'http://api-gw:8000']) for (const token of [true, false]) {
   const input = makeRequest(prefix + gatewayPath, {origin: profile.member_api_origin, host, token});
   const response = await f.handler(input), result = await response.json();
   assert.equal(response.status, 503);
   assert.equal(result.code, 'gateway_upload_held');
   assert.equal(result.receipt, undefined);
   assert.equal(JSON.stringify(result).includes(syntheticMessage), false);
   assert.equal(response.headers.get('access-control-allow-origin'), profile.member_api_origin);
   assert.match(response.headers.get('cache-control'), /no-store/);
   assert.equal(input.bodyUsed, false, 'The runtime wrapper must not consume the source body');
  }
 }
 assertNoEffects(f);
});

test('allowed preflight remains available and a denied origin wins before the hold', async t => {
 const f = fixture(t);
 for (const prefix of prefixes) {
  const allowed = await f.handler(makeRequest(prefix + gatewayPath, {origin: profile.member_api_origin, method: 'OPTIONS'}));
  assert.equal(allowed.status, 204);
  assert.equal(allowed.headers.get('access-control-allow-origin'), profile.member_api_origin);
  for (const method of ['OPTIONS', 'POST']) {
   const denied = await f.handler(makeRequest(prefix + gatewayPath, {origin: 'https://denied.example.invalid', method}));
   assert.equal(denied.status, 403);
   assert.equal((await denied.json()).code, 'origin_denied');
   assert.equal(denied.headers.get('access-control-allow-origin'), null);
  }
 }
 assertNoEffects(f);
});

test('invalid deployment profile wins before the hold', async t => {
 const f = fixture(t, {changes: {COLLECT_DEPLOYMENT_PROFILE_SHA256: '0'.repeat(64)}});
 for (const prefix of prefixes) {
  const response = await f.handler(makeRequest(prefix + gatewayPath, {origin: profile.member_api_origin}));
  assert.equal(response.status, 503);
  assert.equal((await response.json()).code, 'backend_unavailable');
 }
 assertNoEffects(f);
});

test('the Admin function still rejects the member gateway path', async t => {
 const f = fixture(t, {functionName: 'admin-api'});
 for (const prefix of ['/functions/v1/admin-api', '/admin-api']) {
  const response = await f.handler(makeRequest(prefix + gatewayPath, {origin: profile.admin_origin}));
  assert.equal(response.status, 404);
  assert.equal((await response.json()).code, 'not_found');
 }
 assertNoEffects(f);
});

test('near-miss and member routes continue to the normal runtime boundary', async t => {
 const f = fixture(t);
 const cases = [
  ['/functions/v1/collect-api' + gatewayPath + '/', 'POST'],
  ['/collect-api' + gatewayPath + '-other', 'POST'],
  ['/functions/v1/collect-api' + gatewayPath, 'GET'],
  ['/collect-api/v1/functions/ingest-client-sms', 'POST'],
 ];
 for (const [path, method] of cases) {
  const response = await f.handler(makeRequest(path, {origin: profile.member_api_origin, method}));
  assert.equal(response.status, 503);
  assert.equal((await response.json()).code, 'backend_unavailable');
 }
 assert.ok(f.counts.construct > 0, 'Normal routes must reach the synthetic database-construction boundary');
 assert.equal(f.counts.begin, cases.length);
 assert.equal(f.counts.reserve, 0);
 assert.equal(f.counts.admission, 0);
 assert.equal(f.counts.network, 0);
});

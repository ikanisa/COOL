import test from './helpers/fenced-node-test.js';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {SupabaseNativeTransport} from '../storage/supabase-transport.js';
import {ProtectedStorageProtocol} from '../storage/protocol.js';

const capturedBytes = await readFile(new URL('./fixtures/native-storage-missing-response.fixture.json', import.meta.url));
assert.equal(createHash('sha256').update(capturedBytes).digest('hex'), '0ddb54e0c7ca0fe6d69cc7f3a2ce2e5b740df08d6214c21b61f9c82f60d422a2');
const captured = JSON.parse(capturedBytes);
const head = captured.results.find(value => value.method === 'HEAD');
const get = captured.results.find(value => value.method === 'GET');
const missing = JSON.parse(get.body);
const project = 'https://rrlduytparvsjfmegalh.supabase.co';
const bucket = {id: 'collect-evidence', name: 'collect-evidence', public: false};
const key = 'qualification/synthetic-never-created.enc';

function fixture({headStatus = head.httpStatus, getStatus = get.httpStatus, body = get.body,
  contentType = get.contentType, headHeaders = {}, getHeaders = {}, buckets = [bucket, bucket], failAt} = {}) {
  const calls = []; let bucketReads = 0;
  const transport = new SupabaseNativeTransport({url: project, secretKey: 'sb_secret_synthetic_fixture_only', fetchImpl: async (url, init) => {
    const method = init.method; const path = new URL(url).pathname;
    calls.push({method, path});
    assert.equal(new URL(url).origin, project); assert.equal(init.redirect, 'error');
    assert.ok(['GET', 'HEAD'].includes(method), 'This fixture permits no upload, delete, list or provider mutation');
    if (path === '/storage/v1/bucket/collect-evidence') {
      assert.equal(method, 'GET');
      if (failAt === 'bucket') throw new TypeError('Synthetic bucket outcome unknown');
      const item = buckets[Math.min(bucketReads++, buckets.length - 1)];
      if (item instanceof Response) return item;
      return Response.json(item);
    }
    assert.equal(path, '/storage/v1/object/authenticated/collect-evidence/' + key);
    if (failAt === method) throw new TypeError('Synthetic object outcome unknown');
    if (method === 'HEAD') return new Response(null, {status: headStatus, headers: headHeaders});
    return new Response(body, {status: getStatus, headers: {'Content-Type': contentType, ...getHeaders}});
  }});
  return {transport, calls};
}
function protocol(transport, journal = {}) { return new ProtectedStorageProtocol({transport, journal}); }
async function inconclusive(options) {
  const {transport, calls} = fixture(options); const observed = await transport.probe(key);
  assert.equal(observed.absent, false); assert.equal(observed.bucketVerified, false);
  assert.equal(protocol(transport).provesAbsent(observed), false);
  assert.ok(calls.every(call => ['GET', 'HEAD'].includes(call.method)));
  return {observed, calls};
}

test('retained actual HTTP400 typed404 response qualifies only with explicit wire status evidence', async () => {
  assert.equal(captured.readOnly, true); assert.equal(head.bodyBytes, 0);
  assert.equal(get.bodyBytes, 88); assert.equal(new TextEncoder().encode(get.body).length, get.bodyBytes);
  const {transport, calls} = fixture(); const observed = await transport.probe(key);
  assert.equal(observed.absent, true); assert.equal(observed.bucketVerified, true);
  assert.equal(observed.headStatus, 404); assert.equal(observed.getStatus, 404);
  assert.equal(observed.httpHeadStatus, 400); assert.equal(observed.httpGetStatus, 400);
  assert.equal(observed.storageStatusCode, '404'); assert.equal(observed.storageErrorCode, 'NoSuchKey');
  assert.equal(observed.absenceStatusBasis, 'supabase_legacy_nosuchkey_v1');
  assert.deepEqual(calls.map(call => call.method + ' ' + call.path), [
    'GET /storage/v1/bucket/collect-evidence',
    'HEAD /storage/v1/object/authenticated/collect-evidence/' + key,
    'GET /storage/v1/object/authenticated/collect-evidence/' + key,
    'GET /storage/v1/bucket/collect-evidence',
  ]);
  assert.equal(protocol(transport).provesAbsent(observed), true);
  assert.equal(await protocol(transport).readAndVerify({key, operationId: 'synthetic-put'}, {allowMissing: true}), null);
});

test('initial and final exact private bucket identities are both required', async t => {
  const invalid = [{...bucket, public: true}, {...bucket, public: undefined}, {...bucket, id: 'another'}, {...bucket, name: 'another'}];
  for (const [index, value] of invalid.entries()) {
    await t.test('initial bucket mismatch ' + index, async () => {
      const {calls} = await inconclusive({buckets: [value, bucket]}); assert.equal(calls.length, 1);
    });
    await t.test('final bucket mismatch ' + index, async () => {
      const {observed, calls} = await inconclusive({buckets: [bucket, value]});
      assert.equal(observed.headStatus, 400); assert.equal(observed.getStatus, 400); assert.equal(calls.length, 4);
    });
  }
});

test('mixed statuses and authentication, bucket or generic HTTP errors never prove absence', async t => {
  for (const [a, b] of [[400,404], [404,400], [400,200], [200,400], [404,200], [200,404], [401,401], [403,403], [429,429], [500,500], [503,503], [301,301]]) {
    await t.test(a + '/' + b, async () => {
      const {observed, calls} = await inconclusive({headStatus:a, getStatus:b});
      assert.equal(observed.headStatus, a); assert.equal(observed.getStatus, b); assert.equal(calls.length, 3);
    });
  }
});

test('HTTP400 requires the exact observed typed missing-object envelope', async t => {
  const bodies = [
    {...missing, statusCode: 404}, {...missing, statusCode:'400'}, {...missing, statusCode:'403'},
    {...missing, code:'AccessDenied'}, {...missing, code:'NoSuchBucket'}, {...missing, error:'Unauthorized'},
    {...missing, message:'Bucket not found'}, {...missing, status:404},
    {code:'NoSuchKey'}, {statusCode:'404', message:'Object not found'},
    {}, null, [], 'Object not found',
  ];
  for (const [index, body] of bodies.entries()) {
    await t.test('unqualified envelope ' + index, async () => {
      const result = await inconclusive({body:JSON.stringify(body)}); assert.equal(result.calls.length, 3);
    });
  }
});

test('modern and legacy HTTP404 object-missing formats retain their existing semantic contract', async t => {
  const bodies = [{code:'NoSuchKey'}, {error:'NoSuchKey'}, {code:'NoSuchKey', message:'The specified key does not exist.'},
    {statusCode:'404', error:'Not Found', message:'Object not found'}, {status:404, message:'The resource was not found'}, missing];
  for (const [index, body] of bodies.entries()) {
    await t.test('HTTP404 missing object ' + index, async () => {
      const {transport, calls} = fixture({headStatus:404, getStatus:404, body:JSON.stringify(body)});
      const observed = await transport.probe(key);
      assert.deepEqual(observed, {headStatus:404, getStatus:404, absent:true, bucketVerified:true}); assert.equal(calls.length, 4);
    });
  }
});

test('HTTP404 bodies with explicit authentication, bucket or contradictory status evidence stay unknown', async t => {
  for (const [index, body] of [
    {...missing, code:'AccessDenied'}, {...missing, code:'NoSuchBucket'}, {...missing, error:'Unauthorized'},
    {...missing, message:'Access denied'}, {...missing, statusCode:'403'}, {...missing, status:401},
    {statusCode:'404', code:'InvalidJWT', message:'Object not found'}, [],
  ].entries()) {
    await t.test('contradictory HTTP404 envelope ' + index, async () => {
      const {calls} = await inconclusive({headStatus:404, getStatus:404, body:JSON.stringify(body)}); assert.equal(calls.length, 3);
    });
  }
});

test('legacy missing-object evidence must be bounded complete JSON with valid UTF8', async t => {
  await t.test('wrong MIME', async () => { await inconclusive({contentType:'text/html'}); });
  for (const [name, options] of [
    ['malformed JSON', {body:'{"statusCode":'}], ['invalid UTF8', {body:new Uint8Array([0xff])}],
    ['oversized response', {body:' '.repeat(4097)}], ['truncated length', {getHeaders:{'Content-Length':'999'}}],
    ['invalid length', {getHeaders:{'Content-Length':'not-an-integer'}}],
  ]) {
    await t.test(name, async () => {
      const {transport, calls} = fixture(options);
      await assert.rejects(() => transport.probe(key), {code:'storage_response_invalid'}); assert.equal(calls.length, 3);
    });
  }
});

test('network or bucket verification failures stay unknown without retry or mutation', async t => {
  for (const failAt of ['bucket', 'HEAD', 'GET']) {
    await t.test(failAt, async () => {
      const {transport, calls} = fixture({failAt}); await assert.rejects(() => transport.probe(key), TypeError);
      assert.equal(calls.length, {bucket:1, HEAD:2, GET:3}[failAt]);
    });
  }
});

test('present bytes, length and ETag verification are unaffected', async () => {
  const bytes = new TextEncoder().encode('synthetic retained object');
  const {transport, calls} = fixture({headStatus:200, getStatus:200, body:bytes, contentType:'application/octet-stream',
    headHeaders:{'Content-Length':String(bytes.length), ETag:'fixture-head'}, getHeaders:{ETag:'fixture-get'}});
  const observed = await transport.probe(key);
  assert.equal(observed.absent, false); assert.equal(observed.bucketVerified, true);
  assert.deepEqual(observed.bytes, bytes); assert.equal(observed.etag, 'fixture-get'); assert.equal(calls.length, 3);
});

test('present HEAD/GET byte mismatch cannot be normalized to absence', async () => {
  const {transport} = fixture({headStatus:200, getStatus:200, body:'synthetic', headHeaders:{'Content-Length':'999'}});
  await assert.rejects(() => transport.probe(key), {code:'storage_head_get_mismatch'});
});

test('existing requireAbsent deletion consumes typed absence without issuing a provider DELETE', async () => {
  const {transport, calls} = fixture(); let commits = 0; let state = 'pending';
  const journal = {async beginDelete(intent) {return {...intent,state};}, async recordDeleteOutcome() {assert.fail('No provider delete is needed');},
    async commitDelete(intent, proof) {assert.deepEqual(proof,{headStatus:404,getStatus:404,bucketVerified:true}); commits++; state='committed';},
    async getDeleteStatus() {return {intent:{state},metadata:null};}};
  const result = await protocol(transport, journal).delete(key, {operationId:'synthetic-delete', scope:{ownerId:'fixture-owner',entityId:'fixture-entity',purpose:'qualification'},
    expectedSha256:'a'.repeat(64), authorize:async()=>true, requireAbsent:true});
  assert.equal(result.absenceVerified, true); assert.equal(commits, 1);
  assert.equal(calls.length, 12); assert.ok(calls.every(call=>['GET','HEAD'].includes(call.method)));
});

test('generic HTTP400 leaves the delete intent uncommitted and never sends a provider DELETE', async () => {
  const {transport, calls} = fixture({body:JSON.stringify({...missing,code:'AccessDenied'})}); let commits = 0;
  const journal = {async beginDelete(intent) {return {...intent,state:'pending'};}, async commitDelete() {commits++;},
    async recordDeleteOutcome() {assert.fail('No provider mutation is permitted');}};
  await assert.rejects(() => protocol(transport,journal).delete(key,{operationId:'synthetic-delete',scope:{ownerId:'fixture-owner',entityId:'fixture-entity',purpose:'qualification'},
    expectedSha256:'a'.repeat(64),authorize:async()=>true,requireAbsent:true}),{code:'storage_absence_unconfirmed'});
  assert.equal(commits, 0); assert.equal(calls.length, 3);
});

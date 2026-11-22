import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import test from 'node:test';
import { HELD_V2_MIGRATION_SHA, HELD_V2_PROTOCOL } from './catalog.mjs';
import { createHeldRecoveryV2Candidate } from './protocol.mjs';

const sourceSha256 = 'a'.repeat(64);
const groupId = 'test-collection';
const actor = { id: 'test-admin', groupId, installationId: 'test-installation', generation: '3' };
const binding = {
  requestId: '11111111-1111-4111-8111-111111111111',
  groupId,
  actorId: actor.id,
  installationId: actor.installationId,
  generation: actor.generation,
};
const input = {
  requestId: binding.requestId,
  rawSender: 'Synthetic sender',
  rawBody: 'Synthetic example observation',
  sourceMode: 'catch_up',
  complete: false,
  capturedAt: '2026-11-11T12:01:00Z',
  serviceCentreAt: null,
  inboxReceivedAt: '2026-11-11T12:00:00Z',
  subscriptionId: null,
  sourceKey: 'b'.repeat(64),
  expectedConsentGeneration: 7,
};
const headers = {
  'content-type': 'application/json',
  'x-burimunsi-held-source-sha256': sourceSha256,
  'x-burimunsi-held-migration-sha256': HELD_V2_MIGRATION_SHA,
};
const makeRequest = (operation, overrides) => ({
  operation, actor, binding, headers: new Headers(headers), ...overrides,
});
const makeCandidate = (observations) =>
  createHeldRecoveryV2Candidate({ enabled: true, sourceSha256, groupId, observations });
const bodySha256 = createHash('sha256').update(input.rawBody).digest('hex');
const held = {
  requestId: input.requestId,
  sourceId: 'test-source',
  bodySha256,
  status: 'source_unresolved',
  financialEffects: 0,
  autoProcessing: 'held',
  protocol: HELD_V2_PROTOCOL,
  expectedConsentGeneration: 7,
};
const acknowledged = {
  requestId: input.requestId,
  sourceKey: input.sourceKey,
  sourceId: held.sourceId,
  bodySha256,
  state: 'acknowledged',
  autoProcessing: 'held',
  financialEffects: 0,
  retryAllowed: false,
  protocol: HELD_V2_PROTOCOL,
  expectedConsentGeneration: 7,
};

test('the candidate is disabled by default before accessing the body or service port', async () => {
  const run = createHeldRecoveryV2Candidate({
    sourceSha256, groupId,
    observations: { recoverHeldV2() { assert.fail('Unexpected hold'); } },
  });
  const request = makeRequest('observationRecoveryV2Hold', { readBody: () => assert.fail('Unexpected raw body') });
  await assert.rejects(run(request), { status: 404 });
});

test('collection, account, installation, session and release pins precede raw body access', async () => {
  const run = makeCandidate({ recoverHeldV2() { assert.fail('Unexpected hold'); } });
  const request = makeRequest('observationRecoveryV2Hold', { readBody: () => assert.fail('Unexpected raw body') });
  for (const name of Object.keys(headers).filter((name) => name.startsWith('x-burimunsi-'))) {
    for (const value of [null, 'invalid', 'c'.repeat(64), headers[name] + ', ' + headers[name]]) {
      const changed = new Headers(headers);
      if (value === null) changed.delete(name);
      else changed.set(name, value);
      await assert.rejects(run({ ...request, headers: changed }), { status: 403 });
    }
  }
  for (const field of ['id', 'groupId', 'installationId', 'generation']) {
    await assert.rejects(run({ ...request, actor: { ...actor, [field]: 'different' } }), { status: 403 });
  }
});

test('capability binds the release, collection and original consent and is never cached', async () => {
  const expected = {
    protocol: HELD_V2_PROTOCOL, groupId, sourceSha256, migrationSha256: HELD_V2_MIGRATION_SHA, consentGeneration: 7,
  };
  const request = makeRequest('observationRecoveryV2Capability', {
    rawQuery: 'expectedConsentGeneration=7', readBody: () => assert.fail('Unexpected raw body'),
  });
  const run = makeCandidate({
    recoveryV2Capability(account, generation, release) {
      assert.equal(account, actor);
      assert.equal(generation, 7);
      assert.deepEqual(release, { sourceSha256, migrationSha256: HELD_V2_MIGRATION_SHA });
      return expected;
    },
  });
  assert.deepEqual(await run(request), {
    headers: { 'cache-control': 'no-store' },
    body: { contractVersion: 'burimunsi.native.v1', ok: true, binding, data: expected },
  });
  for (const query of ['', 'expectedConsentGeneration=07', 'expectedConsentGeneration=9007199254740992',
    'expectedConsentGeneration=7&expectedConsentGeneration=7']) {
    await assert.rejects(run({ ...request, rawQuery: query }), { status: 400 });
  }
  for (const field of Object.keys(expected)) {
    const wrong = makeCandidate({ recoveryV2Capability: () => ({ ...expected, [field]: 'wrong' }) });
    await assert.rejects(wrong(request), { status: 503 });
  }
});

test('hold dispatches only exact, consent-bound native requests and rejects legacy success', async () => {
  const operation = 'observationRecoveryV2Hold';
  let calls = 0;
  const run = makeCandidate({
    recoverHeldV2(account, observation) {
      assert.equal(account, actor);
      assert.deepEqual({ ...observation }, input);
      calls += 1;
      return held;
    },
  });
  const { expectedConsentGeneration, ...legacy } = input;
  for (const invalid of [legacy, { ...input, expectedConsentGeneration: 0 },
    { ...input, requestId: '33333333-3333-4333-8333-333333333333' }]) {
    await assert.rejects(run(makeRequest(operation, { readBody: () => JSON.stringify(invalid) })), { status: 400 });
  }
  assert.equal(calls, 0);
  const request = makeRequest(operation, { readBody: () => JSON.stringify(input) });
  assert.deepEqual((await run(request)).body.data, held);
  assert.equal(calls, 1);
  const { protocol, ...legacyResponse } = held;
  const wrong = makeCandidate({ recoverHeldV2: () => legacyResponse });
  await assert.rejects(wrong(request), { status: 503 });
});

test('ACK is a dedicated read-only port and exposes proof only for the exact submission', async () => {
  const request = makeRequest('observationRecoveryV2Ack', { readBody: () => JSON.stringify(input) });
  const run = (data) => makeCandidate({
    recoverHeldV2() { assert.fail('ACK must not dispatch a hold'); },
    recoverHeldV2Ack: () => data,
  })(request);
  assert.deepEqual((await run(acknowledged)).body.data, acknowledged);
  const unconfirmed = { ...acknowledged, state: 'unconfirmed', sourceId: null, autoProcessing: 'unknown' };
  assert.deepEqual((await run(unconfirmed)).body.data, unconfirmed);
  for (const drift of [{ sourceKey: bodySha256 }, { bodySha256: input.sourceKey }, { retryAllowed: true },
    { financialEffects: 1 }, { expectedConsentGeneration: 8 }, { state: 'unconfirmed' }]) {
    await assert.rejects(run({ ...acknowledged, ...drift }), { status: 503 });
  }
});

test('candidate operations and SQL stay outside the active profile and migration chain', () => {
  const load = (path) => JSON.parse(readFileSync(new URL(path, import.meta.url), 'utf8'));
  const candidate = load('./contract.json');
  const published = load('../../../contracts/burimunsi-api/profile.json');
  for (const [, path, operation] of candidate.routes) {
    assert.equal(published.routes.some(([, livePath, liveOperation]) =>
      livePath === path || liveOperation === operation), false);
  }
  const migrations = readdirSync(new URL('../../../supabase/migrations/', import.meta.url));
  const fixtures = readdirSync(new URL('./sql/', import.meta.url));
  assert.equal(fixtures.length, 4);
  for (const fixture of fixtures) assert.equal(migrations.includes(fixture), false);
});

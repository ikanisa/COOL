import {test} from './helpers/fenced-node-test.js';
import assert from 'node:assert/strict';
import {startOtp} from './helpers/module-domain-auth.js';
import {ApiError} from '../domain/core.js';

// Intended path: _shared/tests/known-member-bootstrap.test.mjs.
// Actual startOtp, in-memory admission/reservation and fully intercepted GoTrue.
// No PostgreSQL, provider sends, provider policy acceptance or codec execution.
const PROJECT = 'https://collect-auth.invalid';
const PUBLIC_KEY = 'sb_publishable_synthetic_bootstrap_only';
const PRINCIPAL = '11111111-1111-4111-8111-111111111111';
const EMAIL = 'synthetic.member@example.invalid', PHONE = '+250788000001';
const CAPTCHA = 'synthetic-captcha-proof';
const CASES = [
  {name: 'email', body: {email: EMAIL}, type: 'email', identity: EMAIL, channel: 'email'},
  {name: 'explicit WhatsApp', body: {phone: PHONE, channel: 'whatsapp'}, type: 'phone', identity: PHONE, channel: 'whatsapp'},
  {name: 'default WhatsApp', body: {phone: PHONE}, type: 'phone', identity: PHONE, channel: 'whatsapp'},
  {name: 'SMS', body: {phone: PHONE, channel: 'sms'}, type: 'phone', identity: PHONE, channel: 'sms'},
];
const IDENTITIES = [CASES[0], CASES[1]];
const OPT_OUTS = [{should_create_user: false}, {allow_registration: false},
  {should_create_user: false, allow_registration: false}];

class Statement {
  values = [];
  constructor(db, sql) { this.db = db; this.sql = sql; }
  bind(...values) { this.values = values; return this; }
  async first() {
    assert.match(this.sql, /^SELECT (?:a\.)?id FROM /, 'Only local eligibility is queried by this fixture');
    this.db.lookups.push({sql: this.sql, values: [...this.values]});
    return this.db.eligible ? {id: PRINCIPAL} : null;
  }
  async run() {
    assert.ok(this.sql.startsWith('UPDATE private.supabase_otp_challenges SET delivery_status='),
      'startOtp must not create application principals, roles or session projections');
    const [status, id] = this.values, row = this.db.reservations.find(row => row.id === id);
    assert.ok(row, 'Delivery status belongs to a reserved challenge'); row.delivery = status;
    this.db.updates.push({id, status}); return {meta: {changes: 1}};
  }
}
class Database {
  lookups = []; batches = []; reservations = []; updates = [];
  constructor(eligible) { this.eligible = eligible; }
  prepare(sql) { return new Statement(this, sql); }
  async batch(statements) {
    assert.equal(statements.length, 3);
    assert.ok(statements[0].sql.startsWith('INSERT INTO admin_bridge_guards('));
    assert.ok(statements[1].sql.startsWith('INSERT INTO private.supabase_otp_challenges('));
    assert.ok(statements[2].sql.startsWith('DELETE FROM admin_bridge_guards '));
    this.batches.push(statements);
    const [id, , type, identity, surface, registrationAllowed, createdAt, expiresAt] = statements[1].values;
    this.reservations.push({id, type, identity, surface, registrationAllowed, createdAt, expiresAt, delivery: 'reserved'});
    return statements.map(() => ({meta: {changes: 1}}));
  }
}

async function fixture(options, check) {
  const db = new Database(options.eligible ?? true), calls = [];
  // Managed identity existence is deliberately independent of local membership.
  const provider = {hasIdentity: options.managedIdentity ?? false, created: 0};
  const env = {DB: db, SUPABASE_URL: PROJECT, SUPABASE_PUBLISHABLE_KEY: PUBLIC_KEY,
    AUTH_MEMBER_REGISTRATION_ENABLED: options.registration ? 'true' : 'false'};
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init), body = await request.json();
    calls.push({url: request.url, method: request.method, redirect: request.redirect, headers: request.headers, body});
    // Pinned GoTrue otp.go shouldCreateUser rejects an absent Auth identity with
    // 422 otp_disabled when create_user is false; it does not inspect Collect membership.
    if (body.email && body.channel) return Response.json({error_code: 'synthetic_email_channel_invalid'}, {status: 400});
    if (body.phone && !['sms', 'whatsapp'].includes(body.channel)) return Response.json({error_code: 'synthetic_phone_channel_invalid'}, {status: 400});
    if (typeof options.mode === 'number') return Response.json({error_code: 'synthetic_provider_rejected'}, {status: options.mode});
    if (options.mode === 'network') throw new TypeError('synthetic unconfirmed transport');
    if (!provider.hasIdentity && body.create_user !== true) {
      return Response.json({error_code: 'otp_disabled'}, {status: 422});
    }
    if (!provider.hasIdentity) { provider.hasIdentity = true; provider.created++; }
    if (options.mode === 'lost-after-create') throw new TypeError('synthetic committed provider reply lost');
    return Response.json({message_id: 'synthetic-no-delivery'});
  };
  try { await check({db, env, calls, provider, start: body => startOtp(env, {captcha_token: CAPTCHA, ...body})}); }
  finally {
    globalThis.fetch = originalFetch;
    // Run after restoration so even a failed assertion never leaves a fetch stub.
    for (const call of calls) {
      assert.equal(call.url, PROJECT + '/auth/v1/otp'); assert.equal(call.method, 'POST');
      assert.equal(call.redirect, 'error'); assert.equal(call.headers.get('Content-Type'), 'application/json');
      assert.equal(call.headers.get('apikey'), PUBLIC_KEY); assert.equal(call.headers.has('Authorization'), false);
    }
  }
}

const errorIs = (status, code) => error => error instanceof ApiError && error.status === status && error.code === code;
function wire(call, item, createUser) {
  assert.deepEqual(call.body, {[item.type]: item.identity, create_user: createUser,
    ...(item.type === 'phone' ? {channel: item.channel} : {}), gotrue_meta_security: {captcha_token: CAPTCHA}});
  if (item.type === 'email') assert.equal(Object.hasOwn(call.body, 'channel'), false);
}
function challenge(result, db, item, {registration = false, surface = 'member', delivery = 'accepted'} = {}) {
  assert.equal(db.batches.length, 1); assert.equal(db.reservations.length, 1);
  const row = db.reservations[0];
  assert.equal(row.id, result.challenge_id); assert.equal(row.type, item.type); assert.equal(row.identity, item.identity);
  assert.equal(row.surface, surface); assert.equal(row.registrationAllowed, Number(registration));
  assert.equal(row.expiresAt - row.createdAt, 300); assert.equal(row.delivery, delivery);
  assert.deepEqual(result, {challenge_id: row.id, retry_after: 60, expires_in: 300, channel: item.channel, delivery_status: delivery});
  assert.deepEqual(db.updates, [{id: row.id, status: delivery}]);
}
function denied(db, calls) {
  assert.equal(db.lookups.length, 1); assert.equal(db.batches.length, 0);
  assert.equal(db.reservations.length, 0); assert.equal(db.updates.length, 0); assert.equal(calls.length, 0);
}

// Sequential subtests own the temporary global fetch stub, restored in finally.
test('eligible local member managed-Auth bootstrap preserves registration and delivery boundaries', async t => {
  for (const item of CASES) {
    await t.test('known local ' + item.name + ' bootstraps an absent managed identity with public registration paused', async () => {
      await fixture({}, async ({start, db, calls, provider}) => {
        assert.equal(provider.hasIdentity, false);
        const result = await start(item.body); assert.equal(calls.length, 1); wire(calls[0], item, true);
        challenge(result, db, item); assert.equal(provider.created, 1); assert.equal(provider.hasIdentity, true);
      });
    });
  }
  await t.test('already-managed known member remains accepted without creating a second managed identity', async () => {
    await fixture({managedIdentity: true}, async ({start, db, calls, provider}) => {
      const result = await start(CASES[0].body); wire(calls[0], CASES[0], true);
      challenge(result, db, CASES[0]); assert.equal(calls.length, 1); assert.equal(provider.created, 0);
    });
  });
  for (const item of IDENTITIES) for (const optOut of OPT_OUTS) {
    await t.test('known ' + item.name + ' explicit opt-out stays false even with registration enabled: ' + JSON.stringify(optOut), async () => {
      await fixture({registration: true, managedIdentity: true}, async ({start, db, calls, provider}) => {
        const result = await start({...item.body, ...optOut}); assert.equal(calls.length, 1); wire(calls[0], item, false);
        challenge(result, db, item); assert.equal(provider.created, 0);
      });
    });
  }
  for (const item of IDENTITIES) {
    await t.test('privacy-style dual opt-out cannot create an absent managed ' + item.name + ' identity', async () => {
      await fixture({}, async ({start, db, calls, provider}) => {
        await assert.rejects(start({...item.body, should_create_user: false, allow_registration: false}), errorIs(422, 'otp_disabled'));
        assert.equal(calls.length, 1); wire(calls[0], item, false);
        assert.equal(db.reservations[0].registrationAllowed, 0); assert.equal(db.reservations[0].delivery, 'rejected');
        assert.deepEqual(db.updates, [{id: db.reservations[0].id, status: 'rejected'}]);
        assert.equal(provider.hasIdentity, false); assert.equal(provider.created, 0);
      });
    });
    await t.test('unknown local ' + item.name + ' cannot request bootstrap when registration is paused, even with both body flags true', async () => {
      await fixture({eligible: false, managedIdentity: true}, async ({start, db, calls}) => {
        await assert.rejects(start({...item.body, should_create_user: true, allow_registration: true}), errorIs(403, 'registration_unavailable'));
        denied(db, calls);
      });
    });
    await t.test('enabled public registration still permits an unknown local ' + item.name + ' identity', async () => {
      await fixture({eligible: false, registration: true}, async ({start, db, calls, provider}) => {
        const result = await start({...item.body, should_create_user: true, allow_registration: true});
        assert.equal(calls.length, 1); wire(calls[0], item, true); challenge(result, db, item, {registration: true});
        assert.equal(provider.created, 1);
      });
    });
    for (const optOut of OPT_OUTS) {
      await t.test('unknown local ' + item.name + ' opt-out remains denied when public registration is enabled: ' + JSON.stringify(optOut), async () => {
        await fixture({eligible: false, registration: true, managedIdentity: true}, async ({start, db, calls}) => {
          await assert.rejects(start({...item.body, ...optOut}), errorIs(403, 'registration_unavailable')); denied(db, calls);
        });
      });
    }
  }
  for (const optOut of OPT_OUTS) {
    await t.test('approved Admin keeps the existing preapproval bootstrap policy despite member opt-out: ' + JSON.stringify(optOut), async () => {
      await fixture({}, async ({start, db, calls, provider}) => {
        const result = await start({email: EMAIL, surface: 'admin', ...optOut});
        assert.equal(calls.length, 1); wire(calls[0], CASES[0], true);
        challenge(result, db, CASES[0], {surface: 'admin'}); assert.equal(provider.created, 1);
      });
    });
  }
  for (const registration of [false, true]) {
    await t.test('unknown Admin remains denied before reservation/provider regardless of public registration=' + registration, async () => {
      await fixture({eligible: false, registration}, async ({start, db, calls}) => {
        await assert.rejects(start({email: EMAIL, surface: 'admin', should_create_user: true, allow_registration: true}), error =>
          errorIs(403, 'admin_access_not_approved')(error) && error.message === 'This email does not have Admin access. Contact the super admin to be added.');
        denied(db, calls);
      });
    });
  }
  for (const mode of [400, 429]) {
    await t.test('provider ' + mode + ' remains a single rejected bootstrap delivery', async () => {
      await fixture({mode}, async ({start, db, calls, provider}) => {
        await assert.rejects(start(CASES[1].body), errorIs(mode, 'synthetic_provider_rejected'));
        assert.equal(calls.length, 1); wire(calls[0], CASES[1], true);
        assert.equal(db.reservations[0].registrationAllowed, 0); assert.equal(db.reservations[0].delivery, 'rejected');
        assert.deepEqual(db.updates, [{id: db.reservations[0].id, status: 'rejected'}]); assert.equal(provider.created, 0);
      });
    });
  }
  for (const mode of [503, 'network', 'lost-after-create']) {
    await t.test('provider ' + mode + ' remains unknown without automatic retry or false delivery acceptance', async () => {
      await fixture({mode}, async ({start, db, calls, provider}) => {
        const result = await start(CASES[1].body); assert.equal(calls.length, 1); wire(calls[0], CASES[1], true);
        challenge(result, db, CASES[1], {delivery: 'unknown'});
        if (mode === 'lost-after-create') assert.equal(provider.created, 1, 'A possibly committed provider operation is never replayed');
      });
    });
  }
});

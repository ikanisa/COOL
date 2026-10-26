import {fencedTest} from './helpers/fenced-unit.js';
import {assert, assertEquals} from 'jsr:@std/assert@1.0.14';
import {startOtp} from './helpers/module-domain-auth.js';
import {ApiError} from '../domain/core.js';

// Intended location: supabase/functions/_shared/tests/otp_wire.test.ts.
// In-memory DB and intercepted fetch only. No PostgreSQL or provider delivery.
// GoTrue's wire validator is independent of Collect's internal channel label:
// email plus a nonempty channel is rejected before any delivery is accepted.
const PROJECT = 'https://collect-auth.invalid';
const PUBLISHABLE_KEY = 'sb_publishable_synthetic_otp_wire_only';
const PRINCIPAL_ID = '11111111-1111-4111-8111-111111111111';
const EMAIL = 'synthetic.staff@example.invalid';
const PHONE = '+250788000001';
const CAPTCHA = 'synthetic-captcha-proof';
type Json = Record<string, unknown>;
type Captured = {url: string; method: string; headers: Headers; redirect: RequestRedirect; body: Json};
type Mode = 'accept' | 'network' | 'malformed' | 400 | 401 | 403 | 422 | 429 | 503;
type Reservation = {id: unknown; identityType: unknown; identity: unknown; surface: unknown;
  registrationAllowed: unknown; createdAt: unknown; expiresAt: unknown; delivery: string};

class FakeStatement {
  values: unknown[] = [];
  constructor(readonly db: FakeDB, readonly sql: string) {}
  bind(...values: unknown[]) { this.values = values; return this; }
  async first() {
    this.db.lookups.push(this);
    return this.db.eligible ? {id: PRINCIPAL_ID} : null;
  }
  async run() {
    assert(this.sql.startsWith('UPDATE private.supabase_otp_challenges SET delivery_status='),
      'Unexpected write in focused OTP fixture');
    this.db.deliveryUpdates.push({status: this.values[0], challengeId: this.values[1]});
    const reserved = this.db.reservations.find(row => row.id === this.values[1]);
    assert(reserved, 'Only a reserved local challenge may receive a delivery outcome');
    reserved.delivery = String(this.values[0]);
    return {meta: {changes: 1}};
  }
}

class FakeDB {
  lookups: FakeStatement[] = [];
  batches: FakeStatement[][] = [];
  reservations: Reservation[] = [];
  deliveryUpdates: {status: unknown; challengeId: unknown}[] = [];
  constructor(readonly eligible: boolean) {}
  prepare(sql: string) { return new FakeStatement(this, sql); }
  async batch(statements: FakeStatement[]) {
    this.batches.push(statements);
    const insert = statements.find(statement => statement.sql.startsWith('INSERT INTO private.supabase_otp_challenges('));
    assert(insert, 'OTP admission must reserve a local challenge before delivery');
    const [id, , identityType, identity, surface, registrationAllowed, createdAt, expiresAt] = insert.values;
    this.reservations.push({id, identityType, identity, surface, registrationAllowed, createdAt, expiresAt, delivery: 'reserved'});
    return statements.map(() => ({meta: {changes: 1}}));
  }
}

async function withProvider(
  options: {eligible?: boolean; registration?: boolean; mode?: Mode},
  check: (fixture: {env: {DB: FakeDB; SUPABASE_URL: string; SUPABASE_PUBLISHABLE_KEY: string;
    AUTH_MEMBER_REGISTRATION_ENABLED: string}; db: FakeDB; calls: Captured[]}) => Promise<void>,
) {
  const db = new FakeDB(options.eligible ?? true), calls: Captured[] = [];
  const env = {DB: db, SUPABASE_URL: PROJECT, SUPABASE_PUBLISHABLE_KEY: PUBLISHABLE_KEY,
    AUTH_MEMBER_REGISTRATION_ENABLED: options.registration ? 'true' : 'false'};
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input: Request | string | URL, init?: RequestInit) => {
    const request = new Request(input, init);
    const body = await request.json() as Json;
    calls.push({url: request.url, method: request.method, headers: request.headers, redirect: request.redirect, body});
    // Model the provider contract, rather than unconditional mocked success.
    if (typeof body.email === 'string' && typeof body.channel === 'string' && body.channel.length > 0) {
      return Response.json({error_code: 'validation_failed', msg: 'Email requests cannot specify a channel'}, {status: 400});
    }
    if (typeof body.phone === 'string' && !['sms', 'whatsapp'].includes(String(body.channel))) {
      return Response.json({error_code: 'validation_failed'}, {status: 400});
    }
    if (options.mode === 'network') throw new TypeError('synthetic transport outcome unavailable');
    if (options.mode === 'malformed') return new Response('{', {status: 200, headers: {'Content-Type': 'application/json'}});
    if (typeof options.mode === 'number') return Response.json({error_code: 'synthetic_provider_rejection'}, {status: options.mode});
    return Response.json({message_id: 'synthetic-no-delivery'});
  };
  try { await check({env, db, calls}); }
  finally {
    globalThis.fetch = originalFetch;
    // These checks also run after expected provider errors; authRequest cannot
    // swallow a stub assertion and accidentally satisfy an unknown-outcome test.
    for (const call of calls) {
      assertEquals(call.url, PROJECT + '/auth/v1/otp', 'Every provider request was intercepted at the exact OTP endpoint');
      assertEquals(call.method, 'POST');
      assertEquals(call.redirect, 'error');
      assertEquals(call.headers.get('Content-Type'), 'application/json');
      assertEquals(call.headers.get('apikey'), PUBLISHABLE_KEY);
      assertEquals(call.headers.has('Authorization'), false, 'OTP delivery does not need service-role or user credentials');
    }
  }
}

async function apiError(action: () => Promise<unknown>, status: number, code: string) {
  try { await action(); }
  catch (error) {
    assert(error instanceof ApiError, 'Expected the actual domain ApiError');
    assertEquals(error.status, status); assertEquals(error.code, code);
    return error;
  }
  throw new Error('Expected OTP admission or delivery to reject');
}

function accepted(result: any, db: FakeDB, identityType: string, identity: string, surface: string, registration: boolean, channel: string) {
  assertEquals(result.delivery_status, 'accepted'); assertEquals(result.channel, channel);
  assertEquals(result.retry_after, 60); assertEquals(result.expires_in, 300);
  assertEquals(db.reservations.length, 1); assertEquals(db.batches.length, 1);
  const reserved = db.reservations[0];
  assertEquals(reserved.id, result.challenge_id); assertEquals(reserved.identityType, identityType);
  assertEquals(reserved.identity, identity); assertEquals(reserved.surface, surface);
  assertEquals(reserved.registrationAllowed, Number(registration));
  assertEquals(Number(reserved.expiresAt) - Number(reserved.createdAt), 300);
  assertEquals(reserved.delivery, 'accepted');
  assertEquals(db.deliveryUpdates, [{status: 'accepted', challengeId: result.challenge_id}]);
  assertEquals(Object.hasOwn(result, 'access_token'), false);
  assertEquals(Object.hasOwn(result, 'refresh_token'), false);
}

// One sequential parent test owns the global fetch replacement. Every step
// restores it in finally, including assertions and expected provider failures.
fencedTest('OTP provider wire contract preserves admission, phone channels and delivery outcomes', async t => {
  await t.step('approved Admin email omits channel, keeps captcha and permits managed Auth creation', async () => {
    await withProvider({}, async ({env, db, calls}) => {
      const result = await startOtp(env, {email: '  Synthetic.Staff@Example.Invalid  ', surface: 'admin',
        should_create_user: false, captcha_token: CAPTCHA});
      assertEquals(calls.length, 1);
      assertEquals(calls[0].body, {email: EMAIL, create_user: true, gotrue_meta_security: {captcha_token: CAPTCHA}});
      assertEquals(Object.hasOwn(calls[0].body, 'channel'), false);
      accepted(result, db, 'email', EMAIL, 'admin', false, 'email');
    });
  });
  await t.step('existing member email bootstraps managed identity while public registration stays disabled', async () => {
    await withProvider({}, async ({env, db, calls}) => {
      const result = await startOtp(env, {email: EMAIL, surface: 'member', captcha_token: CAPTCHA});
      assertEquals(calls.length, 1);
      assertEquals(calls[0].body, {email: EMAIL, create_user: true, gotrue_meta_security: {captcha_token: CAPTCHA}});
      assertEquals(Object.hasOwn(calls[0].body, 'channel'), false);
      accepted(result, db, 'email', EMAIL, 'member', false, 'email');
    });
  });
  await t.step('explicit member creation opt-out is preserved even when registration is enabled', async () => {
    await withProvider({registration: true}, async ({env, db, calls}) => {
      const result = await startOtp(env, {email: EMAIL, should_create_user: false});
      assertEquals(calls.length, 1);
      assertEquals(calls[0].body, {email: EMAIL, create_user: false, gotrue_meta_security: {}});
      accepted(result, db, 'email', EMAIL, 'member', false, 'email');
    });
  });
  await t.step('enabled member registration still sends create_user=true without an email channel', async () => {
    await withProvider({eligible: false, registration: true}, async ({env, db, calls}) => {
      const result = await startOtp(env, {email: EMAIL, allow_registration: true, captcha_token: CAPTCHA});
      assertEquals(calls.length, 1);
      assertEquals(calls[0].body, {email: EMAIL, create_user: true, gotrue_meta_security: {captcha_token: CAPTCHA}});
      accepted(result, db, 'email', EMAIL, 'member', true, 'email');
    });
  });
  for (const channel of ['sms', 'whatsapp', undefined]) {
    await t.step('member phone preserves ' + (channel ?? 'default WhatsApp') + ' delivery channel', async () => {
      await withProvider({}, async ({env, db, calls}) => {
        const result = await startOtp(env, {phone: PHONE, surface: 'member', ...(channel ? {channel} : {}), captcha_token: CAPTCHA});
        assertEquals(calls.length, 1);
        assertEquals(calls[0].body, {phone: PHONE, create_user: true, channel: channel ?? 'whatsapp', gotrue_meta_security: {captcha_token: CAPTCHA}});
        accepted(result, db, 'phone', PHONE, 'member', false, channel ?? 'whatsapp');
      });
    });
  }
  await t.step('unknown Admin email is denied before reservation or provider delivery even with member registration enabled', async () => {
    await withProvider({eligible: false, registration: true}, async ({env, db, calls}) => {
      const error = await apiError(() => startOtp(env, {email: EMAIL, surface: 'admin'}), 403, 'admin_access_not_approved');
      assertEquals(error.message, 'This email does not have Admin access. Contact the super admin to be added.');
      assertEquals(calls.length, 0); assertEquals(db.batches.length, 0); assertEquals(db.reservations.length, 0); assertEquals(db.deliveryUpdates.length, 0);
    });
  });
  for (const status of [400, 401, 403, 422, 429] as const) {
    await t.step('provider ' + status + ' remains a rejected delivery, with one request and no accepted challenge', async () => {
      await withProvider({mode: status}, async ({env, db, calls}) => {
        const error = await apiError(() => startOtp(env, {email: EMAIL, surface: 'admin', captcha_token: CAPTCHA}), status, 'synthetic_provider_rejection');
        if (status === 429) assertEquals(error.message, 'Too many attempts. Try again later.');
        assertEquals(calls.length, 1); assertEquals(Object.hasOwn(calls[0].body, 'channel'), false);
        assertEquals(db.reservations.length, 1); assertEquals(db.reservations[0].delivery, 'rejected');
        assertEquals(db.deliveryUpdates, [{status: 'rejected', challengeId: db.reservations[0].id}]);
      });
    });
  }
  for (const mode of [503, 'network', 'malformed'] as const) {
    await t.step('provider ' + mode + ' remains an unknown delivery without retry or false acceptance', async () => {
      await withProvider({mode}, async ({env, db, calls}) => {
        const result = await startOtp(env, {email: EMAIL, surface: 'admin', captcha_token: CAPTCHA});
        assertEquals(calls.length, 1); assertEquals(Object.hasOwn(calls[0].body, 'channel'), false);
        assertEquals(result.delivery_status, 'unknown'); assertEquals(result.channel, 'email');
        assertEquals(result.challenge_id, db.reservations[0].id); assertEquals(result.retry_after, 60); assertEquals(result.expires_in, 300);
        assertEquals(db.reservations[0].delivery, 'unknown');
        assertEquals(db.deliveryUpdates, [{status: 'unknown', challengeId: result.challenge_id}]);
        assertEquals(Object.hasOwn(result, 'access_token'), false);
      });
    });
  }
});

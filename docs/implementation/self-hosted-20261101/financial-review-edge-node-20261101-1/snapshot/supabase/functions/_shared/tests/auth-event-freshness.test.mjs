import {test} from './helpers/fenced-node-test.js';
import assert from 'node:assert/strict';
import {projectSession, handleAuth} from './helpers/module-domain-auth.js';
import {ApiError} from '../domain/core.js';

// Intended snapshot/canonical path: _shared/tests/auth-event-freshness.test.mjs.
// Actual domain functions, in-memory query responses and fully intercepted HTTP.
// These fixtures do not establish PostgreSQL trigger or hosted GoTrue behavior.
const NOW = 1_792_497_600;
const AUTH_USER = '11111111-1111-4111-8111-111111111111';
const SESSION = '22222222-2222-4222-8222-222222222222';
const PRINCIPAL = '33333333-3333-4333-8333-333333333333';
const FACTOR = '44444444-4444-4444-8444-444444444444';
const PROJECT = 'https://collect-auth.invalid';
const TOKEN = 'synthetic-cached-managed-user-token';
// Current Collect first-factor flows, confirmed against GoTrue's AMR methods.
const FIRST_FACTOR_METHODS = ['otp', 'password', 'oauth'];
const NON_BASELINE_METHODS = ['email', 'sms', 'whatsapp', 'google', 'totp', 'mfa/totp',
  'token_refresh', 'recovery', 'invite', 'anonymous', 'signup', 'magiclink'];
const clone = value => value == null ? value : structuredClone(value);
const session = (authAt, patch = {}) => ({id: SESSION, user_id: PRINCIPAL, surface: 'member',
  auth_at: authAt, created_at: NOW - 600, expires_at: NOW + 3600, revoked_at: null,
  assurance_level: 1, mfa_at: null, mfa_factor_id: null, ...patch});

class Statement {
  values = [];
  constructor(db, sql) { this.db = db; this.sql = sql; }
  bind(...values) { this.values = values; return this; }
  async first() {
    const db = this.db; db.reads.push({sql: this.sql, values: this.values});
    if (this.sql.startsWith('SELECT private.is_managed_session(')) return {allowed: db.options.managed !== false};
    if (this.sql.startsWith('SELECT user_id FROM private.auth_principal_links ')) return {user_id: PRINCIPAL};
    if (this.sql.startsWith('SELECT * FROM users WHERE id=')) return {id: PRINCIPAL,
      access_status: db.options.principalActive === false ? 'suspended' : 'active',
      full_name: 'Synthetic member', public_id: '100001'};
    if (this.sql.startsWith('SELECT * FROM auth_sessions WHERE id=')) return clone(db.row);
    if (this.sql.startsWith('SELECT a.id FROM admin_sessions ')) return db.options.admission ? {id: 'synthetic-approved-admin'} : null;
    if (this.sql.startsWith('SELECT private.session_expiry(')) return {expires_at: this.values[0]};
    if (this.sql.startsWith('SELECT status FROM auth_mfa_factors ')) return {status: db.options.factorStatus ?? 'unverified'};
    throw new Error('Unexpected query in focused projection fixture: ' + this.sql);
  }
  async all() {
    assert.ok(this.sql.startsWith('SELECT g.permission FROM admin_grants '));
    return {results: [{permission: 'account.manage'}]};
  }
  async run() {
    const db = this.db; db.writes.push({sql: this.sql, values: [...this.values]});
    if (this.sql.startsWith('INSERT INTO auth_sessions(')) {
      // Model a real ON CONFLICT winner created after the initial SELECT. The
      // caller must use the authoritative row read back after this statement.
      if (!db.row && db.options.winningRow) db.row = clone(db.options.winningRow);
      if (!db.row) db.row = session(this.values[3], {id: this.values[0], user_id: this.values[1],
        surface: this.values[2], created_at: this.values[4], expires_at: this.values[5]});
      return {meta: {changes: db.options.winningRow ? 0 : 1}};
    }
    throw new Error('Unexpected write in focused projection fixture: ' + this.sql);
  }
}

class Database {
  reads = []; writes = []; proofRequests = []; claims = null;
  constructor(options) { this.options = options; this.row = clone(options.previous ?? null); }
  setClaims(claims) { this.claims = claims; }
  prepare(sql) { return new Statement(this, sql); }
}

async function fixture(options, check) {
  const db = new Database(options), calls = [];
  const claims = {sub: AUTH_USER, session_id: SESSION, role: 'authenticated', aud: 'authenticated',
    aal: 'aal1', iat: NOW, exp: NOW + 900, iss: PROJECT + '/auth/v1', ...options.claims};
  if (options.amr !== undefined) claims.amr = options.amr;
  const user = {id: AUTH_USER, email: 'synthetic@example.invalid', email_confirmed_at: '2026-10-20T12:00:00Z',
    last_sign_in_at: new Date(NOW * 1000).toISOString(), app_metadata: {provider: 'email'},
    factors: [{id: FACTOR, factor_type: 'totp', status: options.factorStatus ?? 'unverified'}]};
  const verified = {token: TOKEN, user, claims};
  const env = {DB: db, AUTH_VERIFIED: verified, SUPABASE_URL: PROJECT,
    SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_synthetic_freshness_only'};
  const originalNow = Date.now, originalFetch = globalThis.fetch;
  Date.now = () => NOW * 1000;
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init);
    calls.push({url: request.url, method: request.method, authorization: request.headers.get('Authorization')});
    return Response.json({id: FACTOR, factor_type: 'totp'});
  };
  try {
    await check({db, env, verified, calls,
      project: (configuration = {}) => projectSession(env, verified, {surface: options.surface ?? 'member', ...configuration}),
      cancel: () => handleAuth(new Request('https://collect-api.invalid/v1/auth/mfa/cancel-enrollment', {
        method: 'POST', headers: {'Content-Type': 'application/json', Authorization: 'Bearer ' + TOKEN},
        body: JSON.stringify({factor_id: FACTOR}),
      }), env),
    });
  } finally {
    Date.now = originalNow; globalThis.fetch = originalFetch;
    assert.deepEqual(calls, [], 'Projection and retired MFA routes must not call the provider.');
  }
}

const domainError = (status, code) => error => error instanceof ApiError && error.status === status && error.code === code;
const authInserts = db => db.writes.filter(write => write.sql.startsWith('INSERT INTO auth_sessions('));

test('managed authentication freshness uses original events and authoritative persisted projection', async t => {
  await t.test('old OTP event is not renewed by fresh token iat or user last_sign_in_at', async () => {
    await fixture({amr: [{method: 'otp', timestamp: NOW - 600}]}, async ({project, db, calls}) => {
      const actor = await project();
      assert.equal(actor.authAt, NOW - 600); assert.equal(db.row.auth_at, NOW - 600);
      assert.equal(authInserts(db).length, 1); assert.equal(calls.length, 0);
    });
  });
  const noEvent = [
    ['absent AMR', undefined], ['empty AMR', []], ['null AMR', null],
    ['object AMR', {method: 'otp', timestamp: NOW}], ['string AMR', 'otp'],
    ['null AMR entry', [null]], ['bare method entry', ['otp']],
    ['array AMR entry', [['otp', NOW]]],
    ['unknown method', [{method: 'synthetic_token_refresh', timestamp: NOW}]],
    ['string timestamp', [{method: 'otp', timestamp: String(NOW)}]],
    ['fractional timestamp', [{method: 'otp', timestamp: NOW - 0.5}]],
    ['zero timestamp', [{method: 'otp', timestamp: 0}]],
    ['negative timestamp', [{method: 'otp', timestamp: -1}]],
    ['future timestamp', [{method: 'otp', timestamp: NOW + 1}]],
  ];
  for (const [name, amr] of noEvent) {
    await t.test(name + ' yields a live ordinary projection with zero freshness', async () => {
      await fixture({amr}, async ({project, db, calls}) => {
        const actor = await project();
        assert.equal(actor.authAt, 0); assert.equal(db.row.auth_at, 0);
        assert.equal(actor.assuranceLevel, 1); assert.equal(actor.surface, 'member');
        assert.equal(actor.userId, PRINCIPAL); assert.ok(db.row.expires_at > NOW);
        assert.equal(authInserts(db).length, 1); assert.equal(calls.length, 0);
      });
    });
  }
  for (const method of FIRST_FACTOR_METHODS) {
    await t.test('recognized ' + method + ' first-factor event accepts the current-second boundary', async () => {
      await fixture({amr: [{method, timestamp: NOW}]}, async ({project, db}) => {
        const actor = await project(); assert.equal(actor.authAt, NOW); assert.equal(db.row.auth_at, NOW);
        assert.equal(actor.assuranceLevel, 1);
      });
    });
  }
  for (const method of NON_BASELINE_METHODS) {
    await t.test(method + ' cannot establish a first-factor freshness baseline', async () => {
      await fixture({amr: [{method, timestamp: NOW}]}, async ({project, db}) => {
        const actor = await project(); assert.equal(actor.authAt, 0); assert.equal(db.row.auth_at, 0);
        assert.equal(actor.assuranceLevel, 1);
      });
    });
  }
  await t.test('earliest valid first-factor event wins; unrelated invalid entries are ignored', async () => {
    await fixture({amr: [{method: 'password', timestamp: NOW - 20}, {method: 'otp', timestamp: NOW - 2},
      {method: 'oauth', timestamp: NOW - 10},
      null, 'otp', {method: 'synthetic_unknown', timestamp: 1}, {method: 'otp', timestamp: String(NOW - 600)}]},
    async ({project, db}) => {
      const actor = await project(); assert.equal(actor.authAt, NOW - 20); assert.equal(db.row.auth_at, NOW - 20);
    });
  });
  await t.test('fresh token with no AMR and no iat still cannot infer current authentication time', async () => {
    await fixture({claims: {iat: undefined}}, async ({project, db}) => {
      const actor = await project(); assert.equal(actor.authAt, 0); assert.equal(db.row.auth_at, 0);
    });
  });
  await t.test('positive historical lower boundary remains event evidence rather than the no-event sentinel', async () => {
    await fixture({amr: [{method: 'otp', timestamp: 1}]}, async ({project, db}) => {
      const actor = await project(); assert.equal(actor.authAt, 1); assert.equal(db.row.auth_at, 1);
    });
  });
  await t.test('MFA-only token claims cannot create baseline freshness or promote a new projection to AAL2', async () => {
    await fixture({claims: {aal: 'aal2'}, amr: [{method: 'totp', timestamp: NOW}, {method: 'mfa/totp', timestamp: NOW}]},
    async ({project, db}) => {
      const actor = await project(); assert.equal(actor.authAt, 0); assert.equal(db.row.auth_at, 0);
      assert.equal(actor.assuranceLevel, 1); assert.equal(actor.mfaAt, null); assert.deepEqual(db.proofRequests, []);
    });
  });
  for (const amr of [undefined, null, {malformed: true}, [{method: 'otp', timestamp: NOW}]]) {
    await t.test('existing stale projection is preserved despite changed or malformed AMR: ' + JSON.stringify(amr), async () => {
      const previous = session(NOW - 600);
      await fixture({previous, amr}, async ({project, db}) => {
        const actor = await project(); assert.equal(actor.authAt, previous.auth_at);
        assert.deepEqual(db.row, previous); assert.equal(authInserts(db).length, 0);
      });
    });
  }
  await t.test('existing zero baseline is preserved even when a later token contains a fresh event', async () => {
    const previous = session(0);
    await fixture({previous, amr: [{method: 'otp', timestamp: NOW}]}, async ({project, db}) => {
      const actor = await project(); assert.equal(actor.authAt, 0); assert.deepEqual(db.row, previous);
      assert.equal(authInserts(db).length, 0);
    });
  });
  await t.test('ON CONFLICT losing projection returns the winner row freshness, not its optimistic event', async () => {
    const winningRow = session(NOW - 600);
    await fixture({winningRow, amr: [{method: 'otp', timestamp: NOW - 1}]}, async ({project, db}) => {
      const actor = await project();
      assert.equal(authInserts(db).length, 1); assert.deepEqual(db.row, winningRow);
      assert.equal(actor.authAt, winningRow.auth_at);
    });
  });
  await t.test('managed-session rejection still precedes any projection write', async () => {
    await fixture({managed: false, amr: [{method: 'otp', timestamp: NOW}]}, async ({project, db}) => {
      await assert.rejects(project(), domainError(401, 'access_revoked')); assert.equal(db.writes.length, 0);
    });
  });
  await t.test('inactive principal still cannot obtain an ordinary no-event projection', async () => {
    await fixture({principalActive: false}, async ({project, db}) => {
      await assert.rejects(project(), domainError(403, 'access_revoked')); assert.equal(db.writes.length, 0);
    });
  });
  await t.test('Admin surface still requires existing admission', async () => {
    await fixture({surface: 'admin'}, async ({project, db}) => {
      await assert.rejects(project(), domainError(403, 'admin_admission_required')); assert.equal(db.writes.length, 0);
    });
  });
  await t.test('no-event approved Admin projects without a retired MFA capability or cancellation effect', async () => {
    await fixture({surface: 'admin', admission: true}, async ({project, cancel, db, calls}) => {
      const actor = await project(); assert.equal(actor.authAt, 0); assert.equal(actor.surface, 'admin');
      assert.ok(actor.permissions.has('account.manage')); assert.ok(!actor.permissions.has('auth.mfa.enroll'));
      const previous = clone(db.row), writes = db.writes.length, reads = db.reads.length;
      await assert.rejects(cancel(), domainError(410, 'mfa_not_available'));
      assert.deepEqual(db.row, previous); assert.equal(db.writes.length, writes);
      assert.equal(db.reads.length, reads); assert.equal(calls.length, 0);
    });
  });
  await t.test('fresh OTP does not reactivate retired owned-factor cancellation', async () => {
    await fixture({surface: 'admin', admission: true, amr: [{method: 'otp', timestamp: NOW - 2}]},
    async ({project, cancel, db, calls}) => {
      const actor = await project(); assert.equal(actor.authAt, NOW - 2);
      const previous = clone(db.row), writes = db.writes.length, reads = db.reads.length;
      await assert.rejects(cancel(), domainError(410, 'mfa_not_available'));
      assert.deepEqual(db.row, previous); assert.equal(db.writes.length, writes);
      assert.equal(db.reads.length, reads); assert.equal(calls.length, 0);
    });
  });
  await t.test('stale retained AAL2 proof is not refreshed by new JWT iat or fresh AMR', async () => {
    const previous = session(NOW - 700, {surface: 'admin', assurance_level: 2, mfa_at: NOW - 600, mfa_factor_id: FACTOR});
    await fixture({surface: 'admin', admission: true, previous, factorStatus: 'verified',
      claims: {aal: 'aal2'}, amr: [{method: 'otp', timestamp: NOW}, {method: 'totp', timestamp: NOW}]},
    async ({project, cancel, db, calls}) => {
      const actor = await project(); assert.equal(actor.assuranceLevel, 2);
      assert.equal(actor.authAt, previous.mfa_at); assert.equal(actor.mfaAt, previous.mfa_at);
      assert.equal(actor.mfaFactorId, FACTOR); assert.deepEqual(db.row, previous);
      assert.deepEqual(db.proofRequests, []); assert.equal(db.writes.length, 0);
      await assert.rejects(cancel(), domainError(410, 'mfa_not_available')); assert.equal(calls.length, 0);
    });
  });
  await t.test('explicit MFA projection is retired before claims, reads or writes', async () => {
    const previous = session(NOW - 600, {surface: 'admin'});
    await fixture({surface: 'admin', admission: true, previous,
      claims: {aal: 'aal2'}, amr: [{method: 'otp', timestamp: NOW - 600}, {method: 'totp', timestamp: NOW}]},
    async ({project, db, calls}) => {
      await assert.rejects(() => project({mfaVerified: true, factorId: FACTOR}), domainError(410, 'mfa_not_available'));
      assert.equal(db.claims, null); assert.deepEqual(db.reads, []); assert.deepEqual(db.writes, []);
      assert.deepEqual(db.proofRequests, []); assert.deepEqual(db.row, previous); assert.equal(calls.length, 0);
    });
  });
  await t.test('every retired member MFA route rejects malformed bodies and methods before authority work', async () => {
    await fixture({}, async ({env, db, calls}) => {
      for (const path of ['enroll', 'challenge', 'verify', 'cancel-enrollment', 'unenroll', 'unknown/nested']) {
        for (const method of ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS']) {
          const request = new Request('https://collect-api.invalid/v1/auth/mfa/' + path, {
            method, headers: {'Content-Type': 'application/json'},
            ...(!['GET', 'HEAD'].includes(method) ? {body: '{malformed'} : {}),
          });
          await assert.rejects(() => handleAuth(request, env), domainError(410, 'mfa_not_available'));
          assert.equal(db.claims, null); assert.deepEqual(db.reads, []); assert.deepEqual(db.writes, []);
          assert.equal(calls.length, 0);
        }
      }
    });
  });
});

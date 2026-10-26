import {wrapFixtureModule} from './helpers/fenced-module.js';
import {test} from './helpers/fenced-node-test.js';
import assert from 'node:assert/strict';
import {isAbsolute, join} from 'node:path';
import {pathToFileURL} from 'node:url';

// Root runs this file against separate before/after actual _shared graphs.
// Fully intercepted HTTP and a strict member-projection fixture only: no
// provider, signed-JWT, PostgreSQL authority or hosted logout proof is claimed.
const sourceRoot = process.env.COLLECT_AUTH_SOURCE_ROOT;
assert.ok(typeof sourceRoot === 'string' && isAbsolute(sourceRoot),
  'Set COLLECT_AUTH_SOURCE_ROOT to the absolute actual _shared source directory.');
const actual = async relative => {if(relative==='postgres.js')return import('./helpers/fenced-postgres.js');return wrapFixtureModule(relative,await import(pathToFileURL(join(sourceRoot, relative)).href));};
const {authRequest} = await actual('auth-http.js');
const {ApiError} = await actual('domain/core.js');
const {handleAuth} = await actual('domain/auth.js');

const PROJECT = 'https://collect-logout.synthetic.invalid';
const PUBLISHABLE = 'sb_publishable_synthetic_logout_only';
const SECRET_KEY = 'sb_secret_synthetic_logout_only';
const TOKEN = 'synthetic-opaque-member-token';
const PRIVATE_DETAIL = 'synthetic provider private detail';
const EMAIL = 'synthetic.member@example.invalid';
const ENV = {SUPABASE_URL: PROJECT, SUPABASE_PUBLISHABLE_KEY: PUBLISHABLE,
  SUPABASE_SERVICE_ROLE_KEY: SECRET_KEY};
const NOW = 1_792_497_600;
const AUTH_USER = '11111111-1111-4111-8111-111111111111';
const SESSION = '22222222-2222-4222-8222-222222222222';
const PRINCIPAL = '33333333-3333-4333-8333-333333333333';

function safeError(error, status, code) {
  assert.ok(error instanceof ApiError);
  assert.equal(error.status, status); assert.equal(error.code, code);
  const publicShape = JSON.stringify({status: error.status, code: error.code, message: error.message});
  for (const value of [TOKEN, PUBLISHABLE, SECRET_KEY, PRIVATE_DETAIL, EMAIL]) {
    assert.equal(publicShape.includes(value), false, 'Errors must not expose provider/request secrets or private detail');
  }
  return true;
}
async function intercepted(response, check, {onFetch} = {}) {
  const previous = globalThis.fetch, calls = [];
  globalThis.fetch = async (input, init) => {
    calls.push({rawUrl: String(input), request: new Request(input, init), init});
    onFetch?.(calls.at(-1));
    return typeof response === 'function' ? response(calls.at(-1)) : response;
  };
  try {await check(calls);}
  finally {
    globalThis.fetch = previous;
    // Check after restoration so assertions cannot be swallowed by HTTP error
    // handling and so a failed assertion cannot leave the global stub active.
    for (const call of calls) {
      assert.equal(call.request.redirect, 'error');
      assert.equal(call.request.headers.get('Content-Type'), 'application/json');
      assert.ok(call.init.signal instanceof AbortSignal);
      assert.ok(call.rawUrl.startsWith(PROJECT + '/auth/v1/'));
    }
  }
}
function providerError(status, code = 'synthetic_provider_denied') {
  return Response.json({error_code: code, msg: PRIVATE_DETAIL + ' ' + TOKEN + ' ' + EMAIL,
    access_token: TOKEN}, {status});
}

test('authRequest admits only the actual authenticated POST logout no-content contract', {concurrency: false}, async t => {
  for (const path of ['/logout', '/logout?scope=local', '/logout?scope=global']) {
    await t.test('204 logout succeeds for exact path ' + path, async () => {
      await intercepted(new Response(null, {status: 204}), async calls => {
        assert.deepEqual(await authRequest(ENV, path, {token: TOKEN}), {});
        assert.equal(calls.length, 1); assert.equal(calls[0].rawUrl, PROJECT + '/auth/v1' + path);
        assert.equal(calls[0].request.method, 'POST');
        assert.equal(calls[0].request.headers.get('apikey'), PUBLISHABLE);
        assert.equal(calls[0].request.headers.get('Authorization'), 'Bearer ' + TOKEN);
        assert.equal(calls[0].init.body, undefined);
      });
    });
  }
  for (const method of ['GET', 'HEAD', 'DELETE', 'PUT', 'post']) {
    await t.test('204 is not accepted for an unapproved method: ' + method, async () => {
      await intercepted(new Response(null, {status: 204}), async calls => {
        await assert.rejects(authRequest(ENV, '/logout', {method, token: TOKEN}), error => safeError(error, 503, 'auth_unavailable'));
        assert.equal(calls.length, 1);
      });
    });
  }
  const otherPaths = ['/logout/', '/Logout', '/logout?scope=others', '/logout?scope=global&extra=true',
    '/logout?scope=local&extra=true', '/logout?scope=local&scope=local', '/logout?scope=local#fragment',
    '/user', '/verify', '/otp', '/token?grant_type=refresh_token', '/factors/' + AUTH_USER];
  for (const path of otherPaths) {
    await t.test('204 remains invalid outside the exact allowlist: ' + path, async () => {
      await intercepted(new Response(null, {status: 204}), async calls => {
        await assert.rejects(authRequest(ENV, path, {token: TOKEN}), error => safeError(error, 503, 'auth_unavailable'));
        assert.equal(calls.length, 1);
      });
    });
  }
  const invalidTokens = [undefined, null, '', ' ', '\t', 'embedded whitespace', 'leading ', ' trailing', 7, ['opaque']];
  for (const [index, token] of invalidTokens.entries()) {
    await t.test('204 requires a nonempty whitespace-free string token, case ' + index, async () => {
      await intercepted(new Response(null, {status: 204}), async calls => {
        await assert.rejects(authRequest(ENV, '/logout', {token}), error => safeError(error, 503, 'auth_unavailable'));
        assert.equal(calls.length, 1);
      });
    });
  }
  await t.test('provider-accepted opaque token adds no JWT-shape or API-key-prefix policy', async () => {
    const opaque = 'sb_synthetic_opaque_logout_token';
    await intercepted(new Response(null, {status: 204}), async calls => {
      assert.deepEqual(await authRequest(ENV, '/logout', {token: opaque}), {});
      assert.equal(calls.length, 1);
      assert.equal(calls[0].request.headers.get('Authorization'), 'Bearer ' + opaque);
    });
  });
  await t.test('admin API-key authority does not replace the required user token for 204 logout', async () => {
    await intercepted(new Response(null, {status: 204}), async calls => {
      await assert.rejects(authRequest(ENV, '/logout', {admin: true}), error => safeError(error, 503, 'auth_unavailable'));
      assert.equal(calls.length, 1); assert.equal(calls[0].request.headers.get('apikey'), SECRET_KEY);
      assert.equal(calls[0].request.headers.has('Authorization'), false);
    });
  });
  for (const [status, body] of [[200, ''], [200, 'not json'], [201, ''], [205, null]]) {
    await t.test('non-204 non-JSON success is still unavailable: ' + status + '/' + String(body), async () => {
      await intercepted(new Response(body, {status}), async calls => {
        await assert.rejects(authRequest(ENV, '/logout?scope=local', {token: TOKEN}), error => safeError(error, 503, 'auth_unavailable'));
        assert.equal(calls.length, 1);
      });
    });
  }
  await t.test('ordinary JSON success and request body/authorization behavior are unchanged', async () => {
    const result = {access_token: 'synthetic-response-token', user: {id: AUTH_USER}, nested: [1, {ok: true}]};
    const body = {email: EMAIL, password: 'synthetic-password-only'};
    await intercepted(Response.json(result), async calls => {
      assert.deepEqual(await authRequest(ENV, '/token?grant_type=password', {body}), result);
      assert.equal(calls.length, 1); assert.deepEqual(JSON.parse(calls[0].init.body), body);
      assert.equal(calls[0].request.headers.get('apikey'), PUBLISHABLE);
      assert.equal(calls[0].request.headers.has('Authorization'), false);
    });
  });
  await t.test('ordinary JSON logout response remains supported', async () => {
    await intercepted(Response.json({ok: true}), async calls => {
      assert.deepEqual(await authRequest(ENV, '/logout', {token: TOKEN}), {ok: true});
      assert.equal(calls.length, 1);
    });
  });
  for (const key of [SECRET_KEY, 'synthetic-legacy-service-jwt']) {
    await t.test('admin JSON calls retain their existing key and bearer convention: ' + (key === SECRET_KEY ? 'secret' : 'legacy'), async () => {
      await intercepted(Response.json({id: AUTH_USER}), async calls => {
        assert.deepEqual(await authRequest({...ENV, SUPABASE_SERVICE_ROLE_KEY: key}, '/invite', {admin: true, body: {email: EMAIL}}), {id: AUTH_USER});
        assert.equal(calls.length, 1); assert.equal(calls[0].request.headers.get('apikey'), key);
        assert.equal(calls[0].request.headers.get('Authorization'), key === SECRET_KEY ? null : 'Bearer ' + key);
      });
    });
  }
  for (const status of [400, 401, 403, 422, 429, 500, 503, 302]) {
    await t.test('JSON provider failure stays rejected and sanitized: ' + status, async () => {
      await intercepted(providerError(status), async calls => {
        const expectedStatus = [400, 401, 403, 422, 429].includes(status) ? status : 503;
        await assert.rejects(authRequest(ENV, '/logout', {token: TOKEN}), error => {
          safeError(error, expectedStatus, 'synthetic_provider_denied');
          assert.equal(error.message, status === 429 ? 'Too many attempts. Try again later.' : 'The identity request could not be verified.');
          return true;
        });
        assert.equal(calls.length, 1, 'An error must not replay the logout request');
      });
    });
  }
  for (const status of [401, 403, 500]) {
    await t.test('non-JSON failure never becomes a logout acknowledgment: ' + status, async () => {
      await intercepted(new Response(PRIVATE_DETAIL + ' ' + TOKEN, {status}), async calls => {
        await assert.rejects(authRequest(ENV, '/logout', {token: TOKEN}), error => safeError(error, 503, 'auth_unavailable'));
        assert.equal(calls.length, 1);
      });
    });
  }
});

class MemberStatement {
  values = [];
  constructor(db, sql) {this.db = db; this.sql = sql;}
  bind(...values) {this.values = values; return this;}
  async first() {
    this.db.reads.push({sql: this.sql, values: [...this.values]});
    if (this.sql === 'SELECT private.is_managed_session(?::uuid,?::uuid) AS allowed') {
      assert.deepEqual(this.values, [AUTH_USER, SESSION]); return {allowed: this.db.managed};
    }
    if (this.sql === 'SELECT user_id FROM private.auth_principal_links WHERE auth_user_id=?') {
      assert.deepEqual(this.values, [AUTH_USER]); return {user_id: PRINCIPAL};
    }
    if (this.sql === 'SELECT * FROM users WHERE id=?') {
      assert.deepEqual(this.values, [PRINCIPAL]);
      return {id: PRINCIPAL, access_status: 'active', full_name: 'Synthetic member', public_id: '100001'};
    }
    if (this.sql === 'SELECT * FROM auth_sessions WHERE id=?') {
      assert.deepEqual(this.values, [SESSION]); return structuredClone(this.db.row);
    }
    if (this.sql.startsWith('SELECT a.id FROM admin_sessions s JOIN admin_users a ')) {
      assert.deepEqual(this.values, [SESSION, PRINCIPAL, NOW]); return null;
    }
    throw new Error('Unexpected query in member logout fixture: ' + this.sql);
  }
  async run() {
    assert.equal(this.sql, "UPDATE auth_sessions SET revoked_at=?,revocation_reason='signed_out' WHERE id=? AND user_id=?");
    assert.deepEqual(this.values, [NOW, SESSION, PRINCIPAL]);
    this.db.events.push('local-revocation'); this.db.writes.push({sql: this.sql, values: [...this.values]});
    this.db.row.revoked_at = this.values[0]; this.db.row.revocation_reason = 'signed_out';
    return {meta: {changes: 1}};
  }
}
class MemberDatabase {
  managed = true; claims = null; reads = []; writes = []; events = [];
  row = {id: SESSION, user_id: PRINCIPAL, surface: 'member', auth_at: NOW - 600,
    created_at: NOW - 600, expires_at: NOW + 3600, revoked_at: null,
    assurance_level: 1, mfa_at: null, mfa_factor_id: null};
  prepare(sql) {return new MemberStatement(this, sql);}
  setClaims(claims) {this.claims = claims;}
}
async function memberFixture(response, check, {managed = true} = {}) {
  const db = new MemberDatabase(); db.managed = managed;
  const verified = {token: TOKEN, user: {id: AUTH_USER, email: EMAIL,
    email_confirmed_at: '2026-10-20T12:00:00Z', app_metadata: {provider: 'email'}},
    claims: {sub: AUTH_USER, session_id: SESSION, role: 'authenticated', aal: 'aal1'}};
  const env = {...ENV, DB: db, AUTH_VERIFIED: verified};
  const previousNow = Date.now; Date.now = () => NOW * 1000;
  try {
    await intercepted(response, async calls => {
      const logout = () => handleAuth(new Request('https://collect-api.synthetic.invalid/v1/auth/logout', {
        method: 'POST', headers: {'Content-Type': 'application/json', Authorization: 'Bearer ' + TOKEN},
        body: '{}',
      }), env);
      await check({db, calls, env, logout});
    }, {onFetch: () => db.events.push('provider-logout')});
  } finally {Date.now = previousNow;}
}

test('actual member logout reaches local revocation only after provider logout acceptance', {concurrency: false}, async t => {
  await t.test('GoTrue 204 permits the exact local signed_out update and an ok response', async () => {
    await memberFixture(new Response(null, {status: 204}), async ({db, calls, logout}) => {
      const response = await logout(); assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), {ok: true});
      assert.equal(calls.length, 1); assert.equal(calls[0].rawUrl, PROJECT + '/auth/v1/logout?scope=local');
      assert.equal(calls[0].request.method, 'POST');
      assert.equal(calls[0].request.headers.get('Authorization'), 'Bearer ' + TOKEN);
      assert.deepEqual(db.events, ['provider-logout', 'local-revocation']);
      assert.equal(db.writes.length, 1); assert.equal(db.row.revoked_at, NOW);
      assert.equal(db.row.revocation_reason, 'signed_out');
      assert.equal(db.claims.sub, AUTH_USER); assert.equal(db.claims.session_id, SESSION);
    });
  });
  for (const [name, response, status, code] of [
    ['JSON refusal', providerError(401), 401, 'synthetic_provider_denied'],
    ['non-JSON failure', new Response(PRIVATE_DETAIL, {status: 503}), 503, 'auth_unavailable'],
  ]) {
    await t.test(name + ' does not falsely revoke the local session or return ok', async () => {
      await memberFixture(response, async ({db, calls, logout}) => {
        await assert.rejects(logout(), error => safeError(error, status, code));
        assert.equal(calls.length, 1); assert.deepEqual(db.events, ['provider-logout']);
        assert.deepEqual(db.writes, []); assert.equal(db.row.revoked_at, null);
      });
    });
  }
  await t.test('managed-session refusal prevents both provider logout and local revocation', async () => {
    await memberFixture(new Response(null, {status: 204}), async ({db, calls, logout}) => {
      await assert.rejects(logout(), error => safeError(error, 401, 'access_revoked'));
      assert.equal(calls.length, 0); assert.deepEqual(db.events, []); assert.deepEqual(db.writes, []);
    }, {managed: false});
  });
});

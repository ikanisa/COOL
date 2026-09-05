import {test} from "node:test";
import assert from "node:assert/strict";
import {loginSession, productionOrigin, resolveStoredSession, type SessionStore} from "./session_renewal.ts";

const now = 1800000000000;
const environment = {COLLECT_SUPABASE_URL: productionOrigin, COLLECT_OPERATOR_SESSION_RENEWAL: "keychain"};
const jwt = (value: unknown) => `header.${Buffer.from(JSON.stringify(value)).toString("base64url")}.signature`;
const claims = {sub: "test-admin", session_id: "11111111-1111-4111-8111-111111111111",
  role: "authenticated", iss: `${productionOrigin}/auth/v1`, exp: now / 1000 + 30};
const prior = {origin: productionOrigin, anon_key: jwt({role: "anon"}), access_token: jwt(claims),
  refresh_token: "fake-one-use-token", version: 2, refresh_pending: false};
const next = {access_token: jwt({...claims, exp: now / 1000 + 3600}), refresh_token: "fake-rotated-token"};

function memoryStore(value: unknown = prior) {
  let current = structuredClone(value);
  const writes: Record<string, unknown>[] = [];
  const store: SessionStore = {
    read: async () => structuredClone(current),
    write: async row => { current = structuredClone(row); writes.push(structuredClone(row)); },
  };
  return {store, writes, current: () => current};
}

test("renewal saves a tombstone before transport, checks current authority and persists rotation", async () => {
  const state = memoryStore();
  const calls: {url: string; body: unknown}[] = [];
  const fetcher: typeof fetch = async (url, init) => {
    assert.deepEqual(state.writes, [{origin: productionOrigin, version: 2, refresh_pending: true}]);
    assert.equal(init?.redirect, "error");
    assert.equal(init?.cache, "no-store");
    assert.ok(init?.signal instanceof AbortSignal);
    calls.push({url: String(url), body: JSON.parse(String(init?.body))});
    return calls.length === 1 ? Response.json(next) : Response.json({ok: true, result: {enabled: false}});
  };
  const runtime = await resolveStoredSession(state.store, environment, fetcher, () => now);
  assert.equal(runtime.COLLECT_OPERATOR_ACCESS_TOKEN, next.access_token);
  assert.ok(!JSON.stringify(runtime).includes(next.refresh_token));
  assert.deepEqual(calls, [
    {url: `${productionOrigin}/auth/v1/token?grant_type=refresh_token`, body: {refresh_token: prior.refresh_token}},
    {url: `${productionOrigin}/functions/v1/collect-notification-operator`, body: {action: "health"}},
  ]);
  assert.equal(state.writes.length, 2);
  assert.equal(state.writes[1]?.refresh_token, next.refresh_token);
  assert.equal(state.writes[1]?.refresh_pending, false);
});

test("fresh renewable session performs no write or network call", async () => {
  const state = memoryStore({...prior, access_token: next.access_token});
  const runtime = await resolveStoredSession(state.store, environment, async () => { throw new Error("unexpected"); }, () => now);
  assert.equal(runtime.COLLECT_OPERATOR_ACCESS_TOKEN, next.access_token);
  assert.deepEqual(state.writes, []);
});

test("offline preflight never refreshes, writes or makes an Auth request", async () => {
  const state = memoryStore();
  await assert.rejects(resolveStoredSession(state.store, environment, async () => { throw new Error("unexpected"); }, () => now,
    {allowRefresh: false}), /REAUTHENTICATION_REQUIRED/);
  assert.deepEqual(state.writes, []);
});

test("explicit renew verifies an actual rotation without altering the clock or token", async () => {
  const state = memoryStore({...prior, access_token: next.access_token}); let calls = 0;
  await resolveStoredSession(state.store, environment, async () => ++calls === 1 ? Response.json(next) :
    Response.json({ok: true, result: {enabled: false}}), () => now, {refreshNow: true});
  assert.equal(calls, 2);
  assert.equal(state.writes.length, 2);
});

test("legacy expired session cannot invent a refresh token", async () => {
  const {refresh_token: _refresh, ...legacy} = prior;
  const state = memoryStore(legacy);
  await assert.rejects(resolveStoredSession(state.store, environment, async () => { throw new Error("unexpected"); }, () => now), /REAUTHENTICATION_REQUIRED/);
  assert.deepEqual(state.writes, []);
});

test("refresh requires opt-in, version, session identity and nonprivileged project-bound credentials", async () => {
  const variants = [
    {...prior, version: 1}, {...prior, refresh_pending: true}, {...prior, refresh_token: ""},
    {...prior, origin: "https://other.supabase.co"}, {...prior, anon_key: jwt({role: "service_role"})},
    {...prior, access_token: jwt({...claims, session_id: undefined})},
    {...prior, access_token: jwt({...claims, role: "service_role"})},
    {...prior, access_token: jwt({...claims, iss: "https://other.supabase.co/auth/v1"})},
  ];
  for (const value of variants) {
    const state = memoryStore(value);
    await assert.rejects(resolveStoredSession(state.store, environment, async () => { throw new Error("unexpected"); }, () => now), /REAUTHENTICATION_REQUIRED/);
    assert.deepEqual(state.writes, []);
  }
  await assert.rejects(resolveStoredSession(memoryStore().store, {COLLECT_SUPABASE_URL: productionOrigin}, async () => { throw new Error("unexpected"); }, () => now), /REAUTHENTICATION_REQUIRED/);
});

test("timeout, redirect, revoked refresh and malformed responses fail closed without token replay", async () => {
  const failures: (typeof fetch)[] = [
    async () => { throw new Error("secret-token-network-error"); },
    async () => new Response("private-body", {status: 401}),
    async () => new Response("private-body", {status: 302}),
    async () => new Response("not-json"),
    async () => Response.json({}),
  ];
  for (const failure of failures) {
    const state = memoryStore(); let calls = 0;
    const fetcher: typeof fetch = async (...args) => { calls++; return failure(...args); };
    await assert.rejects(resolveStoredSession(state.store, environment, fetcher, () => now), /^Error: OPERATOR_SESSION_REAUTHENTICATION_REQUIRED$/);
    assert.equal(calls, 1);
    await assert.rejects(resolveStoredSession(state.store, environment, fetcher, () => now), /REAUTHENTICATION_REQUIRED/);
    assert.equal(calls, 1);
    assert.deepEqual(state.current(), {origin: productionOrigin, version: 2, refresh_pending: true});
  }
});

test("refreshed tokens cannot change operator, session, project, role or bypass expiry", async () => {
  for (const change of [{sub: "another-admin"}, {session_id: "22222222-2222-4222-8222-222222222222"},
    {iss: "https://other.supabase.co/auth/v1"}, {role: "service_role"}, {exp: now / 1000 + 60}]) {
    const state = memoryStore(); let calls = 0;
    await assert.rejects(resolveStoredSession(state.store, environment, async () => {
      calls++; return Response.json({...next, access_token: jwt({...claims, exp: now / 1000 + 3600, ...change})});
    }, () => now), /REAUTHENTICATION_REQUIRED/);
    assert.equal(calls, 1);
    assert.equal(state.writes.length, 1);
  }
});

test("revoked Admin authorization or invalid health never persists the renewed session", async () => {
  for (const denied of [() => new Response("permission denied", {status: 403}),
    () => Response.json({ok: false}), () => Response.json({ok: true, result: {}})]) {
    const state = memoryStore(); let calls = 0;
    await assert.rejects(resolveStoredSession(state.store, environment, async () => ++calls === 1 ? Response.json(next) : denied(), () => now), /REAUTHENTICATION_REQUIRED/);
    assert.equal(calls, 2);
    assert.equal(state.writes.length, 1);
  }
});

test("Keychain write failures do not return credentials or repeat an uncertain refresh", async () => {
  const state = memoryStore(); let writes = 0; let calls = 0;
  const store = {...state.store, write: async (value: Record<string, unknown>) => {
    if (++writes === 2) throw new Error("disk failure");
    await state.store.write(value);
  }};
  const fetcher: typeof fetch = async () => ++calls === 1 ? Response.json(next) : Response.json({ok: true, result: {enabled: false}});
  await assert.rejects(resolveStoredSession(store, environment, fetcher, () => now), /REAUTHENTICATION_REQUIRED/);
  await assert.rejects(resolveStoredSession(store, environment, fetcher, () => now), /REAUTHENTICATION_REQUIRED/);
  assert.equal(calls, 2);
  let prewriteCalls = 0;
  await assert.rejects(resolveStoredSession({read: async () => prior, write: async () => { throw new Error("locked"); }},
    environment, async () => { prewriteCalls++; return Response.json(next); }, () => now), /locked/);
  assert.equal(prewriteCalls, 0);
});

test("OTP login retains renewal only with explicit opt-in and a valid session id", () => {
  const fresh = {...next, access_token: jwt({...claims, exp: Math.floor(Date.now() / 1000) + 3600})};
  const stored = loginSession(fresh, prior.anon_key, environment);
  assert.equal((stored as Record<string, unknown>).refresh_token, next.refresh_token);
  assert.equal(Object.hasOwn(loginSession(fresh, prior.anon_key, {COLLECT_SUPABASE_URL: productionOrigin}), "refresh_token"), false);
  assert.throws(() => loginSession({...fresh, refresh_token: undefined}, prior.anon_key, environment), /REAUTHENTICATION_REQUIRED/);
});

export const productionOrigin = "https://lhbowpbcpwoiparwnwgt.supabase.co";
const reauthenticate = () => new Error("OPERATOR_SESSION_REAUTHENTICATION_REQUIRED");

type Session = { origin: string; anon_key: string; access_token: string };
type Claims = { sub: string; session_id?: string; exp: number };

function checkedSession(value: unknown, environment: NodeJS.ProcessEnv): {session: Session; claims: Claims} {
  try {
    if (!value || typeof value !== "object" || Array.isArray(value)) throw reauthenticate();
    const row = value as Record<string, unknown>;
    if (row.origin !== productionOrigin || environment.COLLECT_SUPABASE_URL !== productionOrigin ||
        typeof row.anon_key !== "string" || typeof row.access_token !== "string" ||
        Object.hasOwn(row, "refresh_token")) throw reauthenticate();
    const parts = row.access_token.split(".");
    if (parts.length !== 3) throw reauthenticate();
    const token = JSON.parse(Buffer.from(parts[1]!, "base64url").toString());
    const key = row.anon_key.startsWith("sb_publishable_") ? {role: "anon"} :
      JSON.parse(Buffer.from(row.anon_key.split(".")[1]!, "base64url").toString());
    if (key.role !== "anon" || token.role !== "authenticated" || typeof token.sub !== "string" || !token.sub ||
        token.iss !== `${productionOrigin}/auth/v1` || !Number.isSafeInteger(token.exp)) throw reauthenticate();
    return {session: {origin: row.origin, anon_key: row.anon_key, access_token: row.access_token}, claims: token};
  } catch { throw reauthenticate(); }
}

export function scopedRuntime(value: unknown, environment: NodeJS.ProcessEnv, now = Date.now()): NodeJS.ProcessEnv {
  const {session, claims} = checkedSession(value, environment);
  if (claims.exp <= Math.floor(now / 1000) + 60) throw reauthenticate();
  return {...environment, COLLECT_SUPABASE_ANON_KEY: session.anon_key, COLLECT_OPERATOR_ACCESS_TOKEN: session.access_token};
}

export interface SessionStore {
  read(): Promise<unknown>;
  write(value: Record<string, unknown>): Promise<void>;
}

function renewable(value: unknown, environment: NodeJS.ProcessEnv) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw reauthenticate();
  const row = value as Record<string, unknown>;
  if (environment.COLLECT_OPERATOR_SESSION_RENEWAL !== "keychain" || row.version !== 2 ||
      row.refresh_pending !== false || typeof row.refresh_token !== "string" ||
      !row.refresh_token.trim() || row.refresh_token.length > 4096) throw reauthenticate();
  const base = {origin: row.origin, anon_key: row.anon_key, access_token: row.access_token};
  const {session, claims} = checkedSession(base, environment);
  if (typeof claims.session_id !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(claims.session_id)) throw reauthenticate();
  return {session, claims, refreshToken: row.refresh_token};
}

export function loginSession(session: Record<string, unknown>, key: string, environment: NodeJS.ProcessEnv) {
  const base = {origin: productionOrigin, anon_key: key, access_token: session.access_token};
  scopedRuntime(base, environment);
  if (environment.COLLECT_OPERATOR_SESSION_RENEWAL !== "keychain") return base;
  const stored = {...base, version: 2, refresh_token: session.refresh_token, refresh_pending: false};
  renewable(stored, environment);
  return stored;
}

// Caller holds the cross-process Keychain lock throughout this operation.
// Local claim checks are hygiene only; Auth and the operator Edge enforce authority.
export async function resolveStoredSession(
  store: SessionStore,
  environment: NodeJS.ProcessEnv,
  fetcher: typeof fetch = fetch,
  now: () => number = Date.now,
  options: {allowRefresh?: boolean; refreshNow?: boolean} = {},
): Promise<NodeJS.ProcessEnv> {
  const stored = await store.read();
  if (!stored || typeof stored !== "object" || Array.isArray(stored)) throw reauthenticate();
  const row = stored as Record<string, unknown>;
  if (row.refresh_pending === true) throw reauthenticate();
  if (!Object.hasOwn(row, "refresh_token")) {
    if (options.refreshNow) throw reauthenticate();
    return scopedRuntime(stored, environment, now());
  }
  const prior = renewable(stored, environment);
  if (!options.refreshNow && prior.claims.exp > Math.floor(now() / 1000) + 120) {
    return scopedRuntime(prior.session, environment, now());
  }
  if (options.allowRefresh === false) throw reauthenticate();

  // Persist a non-secret tombstone BEFORE consuming a one-use refresh token.
  // Crash, timeout, denial or persistence failure must never replay that token.
  await store.write({origin: productionOrigin, version: 2, refresh_pending: true});
  try {
    const response = await fetcher(`${productionOrigin}/auth/v1/token?grant_type=refresh_token`, {
      method: "POST", redirect: "error", cache: "no-store", signal: AbortSignal.timeout(8000),
      headers: {apikey: prior.session.anon_key, "Content-Type": "application/json"},
      body: JSON.stringify({refresh_token: prior.refreshToken}),
    });
    if (!response.ok) throw reauthenticate();
    const payload = await response.json() as Record<string, unknown>;
    const next = {...prior.session, access_token: payload.access_token,
      refresh_token: payload.refresh_token, version: 2, refresh_pending: false};
    const checked = renewable(next, environment);
    if (checked.claims.sub !== prior.claims.sub || checked.claims.session_id !== prior.claims.session_id) {
      throw reauthenticate();
    }
    const runtime = scopedRuntime(checked.session, environment, now());
    // A refreshed login is not an Admin grant. Recheck the current bounded permission.
    const health = await fetcher(`${productionOrigin}/functions/v1/collect-notification-operator`, {
      method: "POST", redirect: "error", cache: "no-store", signal: AbortSignal.timeout(5000),
      headers: {apikey: checked.session.anon_key, Authorization: `Bearer ${checked.session.access_token}`,
        "Content-Type": "application/json"},
      body: JSON.stringify({action: "health"}),
    });
    if (!health.ok) throw reauthenticate();
    const result = await health.json() as Record<string, unknown>;
    if (result.ok !== true || !result.result || typeof result.result !== "object" ||
        typeof (result.result as Record<string, unknown>).enabled !== "boolean") throw reauthenticate();
    await store.write(next);
    return runtime;
  } catch { throw reauthenticate(); }
}

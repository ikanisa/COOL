import { pathToFileURL } from "node:url";
import { runtimeCredentials } from "./runtime_credentials.ts";
import { callNotificationOperator, operatorEnvironment, type FetchLike } from "./operator_client.ts";

const requiredNames = ["COLLECT_SUPABASE_URL", "COLLECT_SUPABASE_ANON_KEY", "COLLECT_OPERATOR_ACCESS_TOKEN"];

function claims(value: string): Record<string, unknown> | null {
  try {
    const parts = value.split(".");
    if (parts.length !== 3 || !parts[1]) return null;
    const parsed: unknown = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed as Record<string, unknown> : null;
  } catch { return null; }
}

export function runtimeReadiness(environment: NodeJS.ProcessEnv = process.env, now = Date.now()) {
  const missing = requiredNames.filter(name => !environment[name]?.trim());
  const issues: string[] = [];
  if (missing.length) return { ready: false, missing, issues };
  let resolved;
  try { resolved = operatorEnvironment(environment); }
  catch { return { ready: false, missing, issues: ["INVALID_SUPABASE_ORIGIN"] }; }
  const keyClaims = claims(resolved.anonKey);
  if (!resolved.anonKey.startsWith("sb_publishable_") && keyClaims?.role !== "anon") {
    issues.push("PUBLIC_ANON_OR_PUBLISHABLE_KEY_REQUIRED");
  }
  const token = claims(resolved.accessToken);
  if (!token || token.role !== "authenticated") issues.push("AUTHENTICATED_USER_TOKEN_REQUIRED");
  if (token?.iss !== `${resolved.supabaseUrl}/auth/v1`) issues.push("TOKEN_PROJECT_MISMATCH");
  if (typeof token?.exp !== "number" || token.exp <= Math.floor(now / 1000) + 60) {
    issues.push("TOKEN_EXPIRED_OR_RENEWAL_REQUIRED");
  }
  // This is metadata hygiene only. The deployed Edge must validate the signature and current role.
  return { ready: issues.length === 0, missing, issues };
}

export async function connectionPreflight(
  environment: NodeJS.ProcessEnv = process.env,
  liveReadOnly = false,
  fetcher: FetchLike = fetch,
  now = Date.now(),
) {
  const runtime = runtimeReadiness(environment, now);
  const boundary = { provider_sends: 0, queue_mutations: 0, credentials_printed: false };
  if (!runtime.ready) return { status: "BLOCKED_RUNTIME_CONFIGURATION", runtime, ...boundary };
  if (!liveReadOnly) return { status: "READY_FOR_READ_ONLY_CHECK", runtime, ...boundary };
  try {
    const resolved = operatorEnvironment(environment);
    const health = await callNotificationOperator("health", {}, resolved, fetcher);
    if (!health || typeof health !== "object" || Array.isArray(health)) throw new Error("shape");
    const h = health as Record<string, unknown>;
    const countNames = ["queued", "awaiting_confirmation", "send_started", "uncertain", "suppressed", "active_workers"];
    if (typeof h.enabled !== "boolean" || countNames.some(name =>
      !Number.isSafeInteger(h[name]) || Number(h[name]) < 0)) throw new Error("shape");
    const pending = await callNotificationOperator("list_pending", { limit: 1 }, resolved, fetcher);
    if (!Array.isArray(pending) || pending.length > 1) throw new Error("shape");
    return {
      status: "PASS_AUTHENTICATED_READ_ONLY",
      runtime,
      checks: ["health", "list_pending"],
      queue: {
        enabled: h.enabled,
        ...Object.fromEntries(countNames.map(name => [name, h[name]])),
        pending_page_count: pending.length,
      },
      ...boundary,
    };
  } catch {
    // Never print remote bodies, errors, claims, tokens, job IDs, phones, or receipt values.
    return { status: "BLOCKED_AUTHORIZATION_TRANSPORT_OR_RESPONSE", runtime, ...boundary };
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  if (args.some(arg => arg !== "--live-read-only") || args.length > 1) {
    console.error("Usage: preflight.ts [--live-read-only]");
    process.exitCode = 2;
  } else {
    try {
      const result = await connectionPreflight(await runtimeCredentials(), args.includes("--live-read-only"));
      console.log(JSON.stringify(result, null, 2));
      if (result.status.startsWith("BLOCKED_")) process.exitCode = 2;
    } catch {
      console.log(JSON.stringify({status:"BLOCKED_OPERATOR_SESSION_REAUTHENTICATION_REQUIRED",provider_sends:0,queue_mutations:0,credentials_printed:false}));
      process.exitCode = 2;
    }
  }
}

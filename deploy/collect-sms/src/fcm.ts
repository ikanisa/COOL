import type { Env } from "./types.ts";
import { after, isoNow, sha256 } from "./util.ts";
type Fetcher = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;
let cached: { identity: string; token: string; expiresAt: number } | undefined;
const encoder = new TextEncoder();
function b64url(bytes: Uint8Array): string {
  let out = "";
  for (const byte of bytes) out += String.fromCharCode(byte);
  return btoa(out).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
function jsonPart(value: unknown): string {
  return b64url(encoder.encode(JSON.stringify(value)));
}
export async function accessToken(
  env: Env,
  fetcher: Fetcher = env.FETCH ?? fetch,
): Promise<string> {
  if (!env.FCM_PROJECT_ID || !env.FCM_CLIENT_EMAIL || !env.FCM_PRIVATE_KEY)
    throw new Error("FCM credentials are incomplete");
  const identity = `${env.FCM_PROJECT_ID}:${env.FCM_CLIENT_EMAIL}:${env.FCM_PRIVATE_KEY}`;
  if (cached?.identity === identity && cached.expiresAt > Date.now() + 60_000)
    return cached.token;
  const now = Math.floor(Date.now() / 1000),
    header = jsonPart({ alg: "RS256", typ: "JWT" }),
    payload = jsonPart({
      iss: env.FCM_CLIENT_EMAIL,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    });
  const pem = env.FCM_PRIVATE_KEY.replace(/\\n/g, "\n").replace(
    /-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g,
    "",
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signingInput = `${header}.${payload}`,
    signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      encoder.encode(signingInput),
    );
  const response = await fetcher("https://oauth2.googleapis.com/token", {
    method: "POST",
    redirect: "manual",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${signingInput}.${b64url(new Uint8Array(signature))}`,
    }).toString(),
  });
  if (response.status >= 300 && response.status < 400)
    throw new Error("FCM OAuth redirect rejected");
  if (!response.ok) throw new Error(`FCM OAuth HTTP ${response.status}`);
  const result = (await response.json()) as {
    access_token?: string;
    expires_in?: number;
  };
  if (!result.access_token)
    throw new Error("FCM OAuth response did not contain a token");
  cached = {
    identity,
    token: result.access_token,
    expiresAt: Date.now() + Math.min(result.expires_in ?? 3600, 3600) * 1000,
  };
  return result.access_token;
}
export async function sendWake(
  env: Env,
  registration: string,
  revision: number,
  fetcher: Fetcher = env.FETCH ?? fetch,
): Promise<{ ok: boolean; unregistered: boolean; error?: string }> {
  let token = await accessToken(env, fetcher);
  const body = JSON.stringify({
    message: {
      token: registration,
      data: { kind: "gateway_sync", revision: String(revision) },
      android: { priority: "NORMAL", ttl: "30s", collapse_key: "gateway_sync" },
    },
  });
  const url = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(env.FCM_PROJECT_ID!)}/messages:send`;
  let response = await fetcher(url, {
    method: "POST",
    redirect: "manual",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body,
  });
  if (response.status === 401) {
    await response.body?.cancel();
    cached = undefined;
    token = await accessToken(env, fetcher);
    response = await fetcher(url, {
      method: "POST",
      redirect: "manual",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body,
    });
  }
  if (response.status >= 300 && response.status < 400)
    return { ok: false, unregistered: false, error: "FCM_REDIRECT_REJECTED" };
  if (response.ok) { await response.body?.cancel(); return { ok: true, unregistered: false }; }
  let unregistered = false;
  try {
    const json = (await response.json()) as {
      error?: { details?: { errorCode?: string }[] };
    };
    unregistered = !!json.error?.details?.some(
      (d) => d.errorCode === "UNREGISTERED",
    );
  } catch {}
  return {
    ok: false,
    unregistered,
    error: unregistered ? "UNREGISTERED" : `FCM_HTTP_${response.status}`,
  };
}
export async function flushWakeups(
  env: Env,
  fetcher: Fetcher = env.FETCH ?? fetch,
): Promise<void> {
  if (env.FCM_ENABLED !== "true") return;
  const rows = await env.DB.prepare(
    "SELECT installation_id,fcm_token,wake_revision,fcm_attempts FROM devices WHERE fcm_pending=1 AND fcm_token IS NOT NULL AND revoked_at IS NULL AND ready=1 AND (fcm_next_at IS NULL OR fcm_next_at<=?) ORDER BY fcm_next_at LIMIT 10",
  )
    .bind(isoNow())
    .all<{
      installation_id: string;
      fcm_token: string;
      wake_revision: number;
      fcm_attempts: number;
    }>();
  for (const row of rows.results) {
    try {
      const result = await sendWake(
        env,
        row.fcm_token,
        row.wake_revision,
        fetcher,
      );
      if (result.ok)
        await env.DB.prepare(
          "UPDATE devices SET fcm_pending=0,fcm_attempts=0,fcm_last_error=NULL WHERE installation_id=? AND wake_revision=? AND fcm_token=?",
        )
          .bind(row.installation_id, row.wake_revision, row.fcm_token)
          .run();
      else if (result.unregistered)
        await env.DB.prepare(
          "UPDATE devices SET fcm_token=NULL,fcm_pending=0,fcm_next_at=NULL,fcm_rejected_token_hash=?,fcm_last_error=? WHERE installation_id=? AND fcm_token=?",
        )
          .bind(
            await sha256(row.fcm_token),
            "UNREGISTERED",
            row.installation_id,
            row.fcm_token,
          )
          .run();
      else await retryWake(env, row, result.error ?? "FCM_FAILURE");
    } catch {
      await retryWake(env, row, "FCM_CONFIGURATION_OR_TRANSPORT_FAILURE");
    }
  }
}
async function retryWake(
  env: Env,
  row: {
    installation_id: string;
    fcm_attempts: number;
    fcm_token: string;
    wake_revision: number;
  },
  error: string,
) {
  const delay = Math.min(900_000, 5_000 * 2 ** Math.min(row.fcm_attempts, 8));
  await env.DB.prepare(
    "UPDATE devices SET fcm_attempts=fcm_attempts+1,fcm_next_at=?,fcm_last_error=? WHERE installation_id=? AND fcm_token=? AND wake_revision=?",
  )
    .bind(
      after(delay),
      error,
      row.installation_id,
      row.fcm_token,
      row.wake_revision,
    )
    .run();
}

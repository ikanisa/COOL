import { execFile } from "node:child_process";
import { lstat } from "node:fs/promises";
import { isAbsolute } from "node:path";

export const productionOrigin = "https://lhbowpbcpwoiparwnwgt.supabase.co";

export function scopedRuntime(value: unknown, environment: NodeJS.ProcessEnv, now = Date.now()): NodeJS.ProcessEnv {
  const fail = () => { throw new Error("OPERATOR_SESSION_REAUTHENTICATION_REQUIRED"); };
  if (!value || typeof value !== "object" || Array.isArray(value)) return fail();
  const row = value as Record<string, unknown>;
  if (row.origin !== productionOrigin || environment.COLLECT_SUPABASE_URL !== productionOrigin ||
      typeof row.anon_key !== "string" || typeof row.access_token !== "string" ||
      Object.hasOwn(row, "refresh_token")) return fail();
  try {
    const token = JSON.parse(Buffer.from(row.access_token.split(".")[1]!, "base64url").toString());
    const key = row.anon_key.startsWith("sb_publishable_") ? {role:"anon"} :
      JSON.parse(Buffer.from(row.anon_key.split(".")[1]!, "base64url").toString());
    if (key.role !== "anon" || token.role !== "authenticated" || !token.sub ||
        token.iss !== `${productionOrigin}/auth/v1` || typeof token.exp !== "number" ||
        token.exp <= Math.floor(now / 1000) + 60) return fail();
  } catch { return fail(); }
  return {...environment, COLLECT_SUPABASE_ANON_KEY:row.anon_key, COLLECT_OPERATOR_ACCESS_TOKEN:row.access_token};
}

export async function runtimeCredentials(environment: NodeJS.ProcessEnv = process.env): Promise<NodeJS.ProcessEnv> {
  if (environment.COLLECT_SUPABASE_ANON_KEY && environment.COLLECT_OPERATOR_ACCESS_TOKEN) return environment;
  const helper = environment.COLLECT_OPERATOR_KEYCHAIN_HELPER;
  if (!helper) return environment;
  if (process.platform !== "darwin" || !isAbsolute(helper)) throw new Error("INVALID_OPERATOR_KEYCHAIN_HELPER");
  const stat = await lstat(helper);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.uid !== process.getuid?.() || (stat.mode & 0o022)) {
    throw new Error("INVALID_OPERATOR_KEYCHAIN_HELPER");
  }
  const raw = await new Promise<string>((resolve, reject) => {
    execFile(helper, ["read"], {timeout:5000,maxBuffer:16384}, (error, stdout) => {
      if (error) reject(new Error("OPERATOR_SESSION_REAUTHENTICATION_REQUIRED"));
      else resolve(stdout);
    });
  });
  let parsed: unknown;
  try { parsed = JSON.parse(raw); } catch { throw new Error("OPERATOR_SESSION_REAUTHENTICATION_REQUIRED"); }
  return scopedRuntime(parsed, environment);
}

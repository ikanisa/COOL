import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireEnv } from "./cors.ts";

export function serviceClient() {
  return createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false } },
  );
}

export function userClient(authorization: string | null) {
  return createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_ANON_KEY"),
    {
      global: { headers: { Authorization: authorization ?? "" } },
      auth: { persistSession: false },
    },
  );
}

export async function requireUser(authorization: string | null) {
  if (!authorization) throw new Error("Authentication required");
  const supabase = userClient(authorization);
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) throw new Error("Authentication required");
  return { supabase, user: data.user };
}

export function requireInternalRequest(req: Request) {
  const expected = requireEnv("INTERNAL_FUNCTION_SECRET");
  const actual = req.headers.get("x-collect-signature") ??
    req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (actual !== expected) {
    throw new Error("Internal function authorization failed");
  }
}

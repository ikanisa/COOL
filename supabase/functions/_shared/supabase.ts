import { createClient } from "npm:@supabase/supabase-js@2";

function requireEnv(...names: string[]): string {
  for (const name of names) {
    const value = Deno.env.get(name)?.trim();
    if (value) {
      return value;
    }
  }

  throw new Error(`Missing environment variable: ${names.join(" or ")}`);
}

function getSupabaseUrl() {
  return requireEnv("SUPABASE_URL", "COOL_PROJECT_SUPABASE_URL");
}

function getSupabaseAnonKey() {
  return requireEnv("SUPABASE_ANON_KEY", "COOL_PROJECT_SUPABASE_ANON_KEY");
}

function getSupabaseServiceRoleKey() {
  return requireEnv(
    "SUPABASE_SERVICE_ROLE_KEY",
    "COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY",
  );
}

export function createAdminClient() {
  return createClient(
    getSupabaseUrl(),
    getSupabaseServiceRoleKey(),
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );
}

export function createAnonClient() {
  return createClient(
    getSupabaseUrl(),
    getSupabaseAnonKey(),
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );
}

export function createUserClient(authorization: string) {
  return createClient(
    getSupabaseUrl(),
    getSupabaseAnonKey(),
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
      global: {
        headers: {
          Authorization: authorization,
        },
      },
    },
  );
}

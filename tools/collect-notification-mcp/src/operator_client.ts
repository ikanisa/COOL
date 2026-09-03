import { runtimeCredentials } from "./runtime_credentials.ts";

export type OperatorEnvironment = {
  supabaseUrl: string;
  anonKey: string;
  accessToken: string;
};

export type FetchLike = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

function requiredEnvironment(name: string, environment: NodeJS.ProcessEnv): string {
  const value = environment[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

export function validatedSupabaseUrl(value: string): string {
  const url = new URL(value);
  const loopback = ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname);
  if ((url.protocol !== "https:" && !(url.protocol === "http:" && loopback)) ||
      url.username || url.password || url.search || url.hash || url.pathname !== "/") {
    throw new Error("COLLECT_SUPABASE_URL must be an HTTPS origin or local loopback HTTP origin");
  }
  return url.origin;
}

export function operatorEnvironment(environment: NodeJS.ProcessEnv = process.env): OperatorEnvironment {
  const supabaseUrl = validatedSupabaseUrl(requiredEnvironment("COLLECT_SUPABASE_URL", environment));
  return {
    supabaseUrl,
    anonKey: requiredEnvironment("COLLECT_SUPABASE_ANON_KEY", environment),
    accessToken: requiredEnvironment("COLLECT_OPERATOR_ACCESS_TOKEN", environment),
  };
}

export async function callNotificationOperator(
  action: string,
  input: Record<string, unknown>,
  environment?: OperatorEnvironment,
  fetcher: FetchLike = fetch,
): Promise<unknown> {
  const actions = ["health", "list_pending", "claim", "get_claimed", "confirm",
    "record_send_start", "record_outcome", "release_claim", "heartbeat"];
  if (!actions.includes(action) || Object.hasOwn(input, "action")) {
    throw new Error("Unsupported or overridden notification operator action");
  }
  const resolved = environment ?? operatorEnvironment(await runtimeCredentials());
  const origin = validatedSupabaseUrl(resolved.supabaseUrl);
  const response = await fetcher(
    `${origin}/functions/v1/collect-notification-operator`,
    {
      method: "POST",
      redirect: "error",
      cache: "no-store",
      signal: AbortSignal.timeout(15_000),
      headers: {
        Authorization: `Bearer ${resolved.accessToken}`,
        apikey: resolved.anonKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ...input, action }),
    },
  );
  const payload = await response.json().catch(() => ({})) as Record<
    string,
    unknown
  >;
  if (!response.ok || payload.ok !== true) {
    const message = typeof payload.error === "string"
      ? payload.error
      : `Collect notification operator failed (${response.status})`;
    throw new Error(message);
  }
  return payload.result;
}

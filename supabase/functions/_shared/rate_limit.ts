import { createAdminClient } from "./supabase.ts";
import { HttpError } from "./auth.ts";

type AdminClientLike = ReturnType<typeof createAdminClient>;

export type RateLimitConfig = {
  /** Maximum number of requests allowed within the window. */
  maxRequests: number;
  /** Time window in seconds. */
  windowSeconds: number;
};

export type RateLimitResult = {
  allowed: boolean;
  retryAfterSeconds?: number;
};

type RateLimitDependencies = {
  now: () => Date;
  countRecent: (
    adminClient: AdminClientLike,
    userId: string,
    functionName: string,
    windowStartIso: string,
  ) => Promise<number>;
  recordInvocation: (
    adminClient: AdminClientLike,
    userId: string,
    functionName: string,
  ) => Promise<void>;
};

async function countRecentInvocations(
  adminClient: AdminClientLike,
  userId: string,
  functionName: string,
  windowStartIso: string,
): Promise<number> {
  const { count, error } = await adminClient
    .from("edge_function_rate_events")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("function_name", functionName)
    .gte("created_at", windowStartIso);

  if (error) {
    // Fail open with a warning rather than blocking the user on a telemetry error.
    console.warn("Rate-limit count query failed:", error);
    return 0;
  }

  return count ?? 0;
}

async function recordInvocation(
  adminClient: AdminClientLike,
  userId: string,
  functionName: string,
): Promise<void> {
  const { error } = await adminClient
    .from("edge_function_rate_events")
    .insert({ user_id: userId, function_name: functionName });

  if (error) {
    console.warn("Rate-limit event insert failed:", error);
  }
}

const defaultDependencies: RateLimitDependencies = {
  now: () => new Date(),
  countRecent: countRecentInvocations,
  recordInvocation,
};

/**
 * Check whether a user is within their rate limit for a given function.
 *
 * Records the invocation when allowed.
 * Throws HttpError(429) when the limit is exceeded.
 */
export async function enforceRateLimit(
  adminClient: AdminClientLike,
  userId: string,
  functionName: string,
  config: RateLimitConfig,
  dependencies: Partial<RateLimitDependencies> = {},
): Promise<void> {
  const deps: RateLimitDependencies = {
    ...defaultDependencies,
    ...dependencies,
  };

  const now = deps.now();
  const windowStartIso = new Date(
    now.getTime() - config.windowSeconds * 1000,
  ).toISOString();

  const recentCount = await deps.countRecent(
    adminClient,
    userId,
    functionName,
    windowStartIso,
  );

  if (recentCount >= config.maxRequests) {
    throw new HttpError(
      429,
      `Rate limit exceeded. Please wait before trying again.`,
    );
  }

  await deps.recordInvocation(adminClient, userId, functionName);
}

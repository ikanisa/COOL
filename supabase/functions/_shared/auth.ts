import { createAdminClient, createUserClient } from "./supabase.ts";

type AuthUserLike = {
  id: string;
  app_metadata?: Record<string, unknown> | null;
};

type UserClientLike = {
  auth: {
    getUser(): Promise<{
      data: { user: AuthUserLike | null };
      error: unknown;
    }>;
  };
};

type AdminClientLike = {
  from(table: string): {
    select(columns: string): {
      eq(column: string, value: string): {
        maybeSingle(): Promise<{
          data: { is_admin?: boolean } | null;
          error: unknown;
        }>;
      };
    };
  };
  rpc(
    fn: string,
    params?: Record<string, unknown>,
  ): Promise<{ data: unknown; error: unknown }>;
};

export class HttpError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

export type AuthenticatedCaller = {
  user: AuthUserLike;
  userId: string;
  appMetadata: Record<string, unknown>;
  isAppAdmin: boolean;
  isAdmin: boolean;
};

type AuthDependencies = {
  createUserClient: (authorization: string) => UserClientLike;
};

type AdminAuthDependencies = AuthDependencies & {
  createAdminClient: () => AdminClientLike;
};

function defaultAuthDependencies(): AuthDependencies {
  return {
    createUserClient: (authorization) =>
      createUserClient(authorization) as unknown as UserClientLike,
  };
}

function defaultAdminAuthDependencies(): AdminAuthDependencies {
  return {
    ...defaultAuthDependencies(),
    createAdminClient: () => createAdminClient() as unknown as AdminClientLike,
  };
}

export function metadataBool(value: unknown): boolean {
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value === "number") {
    return value !== 0;
  }
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    return normalized === "true" || normalized === "1";
  }
  return false;
}

export function getAuthorizationHeader(request: Request): string | null {
  const value = request.headers.get("authorization") ??
    request.headers.get("Authorization");
  const trimmed = value?.trim();
  return trimmed && trimmed.length > 0 ? trimmed : null;
}

export async function requireAuthenticatedCaller(
  request: Request,
  dependencies: Partial<AuthDependencies> = {},
): Promise<AuthenticatedCaller> {
  const deps: AuthDependencies = {
    ...defaultAuthDependencies(),
    ...dependencies,
  };

  const authorization = getAuthorizationHeader(request);
  if (!authorization) {
    throw new HttpError(401, "Authentication required.");
  }

  const userClient = deps.createUserClient(authorization);
  const {
    data: { user },
    error,
  } = await userClient.auth.getUser();

  if (error || !user) {
    throw new HttpError(401, "Authentication required.");
  }

  const appMetadata = (user.app_metadata ?? {}) as Record<string, unknown>;
  const isAppAdmin = metadataBool(appMetadata["is_admin"]);

  return {
    user,
    userId: user.id,
    appMetadata,
    isAppAdmin,
    isAdmin: isAppAdmin,
  };
}

export async function requireAdminCaller(
  request: Request,
  dependencies: Partial<AdminAuthDependencies> = {},
): Promise<AuthenticatedCaller> {
  const deps: AdminAuthDependencies = {
    ...defaultAdminAuthDependencies(),
    ...dependencies,
  };

  const caller = await requireAuthenticatedCaller(request, deps);
  if (caller.isAppAdmin) {
    return caller;
  }

  const adminClient = deps.createAdminClient();
  const { data, error } = await adminClient
    .from("users")
    .select("is_admin")
    .eq("id", caller.userId)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, "Failed to verify admin access.");
  }

  if (data?.is_admin === true) {
    return {
      ...caller,
      isAdmin: true,
    };
  }

  // Third fallback: check role assignments via the RPC.
  // This covers users granted platform access through admin_role_assignments
  // without the legacy users.is_admin flag.
  try {
    const { data: rpcData, error: rpcError } = await adminClient.rpc(
      "get_admin_access_for_user",
      { p_user_id: caller.userId },
    );

    if (
      !rpcError &&
      rpcData &&
      typeof rpcData === "object" &&
      (rpcData as Record<string, unknown>)["has_platform_access"] === true
    ) {
      return {
        ...caller,
        isAdmin: true,
      };
    }
  } catch {
    // RPC not deployed or other transient error — fall through to rejection.
  }

  throw new HttpError(403, "Admin access required.");
}

export function requireCronSecret(
  request: Request,
  envNames: string[] = ["CRON_JOB_SECRET"],
): void {
  const configuredSecret = envNames
    .map((name) => Deno.env.get(name)?.trim())
    .find((value) => value != null && value.length > 0);

  if (!configuredSecret) {
    throw new HttpError(
      500,
      `Missing cron secret configuration: ${envNames.join(" or ")}`,
    );
  }

  const authorization = getAuthorizationHeader(request);
  const bearerToken = authorization?.startsWith("Bearer ")
    ? authorization.slice("Bearer ".length).trim()
    : null;
  const providedSecret = bearerToken ??
    request.headers.get("x-cron-secret")?.trim();

  if (!providedSecret || providedSecret !== configuredSecret) {
    throw new HttpError(401, "Unauthorized.");
  }
}

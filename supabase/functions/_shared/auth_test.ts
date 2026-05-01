import {
  getAuthorizationHeader,
  HttpError,
  metadataBool,
  requireAdminCaller,
  requireAuthenticatedCaller,
  requireCronSecret,
} from "./auth.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`);
  }
}

function expectHttpError(
  error: unknown,
  status: number,
  message: string,
): void {
  if (!(error instanceof HttpError)) {
    throw new Error(`${message}: expected HttpError`);
  }
  assertEquals(error.status, status, `${message}: status`);
}

Deno.test("metadataBool accepts common truthy encodings", () => {
  assert(metadataBool(true), "boolean true should be truthy");
  assert(metadataBool(1), "number 1 should be truthy");
  assert(metadataBool("true"), "string true should be truthy");
  assert(metadataBool("1"), "string 1 should be truthy");
  assert(!metadataBool("false"), "string false should be falsy");
});

Deno.test("getAuthorizationHeader reads either header casing", () => {
  const request = new Request("https://example.com", {
    headers: { Authorization: "Bearer token-1" },
  });

  assertEquals(
    getAuthorizationHeader(request),
    "Bearer token-1",
    "should read the authorization header",
  );
});

Deno.test("requireAuthenticatedCaller rejects requests without auth", async () => {
  try {
    await requireAuthenticatedCaller(new Request("https://example.com"));
    throw new Error("expected requireAuthenticatedCaller to throw");
  } catch (error) {
    expectHttpError(error, 401, "missing auth should fail");
  }
});

Deno.test("requireAdminCaller allows app metadata admins without a profile lookup", async () => {
  let profileLookups = 0;
  const caller = await requireAdminCaller(
    new Request("https://example.com", {
      headers: { authorization: "Bearer test-token" },
    }),
    {
      createUserClient: () => ({
        auth: {
          getUser: async () => ({
            data: {
              user: {
                id: "admin-1",
                app_metadata: { is_admin: true },
              },
            },
            error: null,
          }),
        },
      }),
      createAdminClient: () => ({
        from: () => ({
          select: () => ({
            eq: () => ({
              maybeSingle: async () => {
                profileLookups += 1;
                return { data: { is_admin: false }, error: null };
              },
            }),
          }),
        }),
        rpc: async () => ({
          data: { has_platform_access: false, role_assignments: [] },
          error: null,
        }),
      }),
    },
  );

  assertEquals(caller.userId, "admin-1", "should return the caller user id");
  assertEquals(profileLookups, 0, "app metadata admins should short-circuit");
});

Deno.test("requireAdminCaller falls back to public.users.is_admin", async () => {
  const caller = await requireAdminCaller(
    new Request("https://example.com", {
      headers: { authorization: "Bearer test-token" },
    }),
    {
      createUserClient: () => ({
        auth: {
          getUser: async () => ({
            data: {
              user: {
                id: "admin-2",
                app_metadata: {},
              },
            },
            error: null,
          }),
        },
      }),
      createAdminClient: () => ({
        from: () => ({
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({
                data: { is_admin: true },
                error: null,
              }),
            }),
          }),
        }),
        rpc: async () => ({ data: null, error: "unused" }),
      }),
    },
  );

  assert(caller.isAdmin, "db-backed admins should be accepted");
});

Deno.test("requireAdminCaller accepts role-assigned platform admins via RPC", async () => {
  const caller = await requireAdminCaller(
    new Request("https://example.com", {
      headers: { authorization: "Bearer test-token" },
    }),
    {
      createUserClient: () => ({
        auth: {
          getUser: async () => ({
            data: {
              user: {
                id: "role-admin-1",
                app_metadata: {},
              },
            },
            error: null,
          }),
        },
      }),
      createAdminClient: () => ({
        from: () => ({
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({
                data: { is_admin: false },
                error: null,
              }),
            }),
          }),
        }),
        rpc: async (fn: string, params?: Record<string, unknown>) => {
          assertEquals(fn, "get_admin_access_for_user", "should call RPC");
          assertEquals(
            (params as Record<string, unknown>)?.p_user_id,
            "role-admin-1",
            "should pass the user ID",
          );
          return {
            data: { has_platform_access: true, role_assignments: [] },
            error: null,
          };
        },
      }),
    },
  );

  assert(caller.isAdmin, "role-assigned admins should be accepted");
  assertEquals(caller.userId, "role-admin-1", "should return correct user");
});

Deno.test("requireAdminCaller rejects non-admin users (including no role assignments)", async () => {
  try {
    await requireAdminCaller(
      new Request("https://example.com", {
        headers: { authorization: "Bearer test-token" },
      }),
      {
        createUserClient: () => ({
          auth: {
            getUser: async () => ({
              data: {
                user: {
                  id: "user-1",
                  app_metadata: {},
                },
              },
              error: null,
            }),
          },
        }),
        createAdminClient: () => ({
          from: () => ({
            select: () => ({
              eq: () => ({
                maybeSingle: async () => ({
                  data: { is_admin: false },
                  error: null,
                }),
              }),
            }),
          }),
          rpc: async () => ({
            data: { has_platform_access: false, role_assignments: [] },
            error: null,
          }),
        }),
      },
    );
    throw new Error("expected requireAdminCaller to throw");
  } catch (error) {
    expectHttpError(error, 403, "non-admin should be rejected");
  }
});

Deno.test("requireCronSecret accepts bearer and x-cron-secret inputs", () => {
  requireCronSecret(
    new Request("https://example.com", {
      headers: { authorization: "Bearer secret-123" },
    }),
    ["TEST_CRON_SECRET"],
    (name) => name === "TEST_CRON_SECRET" ? "secret-123" : undefined,
  );

  requireCronSecret(
    new Request("https://example.com", {
      headers: { "x-cron-secret": "secret-123" },
    }),
    ["TEST_CRON_SECRET"],
    (name) => name === "TEST_CRON_SECRET" ? "secret-123" : undefined,
  );
});

Deno.test("requireCronSecret rejects partial prefix matches", () => {
  try {
    requireCronSecret(
      new Request("https://example.com", {
        headers: { authorization: "Bearer secret" },
      }),
      ["TEST_CRON_SECRET"],
      (name) => name === "TEST_CRON_SECRET" ? "secret-123" : undefined,
    );
    throw new Error("expected requireCronSecret to throw");
  } catch (error) {
    expectHttpError(error, 401, "partial cron secret should fail");
  }
});

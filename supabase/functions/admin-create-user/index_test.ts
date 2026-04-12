import {
  createAdminCreateUserHandler,
  type AdminCreateUserHandlerDependencies,
} from "./index.ts";

function createDeps(overrides: Partial<AdminCreateUserHandlerDependencies> = {}) {
  const listUsersCalls: Array<{ page: number; perPage: number }> = [];
  const insertedRoles: Array<Record<string, unknown>> = [];
  const upsertedUsers: Array<Record<string, unknown>> = [];

  const deps: AdminCreateUserHandlerDependencies = {
    createAdminClient: () =>
      ({
        auth: {
          admin: {
            listUsers: async ({
              page,
              perPage,
            }: {
              page: number;
              perPage: number;
            }) => {
              listUsersCalls.push({ page, perPage });
              return { data: { users: [] }, error: null };
            },
            createUser: async () => ({
              data: { user: { id: "auth-user-1" } },
              error: null,
            }),
          },
        },
        from: (table: string) => {
          if (table === "users") {
            return {
              select: () => ({
                eq: () => ({
                  maybeSingle: async () => ({ data: null, error: null }),
                }),
              }),
              upsert: async (payload: Record<string, unknown>) => {
                upsertedUsers.push(payload);
                return { error: null };
              },
            };
          }

          if (table === "admin_role_assignments") {
            return {
              select: () => ({
                eq: () => ({
                  eq: () => ({
                    is: () => ({
                      order: () => ({
                        limit: () => ({
                          maybeSingle: async () => ({ data: null, error: null }),
                        }),
                      }),
                    }),
                  }),
                }),
              }),
              insert: async (payload: Record<string, unknown>) => {
                insertedRoles.push(payload);
                return { error: null };
              },
              update: async () => ({
                eq: async () => ({ error: null }),
              }),
            };
          }

          throw new Error(`Unexpected table: ${table}`);
        },
      }) as unknown as ReturnType<
        AdminCreateUserHandlerDependencies["createAdminClient"]
      >,
    requireAdminCaller: async () =>
      ({
        userId: "admin-user-1",
        user: { id: "admin-user-1" },
        appMetadata: {},
        isAdmin: true,
        isAppAdmin: true,
      }) as never,
    recordEdgeFunctionFailure: async () => {},
    ...overrides,
  };

  return {
    deps,
    listUsersCalls,
    insertedRoles,
    upsertedUsers,
  };
}

Deno.test("admin-create-user provisions a new user and optional platform role", async () => {
  const { deps, listUsersCalls, insertedRoles, upsertedUsers } = createDeps();
  const handler = createAdminCreateUserHandler(deps);

  const response = await handler(
    new Request("https://example.com/functions/v1/admin-create-user", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        fullName: "Jeanne Tester",
        phone: "+250788123456",
        country: "rw",
        grantPlatformAdmin: true,
      }),
    }),
  );
  const payload = await response.json();

  if (response.status !== 200) {
    throw new Error(`Expected 200 response, received ${response.status}`);
  }
  if (!payload.success) {
    throw new Error(`Expected success payload: ${JSON.stringify(payload)}`);
  }
  if (listUsersCalls.length !== 1) {
    throw new Error(`Expected one listUsers call, got ${listUsersCalls.length}`);
  }
  if (upsertedUsers.length !== 1) {
    throw new Error(`Expected one public.users upsert, got ${upsertedUsers.length}`);
  }
  if (insertedRoles.length !== 1) {
    throw new Error(`Expected one admin role insert, got ${insertedRoles.length}`);
  }
});

Deno.test("admin-create-user rejects duplicate public user phones", async () => {
  const { deps } = createDeps({
    createAdminClient: () =>
      ({
        auth: {
          admin: {
            listUsers: async () => ({ data: { users: [] }, error: null }),
            createUser: async () => ({
              data: { user: { id: "auth-user-1" } },
              error: null,
            }),
          },
        },
        from: (table: string) => {
          if (table === "users") {
            return {
              select: () => ({
                eq: () => ({
                  maybeSingle: async () => ({
                    data: { id: "existing-user-1", phone: "+250788123456" },
                    error: null,
                  }),
                }),
              }),
              upsert: async () => ({ error: null }),
            };
          }

          if (table === "admin_role_assignments") {
            return {
              select: () => ({
                eq: () => ({
                  eq: () => ({
                    is: () => ({
                      order: () => ({
                        limit: () => ({
                          maybeSingle: async () => ({ data: null, error: null }),
                        }),
                      }),
                    }),
                  }),
                }),
              }),
              insert: async () => ({ error: null }),
              update: async () => ({
                eq: async () => ({ error: null }),
              }),
            };
          }

          throw new Error(`Unexpected table: ${table}`);
        },
      }) as unknown as ReturnType<
        AdminCreateUserHandlerDependencies["createAdminClient"]
      >,
  });
  const handler = createAdminCreateUserHandler(deps);

  const response = await handler(
    new Request("https://example.com/functions/v1/admin-create-user", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        fullName: "Duplicate User",
        phone: "+250788123456",
      }),
    }),
  );
  const payload = await response.json();

  if (response.status !== 409) {
    throw new Error(`Expected 409 response, received ${response.status}`);
  }
  if (payload.message !== "A user with this phone number already exists.") {
    throw new Error(`Unexpected payload: ${JSON.stringify(payload)}`);
  }
});

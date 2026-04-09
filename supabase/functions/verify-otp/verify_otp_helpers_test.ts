import { ensureAuthUser } from "./verify_otp_helpers.ts";

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

function assertHasRwandaEnglishDefaults(
  payload: Record<string, unknown>,
  messagePrefix: string,
): void {
  const metadata = payload["user_metadata"];
  if (!metadata || typeof metadata !== "object") {
    throw new Error(`${messagePrefix}: user_metadata missing`);
  }

  const values = metadata as Record<string, unknown>;
  assertEquals(values["country"], "RW", `${messagePrefix}: country`);
  assertEquals(
    values["language_code"],
    "en",
    `${messagePrefix}: language_code`,
  );
  assertEquals(values["market"], "RW", `${messagePrefix}: market`);
  assertEquals(
    values["ui_language"],
    "en",
    `${messagePrefix}: ui_language`,
  );
}

Deno.test("ensureAuthUser stamps Rwanda English defaults when creating users", async () => {
  let capturedCreatePayload: Record<string, unknown> | null = null;

  const adminClient = {
    rpc: async () => ({
      data: [],
      error: null,
    }),
    auth: {
      admin: {
        getUserById: async () => ({
          data: { user: null },
          error: null,
        }),
        createUser: async (payload: Record<string, unknown>) => {
          capturedCreatePayload = payload;
          return {
            data: { user: { id: "auth-user-1" } },
            error: null,
          };
        },
        updateUserById: async () => ({
          data: { user: { id: "auth-user-1" } },
          error: null,
        }),
      },
    },
  } as unknown;

  const result = await ensureAuthUser(
    adminClient as Parameters<typeof ensureAuthUser>[0],
    "+250781234567",
    "user@example.com",
  );

  assert(capturedCreatePayload != null, "createUser payload should be captured");
  assertHasRwandaEnglishDefaults(
    capturedCreatePayload!,
    "createUser payload",
  );
  assertEquals(result.created, true, "new users should report created=true");
});

Deno.test("ensureAuthUser preserves existing metadata and restamps Rwanda English defaults on update", async () => {
  let capturedUpdatePayload: Record<string, unknown> | null = null;

  const adminClient = {
    rpc: async () => ({
      data: [{ user_id: "auth-user-2" }],
      error: null,
    }),
    auth: {
      admin: {
        getUserById: async () => ({
          data: {
            user: {
              id: "auth-user-2",
              user_metadata: {
                phone: "+250700000000",
                custom_flag: "keep-me",
                country: "UG",
              },
            },
          },
          error: null,
        }),
        createUser: async () => ({
          data: { user: { id: "auth-user-2" } },
          error: null,
        }),
        updateUserById: async (
          _userId: string,
          payload: Record<string, unknown>,
        ) => {
          capturedUpdatePayload = payload;
          return {
            data: { user: { id: "auth-user-2" } },
            error: null,
          };
        },
      },
    },
  } as unknown;

  const result = await ensureAuthUser(
    adminClient as Parameters<typeof ensureAuthUser>[0],
    "+250781234567",
    "user@example.com",
  );

  assert(capturedUpdatePayload != null, "updateUserById payload should be captured");
  assertHasRwandaEnglishDefaults(
    capturedUpdatePayload!,
    "updateUserById payload",
  );
  const metadata = capturedUpdatePayload!["user_metadata"] as Record<
    string,
    unknown
  >;
  assertEquals(
    metadata["custom_flag"],
    "keep-me",
    "existing user metadata should be preserved",
  );
  assertEquals(result.created, false, "existing users should report created=false");
});

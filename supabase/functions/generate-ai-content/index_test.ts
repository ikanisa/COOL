import {
  createGenerateAiContentHandler,
  type GenerateAiContentHandlerDependencies,
} from "./index.ts";
import { HttpError } from "../_shared/auth.ts";

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

function buildAdminClient(overrides: {
  configEnabled?: boolean;
  existingTitles?: string[];
} = {}) {
  const inserts: Record<string, unknown>[] = [];
  const configUpdates: Record<string, unknown>[] = [];

  const client = {
    from(table: string) {
      if (table === "ai_content_generation_config") {
        return {
          select() {
            return {
              limit() {
                return {
                  maybeSingle: async () => ({
                    data: { is_enabled: overrides.configEnabled ?? false },
                    error: null,
                  }),
                };
              },
            };
          },
          update(payload: Record<string, unknown>) {
            configUpdates.push(payload);
            return {
              not: async () => ({ error: null }),
            };
          },
        };
      }

      if (table === "ai_content") {
        return {
          select() {
            return {
              eq(_column: string, value: string) {
                return {
                  limit: async () => ({
                    data: (overrides.existingTitles ?? []).includes(value)
                      ? [{ id: "existing-1" }]
                      : [],
                    error: null,
                  }),
                };
              },
            };
          },
          insert(payload: Record<string, unknown>) {
            inserts.push(payload);
            return Promise.resolve({ error: null });
          },
        };
      }

      throw new Error(`Unexpected table: ${table}`);
    },
  };

  return {
    client: client as unknown as ReturnType<
      GenerateAiContentHandlerDependencies["createAdminClient"]
    >,
    getState: () => ({ inserts, configUpdates }),
  };
}

function buildHandler(
  overrides: Partial<GenerateAiContentHandlerDependencies> = {},
) {
  const { client, getState } = buildAdminClient();
  const handler = createGenerateAiContentHandler({
    createAdminClient: () => client,
    requireAdminCaller: async () => ({
      userId: "admin-1",
      user: { id: "admin-1", app_metadata: { is_admin: true } },
      appMetadata: { is_admin: true },
      isAppAdmin: true,
      isAdmin: true,
    }),
    requireCronSecret: () => undefined,
    generateContent: async () => ({
      title: "Weekly Savings Boost",
      subtitle: "Keep your spending in view",
      body: "Set aside a small amount after each mobile money cash-in.",
      rationale: "Small recurring habits compound faster than one-off goals.",
    }),
    random: () => 0,
    now: () => new Date("2026-03-23T12:00:00.000Z"),
    ...overrides,
  });

  return { handler, getState };
}

Deno.test("generate-ai-content requires admin auth for manual runs", async () => {
  const { handler } = buildHandler({
    requireAdminCaller: async () => {
      throw new HttpError(403, "Admin access required.");
    },
  });

  const response = await handler(
    new Request(
      "https://example.com/functions/v1/generate-ai-content?manual=true",
      {
        method: "POST",
      },
    ),
  );
  const payload = await response.json();

  assertEquals(response.status, 403, "manual runs should be forbidden");
  assertEquals(
    payload.message,
    "Admin access required.",
    "should surface auth error",
  );
});

Deno.test("generate-ai-content requires a cron secret for automated runs", async () => {
  const { handler } = buildHandler({
    requireCronSecret: () => {
      throw new HttpError(401, "Unauthorized.");
    },
  });

  const response = await handler(
    new Request("https://example.com/functions/v1/generate-ai-content", {
      method: "POST",
    }),
  );
  const payload = await response.json();

  assertEquals(response.status, 401, "cron runs should require a secret");
  assertEquals(
    payload.message,
    "Unauthorized.",
    "should surface cron auth error",
  );
});

Deno.test("generate-ai-content skips automated generation when disabled", async () => {
  const { client, getState } = buildAdminClient({ configEnabled: false });
  let generated = false;
  const handler = createGenerateAiContentHandler({
    createAdminClient: () => client,
    requireCronSecret: () => undefined,
    generateContent: async () => {
      generated = true;
      return null;
    },
    random: () => 0,
    now: () => new Date("2026-03-23T12:00:00.000Z"),
  });

  const response = await handler(
    new Request("https://example.com/functions/v1/generate-ai-content", {
      method: "POST",
    }),
  );
  const payload = await response.json();

  assertEquals(
    response.status,
    200,
    "disabled auto-generation should short-circuit",
  );
  assertEquals(
    payload.reason,
    "Auto-generation is disabled by admin",
    "should explain why it skipped",
  );
  assert(!generated, "generator should not be called when disabled");
  assertEquals(getState().inserts.length, 0, "no content should be inserted");
});

Deno.test("generate-ai-content records the acting admin on manual success", async () => {
  const { handler, getState } = buildHandler();

  const response = await handler(
    new Request(
      "https://example.com/functions/v1/generate-ai-content?manual=true",
      {
        method: "POST",
      },
    ),
  );
  const payload = await response.json();
  const state = getState();

  assertEquals(response.status, 200, "manual generation should succeed");
  assertEquals(payload.success, true, "payload should report success");
  assertEquals(state.inserts.length, 1, "should insert one content row");
  assertEquals(
    state.configUpdates[0]?.updated_by,
    "admin-1",
    "manual runs should attribute the config update",
  );
});

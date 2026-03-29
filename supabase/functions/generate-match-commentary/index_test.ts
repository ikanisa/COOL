import {
  createGenerateMatchCommentaryHandler,
  type GenerateMatchCommentaryHandlerDependencies,
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

function buildAdminClient() {
  const inserts: Record<string, unknown>[] = [];

  const client = {
    from(table: string) {
      if (table !== "rs_match_commentary") {
        throw new Error(`Unexpected table: ${table}`);
      }

      return {
        insert(payload: Record<string, unknown>) {
          inserts.push(payload);
          return {
            select() {
              return {
                single: async () => ({
                  data: { id: "commentary-1", ...payload },
                  error: null,
                }),
              };
            },
          };
        },
      };
    },
  };

  return {
    client: client as unknown as ReturnType<
      GenerateMatchCommentaryHandlerDependencies["createAdminClient"]
    >,
    getState: () => ({ inserts }),
  };
}

function buildHandler(
  overrides: Partial<GenerateMatchCommentaryHandlerDependencies> = {},
) {
  const { client, getState } = buildAdminClient();
  const handler = createGenerateMatchCommentaryHandler({
    createAdminClient: () => client,
    requireAdminCaller: async () => ({
      userId: "admin-1",
      user: { id: "admin-1", app_metadata: { is_admin: true } },
      appMetadata: { is_admin: true },
      isAppAdmin: true,
      isAdmin: true,
    }),
    generateCommentary: async () => ({
      title: "Rayon edge late rivals in Kigali",
      body: "A composed late finish settled a tense fixture under the lights.",
    }),
    ...overrides,
  });

  return { handler, getState };
}

function buildRequest(body: Record<string, unknown>) {
  return new Request(
    "https://example.com/functions/v1/generate-match-commentary",
    {
      method: "POST",
      body: JSON.stringify(body),
      headers: {
        "Content-Type": "application/json",
      },
    },
  );
}

Deno.test("generate-match-commentary requires admin auth", async () => {
  const { handler } = buildHandler({
    requireAdminCaller: async () => {
      throw new HttpError(403, "Admin access required.");
    },
  });

  const response = await handler(
    buildRequest({
      match_id: "match-1",
      home_team: "Rayon Sports",
      away_team: "APR FC",
    }),
  );
  const payload = await response.json();

  assertEquals(response.status, 403, "non-admin callers should be rejected");
  assertEquals(
    payload.message,
    "Admin access required.",
    "should surface the admin auth error",
  );
});

Deno.test("generate-match-commentary validates required body fields", async () => {
  let generated = false;
  const { handler } = buildHandler({
    generateCommentary: async () => {
      generated = true;
      return {
        title: "unused",
        body: "unused",
      };
    },
  });

  const response = await handler(
    buildRequest({
      home_team: "Rayon Sports",
      away_team: "APR FC",
    }),
  );
  const payload = await response.json();

  assertEquals(response.status, 400, "missing match_id should fail validation");
  assertEquals(
    payload.message,
    "match_id, home_team, and away_team are required.",
    "should explain the validation failure",
  );
  assert(!generated, "generation should not run when validation fails");
});

Deno.test("generate-match-commentary inserts a published recap by default", async () => {
  const { handler, getState } = buildHandler();

  const response = await handler(
    buildRequest({
      match_id: "match-1",
      home_team: "Rayon Sports",
      away_team: "APR FC",
      home_score: 2,
      away_score: 1,
      commentary_type: "something-else",
    }),
  );
  const payload = await response.json();
  const insert = getState().inserts[0];

  assertEquals(response.status, 200, "valid requests should succeed");
  assertEquals(payload.success, true, "payload should report success");
  assertEquals(
    getState().inserts.length,
    1,
    "should insert one commentary row",
  );
  assertEquals(
    insert.commentary_type as string,
    "recap",
    "invalid commentary types should normalize to recap",
  );
  assertEquals(
    insert.is_published as boolean,
    true,
    "generated commentary should be published",
  );

  const metadata = insert.metadata as Record<string, unknown>;
  assertEquals(
    metadata.generated_by as string,
    "admin-1",
    "insert metadata should record the acting admin",
  );
});

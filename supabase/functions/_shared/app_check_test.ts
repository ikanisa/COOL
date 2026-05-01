import { requireAppCheckToken } from "./app_check.ts";
import { HttpError } from "./auth.ts";

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
    throw new Error(`${message}: expected HttpError, got ${error}`);
  }
  assertEquals(error.status, status, `${message}: status`);
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.test("requireAppCheckToken rejects missing header", async () => {
  try {
    await requireAppCheckToken(new Request("https://example.com"));
    throw new Error("should have thrown");
  } catch (error) {
    expectHttpError(error, 401, "missing header");
  }
});

Deno.test("requireAppCheckToken rejects empty header", async () => {
  try {
    await requireAppCheckToken(
      new Request("https://example.com", {
        headers: { "X-Firebase-AppCheck": "" },
      }),
    );
    throw new Error("should have thrown");
  } catch (error) {
    expectHttpError(error, 401, "empty header");
  }
});

Deno.test("requireAppCheckToken rejects invalid tokens from the verifier", async () => {
  try {
    await requireAppCheckToken(
      new Request("https://example.com", {
        headers: { "X-Firebase-AppCheck": "not-a-jwt" },
      }),
      {
        getAccessToken: async () => "access-token",
        getProjectId: () => "project-id",
        fetchFn: async () => jsonResponse({}, 403),
      },
    );
    throw new Error("should have thrown");
  } catch (error) {
    expectHttpError(error, 401, "invalid token");
  }
});

Deno.test("requireAppCheckToken rejects already-consumed limited-use tokens", async () => {
  try {
    await requireAppCheckToken(
      new Request("https://example.com", {
        headers: { "X-Firebase-AppCheck": "fresh-token" },
      }),
      {
        getAccessToken: async () => "access-token",
        getProjectId: () => "project-id",
        fetchFn: async () => jsonResponse({ alreadyConsumed: true }),
      },
    );
    throw new Error("should have thrown");
  } catch (error) {
    expectHttpError(error, 409, "consumed token");
  }
});

Deno.test("requireAppCheckToken returns 503 when the provider is unsupported", async () => {
  try {
    await requireAppCheckToken(
      new Request("https://example.com", {
        headers: { "X-Firebase-AppCheck": "fresh-token" },
      }),
      {
        getAccessToken: async () => "access-token",
        getProjectId: () => "project-id",
        fetchFn: async () => jsonResponse({}, 400),
      },
    );
    throw new Error("should have thrown");
  } catch (error) {
    expectHttpError(error, 503, "unsupported provider");
  }
});

Deno.test("requireAppCheckToken accepts valid tokens", async () => {
  const result = await requireAppCheckToken(
    new Request("https://example.com", {
      headers: { "X-Firebase-AppCheck": "fresh-token" },
    }),
    {
      getAccessToken: async () => "access-token",
      getProjectId: () => "project-id",
      fetchFn: async () => jsonResponse({}),
    },
  );

  assertEquals(result, "fresh-token", "should return the token string");
});

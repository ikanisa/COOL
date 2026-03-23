import { enforceRateLimit } from "./rate_limit.ts";
import { HttpError } from "./auth.ts";

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

function buildMockAdminClient(recentCount: number) {
  const inserts: Record<string, unknown>[] = [];

  const client = {
    from(table: string) {
      if (table !== "edge_function_rate_events") {
        throw new Error(`Unexpected table: ${table}`);
      }

      return {
        select(_columns: string, _opts?: Record<string, unknown>) {
          return {
            eq(_col: string, _val: string) {
              return {
                eq(_col2: string, _val2: string) {
                  return {
                    gte(_col3: string, _val3: string) {
                      return Promise.resolve({
                        count: recentCount,
                        error: null,
                      });
                    },
                  };
                },
              };
            },
          };
        },
        insert(payload: Record<string, unknown>) {
          inserts.push(payload);
          return Promise.resolve({ error: null });
        },
      };
    },
  };

  return { client: client as any, getInserts: () => inserts };
}

Deno.test("enforceRateLimit allows requests under the limit", async () => {
  const { client, getInserts } = buildMockAdminClient(3);

  await enforceRateLimit(client, "user-1", "test-fn", {
    maxRequests: 10,
    windowSeconds: 60,
  });

  assertEquals(getInserts().length, 1, "should record the invocation");
  assertEquals(
    getInserts()[0].function_name,
    "test-fn",
    "should record the correct function name",
  );
});

Deno.test("enforceRateLimit throws 429 when limit is exceeded", async () => {
  const { client } = buildMockAdminClient(10);

  try {
    await enforceRateLimit(client, "user-1", "test-fn", {
      maxRequests: 10,
      windowSeconds: 60,
    });
    throw new Error("expected enforceRateLimit to throw");
  } catch (error) {
    assert(error instanceof HttpError, "should throw HttpError");
    assertEquals((error as HttpError).status, 429, "should return 429");
  }
});

Deno.test("enforceRateLimit fails open when count query returns zero", async () => {
  let insertCalled = false;

  // When the count returns 0 (e.g. table is empty or query failed upstream),
  // the function should proceed and record the invocation.
  await enforceRateLimit(
    {} as any,
    "user-1",
    "test-fn",
    { maxRequests: 5, windowSeconds: 60 },
    {
      countRecent: async () => 0,
      recordInvocation: async () => {
        insertCalled = true;
      },
    },
  );

  assert(insertCalled, "should have recorded the invocation (fail-open)");
});

Deno.test("enforceRateLimit uses dependency-injected count", async () => {
  let countCalls = 0;
  let recordCalls = 0;

  await enforceRateLimit(
    {} as any,
    "user-42",
    "fn-test",
    { maxRequests: 5, windowSeconds: 120 },
    {
      now: () => new Date("2026-03-23T12:00:00.000Z"),
      countRecent: async () => {
        countCalls += 1;
        return 2;
      },
      recordInvocation: async () => {
        recordCalls += 1;
      },
    },
  );

  assertEquals(countCalls, 1, "should call countRecent once");
  assertEquals(recordCalls, 1, "should call recordInvocation once");
});

Deno.test("enforceRateLimit blocks with injected over-limit count", async () => {
  try {
    await enforceRateLimit(
      {} as any,
      "user-42",
      "fn-test",
      { maxRequests: 5, windowSeconds: 120 },
      {
        now: () => new Date("2026-03-23T12:00:00.000Z"),
        countRecent: async () => 5,
        recordInvocation: async () => {
          throw new Error("should not record when blocked");
        },
      },
    );
    throw new Error("expected enforceRateLimit to throw");
  } catch (error) {
    assert(error instanceof HttpError, "should throw HttpError");
    assertEquals((error as HttpError).status, 429, "should return 429");
  }
});

import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { fetchOpenAIWithRetry, OpenAIHttpError } from "./openai_retry.ts";

function errorResponse(
  status: number,
  code: string,
  headers: HeadersInit = {},
) {
  return new Response(
    JSON.stringify({ error: { code, message: "not logged" } }),
    {
      status,
      headers: { "content-type": "application/json", ...headers },
    },
  );
}

Deno.test("quota 429 is classified and never retried", async () => {
  let calls = 0;
  const error = await assertRejects(
    () =>
      fetchOpenAIWithRetry(
        () => {
          calls += 1;
          return Promise.resolve(
            errorResponse(429, "credit_balance_exhausted"),
          );
        },
        { wait: () => Promise.resolve() },
      ),
    OpenAIHttpError,
    "quota",
  );
  assertEquals(calls, 1);
  assertEquals(error.kind, "quota");
  assertEquals(error.retryable, false);
});

Deno.test("rate-limit 429 honors bounded Retry-After then succeeds", async () => {
  let calls = 0;
  const waits: number[] = [];
  const response = await fetchOpenAIWithRetry(
    () => {
      calls += 1;
      return Promise.resolve(
        calls === 1
          ? errorResponse(429, "rate_limit_exceeded", { "retry-after": "20" })
          : new Response("{}", { status: 200 }),
      );
    },
    {
      maxDelayMs: 2_500,
      wait: (milliseconds) => {
        waits.push(milliseconds);
        return Promise.resolve();
      },
    },
  );
  assertEquals(response.status, 200);
  assertEquals(calls, 2);
  assertEquals(waits, [2_500]);
});

Deno.test("transient server failure uses exponential backoff", async () => {
  let calls = 0;
  const waits: number[] = [];
  await fetchOpenAIWithRetry(
    () => {
      calls += 1;
      return Promise.resolve(
        calls < 3
          ? errorResponse(503, "server_error")
          : new Response("{}", { status: 200 }),
      );
    },
    {
      random: () => 0,
      wait: (milliseconds) => {
        waits.push(milliseconds);
        return Promise.resolve();
      },
    },
  );
  assertEquals(calls, 3);
  assertEquals(waits, [300, 600]);
});

Deno.test("non-retryable request failures stop immediately", async () => {
  let calls = 0;
  await assertRejects(
    () =>
      fetchOpenAIWithRetry(
        () => {
          calls += 1;
          return Promise.resolve(errorResponse(400, "invalid_request_error"));
        },
        { wait: () => Promise.resolve() },
      ),
    OpenAIHttpError,
    "(400)",
  );
  assertEquals(calls, 1);
});

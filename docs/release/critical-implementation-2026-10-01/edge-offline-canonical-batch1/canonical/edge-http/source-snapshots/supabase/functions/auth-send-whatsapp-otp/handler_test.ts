import { assertEquals } from "../_shared/test_assert.ts";
import { PublicError } from "../_shared/production_contract.ts";
import { sha256Hex } from "../_shared/hash.ts";
import {
  createOtpHandler,
  type OtpDependencies,
  type OtpReceipt,
  type OtpState,
} from "./handler.ts";

const now = Date.parse("2026-09-30T12:00:00Z");
const secret = btoa(String.fromCharCode(...new Uint8Array(32).fill(7)));
const attempt = "11111111-1111-4111-8111-111111111111";
const privateText =
  "Bearer SECRET_TOKEN SQL users_private +250788123456 OTP 123456";
const baseEnv: Record<string, string> = {
  SEND_SMS_HOOK_SECRET: "v1,whsec_" + secret,
  WHATSAPP_GRAPH_API_VERSION: "v25.0",
  WHATSAPP_PHONE_NUMBER_ID: "1234",
  WHATSAPP_CLOUD_OTP_AUTH_BUTTON: "true",
  WHATSAPP_CLOUD_API_TOKEN: "SECRET_TOKEN",
  WHATSAPP_AUTH_TEMPLATE_NAME: "collect_otp",
  WHATSAPP_AUTH_TEMPLATE_LANGUAGE: "en_US",
};
async function request(
  options: { id?: string; body?: string; time?: number; key?: string } = {},
) {
  const id = options.id ?? "hook_signed_test";
  const body = options.body ??
    JSON.stringify({
      user: { phone: "+250788123456" },
      sms: { otp: "123456" },
    });
  const time = options.time ?? now / 1000;
  const key = await crypto.subtle.importKey(
    "raw",
    Uint8Array.from(atob(options.key ?? secret), (c) => c.charCodeAt(0)),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = btoa(
    String.fromCharCode(
      ...new Uint8Array(
        await crypto.subtle.sign(
          "HMAC",
          key,
          new TextEncoder().encode(`${id}.${time}.${body}`),
        ),
      ),
    ),
  );
  return new Request("https://edge.test/otp", {
    method: "POST",
    headers: {
      "webhook-id": id,
      "webhook-timestamp": String(time),
      "webhook-signature": "v1," + signature,
    },
    body,
  });
}
function fixture(budgets?: { totalMs: number; providerMs: number }) {
  const env = { ...baseEnv };
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const rows = new Map<string, OtpReceipt>();
  let sends = 0, quota = 0;
  let provider: OtpDependencies["fetch"] = () =>
    Promise.resolve(new Response('{"messages":[{"id":"wamid.test-only"}]}'));
  let rpcOverride:
    | ((name: string, args: Record<string, unknown>) => unknown)
    | null = null;
  const deps: OtpDependencies = {
    budgets,
    env: (name) => env[name],
    now: () => now,
    service: () => ({
      rpc: async (name, args) => {
        calls.push({ name, args });
        if (rpcOverride) {
          const result = await rpcOverride(name, args);
          if (result !== undefined) {
            return result as {
              data: unknown;
              error: unknown;
            };
          }
        }
        const id = args.p_hook_id as string,
          hash = args.p_payload_hash as string;
        let row = rows.get(id);
        if (name === "reserve_signed_otp_v3") {
          if (row && row.payload_hash !== hash) {
            return {
              data: null,
              error: new Error(privateText),
            };
          }
          if (!row) {
            quota++;
            row = {
              contract_version: 3,
              hook_id: id,
              payload_hash: hash,
              attempt_id: attempt,
              state: "reserved",
              revision: 1,
              can_send: true,
            };
            rows.set(id, row);
          }
          return { data: { ...row }, error: null };
        }
        if (!row) throw new Error("fixture absent row");
        if (name === "begin_signed_otp_v3") {
          const started = row.state === "reserved" &&
            row.revision === args.p_revision;
          if (started) {
            row.state = "sending";
            row.revision++;
            row.can_send = false;
          }
          return { data: { ...row, started }, error: null };
        }
        if (name === "record_signed_otp_v3") {
          row.state = args.p_outcome as OtpState;
          row.revision++;
          row.can_send = false;
          return { data: { ...row }, error: null };
        }
        throw new Error("unexpected fixture RPC");
      },
    }),
    fetch: async (url, init) => {
      sends++;
      return await provider(url, init);
    },
  };
  return {
    handler: createOtpHandler(deps),
    env,
    calls,
    rows,
    sends: () => sends,
    quota: () => quota,
    provider: (f: OtpDependencies["fetch"]) => provider = f,
    override: (f: typeof rpcOverride) => rpcOverride = f,
  };
}
async function assertError(response: Response, code: string, status = 503) {
  assertEquals(response.status, status);
  assertEquals(response.headers.get("cache-control"), "no-store");
  const text = await response.text();
  assertEquals(
    text,
    JSON.stringify({ error: { http_code: status, message: code } }),
  );
  for (
    const secret of [
      "SECRET_TOKEN",
      "+250788123456",
      "123456",
      "users_private",
      "SQL",
    ]
  ) {
    assertEquals(text.includes(secret), false);
  }
}
Deno.test("OTP signed acceptance is charged once and is never mislabeled delivered", async () => {
  const f = fixture();
  f.provider((url, init) => {
    assertEquals(url, "https://graph.facebook.com/v25.0/1234/messages");
    assertEquals(init.redirect, "error");
    assertEquals(init.signal instanceof AbortSignal, true);
    const message = JSON.parse(init.body as string);
    assertEquals(message.template.components[0].parameters[0].text, "123456");
    return Promise.resolve(
      new Response('{"messages":[{"id":"wamid.test-only"}]}'),
    );
  });
  assertEquals((await f.handler(await request())).status, 200);
  assertEquals((await f.handler(await request())).status, 200);
  assertEquals(f.sends(), 1);
  assertEquals(f.quota(), 1);
  assertEquals(f.rows.get("hook_signed_test")?.state, "accepted");
  const record = f.calls.find((c) => c.name === "record_signed_otp_v3")!;
  assertEquals(record.args.p_outcome, "accepted");
  assertEquals(
    record.args.p_provider_message_hash,
    await sha256Hex("wamid.test-only"),
  );
  assertEquals(JSON.stringify(record.args).includes("wamid.test-only"), false);
});
Deno.test("OTP simultaneous signed replay has one send claim and one quota charge", async () => {
  const f = fixture();
  let release!: () => void;
  const gate = new Promise<void>((resolve) => release = resolve);
  f.provider(async () => {
    await gate;
    return new Response('{"messages":[{"id":"wamid.one"}]}');
  });
  const responses = Promise.all(
    Array.from({ length: 8 }, async () => f.handler(await request())),
  );
  // Wait only for actual mocked provider invocation, never infer live progress.
  while (f.sends() === 0) {
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  release();
  const results = await responses;
  assertEquals(f.sends(), 1);
  assertEquals(f.quota(), 1);
  assertEquals(results.every((r) => [200, 503].includes(r.status)), true);
});
Deno.test("OTP changed signed body under same hook cannot send or consume another quota", async () => {
  const f = fixture();
  await f.handler(await request());
  await assertError(
    await f.handler(
      await request({
        body: JSON.stringify({
          user: { phone: "+250788123456" },
          sms: { otp: "987654" },
        }),
      }),
    ),
    "otp_reservation_unavailable",
  );
  assertEquals(f.sends(), 1);
  assertEquals(f.quota(), 1);
});
for (
  const [label, response] of [
    [
      "http error",
      () =>
        new Response('{"error":{"code":100,"message":"' + privateText + '"}}', {
          status: 400,
        }),
    ],
    [
      "quota error",
      () => new Response('{"error":{"code":130429}}', { status: 429 }),
    ],
    ["gateway error", () => new Response(privateText, { status: 502 })],
    ["empty ack", () => new Response("{}")],
    ["empty message id", () => new Response('{"messages":[{"id":""}]}')],
    [
      "multiple message ids",
      () => new Response('{"messages":[{"id":"one"},{"id":"two"}]}'),
    ],
    [
      "control in message id",
      () => new Response('{"messages":[{"id":"line\\nprivate"}]}'),
    ],
    ["nontext message id", () => new Response('{"messages":[{"id":123}]}')],
    ["invalid json", () => new Response(privateText)],
    ["oversized body", () => new Response("x".repeat(65537))],
  ] as const
) {
  Deno.test(
    "OTP " + label + " stays ambiguous without blind resend",
    async () => {
      const f = fixture();
      f.provider(() => Promise.resolve(response()));
      await assertError(
        await f.handler(await request()),
        "otp_delivery_unresolved",
      );
      await assertError(
        await f.handler(await request()),
        "otp_delivery_unresolved",
      );
      assertEquals(f.sends(), 1);
      assertEquals(f.quota(), 1);
      assertEquals(f.rows.get("hook_signed_test")?.state, "ambiguous");
      assertEquals(
        f.calls.find((c) => c.name === "record_signed_otp_v3")?.args
          .p_provider_message_hash,
        null,
      );
    },
  );
}
for (
  const exception of [
    new Error(privateText),
    new DOMException(privateText, "TimeoutError"),
    new PublicError(privateText, 400),
  ]
) {
  Deno.test("OTP transport exception redacted and charged", async () => {
    const f = fixture();
    f.provider(() => Promise.reject(exception));
    await assertError(
      await f.handler(await request()),
      "otp_delivery_unresolved",
    );
    await assertError(
      await f.handler(await request()),
      "otp_delivery_unresolved",
    );
    assertEquals(f.sends(), 1);
    assertEquals(f.quota(), 1);
  });
}
Deno.test("OTP accepted completion with lost ACK recovers from durable acceptance without resend", async () => {
  const f = fixture();
  f.override((name) => {
    if (name === "record_signed_otp_v3") {
      const row = f.rows.get("hook_signed_test")!;
      row.state = "accepted";
      row.revision++;
      row.can_send = false;
      return { data: null, error: new Error(privateText) };
    }
  });
  await assertError(
    await f.handler(await request()),
    "otp_delivery_unresolved",
  );
  assertEquals((await f.handler(await request())).status, 200);
  assertEquals(f.sends(), 1);
  assertEquals(f.quota(), 1);
});
Deno.test("OTP provider accepted but completion absent remains unresolved until explicit evidence recovery", async () => {
  const f = fixture();
  f.override((name) =>
    name === "record_signed_otp_v3"
      ? { data: null, error: new Error(privateText) }
      : undefined
  );
  await assertError(
    await f.handler(await request()),
    "otp_delivery_unresolved",
  );
  await assertError(
    await f.handler(await request()),
    "otp_delivery_unresolved",
  );
  assertEquals(f.sends(), 1);
  const row = f.rows.get("hook_signed_test")!;
  row.state = "delivered";
  row.revision++;
  row.can_send = false;
  // Simulates independently verified recovery, not a handler-created delivery.
  assertEquals((await f.handler(await request())).status, 200);
  assertEquals(f.sends(), 1);
});
Deno.test("OTP lost begin ACK cannot launch a provider send on replay", async () => {
  const f = fixture();
  f.override((name) => {
    if (name === "begin_signed_otp_v3") {
      const row = f.rows.get("hook_signed_test")!;
      row.state = "sending";
      row.revision++;
      row.can_send = false;
      return { data: null, error: new Error(privateText) };
    }
  });
  await assertError(
    await f.handler(await request()),
    "otp_delivery_unresolved",
  );
  await assertError(
    await f.handler(await request()),
    "otp_delivery_unresolved",
  );
  assertEquals(f.sends(), 0);
  assertEquals(f.quota(), 1);
});
for (
  const state of [
    "sending",
    "ambiguous",
    "not_sent",
    "failed",
    "expired",
    "accepted",
    "delivered",
  ] as const
) {
  Deno.test(
    "OTP durable " + state + " read cannot launch another send",
    async () => {
      const f = fixture();
      f.override((name, args) =>
        name === "reserve_signed_otp_v3"
          ? {
            error: null,
            data: {
              contract_version: 3,
              hook_id: args.p_hook_id,
              payload_hash: args.p_payload_hash,
              attempt_id: attempt,
              state,
              revision: 8,
              can_send: false,
            },
          }
          : undefined
      );
      const response = await f.handler(await request());
      if (state === "accepted" || state === "delivered") {
        assertEquals(response.status, 200);
      } else {await assertError(
          response,
          state === "not_sent"
            ? "otp_not_sent"
            : state === "failed"
            ? "otp_delivery_failed"
            : state === "expired"
            ? "otp_expired"
            : "otp_delivery_unresolved",
          ["not_sent", "failed", "expired"].includes(state) ? 502 : 503,
        );}
      assertEquals(f.sends(), 0);
    },
  );
}
for (
  const mutation of [
    { contract_version: 2 },
    { payload_hash: "a".repeat(64) },
    { hook_id: "wrong" },
    { attempt_id: "broken" },
    { state: "unexpected" },
    { revision: 0 },
    { revision: "1" },
    { can_send: "true" },
    { state: "accepted", can_send: true },
  ]
) {
  Deno.test(
    "OTP malformed durable receipt blocks before sending: " +
      JSON.stringify(mutation),
    async () => {
      const f = fixture();
      f.override((name, args) =>
        name === "reserve_signed_otp_v3"
          ? {
            error: null,
            data: {
              contract_version: 3,
              hook_id: args.p_hook_id,
              payload_hash: args.p_payload_hash,
              attempt_id: attempt,
              state: "reserved",
              revision: 1,
              can_send: true,
              ...mutation,
            },
          }
          : undefined
      );
      await assertError(
        await f.handler(await request()),
        "otp_delivery_unresolved",
      );
      assertEquals(f.sends(), 0);
    },
  );
}
Deno.test("OTP throttling sends nothing", async () => {
  const f = fixture();
  f.override(() => ({ data: "throttled", error: null }));
  await assertError(await f.handler(await request()), "otp_rate_limited", 429);
  assertEquals(f.sends(), 0);
});
for (const name of Object.keys(baseEnv)) {
  Deno.test(
    "OTP missing configuration consumes no quota: " + name,
    async () => {
      const f = fixture();
      delete f.env[name];
      await assertError(
        await f.handler(await request()),
        "otp_configuration_unavailable",
      );
      assertEquals(f.quota(), 0);
      assertEquals(f.sends(), 0);
    },
  );
}
Deno.test("OTP stale signed hook cannot reserve or send", async () => {
  const f = fixture();
  await assertError(
    await f.handler(await request({ time: now / 1000 - 301 })),
    "invalid_hook_signature",
    401,
  );
  assertEquals(f.quota(), 0);
  assertEquals(f.sends(), 0);
});
Deno.test("OTP key rotation validates previous secret and does not accept an unrelated secret", async () => {
  const f = fixture();
  const other = btoa(String.fromCharCode(...new Uint8Array(32).fill(9)));
  f.env.SEND_SMS_HOOK_SECRET = "whsec_" + other;
  f.env.SEND_SMS_HOOK_PREVIOUS_SECRET = "whsec_" + secret;
  assertEquals((await f.handler(await request())).status, 200);
  delete f.env.SEND_SMS_HOOK_PREVIOUS_SECRET;
  await assertError(
    await f.handler(await request()),
    "invalid_hook_signature",
    401,
  );
  assertEquals(f.sends(), 1);
});
Deno.test("OTP malformed phone and OTP cannot reserve or send", async () => {
  for (
    const body of [
      { user: { phone: "+250788123456 SQL" }, sms: { otp: "123456" } },
      { user: { phone: "+250788123456" }, sms: { otp: 123456 } },
      { user: { phone: "+250788123456" }, sms: { otp: "123" } },
    ]
  ) {
    const f = fixture();
    await assertError(
      await f.handler(await request({ body: JSON.stringify(body) })),
      "invalid_otp_payload",
      400,
    );
    assertEquals(f.quota(), 0);
    assertEquals(f.sends(), 0);
  }
});
Deno.test("OTP unknown dependency errors and forged PublicError codes never disclose data", async () => {
  for (
    const error of [new Error(privateText), new PublicError(privateText, 400)]
  ) {
    const f = fixture();
    f.override(() => {
      throw error;
    });
    await assertError(await f.handler(await request()), "service_unavailable");
    assertEquals(f.sends(), 0);
  }
});
Deno.test("OTP late completion from another attempt cannot acknowledge success", async () => {
  const f = fixture();
  f.override((name, args) =>
    name === "record_signed_otp_v3"
      ? {
        data: {
          contract_version: 3,
          hook_id: args.p_hook_id,
          payload_hash: args.p_payload_hash,
          attempt_id: "22222222-2222-4222-8222-222222222222",
          state: "accepted",
          revision: 3,
          can_send: false,
        },
        error: null,
      }
      : undefined
  );
  await assertError(
    await f.handler(await request()),
    "otp_delivery_unresolved",
  );
  assertEquals(f.sends(), 1);
});
Deno.test("OTP GET and OPTIONS do not consume quota", async () => {
  const f = fixture();
  assertEquals((await f.handler(new Request("https://edge.test"))).status, 405);
  assertEquals(
    (await f.handler(new Request("https://edge.test", { method: "OPTIONS" })))
      .status,
    200,
  );
  assertEquals(f.quota(), 0);
  assertEquals(f.sends(), 0);
});

Deno.test("OTP never-resolving provider obeys deadline, records ambiguity and never resends", async () => {
  const f = fixture({ totalMs: 200, providerMs: 10 });
  f.provider(() => new Promise(() => {}));
  const started = performance.now();
  await assertError(
    await f.handler(await request()),
    "otp_delivery_unresolved",
  );
  assertEquals(performance.now() - started < 1000, true);
  assertEquals(f.rows.get("hook_signed_test")?.state, "ambiguous");
  await assertError(
    await f.handler(await request()),
    "otp_delivery_unresolved",
  );
  assertEquals(f.sends(), 1);
  assertEquals(f.quota(), 1);
});
Deno.test("OTP never-resolving reservation obeys total hook deadline and sends nothing", async () => {
  const f = fixture({ totalMs: 20, providerMs: 10 });
  f.override((name) =>
    name === "reserve_signed_otp_v3" ? new Promise(() => {}) : undefined
  );
  const started = performance.now();
  await assertError(
    await f.handler(await request()),
    "otp_delivery_unresolved",
  );
  assertEquals(performance.now() - started < 1000, true);
  assertEquals(f.sends(), 0);
});
Deno.test("OTP accepted send with stalled completion returns unresolved within hook deadline", async () => {
  const f = fixture({ totalMs: 30, providerMs: 10 });
  f.override((name) =>
    name === "record_signed_otp_v3" ? new Promise(() => {}) : undefined
  );
  await assertError(
    await f.handler(await request()),
    "otp_delivery_unresolved",
  );
  await assertError(
    await f.handler(await request()),
    "otp_delivery_unresolved",
  );
  assertEquals(f.sends(), 1);
  assertEquals(f.quota(), 1);
});
Deno.test("OTP stalled provider response body times out as ambiguity without leaking or resending", async () => {
  const f = fixture({ totalMs: 200, providerMs: 10 });
  let stream!: ReadableStreamDefaultController<Uint8Array>;
  f.provider(() =>
    Promise.resolve(
      new Response(
        new ReadableStream({
          start(c) {
            stream = c;
          },
        }),
      ),
    )
  );
  try {
    await assertError(
      await f.handler(await request()),
      "otp_delivery_unresolved",
    );
    await assertError(
      await f.handler(await request()),
      "otp_delivery_unresolved",
    );
    assertEquals(f.sends(), 1);
    assertEquals(f.rows.get("hook_signed_test")?.state, "ambiguous");
  } finally {
    stream.close();
  }
});

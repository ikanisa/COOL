import { assertEquals } from "../_shared/test_assert.ts";
import { PublicError } from "../_shared/production_contract.ts";
import { sha256Hex } from "../_shared/hash.ts";
import { createOtpHandler } from "./handler.ts";
const now = Date.parse("2026-09-30T12:00:00Z");
const secret = btoa(String.fromCharCode(...new Uint8Array(32).fill(7)));
const attempt = "11111111-1111-4111-8111-111111111111";
const privateText = "Bearer SECRET_TOKEN SQL users_private +250788123456 OTP 123456";
const baseEnv = {
  SEND_SMS_HOOK_SECRET: "v1,whsec_" + secret,
  WHATSAPP_GRAPH_API_VERSION: "v25.0",
  WHATSAPP_PHONE_NUMBER_ID: "1234",
  WHATSAPP_CLOUD_OTP_AUTH_BUTTON: "true",
  WHATSAPP_CLOUD_API_TOKEN: "SECRET_TOKEN",
  WHATSAPP_AUTH_TEMPLATE_NAME: "collect_otp",
  WHATSAPP_AUTH_TEMPLATE_LANGUAGE: "en_US"
};
async function request(options = {}) {
  const id = options.id ?? "hook_signed_test";
  const body = options.body ?? JSON.stringify({
    user: {
      phone: "+250788123456"
    },
    sms: {
      otp: "123456"
    }
  });
  const time = options.time ?? now / 1000;
  const key = await crypto.subtle.importKey("raw", Uint8Array.from(atob(options.key ?? secret), (c)=>c.charCodeAt(0)), {
    name: "HMAC",
    hash: "SHA-256"
  }, false, [
    "sign"
  ]);
  const signature = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${id}.${time}.${body}`)))));
  return new Request("https://edge.test/otp", {
    method: "POST",
    headers: {
      "webhook-id": id,
      "webhook-timestamp": String(time),
      "webhook-signature": "v1," + signature
    },
    body
  });
}
function fixture(budgets) {
  const env = {
    ...baseEnv
  };
  const calls = [];
  const rows = new Map();
  let sends = 0, quota = 0;
  let provider = ()=>Promise.resolve(new Response('{"messages":[{"id":"wamid.test-only"}]}'));
  let rpcOverride = null;
  const deps = {
    budgets,
    env: (name)=>env[name],
    now: ()=>now,
    service: ()=>({
        rpc: async (name, args)=>{
          calls.push({
            name,
            args
          });
          if (rpcOverride) {
            const result = await rpcOverride(name, args);
            if (result !== undefined) {
              return result;
            }
          }
          const id = args.p_hook_id, hash = args.p_payload_hash;
          let row = rows.get(id);
          if (name === "reserve_signed_otp_v3") {
            if (row && row.payload_hash !== hash) {
              return {
                data: null,
                error: new Error(privateText)
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
                can_send: true
              };
              rows.set(id, row);
            }
            return {
              data: {
                ...row
              },
              error: null
            };
          }
          if (!row) throw new Error("fixture absent row");
          if (name === "begin_signed_otp_v3") {
            const started = row.state === "reserved" && row.revision === args.p_revision;
            if (started) {
              row.state = "sending";
              row.revision++;
              row.can_send = false;
            }
            return {
              data: {
                ...row,
                started
              },
              error: null
            };
          }
          if (name === "record_signed_otp_v3") {
            row.state = args.p_outcome;
            row.revision++;
            row.can_send = false;
            return {
              data: {
                ...row
              },
              error: null
            };
          }
          throw new Error("unexpected fixture RPC");
        }
      }),
    fetch: async (url, init)=>{
      sends++;
      return await provider(url, init);
    }
  };
  return {
    handler: createOtpHandler(deps),
    env,
    calls,
    rows,
    sends: ()=>sends,
    quota: ()=>quota,
    provider: (f)=>provider = f,
    override: (f)=>rpcOverride = f
  };
}
async function assertError(response, code, status = 503) {
  assertEquals(response.status, status);
  assertEquals(response.headers.get("cache-control"), "no-store");
  const text = await response.text();
  assertEquals(text, JSON.stringify({
    error: {
      http_code: status,
      message: code
    }
  }));
  for (const secret of [
    "SECRET_TOKEN",
    "+250788123456",
    "123456",
    "users_private",
    "SQL"
  ]){
    assertEquals(text.includes(secret), false);
  }
}
Deno.test("OTP signed acceptance is charged once and is never mislabeled delivered", async ()=>{
  const f = fixture();
  f.provider((url, init)=>{
    assertEquals(url, "https://graph.facebook.com/v25.0/1234/messages");
    assertEquals(init.redirect, "error");
    assertEquals(init.signal instanceof AbortSignal, true);
    const message = JSON.parse(init.body);
    assertEquals(message.template.components[0].parameters[0].text, "123456");
    return Promise.resolve(new Response('{"messages":[{"id":"wamid.test-only"}]}'));
  });
  assertEquals((await f.handler(await request())).status, 200);
  assertEquals((await f.handler(await request())).status, 200);
  assertEquals(f.sends(), 1);
  assertEquals(f.quota(), 1);
  assertEquals(f.rows.get("hook_signed_test")?.state, "accepted");
  const record = f.calls.find((c)=>c.name === "record_signed_otp_v3");
  assertEquals(record.args.p_outcome, "accepted");
  assertEquals(record.args.p_provider_message_hash, await sha256Hex("wamid.test-only"));
  assertEquals(JSON.stringify(record.args).includes("wamid.test-only"), false);
});
Deno.test("OTP simultaneous signed replay has one send claim and one quota charge", async ()=>{
  const f = fixture();
  let release;
  const gate = new Promise((resolve)=>release = resolve);
  f.provider(async ()=>{
    await gate;
    return new Response('{"messages":[{"id":"wamid.one"}]}');
  });
  const responses = Promise.all(Array.from({
    length: 8
  }, async ()=>f.handler(await request())));
  // Wait only for actual mocked provider invocation, never infer live progress.
  while(f.sends() === 0){
    await new Promise((resolve)=>setTimeout(resolve, 0));
  }
  release();
  const results = await responses;
  assertEquals(f.sends(), 1);
  assertEquals(f.quota(), 1);
  assertEquals(results.every((r)=>[
      200,
      503
    ].includes(r.status)), true);
});
Deno.test("OTP changed signed body under same hook cannot send or consume another quota", async ()=>{
  const f = fixture();
  await f.handler(await request());
  await assertError(await f.handler(await request({
    body: JSON.stringify({
      user: {
        phone: "+250788123456"
      },
      sms: {
        otp: "987654"
      }
    })
  })), "otp_reservation_unavailable");
  assertEquals(f.sends(), 1);
  assertEquals(f.quota(), 1);
});
for (const [label, response] of [
  [
    "http error",
    ()=>new Response('{"error":{"code":100,"message":"' + privateText + '"}}', {
        status: 400
      })
  ],
  [
    "quota error",
    ()=>new Response('{"error":{"code":130429}}', {
        status: 429
      })
  ],
  [
    "gateway error",
    ()=>new Response(privateText, {
        status: 502
      })
  ],
  [
    "empty ack",
    ()=>new Response("{}")
  ],
  [
    "empty message id",
    ()=>new Response('{"messages":[{"id":""}]}')
  ],
  [
    "multiple message ids",
    ()=>new Response('{"messages":[{"id":"one"},{"id":"two"}]}')
  ],
  [
    "control in message id",
    ()=>new Response('{"messages":[{"id":"line\\nprivate"}]}')
  ],
  [
    "nontext message id",
    ()=>new Response('{"messages":[{"id":123}]}')
  ],
  [
    "invalid json",
    ()=>new Response(privateText)
  ],
  [
    "oversized body",
    ()=>new Response("x".repeat(65537))
  ]
]){
  Deno.test("OTP " + label + " stays ambiguous without blind resend", async ()=>{
    const f = fixture();
    f.provider(()=>Promise.resolve(response()));
    await assertError(await f.handler(await request()), "otp_delivery_unresolved");
    await assertError(await f.handler(await request()), "otp_delivery_unresolved");
    assertEquals(f.sends(), 1);
    assertEquals(f.quota(), 1);
    assertEquals(f.rows.get("hook_signed_test")?.state, "ambiguous");
    assertEquals(f.calls.find((c)=>c.name === "record_signed_otp_v3")?.args.p_provider_message_hash, null);
  });
}
for (const exception of [
  new Error(privateText),
  new DOMException(privateText, "TimeoutError"),
  new PublicError(privateText, 400)
]){
  Deno.test("OTP transport exception redacted and charged", async ()=>{
    const f = fixture();
    f.provider(()=>Promise.reject(exception));
    await assertError(await f.handler(await request()), "otp_delivery_unresolved");
    await assertError(await f.handler(await request()), "otp_delivery_unresolved");
    assertEquals(f.sends(), 1);
    assertEquals(f.quota(), 1);
  });
}
Deno.test("OTP accepted completion with lost ACK recovers from durable acceptance without resend", async ()=>{
  const f = fixture();
  f.override((name)=>{
    if (name === "record_signed_otp_v3") {
      const row = f.rows.get("hook_signed_test");
      row.state = "accepted";
      row.revision++;
      row.can_send = false;
      return {
        data: null,
        error: new Error(privateText)
      };
    }
  });
  await assertError(await f.handler(await request()), "otp_delivery_unresolved");
  assertEquals((await f.handler(await request())).status, 200);
  assertEquals(f.sends(), 1);
  assertEquals(f.quota(), 1);
});
Deno.test("OTP provider accepted but completion absent remains unresolved until explicit evidence recovery", async ()=>{
  const f = fixture();
  f.override((name)=>name === "record_signed_otp_v3" ? {
      data: null,
      error: new Error(privateText)
    } : undefined);
  await assertError(await f.handler(await request()), "otp_delivery_unresolved");
  await assertError(await f.handler(await request()), "otp_delivery_unresolved");
  assertEquals(f.sends(), 1);
  const row = f.rows.get("hook_signed_test");
  row.state = "delivered";
  row.revision++;
  row.can_send = false;
  // Simulates independently verified recovery, not a handler-created delivery.
  assertEquals((await f.handler(await request())).status, 200);
  assertEquals(f.sends(), 1);
});
Deno.test("OTP lost begin ACK cannot launch a provider send on replay", async ()=>{
  const f = fixture();
  f.override((name)=>{
    if (name === "begin_signed_otp_v3") {
      const row = f.rows.get("hook_signed_test");
      row.state = "sending";
      row.revision++;
      row.can_send = false;
      return {
        data: null,
        error: new Error(privateText)
      };
    }
  });
  await assertError(await f.handler(await request()), "otp_delivery_unresolved");
  await assertError(await f.handler(await request()), "otp_delivery_unresolved");
  assertEquals(f.sends(), 0);
  assertEquals(f.quota(), 1);
});
for (const state of [
  "sending",
  "ambiguous",
  "not_sent",
  "failed",
  "expired",
  "accepted",
  "delivered"
]){
  Deno.test("OTP durable " + state + " read cannot launch another send", async ()=>{
    const f = fixture();
    f.override((name, args)=>name === "reserve_signed_otp_v3" ? {
        error: null,
        data: {
          contract_version: 3,
          hook_id: args.p_hook_id,
          payload_hash: args.p_payload_hash,
          attempt_id: attempt,
          state,
          revision: 8,
          can_send: false
        }
      } : undefined);
    const response = await f.handler(await request());
    if (state === "accepted" || state === "delivered") {
      assertEquals(response.status, 200);
    } else {
      await assertError(response, state === "not_sent" ? "otp_not_sent" : state === "failed" ? "otp_delivery_failed" : state === "expired" ? "otp_expired" : "otp_delivery_unresolved", [
        "not_sent",
        "failed",
        "expired"
      ].includes(state) ? 502 : 503);
    }
    assertEquals(f.sends(), 0);
  });
}
for (const mutation of [
  {
    contract_version: 2
  },
  {
    payload_hash: "a".repeat(64)
  },
  {
    hook_id: "wrong"
  },
  {
    attempt_id: "broken"
  },
  {
    state: "unexpected"
  },
  {
    revision: 0
  },
  {
    revision: "1"
  },
  {
    can_send: "true"
  },
  {
    state: "accepted",
    can_send: true
  }
]){
  Deno.test("OTP malformed durable receipt blocks before sending: " + JSON.stringify(mutation), async ()=>{
    const f = fixture();
    f.override((name, args)=>name === "reserve_signed_otp_v3" ? {
        error: null,
        data: {
          contract_version: 3,
          hook_id: args.p_hook_id,
          payload_hash: args.p_payload_hash,
          attempt_id: attempt,
          state: "reserved",
          revision: 1,
          can_send: true,
          ...mutation
        }
      } : undefined);
    await assertError(await f.handler(await request()), "otp_delivery_unresolved");
    assertEquals(f.sends(), 0);
  });
}
Deno.test("OTP throttling sends nothing", async ()=>{
  const f = fixture();
  f.override(()=>({
      data: "throttled",
      error: null
    }));
  await assertError(await f.handler(await request()), "otp_rate_limited", 429);
  assertEquals(f.sends(), 0);
});
for (const name of Object.keys(baseEnv)){
  Deno.test("OTP missing configuration consumes no quota: " + name, async ()=>{
    const f = fixture();
    delete f.env[name];
    await assertError(await f.handler(await request()), "otp_configuration_unavailable");
    assertEquals(f.quota(), 0);
    assertEquals(f.sends(), 0);
  });
}
Deno.test("OTP stale signed hook cannot reserve or send", async ()=>{
  const f = fixture();
  await assertError(await f.handler(await request({
    time: now / 1000 - 301
  })), "invalid_hook_signature", 401);
  assertEquals(f.quota(), 0);
  assertEquals(f.sends(), 0);
});
Deno.test("OTP key rotation validates previous secret and does not accept an unrelated secret", async ()=>{
  const f = fixture();
  const other = btoa(String.fromCharCode(...new Uint8Array(32).fill(9)));
  f.env.SEND_SMS_HOOK_SECRET = "whsec_" + other;
  f.env.SEND_SMS_HOOK_PREVIOUS_SECRET = "whsec_" + secret;
  assertEquals((await f.handler(await request())).status, 200);
  delete f.env.SEND_SMS_HOOK_PREVIOUS_SECRET;
  await assertError(await f.handler(await request()), "invalid_hook_signature", 401);
  assertEquals(f.sends(), 1);
});
Deno.test("OTP malformed phone and OTP cannot reserve or send", async ()=>{
  for (const body of [
    {
      user: {
        phone: "+250788123456 SQL"
      },
      sms: {
        otp: "123456"
      }
    },
    {
      user: {
        phone: "+250788123456"
      },
      sms: {
        otp: 123456
      }
    },
    {
      user: {
        phone: "+250788123456"
      },
      sms: {
        otp: "123"
      }
    }
  ]){
    const f = fixture();
    await assertError(await f.handler(await request({
      body: JSON.stringify(body)
    })), "invalid_otp_payload", 400);
    assertEquals(f.quota(), 0);
    assertEquals(f.sends(), 0);
  }
});
Deno.test("OTP unknown dependency errors and forged PublicError codes never disclose data", async ()=>{
  for (const error of [
    new Error(privateText),
    new PublicError(privateText, 400)
  ]){
    const f = fixture();
    f.override(()=>{
      throw error;
    });
    await assertError(await f.handler(await request()), "service_unavailable");
    assertEquals(f.sends(), 0);
  }
});
Deno.test("OTP late completion from another attempt cannot acknowledge success", async ()=>{
  const f = fixture();
  f.override((name, args)=>name === "record_signed_otp_v3" ? {
      data: {
        contract_version: 3,
        hook_id: args.p_hook_id,
        payload_hash: args.p_payload_hash,
        attempt_id: "22222222-2222-4222-8222-222222222222",
        state: "accepted",
        revision: 3,
        can_send: false
      },
      error: null
    } : undefined);
  await assertError(await f.handler(await request()), "otp_delivery_unresolved");
  assertEquals(f.sends(), 1);
});
Deno.test("OTP GET and OPTIONS do not consume quota", async ()=>{
  const f = fixture();
  assertEquals((await f.handler(new Request("https://edge.test"))).status, 405);
  assertEquals((await f.handler(new Request("https://edge.test", {
    method: "OPTIONS"
  }))).status, 200);
  assertEquals(f.quota(), 0);
  assertEquals(f.sends(), 0);
});
Deno.test("OTP never-resolving provider obeys deadline, records ambiguity and never resends", async ()=>{
  const f = fixture({
    totalMs: 200,
    providerMs: 10
  });
  f.provider(()=>new Promise(()=>{}));
  const started = performance.now();
  await assertError(await f.handler(await request()), "otp_delivery_unresolved");
  assertEquals(performance.now() - started < 1000, true);
  assertEquals(f.rows.get("hook_signed_test")?.state, "ambiguous");
  await assertError(await f.handler(await request()), "otp_delivery_unresolved");
  assertEquals(f.sends(), 1);
  assertEquals(f.quota(), 1);
});
Deno.test("OTP never-resolving reservation obeys total hook deadline and sends nothing", async ()=>{
  const f = fixture({
    totalMs: 20,
    providerMs: 10
  });
  f.override((name)=>name === "reserve_signed_otp_v3" ? new Promise(()=>{}) : undefined);
  const started = performance.now();
  await assertError(await f.handler(await request()), "otp_delivery_unresolved");
  assertEquals(performance.now() - started < 1000, true);
  assertEquals(f.sends(), 0);
});
Deno.test("OTP accepted send with stalled completion returns unresolved within hook deadline", async ()=>{
  const f = fixture({
    totalMs: 30,
    providerMs: 10
  });
  f.override((name)=>name === "record_signed_otp_v3" ? new Promise(()=>{}) : undefined);
  await assertError(await f.handler(await request()), "otp_delivery_unresolved");
  await assertError(await f.handler(await request()), "otp_delivery_unresolved");
  assertEquals(f.sends(), 1);
  assertEquals(f.quota(), 1);
});
Deno.test("OTP stalled provider response body times out as ambiguity without leaking or resending", async ()=>{
  const f = fixture({
    totalMs: 200,
    providerMs: 10
  });
  let stream;
  f.provider(()=>Promise.resolve(new Response(new ReadableStream({
      start (c) {
        stream = c;
      }
    }))));
  try {
    await assertError(await f.handler(await request()), "otp_delivery_unresolved");
    await assertError(await f.handler(await request()), "otp_delivery_unresolved");
    assertEquals(f.sends(), 1);
    assertEquals(f.rows.get("hook_signed_test")?.state, "ambiguous");
  } finally{
    stream.close();
  }
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2F1dGgtc2VuZC13aGF0c2FwcC1vdHAvaGFuZGxlcl90ZXN0LnRzIl0sInNvdXJjZXNDb250ZW50IjpbImltcG9ydCB7IGFzc2VydEVxdWFscyB9IGZyb20gXCIuLi9fc2hhcmVkL3Rlc3RfYXNzZXJ0LnRzXCI7XG5pbXBvcnQgeyBQdWJsaWNFcnJvciB9IGZyb20gXCIuLi9fc2hhcmVkL3Byb2R1Y3Rpb25fY29udHJhY3QudHNcIjtcbmltcG9ydCB7IHNoYTI1NkhleCB9IGZyb20gXCIuLi9fc2hhcmVkL2hhc2gudHNcIjtcbmltcG9ydCB7XG4gIGNyZWF0ZU90cEhhbmRsZXIsXG4gIHR5cGUgT3RwRGVwZW5kZW5jaWVzLFxuICB0eXBlIE90cFJlY2VpcHQsXG4gIHR5cGUgT3RwU3RhdGUsXG59IGZyb20gXCIuL2hhbmRsZXIudHNcIjtcblxuY29uc3Qgbm93ID0gRGF0ZS5wYXJzZShcIjIwMjYtMDktMzBUMTI6MDA6MDBaXCIpO1xuY29uc3Qgc2VjcmV0ID0gYnRvYShTdHJpbmcuZnJvbUNoYXJDb2RlKC4uLm5ldyBVaW50OEFycmF5KDMyKS5maWxsKDcpKSk7XG5jb25zdCBhdHRlbXB0ID0gXCIxMTExMTExMS0xMTExLTQxMTEtODExMS0xMTExMTExMTExMTFcIjtcbmNvbnN0IHByaXZhdGVUZXh0ID1cbiAgXCJCZWFyZXIgU0VDUkVUX1RPS0VOIFNRTCB1c2Vyc19wcml2YXRlICsyNTA3ODgxMjM0NTYgT1RQIDEyMzQ1NlwiO1xuY29uc3QgYmFzZUVudjogUmVjb3JkPHN0cmluZywgc3RyaW5nPiA9IHtcbiAgU0VORF9TTVNfSE9PS19TRUNSRVQ6IFwidjEsd2hzZWNfXCIgKyBzZWNyZXQsXG4gIFdIQVRTQVBQX0dSQVBIX0FQSV9WRVJTSU9OOiBcInYyNS4wXCIsXG4gIFdIQVRTQVBQX1BIT05FX05VTUJFUl9JRDogXCIxMjM0XCIsXG4gIFdIQVRTQVBQX0NMT1VEX09UUF9BVVRIX0JVVFRPTjogXCJ0cnVlXCIsXG4gIFdIQVRTQVBQX0NMT1VEX0FQSV9UT0tFTjogXCJTRUNSRVRfVE9LRU5cIixcbiAgV0hBVFNBUFBfQVVUSF9URU1QTEFURV9OQU1FOiBcImNvbGxlY3Rfb3RwXCIsXG4gIFdIQVRTQVBQX0FVVEhfVEVNUExBVEVfTEFOR1VBR0U6IFwiZW5fVVNcIixcbn07XG5hc3luYyBmdW5jdGlvbiByZXF1ZXN0KFxuICBvcHRpb25zOiB7IGlkPzogc3RyaW5nOyBib2R5Pzogc3RyaW5nOyB0aW1lPzogbnVtYmVyOyBrZXk/OiBzdHJpbmcgfSA9IHt9LFxuKSB7XG4gIGNvbnN0IGlkID0gb3B0aW9ucy5pZCA/PyBcImhvb2tfc2lnbmVkX3Rlc3RcIjtcbiAgY29uc3QgYm9keSA9IG9wdGlvbnMuYm9keSA/P1xuICAgIEpTT04uc3RyaW5naWZ5KHtcbiAgICAgIHVzZXI6IHsgcGhvbmU6IFwiKzI1MDc4ODEyMzQ1NlwiIH0sXG4gICAgICBzbXM6IHsgb3RwOiBcIjEyMzQ1NlwiIH0sXG4gICAgfSk7XG4gIGNvbnN0IHRpbWUgPSBvcHRpb25zLnRpbWUgPz8gbm93IC8gMTAwMDtcbiAgY29uc3Qga2V5ID0gYXdhaXQgY3J5cHRvLnN1YnRsZS5pbXBvcnRLZXkoXG4gICAgXCJyYXdcIixcbiAgICBVaW50OEFycmF5LmZyb20oYXRvYihvcHRpb25zLmtleSA/PyBzZWNyZXQpLCAoYykgPT4gYy5jaGFyQ29kZUF0KDApKSxcbiAgICB7IG5hbWU6IFwiSE1BQ1wiLCBoYXNoOiBcIlNIQS0yNTZcIiB9LFxuICAgIGZhbHNlLFxuICAgIFtcInNpZ25cIl0sXG4gICk7XG4gIGNvbnN0IHNpZ25hdHVyZSA9IGJ0b2EoXG4gICAgU3RyaW5nLmZyb21DaGFyQ29kZShcbiAgICAgIC4uLm5ldyBVaW50OEFycmF5KFxuICAgICAgICBhd2FpdCBjcnlwdG8uc3VidGxlLnNpZ24oXG4gICAgICAgICAgXCJITUFDXCIsXG4gICAgICAgICAga2V5LFxuICAgICAgICAgIG5ldyBUZXh0RW5jb2RlcigpLmVuY29kZShgJHtpZH0uJHt0aW1lfS4ke2JvZHl9YCksXG4gICAgICAgICksXG4gICAgICApLFxuICAgICksXG4gICk7XG4gIHJldHVybiBuZXcgUmVxdWVzdChcImh0dHBzOi8vZWRnZS50ZXN0L290cFwiLCB7XG4gICAgbWV0aG9kOiBcIlBPU1RcIixcbiAgICBoZWFkZXJzOiB7XG4gICAgICBcIndlYmhvb2staWRcIjogaWQsXG4gICAgICBcIndlYmhvb2stdGltZXN0YW1wXCI6IFN0cmluZyh0aW1lKSxcbiAgICAgIFwid2ViaG9vay1zaWduYXR1cmVcIjogXCJ2MSxcIiArIHNpZ25hdHVyZSxcbiAgICB9LFxuICAgIGJvZHksXG4gIH0pO1xufVxuZnVuY3Rpb24gZml4dHVyZShidWRnZXRzPzogeyB0b3RhbE1zOiBudW1iZXI7IHByb3ZpZGVyTXM6IG51bWJlciB9KSB7XG4gIGNvbnN0IGVudiA9IHsgLi4uYmFzZUVudiB9O1xuICBjb25zdCBjYWxsczogQXJyYXk8eyBuYW1lOiBzdHJpbmc7IGFyZ3M6IFJlY29yZDxzdHJpbmcsIHVua25vd24+IH0+ID0gW107XG4gIGNvbnN0IHJvd3MgPSBuZXcgTWFwPHN0cmluZywgT3RwUmVjZWlwdD4oKTtcbiAgbGV0IHNlbmRzID0gMCwgcXVvdGEgPSAwO1xuICBsZXQgcHJvdmlkZXI6IE90cERlcGVuZGVuY2llc1tcImZldGNoXCJdID0gKCkgPT5cbiAgICBQcm9taXNlLnJlc29sdmUobmV3IFJlc3BvbnNlKCd7XCJtZXNzYWdlc1wiOlt7XCJpZFwiOlwid2FtaWQudGVzdC1vbmx5XCJ9XX0nKSk7XG4gIGxldCBycGNPdmVycmlkZTpcbiAgICB8ICgobmFtZTogc3RyaW5nLCBhcmdzOiBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPikgPT4gdW5rbm93bilcbiAgICB8IG51bGwgPSBudWxsO1xuICBjb25zdCBkZXBzOiBPdHBEZXBlbmRlbmNpZXMgPSB7XG4gICAgYnVkZ2V0cyxcbiAgICBlbnY6IChuYW1lKSA9PiBlbnZbbmFtZV0sXG4gICAgbm93OiAoKSA9PiBub3csXG4gICAgc2VydmljZTogKCkgPT4gKHtcbiAgICAgIHJwYzogYXN5bmMgKG5hbWUsIGFyZ3MpID0+IHtcbiAgICAgICAgY2FsbHMucHVzaCh7IG5hbWUsIGFyZ3MgfSk7XG4gICAgICAgIGlmIChycGNPdmVycmlkZSkge1xuICAgICAgICAgIGNvbnN0IHJlc3VsdCA9IGF3YWl0IHJwY092ZXJyaWRlKG5hbWUsIGFyZ3MpO1xuICAgICAgICAgIGlmIChyZXN1bHQgIT09IHVuZGVmaW5lZCkge1xuICAgICAgICAgICAgcmV0dXJuIHJlc3VsdCBhcyB7XG4gICAgICAgICAgICAgIGRhdGE6IHVua25vd247XG4gICAgICAgICAgICAgIGVycm9yOiB1bmtub3duO1xuICAgICAgICAgICAgfTtcbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgICAgY29uc3QgaWQgPSBhcmdzLnBfaG9va19pZCBhcyBzdHJpbmcsXG4gICAgICAgICAgaGFzaCA9IGFyZ3MucF9wYXlsb2FkX2hhc2ggYXMgc3RyaW5nO1xuICAgICAgICBsZXQgcm93ID0gcm93cy5nZXQoaWQpO1xuICAgICAgICBpZiAobmFtZSA9PT0gXCJyZXNlcnZlX3NpZ25lZF9vdHBfdjNcIikge1xuICAgICAgICAgIGlmIChyb3cgJiYgcm93LnBheWxvYWRfaGFzaCAhPT0gaGFzaCkge1xuICAgICAgICAgICAgcmV0dXJuIHtcbiAgICAgICAgICAgICAgZGF0YTogbnVsbCxcbiAgICAgICAgICAgICAgZXJyb3I6IG5ldyBFcnJvcihwcml2YXRlVGV4dCksXG4gICAgICAgICAgICB9O1xuICAgICAgICAgIH1cbiAgICAgICAgICBpZiAoIXJvdykge1xuICAgICAgICAgICAgcXVvdGErKztcbiAgICAgICAgICAgIHJvdyA9IHtcbiAgICAgICAgICAgICAgY29udHJhY3RfdmVyc2lvbjogMyxcbiAgICAgICAgICAgICAgaG9va19pZDogaWQsXG4gICAgICAgICAgICAgIHBheWxvYWRfaGFzaDogaGFzaCxcbiAgICAgICAgICAgICAgYXR0ZW1wdF9pZDogYXR0ZW1wdCxcbiAgICAgICAgICAgICAgc3RhdGU6IFwicmVzZXJ2ZWRcIixcbiAgICAgICAgICAgICAgcmV2aXNpb246IDEsXG4gICAgICAgICAgICAgIGNhbl9zZW5kOiB0cnVlLFxuICAgICAgICAgICAgfTtcbiAgICAgICAgICAgIHJvd3Muc2V0KGlkLCByb3cpO1xuICAgICAgICAgIH1cbiAgICAgICAgICByZXR1cm4geyBkYXRhOiB7IC4uLnJvdyB9LCBlcnJvcjogbnVsbCB9O1xuICAgICAgICB9XG4gICAgICAgIGlmICghcm93KSB0aHJvdyBuZXcgRXJyb3IoXCJmaXh0dXJlIGFic2VudCByb3dcIik7XG4gICAgICAgIGlmIChuYW1lID09PSBcImJlZ2luX3NpZ25lZF9vdHBfdjNcIikge1xuICAgICAgICAgIGNvbnN0IHN0YXJ0ZWQgPSByb3cuc3RhdGUgPT09IFwicmVzZXJ2ZWRcIiAmJlxuICAgICAgICAgICAgcm93LnJldmlzaW9uID09PSBhcmdzLnBfcmV2aXNpb247XG4gICAgICAgICAgaWYgKHN0YXJ0ZWQpIHtcbiAgICAgICAgICAgIHJvdy5zdGF0ZSA9IFwic2VuZGluZ1wiO1xuICAgICAgICAgICAgcm93LnJldmlzaW9uKys7XG4gICAgICAgICAgICByb3cuY2FuX3NlbmQgPSBmYWxzZTtcbiAgICAgICAgICB9XG4gICAgICAgICAgcmV0dXJuIHsgZGF0YTogeyAuLi5yb3csIHN0YXJ0ZWQgfSwgZXJyb3I6IG51bGwgfTtcbiAgICAgICAgfVxuICAgICAgICBpZiAobmFtZSA9PT0gXCJyZWNvcmRfc2lnbmVkX290cF92M1wiKSB7XG4gICAgICAgICAgcm93LnN0YXRlID0gYXJncy5wX291dGNvbWUgYXMgT3RwU3RhdGU7XG4gICAgICAgICAgcm93LnJldmlzaW9uKys7XG4gICAgICAgICAgcm93LmNhbl9zZW5kID0gZmFsc2U7XG4gICAgICAgICAgcmV0dXJuIHsgZGF0YTogeyAuLi5yb3cgfSwgZXJyb3I6IG51bGwgfTtcbiAgICAgICAgfVxuICAgICAgICB0aHJvdyBuZXcgRXJyb3IoXCJ1bmV4cGVjdGVkIGZpeHR1cmUgUlBDXCIpO1xuICAgICAgfSxcbiAgICB9KSxcbiAgICBmZXRjaDogYXN5bmMgKHVybCwgaW5pdCkgPT4ge1xuICAgICAgc2VuZHMrKztcbiAgICAgIHJldHVybiBhd2FpdCBwcm92aWRlcih1cmwsIGluaXQpO1xuICAgIH0sXG4gIH07XG4gIHJldHVybiB7XG4gICAgaGFuZGxlcjogY3JlYXRlT3RwSGFuZGxlcihkZXBzKSxcbiAgICBlbnYsXG4gICAgY2FsbHMsXG4gICAgcm93cyxcbiAgICBzZW5kczogKCkgPT4gc2VuZHMsXG4gICAgcXVvdGE6ICgpID0+IHF1b3RhLFxuICAgIHByb3ZpZGVyOiAoZjogT3RwRGVwZW5kZW5jaWVzW1wiZmV0Y2hcIl0pID0+IHByb3ZpZGVyID0gZixcbiAgICBvdmVycmlkZTogKGY6IHR5cGVvZiBycGNPdmVycmlkZSkgPT4gcnBjT3ZlcnJpZGUgPSBmLFxuICB9O1xufVxuYXN5bmMgZnVuY3Rpb24gYXNzZXJ0RXJyb3IocmVzcG9uc2U6IFJlc3BvbnNlLCBjb2RlOiBzdHJpbmcsIHN0YXR1cyA9IDUwMykge1xuICBhc3NlcnRFcXVhbHMocmVzcG9uc2Uuc3RhdHVzLCBzdGF0dXMpO1xuICBhc3NlcnRFcXVhbHMocmVzcG9uc2UuaGVhZGVycy5nZXQoXCJjYWNoZS1jb250cm9sXCIpLCBcIm5vLXN0b3JlXCIpO1xuICBjb25zdCB0ZXh0ID0gYXdhaXQgcmVzcG9uc2UudGV4dCgpO1xuICBhc3NlcnRFcXVhbHMoXG4gICAgdGV4dCxcbiAgICBKU09OLnN0cmluZ2lmeSh7IGVycm9yOiB7IGh0dHBfY29kZTogc3RhdHVzLCBtZXNzYWdlOiBjb2RlIH0gfSksXG4gICk7XG4gIGZvciAoXG4gICAgY29uc3Qgc2VjcmV0IG9mIFtcbiAgICAgIFwiU0VDUkVUX1RPS0VOXCIsXG4gICAgICBcIisyNTA3ODgxMjM0NTZcIixcbiAgICAgIFwiMTIzNDU2XCIsXG4gICAgICBcInVzZXJzX3ByaXZhdGVcIixcbiAgICAgIFwiU1FMXCIsXG4gICAgXVxuICApIHtcbiAgICBhc3NlcnRFcXVhbHModGV4dC5pbmNsdWRlcyhzZWNyZXQpLCBmYWxzZSk7XG4gIH1cbn1cbkRlbm8udGVzdChcIk9UUCBzaWduZWQgYWNjZXB0YW5jZSBpcyBjaGFyZ2VkIG9uY2UgYW5kIGlzIG5ldmVyIG1pc2xhYmVsZWQgZGVsaXZlcmVkXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGZpeHR1cmUoKTtcbiAgZi5wcm92aWRlcigodXJsLCBpbml0KSA9PiB7XG4gICAgYXNzZXJ0RXF1YWxzKHVybCwgXCJodHRwczovL2dyYXBoLmZhY2Vib29rLmNvbS92MjUuMC8xMjM0L21lc3NhZ2VzXCIpO1xuICAgIGFzc2VydEVxdWFscyhpbml0LnJlZGlyZWN0LCBcImVycm9yXCIpO1xuICAgIGFzc2VydEVxdWFscyhpbml0LnNpZ25hbCBpbnN0YW5jZW9mIEFib3J0U2lnbmFsLCB0cnVlKTtcbiAgICBjb25zdCBtZXNzYWdlID0gSlNPTi5wYXJzZShpbml0LmJvZHkgYXMgc3RyaW5nKTtcbiAgICBhc3NlcnRFcXVhbHMobWVzc2FnZS50ZW1wbGF0ZS5jb21wb25lbnRzWzBdLnBhcmFtZXRlcnNbMF0udGV4dCwgXCIxMjM0NTZcIik7XG4gICAgcmV0dXJuIFByb21pc2UucmVzb2x2ZShcbiAgICAgIG5ldyBSZXNwb25zZSgne1wibWVzc2FnZXNcIjpbe1wiaWRcIjpcIndhbWlkLnRlc3Qtb25seVwifV19JyksXG4gICAgKTtcbiAgfSk7XG4gIGFzc2VydEVxdWFscygoYXdhaXQgZi5oYW5kbGVyKGF3YWl0IHJlcXVlc3QoKSkpLnN0YXR1cywgMjAwKTtcbiAgYXNzZXJ0RXF1YWxzKChhd2FpdCBmLmhhbmRsZXIoYXdhaXQgcmVxdWVzdCgpKSkuc3RhdHVzLCAyMDApO1xuICBhc3NlcnRFcXVhbHMoZi5zZW5kcygpLCAxKTtcbiAgYXNzZXJ0RXF1YWxzKGYucXVvdGEoKSwgMSk7XG4gIGFzc2VydEVxdWFscyhmLnJvd3MuZ2V0KFwiaG9va19zaWduZWRfdGVzdFwiKT8uc3RhdGUsIFwiYWNjZXB0ZWRcIik7XG4gIGNvbnN0IHJlY29yZCA9IGYuY2FsbHMuZmluZCgoYykgPT4gYy5uYW1lID09PSBcInJlY29yZF9zaWduZWRfb3RwX3YzXCIpITtcbiAgYXNzZXJ0RXF1YWxzKHJlY29yZC5hcmdzLnBfb3V0Y29tZSwgXCJhY2NlcHRlZFwiKTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIHJlY29yZC5hcmdzLnBfcHJvdmlkZXJfbWVzc2FnZV9oYXNoLFxuICAgIGF3YWl0IHNoYTI1NkhleChcIndhbWlkLnRlc3Qtb25seVwiKSxcbiAgKTtcbiAgYXNzZXJ0RXF1YWxzKEpTT04uc3RyaW5naWZ5KHJlY29yZC5hcmdzKS5pbmNsdWRlcyhcIndhbWlkLnRlc3Qtb25seVwiKSwgZmFsc2UpO1xufSk7XG5EZW5vLnRlc3QoXCJPVFAgc2ltdWx0YW5lb3VzIHNpZ25lZCByZXBsYXkgaGFzIG9uZSBzZW5kIGNsYWltIGFuZCBvbmUgcXVvdGEgY2hhcmdlXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGZpeHR1cmUoKTtcbiAgbGV0IHJlbGVhc2UhOiAoKSA9PiB2b2lkO1xuICBjb25zdCBnYXRlID0gbmV3IFByb21pc2U8dm9pZD4oKHJlc29sdmUpID0+IHJlbGVhc2UgPSByZXNvbHZlKTtcbiAgZi5wcm92aWRlcihhc3luYyAoKSA9PiB7XG4gICAgYXdhaXQgZ2F0ZTtcbiAgICByZXR1cm4gbmV3IFJlc3BvbnNlKCd7XCJtZXNzYWdlc1wiOlt7XCJpZFwiOlwid2FtaWQub25lXCJ9XX0nKTtcbiAgfSk7XG4gIGNvbnN0IHJlc3BvbnNlcyA9IFByb21pc2UuYWxsKFxuICAgIEFycmF5LmZyb20oeyBsZW5ndGg6IDggfSwgYXN5bmMgKCkgPT4gZi5oYW5kbGVyKGF3YWl0IHJlcXVlc3QoKSkpLFxuICApO1xuICAvLyBXYWl0IG9ubHkgZm9yIGFjdHVhbCBtb2NrZWQgcHJvdmlkZXIgaW52b2NhdGlvbiwgbmV2ZXIgaW5mZXIgbGl2ZSBwcm9ncmVzcy5cbiAgd2hpbGUgKGYuc2VuZHMoKSA9PT0gMCkge1xuICAgIGF3YWl0IG5ldyBQcm9taXNlKChyZXNvbHZlKSA9PiBzZXRUaW1lb3V0KHJlc29sdmUsIDApKTtcbiAgfVxuICByZWxlYXNlKCk7XG4gIGNvbnN0IHJlc3VsdHMgPSBhd2FpdCByZXNwb25zZXM7XG4gIGFzc2VydEVxdWFscyhmLnNlbmRzKCksIDEpO1xuICBhc3NlcnRFcXVhbHMoZi5xdW90YSgpLCAxKTtcbiAgYXNzZXJ0RXF1YWxzKHJlc3VsdHMuZXZlcnkoKHIpID0+IFsyMDAsIDUwM10uaW5jbHVkZXMoci5zdGF0dXMpKSwgdHJ1ZSk7XG59KTtcbkRlbm8udGVzdChcIk9UUCBjaGFuZ2VkIHNpZ25lZCBib2R5IHVuZGVyIHNhbWUgaG9vayBjYW5ub3Qgc2VuZCBvciBjb25zdW1lIGFub3RoZXIgcXVvdGFcIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCBmID0gZml4dHVyZSgpO1xuICBhd2FpdCBmLmhhbmRsZXIoYXdhaXQgcmVxdWVzdCgpKTtcbiAgYXdhaXQgYXNzZXJ0RXJyb3IoXG4gICAgYXdhaXQgZi5oYW5kbGVyKFxuICAgICAgYXdhaXQgcmVxdWVzdCh7XG4gICAgICAgIGJvZHk6IEpTT04uc3RyaW5naWZ5KHtcbiAgICAgICAgICB1c2VyOiB7IHBob25lOiBcIisyNTA3ODgxMjM0NTZcIiB9LFxuICAgICAgICAgIHNtczogeyBvdHA6IFwiOTg3NjU0XCIgfSxcbiAgICAgICAgfSksXG4gICAgICB9KSxcbiAgICApLFxuICAgIFwib3RwX3Jlc2VydmF0aW9uX3VuYXZhaWxhYmxlXCIsXG4gICk7XG4gIGFzc2VydEVxdWFscyhmLnNlbmRzKCksIDEpO1xuICBhc3NlcnRFcXVhbHMoZi5xdW90YSgpLCAxKTtcbn0pO1xuZm9yIChcbiAgY29uc3QgW2xhYmVsLCByZXNwb25zZV0gb2YgW1xuICAgIFtcbiAgICAgIFwiaHR0cCBlcnJvclwiLFxuICAgICAgKCkgPT5cbiAgICAgICAgbmV3IFJlc3BvbnNlKCd7XCJlcnJvclwiOntcImNvZGVcIjoxMDAsXCJtZXNzYWdlXCI6XCInICsgcHJpdmF0ZVRleHQgKyAnXCJ9fScsIHtcbiAgICAgICAgICBzdGF0dXM6IDQwMCxcbiAgICAgICAgfSksXG4gICAgXSxcbiAgICBbXG4gICAgICBcInF1b3RhIGVycm9yXCIsXG4gICAgICAoKSA9PiBuZXcgUmVzcG9uc2UoJ3tcImVycm9yXCI6e1wiY29kZVwiOjEzMDQyOX19JywgeyBzdGF0dXM6IDQyOSB9KSxcbiAgICBdLFxuICAgIFtcImdhdGV3YXkgZXJyb3JcIiwgKCkgPT4gbmV3IFJlc3BvbnNlKHByaXZhdGVUZXh0LCB7IHN0YXR1czogNTAyIH0pXSxcbiAgICBbXCJlbXB0eSBhY2tcIiwgKCkgPT4gbmV3IFJlc3BvbnNlKFwie31cIildLFxuICAgIFtcImVtcHR5IG1lc3NhZ2UgaWRcIiwgKCkgPT4gbmV3IFJlc3BvbnNlKCd7XCJtZXNzYWdlc1wiOlt7XCJpZFwiOlwiXCJ9XX0nKV0sXG4gICAgW1xuICAgICAgXCJtdWx0aXBsZSBtZXNzYWdlIGlkc1wiLFxuICAgICAgKCkgPT4gbmV3IFJlc3BvbnNlKCd7XCJtZXNzYWdlc1wiOlt7XCJpZFwiOlwib25lXCJ9LHtcImlkXCI6XCJ0d29cIn1dfScpLFxuICAgIF0sXG4gICAgW1xuICAgICAgXCJjb250cm9sIGluIG1lc3NhZ2UgaWRcIixcbiAgICAgICgpID0+IG5ldyBSZXNwb25zZSgne1wibWVzc2FnZXNcIjpbe1wiaWRcIjpcImxpbmVcXFxcbnByaXZhdGVcIn1dfScpLFxuICAgIF0sXG4gICAgW1wibm9udGV4dCBtZXNzYWdlIGlkXCIsICgpID0+IG5ldyBSZXNwb25zZSgne1wibWVzc2FnZXNcIjpbe1wiaWRcIjoxMjN9XX0nKV0sXG4gICAgW1wiaW52YWxpZCBqc29uXCIsICgpID0+IG5ldyBSZXNwb25zZShwcml2YXRlVGV4dCldLFxuICAgIFtcIm92ZXJzaXplZCBib2R5XCIsICgpID0+IG5ldyBSZXNwb25zZShcInhcIi5yZXBlYXQoNjU1MzcpKV0sXG4gIF0gYXMgY29uc3Rcbikge1xuICBEZW5vLnRlc3QoXG4gICAgXCJPVFAgXCIgKyBsYWJlbCArIFwiIHN0YXlzIGFtYmlndW91cyB3aXRob3V0IGJsaW5kIHJlc2VuZFwiLFxuICAgIGFzeW5jICgpID0+IHtcbiAgICAgIGNvbnN0IGYgPSBmaXh0dXJlKCk7XG4gICAgICBmLnByb3ZpZGVyKCgpID0+IFByb21pc2UucmVzb2x2ZShyZXNwb25zZSgpKSk7XG4gICAgICBhd2FpdCBhc3NlcnRFcnJvcihcbiAgICAgICAgYXdhaXQgZi5oYW5kbGVyKGF3YWl0IHJlcXVlc3QoKSksXG4gICAgICAgIFwib3RwX2RlbGl2ZXJ5X3VucmVzb2x2ZWRcIixcbiAgICAgICk7XG4gICAgICBhd2FpdCBhc3NlcnRFcnJvcihcbiAgICAgICAgYXdhaXQgZi5oYW5kbGVyKGF3YWl0IHJlcXVlc3QoKSksXG4gICAgICAgIFwib3RwX2RlbGl2ZXJ5X3VucmVzb2x2ZWRcIixcbiAgICAgICk7XG4gICAgICBhc3NlcnRFcXVhbHMoZi5zZW5kcygpLCAxKTtcbiAgICAgIGFzc2VydEVxdWFscyhmLnF1b3RhKCksIDEpO1xuICAgICAgYXNzZXJ0RXF1YWxzKGYucm93cy5nZXQoXCJob29rX3NpZ25lZF90ZXN0XCIpPy5zdGF0ZSwgXCJhbWJpZ3VvdXNcIik7XG4gICAgICBhc3NlcnRFcXVhbHMoXG4gICAgICAgIGYuY2FsbHMuZmluZCgoYykgPT4gYy5uYW1lID09PSBcInJlY29yZF9zaWduZWRfb3RwX3YzXCIpPy5hcmdzXG4gICAgICAgICAgLnBfcHJvdmlkZXJfbWVzc2FnZV9oYXNoLFxuICAgICAgICBudWxsLFxuICAgICAgKTtcbiAgICB9LFxuICApO1xufVxuZm9yIChcbiAgY29uc3QgZXhjZXB0aW9uIG9mIFtcbiAgICBuZXcgRXJyb3IocHJpdmF0ZVRleHQpLFxuICAgIG5ldyBET01FeGNlcHRpb24ocHJpdmF0ZVRleHQsIFwiVGltZW91dEVycm9yXCIpLFxuICAgIG5ldyBQdWJsaWNFcnJvcihwcml2YXRlVGV4dCwgNDAwKSxcbiAgXVxuKSB7XG4gIERlbm8udGVzdChcIk9UUCB0cmFuc3BvcnQgZXhjZXB0aW9uIHJlZGFjdGVkIGFuZCBjaGFyZ2VkXCIsIGFzeW5jICgpID0+IHtcbiAgICBjb25zdCBmID0gZml4dHVyZSgpO1xuICAgIGYucHJvdmlkZXIoKCkgPT4gUHJvbWlzZS5yZWplY3QoZXhjZXB0aW9uKSk7XG4gICAgYXdhaXQgYXNzZXJ0RXJyb3IoXG4gICAgICBhd2FpdCBmLmhhbmRsZXIoYXdhaXQgcmVxdWVzdCgpKSxcbiAgICAgIFwib3RwX2RlbGl2ZXJ5X3VucmVzb2x2ZWRcIixcbiAgICApO1xuICAgIGF3YWl0IGFzc2VydEVycm9yKFxuICAgICAgYXdhaXQgZi5oYW5kbGVyKGF3YWl0IHJlcXVlc3QoKSksXG4gICAgICBcIm90cF9kZWxpdmVyeV91bnJlc29sdmVkXCIsXG4gICAgKTtcbiAgICBhc3NlcnRFcXVhbHMoZi5zZW5kcygpLCAxKTtcbiAgICBhc3NlcnRFcXVhbHMoZi5xdW90YSgpLCAxKTtcbiAgfSk7XG59XG5EZW5vLnRlc3QoXCJPVFAgYWNjZXB0ZWQgY29tcGxldGlvbiB3aXRoIGxvc3QgQUNLIHJlY292ZXJzIGZyb20gZHVyYWJsZSBhY2NlcHRhbmNlIHdpdGhvdXQgcmVzZW5kXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGZpeHR1cmUoKTtcbiAgZi5vdmVycmlkZSgobmFtZSkgPT4ge1xuICAgIGlmIChuYW1lID09PSBcInJlY29yZF9zaWduZWRfb3RwX3YzXCIpIHtcbiAgICAgIGNvbnN0IHJvdyA9IGYucm93cy5nZXQoXCJob29rX3NpZ25lZF90ZXN0XCIpITtcbiAgICAgIHJvdy5zdGF0ZSA9IFwiYWNjZXB0ZWRcIjtcbiAgICAgIHJvdy5yZXZpc2lvbisrO1xuICAgICAgcm93LmNhbl9zZW5kID0gZmFsc2U7XG4gICAgICByZXR1cm4geyBkYXRhOiBudWxsLCBlcnJvcjogbmV3IEVycm9yKHByaXZhdGVUZXh0KSB9O1xuICAgIH1cbiAgfSk7XG4gIGF3YWl0IGFzc2VydEVycm9yKFxuICAgIGF3YWl0IGYuaGFuZGxlcihhd2FpdCByZXF1ZXN0KCkpLFxuICAgIFwib3RwX2RlbGl2ZXJ5X3VucmVzb2x2ZWRcIixcbiAgKTtcbiAgYXNzZXJ0RXF1YWxzKChhd2FpdCBmLmhhbmRsZXIoYXdhaXQgcmVxdWVzdCgpKSkuc3RhdHVzLCAyMDApO1xuICBhc3NlcnRFcXVhbHMoZi5zZW5kcygpLCAxKTtcbiAgYXNzZXJ0RXF1YWxzKGYucXVvdGEoKSwgMSk7XG59KTtcbkRlbm8udGVzdChcIk9UUCBwcm92aWRlciBhY2NlcHRlZCBidXQgY29tcGxldGlvbiBhYnNlbnQgcmVtYWlucyB1bnJlc29sdmVkIHVudGlsIGV4cGxpY2l0IGV2aWRlbmNlIHJlY292ZXJ5XCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGZpeHR1cmUoKTtcbiAgZi5vdmVycmlkZSgobmFtZSkgPT5cbiAgICBuYW1lID09PSBcInJlY29yZF9zaWduZWRfb3RwX3YzXCJcbiAgICAgID8geyBkYXRhOiBudWxsLCBlcnJvcjogbmV3IEVycm9yKHByaXZhdGVUZXh0KSB9XG4gICAgICA6IHVuZGVmaW5lZFxuICApO1xuICBhd2FpdCBhc3NlcnRFcnJvcihcbiAgICBhd2FpdCBmLmhhbmRsZXIoYXdhaXQgcmVxdWVzdCgpKSxcbiAgICBcIm90cF9kZWxpdmVyeV91bnJlc29sdmVkXCIsXG4gICk7XG4gIGF3YWl0IGFzc2VydEVycm9yKFxuICAgIGF3YWl0IGYuaGFuZGxlcihhd2FpdCByZXF1ZXN0KCkpLFxuICAgIFwib3RwX2RlbGl2ZXJ5X3VucmVzb2x2ZWRcIixcbiAgKTtcbiAgYXNzZXJ0RXF1YWxzKGYuc2VuZHMoKSwgMSk7XG4gIGNvbnN0IHJvdyA9IGYucm93cy5nZXQoXCJob29rX3NpZ25lZF90ZXN0XCIpITtcbiAgcm93LnN0YXRlID0gXCJkZWxpdmVyZWRcIjtcbiAgcm93LnJldmlzaW9uKys7XG4gIHJvdy5jYW5fc2VuZCA9IGZhbHNlO1xuICAvLyBTaW11bGF0ZXMgaW5kZXBlbmRlbnRseSB2ZXJpZmllZCByZWNvdmVyeSwgbm90IGEgaGFuZGxlci1jcmVhdGVkIGRlbGl2ZXJ5LlxuICBhc3NlcnRFcXVhbHMoKGF3YWl0IGYuaGFuZGxlcihhd2FpdCByZXF1ZXN0KCkpKS5zdGF0dXMsIDIwMCk7XG4gIGFzc2VydEVxdWFscyhmLnNlbmRzKCksIDEpO1xufSk7XG5EZW5vLnRlc3QoXCJPVFAgbG9zdCBiZWdpbiBBQ0sgY2Fubm90IGxhdW5jaCBhIHByb3ZpZGVyIHNlbmQgb24gcmVwbGF5XCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGZpeHR1cmUoKTtcbiAgZi5vdmVycmlkZSgobmFtZSkgPT4ge1xuICAgIGlmIChuYW1lID09PSBcImJlZ2luX3NpZ25lZF9vdHBfdjNcIikge1xuICAgICAgY29uc3Qgcm93ID0gZi5yb3dzLmdldChcImhvb2tfc2lnbmVkX3Rlc3RcIikhO1xuICAgICAgcm93LnN0YXRlID0gXCJzZW5kaW5nXCI7XG4gICAgICByb3cucmV2aXNpb24rKztcbiAgICAgIHJvdy5jYW5fc2VuZCA9IGZhbHNlO1xuICAgICAgcmV0dXJuIHsgZGF0YTogbnVsbCwgZXJyb3I6IG5ldyBFcnJvcihwcml2YXRlVGV4dCkgfTtcbiAgICB9XG4gIH0pO1xuICBhd2FpdCBhc3NlcnRFcnJvcihcbiAgICBhd2FpdCBmLmhhbmRsZXIoYXdhaXQgcmVxdWVzdCgpKSxcbiAgICBcIm90cF9kZWxpdmVyeV91bnJlc29sdmVkXCIsXG4gICk7XG4gIGF3YWl0IGFzc2VydEVycm9yKFxuICAgIGF3YWl0IGYuaGFuZGxlcihhd2FpdCByZXF1ZXN0KCkpLFxuICAgIFwib3RwX2RlbGl2ZXJ5X3VucmVzb2x2ZWRcIixcbiAgKTtcbiAgYXNzZXJ0RXF1YWxzKGYuc2VuZHMoKSwgMCk7XG4gIGFzc2VydEVxdWFscyhmLnF1b3RhKCksIDEpO1xufSk7XG5mb3IgKFxuICBjb25zdCBzdGF0ZSBvZiBbXG4gICAgXCJzZW5kaW5nXCIsXG4gICAgXCJhbWJpZ3VvdXNcIixcbiAgICBcIm5vdF9zZW50XCIsXG4gICAgXCJmYWlsZWRcIixcbiAgICBcImV4cGlyZWRcIixcbiAgICBcImFjY2VwdGVkXCIsXG4gICAgXCJkZWxpdmVyZWRcIixcbiAgXSBhcyBjb25zdFxuKSB7XG4gIERlbm8udGVzdChcbiAgICBcIk9UUCBkdXJhYmxlIFwiICsgc3RhdGUgKyBcIiByZWFkIGNhbm5vdCBsYXVuY2ggYW5vdGhlciBzZW5kXCIsXG4gICAgYXN5bmMgKCkgPT4ge1xuICAgICAgY29uc3QgZiA9IGZpeHR1cmUoKTtcbiAgICAgIGYub3ZlcnJpZGUoKG5hbWUsIGFyZ3MpID0+XG4gICAgICAgIG5hbWUgPT09IFwicmVzZXJ2ZV9zaWduZWRfb3RwX3YzXCJcbiAgICAgICAgICA/IHtcbiAgICAgICAgICAgIGVycm9yOiBudWxsLFxuICAgICAgICAgICAgZGF0YToge1xuICAgICAgICAgICAgICBjb250cmFjdF92ZXJzaW9uOiAzLFxuICAgICAgICAgICAgICBob29rX2lkOiBhcmdzLnBfaG9va19pZCxcbiAgICAgICAgICAgICAgcGF5bG9hZF9oYXNoOiBhcmdzLnBfcGF5bG9hZF9oYXNoLFxuICAgICAgICAgICAgICBhdHRlbXB0X2lkOiBhdHRlbXB0LFxuICAgICAgICAgICAgICBzdGF0ZSxcbiAgICAgICAgICAgICAgcmV2aXNpb246IDgsXG4gICAgICAgICAgICAgIGNhbl9zZW5kOiBmYWxzZSxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgfVxuICAgICAgICAgIDogdW5kZWZpbmVkXG4gICAgICApO1xuICAgICAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBmLmhhbmRsZXIoYXdhaXQgcmVxdWVzdCgpKTtcbiAgICAgIGlmIChzdGF0ZSA9PT0gXCJhY2NlcHRlZFwiIHx8IHN0YXRlID09PSBcImRlbGl2ZXJlZFwiKSB7XG4gICAgICAgIGFzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMsIDIwMCk7XG4gICAgICB9IGVsc2Uge2F3YWl0IGFzc2VydEVycm9yKFxuICAgICAgICAgIHJlc3BvbnNlLFxuICAgICAgICAgIHN0YXRlID09PSBcIm5vdF9zZW50XCJcbiAgICAgICAgICAgID8gXCJvdHBfbm90X3NlbnRcIlxuICAgICAgICAgICAgOiBzdGF0ZSA9PT0gXCJmYWlsZWRcIlxuICAgICAgICAgICAgPyBcIm90cF9kZWxpdmVyeV9mYWlsZWRcIlxuICAgICAgICAgICAgOiBzdGF0ZSA9PT0gXCJleHBpcmVkXCJcbiAgICAgICAgICAgID8gXCJvdHBfZXhwaXJlZFwiXG4gICAgICAgICAgICA6IFwib3RwX2RlbGl2ZXJ5X3VucmVzb2x2ZWRcIixcbiAgICAgICAgICBbXCJub3Rfc2VudFwiLCBcImZhaWxlZFwiLCBcImV4cGlyZWRcIl0uaW5jbHVkZXMoc3RhdGUpID8gNTAyIDogNTAzLFxuICAgICAgICApO31cbiAgICAgIGFzc2VydEVxdWFscyhmLnNlbmRzKCksIDApO1xuICAgIH0sXG4gICk7XG59XG5mb3IgKFxuICBjb25zdCBtdXRhdGlvbiBvZiBbXG4gICAgeyBjb250cmFjdF92ZXJzaW9uOiAyIH0sXG4gICAgeyBwYXlsb2FkX2hhc2g6IFwiYVwiLnJlcGVhdCg2NCkgfSxcbiAgICB7IGhvb2tfaWQ6IFwid3JvbmdcIiB9LFxuICAgIHsgYXR0ZW1wdF9pZDogXCJicm9rZW5cIiB9LFxuICAgIHsgc3RhdGU6IFwidW5leHBlY3RlZFwiIH0sXG4gICAgeyByZXZpc2lvbjogMCB9LFxuICAgIHsgcmV2aXNpb246IFwiMVwiIH0sXG4gICAgeyBjYW5fc2VuZDogXCJ0cnVlXCIgfSxcbiAgICB7IHN0YXRlOiBcImFjY2VwdGVkXCIsIGNhbl9zZW5kOiB0cnVlIH0sXG4gIF1cbikge1xuICBEZW5vLnRlc3QoXG4gICAgXCJPVFAgbWFsZm9ybWVkIGR1cmFibGUgcmVjZWlwdCBibG9ja3MgYmVmb3JlIHNlbmRpbmc6IFwiICtcbiAgICAgIEpTT04uc3RyaW5naWZ5KG11dGF0aW9uKSxcbiAgICBhc3luYyAoKSA9PiB7XG4gICAgICBjb25zdCBmID0gZml4dHVyZSgpO1xuICAgICAgZi5vdmVycmlkZSgobmFtZSwgYXJncykgPT5cbiAgICAgICAgbmFtZSA9PT0gXCJyZXNlcnZlX3NpZ25lZF9vdHBfdjNcIlxuICAgICAgICAgID8ge1xuICAgICAgICAgICAgZXJyb3I6IG51bGwsXG4gICAgICAgICAgICBkYXRhOiB7XG4gICAgICAgICAgICAgIGNvbnRyYWN0X3ZlcnNpb246IDMsXG4gICAgICAgICAgICAgIGhvb2tfaWQ6IGFyZ3MucF9ob29rX2lkLFxuICAgICAgICAgICAgICBwYXlsb2FkX2hhc2g6IGFyZ3MucF9wYXlsb2FkX2hhc2gsXG4gICAgICAgICAgICAgIGF0dGVtcHRfaWQ6IGF0dGVtcHQsXG4gICAgICAgICAgICAgIHN0YXRlOiBcInJlc2VydmVkXCIsXG4gICAgICAgICAgICAgIHJldmlzaW9uOiAxLFxuICAgICAgICAgICAgICBjYW5fc2VuZDogdHJ1ZSxcbiAgICAgICAgICAgICAgLi4ubXV0YXRpb24sXG4gICAgICAgICAgICB9LFxuICAgICAgICAgIH1cbiAgICAgICAgICA6IHVuZGVmaW5lZFxuICAgICAgKTtcbiAgICAgIGF3YWl0IGFzc2VydEVycm9yKFxuICAgICAgICBhd2FpdCBmLmhhbmRsZXIoYXdhaXQgcmVxdWVzdCgpKSxcbiAgICAgICAgXCJvdHBfZGVsaXZlcnlfdW5yZXNvbHZlZFwiLFxuICAgICAgKTtcbiAgICAgIGFzc2VydEVxdWFscyhmLnNlbmRzKCksIDApO1xuICAgIH0sXG4gICk7XG59XG5EZW5vLnRlc3QoXCJPVFAgdGhyb3R0bGluZyBzZW5kcyBub3RoaW5nXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGZpeHR1cmUoKTtcbiAgZi5vdmVycmlkZSgoKSA9PiAoeyBkYXRhOiBcInRocm90dGxlZFwiLCBlcnJvcjogbnVsbCB9KSk7XG4gIGF3YWl0IGFzc2VydEVycm9yKGF3YWl0IGYuaGFuZGxlcihhd2FpdCByZXF1ZXN0KCkpLCBcIm90cF9yYXRlX2xpbWl0ZWRcIiwgNDI5KTtcbiAgYXNzZXJ0RXF1YWxzKGYuc2VuZHMoKSwgMCk7XG59KTtcbmZvciAoY29uc3QgbmFtZSBvZiBPYmplY3Qua2V5cyhiYXNlRW52KSkge1xuICBEZW5vLnRlc3QoXG4gICAgXCJPVFAgbWlzc2luZyBjb25maWd1cmF0aW9uIGNvbnN1bWVzIG5vIHF1b3RhOiBcIiArIG5hbWUsXG4gICAgYXN5bmMgKCkgPT4ge1xuICAgICAgY29uc3QgZiA9IGZpeHR1cmUoKTtcbiAgICAgIGRlbGV0ZSBmLmVudltuYW1lXTtcbiAgICAgIGF3YWl0IGFzc2VydEVycm9yKFxuICAgICAgICBhd2FpdCBmLmhhbmRsZXIoYXdhaXQgcmVxdWVzdCgpKSxcbiAgICAgICAgXCJvdHBfY29uZmlndXJhdGlvbl91bmF2YWlsYWJsZVwiLFxuICAgICAgKTtcbiAgICAgIGFzc2VydEVxdWFscyhmLnF1b3RhKCksIDApO1xuICAgICAgYXNzZXJ0RXF1YWxzKGYuc2VuZHMoKSwgMCk7XG4gICAgfSxcbiAgKTtcbn1cbkRlbm8udGVzdChcIk9UUCBzdGFsZSBzaWduZWQgaG9vayBjYW5ub3QgcmVzZXJ2ZSBvciBzZW5kXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGZpeHR1cmUoKTtcbiAgYXdhaXQgYXNzZXJ0RXJyb3IoXG4gICAgYXdhaXQgZi5oYW5kbGVyKGF3YWl0IHJlcXVlc3QoeyB0aW1lOiBub3cgLyAxMDAwIC0gMzAxIH0pKSxcbiAgICBcImludmFsaWRfaG9va19zaWduYXR1cmVcIixcbiAgICA0MDEsXG4gICk7XG4gIGFzc2VydEVxdWFscyhmLnF1b3RhKCksIDApO1xuICBhc3NlcnRFcXVhbHMoZi5zZW5kcygpLCAwKTtcbn0pO1xuRGVuby50ZXN0KFwiT1RQIGtleSByb3RhdGlvbiB2YWxpZGF0ZXMgcHJldmlvdXMgc2VjcmV0IGFuZCBkb2VzIG5vdCBhY2NlcHQgYW4gdW5yZWxhdGVkIHNlY3JldFwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGYgPSBmaXh0dXJlKCk7XG4gIGNvbnN0IG90aGVyID0gYnRvYShTdHJpbmcuZnJvbUNoYXJDb2RlKC4uLm5ldyBVaW50OEFycmF5KDMyKS5maWxsKDkpKSk7XG4gIGYuZW52LlNFTkRfU01TX0hPT0tfU0VDUkVUID0gXCJ3aHNlY19cIiArIG90aGVyO1xuICBmLmVudi5TRU5EX1NNU19IT09LX1BSRVZJT1VTX1NFQ1JFVCA9IFwid2hzZWNfXCIgKyBzZWNyZXQ7XG4gIGFzc2VydEVxdWFscygoYXdhaXQgZi5oYW5kbGVyKGF3YWl0IHJlcXVlc3QoKSkpLnN0YXR1cywgMjAwKTtcbiAgZGVsZXRlIGYuZW52LlNFTkRfU01TX0hPT0tfUFJFVklPVVNfU0VDUkVUO1xuICBhd2FpdCBhc3NlcnRFcnJvcihcbiAgICBhd2FpdCBmLmhhbmRsZXIoYXdhaXQgcmVxdWVzdCgpKSxcbiAgICBcImludmFsaWRfaG9va19zaWduYXR1cmVcIixcbiAgICA0MDEsXG4gICk7XG4gIGFzc2VydEVxdWFscyhmLnNlbmRzKCksIDEpO1xufSk7XG5EZW5vLnRlc3QoXCJPVFAgbWFsZm9ybWVkIHBob25lIGFuZCBPVFAgY2Fubm90IHJlc2VydmUgb3Igc2VuZFwiLCBhc3luYyAoKSA9PiB7XG4gIGZvciAoXG4gICAgY29uc3QgYm9keSBvZiBbXG4gICAgICB7IHVzZXI6IHsgcGhvbmU6IFwiKzI1MDc4ODEyMzQ1NiBTUUxcIiB9LCBzbXM6IHsgb3RwOiBcIjEyMzQ1NlwiIH0gfSxcbiAgICAgIHsgdXNlcjogeyBwaG9uZTogXCIrMjUwNzg4MTIzNDU2XCIgfSwgc21zOiB7IG90cDogMTIzNDU2IH0gfSxcbiAgICAgIHsgdXNlcjogeyBwaG9uZTogXCIrMjUwNzg4MTIzNDU2XCIgfSwgc21zOiB7IG90cDogXCIxMjNcIiB9IH0sXG4gICAgXVxuICApIHtcbiAgICBjb25zdCBmID0gZml4dHVyZSgpO1xuICAgIGF3YWl0IGFzc2VydEVycm9yKFxuICAgICAgYXdhaXQgZi5oYW5kbGVyKGF3YWl0IHJlcXVlc3QoeyBib2R5OiBKU09OLnN0cmluZ2lmeShib2R5KSB9KSksXG4gICAgICBcImludmFsaWRfb3RwX3BheWxvYWRcIixcbiAgICAgIDQwMCxcbiAgICApO1xuICAgIGFzc2VydEVxdWFscyhmLnF1b3RhKCksIDApO1xuICAgIGFzc2VydEVxdWFscyhmLnNlbmRzKCksIDApO1xuICB9XG59KTtcbkRlbm8udGVzdChcIk9UUCB1bmtub3duIGRlcGVuZGVuY3kgZXJyb3JzIGFuZCBmb3JnZWQgUHVibGljRXJyb3IgY29kZXMgbmV2ZXIgZGlzY2xvc2UgZGF0YVwiLCBhc3luYyAoKSA9PiB7XG4gIGZvciAoXG4gICAgY29uc3QgZXJyb3Igb2YgW25ldyBFcnJvcihwcml2YXRlVGV4dCksIG5ldyBQdWJsaWNFcnJvcihwcml2YXRlVGV4dCwgNDAwKV1cbiAgKSB7XG4gICAgY29uc3QgZiA9IGZpeHR1cmUoKTtcbiAgICBmLm92ZXJyaWRlKCgpID0+IHtcbiAgICAgIHRocm93IGVycm9yO1xuICAgIH0pO1xuICAgIGF3YWl0IGFzc2VydEVycm9yKGF3YWl0IGYuaGFuZGxlcihhd2FpdCByZXF1ZXN0KCkpLCBcInNlcnZpY2VfdW5hdmFpbGFibGVcIik7XG4gICAgYXNzZXJ0RXF1YWxzKGYuc2VuZHMoKSwgMCk7XG4gIH1cbn0pO1xuRGVuby50ZXN0KFwiT1RQIGxhdGUgY29tcGxldGlvbiBmcm9tIGFub3RoZXIgYXR0ZW1wdCBjYW5ub3QgYWNrbm93bGVkZ2Ugc3VjY2Vzc1wiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGYgPSBmaXh0dXJlKCk7XG4gIGYub3ZlcnJpZGUoKG5hbWUsIGFyZ3MpID0+XG4gICAgbmFtZSA9PT0gXCJyZWNvcmRfc2lnbmVkX290cF92M1wiXG4gICAgICA/IHtcbiAgICAgICAgZGF0YToge1xuICAgICAgICAgIGNvbnRyYWN0X3ZlcnNpb246IDMsXG4gICAgICAgICAgaG9va19pZDogYXJncy5wX2hvb2tfaWQsXG4gICAgICAgICAgcGF5bG9hZF9oYXNoOiBhcmdzLnBfcGF5bG9hZF9oYXNoLFxuICAgICAgICAgIGF0dGVtcHRfaWQ6IFwiMjIyMjIyMjItMjIyMi00MjIyLTgyMjItMjIyMjIyMjIyMjIyXCIsXG4gICAgICAgICAgc3RhdGU6IFwiYWNjZXB0ZWRcIixcbiAgICAgICAgICByZXZpc2lvbjogMyxcbiAgICAgICAgICBjYW5fc2VuZDogZmFsc2UsXG4gICAgICAgIH0sXG4gICAgICAgIGVycm9yOiBudWxsLFxuICAgICAgfVxuICAgICAgOiB1bmRlZmluZWRcbiAgKTtcbiAgYXdhaXQgYXNzZXJ0RXJyb3IoXG4gICAgYXdhaXQgZi5oYW5kbGVyKGF3YWl0IHJlcXVlc3QoKSksXG4gICAgXCJvdHBfZGVsaXZlcnlfdW5yZXNvbHZlZFwiLFxuICApO1xuICBhc3NlcnRFcXVhbHMoZi5zZW5kcygpLCAxKTtcbn0pO1xuRGVuby50ZXN0KFwiT1RQIEdFVCBhbmQgT1BUSU9OUyBkbyBub3QgY29uc3VtZSBxdW90YVwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGYgPSBmaXh0dXJlKCk7XG4gIGFzc2VydEVxdWFscygoYXdhaXQgZi5oYW5kbGVyKG5ldyBSZXF1ZXN0KFwiaHR0cHM6Ly9lZGdlLnRlc3RcIikpKS5zdGF0dXMsIDQwNSk7XG4gIGFzc2VydEVxdWFscyhcbiAgICAoYXdhaXQgZi5oYW5kbGVyKG5ldyBSZXF1ZXN0KFwiaHR0cHM6Ly9lZGdlLnRlc3RcIiwgeyBtZXRob2Q6IFwiT1BUSU9OU1wiIH0pKSlcbiAgICAgIC5zdGF0dXMsXG4gICAgMjAwLFxuICApO1xuICBhc3NlcnRFcXVhbHMoZi5xdW90YSgpLCAwKTtcbiAgYXNzZXJ0RXF1YWxzKGYuc2VuZHMoKSwgMCk7XG59KTtcblxuRGVuby50ZXN0KFwiT1RQIG5ldmVyLXJlc29sdmluZyBwcm92aWRlciBvYmV5cyBkZWFkbGluZSwgcmVjb3JkcyBhbWJpZ3VpdHkgYW5kIG5ldmVyIHJlc2VuZHNcIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCBmID0gZml4dHVyZSh7IHRvdGFsTXM6IDIwMCwgcHJvdmlkZXJNczogMTAgfSk7XG4gIGYucHJvdmlkZXIoKCkgPT4gbmV3IFByb21pc2UoKCkgPT4ge30pKTtcbiAgY29uc3Qgc3RhcnRlZCA9IHBlcmZvcm1hbmNlLm5vdygpO1xuICBhd2FpdCBhc3NlcnRFcnJvcihcbiAgICBhd2FpdCBmLmhhbmRsZXIoYXdhaXQgcmVxdWVzdCgpKSxcbiAgICBcIm90cF9kZWxpdmVyeV91bnJlc29sdmVkXCIsXG4gICk7XG4gIGFzc2VydEVxdWFscyhwZXJmb3JtYW5jZS5ub3coKSAtIHN0YXJ0ZWQgPCAxMDAwLCB0cnVlKTtcbiAgYXNzZXJ0RXF1YWxzKGYucm93cy5nZXQoXCJob29rX3NpZ25lZF90ZXN0XCIpPy5zdGF0ZSwgXCJhbWJpZ3VvdXNcIik7XG4gIGF3YWl0IGFzc2VydEVycm9yKFxuICAgIGF3YWl0IGYuaGFuZGxlcihhd2FpdCByZXF1ZXN0KCkpLFxuICAgIFwib3RwX2RlbGl2ZXJ5X3VucmVzb2x2ZWRcIixcbiAgKTtcbiAgYXNzZXJ0RXF1YWxzKGYuc2VuZHMoKSwgMSk7XG4gIGFzc2VydEVxdWFscyhmLnF1b3RhKCksIDEpO1xufSk7XG5EZW5vLnRlc3QoXCJPVFAgbmV2ZXItcmVzb2x2aW5nIHJlc2VydmF0aW9uIG9iZXlzIHRvdGFsIGhvb2sgZGVhZGxpbmUgYW5kIHNlbmRzIG5vdGhpbmdcIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCBmID0gZml4dHVyZSh7IHRvdGFsTXM6IDIwLCBwcm92aWRlck1zOiAxMCB9KTtcbiAgZi5vdmVycmlkZSgobmFtZSkgPT5cbiAgICBuYW1lID09PSBcInJlc2VydmVfc2lnbmVkX290cF92M1wiID8gbmV3IFByb21pc2UoKCkgPT4ge30pIDogdW5kZWZpbmVkXG4gICk7XG4gIGNvbnN0IHN0YXJ0ZWQgPSBwZXJmb3JtYW5jZS5ub3coKTtcbiAgYXdhaXQgYXNzZXJ0RXJyb3IoXG4gICAgYXdhaXQgZi5oYW5kbGVyKGF3YWl0IHJlcXVlc3QoKSksXG4gICAgXCJvdHBfZGVsaXZlcnlfdW5yZXNvbHZlZFwiLFxuICApO1xuICBhc3NlcnRFcXVhbHMocGVyZm9ybWFuY2Uubm93KCkgLSBzdGFydGVkIDwgMTAwMCwgdHJ1ZSk7XG4gIGFzc2VydEVxdWFscyhmLnNlbmRzKCksIDApO1xufSk7XG5EZW5vLnRlc3QoXCJPVFAgYWNjZXB0ZWQgc2VuZCB3aXRoIHN0YWxsZWQgY29tcGxldGlvbiByZXR1cm5zIHVucmVzb2x2ZWQgd2l0aGluIGhvb2sgZGVhZGxpbmVcIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCBmID0gZml4dHVyZSh7IHRvdGFsTXM6IDMwLCBwcm92aWRlck1zOiAxMCB9KTtcbiAgZi5vdmVycmlkZSgobmFtZSkgPT5cbiAgICBuYW1lID09PSBcInJlY29yZF9zaWduZWRfb3RwX3YzXCIgPyBuZXcgUHJvbWlzZSgoKSA9PiB7fSkgOiB1bmRlZmluZWRcbiAgKTtcbiAgYXdhaXQgYXNzZXJ0RXJyb3IoXG4gICAgYXdhaXQgZi5oYW5kbGVyKGF3YWl0IHJlcXVlc3QoKSksXG4gICAgXCJvdHBfZGVsaXZlcnlfdW5yZXNvbHZlZFwiLFxuICApO1xuICBhd2FpdCBhc3NlcnRFcnJvcihcbiAgICBhd2FpdCBmLmhhbmRsZXIoYXdhaXQgcmVxdWVzdCgpKSxcbiAgICBcIm90cF9kZWxpdmVyeV91bnJlc29sdmVkXCIsXG4gICk7XG4gIGFzc2VydEVxdWFscyhmLnNlbmRzKCksIDEpO1xuICBhc3NlcnRFcXVhbHMoZi5xdW90YSgpLCAxKTtcbn0pO1xuRGVuby50ZXN0KFwiT1RQIHN0YWxsZWQgcHJvdmlkZXIgcmVzcG9uc2UgYm9keSB0aW1lcyBvdXQgYXMgYW1iaWd1aXR5IHdpdGhvdXQgbGVha2luZyBvciByZXNlbmRpbmdcIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCBmID0gZml4dHVyZSh7IHRvdGFsTXM6IDIwMCwgcHJvdmlkZXJNczogMTAgfSk7XG4gIGxldCBzdHJlYW0hOiBSZWFkYWJsZVN0cmVhbURlZmF1bHRDb250cm9sbGVyPFVpbnQ4QXJyYXk+O1xuICBmLnByb3ZpZGVyKCgpID0+XG4gICAgUHJvbWlzZS5yZXNvbHZlKFxuICAgICAgbmV3IFJlc3BvbnNlKFxuICAgICAgICBuZXcgUmVhZGFibGVTdHJlYW0oe1xuICAgICAgICAgIHN0YXJ0KGMpIHtcbiAgICAgICAgICAgIHN0cmVhbSA9IGM7XG4gICAgICAgICAgfSxcbiAgICAgICAgfSksXG4gICAgICApLFxuICAgIClcbiAgKTtcbiAgdHJ5IHtcbiAgICBhd2FpdCBhc3NlcnRFcnJvcihcbiAgICAgIGF3YWl0IGYuaGFuZGxlcihhd2FpdCByZXF1ZXN0KCkpLFxuICAgICAgXCJvdHBfZGVsaXZlcnlfdW5yZXNvbHZlZFwiLFxuICAgICk7XG4gICAgYXdhaXQgYXNzZXJ0RXJyb3IoXG4gICAgICBhd2FpdCBmLmhhbmRsZXIoYXdhaXQgcmVxdWVzdCgpKSxcbiAgICAgIFwib3RwX2RlbGl2ZXJ5X3VucmVzb2x2ZWRcIixcbiAgICApO1xuICAgIGFzc2VydEVxdWFscyhmLnNlbmRzKCksIDEpO1xuICAgIGFzc2VydEVxdWFscyhmLnJvd3MuZ2V0KFwiaG9va19zaWduZWRfdGVzdFwiKT8uc3RhdGUsIFwiYW1iaWd1b3VzXCIpO1xuICB9IGZpbmFsbHkge1xuICAgIHN0cmVhbS5jbG9zZSgpO1xuICB9XG59KTtcbiJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiQUFBQSxTQUFTLFlBQVksUUFBUSw0QkFBNEI7QUFDekQsU0FBUyxXQUFXLFFBQVEsb0NBQW9DO0FBQ2hFLFNBQVMsU0FBUyxRQUFRLHFCQUFxQjtBQUMvQyxTQUNFLGdCQUFnQixRQUlYLGVBQWU7QUFFdEIsTUFBTSxNQUFNLEtBQUssS0FBSyxDQUFDO0FBQ3ZCLE1BQU0sU0FBUyxLQUFLLE9BQU8sWUFBWSxJQUFJLElBQUksV0FBVyxJQUFJLElBQUksQ0FBQztBQUNuRSxNQUFNLFVBQVU7QUFDaEIsTUFBTSxjQUNKO0FBQ0YsTUFBTSxVQUFrQztFQUN0QyxzQkFBc0IsY0FBYztFQUNwQyw0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
// denoCacheMetadata=2662747151984750778,7965065077620566054
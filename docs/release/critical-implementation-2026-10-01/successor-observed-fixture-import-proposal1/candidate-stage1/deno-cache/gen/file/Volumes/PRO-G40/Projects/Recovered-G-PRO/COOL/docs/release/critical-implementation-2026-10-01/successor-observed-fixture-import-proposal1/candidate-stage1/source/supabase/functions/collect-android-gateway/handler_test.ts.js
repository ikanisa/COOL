import { assertEquals } from "../_shared/test_assert.ts";
import { createGatewayHandler, derToP1363 } from "./handler.ts";
const DEVICE = "99750000-0000-4000-8000-000000000001";
const REQUEST = "99750000-0000-4000-8000-000000000002";
const TARGET = "99750000-0000-4000-8000-000000000003";
const CALLBACK = "99750000-0000-4000-8000-000000000004";
const NOW = Date.parse("2026-09-30T21:00:00Z");
const TIME = new Date(NOW).toISOString();
const encode = new TextEncoder();
const b64 = (bytes)=>btoa(String.fromCharCode(...bytes));
async function sha(bytes) {
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes))), (b)=>b.toString(16).padStart(2, "0")).join("");
}
function der(raw) {
  const parts = [
    raw.slice(0, 32),
    raw.slice(32)
  ].map((part)=>{
    while(part.length > 1 && part[0] === 0)part = part.slice(1);
    if (part[0] & 128) part = Uint8Array.from([
      0,
      ...part
    ]);
    return Uint8Array.from([
      2,
      part.length,
      ...part
    ]);
  });
  return Uint8Array.from([
    48,
    parts[0].length + parts[1].length,
    ...parts[0],
    ...parts[1]
  ]);
}
const heartbeat = ()=>({
    sms_permission: true,
    network: "validated",
    telephony: "ready",
    sim_selected: true,
    sim_revision_sha256: "a".repeat(64),
    local_pause: false,
    reported_at: TIME
  });
const callback = ()=>({
    callback_id: CALLBACK,
    attempt_id: TARGET,
    fence_version: 1,
    segment_index: 0,
    segment_count: 1,
    body_sha256: "b".repeat(64),
    destination_sha256: "c".repeat(64),
    callback_kind: "sent",
    result_code: -1,
    tp_status: null,
    occurred_at: TIME
  });
function envelope(action = "heartbeat", payload = heartbeat(), patch = {}) {
  return {
    contract_version: 1,
    action,
    device_id: DEVICE,
    request_id: REQUEST,
    issued_at: TIME,
    payload,
    ...patch
  };
}
async function fixture(state = "pending") {
  const pair = await crypto.subtle.generateKey({
    name: "ECDSA",
    namedCurve: "P-256"
  }, true, [
    "sign",
    "verify"
  ]);
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", pair.publicKey));
  const id = await sha(spki);
  const calls = [];
  let result = {
    observation_id: TARGET,
    ingested_at: TIME,
    replay: false,
    carrier_proof: false
  };
  let error = null;
  const deps = {
    now: ()=>NOW,
    timeoutMs: 50,
    rpc: async (name, args)=>{
      calls.push({
        name,
        args
      });
      if (name === "gateway_device_key_v1") {
        return {
          data: {
            device_id: DEVICE,
            state,
            public_key_spki_base64: b64(spki),
            key_sha256: id,
            installation_id: TARGET,
            signing_certificate_sha256: "d".repeat(64)
          },
          error: null
        };
      }
      return {
        data: result,
        error
      };
    }
  };
  async function signed(value = envelope(), text, patch = {}) {
    const bytes = encode.encode(text ?? JSON.stringify(value));
    const signature = der(new Uint8Array(await crypto.subtle.sign({
      name: "ECDSA",
      hash: "SHA-256"
    }, pair.privateKey, bytes)));
    return new Request("https://gateway.test/collect-android-gateway", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "X-Collect-Gateway-Key-Id": id,
        "X-Collect-Gateway-Signature": b64(signature),
        ...patch
      },
      body: bytes
    });
  }
  return {
    pair,
    spki,
    id,
    calls,
    deps,
    signed,
    handler: createGatewayHandler(deps),
    setResult: (value)=>result = value,
    setError: (value)=>error = value
  };
}
Deno.test("real synthetic P-256 DER signature accepts pending key-possession health and server request SHA", async ()=>{
  const f = await fixture();
  const env = envelope();
  const response = await f.handler(await f.signed(env));
  assertEquals(response.status, 200);
  const parsed = await response.json();
  assertEquals(parsed.action, "heartbeat");
  assertEquals(parsed.result.carrier_proof, false);
  assertEquals(f.calls.map((x)=>x.name), [
    "gateway_device_key_v1",
    "gateway_heartbeat_v1"
  ]);
  assertEquals(f.calls[1].args.p_request_sha256, await sha(encode.encode(JSON.stringify(env))));
  assertEquals(response.headers.get("cache-control"), "no-store");
});
Deno.test("tampered signed UTF8 body cannot reach a mutation RPC", async ()=>{
  const f = await fixture();
  const signed = await f.signed();
  const response = await f.handler(new Request(signed.url, {
    method: "POST",
    headers: signed.headers,
    body: JSON.stringify(envelope("heartbeat", {
      ...heartbeat(),
      local_pause: true
    }))
  }));
  assertEquals(response.status, 401);
  assertEquals(f.calls.length, 1);
});
Deno.test("different generated private key cannot authorize enrolled identity", async ()=>{
  const f = await fixture();
  const other = await fixture();
  const request = await other.signed(undefined, undefined, {
    "X-Collect-Gateway-Key-Id": f.id
  });
  const response = await f.handler(request);
  assertEquals(response.status, 401);
  assertEquals(f.calls.length, 1);
});
Deno.test("wrong public-key header and malformed DER fail closed", async ()=>{
  const f = await fixture();
  assertEquals((await f.handler(await f.signed(undefined, undefined, {
    "X-Collect-Gateway-Key-Id": "f".repeat(64)
  }))).status, 401);
  assertEquals((await f.handler(await f.signed(undefined, undefined, {
    "X-Collect-Gateway-Signature": b64(Uint8Array.from([
      48,
      6,
      2,
      1,
      0,
      2,
      1,
      1
    ]))
  }))).status, 400);
  assertEquals(f.calls.length, 1);
});
Deno.test("canonical DER roundtrip and nonminimal integers are enforced", async ()=>{
  const f = await fixture();
  const raw = new Uint8Array(await crypto.subtle.sign({
    name: "ECDSA",
    hash: "SHA-256"
  }, f.pair.privateKey, encode.encode("synthetic")));
  assertEquals(Array.from(derToP1363(der(raw))), Array.from(raw));
  let refused = false;
  try {
    derToP1363(Uint8Array.from([
      48,
      7,
      2,
      2,
      0,
      1,
      2,
      1,
      1
    ]));
  } catch  {
    refused = true;
  }
  assertEquals(refused, true);
});
for (const [name, value] of [
  [
    "expired",
    envelope("heartbeat", heartbeat(), {
      issued_at: new Date(NOW - 120001).toISOString()
    })
  ],
  [
    "future",
    envelope("heartbeat", heartbeat(), {
      issued_at: new Date(NOW + 120001).toISOString()
    })
  ],
  [
    "invalid calendar",
    envelope("heartbeat", heartbeat(), {
      issued_at: "2026-02-31T21:00:00Z"
    })
  ],
  [
    "unknown action",
    envelope("enroll", {})
  ],
  [
    "wrong version",
    envelope("heartbeat", heartbeat(), {
      contract_version: 2
    })
  ],
  [
    "bad UUID",
    envelope("heartbeat", heartbeat(), {
      device_id: "unsafe"
    })
  ],
  [
    "extra envelope",
    envelope("heartbeat", heartbeat(), {
      message_body: "private"
    })
  ],
  [
    "permission string",
    envelope("heartbeat", {
      ...heartbeat(),
      sms_permission: "true"
    })
  ],
  [
    "extra health field",
    envelope("heartbeat", {
      ...heartbeat(),
      destination: "private"
    })
  ],
  [
    "null SIM revision selected",
    envelope("heartbeat", {
      ...heartbeat(),
      sim_revision_sha256: null
    })
  ],
  [
    "unselected SIM with revision",
    envelope("heartbeat", {
      ...heartbeat(),
      sim_selected: false
    })
  ],
  [
    "invalid network",
    envelope("heartbeat", {
      ...heartbeat(),
      network: "online"
    })
  ],
  [
    "unsupported callback conclusion",
    envelope("callback", {
      ...callback(),
      delivered: true
    })
  ],
  [
    "fractional segment",
    envelope("callback", {
      ...callback(),
      segment_index: 0.5
    })
  ],
  [
    "oversized segment count",
    envelope("callback", {
      ...callback(),
      segment_count: 11
    })
  ],
  [
    "segment beyond count",
    envelope("callback", {
      ...callback(),
      segment_index: 1
    })
  ],
  [
    "reused callback request UUID",
    envelope("callback", {
      ...callback(),
      callback_id: REQUEST
    })
  ],
  [
    "callback result boolean",
    envelope("callback", {
      ...callback(),
      result_code: true
    })
  ],
  [
    "callback TP overflow",
    envelope("callback", {
      ...callback(),
      tp_status: 256
    })
  ],
  [
    "grant with client body",
    envelope("dispatch_grant", {
      message_body: "private"
    })
  ],
  [
    "reconcile invalid target",
    envelope("reconcile", {
      target_request_id: null
    })
  ]
]){
  Deno.test("strict envelope/payload refuses " + name, async ()=>{
    const f = await fixture();
    assertEquals((await f.handler(await f.signed(value))).status, 400);
    assertEquals(f.calls.length, 0);
  });
}
Deno.test("duplicate JSON keys rejected before signature-authorized RPC", async ()=>{
  const f = await fixture();
  const text = JSON.stringify(envelope()).replace('"contract_version":1', '"contract_version":1,"contract_version":1');
  assertEquals((await f.handler(await f.signed(undefined, text))).status, 400);
  assertEquals(f.calls.length, 0);
});
Deno.test("signed Unicode tamper verifies exact bytes rather than reserialized JSON", async ()=>{
  const f = await fixture();
  const text = JSON.stringify(envelope()).replace('"network":"validated"', '"network":"valid\\u0061ted"');
  const response = await f.handler(await f.signed(undefined, text));
  assertEquals(response.status, 200);
  assertEquals(f.calls[1].args.p_request_sha256, await sha(encode.encode(text)));
});
Deno.test("POST-only and oversized/invalid UTF8 bodies reach no RPC", async ()=>{
  const f = await fixture();
  assertEquals((await f.handler(new Request("https://gateway.test", {
    method: "GET"
  }))).status, 405);
  assertEquals((await f.handler(new Request("https://gateway.test", {
    method: "POST",
    headers: {
      "content-type": "application/json"
    },
    body: " ".repeat(8193)
  }))).status, 413);
  assertEquals((await f.handler(new Request("https://gateway.test", {
    method: "POST",
    headers: {
      "content-type": "application/json"
    },
    body: Uint8Array.from([
      255
    ])
  }))).status, 400);
  assertEquals(f.calls.length, 0);
});
Deno.test("revoked key permits only bounded reconciliation and prior-arm callback routes", async ()=>{
  const f = await fixture("revoked");
  assertEquals((await f.handler(await f.signed())).status, 403);
  assertEquals(f.calls.length, 1);
  f.setResult({
    target_request_id: TARGET,
    outcome: "unknown",
    recorded_action: null,
    recorded_result: null
  });
  assertEquals((await f.handler(await f.signed(envelope("reconcile", {
    target_request_id: TARGET
  })))).status, 200);
  f.setResult({
    callback_id: CALLBACK,
    recorded_at: TIME,
    replay: false,
    carrier_proof: false
  });
  assertEquals((await f.handler(await f.signed(envelope("callback", callback())))).status, 200);
  f.setError({
    code: "42501"
  });
  assertEquals((await f.handler(await f.signed(envelope("callback", callback())))).status, 403);
});
Deno.test("dispatch is stable authority-pending refusal with no body destination or grant", async ()=>{
  const f = await fixture("active");
  f.setResult({
    ok: false,
    code: "GATEWAY_DISPATCH_AUTHORITY_PENDING",
    device_id: DEVICE,
    request_id: REQUEST,
    replay: false
  });
  const response = await f.handler(await f.signed(envelope("dispatch_grant", {})));
  assertEquals(response.status, 200);
  assertEquals(Object.keys((await response.json()).result).sort(), [
    "code",
    "device_id",
    "ok",
    "replay",
    "request_id"
  ]);
});
Deno.test("stored request reconciliation validates nested bounded result rather than leaking extra keys", async ()=>{
  const f = await fixture();
  f.setResult({
    target_request_id: TARGET,
    outcome: "recorded",
    recorded_action: "dispatch_grant",
    recorded_result: {
      ok: false,
      code: "GATEWAY_DISPATCH_AUTHORITY_PENDING",
      device_id: DEVICE,
      request_id: TARGET,
      replay: false
    }
  });
  assertEquals((await f.handler(await f.signed(envelope("reconcile", {
    target_request_id: TARGET
  })))).status, 200);
  f.setResult({
    target_request_id: TARGET,
    outcome: "recorded",
    recorded_action: "callback",
    recorded_result: {
      callback_id: CALLBACK,
      recorded_at: TIME,
      replay: false,
      carrier_proof: false,
      message_body: "private"
    }
  });
  const response = await f.handler(await f.signed(envelope("reconcile", {
    target_request_id: TARGET
  })));
  assertEquals(response.status, 502);
  assertEquals(await response.text(), '{"ok":false,"code":"GATEWAY_OUTCOME_UNKNOWN"}');
});
Deno.test("malformed success provider diagnostics and deadline return safe unknown without retry", async ()=>{
  const f = await fixture();
  f.setResult({
    observation_id: TARGET,
    ingested_at: TIME,
    replay: false,
    carrier_proof: false,
    destination: "private"
  });
  assertEquals((await f.handler(await f.signed())).status, 502);
  f.setError({
    code: "XX000"
  });
  assertEquals((await f.handler(await f.signed())).status, 503);
  const old = f.deps.rpc;
  f.deps.rpc = (name, args, signal)=>name === "gateway_device_key_v1" ? old(name, args, signal) : new Promise(()=>{});
  const response = await f.handler(await f.signed());
  assertEquals(response.status, 504);
  assertEquals((await response.json()).code, "GATEWAY_OUTCOME_UNKNOWN");
  assertEquals(f.calls.filter((c)=>c.name === "gateway_heartbeat_v1").length, 2);
});
Deno.test("exact replay returns original observation rather than a second mutation route", async ()=>{
  const f = await fixture();
  const request = await f.signed();
  assertEquals((await f.handler(request)).status, 200);
  f.setResult({
    observation_id: TARGET,
    ingested_at: TIME,
    replay: true,
    carrier_proof: false
  });
  const response = await f.handler(await f.signed());
  assertEquals(response.status, 200);
  assertEquals((await response.json()).result.replay, true);
});
Deno.test("slow body reader is bounded and cannot reach any service RPC", async ()=>{
  const f = await fixture();
  let canceled = false;
  const stream = new ReadableStream({
    cancel () {
      canceled = true;
    }
  });
  const request = new Request("https://gateway.test", {
    method: "POST",
    headers: {
      "content-type": "application/json"
    },
    body: stream
  });
  const response = await f.handler(request);
  assertEquals(response.status >= 400, true);
  assertEquals(f.calls.length, 0);
  assertEquals(canceled, true);
});
Deno.test("malformed large service success stays outcome-unknown and redacted", async ()=>{
  const f = await fixture();
  f.setResult({
    private_body: "private".repeat(2000)
  });
  const response = await f.handler(await f.signed());
  assertEquals(response.status, 502);
  assertEquals(await response.text(), '{"ok":false,"code":"GATEWAY_OUTCOME_UNKNOWN"}');
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2NvbGxlY3QtYW5kcm9pZC1nYXRld2F5L2hhbmRsZXJfdGVzdC50cyJdLCJzb3VyY2VzQ29udGVudCI6WyJpbXBvcnQgeyBhc3NlcnRFcXVhbHMgfSBmcm9tIFwiLi4vX3NoYXJlZC90ZXN0X2Fzc2VydC50c1wiO1xuaW1wb3J0IHtcbiAgY3JlYXRlR2F0ZXdheUhhbmRsZXIsXG4gIGRlclRvUDEzNjMsXG4gIHR5cGUgR2F0ZXdheURlcGVuZGVuY2llcyxcbn0gZnJvbSBcIi4vaGFuZGxlci50c1wiO1xuY29uc3QgREVWSUNFID0gXCI5OTc1MDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDFcIjtcbmNvbnN0IFJFUVVFU1QgPSBcIjk5NzUwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwMlwiO1xuY29uc3QgVEFSR0VUID0gXCI5OTc1MDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDNcIjtcbmNvbnN0IENBTExCQUNLID0gXCI5OTc1MDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDRcIjtcbmNvbnN0IE5PVyA9IERhdGUucGFyc2UoXCIyMDI2LTA5LTMwVDIxOjAwOjAwWlwiKTtcbmNvbnN0IFRJTUUgPSBuZXcgRGF0ZShOT1cpLnRvSVNPU3RyaW5nKCk7XG5jb25zdCBlbmNvZGUgPSBuZXcgVGV4dEVuY29kZXIoKTtcbmNvbnN0IGI2NCA9IChieXRlczogVWludDhBcnJheSkgPT4gYnRvYShTdHJpbmcuZnJvbUNoYXJDb2RlKC4uLmJ5dGVzKSk7XG5hc3luYyBmdW5jdGlvbiBzaGEoYnl0ZXM6IFVpbnQ4QXJyYXkpIHtcbiAgcmV0dXJuIEFycmF5LmZyb20oXG4gICAgbmV3IFVpbnQ4QXJyYXkoXG4gICAgICBhd2FpdCBjcnlwdG8uc3VidGxlLmRpZ2VzdChcIlNIQS0yNTZcIiwgbmV3IFVpbnQ4QXJyYXkoYnl0ZXMpKSxcbiAgICApLFxuICAgIChiKSA9PiBiLnRvU3RyaW5nKDE2KS5wYWRTdGFydCgyLCBcIjBcIiksXG4gICkuam9pbihcIlwiKTtcbn1cbmZ1bmN0aW9uIGRlcihyYXc6IFVpbnQ4QXJyYXkpOiBVaW50OEFycmF5IHtcbiAgY29uc3QgcGFydHMgPSBbcmF3LnNsaWNlKDAsIDMyKSwgcmF3LnNsaWNlKDMyKV0ubWFwKChwYXJ0KSA9PiB7XG4gICAgd2hpbGUgKHBhcnQubGVuZ3RoID4gMSAmJiBwYXJ0WzBdID09PSAwKSBwYXJ0ID0gcGFydC5zbGljZSgxKTtcbiAgICBpZiAocGFydFswXSAmIDEyOCkgcGFydCA9IFVpbnQ4QXJyYXkuZnJvbShbMCwgLi4ucGFydF0pO1xuICAgIHJldHVybiBVaW50OEFycmF5LmZyb20oWzIsIHBhcnQubGVuZ3RoLCAuLi5wYXJ0XSk7XG4gIH0pO1xuICByZXR1cm4gVWludDhBcnJheS5mcm9tKFtcbiAgICA0OCxcbiAgICBwYXJ0c1swXS5sZW5ndGggKyBwYXJ0c1sxXS5sZW5ndGgsXG4gICAgLi4ucGFydHNbMF0sXG4gICAgLi4ucGFydHNbMV0sXG4gIF0pO1xufVxuY29uc3QgaGVhcnRiZWF0ID0gKCkgPT4gKHtcbiAgc21zX3Blcm1pc3Npb246IHRydWUsXG4gIG5ldHdvcms6IFwidmFsaWRhdGVkXCIsXG4gIHRlbGVwaG9ueTogXCJyZWFkeVwiLFxuICBzaW1fc2VsZWN0ZWQ6IHRydWUsXG4gIHNpbV9yZXZpc2lvbl9zaGEyNTY6IFwiYVwiLnJlcGVhdCg2NCksXG4gIGxvY2FsX3BhdXNlOiBmYWxzZSxcbiAgcmVwb3J0ZWRfYXQ6IFRJTUUsXG59KTtcbmNvbnN0IGNhbGxiYWNrID0gKCkgPT4gKHtcbiAgY2FsbGJhY2tfaWQ6IENBTExCQUNLLFxuICBhdHRlbXB0X2lkOiBUQVJHRVQsXG4gIGZlbmNlX3ZlcnNpb246IDEsXG4gIHNlZ21lbnRfaW5kZXg6IDAsXG4gIHNlZ21lbnRfY291bnQ6IDEsXG4gIGJvZHlfc2hhMjU2OiBcImJcIi5yZXBlYXQoNjQpLFxuICBkZXN0aW5hdGlvbl9zaGEyNTY6IFwiY1wiLnJlcGVhdCg2NCksXG4gIGNhbGxiYWNrX2tpbmQ6IFwic2VudFwiLFxuICByZXN1bHRfY29kZTogLTEsXG4gIHRwX3N0YXR1czogbnVsbCxcbiAgb2NjdXJyZWRfYXQ6IFRJTUUsXG59KTtcbmZ1bmN0aW9uIGVudmVsb3BlKFxuICBhY3Rpb24gPSBcImhlYXJ0YmVhdFwiLFxuICBwYXlsb2FkOiB1bmtub3duID0gaGVhcnRiZWF0KCksXG4gIHBhdGNoOiBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPiA9IHt9LFxuKSB7XG4gIHJldHVybiB7XG4gICAgY29udHJhY3RfdmVyc2lvbjogMSxcbiAgICBhY3Rpb24sXG4gICAgZGV2aWNlX2lkOiBERVZJQ0UsXG4gICAgcmVxdWVzdF9pZDogUkVRVUVTVCxcbiAgICBpc3N1ZWRfYXQ6IFRJTUUsXG4gICAgcGF5bG9hZCxcbiAgICAuLi5wYXRjaCxcbiAgfTtcbn1cbmFzeW5jIGZ1bmN0aW9uIGZpeHR1cmUoc3RhdGUgPSBcInBlbmRpbmdcIikge1xuICBjb25zdCBwYWlyID0gYXdhaXQgY3J5cHRvLnN1YnRsZS5nZW5lcmF0ZUtleShcbiAgICB7IG5hbWU6IFwiRUNEU0FcIiwgbmFtZWRDdXJ2ZTogXCJQLTI1NlwiIH0sXG4gICAgdHJ1ZSxcbiAgICBbXCJzaWduXCIsIFwidmVyaWZ5XCJdLFxuICApO1xuICBjb25zdCBzcGtpID0gbmV3IFVpbnQ4QXJyYXkoXG4gICAgYXdhaXQgY3J5cHRvLnN1YnRsZS5leHBvcnRLZXkoXCJzcGtpXCIsIHBhaXIucHVibGljS2V5KSxcbiAgKTtcbiAgY29uc3QgaWQgPSBhd2FpdCBzaGEoc3BraSk7XG4gIGNvbnN0IGNhbGxzOiB7IG5hbWU6IHN0cmluZzsgYXJnczogUmVjb3JkPHN0cmluZywgdW5rbm93bj4gfVtdID0gW107XG4gIGxldCByZXN1bHQ6IHVua25vd24gPSB7XG4gICAgb2JzZXJ2YXRpb25faWQ6IFRBUkdFVCxcbiAgICBpbmdlc3RlZF9hdDogVElNRSxcbiAgICByZXBsYXk6IGZhbHNlLFxuICAgIGNhcnJpZXJfcHJvb2Y6IGZhbHNlLFxuICB9O1xuICBsZXQgZXJyb3I6IHsgY29kZT86IHN0cmluZyB9IHwgbnVsbCA9IG51bGw7XG4gIGNvbnN0IGRlcHM6IEdhdGV3YXlEZXBlbmRlbmNpZXMgPSB7XG4gICAgbm93OiAoKSA9PiBOT1csXG4gICAgdGltZW91dE1zOiA1MCxcbiAgICBycGM6IGFzeW5jIChuYW1lLCBhcmdzKSA9PiB7XG4gICAgICBjYWxscy5wdXNoKHsgbmFtZSwgYXJncyB9KTtcbiAgICAgIGlmIChuYW1lID09PSBcImdhdGV3YXlfZGV2aWNlX2tleV92MVwiKSB7XG4gICAgICAgIHJldHVybiB7XG4gICAgICAgICAgZGF0YToge1xuICAgICAgICAgICAgZGV2aWNlX2lkOiBERVZJQ0UsXG4gICAgICAgICAgICBzdGF0ZSxcbiAgICAgICAgICAgIHB1YmxpY19rZXlfc3BraV9iYXNlNjQ6IGI2NChzcGtpKSxcbiAgICAgICAgICAgIGtleV9zaGEyNTY6IGlkLFxuICAgICAgICAgICAgaW5zdGFsbGF0aW9uX2lkOiBUQVJHRVQsXG4gICAgICAgICAgICBzaWduaW5nX2NlcnRpZmljYXRlX3NoYTI1NjogXCJkXCIucmVwZWF0KDY0KSxcbiAgICAgICAgICB9LFxuICAgICAgICAgIGVycm9yOiBudWxsLFxuICAgICAgICB9O1xuICAgICAgfVxuICAgICAgcmV0dXJuIHsgZGF0YTogcmVzdWx0LCBlcnJvciB9O1xuICAgIH0sXG4gIH07XG4gIGFzeW5jIGZ1bmN0aW9uIHNpZ25lZChcbiAgICB2YWx1ZTogdW5rbm93biA9IGVudmVsb3BlKCksXG4gICAgdGV4dD86IHN0cmluZyxcbiAgICBwYXRjaDogUmVjb3JkPHN0cmluZywgc3RyaW5nPiA9IHt9LFxuICApIHtcbiAgICBjb25zdCBieXRlcyA9IGVuY29kZS5lbmNvZGUodGV4dCA/PyBKU09OLnN0cmluZ2lmeSh2YWx1ZSkpO1xuICAgIGNvbnN0IHNpZ25hdHVyZSA9IGRlcihcbiAgICAgIG5ldyBVaW50OEFycmF5KFxuICAgICAgICBhd2FpdCBjcnlwdG8uc3VidGxlLnNpZ24oXG4gICAgICAgICAgeyBuYW1lOiBcIkVDRFNBXCIsIGhhc2g6IFwiU0hBLTI1NlwiIH0sXG4gICAgICAgICAgcGFpci5wcml2YXRlS2V5LFxuICAgICAgICAgIGJ5dGVzLFxuICAgICAgICApLFxuICAgICAgKSxcbiAgICApO1xuICAgIHJldHVybiBuZXcgUmVxdWVzdChcImh0dHBzOi8vZ2F0ZXdheS50ZXN0L2NvbGxlY3QtYW5kcm9pZC1nYXRld2F5XCIsIHtcbiAgICAgIG1ldGhvZDogXCJQT1NUXCIsXG4gICAgICBoZWFkZXJzOiB7XG4gICAgICAgIFwiY29udGVudC10eXBlXCI6IFwiYXBwbGljYXRpb24vanNvblwiLFxuICAgICAgICBcIlgtQ29sbGVjdC1HYXRld2F5LUtleS1JZFwiOiBpZCxcbiAgICAgICAgXCJYLUNvbGxlY3QtR2F0ZXdheS1TaWduYXR1cmVcIjogYjY0KHNpZ25hdHVyZSksXG4gICAgICAgIC4uLnBhdGNoLFxuICAgICAgfSxcbiAgICAgIGJvZHk6IGJ5dGVzLFxuICAgIH0pO1xuICB9XG4gIHJldHVybiB7XG4gICAgcGFpcixcbiAgICBzcGtpLFxuICAgIGlkLFxuICAgIGNhbGxzLFxuICAgIGRlcHMsXG4gICAgc2lnbmVkLFxuICAgIGhhbmRsZXI6IGNyZWF0ZUdhdGV3YXlIYW5kbGVyKGRlcHMpLFxuICAgIHNldFJlc3VsdDogKHZhbHVlOiB1bmtub3duKSA9PiByZXN1bHQgPSB2YWx1ZSxcbiAgICBzZXRFcnJvcjogKHZhbHVlOiB7IGNvZGU/OiBzdHJpbmcgfSB8IG51bGwpID0+IGVycm9yID0gdmFsdWUsXG4gIH07XG59XG5EZW5vLnRlc3QoXCJyZWFsIHN5bnRoZXRpYyBQLTI1NiBERVIgc2lnbmF0dXJlIGFjY2VwdHMgcGVuZGluZyBrZXktcG9zc2Vzc2lvbiBoZWFsdGggYW5kIHNlcnZlciByZXF1ZXN0IFNIQVwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGYgPSBhd2FpdCBmaXh0dXJlKCk7XG4gIGNvbnN0IGVudiA9IGVudmVsb3BlKCk7XG4gIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYuc2lnbmVkKGVudikpO1xuICBhc3NlcnRFcXVhbHMocmVzcG9uc2Uuc3RhdHVzLCAyMDApO1xuICBjb25zdCBwYXJzZWQgPSBhd2FpdCByZXNwb25zZS5qc29uKCk7XG4gIGFzc2VydEVxdWFscyhwYXJzZWQuYWN0aW9uLCBcImhlYXJ0YmVhdFwiKTtcbiAgYXNzZXJ0RXF1YWxzKHBhcnNlZC5yZXN1bHQuY2Fycmllcl9wcm9vZiwgZmFsc2UpO1xuICBhc3NlcnRFcXVhbHMoZi5jYWxscy5tYXAoKHgpID0+IHgubmFtZSksIFtcbiAgICBcImdhdGV3YXlfZGV2aWNlX2tleV92MVwiLFxuICAgIFwiZ2F0ZXdheV9oZWFydGJlYXRfdjFcIixcbiAgXSk7XG4gIGFzc2VydEVxdWFscyhcbiAgICBmLmNhbGxzWzFdLmFyZ3MucF9yZXF1ZXN0X3NoYTI1NixcbiAgICBhd2FpdCBzaGEoZW5jb2RlLmVuY29kZShKU09OLnN0cmluZ2lmeShlbnYpKSksXG4gICk7XG4gIGFzc2VydEVxdWFscyhyZXNwb25zZS5oZWFkZXJzLmdldChcImNhY2hlLWNvbnRyb2xcIiksIFwibm8tc3RvcmVcIik7XG59KTtcbkRlbm8udGVzdChcInRhbXBlcmVkIHNpZ25lZCBVVEY4IGJvZHkgY2Fubm90IHJlYWNoIGEgbXV0YXRpb24gUlBDXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoKTtcbiAgY29uc3Qgc2lnbmVkID0gYXdhaXQgZi5zaWduZWQoKTtcbiAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBmLmhhbmRsZXIoXG4gICAgbmV3IFJlcXVlc3Qoc2lnbmVkLnVybCwge1xuICAgICAgbWV0aG9kOiBcIlBPU1RcIixcbiAgICAgIGhlYWRlcnM6IHNpZ25lZC5oZWFkZXJzLFxuICAgICAgYm9keTogSlNPTi5zdHJpbmdpZnkoXG4gICAgICAgIGVudmVsb3BlKFwiaGVhcnRiZWF0XCIsIHsgLi4uaGVhcnRiZWF0KCksIGxvY2FsX3BhdXNlOiB0cnVlIH0pLFxuICAgICAgKSxcbiAgICB9KSxcbiAgKTtcbiAgYXNzZXJ0RXF1YWxzKHJlc3BvbnNlLnN0YXR1cywgNDAxKTtcbiAgYXNzZXJ0RXF1YWxzKGYuY2FsbHMubGVuZ3RoLCAxKTtcbn0pO1xuRGVuby50ZXN0KFwiZGlmZmVyZW50IGdlbmVyYXRlZCBwcml2YXRlIGtleSBjYW5ub3QgYXV0aG9yaXplIGVucm9sbGVkIGlkZW50aXR5XCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoKTtcbiAgY29uc3Qgb3RoZXIgPSBhd2FpdCBmaXh0dXJlKCk7XG4gIGNvbnN0IHJlcXVlc3QgPSBhd2FpdCBvdGhlci5zaWduZWQodW5kZWZpbmVkLCB1bmRlZmluZWQsIHtcbiAgICBcIlgtQ29sbGVjdC1HYXRld2F5LUtleS1JZFwiOiBmLmlkLFxuICB9KTtcbiAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBmLmhhbmRsZXIocmVxdWVzdCk7XG4gIGFzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMsIDQwMSk7XG4gIGFzc2VydEVxdWFscyhmLmNhbGxzLmxlbmd0aCwgMSk7XG59KTtcbkRlbm8udGVzdChcIndyb25nIHB1YmxpYy1rZXkgaGVhZGVyIGFuZCBtYWxmb3JtZWQgREVSIGZhaWwgY2xvc2VkXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoKTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIChhd2FpdCBmLmhhbmRsZXIoXG4gICAgICBhd2FpdCBmLnNpZ25lZCh1bmRlZmluZWQsIHVuZGVmaW5lZCwge1xuICAgICAgICBcIlgtQ29sbGVjdC1HYXRld2F5LUtleS1JZFwiOiBcImZcIi5yZXBlYXQoNjQpLFxuICAgICAgfSksXG4gICAgKSkuc3RhdHVzLFxuICAgIDQwMSxcbiAgKTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIChhd2FpdCBmLmhhbmRsZXIoXG4gICAgICBhd2FpdCBmLnNpZ25lZCh1bmRlZmluZWQsIHVuZGVmaW5lZCwge1xuICAgICAgICBcIlgtQ29sbGVjdC1HYXRld2F5LVNpZ25hdHVyZVwiOiBiNjQoXG4gICAgICAgICAgVWludDhBcnJheS5mcm9tKFs0OCwgNiwgMiwgMSwgMCwgMiwgMSwgMV0pLFxuICAgICAgICApLFxuICAgICAgfSksXG4gICAgKSkuc3RhdHVzLFxuICAgIDQwMCxcbiAgKTtcbiAgYXNzZXJ0RXF1YWxzKGYuY2FsbHMubGVuZ3RoLCAxKTtcbn0pO1xuRGVuby50ZXN0KFwiY2Fub25pY2FsIERFUiByb3VuZHRyaXAgYW5kIG5vbm1pbmltYWwgaW50ZWdlcnMgYXJlIGVuZm9yY2VkXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoKTtcbiAgY29uc3QgcmF3ID0gbmV3IFVpbnQ4QXJyYXkoXG4gICAgYXdhaXQgY3J5cHRvLnN1YnRsZS5zaWduKFxuICAgICAgeyBuYW1lOiBcIkVDRFNBXCIsIGhhc2g6IFwiU0hBLTI1NlwiIH0sXG4gICAgICBmLnBhaXIucHJpdmF0ZUtleSxcbiAgICAgIGVuY29kZS5lbmNvZGUoXCJzeW50aGV0aWNcIiksXG4gICAgKSxcbiAgKTtcbiAgYXNzZXJ0RXF1YWxzKEFycmF5LmZyb20oZGVyVG9QMTM2MyhkZXIocmF3KSkpLCBBcnJheS5mcm9tKHJhdykpO1xuICBsZXQgcmVmdXNlZCA9IGZhbHNlO1xuICB0cnkge1xuICAgIGRlclRvUDEzNjMoVWludDhBcnJheS5mcm9tKFs0OCwgNywgMiwgMiwgMCwgMSwgMiwgMSwgMV0pKTtcbiAgfSBjYXRjaCB7XG4gICAgcmVmdXNlZCA9IHRydWU7XG4gIH1cbiAgYXNzZXJ0RXF1YWxzKHJlZnVzZWQsIHRydWUpO1xufSk7XG5mb3IgKFxuICBjb25zdCBbbmFtZSwgdmFsdWVdIG9mIFtcbiAgICBbXG4gICAgICBcImV4cGlyZWRcIixcbiAgICAgIGVudmVsb3BlKFwiaGVhcnRiZWF0XCIsIGhlYXJ0YmVhdCgpLCB7XG4gICAgICAgIGlzc3VlZF9hdDogbmV3IERhdGUoTk9XIC0gMTIwMDAxKS50b0lTT1N0cmluZygpLFxuICAgICAgfSksXG4gICAgXSxcbiAgICBbXG4gICAgICBcImZ1dHVyZVwiLFxuICAgICAgZW52ZWxvcGUoXCJoZWFydGJlYXRcIiwgaGVhcnRiZWF0KCksIHtcbiAgICAgICAgaXNzdWVkX2F0OiBuZXcgRGF0ZShOT1cgKyAxMjAwMDEpLnRvSVNPU3RyaW5nKCksXG4gICAgICB9KSxcbiAgICBdLFxuICAgIFtcbiAgICAgIFwiaW52YWxpZCBjYWxlbmRhclwiLFxuICAgICAgZW52ZWxvcGUoXCJoZWFydGJlYXRcIiwgaGVhcnRiZWF0KCksIHsgaXNzdWVkX2F0OiBcIjIwMjYtMDItMzFUMjE6MDA6MDBaXCIgfSksXG4gICAgXSxcbiAgICBbXCJ1bmtub3duIGFjdGlvblwiLCBlbnZlbG9wZShcImVucm9sbFwiLCB7fSldLFxuICAgIFtcbiAgICAgIFwid3JvbmcgdmVyc2lvblwiLFxuICAgICAgZW52ZWxvcGUoXCJoZWFydGJlYXRcIiwgaGVhcnRiZWF0KCksIHsgY29udHJhY3RfdmVyc2lvbjogMiB9KSxcbiAgICBdLFxuICAgIFtcImJhZCBVVUlEXCIsIGVudmVsb3BlKFwiaGVhcnRiZWF0XCIsIGhlYXJ0YmVhdCgpLCB7IGRldmljZV9pZDogXCJ1bnNhZmVcIiB9KV0sXG4gICAgW1xuICAgICAgXCJleHRyYSBlbnZlbG9wZVwiLFxuICAgICAgZW52ZWxvcGUoXCJoZWFydGJlYXRcIiwgaGVhcnRiZWF0KCksIHsgbWVzc2FnZV9ib2R5OiBcInByaXZhdGVcIiB9KSxcbiAgICBdLFxuICAgIFtcbiAgICAgIFwicGVybWlzc2lvbiBzdHJpbmdcIixcbiAgICAgIGVudmVsb3BlKFwiaGVhcnRiZWF0XCIsIHsgLi4uaGVhcnRiZWF0KCksIHNtc19wZXJtaXNzaW9uOiBcInRydWVcIiB9KSxcbiAgICBdLFxuICAgIFtcbiAgICAgIFwiZXh0cmEgaGVhbHRoIGZpZWxkXCIsXG4gICAgICBlbnZlbG9wZShcImhlYXJ0YmVhdFwiLCB7IC4uLmhlYXJ0YmVhdCgpLCBkZXN0aW5hdGlvbjogXCJwcml2YXRlXCIgfSksXG4gICAgXSxcbiAgICBbXG4gICAgICBcIm51bGwgU0lNIHJldmlzaW9uIHNlbGVjdGVkXCIsXG4gICAgICBlbnZlbG9wZShcImhlYXJ0YmVhdFwiLCB7IC4uLmhlYXJ0YmVhdCgpLCBzaW1fcmV2aXNpb25fc2hhMjU2OiBudWxsIH0pLFxuICAgIF0sXG4gICAgW1xuICAgICAgXCJ1bnNlbGVjdGVkIFNJTSB3aXRoIHJldmlzaW9uXCIsXG4gICAgICBlbnZlbG9wZShcImhlYXJ0YmVhdFwiLCB7IC4uLmhlYXJ0YmVhdCgpLCBzaW1fc2VsZWN0ZWQ6IGZhbHNlIH0pLFxuICAgIF0sXG4gICAgW1xuICAgICAgXCJpbnZhbGlkIG5ldHdvcmtcIixcbiAgICAgIGVudmVsb3BlKFwiaGVhcnRiZWF0XCIsIHsgLi4uaGVhcnRiZWF0KCksIG5ldHdvcms6IFwib25saW5lXCIgfSksXG4gICAgXSxcbiAgICBbXG4gICAgICBcInVuc3VwcG9ydGVkIGNhbGxiYWNrIGNvbmNsdXNpb25cIixcbiAgICAgIGVudmVsb3BlKFwiY2FsbGJhY2tcIiwgeyAuLi5jYWxsYmFjaygpLCBkZWxpdmVyZWQ6IHRydWUgfSksXG4gICAgXSxcbiAgICBbXG4gICAgICBcImZyYWN0aW9uYWwgc2VnbWVudFwiLFxuICAgICAgZW52ZWxvcGUoXCJjYWxsYmFja1wiLCB7IC4uLmNhbGxiYWNrKCksIHNlZ21lbnRfaW5kZXg6IDAuNSB9KSxcbiAgICBdLFxuICAgIFtcbiAgICAgIFwib3ZlcnNpemVkIHNlZ21lbnQgY291bnRcIixcbiAgICAgIGVudmVsb3BlKFwiY2FsbGJhY2tcIiwgeyAuLi5jYWxsYmFjaygpLCBzZWdtZW50X2NvdW50OiAxMSB9KSxcbiAgICBdLFxuICAgIFtcbiAgICAgIFwic2VnbWVudCBiZXlvbmQgY291bnRcIixcbiAgICAgIGVudmVsb3BlKFwiY2FsbGJhY2tcIiwgeyAuLi5jYWxsYmFjaygpLCBzZWdtZW50X2luZGV4OiAxIH0pLFxuICAgIF0sXG4gICAgW1xuICAgICAgXCJyZXVzZWQgY2FsbGJhY2sgcmVxdWVzdCBVVUlEXCIsXG4gICAgICBlbnZlbG9wZShcImNhbGxiYWNrXCIsIHsgLi4uY2FsbGJhY2soKSwgY2FsbGJhY2tfaWQ6IFJFUVVFU1QgfSksXG4gICAgXSxcbiAgICBbXG4gICAgICBcImNhbGxiYWNrIHJlc3VsdCBib29sZWFuXCIsXG4gICAgICBlbnZlbG9wZShcImNhbGxiYWNrXCIsIHsgLi4uY2FsbGJhY2soKSwgcmVzdWx0X2NvZGU6IHRydWUgfSksXG4gICAgXSxcbiAgICBbXG4gICAgICBcImNhbGxiYWNrIFRQIG92ZXJmbG93XCIsXG4gICAgICBlbnZlbG9wZShcImNhbGxiYWNrXCIsIHsgLi4uY2FsbGJhY2soKSwgdHBfc3RhdHVzOiAyNTYgfSksXG4gICAgXSxcbiAgICBbXG4gICAgICBcImdyYW50IHdpdGggY2xpZW50IGJvZHlcIixcbiAgICAgIGVudmVsb3BlKFwiZGlzcGF0Y2hfZ3JhbnRcIiwgeyBtZXNzYWdlX2JvZHk6IFwicHJpdmF0ZVwiIH0pLFxuICAgIF0sXG4gICAgW1xuICAgICAgXCJyZWNvbmNpbGUgaW52YWxpZCB0YXJnZXRcIixcbiAgICAgIGVudmVsb3BlKFwicmVjb25jaWxlXCIsIHsgdGFyZ2V0X3JlcXVlc3RfaWQ6IG51bGwgfSksXG4gICAgXSxcbiAgXSBhcyBjb25zdFxuKSB7XG4gIERlbm8udGVzdChcInN0cmljdCBlbnZlbG9wZS9wYXlsb2FkIHJlZnVzZXMgXCIgKyBuYW1lLCBhc3luYyAoKSA9PiB7XG4gICAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoKTtcbiAgICBhc3NlcnRFcXVhbHMoKGF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnNpZ25lZCh2YWx1ZSkpKS5zdGF0dXMsIDQwMCk7XG4gICAgYXNzZXJ0RXF1YWxzKGYuY2FsbHMubGVuZ3RoLCAwKTtcbiAgfSk7XG59XG5EZW5vLnRlc3QoXCJkdXBsaWNhdGUgSlNPTiBrZXlzIHJlamVjdGVkIGJlZm9yZSBzaWduYXR1cmUtYXV0aG9yaXplZCBSUENcIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCBmID0gYXdhaXQgZml4dHVyZSgpO1xuICBjb25zdCB0ZXh0ID0gSlNPTi5zdHJpbmdpZnkoZW52ZWxvcGUoKSkucmVwbGFjZShcbiAgICAnXCJjb250cmFjdF92ZXJzaW9uXCI6MScsXG4gICAgJ1wiY29udHJhY3RfdmVyc2lvblwiOjEsXCJjb250cmFjdF92ZXJzaW9uXCI6MScsXG4gICk7XG4gIGFzc2VydEVxdWFscygoYXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYuc2lnbmVkKHVuZGVmaW5lZCwgdGV4dCkpKS5zdGF0dXMsIDQwMCk7XG4gIGFzc2VydEVxdWFscyhmLmNhbGxzLmxlbmd0aCwgMCk7XG59KTtcbkRlbm8udGVzdChcInNpZ25lZCBVbmljb2RlIHRhbXBlciB2ZXJpZmllcyBleGFjdCBieXRlcyByYXRoZXIgdGhhbiByZXNlcmlhbGl6ZWQgSlNPTlwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGYgPSBhd2FpdCBmaXh0dXJlKCk7XG4gIGNvbnN0IHRleHQgPSBKU09OLnN0cmluZ2lmeShlbnZlbG9wZSgpKS5yZXBsYWNlKFxuICAgICdcIm5ldHdvcmtcIjpcInZhbGlkYXRlZFwiJyxcbiAgICAnXCJuZXR3b3JrXCI6XCJ2YWxpZFxcXFx1MDA2MXRlZFwiJyxcbiAgKTtcbiAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQodW5kZWZpbmVkLCB0ZXh0KSk7XG4gIGFzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMsIDIwMCk7XG4gIGFzc2VydEVxdWFscyhcbiAgICBmLmNhbGxzWzFdLmFyZ3MucF9yZXF1ZXN0X3NoYTI1NixcbiAgICBhd2FpdCBzaGEoZW5jb2RlLmVuY29kZSh0ZXh0KSksXG4gICk7XG59KTtcbkRlbm8udGVzdChcIlBPU1Qtb25seSBhbmQgb3ZlcnNpemVkL2ludmFsaWQgVVRGOCBib2RpZXMgcmVhY2ggbm8gUlBDXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoKTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIChhd2FpdCBmLmhhbmRsZXIobmV3IFJlcXVlc3QoXCJodHRwczovL2dhdGV3YXkudGVzdFwiLCB7IG1ldGhvZDogXCJHRVRcIiB9KSkpXG4gICAgICAuc3RhdHVzLFxuICAgIDQwNSxcbiAgKTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIChhd2FpdCBmLmhhbmRsZXIoXG4gICAgICBuZXcgUmVxdWVzdChcImh0dHBzOi8vZ2F0ZXdheS50ZXN0XCIsIHtcbiAgICAgICAgbWV0aG9kOiBcIlBPU1RcIixcbiAgICAgICAgaGVhZGVyczogeyBcImNvbnRlbnQtdHlwZVwiOiBcImFwcGxpY2F0aW9uL2pzb25cIiB9LFxuICAgICAgICBib2R5OiBcIiBcIi5yZXBlYXQoODE5MyksXG4gICAgICB9KSxcbiAgICApKS5zdGF0dXMsXG4gICAgNDEzLFxuICApO1xuICBhc3NlcnRFcXVhbHMoXG4gICAgKGF3YWl0IGYuaGFuZGxlcihcbiAgICAgIG5ldyBSZXF1ZXN0KFwiaHR0cHM6Ly9nYXRld2F5LnRlc3RcIiwge1xuICAgICAgICBtZXRob2Q6IFwiUE9TVFwiLFxuICAgICAgICBoZWFkZXJzOiB7IFwiY29udGVudC10eXBlXCI6IFwiYXBwbGljYXRpb24vanNvblwiIH0sXG4gICAgICAgIGJvZHk6IFVpbnQ4QXJyYXkuZnJvbShbMjU1XSksXG4gICAgICB9KSxcbiAgICApKS5zdGF0dXMsXG4gICAgNDAwLFxuICApO1xuICBhc3NlcnRFcXVhbHMoZi5jYWxscy5sZW5ndGgsIDApO1xufSk7XG5EZW5vLnRlc3QoXCJyZXZva2VkIGtleSBwZXJtaXRzIG9ubHkgYm91bmRlZCByZWNvbmNpbGlhdGlvbiBhbmQgcHJpb3ItYXJtIGNhbGxiYWNrIHJvdXRlc1wiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGYgPSBhd2FpdCBmaXh0dXJlKFwicmV2b2tlZFwiKTtcbiAgYXNzZXJ0RXF1YWxzKChhd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoKSkpLnN0YXR1cywgNDAzKTtcbiAgYXNzZXJ0RXF1YWxzKGYuY2FsbHMubGVuZ3RoLCAxKTtcbiAgZi5zZXRSZXN1bHQoe1xuICAgIHRhcmdldF9yZXF1ZXN0X2lkOiBUQVJHRVQsXG4gICAgb3V0Y29tZTogXCJ1bmtub3duXCIsXG4gICAgcmVjb3JkZWRfYWN0aW9uOiBudWxsLFxuICAgIHJlY29yZGVkX3Jlc3VsdDogbnVsbCxcbiAgfSk7XG4gIGFzc2VydEVxdWFscyhcbiAgICAoYXdhaXQgZi5oYW5kbGVyKFxuICAgICAgYXdhaXQgZi5zaWduZWQoZW52ZWxvcGUoXCJyZWNvbmNpbGVcIiwgeyB0YXJnZXRfcmVxdWVzdF9pZDogVEFSR0VUIH0pKSxcbiAgICApKS5zdGF0dXMsXG4gICAgMjAwLFxuICApO1xuICBmLnNldFJlc3VsdCh7XG4gICAgY2FsbGJhY2tfaWQ6IENBTExCQUNLLFxuICAgIHJlY29yZGVkX2F0OiBUSU1FLFxuICAgIHJlcGxheTogZmFsc2UsXG4gICAgY2Fycmllcl9wcm9vZjogZmFsc2UsXG4gIH0pO1xuICBhc3NlcnRFcXVhbHMoXG4gICAgKGF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnNpZ25lZChlbnZlbG9wZShcImNhbGxiYWNrXCIsIGNhbGxiYWNrKCkpKSkpLnN0YXR1cyxcbiAgICAyMDAsXG4gICk7XG4gIGYuc2V0RXJyb3IoeyBjb2RlOiBcIjQyNTAxXCIgfSk7XG4gIGFzc2VydEVxdWFscyhcbiAgICAoYXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYuc2lnbmVkKGVudmVsb3BlKFwiY2FsbGJhY2tcIiwgY2FsbGJhY2soKSkpKSkuc3RhdHVzLFxuICAgIDQwMyxcbiAgKTtcbn0pO1xuRGVuby50ZXN0KFwiZGlzcGF0Y2ggaXMgc3RhYmxlIGF1dGhvcml0eS1wZW5kaW5nIHJlZnVzYWwgd2l0aCBubyBib2R5IGRlc3RpbmF0aW9uIG9yIGdyYW50XCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoXCJhY3RpdmVcIik7XG4gIGYuc2V0UmVzdWx0KHtcbiAgICBvazogZmFsc2UsXG4gICAgY29kZTogXCJHQVRFV0FZX0RJU1BBVENIX0FVVEhPUklUWV9QRU5ESU5HXCIsXG4gICAgZGV2aWNlX2lkOiBERVZJQ0UsXG4gICAgcmVxdWVzdF9pZDogUkVRVUVTVCxcbiAgICByZXBsYXk6IGZhbHNlLFxuICB9KTtcbiAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBmLmhhbmRsZXIoXG4gICAgYXdhaXQgZi5zaWduZWQoZW52ZWxvcGUoXCJkaXNwYXRjaF9ncmFudFwiLCB7fSkpLFxuICApO1xuICBhc3NlcnRFcXVhbHMocmVzcG9uc2Uuc3RhdHVzLCAyMDApO1xuICBhc3NlcnRFcXVhbHMoT2JqZWN0LmtleXMoKGF3YWl0IHJlc3BvbnNlLmpzb24oKSkucmVzdWx0KS5zb3J0KCksIFtcbiAgICBcImNvZGVcIixcbiAgICBcImRldmljZV9pZFwiLFxuICAgIFwib2tcIixcbiAgICBcInJlcGxheVwiLFxuICAgIFwicmVxdWVzdF9pZFwiLFxuICBdKTtcbn0pO1xuRGVuby50ZXN0KFwic3RvcmVkIHJlcXVlc3QgcmVjb25jaWxpYXRpb24gdmFsaWRhdGVzIG5lc3RlZCBib3VuZGVkIHJlc3VsdCByYXRoZXIgdGhhbiBsZWFraW5nIGV4dHJhIGtleXNcIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCBmID0gYXdhaXQgZml4dHVyZSgpO1xuICBmLnNldFJlc3VsdCh7XG4gICAgdGFyZ2V0X3JlcXVlc3RfaWQ6IFRBUkdFVCxcbiAgICBvdXRjb21lOiBcInJlY29yZGVkXCIsXG4gICAgcmVjb3JkZWRfYWN0aW9uOiBcImRpc3BhdGNoX2dyYW50XCIsXG4gICAgcmVjb3JkZWRfcmVzdWx0OiB7XG4gICAgICBvazogZmFsc2UsXG4gICAgICBjb2RlOiBcIkdBVEVXQVlfRElTUEFUQ0hfQVVUSE9SSVRZX1BFTkRJTkdcIixcbiAgICAgIGRldmljZV9pZDogREVWSUNFLFxuICAgICAgcmVxdWVzdF9pZDogVEFSR0VULFxuICAgICAgcmVwbGF5OiBmYWxzZSxcbiAgICB9LFxuICB9KTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIChhd2FpdCBmLmhhbmRsZXIoXG4gICAgICBhd2FpdCBmLnNpZ25lZChlbnZlbG9wZShcInJlY29uY2lsZVwiLCB7IHRhcmdldF9yZXF1ZXN0X2lkOiBUQVJHRVQgfSkpLFxuICAgICkpLnN0YXR1cyxcbiAgICAyMDAsXG4gICk7XG4gIGYuc2V0UmVzdWx0KHtcbiAgICB0YXJnZXRfcmVxdWVzdF9pZDogVEFSR0VULFxuICAgIG91dGNvbWU6IFwicmVjb3JkZWRcIixcbiAgICByZWNvcmRlZF9hY3Rpb246IFwiY2FsbGJhY2tcIixcbiAgICByZWNvcmRlZF9yZXN1bHQ6IHtcbiAgICAgIGNhbGxiYWNrX2lkOiBDQUxMQkFDSyxcbiAgICAgIHJlY29yZGVkX2F0OiBUSU1FLFxuICAgICAgcmVwbGF5OiBmYWxzZSxcbiAgICAgIGNhcnJpZXJfcHJvb2Y6IGZhbHNlLFxuICAgICAgbWVzc2FnZV9ib2R5OiBcInByaXZhdGVcIixcbiAgICB9LFxuICB9KTtcbiAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBmLmhhbmRsZXIoXG4gICAgYXdhaXQgZi5zaWduZWQoZW52ZWxvcGUoXCJyZWNvbmNpbGVcIiwgeyB0YXJnZXRfcmVxdWVzdF9pZDogVEFSR0VUIH0pKSxcbiAgKTtcbiAgYXNzZXJ0RXF1YWxzKHJlc3BvbnNlLnN0YXR1cywgNTAyKTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIGF3YWl0IHJlc3BvbnNlLnRleHQoKSxcbiAgICAne1wib2tcIjpmYWxzZSxcImNvZGVcIjpcIkdBVEVXQVlfT1VUQ09NRV9VTktOT1dOXCJ9JyxcbiAgKTtcbn0pO1xuRGVuby50ZXN0KFwibWFsZm9ybWVkIHN1Y2Nlc3MgcHJvdmlkZXIgZGlhZ25vc3RpY3MgYW5kIGRlYWRsaW5lIHJldHVybiBzYWZlIHVua25vd24gd2l0aG91dCByZXRyeVwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGYgPSBhd2FpdCBmaXh0dXJlKCk7XG4gIGYuc2V0UmVzdWx0KHtcbiAgICBvYnNlcnZhdGlvbl9pZDogVEFSR0VULFxuICAgIGluZ2VzdGVkX2F0OiBUSU1FLFxuICAgIHJlcGxheTogZmFsc2UsXG4gICAgY2Fycmllcl9wcm9vZjogZmFsc2UsXG4gICAgZGVzdGluYXRpb246IFwicHJpdmF0ZVwiLFxuICB9KTtcbiAgYXNzZXJ0RXF1YWxzKChhd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoKSkpLnN0YXR1cywgNTAyKTtcbiAgZi5zZXRFcnJvcih7IGNvZGU6IFwiWFgwMDBcIiB9KTtcbiAgYXNzZXJ0RXF1YWxzKChhd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoKSkpLnN0YXR1cywgNTAzKTtcbiAgY29uc3Qgb2xkID0gZi5kZXBzLnJwYztcbiAgZi5kZXBzLnJwYyA9IChuYW1lLCBhcmdzLCBzaWduYWwpID0+XG4gICAgbmFtZSA9PT0gXCJnYXRld2F5X2RldmljZV9rZXlfdjFcIlxuICAgICAgPyBvbGQobmFtZSwgYXJncywgc2lnbmFsKVxuICAgICAgOiBuZXcgUHJvbWlzZSgoKSA9PiB7fSk7XG4gIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYuc2lnbmVkKCkpO1xuICBhc3NlcnRFcXVhbHMocmVzcG9uc2Uuc3RhdHVzLCA1MDQpO1xuICBhc3NlcnRFcXVhbHMoKGF3YWl0IHJlc3BvbnNlLmpzb24oKSkuY29kZSwgXCJHQVRFV0FZX09VVENPTUVfVU5LTk9XTlwiKTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIGYuY2FsbHMuZmlsdGVyKChjKSA9PiBjLm5hbWUgPT09IFwiZ2F0ZXdheV9oZWFydGJlYXRfdjFcIikubGVuZ3RoLFxuICAgIDIsXG4gICk7XG59KTtcbkRlbm8udGVzdChcImV4YWN0IHJlcGxheSByZXR1cm5zIG9yaWdpbmFsIG9ic2VydmF0aW9uIHJhdGhlciB0aGFuIGEgc2Vjb25kIG11dGF0aW9uIHJvdXRlXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoKTtcbiAgY29uc3QgcmVxdWVzdCA9IGF3YWl0IGYuc2lnbmVkKCk7XG4gIGFzc2VydEVxdWFscygoYXdhaXQgZi5oYW5kbGVyKHJlcXVlc3QpKS5zdGF0dXMsIDIwMCk7XG4gIGYuc2V0UmVzdWx0KHtcbiAgICBvYnNlcnZhdGlvbl9pZDogVEFSR0VULFxuICAgIGluZ2VzdGVkX2F0OiBUSU1FLFxuICAgIHJlcGxheTogdHJ1ZSxcbiAgICBjYXJyaWVyX3Byb29mOiBmYWxzZSxcbiAgfSk7XG4gIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYuc2lnbmVkKCkpO1xuICBhc3NlcnRFcXVhbHMocmVzcG9uc2Uuc3RhdHVzLCAyMDApO1xuICBhc3NlcnRFcXVhbHMoKGF3YWl0IHJlc3BvbnNlLmpzb24oKSkucmVzdWx0LnJlcGxheSwgdHJ1ZSk7XG59KTtcbkRlbm8udGVzdChcInNsb3cgYm9keSByZWFkZXIgaXMgYm91bmRlZCBhbmQgY2Fubm90IHJlYWNoIGFueSBzZXJ2aWNlIFJQQ1wiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGYgPSBhd2FpdCBmaXh0dXJlKCk7XG4gIGxldCBjYW5jZWxlZCA9IGZhbHNlO1xuICBjb25zdCBzdHJlYW0gPSBuZXcgUmVhZGFibGVTdHJlYW08VWludDhBcnJheT4oe1xuICAgIGNhbmNlbCgpIHtcbiAgICAgIGNhbmNlbGVkID0gdHJ1ZTtcbiAgICB9LFxuICB9KTtcbiAgY29uc3QgcmVxdWVzdCA9IG5ldyBSZXF1ZXN0KFwiaHR0cHM6Ly9nYXRld2F5LnRlc3RcIiwge1xuICAgIG1ldGhvZDogXCJQT1NUXCIsXG4gICAgaGVhZGVyczogeyBcImNvbnRlbnQtdHlwZVwiOiBcImFwcGxpY2F0aW9uL2pzb25cIiB9LFxuICAgIGJvZHk6IHN0cmVhbSxcbiAgfSk7XG4gIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgZi5oYW5kbGVyKHJlcXVlc3QpO1xuICBhc3NlcnRFcXVhbHMocmVzcG9uc2Uuc3RhdHVzID49IDQwMCwgdHJ1ZSk7XG4gIGFzc2VydEVxdWFscyhmLmNhbGxzLmxlbmd0aCwgMCk7XG4gIGFzc2VydEVxdWFscyhjYW5jZWxlZCwgdHJ1ZSk7XG59KTtcbkRlbm8udGVzdChcIm1hbGZvcm1lZCBsYXJnZSBzZXJ2aWNlIHN1Y2Nlc3Mgc3RheXMgb3V0Y29tZS11bmtub3duIGFuZCByZWRhY3RlZFwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGYgPSBhd2FpdCBmaXh0dXJlKCk7XG4gIGYuc2V0UmVzdWx0KHsgcHJpdmF0ZV9ib2R5OiBcInByaXZhdGVcIi5yZXBlYXQoMjAwMCkgfSk7XG4gIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYuc2lnbmVkKCkpO1xuICBhc3NlcnRFcXVhbHMocmVzcG9uc2Uuc3RhdHVzLCA1MDIpO1xuICBhc3NlcnRFcXVhbHMoXG4gICAgYXdhaXQgcmVzcG9uc2UudGV4dCgpLFxuICAgICd7XCJva1wiOmZhbHNlLFwiY29kZVwiOlwiR0FURVdBWV9PVVRDT01FX1VOS05PV05cIn0nLFxuICApO1xufSk7XG4iXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IkFBQUEsU0FBUyxZQUFZLFFBQVEsNEJBQTRCO0FBQ3pELFNBQ0Usb0JBQW9CLEVBQ3BCLFVBQVUsUUFFTCxlQUFlO0FBQ3RCLE1BQU0sU0FBUztBQUNmLE1BQU0sVUFBVTtBQUNoQixNQUFNLFNBQVM7QUFDZixNQUFNLFdBQVc7QUFDakIsTUFBTSxNQUFNLEtBQUssS0FBSyxDQUFDO0FBQ3ZCLE1BQU0sT0FBTyxJQUFJLEtBQUssS0FBSyxXQUFXO0FBQ3RDLE1BQU0sU0FBUyxJQUFJO0FBQ25CLE1BQU0sTUFBTSxDQUFDLFFBQXNCLEtBQUssT0FBTyxZQUFZLElBQUk7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
// denoCacheMetadata=13056920643601893985,2424706315858976254
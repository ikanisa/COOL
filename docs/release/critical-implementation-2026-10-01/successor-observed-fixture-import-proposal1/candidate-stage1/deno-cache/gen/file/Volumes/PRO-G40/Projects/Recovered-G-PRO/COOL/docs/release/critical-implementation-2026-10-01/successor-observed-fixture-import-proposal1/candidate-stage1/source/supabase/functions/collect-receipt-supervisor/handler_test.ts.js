import { createSupervisorHandler } from "./handler.ts";
const ID = "99800000-0000-4000-8000-000000000001";
const REQUEST = "99800000-0000-4000-8000-000000000002";
const TARGET = "99800000-0000-4000-8000-000000000003";
const NOW = Date.parse("2026-09-30T23:30:00Z");
const TIME = new Date(NOW).toISOString();
const EXPIRES = new Date(NOW + 86400000).toISOString();
const encode = new TextEncoder();
const b64 = (b)=>btoa(String.fromCharCode(...b));
async function digest(b) {
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(b))), (v)=>v.toString(16).padStart(2, "0")).join("");
}
function assert(v) {
  if (!v) throw Error("assertion_failed");
}
function equal(a, b) {
  assert(JSON.stringify(a) === JSON.stringify(b));
}
function der(raw) {
  const parts = [
    raw.slice(0, 32),
    raw.slice(32)
  ].map((p)=>{
    while(p.length > 1 && p[0] === 0)p = p.slice(1);
    if (p[0] & 128) p = Uint8Array.from([
      0,
      ...p
    ]);
    return Uint8Array.from([
      2,
      p.length,
      ...p
    ]);
  });
  return Uint8Array.from([
    48,
    parts[0].length + parts[1].length,
    ...parts[0],
    ...parts[1]
  ]);
}
const envelope = (action = "shadow_health", payload = {})=>({
    contract_version: 1,
    audience: "collect.receipt-supervisor.v1/lhbowpbcpwoiparwnwgt",
    action,
    principal_id: ID,
    request_id: REQUEST,
    issued_at: TIME,
    payload
  });
const observation = (action = "shadow_health", request = REQUEST)=>({
    contract_version: 1,
    principal_id: ID,
    request_id: request,
    action,
    observed_at: TIME,
    expires_at: EXPIRES,
    scope: "rw_receipt_shadow",
    mode: "Shadow",
    business_handled: false,
    financial_action: false,
    send_action: false,
    ...action === "shadow_health" ? {
      sample_valid_until: new Date(NOW + 60000).toISOString(),
      queued_count: 3,
      unknown_count: 1,
      failed_no_send_count: 2,
      dispatch_enabled: false
    } : {}
  });
async function fixture(state = "active", timeout = 5000) {
  const pair = await crypto.subtle.generateKey({
    name: "ECDSA",
    namedCurve: "P-256"
  }, true, [
    "sign",
    "verify"
  ]);
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", pair.publicKey));
  const keyHash = await digest(spki);
  const calls = [];
  let key = {
    contract_version: 1,
    principal_id: ID,
    state,
    scope: "rw_receipt_shadow",
    public_key_spki_base64: b64(spki),
    key_sha256: keyHash,
    expires_at: EXPIRES
  };
  let result = observation();
  let error = null;
  let pendingAt = null;
  let aborted = false;
  const dependencies = {
    now: ()=>NOW,
    timeoutMs: timeout,
    rpc: async (name, args, signal)=>{
      calls.push({
        name,
        args
      });
      if (name === pendingAt) return await new Promise((resolve)=>signal.addEventListener("abort", ()=>{
          aborted = true;
          resolve({
            data: null,
            error: {
              code: "cancelled"
            }
          });
        }, {
          once: true
        }));
      if (error) return {
        data: null,
        error
      };
      return {
        data: name === "receipt_supervisor_key_v1" ? key : result,
        error: null
      };
    }
  };
  const handler = createSupervisorHandler(dependencies);
  async function request(body = envelope(), patch = {}, raw, method = "POST", url = "https://example.invalid/supervisor") {
    const bytes = encode.encode(raw ?? JSON.stringify(body));
    const signature = der(new Uint8Array(await crypto.subtle.sign({
      name: "ECDSA",
      hash: "SHA-256"
    }, pair.privateKey, new Uint8Array(bytes))));
    return new Request(url, {
      method,
      headers: {
        "content-type": "application/json",
        "X-Collect-Supervisor-Key-Id": keyHash,
        "X-Collect-Supervisor-Signature": b64(signature),
        ...patch
      },
      ...method === "POST" ? {
        body: bytes
      } : {}
    });
  }
  return {
    handler,
    request,
    calls,
    setKey: (v)=>key = v,
    key: ()=>key,
    setResult: (v)=>result = v,
    setError: (v)=>error = v,
    setPending: (v)=>pendingAt = v,
    aborted: ()=>aborted
  };
}
Deno.test("real signed P256 health maps only to narrow service RPCs", async ()=>{
  const f = await fixture();
  const r = await f.handler(await f.request());
  equal(r.status, 200);
  equal(f.calls.map((x)=>x.name), [
    "receipt_supervisor_key_v1",
    "receipt_supervisor_observe_v1"
  ]);
  const args = f.calls[1].args;
  equal(args.p_action, "shadow_health");
  equal(args.p_key_sha256, f.key().key_sha256);
  assert(typeof args.p_request_sha256 === "string" && args.p_request_sha256.length === 64);
  equal((await r.json()).result.send_action, false);
  equal(r.headers.get("cache-control"), "no-store");
});
for (const [name, patch] of Object.entries({
  principal: {
    principal_id: "ABCDEF00-0000-4000-8000-000000000001"
  },
  request: {
    request_id: "ABCDEF00-0000-4000-8000-000000000002"
  },
  target: {
    action: "reconcile",
    payload: {
      target_request_id: "ABCDEF00-0000-4000-8000-000000000003"
    }
  }
})){
  Deno.test("canonical lowercase UUID required for " + name + " before RPC", async ()=>{
    const f = await fixture();
    const r = await f.handler(await f.request({
      ...envelope(),
      ...patch
    }));
    equal(r.status, 400);
    equal(f.calls.length, 0);
  });
}
for (const raw of [
  String.raw`{"x":"\uXXXX"}`,
  String.raw`{"x":"\q"}`
]){
  Deno.test("malformed string escape remains a client refusal: " + raw, async ()=>{
    const f = await fixture();
    const r = await f.handler(await f.request(undefined, {}, raw));
    equal(r.status, 400);
    equal(await r.json(), {
      ok: false,
      code: "SUPERVISOR_REQUEST_INVALID"
    });
    equal(f.calls.length, 0);
  });
}
Deno.test("oversized streamed body uses supervisor refusal before RPC", async ()=>{
  const f = await fixture();
  const r = await f.handler(await f.request(undefined, {}, "x".repeat(8193)));
  equal(r.status, 413);
  equal(await r.json(), {
    ok: false,
    code: "SUPERVISOR_BODY_TOO_LARGE"
  });
  equal(f.calls.length, 0);
});
Deno.test("pending identity can prove key but cannot read health", async ()=>{
  const f = await fixture("pending");
  f.setResult(observation("prove_key"));
  equal((await f.handler(await f.request(envelope("prove_key")))).status, 200);
  equal((await f.handler(await f.request())).status, 403);
  equal(f.calls.filter((x)=>x.name === "receipt_supervisor_observe_v1").length, 1);
});
for (const [name, patch] of Object.entries({
  audience: {
    audience: "other_project"
  },
  version: {
    contract_version: 2
  },
  send: {
    action: "send"
  },
  enqueue: {
    action: "ensure_receipt"
  },
  member: {
    principal_id: "not_uuid"
  },
  unknownField: {
    recipient: "+250788000000"
  },
  stale: {
    issued_at: new Date(NOW - 31000).toISOString()
  },
  future: {
    issued_at: new Date(NOW + 11000).toISOString()
  },
  date: {
    issued_at: "2026-02-30T00:00:00Z"
  },
  payload: {
    payload: {
      destination: "+250788000000"
    }
  },
  reconcile: {
    action: "reconcile",
    payload: {
      target_request_id: "bad"
    }
  }
})){
  Deno.test("closed signed protocol refuses " + name + " before key lookup", async ()=>{
    const f = await fixture();
    equal((await f.handler(await f.request({
      ...envelope(),
      ...patch
    }))).status, 400);
    equal(f.calls.length, 0);
  });
}
for (const [name, raw] of Object.entries({
  duplicate: JSON.stringify(envelope()).replace('"action":"shadow_health"', '"action":"prove_key","action":"shadow_health"'),
  extraText: JSON.stringify(envelope()) + " trailing",
  bom: "\ufeff" + JSON.stringify(envelope()),
  nested: JSON.stringify({
    ...envelope(),
    payload: Array.from({
      length: 10
    }).reduce((v)=>({
        x: v
      }), {})
  })
})){
  Deno.test("strict byte parser refuses " + name, async ()=>{
    const f = await fixture();
    equal((await f.handler(await f.request(undefined, {}, raw))).status, 400);
    equal(f.calls.length, 0);
  });
}
Deno.test("signed bytes cannot be modified without losing proof", async ()=>{
  const f = await fixture();
  const original = await f.request();
  const altered = JSON.stringify({
    ...envelope(),
    request_id: TARGET
  });
  const r = await f.handler(new Request(original.url, {
    method: "POST",
    headers: original.headers,
    body: altered
  }));
  equal(r.status, 401);
  equal(f.calls.length, 1);
});
Deno.test("gateway signature envelope cannot authorize supervisor calls", async ()=>{
  const f = await fixture();
  equal((await f.handler(await f.request({
    contract_version: 1,
    action: "heartbeat",
    device_id: ID,
    request_id: REQUEST,
    issued_at: TIME,
    payload: {}
  }))).status, 400);
  equal(f.calls.length, 0);
});
for (const [name, patch] of Object.entries({
  revoked: {
    state: "revoked"
  },
  scope: {
    scope: "platform_owner"
  },
  keyHash: {
    key_sha256: "a".repeat(64)
  },
  expiry: {
    expires_at: TIME
  },
  spki: {
    public_key_spki_base64: "invalid"
  },
  secret: {
    private_key: "secret"
  }
})){
  Deno.test("strict key readback refuses " + name, async ()=>{
    const f = await fixture();
    f.setKey({
      ...f.key(),
      ...patch
    });
    equal((await f.handler(await f.request())).status, 401);
    equal(f.calls.length, 1);
  });
}
for (const [name, patch] of Object.entries({
  send: {
    send_action: true
  },
  finance: {
    financial_action: true
  },
  handled: {
    business_handled: true
  },
  mode: {
    mode: "Live"
  },
  principal: {
    principal_id: TARGET
  },
  request: {
    request_id: TARGET
  },
  fraction: {
    queued_count: 1.5
  },
  overflow: {
    queued_count: 1e9 + 1
  },
  foreignExpiry: {
    expires_at: new Date(NOW + 90000000).toISOString()
  },
  futureObservation: {
    observed_at: new Date(NOW + 11000).toISOString()
  },
  renewedSample: {
    sample_valid_until: new Date(NOW + 61000).toISOString()
  },
  privateField: {
    body: "private"
  }
})){
  Deno.test("post-proof malformed outcome remains unknown: " + name, async ()=>{
    const f = await fixture();
    f.setResult({
      ...observation(),
      ...patch
    });
    const r = await f.handler(await f.request());
    equal(r.status, 502);
    equal((await r.json()).code, "SUPERVISOR_OUTCOME_UNKNOWN");
  });
}
Deno.test("reconciliation uses original request UUID and historical observation", async ()=>{
  const f = await fixture();
  const historical = {
    ...observation("shadow_health", TARGET),
    observed_at: new Date(NOW - 100000).toISOString(),
    sample_valid_until: new Date(NOW - 40000).toISOString()
  };
  f.setResult({
    contract_version: 1,
    target_request_id: TARGET,
    status: "recorded",
    receipt: historical
  });
  const r = await f.handler(await f.request(envelope("reconcile", {
    target_request_id: TARGET
  })));
  equal(r.status, 200);
  equal(f.calls[1].name, "receipt_supervisor_reconcile_v1");
  equal(f.calls[1].args.p_target_request_id, TARGET);
  equal((await r.json()).result.receipt.sample_valid_until, historical.sample_valid_until);
});
for (const status of [
  "not_recorded",
  "in_progress"
]){
  Deno.test("lookup " + status + " conveys no receipt or replay", async ()=>{
    const f = await fixture();
    f.setResult({
      contract_version: 1,
      target_request_id: TARGET,
      status,
      receipt: null
    });
    equal((await f.handler(await f.request(envelope("reconcile", {
      target_request_id: TARGET
    })))).status, 200);
  });
}
Deno.test("mismatched reconciled receipt stays unknown", async ()=>{
  const f = await fixture();
  f.setResult({
    contract_version: 1,
    target_request_id: TARGET,
    status: "recorded",
    receipt: observation()
  });
  equal((await f.handler(await f.request(envelope("reconcile", {
    target_request_id: TARGET
  })))).status, 502);
});
Deno.test("readback outage aborts within deadline before service action", async ()=>{
  const f = await fixture("active", 70);
  f.setPending("receipt_supervisor_key_v1");
  const r = await f.handler(await f.request());
  equal(r.status, 503);
  equal((await r.json()).code, "SUPERVISOR_AUTH_UNAVAILABLE");
  assert(f.aborted());
  equal(f.calls.length, 1);
});
Deno.test("uncertain post-proof response aborts without retry", async ()=>{
  const f = await fixture("active", 70);
  f.setPending("receipt_supervisor_observe_v1");
  const r = await f.handler(await f.request());
  equal(r.status, 503);
  equal((await r.json()).code, "SUPERVISOR_OUTCOME_UNKNOWN");
  assert(f.aborted());
  equal(f.calls.length, 2);
});
for (const [code, status, label] of [
  [
    "42501",
    403,
    "SUPERVISOR_AUTHORITY_REFUSED"
  ],
  [
    "55P03",
    409,
    "SUPERVISOR_AUTHORITY_BUSY"
  ],
  [
    "22023",
    409,
    "SUPERVISOR_REQUEST_REFUSED"
  ],
  [
    "unknown",
    503,
    "SUPERVISOR_AUTH_UNAVAILABLE"
  ]
]){
  Deno.test("backend " + code + " is redacted", async ()=>{
    const f = await fixture();
    f.setError({
      code
    });
    const r = await f.handler(await f.request());
    equal(r.status, status);
    equal(await r.json(), {
      ok: false,
      code: label
    });
  });
}
Deno.test("method query and malformed DER are rejected before database", async ()=>{
  const f = await fixture();
  equal((await f.handler(await f.request(undefined, {}, undefined, "GET"))).status, 405);
  equal((await f.handler(await f.request(undefined, {}, undefined, "POST", "https://example.invalid/supervisor?rpc=send"))).status, 400);
  equal((await f.handler(await f.request(undefined, {
    "X-Collect-Supervisor-Signature": b64(new Uint8Array(64))
  }))).status, 400);
  equal(f.calls.length, 0);
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2NvbGxlY3QtcmVjZWlwdC1zdXBlcnZpc29yL2hhbmRsZXJfdGVzdC50cyJdLCJzb3VyY2VzQ29udGVudCI6WyJpbXBvcnQge2NyZWF0ZVN1cGVydmlzb3JIYW5kbGVyLCB0eXBlIFN1cGVydmlzb3JEZXBlbmRlbmNpZXN9IGZyb20gXCIuL2hhbmRsZXIudHNcIjtcbmNvbnN0IElEPVwiOTk4MDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAxXCI7XG5jb25zdCBSRVFVRVNUPVwiOTk4MDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAyXCI7XG5jb25zdCBUQVJHRVQ9XCI5OTgwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDNcIjtcbmNvbnN0IE5PVz1EYXRlLnBhcnNlKFwiMjAyNi0wOS0zMFQyMzozMDowMFpcIik7XG5jb25zdCBUSU1FPW5ldyBEYXRlKE5PVykudG9JU09TdHJpbmcoKTtcbmNvbnN0IEVYUElSRVM9bmV3IERhdGUoTk9XKzg2NDAwMDAwKS50b0lTT1N0cmluZygpO1xuY29uc3QgZW5jb2RlPW5ldyBUZXh0RW5jb2RlcigpO1xuY29uc3QgYjY0PShiOlVpbnQ4QXJyYXkpPT5idG9hKFN0cmluZy5mcm9tQ2hhckNvZGUoLi4uYikpO1xuYXN5bmMgZnVuY3Rpb24gZGlnZXN0KGI6VWludDhBcnJheSl7cmV0dXJuIEFycmF5LmZyb20obmV3IFVpbnQ4QXJyYXkoYXdhaXQgY3J5cHRvLnN1YnRsZS5kaWdlc3QoXCJTSEEtMjU2XCIsbmV3IFVpbnQ4QXJyYXkoYikpKSwodik9PnYudG9TdHJpbmcoMTYpLnBhZFN0YXJ0KDIsXCIwXCIpKS5qb2luKFwiXCIpO31cbmZ1bmN0aW9uIGFzc2VydCh2OnVua25vd24pOmFzc2VydHMgdntpZighdil0aHJvdyBFcnJvcihcImFzc2VydGlvbl9mYWlsZWRcIik7fVxuZnVuY3Rpb24gZXF1YWwoYTp1bmtub3duLGI6dW5rbm93bil7YXNzZXJ0KEpTT04uc3RyaW5naWZ5KGEpPT09SlNPTi5zdHJpbmdpZnkoYikpO31cbmZ1bmN0aW9uIGRlcihyYXc6VWludDhBcnJheSl7XG4gY29uc3QgcGFydHM9W3Jhdy5zbGljZSgwLDMyKSxyYXcuc2xpY2UoMzIpXS5tYXAocD0+e1xuICB3aGlsZShwLmxlbmd0aD4xJiZwWzBdPT09MClwPXAuc2xpY2UoMSk7XG4gIGlmKHBbMF0mMTI4KXA9VWludDhBcnJheS5mcm9tKFswLC4uLnBdKTtcbiAgcmV0dXJuIFVpbnQ4QXJyYXkuZnJvbShbMixwLmxlbmd0aCwuLi5wXSk7XG4gfSk7cmV0dXJuIFVpbnQ4QXJyYXkuZnJvbShbNDgscGFydHNbMF0ubGVuZ3RoK3BhcnRzWzFdLmxlbmd0aCwuLi5wYXJ0c1swXSwuLi5wYXJ0c1sxXV0pO1xufVxuY29uc3QgZW52ZWxvcGU9KGFjdGlvbj1cInNoYWRvd19oZWFsdGhcIixwYXlsb2FkOnVua25vd249e30pPT4oe2NvbnRyYWN0X3ZlcnNpb246MSxcbiBhdWRpZW5jZTpcImNvbGxlY3QucmVjZWlwdC1zdXBlcnZpc29yLnYxL2xoYm93cGJjcHdvaXBhcndud2d0XCIsYWN0aW9uLHByaW5jaXBhbF9pZDpJRCxcbiByZXF1ZXN0X2lkOlJFUVVFU1QsaXNzdWVkX2F0OlRJTUUscGF5bG9hZH0pO1xuY29uc3Qgb2JzZXJ2YXRpb249KGFjdGlvbj1cInNoYWRvd19oZWFsdGhcIixyZXF1ZXN0PVJFUVVFU1QpPT4oe2NvbnRyYWN0X3ZlcnNpb246MSxcbiBwcmluY2lwYWxfaWQ6SUQscmVxdWVzdF9pZDpyZXF1ZXN0LGFjdGlvbixvYnNlcnZlZF9hdDpUSU1FLGV4cGlyZXNfYXQ6RVhQSVJFUyxcbiBzY29wZTpcInJ3X3JlY2VpcHRfc2hhZG93XCIsbW9kZTpcIlNoYWRvd1wiLGJ1c2luZXNzX2hhbmRsZWQ6ZmFsc2UsZmluYW5jaWFsX2FjdGlvbjpmYWxzZSxcbiBzZW5kX2FjdGlvbjpmYWxzZSwuLi4oYWN0aW9uPT09XCJzaGFkb3dfaGVhbHRoXCI/e3NhbXBsZV92YWxpZF91bnRpbDpuZXcgRGF0ZShOT1crNjAwMDApLnRvSVNPU3RyaW5nKCksXG4gcXVldWVkX2NvdW50OjMsdW5rbm93bl9jb3VudDoxLGZhaWxlZF9ub19zZW5kX2NvdW50OjIsZGlzcGF0Y2hfZW5hYmxlZDpmYWxzZX06e30pfSk7XG5hc3luYyBmdW5jdGlvbiBmaXh0dXJlKHN0YXRlPVwiYWN0aXZlXCIsdGltZW91dD01MDAwKXtcbiBjb25zdCBwYWlyPWF3YWl0IGNyeXB0by5zdWJ0bGUuZ2VuZXJhdGVLZXkoe25hbWU6XCJFQ0RTQVwiLG5hbWVkQ3VydmU6XCJQLTI1NlwifSx0cnVlLFtcInNpZ25cIixcInZlcmlmeVwiXSk7XG4gY29uc3Qgc3BraT1uZXcgVWludDhBcnJheShhd2FpdCBjcnlwdG8uc3VidGxlLmV4cG9ydEtleShcInNwa2lcIixwYWlyLnB1YmxpY0tleSkpO1xuIGNvbnN0IGtleUhhc2g9YXdhaXQgZGlnZXN0KHNwa2kpO2NvbnN0IGNhbGxzOntuYW1lOnN0cmluZzthcmdzOlJlY29yZDxzdHJpbmcsdW5rbm93bj59W109W107XG4gbGV0IGtleTp1bmtub3duPXtjb250cmFjdF92ZXJzaW9uOjEscHJpbmNpcGFsX2lkOklELHN0YXRlLHNjb3BlOlwicndfcmVjZWlwdF9zaGFkb3dcIixcbiAgcHVibGljX2tleV9zcGtpX2Jhc2U2NDpiNjQoc3BraSksa2V5X3NoYTI1NjprZXlIYXNoLGV4cGlyZXNfYXQ6RVhQSVJFU307XG4gbGV0IHJlc3VsdDp1bmtub3duPW9ic2VydmF0aW9uKCk7bGV0IGVycm9yOntjb2RlPzpzdHJpbmd9fG51bGw9bnVsbDtcbiBsZXQgcGVuZGluZ0F0OnN0cmluZ3xudWxsPW51bGw7bGV0IGFib3J0ZWQ9ZmFsc2U7XG4gY29uc3QgZGVwZW5kZW5jaWVzOlN1cGVydmlzb3JEZXBlbmRlbmNpZXM9e25vdzooKT0+Tk9XLHRpbWVvdXRNczp0aW1lb3V0LHJwYzphc3luYyhuYW1lLGFyZ3Msc2lnbmFsKT0+e1xuICBjYWxscy5wdXNoKHtuYW1lLGFyZ3N9KTtcbiAgaWYobmFtZT09PXBlbmRpbmdBdClyZXR1cm4gYXdhaXQgbmV3IFByb21pc2UocmVzb2x2ZT0+c2lnbmFsLmFkZEV2ZW50TGlzdGVuZXIoXCJhYm9ydFwiLCgpPT57XG4gICBhYm9ydGVkPXRydWU7cmVzb2x2ZSh7ZGF0YTpudWxsLGVycm9yOntjb2RlOlwiY2FuY2VsbGVkXCJ9fSk7XG4gIH0se29uY2U6dHJ1ZX0pKTtcbiAgaWYoZXJyb3IpcmV0dXJue2RhdGE6bnVsbCxlcnJvcn07XG4gIHJldHVybiB7ZGF0YTpuYW1lPT09XCJyZWNlaXB0X3N1cGVydmlzb3Jfa2V5X3YxXCI/a2V5OnJlc3VsdCxlcnJvcjpudWxsfTtcbiB9fTtcbiBjb25zdCBoYW5kbGVyPWNyZWF0ZVN1cGVydmlzb3JIYW5kbGVyKGRlcGVuZGVuY2llcyk7XG4gYXN5bmMgZnVuY3Rpb24gcmVxdWVzdChib2R5OnVua25vd249ZW52ZWxvcGUoKSxwYXRjaDpSZWNvcmQ8c3RyaW5nLHN0cmluZz49e30scmF3PzpzdHJpbmcsbWV0aG9kPVwiUE9TVFwiLHVybD1cImh0dHBzOi8vZXhhbXBsZS5pbnZhbGlkL3N1cGVydmlzb3JcIil7XG4gIGNvbnN0IGJ5dGVzPWVuY29kZS5lbmNvZGUocmF3Pz9KU09OLnN0cmluZ2lmeShib2R5KSk7XG4gIGNvbnN0IHNpZ25hdHVyZT1kZXIobmV3IFVpbnQ4QXJyYXkoYXdhaXQgY3J5cHRvLnN1YnRsZS5zaWduKHtuYW1lOlwiRUNEU0FcIixoYXNoOlwiU0hBLTI1NlwifSxwYWlyLnByaXZhdGVLZXksbmV3IFVpbnQ4QXJyYXkoYnl0ZXMpKSkpO1xuICByZXR1cm4gbmV3IFJlcXVlc3QodXJsLHttZXRob2QsaGVhZGVyczp7XCJjb250ZW50LXR5cGVcIjpcImFwcGxpY2F0aW9uL2pzb25cIixcbiAgIFwiWC1Db2xsZWN0LVN1cGVydmlzb3ItS2V5LUlkXCI6a2V5SGFzaCxcIlgtQ29sbGVjdC1TdXBlcnZpc29yLVNpZ25hdHVyZVwiOmI2NChzaWduYXR1cmUpLC4uLnBhdGNofSxcbiAgIC4uLihtZXRob2Q9PT1cIlBPU1RcIj97Ym9keTpieXRlc306e30pfSk7XG4gfVxuIHJldHVybntoYW5kbGVyLHJlcXVlc3QsY2FsbHMsc2V0S2V5Oih2OnVua25vd24pPT5rZXk9dixrZXk6KCk9PmtleSxcbiAgc2V0UmVzdWx0Oih2OnVua25vd24pPT5yZXN1bHQ9dixzZXRFcnJvcjoodjp7Y29kZTpzdHJpbmd9KT0+ZXJyb3I9dixcbiAgc2V0UGVuZGluZzoodjpzdHJpbmcpPT5wZW5kaW5nQXQ9dixhYm9ydGVkOigpPT5hYm9ydGVkfTtcbn1cbkRlbm8udGVzdChcInJlYWwgc2lnbmVkIFAyNTYgaGVhbHRoIG1hcHMgb25seSB0byBuYXJyb3cgc2VydmljZSBSUENzXCIsYXN5bmMoKT0+e1xuIGNvbnN0IGY9YXdhaXQgZml4dHVyZSgpO2NvbnN0IHI9YXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYucmVxdWVzdCgpKTtlcXVhbChyLnN0YXR1cywyMDApO1xuIGVxdWFsKGYuY2FsbHMubWFwKHg9PngubmFtZSksW1wicmVjZWlwdF9zdXBlcnZpc29yX2tleV92MVwiLFwicmVjZWlwdF9zdXBlcnZpc29yX29ic2VydmVfdjFcIl0pO1xuIGNvbnN0IGFyZ3M9Zi5jYWxsc1sxXS5hcmdzO2VxdWFsKGFyZ3MucF9hY3Rpb24sXCJzaGFkb3dfaGVhbHRoXCIpO2VxdWFsKGFyZ3MucF9rZXlfc2hhMjU2LChmLmtleSgpYXMgUmVjb3JkPHN0cmluZyx1bmtub3duPikua2V5X3NoYTI1Nik7XG4gYXNzZXJ0KHR5cGVvZiBhcmdzLnBfcmVxdWVzdF9zaGEyNTY9PT1cInN0cmluZ1wiJiZhcmdzLnBfcmVxdWVzdF9zaGEyNTYubGVuZ3RoPT09NjQpO1xuIGVxdWFsKChhd2FpdCByLmpzb24oKSkucmVzdWx0LnNlbmRfYWN0aW9uLGZhbHNlKTtlcXVhbChyLmhlYWRlcnMuZ2V0KFwiY2FjaGUtY29udHJvbFwiKSxcIm5vLXN0b3JlXCIpO1xufSk7XG5mb3IoY29uc3QgW25hbWUscGF0Y2hdb2YgT2JqZWN0LmVudHJpZXMoe3ByaW5jaXBhbDp7cHJpbmNpcGFsX2lkOlwiQUJDREVGMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAxXCJ9LHJlcXVlc3Q6e3JlcXVlc3RfaWQ6XCJBQkNERUYwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDJcIn0sdGFyZ2V0OnthY3Rpb246XCJyZWNvbmNpbGVcIixwYXlsb2FkOnt0YXJnZXRfcmVxdWVzdF9pZDpcIkFCQ0RFRjAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwM1wifX19KSl7XG4gRGVuby50ZXN0KFwiY2Fub25pY2FsIGxvd2VyY2FzZSBVVUlEIHJlcXVpcmVkIGZvciBcIituYW1lK1wiIGJlZm9yZSBSUENcIixhc3luYygpPT57XG4gIGNvbnN0IGY9YXdhaXQgZml4dHVyZSgpO2NvbnN0IHI9YXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYucmVxdWVzdCh7Li4uZW52ZWxvcGUoKSwuLi5wYXRjaH0pKTtlcXVhbChyLnN0YXR1cyw0MDApO2VxdWFsKGYuY2FsbHMubGVuZ3RoLDApO1xuIH0pO1xufVxuZm9yKGNvbnN0IHJhdyBvZiBbU3RyaW5nLnJhd2B7XCJ4XCI6XCJcXHVYWFhYXCJ9YCxTdHJpbmcucmF3YHtcInhcIjpcIlxccVwifWBdKXtcbiBEZW5vLnRlc3QoXCJtYWxmb3JtZWQgc3RyaW5nIGVzY2FwZSByZW1haW5zIGEgY2xpZW50IHJlZnVzYWw6IFwiK3Jhdyxhc3luYygpPT57XG4gIGNvbnN0IGY9YXdhaXQgZml4dHVyZSgpO2NvbnN0IHI9YXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYucmVxdWVzdCh1bmRlZmluZWQse30scmF3KSk7ZXF1YWwoci5zdGF0dXMsNDAwKTtlcXVhbChhd2FpdCByLmpzb24oKSx7b2s6ZmFsc2UsY29kZTpcIlNVUEVSVklTT1JfUkVRVUVTVF9JTlZBTElEXCJ9KTtlcXVhbChmLmNhbGxzLmxlbmd0aCwwKTtcbiB9KTtcbn1cbkRlbm8udGVzdChcIm92ZXJzaXplZCBzdHJlYW1lZCBib2R5IHVzZXMgc3VwZXJ2aXNvciByZWZ1c2FsIGJlZm9yZSBSUENcIixhc3luYygpPT57XG4gY29uc3QgZj1hd2FpdCBmaXh0dXJlKCk7Y29uc3Qgcj1hd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5yZXF1ZXN0KHVuZGVmaW5lZCx7fSxcInhcIi5yZXBlYXQoODE5MykpKTtlcXVhbChyLnN0YXR1cyw0MTMpO2VxdWFsKGF3YWl0IHIuanNvbigpLHtvazpmYWxzZSxjb2RlOlwiU1VQRVJWSVNPUl9CT0RZX1RPT19MQVJHRVwifSk7ZXF1YWwoZi5jYWxscy5sZW5ndGgsMCk7XG59KTtcbkRlbm8udGVzdChcInBlbmRpbmcgaWRlbnRpdHkgY2FuIHByb3ZlIGtleSBidXQgY2Fubm90IHJlYWQgaGVhbHRoXCIsYXN5bmMoKT0+e1xuIGNvbnN0IGY9YXdhaXQgZml4dHVyZShcInBlbmRpbmdcIik7Zi5zZXRSZXN1bHQob2JzZXJ2YXRpb24oXCJwcm92ZV9rZXlcIikpO1xuIGVxdWFsKChhd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5yZXF1ZXN0KGVudmVsb3BlKFwicHJvdmVfa2V5XCIpKSkpLnN0YXR1cywyMDApO1xuIGVxdWFsKChhd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5yZXF1ZXN0KCkpKS5zdGF0dXMsNDAzKTtlcXVhbChmLmNhbGxzLmZpbHRlcih4PT54Lm5hbWU9PT1cInJlY2VpcHRfc3VwZXJ2aXNvcl9vYnNlcnZlX3YxXCIpLmxlbmd0aCwxKTtcbn0pO1xuZm9yKGNvbnN0IFtuYW1lLHBhdGNoXW9mIE9iamVjdC5lbnRyaWVzKHthdWRpZW5jZTp7YXVkaWVuY2U6XCJvdGhlcl9wcm9qZWN0XCJ9LHZlcnNpb246e2NvbnRyYWN0X3ZlcnNpb246Mn0sXG4gc2VuZDp7YWN0aW9uOlwic2VuZFwifSxlbnF1ZXVlOnthY3Rpb246XCJlbnN1cmVfcmVjZWlwdFwifSxtZW1iZXI6e3ByaW5jaXBhbF9pZDpcIm5vdF91dWlkXCJ9LFxuIHVua25vd25GaWVsZDp7cmVjaXBpZW50OlwiKzI1MDc4ODAwMDAwMFwifSxzdGFsZTp7aXNzdWVkX2F0Om5ldyBEYXRlKE5PVy0zMTAwMCkudG9JU09TdHJpbmcoKX0sXG4gZnV0dXJlOntpc3N1ZWRfYXQ6bmV3IERhdGUoTk9XKzExMDAwKS50b0lTT1N0cmluZygpfSxkYXRlOntpc3N1ZWRfYXQ6XCIyMDI2LTAyLTMwVDAwOjAwOjAwWlwifSxcbiBwYXlsb2FkOntwYXlsb2FkOntkZXN0aW5hdGlvbjpcIisyNTA3ODgwMDAwMDBcIn19LHJlY29uY2lsZTp7YWN0aW9uOlwicmVjb25jaWxlXCIscGF5bG9hZDp7dGFyZ2V0X3JlcXVlc3RfaWQ6XCJiYWRcIn19fSkpe1xuIERlbm8udGVzdChcImNsb3NlZCBzaWduZWQgcHJvdG9jb2wgcmVmdXNlcyBcIituYW1lK1wiIGJlZm9yZSBrZXkgbG9va3VwXCIsYXN5bmMoKT0+e1xuICBjb25zdCBmPWF3YWl0IGZpeHR1cmUoKTtlcXVhbCgoYXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYucmVxdWVzdCh7Li4uZW52ZWxvcGUoKSwuLi5wYXRjaH0pKSkuc3RhdHVzLDQwMCk7ZXF1YWwoZi5jYWxscy5sZW5ndGgsMCk7XG4gfSk7XG59XG5mb3IoY29uc3QgW25hbWUscmF3XW9mIE9iamVjdC5lbnRyaWVzKHtkdXBsaWNhdGU6SlNPTi5zdHJpbmdpZnkoZW52ZWxvcGUoKSkucmVwbGFjZSgnXCJhY3Rpb25cIjpcInNoYWRvd19oZWFsdGhcIicsJ1wiYWN0aW9uXCI6XCJwcm92ZV9rZXlcIixcImFjdGlvblwiOlwic2hhZG93X2hlYWx0aFwiJyksXG4gZXh0cmFUZXh0OkpTT04uc3RyaW5naWZ5KGVudmVsb3BlKCkpK1wiIHRyYWlsaW5nXCIsYm9tOlwiXFx1ZmVmZlwiK0pTT04uc3RyaW5naWZ5KGVudmVsb3BlKCkpLFxuIG5lc3RlZDpKU09OLnN0cmluZ2lmeSh7Li4uZW52ZWxvcGUoKSxwYXlsb2FkOkFycmF5LmZyb20oe2xlbmd0aDoxMH0pLnJlZHVjZTxSZWNvcmQ8c3RyaW5nLHVua25vd24+Pigodik9Pih7eDp2fSkse30pfSl9KSl7XG4gRGVuby50ZXN0KFwic3RyaWN0IGJ5dGUgcGFyc2VyIHJlZnVzZXMgXCIrbmFtZSxhc3luYygpPT57XG4gIGNvbnN0IGY9YXdhaXQgZml4dHVyZSgpO2VxdWFsKChhd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5yZXF1ZXN0KHVuZGVmaW5lZCx7fSxyYXcpKSkuc3RhdHVzLDQwMCk7ZXF1YWwoZi5jYWxscy5sZW5ndGgsMCk7XG4gfSk7XG59XG5EZW5vLnRlc3QoXCJzaWduZWQgYnl0ZXMgY2Fubm90IGJlIG1vZGlmaWVkIHdpdGhvdXQgbG9zaW5nIHByb29mXCIsYXN5bmMoKT0+e1xuIGNvbnN0IGY9YXdhaXQgZml4dHVyZSgpO2NvbnN0IG9yaWdpbmFsPWF3YWl0IGYucmVxdWVzdCgpO2NvbnN0IGFsdGVyZWQ9SlNPTi5zdHJpbmdpZnkoey4uLmVudmVsb3BlKCkscmVxdWVzdF9pZDpUQVJHRVR9KTtcbiBjb25zdCByPWF3YWl0IGYuaGFuZGxlcihuZXcgUmVxdWVzdChvcmlnaW5hbC51cmwse21ldGhvZDpcIlBPU1RcIixoZWFkZXJzOm9yaWdpbmFsLmhlYWRlcnMsYm9keTphbHRlcmVkfSkpO1xuIGVxdWFsKHIuc3RhdHVzLDQwMSk7ZXF1YWwoZi5jYWxscy5sZW5ndGgsMSk7XG59KTtcbkRlbm8udGVzdChcImdhdGV3YXkgc2lnbmF0dXJlIGVudmVsb3BlIGNhbm5vdCBhdXRob3JpemUgc3VwZXJ2aXNvciBjYWxsc1wiLGFzeW5jKCk9PntcbiBjb25zdCBmPWF3YWl0IGZpeHR1cmUoKTtlcXVhbCgoYXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYucmVxdWVzdCh7Y29udHJhY3RfdmVyc2lvbjoxLGFjdGlvbjpcImhlYXJ0YmVhdFwiLGRldmljZV9pZDpJRCxyZXF1ZXN0X2lkOlJFUVVFU1QsaXNzdWVkX2F0OlRJTUUscGF5bG9hZDp7fX0pKSkuc3RhdHVzLDQwMCk7ZXF1YWwoZi5jYWxscy5sZW5ndGgsMCk7XG59KTtcbmZvcihjb25zdCBbbmFtZSxwYXRjaF1vZiBPYmplY3QuZW50cmllcyh7cmV2b2tlZDp7c3RhdGU6XCJyZXZva2VkXCJ9LHNjb3BlOntzY29wZTpcInBsYXRmb3JtX293bmVyXCJ9LGtleUhhc2g6e2tleV9zaGEyNTY6XCJhXCIucmVwZWF0KDY0KX0sXG4gZXhwaXJ5OntleHBpcmVzX2F0OlRJTUV9LHNwa2k6e3B1YmxpY19rZXlfc3BraV9iYXNlNjQ6XCJpbnZhbGlkXCJ9LHNlY3JldDp7cHJpdmF0ZV9rZXk6XCJzZWNyZXRcIn19KSl7XG4gRGVuby50ZXN0KFwic3RyaWN0IGtleSByZWFkYmFjayByZWZ1c2VzIFwiK25hbWUsYXN5bmMoKT0+e1xuICBjb25zdCBmPWF3YWl0IGZpeHR1cmUoKTtmLnNldEtleSh7Li4uZi5rZXkoKWFzIFJlY29yZDxzdHJpbmcsdW5rbm93bj4sLi4ucGF0Y2h9KTtlcXVhbCgoYXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYucmVxdWVzdCgpKSkuc3RhdHVzLDQwMSk7ZXF1YWwoZi5jYWxscy5sZW5ndGgsMSk7XG4gfSk7XG59XG5mb3IoY29uc3QgW25hbWUscGF0Y2hdb2YgT2JqZWN0LmVudHJpZXMoe3NlbmQ6e3NlbmRfYWN0aW9uOnRydWV9LGZpbmFuY2U6e2ZpbmFuY2lhbF9hY3Rpb246dHJ1ZX0saGFuZGxlZDp7YnVzaW5lc3NfaGFuZGxlZDp0cnVlfSxtb2RlOnttb2RlOlwiTGl2ZVwifSxcbiBwcmluY2lwYWw6e3ByaW5jaXBhbF9pZDpUQVJHRVR9LHJlcXVlc3Q6e3JlcXVlc3RfaWQ6VEFSR0VUfSxmcmFjdGlvbjp7cXVldWVkX2NvdW50OjEuNX0sb3ZlcmZsb3c6e3F1ZXVlZF9jb3VudDoxZTkrMX0sXG4gZm9yZWlnbkV4cGlyeTp7ZXhwaXJlc19hdDpuZXcgRGF0ZShOT1crOTAwMDAwMDApLnRvSVNPU3RyaW5nKCl9LGZ1dHVyZU9ic2VydmF0aW9uOntvYnNlcnZlZF9hdDpuZXcgRGF0ZShOT1crMTEwMDApLnRvSVNPU3RyaW5nKCl9LFxuIHJlbmV3ZWRTYW1wbGU6e3NhbXBsZV92YWxpZF91bnRpbDpuZXcgRGF0ZShOT1crNjEwMDApLnRvSVNPU3RyaW5nKCl9LHByaXZhdGVGaWVsZDp7Ym9keTpcInByaXZhdGVcIn19KSl7XG4gRGVuby50ZXN0KFwicG9zdC1wcm9vZiBtYWxmb3JtZWQgb3V0Y29tZSByZW1haW5zIHVua25vd246IFwiK25hbWUsYXN5bmMoKT0+e1xuICBjb25zdCBmPWF3YWl0IGZpeHR1cmUoKTtmLnNldFJlc3VsdCh7Li4ub2JzZXJ2YXRpb24oKSwuLi5wYXRjaH0pO2NvbnN0IHI9YXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYucmVxdWVzdCgpKTtlcXVhbChyLnN0YXR1cyw1MDIpO2VxdWFsKChhd2FpdCByLmpzb24oKSkuY29kZSxcIlNVUEVSVklTT1JfT1VUQ09NRV9VTktOT1dOXCIpO1xuIH0pO1xufVxuRGVuby50ZXN0KFwicmVjb25jaWxpYXRpb24gdXNlcyBvcmlnaW5hbCByZXF1ZXN0IFVVSUQgYW5kIGhpc3RvcmljYWwgb2JzZXJ2YXRpb25cIixhc3luYygpPT57XG4gY29uc3QgZj1hd2FpdCBmaXh0dXJlKCk7Y29uc3QgaGlzdG9yaWNhbD17Li4ub2JzZXJ2YXRpb24oXCJzaGFkb3dfaGVhbHRoXCIsVEFSR0VUKSxvYnNlcnZlZF9hdDpuZXcgRGF0ZShOT1ctMTAwMDAwKS50b0lTT1N0cmluZygpLHNhbXBsZV92YWxpZF91bnRpbDpuZXcgRGF0ZShOT1ctNDAwMDApLnRvSVNPU3RyaW5nKCl9O1xuIGYuc2V0UmVzdWx0KHtjb250cmFjdF92ZXJzaW9uOjEsdGFyZ2V0X3JlcXVlc3RfaWQ6VEFSR0VULHN0YXR1czpcInJlY29yZGVkXCIscmVjZWlwdDpoaXN0b3JpY2FsfSk7XG4gY29uc3Qgcj1hd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5yZXF1ZXN0KGVudmVsb3BlKFwicmVjb25jaWxlXCIse3RhcmdldF9yZXF1ZXN0X2lkOlRBUkdFVH0pKSk7ZXF1YWwoci5zdGF0dXMsMjAwKTtcbiBlcXVhbChmLmNhbGxzWzFdLm5hbWUsXCJyZWNlaXB0X3N1cGVydmlzb3JfcmVjb25jaWxlX3YxXCIpO2VxdWFsKGYuY2FsbHNbMV0uYXJncy5wX3RhcmdldF9yZXF1ZXN0X2lkLFRBUkdFVCk7ZXF1YWwoKGF3YWl0IHIuanNvbigpKS5yZXN1bHQucmVjZWlwdC5zYW1wbGVfdmFsaWRfdW50aWwsaGlzdG9yaWNhbC5zYW1wbGVfdmFsaWRfdW50aWwpO1xufSk7XG5mb3IoY29uc3Qgc3RhdHVzIG9mIFtcIm5vdF9yZWNvcmRlZFwiLFwiaW5fcHJvZ3Jlc3NcIl0pe0Rlbm8udGVzdChcImxvb2t1cCBcIitzdGF0dXMrXCIgY29udmV5cyBubyByZWNlaXB0IG9yIHJlcGxheVwiLGFzeW5jKCk9PntcbiBjb25zdCBmPWF3YWl0IGZpeHR1cmUoKTtmLnNldFJlc3VsdCh7Y29udHJhY3RfdmVyc2lvbjoxLHRhcmdldF9yZXF1ZXN0X2lkOlRBUkdFVCxzdGF0dXMscmVjZWlwdDpudWxsfSk7XG4gZXF1YWwoKGF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnJlcXVlc3QoZW52ZWxvcGUoXCJyZWNvbmNpbGVcIix7dGFyZ2V0X3JlcXVlc3RfaWQ6VEFSR0VUfSkpKSkuc3RhdHVzLDIwMCk7XG59KTt9XG5EZW5vLnRlc3QoXCJtaXNtYXRjaGVkIHJlY29uY2lsZWQgcmVjZWlwdCBzdGF5cyB1bmtub3duXCIsYXN5bmMoKT0+e1xuIGNvbnN0IGY9YXdhaXQgZml4dHVyZSgpO2Yuc2V0UmVzdWx0KHtjb250cmFjdF92ZXJzaW9uOjEsdGFyZ2V0X3JlcXVlc3RfaWQ6VEFSR0VULHN0YXR1czpcInJlY29yZGVkXCIscmVjZWlwdDpvYnNlcnZhdGlvbigpfSk7XG4gZXF1YWwoKGF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnJlcXVlc3QoZW52ZWxvcGUoXCJyZWNvbmNpbGVcIix7dGFyZ2V0X3JlcXVlc3RfaWQ6VEFSR0VUfSkpKSkuc3RhdHVzLDUwMik7XG59KTtcbkRlbm8udGVzdChcInJlYWRiYWNrIG91dGFnZSBhYm9ydHMgd2l0aGluIGRlYWRsaW5lIGJlZm9yZSBzZXJ2aWNlIGFjdGlvblwiLGFzeW5jKCk9PntcbiBjb25zdCBmPWF3YWl0IGZpeHR1cmUoXCJhY3RpdmVcIiw3MCk7Zi5zZXRQZW5kaW5nKFwicmVjZWlwdF9zdXBlcnZpc29yX2tleV92MVwiKTtjb25zdCByPWF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnJlcXVlc3QoKSk7ZXF1YWwoci5zdGF0dXMsNTAzKTtlcXVhbCgoYXdhaXQgci5qc29uKCkpLmNvZGUsXCJTVVBFUlZJU09SX0FVVEhfVU5BVkFJTEFCTEVcIik7YXNzZXJ0KGYuYWJvcnRlZCgpKTtlcXVhbChmLmNhbGxzLmxlbmd0aCwxKTtcbn0pO1xuRGVuby50ZXN0KFwidW5jZXJ0YWluIHBvc3QtcHJvb2YgcmVzcG9uc2UgYWJvcnRzIHdpdGhvdXQgcmV0cnlcIixhc3luYygpPT57XG4gY29uc3QgZj1hd2FpdCBmaXh0dXJlKFwiYWN0aXZlXCIsNzApO2Yuc2V0UGVuZGluZyhcInJlY2VpcHRfc3VwZXJ2aXNvcl9vYnNlcnZlX3YxXCIpO2NvbnN0IHI9YXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYucmVxdWVzdCgpKTtlcXVhbChyLnN0YXR1cyw1MDMpO2VxdWFsKChhd2FpdCByLmpzb24oKSkuY29kZSxcIlNVUEVSVklTT1JfT1VUQ09NRV9VTktOT1dOXCIpO2Fzc2VydChmLmFib3J0ZWQoKSk7ZXF1YWwoZi5jYWxscy5sZW5ndGgsMik7XG59KTtcbmZvcihjb25zdCBbY29kZSxzdGF0dXMsbGFiZWxdb2YgW1tcIjQyNTAxXCIsNDAzLFwiU1VQRVJWSVNPUl9BVVRIT1JJVFlfUkVGVVNFRFwiXSxbXCI1NVAwM1wiLDQwOSxcIlNVUEVSVklTT1JfQVVUSE9SSVRZX0JVU1lcIl0sW1wiMjIwMjNcIiw0MDksXCJTVVBFUlZJU09SX1JFUVVFU1RfUkVGVVNFRFwiXSxbXCJ1bmtub3duXCIsNTAzLFwiU1VQRVJWSVNPUl9BVVRIX1VOQVZBSUxBQkxFXCJdXWFzIGNvbnN0KXtcbiBEZW5vLnRlc3QoXCJiYWNrZW5kIFwiK2NvZGUrXCIgaXMgcmVkYWN0ZWRcIixhc3luYygpPT57XG4gIGNvbnN0IGY9YXdhaXQgZml4dHVyZSgpO2Yuc2V0RXJyb3Ioe2NvZGV9KTtjb25zdCByPWF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnJlcXVlc3QoKSk7ZXF1YWwoci5zdGF0dXMsc3RhdHVzKTtlcXVhbChhd2FpdCByLmpzb24oKSx7b2s6ZmFsc2UsY29kZTpsYWJlbH0pO1xuIH0pO1xufVxuRGVuby50ZXN0KFwibWV0aG9kIHF1ZXJ5IGFuZCBtYWxmb3JtZWQgREVSIGFyZSByZWplY3RlZCBiZWZvcmUgZGF0YWJhc2VcIixhc3luYygpPT57XG4gY29uc3QgZj1hd2FpdCBmaXh0dXJlKCk7ZXF1YWwoKGF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnJlcXVlc3QodW5kZWZpbmVkLHt9LHVuZGVmaW5lZCxcIkdFVFwiKSkpLnN0YXR1cyw0MDUpO1xuIGVxdWFsKChhd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5yZXF1ZXN0KHVuZGVmaW5lZCx7fSx1bmRlZmluZWQsXCJQT1NUXCIsXCJodHRwczovL2V4YW1wbGUuaW52YWxpZC9zdXBlcnZpc29yP3JwYz1zZW5kXCIpKSkuc3RhdHVzLDQwMCk7XG4gZXF1YWwoKGF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnJlcXVlc3QodW5kZWZpbmVkLHtcIlgtQ29sbGVjdC1TdXBlcnZpc29yLVNpZ25hdHVyZVwiOmI2NChuZXcgVWludDhBcnJheSg2NCkpfSkpKS5zdGF0dXMsNDAwKTtlcXVhbChmLmNhbGxzLmxlbmd0aCwwKTtcbn0pO1xuIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiJBQUFBLFNBQVEsdUJBQXVCLFFBQW9DLGVBQWU7QUFDbEYsTUFBTSxLQUFHO0FBQ1QsTUFBTSxVQUFRO0FBQ2QsTUFBTSxTQUFPO0FBQ2IsTUFBTSxNQUFJLEtBQUssS0FBSyxDQUFD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
// denoCacheMetadata=2017380490917872985,10861712530438759950
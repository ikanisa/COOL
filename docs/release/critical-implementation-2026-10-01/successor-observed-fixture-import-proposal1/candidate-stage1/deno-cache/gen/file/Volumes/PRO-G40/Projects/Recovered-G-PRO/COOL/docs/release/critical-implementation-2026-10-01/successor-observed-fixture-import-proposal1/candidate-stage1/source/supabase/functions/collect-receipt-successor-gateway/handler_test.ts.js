import { assertEquals } from "../_shared/test_assert.ts";
import { createSuccessorGatewayHandler } from "./handler.ts";
import { AUDIENCE, digest, FAMILY, result, route } from "./wire.ts";
import GRANT from "./fixtures/observed-first-successor-grant.json" with {
  type: "json"
};
import ARM from "./fixtures/observed-first-successor-arm.json" with {
  type: "json"
};
import RECOVERY from "./fixtures/observed-exact-grant-recovery.json" with {
  type: "json"
};
const device = GRANT.device_id;
const encode = new TextEncoder();
const b64 = (b)=>btoa(String.fromCharCode(...b));
const copy = (v)=>structuredClone(v);
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
function envelope(action, id, p, issued = GRANT.issued_at) {
  return {
    contract_version: 1,
    protocol_family: FAMILY,
    audience: AUDIENCE,
    action,
    device_id: device,
    request_id: id,
    issued_at: issued,
    payload: p
  };
}
const armPayload = ()=>({
    route: copy(ARM.route),
    attempt_id: ARM.attempt_id,
    fence_version: ARM.fence_version,
    body_sha256: GRANT.body_sha256,
    destination_sha256: GRANT.destination_sha256,
    reservation_sha256: ARM.reservation_sha256,
    callbacks: Array.from({
      length: GRANT.segment_count
    }, (_, segment_index)=>({
        segment_index,
        sent_callback_id: crypto.randomUUID(),
        delivery_callback_id: crypto.randomUUID()
      }))
  });
async function fixture(value, now = Date.parse(GRANT.issued_at), state = "active", error = null, forDevice = device) {
  const pair = await crypto.subtle.generateKey({
    name: "ECDSA",
    namedCurve: "P-256"
  }, true, [
    "sign",
    "verify"
  ]);
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", pair.publicKey));
  const keyId = await digest(spki);
  const calls = [];
  const deps = {
    now: ()=>now,
    timeoutMs: 25,
    rpc: (name, args)=>{
      calls.push({
        name,
        args
      });
      return Promise.resolve(name === "gateway_device_key_v1" ? {
        data: {
          device_id: forDevice,
          state,
          public_key_spki_base64: b64(spki),
          key_sha256: keyId,
          installation_id: crypto.randomUUID(),
          signing_certificate_sha256: "f".repeat(64)
        },
        error: null
      } : {
        data: value,
        error
      });
    }
  };
  async function signed(e, raw = JSON.stringify(e)) {
    const bytes = encode.encode(raw);
    const signature = der(new Uint8Array(await crypto.subtle.sign({
      name: "ECDSA",
      hash: "SHA-256"
    }, pair.privateKey, bytes)));
    return new Request("https://gateway.test/collect-receipt-successor-gateway", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "X-Collect-Gateway-Key-Id": keyId,
        "X-Collect-Gateway-Signature": b64(signature)
      },
      body: bytes
    });
  }
  return {
    calls,
    signed,
    deps,
    handler: createSuccessorGatewayHandler(deps)
  };
}
Deno.test("actual SQL first-job grant is consumed by strict signed route transport", async ()=>{
  const f = await fixture(GRANT);
  const e = envelope("dispatch_grant", GRANT.request_id, {});
  const response = await f.handler(await f.signed(e));
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.result, GRANT);
  assertEquals(f.calls.map((c)=>c.name), [
    "gateway_device_key_v1",
    "gateway_receipt_successor_grant_v1"
  ]);
  assertEquals(f.calls[1].args.p_request_sha256, await digest(encode.encode(JSON.stringify(e))));
  assertEquals(body.result.send_authority, false);
  assertEquals(route(body.result.route), true);
});
Deno.test("actual SQL final arm preserves exact route digest and own authority", async ()=>{
  const f = await fixture(ARM, Date.parse(ARM.armed_at));
  const e = envelope("arm_dispatch", ARM.request_id, armPayload(), ARM.armed_at);
  const response = await f.handler(await f.signed(e));
  assertEquals(response.status, 200);
  assertEquals((await response.json()).result, ARM);
  assertEquals(f.calls[1].name, "gateway_receipt_successor_arm_v1");
});
Deno.test("actual SQL original UUID recovery stays redacted and nonauthorizing", async ()=>{
  const id = crypto.randomUUID();
  const f = await fixture(RECOVERY);
  const response = await f.handler(await f.signed(envelope("reconcile", id, {
    target_request_id: GRANT.request_id
  })));
  assertEquals(response.status, 200);
  const v = (await response.json()).result;
  assertEquals(v, RECOVERY);
  assertEquals(v.send_authority, false);
  assertEquals("body" in v.recorded_result, false);
});
Deno.test("signed old family version and audience cannot reach new RPCs", async ()=>{
  for (const patch of [
    {
      protocol_family: "primary_v1"
    },
    {
      contract_version: 2
    },
    {
      audience: "collect-android-gateway"
    },
    {
      action: "callback"
    },
    {
      extra: true
    }
  ]){
    const f = await fixture(GRANT);
    const response = await f.handler(await f.signed({
      ...envelope("dispatch_grant", GRANT.request_id, {}),
      ...patch
    }));
    assertEquals(response.status, 400);
    assertEquals(f.calls.length, 0);
  }
});
Deno.test("signed duplicate JSON keys are rejected before verification", async ()=>{
  const f = await fixture(GRANT);
  const e = envelope("dispatch_grant", GRANT.request_id, {});
  const text = JSON.stringify(e).replace('"contract_version":1', '"contract_version":1,"contract_version":1');
  assertEquals((await f.handler(await f.signed(e, text))).status, 400);
  assertEquals(f.calls.length, 0);
});
Deno.test("old ordinary receipt_id alias and permissive result extras are unknown", async ()=>{
  for (const patch of [
    {
      receipt_id: GRANT.route.dispatch_job_id
    },
    {
      route: {
        ...GRANT.route,
        extra: true
      }
    },
    {
      route: {
        ...GRANT.route,
        dispatch_job_id: GRANT.route.primary_receipt_id
      }
    },
    {
      body: GRANT.body + " "
    },
    {
      send_authority: true
    }
  ]){
    const f = await fixture({
      ...GRANT,
      ...patch
    });
    const response = await f.handler(await f.signed(envelope("dispatch_grant", GRANT.request_id, {})));
    assertEquals(response.status, 502);
    assertEquals((await response.json()).send_authority, false);
  }
});
Deno.test("final arm changed route or reservation cannot validate", async ()=>{
  for (const patch of [
    {
      route: {
        ...ARM.route,
        approval_id: crypto.randomUUID()
      }
    },
    {
      reservation_sha256: "0".repeat(64)
    },
    {
      send_authority: false
    },
    {
      carrier_proof: true
    }
  ])assertEquals(await result("arm_dispatch", {
    ...ARM,
    ...patch
  }, device, ARM.request_id, armPayload(), Date.parse(ARM.armed_at)), false);
});
Deno.test("final arm repeated callback IDs cannot reach SQL", async ()=>{
  const f = await fixture(ARM, Date.parse(ARM.armed_at));
  const p = armPayload();
  const cb = p.callbacks[0];
  cb.delivery_callback_id = cb.sent_callback_id;
  const response = await f.handler(await f.signed(envelope("arm_dispatch", ARM.request_id, p, ARM.armed_at)));
  assertEquals(response.status, 400);
  assertEquals(f.calls.length, 0);
});
Deno.test("redacted arm replay never reconstructs authority", async ()=>{
  const refusal = {
    contract_version: 1,
    protocol_family: FAMILY,
    ok: false,
    code: "ORIGINAL_REQUEST_RECORDED",
    device_id: device,
    request_id: ARM.request_id,
    replay: true,
    send_authority: false,
    carrier_proof: false,
    delivery_proven: false
  };
  const f = await fixture(refusal, Date.parse(ARM.armed_at));
  const response = await f.handler(await f.signed(envelope("arm_dispatch", ARM.request_id, armPayload(), ARM.armed_at)));
  assertEquals(response.status, 200);
  assertEquals((await response.json()).result.send_authority, false);
});
Deno.test("revoked device permits readonly original lookup and refuses arm", async ()=>{
  const f = await fixture(ARM, Date.parse(ARM.armed_at), "revoked");
  assertEquals((await f.handler(await f.signed(envelope("arm_dispatch", ARM.request_id, armPayload(), ARM.armed_at)))).status, 403);
  assertEquals(f.calls.length, 1);
  const read = await fixture(RECOVERY, Date.parse(GRANT.issued_at), "revoked");
  assertEquals((await read.handler(await read.signed(envelope("reconcile", crypto.randomUUID(), {
    target_request_id: GRANT.request_id
  })))).status, 200);
});
Deno.test("expired grant result is unknown without body release", async ()=>{
  const f = await fixture(GRANT, Date.parse(GRANT.expires_at) + 1);
  const response = await f.handler(await f.signed(envelope("dispatch_grant", GRANT.request_id, {}, GRANT.expires_at)));
  assertEquals(response.status, 502);
  assertEquals("result" in await response.json(), false);
});
Deno.test("unknown lookup cannot invent a route or recorded receipt", async ()=>{
  const target = crypto.randomUUID();
  const v = {
    contract_version: 1,
    protocol_family: FAMILY,
    target_request_id: target,
    outcome: "unknown",
    recorded_action: null,
    recorded_route: null,
    recorded_result: null,
    send_authority: false,
    carrier_proof: false,
    delivery_proven: false
  };
  assertEquals(await result("reconcile", v, device, crypto.randomUUID(), {
    target_request_id: target
  }, Date.parse(GRANT.issued_at)), true);
  assertEquals(await result("reconcile", {
    ...v,
    recorded_route: GRANT.route
  }, device, crypto.randomUUID(), {
    target_request_id: target
  }, Date.parse(GRANT.issued_at)), false);
});
Deno.test("known refusal recovery retains actual refusal rather than empty success", async ()=>{
  const target = crypto.randomUUID();
  const refused = {
    contract_version: 1,
    protocol_family: FAMILY,
    ok: false,
    code: "SUCCESSORS_DISABLED",
    device_id: device,
    request_id: target,
    replay: false,
    send_authority: false,
    carrier_proof: false,
    delivery_proven: false
  };
  const v = {
    contract_version: 1,
    protocol_family: FAMILY,
    target_request_id: target,
    outcome: "recorded",
    recorded_action: "dispatch_grant",
    recorded_route: null,
    recorded_result: refused,
    send_authority: false,
    carrier_proof: false,
    delivery_proven: false
  };
  assertEquals(await result("reconcile", v, device, crypto.randomUUID(), {
    target_request_id: target
  }, Date.parse(GRANT.issued_at)), true);
});
Deno.test("signed backend denial is explicit and grants no response authority", async ()=>{
  for (const code of [
    "42501",
    "22023",
    "55000",
    "XX000"
  ]){
    const f = await fixture(null, Date.parse(GRANT.issued_at), "active", {
      code
    });
    const response = await f.handler(await f.signed(envelope("dispatch_grant", GRANT.request_id, {})));
    assertEquals(response.status, code === "42501" ? 403 : code === "XX000" ? 503 : 409);
    assertEquals((await response.json()).send_authority, false);
  }
});
import CALLBACKS from "./fixtures/observed-multipart-callbacks.json" with {
  type: "json"
};
import OBSGRANT from "./fixtures/observed-successor-grant.json" with {
  type: "json"
};
import ACK from "./fixtures/observed-exact-successor-archive-ack.json" with {
  type: "json"
};
import STATUS from "./fixtures/observed-armed-status.json" with {
  type: "json"
};
import LATESTATUS from "./fixtures/observed-late-conflicting-status.json" with {
  type: "json"
};
import LATERECOVERY from "./fixtures/observed-late-original-request-recovery.json" with {
  type: "json"
};
import INCOMPLETE from "./fixtures/observed-incomplete-archive.json" with {
  type: "json"
};
const archivePayload = ()=>({
    route: ACK.route,
    attempt_id: ACK.attempt_id,
    fence_version: ACK.fence_version,
    body_sha256: ACK.body_sha256,
    destination_sha256: ACK.destination_sha256,
    callback_requests: ACK.callback_requests
  });
Deno.test("actual SQL callback observations survive revoked device and exact route", async ()=>{
  for (const cb of CALLBACKS){
    const f = await fixture(cb.result, Date.parse(cb.result.recorded_at), "revoked", null, OBSGRANT.device_id);
    const e = {
      ...envelope("callback", cb.request_id, cb.payload, cb.result.recorded_at),
      device_id: OBSGRANT.device_id
    };
    const r = await f.handler(await f.signed(e));
    assertEquals(r.status, 200);
    assertEquals((await r.json()).result, cb.result);
    assertEquals(f.calls[1].name, "gateway_receipt_successor_callback_v1");
  }
});
Deno.test("actual SQL current and late contradictory status remain nonauthorizing", async ()=>{
  for (const st of [
    STATUS,
    LATESTATUS
  ]){
    const id = crypto.randomUUID();
    const p = {
      route: st.route,
      attempt_id: st.attempt_id,
      fence_version: st.fence_version
    };
    const f = await fixture(st, Date.parse(OBSGRANT.issued_at), "revoked", null, OBSGRANT.device_id);
    const r = await f.handler(await f.signed({
      ...envelope("attempt_status", id, p, OBSGRANT.issued_at),
      device_id: OBSGRANT.device_id
    }));
    assertEquals(r.status, 200);
    assertEquals((await r.json()).result, st);
    assertEquals(f.calls[1].name, "gateway_receipt_successor_attempt_status_v1");
  }
});
Deno.test("actual SQL archive ACK binds exact callback originals without delivery claim", async ()=>{
  const f = await fixture(ACK, Date.parse(ACK.recorded_at), "revoked", null, OBSGRANT.device_id);
  const r = await f.handler(await f.signed({
    ...envelope("archive_attempt", ACK.request_id, archivePayload(), ACK.recorded_at),
    device_id: OBSGRANT.device_id
  }));
  assertEquals(r.status, 200);
  assertEquals((await r.json()).result, ACK);
  assertEquals(f.calls[1].name, "gateway_receipt_successor_archive_v1");
  assertEquals(ACK.delivery_proven, false);
});
Deno.test("actual SQL incomplete archive remains an explicit immutable refusal", async ()=>{
  assertEquals(await result("archive_attempt", INCOMPLETE, INCOMPLETE.device_id, INCOMPLETE.request_id, archivePayload(), Date.parse(ACK.recorded_at)), true);
});
Deno.test("actual late original UUID reconciliation keeps contradictory facts", async ()=>{
  const id = crypto.randomUUID();
  const f = await fixture(LATERECOVERY, Date.parse(OBSGRANT.issued_at), "revoked", null, OBSGRANT.device_id);
  const r = await f.handler(await f.signed({
    ...envelope("reconcile", id, {
      target_request_id: LATERECOVERY.target_request_id
    }, OBSGRANT.issued_at),
    device_id: OBSGRANT.device_id
  }));
  assertEquals(r.status, 200);
  assertEquals((await r.json()).result, LATERECOVERY);
});
Deno.test("callback route and closed facts cannot invent delivery or send permission", async ()=>{
  const cb = CALLBACKS[0];
  for (const patch of [
    {
      delivery_proven: true
    },
    {
      send_authority: true
    },
    {
      extra: true
    },
    {
      route: {
        ...cb.result.route,
        dispatch_job_id: crypto.randomUUID()
      }
    },
    {
      sent_observations: 11
    }
  ])assertEquals(await result("callback", {
    ...cb.result,
    ...patch
  }, OBSGRANT.device_id, cb.request_id, cb.payload, Date.parse(cb.result.recorded_at)), false);
});
Deno.test("archive altered exact original references and old receipt aliases are refused", async ()=>{
  for (const patch of [
    {
      receipt_id: ACK.route.dispatch_job_id
    },
    {
      callback_requests: ACK.callback_requests.map((v, i)=>i ? v : {
          ...v,
          request_sha256: "0".repeat(64)
        })
    },
    {
      route: {
        ...ACK.route,
        approval_id: crypto.randomUUID()
      }
    },
    {
      journal_ack: false
    }
  ])assertEquals(await result("archive_attempt", {
    ...ACK,
    ...patch
  }, OBSGRANT.device_id, ACK.request_id, archivePayload(), Date.parse(ACK.recorded_at)), false);
});
Deno.test("recorded callback and archive reconciliation rejects permissive nested results", async ()=>{
  const p = {
    target_request_id: LATERECOVERY.target_request_id
  };
  for (const patch of [
    {
      recorded_result: {
        ...LATERECOVERY.recorded_result,
        extra: true
      }
    },
    {
      recorded_route: {
        ...LATERECOVERY.recorded_route,
        approval_id: crypto.randomUUID()
      }
    },
    {
      recorded_result: {
        ...LATERECOVERY.recorded_result,
        send_authority: true
      }
    }
  ])assertEquals(await result("reconcile", {
    ...LATERECOVERY,
    ...patch
  }, OBSGRANT.device_id, crypto.randomUUID(), p, Date.parse(OBSGRANT.issued_at)), false);
});
Deno.test("wrong exact signature never reaches the mutation RPC", async ()=>{
  const f = await fixture(GRANT);
  const request = await f.signed(envelope("dispatch_grant", GRANT.request_id, {}));
  const h = new Headers(request.headers);
  h.set("X-Collect-Gateway-Signature", b64(der(new Uint8Array(64).fill(1))));
  const r = await f.handler(new Request(request.url, {
    method: "POST",
    headers: h,
    body: await request.arrayBuffer()
  }));
  assertEquals(r.status, 401);
  assertEquals(f.calls.length, 1);
});
Deno.test("bounded SQL timeout returns unknown and performs one mutation invocation", async ()=>{
  const f = await fixture(GRANT);
  let mutations = 0;
  const timed = createSuccessorGatewayHandler({
    ...f.deps,
    timeoutMs: 5,
    rpc: (name, args, signal)=>{
      if (name === "gateway_device_key_v1") return f.deps.rpc(name, args, signal);
      mutations++;
      return new Promise(()=>{});
    }
  });
  const r = await timed(await f.signed(envelope("dispatch_grant", GRANT.request_id, {})));
  assertEquals(r.status, 504);
  assertEquals((await r.json()).send_authority, false);
  assertEquals(mutations, 1);
  assertEquals(f.calls.length, 1);
});
Deno.test("oversized and malformed UTF8 bodies are rejected before key discovery", async ()=>{
  const f = await fixture(GRANT);
  for (const bytes of [
    new Uint8Array(8193).fill(32),
    new Uint8Array([
      0xff,
      0xfe
    ])
  ]){
    const r = await f.handler(new Request("https://gateway.test", {
      method: "POST",
      headers: {
        "content-type": "application/json"
      },
      body: bytes
    }));
    assertEquals([
      400,
      413
    ].includes(r.status), true);
  }
  assertEquals(f.calls.length, 0);
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2NvbGxlY3QtcmVjZWlwdC1zdWNjZXNzb3ItZ2F0ZXdheS9oYW5kbGVyX3Rlc3QudHMiXSwic291cmNlc0NvbnRlbnQiOlsiaW1wb3J0IHsgYXNzZXJ0RXF1YWxzIH0gZnJvbSBcIi4uL19zaGFyZWQvdGVzdF9hc3NlcnQudHNcIjtcbmltcG9ydCB7IGNyZWF0ZVN1Y2Nlc3NvckdhdGV3YXlIYW5kbGVyLCB0eXBlIFN1Y2Nlc3NvckRlcGVuZGVuY2llcyB9IGZyb20gXCIuL2hhbmRsZXIudHNcIjtcbmltcG9ydCB7IEFVRElFTkNFLCBkaWdlc3QsIEZBTUlMWSwgdHlwZSBKc29uLCByZXN1bHQsIHJvdXRlIH0gZnJvbSBcIi4vd2lyZS50c1wiO1xuaW1wb3J0IEdSQU5UIGZyb20gXCIuL2ZpeHR1cmVzL29ic2VydmVkLWZpcnN0LXN1Y2Nlc3Nvci1ncmFudC5qc29uXCIgd2l0aCB7IHR5cGU6IFwianNvblwiIH07XG5pbXBvcnQgQVJNIGZyb20gXCIuL2ZpeHR1cmVzL29ic2VydmVkLWZpcnN0LXN1Y2Nlc3Nvci1hcm0uanNvblwiIHdpdGggeyB0eXBlOiBcImpzb25cIiB9O1xuaW1wb3J0IFJFQ09WRVJZIGZyb20gXCIuL2ZpeHR1cmVzL29ic2VydmVkLWV4YWN0LWdyYW50LXJlY292ZXJ5Lmpzb25cIiB3aXRoIHsgdHlwZTogXCJqc29uXCIgfTtcbmNvbnN0IGRldmljZSA9IEdSQU5ULmRldmljZV9pZDtcbmNvbnN0IGVuY29kZSA9IG5ldyBUZXh0RW5jb2RlcigpO1xuY29uc3QgYjY0ID0gKGI6IFVpbnQ4QXJyYXkpID0+IGJ0b2EoU3RyaW5nLmZyb21DaGFyQ29kZSguLi5iKSk7XG5jb25zdCBjb3B5ID0gPFQ+KHY6IFQpOiBUID0+IHN0cnVjdHVyZWRDbG9uZSh2KTtcbmZ1bmN0aW9uIGRlcihyYXc6IFVpbnQ4QXJyYXkpOiBVaW50OEFycmF5IHtcbiBjb25zdCBwYXJ0cyA9IFtyYXcuc2xpY2UoMCwzMikscmF3LnNsaWNlKDMyKV0ubWFwKHAgPT4ge3doaWxlKHAubGVuZ3RoPjEgJiYgcFswXT09PTApIHA9cC5zbGljZSgxKTtpZihwWzBdJjEyOClwPVVpbnQ4QXJyYXkuZnJvbShbMCwuLi5wXSk7cmV0dXJuIFVpbnQ4QXJyYXkuZnJvbShbMixwLmxlbmd0aCwuLi5wXSk7fSk7XG4gcmV0dXJuIFVpbnQ4QXJyYXkuZnJvbShbNDgscGFydHNbMF0ubGVuZ3RoK3BhcnRzWzFdLmxlbmd0aCwuLi5wYXJ0c1swXSwuLi5wYXJ0c1sxXV0pO1xufVxuZnVuY3Rpb24gZW52ZWxvcGUoYWN0aW9uOiBzdHJpbmcsIGlkOiBzdHJpbmcsIHA6IEpzb24sIGlzc3VlZCA9IEdSQU5ULmlzc3VlZF9hdCk6IEpzb24ge1xuIHJldHVybiB7Y29udHJhY3RfdmVyc2lvbjoxLHByb3RvY29sX2ZhbWlseTpGQU1JTFksYXVkaWVuY2U6QVVESUVOQ0UsYWN0aW9uLGRldmljZV9pZDpkZXZpY2UscmVxdWVzdF9pZDppZCxpc3N1ZWRfYXQ6aXNzdWVkLHBheWxvYWQ6cH07XG59XG5jb25zdCBhcm1QYXlsb2FkID0gKCk6IEpzb24gPT4gKHtyb3V0ZTpjb3B5KEFSTS5yb3V0ZSksYXR0ZW1wdF9pZDpBUk0uYXR0ZW1wdF9pZCxmZW5jZV92ZXJzaW9uOkFSTS5mZW5jZV92ZXJzaW9uLGJvZHlfc2hhMjU2OkdSQU5ULmJvZHlfc2hhMjU2LGRlc3RpbmF0aW9uX3NoYTI1NjpHUkFOVC5kZXN0aW5hdGlvbl9zaGEyNTYscmVzZXJ2YXRpb25fc2hhMjU2OkFSTS5yZXNlcnZhdGlvbl9zaGEyNTYsY2FsbGJhY2tzOkFycmF5LmZyb20oe2xlbmd0aDpHUkFOVC5zZWdtZW50X2NvdW50fSwoXyxzZWdtZW50X2luZGV4KT0+KHtzZWdtZW50X2luZGV4LHNlbnRfY2FsbGJhY2tfaWQ6Y3J5cHRvLnJhbmRvbVVVSUQoKSxkZWxpdmVyeV9jYWxsYmFja19pZDpjcnlwdG8ucmFuZG9tVVVJRCgpfSkpfSk7XG5hc3luYyBmdW5jdGlvbiBmaXh0dXJlKHZhbHVlOiB1bmtub3duLCBub3cgPSBEYXRlLnBhcnNlKEdSQU5ULmlzc3VlZF9hdCksIHN0YXRlID0gXCJhY3RpdmVcIiwgZXJyb3I6IHtjb2RlPzpzdHJpbmd9fG51bGwgPSBudWxsLCBmb3JEZXZpY2UgPSBkZXZpY2UpIHtcbiBjb25zdCBwYWlyID0gYXdhaXQgY3J5cHRvLnN1YnRsZS5nZW5lcmF0ZUtleSh7bmFtZTpcIkVDRFNBXCIsbmFtZWRDdXJ2ZTpcIlAtMjU2XCJ9LHRydWUsW1wic2lnblwiLFwidmVyaWZ5XCJdKTtcbiBjb25zdCBzcGtpID0gbmV3IFVpbnQ4QXJyYXkoYXdhaXQgY3J5cHRvLnN1YnRsZS5leHBvcnRLZXkoXCJzcGtpXCIscGFpci5wdWJsaWNLZXkpKTtjb25zdCBrZXlJZCA9IGF3YWl0IGRpZ2VzdChzcGtpKTtjb25zdCBjYWxsczp7bmFtZTpzdHJpbmc7YXJnczpKc29ufVtdPVtdO1xuIGNvbnN0IGRlcHM6U3VjY2Vzc29yRGVwZW5kZW5jaWVzPXtub3c6KCk9Pm5vdyx0aW1lb3V0TXM6MjUscnBjOihuYW1lLGFyZ3MpPT57Y2FsbHMucHVzaCh7bmFtZSxhcmdzfSk7cmV0dXJuIFByb21pc2UucmVzb2x2ZShuYW1lPT09XCJnYXRld2F5X2RldmljZV9rZXlfdjFcIj97ZGF0YTp7ZGV2aWNlX2lkOmZvckRldmljZSxzdGF0ZSxwdWJsaWNfa2V5X3Nwa2lfYmFzZTY0OmI2NChzcGtpKSxrZXlfc2hhMjU2OmtleUlkLGluc3RhbGxhdGlvbl9pZDpjcnlwdG8ucmFuZG9tVVVJRCgpLHNpZ25pbmdfY2VydGlmaWNhdGVfc2hhMjU2OlwiZlwiLnJlcGVhdCg2NCl9LGVycm9yOm51bGx9OntkYXRhOnZhbHVlLGVycm9yfSk7fX07XG4gYXN5bmMgZnVuY3Rpb24gc2lnbmVkKGU6SnNvbiwgcmF3ID0gSlNPTi5zdHJpbmdpZnkoZSkpIHtcbiAgY29uc3QgYnl0ZXM9ZW5jb2RlLmVuY29kZShyYXcpO2NvbnN0IHNpZ25hdHVyZT1kZXIobmV3IFVpbnQ4QXJyYXkoYXdhaXQgY3J5cHRvLnN1YnRsZS5zaWduKHtuYW1lOlwiRUNEU0FcIixoYXNoOlwiU0hBLTI1NlwifSxwYWlyLnByaXZhdGVLZXksYnl0ZXMpKSk7XG4gIHJldHVybiBuZXcgUmVxdWVzdChcImh0dHBzOi8vZ2F0ZXdheS50ZXN0L2NvbGxlY3QtcmVjZWlwdC1zdWNjZXNzb3ItZ2F0ZXdheVwiLHttZXRob2Q6XCJQT1NUXCIsaGVhZGVyczp7XCJjb250ZW50LXR5cGVcIjpcImFwcGxpY2F0aW9uL2pzb25cIixcIlgtQ29sbGVjdC1HYXRld2F5LUtleS1JZFwiOmtleUlkLFwiWC1Db2xsZWN0LUdhdGV3YXktU2lnbmF0dXJlXCI6YjY0KHNpZ25hdHVyZSl9LGJvZHk6Ynl0ZXN9KTtcbiB9XG4gcmV0dXJuIHtjYWxscyxzaWduZWQsZGVwcyxoYW5kbGVyOmNyZWF0ZVN1Y2Nlc3NvckdhdGV3YXlIYW5kbGVyKGRlcHMpfTtcbn1cbkRlbm8udGVzdChcImFjdHVhbCBTUUwgZmlyc3Qtam9iIGdyYW50IGlzIGNvbnN1bWVkIGJ5IHN0cmljdCBzaWduZWQgcm91dGUgdHJhbnNwb3J0XCIsYXN5bmMoKT0+e1xuIGNvbnN0IGY9YXdhaXQgZml4dHVyZShHUkFOVCk7Y29uc3QgZT1lbnZlbG9wZShcImRpc3BhdGNoX2dyYW50XCIsR1JBTlQucmVxdWVzdF9pZCx7fSk7Y29uc3QgcmVzcG9uc2U9YXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYuc2lnbmVkKGUpKTtjb25zdCBib2R5PWF3YWl0IHJlc3BvbnNlLmpzb24oKTthc3NlcnRFcXVhbHMocmVzcG9uc2Uuc3RhdHVzLDIwMCk7YXNzZXJ0RXF1YWxzKGJvZHkucmVzdWx0LEdSQU5UKTthc3NlcnRFcXVhbHMoZi5jYWxscy5tYXAoYz0+Yy5uYW1lKSxbXCJnYXRld2F5X2RldmljZV9rZXlfdjFcIixcImdhdGV3YXlfcmVjZWlwdF9zdWNjZXNzb3JfZ3JhbnRfdjFcIl0pO2Fzc2VydEVxdWFscyhmLmNhbGxzWzFdLmFyZ3MucF9yZXF1ZXN0X3NoYTI1Nixhd2FpdCBkaWdlc3QoZW5jb2RlLmVuY29kZShKU09OLnN0cmluZ2lmeShlKSkpKTthc3NlcnRFcXVhbHMoYm9keS5yZXN1bHQuc2VuZF9hdXRob3JpdHksZmFsc2UpO2Fzc2VydEVxdWFscyhyb3V0ZShib2R5LnJlc3VsdC5yb3V0ZSksdHJ1ZSk7XG59KTtcbkRlbm8udGVzdChcImFjdHVhbCBTUUwgZmluYWwgYXJtIHByZXNlcnZlcyBleGFjdCByb3V0ZSBkaWdlc3QgYW5kIG93biBhdXRob3JpdHlcIixhc3luYygpPT57XG4gY29uc3QgZj1hd2FpdCBmaXh0dXJlKEFSTSxEYXRlLnBhcnNlKEFSTS5hcm1lZF9hdCkpO2NvbnN0IGU9ZW52ZWxvcGUoXCJhcm1fZGlzcGF0Y2hcIixBUk0ucmVxdWVzdF9pZCxhcm1QYXlsb2FkKCksQVJNLmFybWVkX2F0KTtjb25zdCByZXNwb25zZT1hd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoZSkpO2Fzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMsMjAwKTthc3NlcnRFcXVhbHMoKGF3YWl0IHJlc3BvbnNlLmpzb24oKSkucmVzdWx0LEFSTSk7YXNzZXJ0RXF1YWxzKGYuY2FsbHNbMV0ubmFtZSxcImdhdGV3YXlfcmVjZWlwdF9zdWNjZXNzb3JfYXJtX3YxXCIpO1xufSk7XG5EZW5vLnRlc3QoXCJhY3R1YWwgU1FMIG9yaWdpbmFsIFVVSUQgcmVjb3Zlcnkgc3RheXMgcmVkYWN0ZWQgYW5kIG5vbmF1dGhvcml6aW5nXCIsYXN5bmMoKT0+e1xuIGNvbnN0IGlkPWNyeXB0by5yYW5kb21VVUlEKCk7Y29uc3QgZj1hd2FpdCBmaXh0dXJlKFJFQ09WRVJZKTtjb25zdCByZXNwb25zZT1hd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoZW52ZWxvcGUoXCJyZWNvbmNpbGVcIixpZCx7dGFyZ2V0X3JlcXVlc3RfaWQ6R1JBTlQucmVxdWVzdF9pZH0pKSk7YXNzZXJ0RXF1YWxzKHJlc3BvbnNlLnN0YXR1cywyMDApO2NvbnN0IHY9KGF3YWl0IHJlc3BvbnNlLmpzb24oKSkucmVzdWx0O2Fzc2VydEVxdWFscyh2LFJFQ09WRVJZKTthc3NlcnRFcXVhbHModi5zZW5kX2F1dGhvcml0eSxmYWxzZSk7YXNzZXJ0RXF1YWxzKFwiYm9keVwiaW4gdi5yZWNvcmRlZF9yZXN1bHQsZmFsc2UpO1xufSk7XG5EZW5vLnRlc3QoXCJzaWduZWQgb2xkIGZhbWlseSB2ZXJzaW9uIGFuZCBhdWRpZW5jZSBjYW5ub3QgcmVhY2ggbmV3IFJQQ3NcIixhc3luYygpPT57XG4gZm9yKGNvbnN0IHBhdGNoIG9mIFt7cHJvdG9jb2xfZmFtaWx5OlwicHJpbWFyeV92MVwifSx7Y29udHJhY3RfdmVyc2lvbjoyfSx7YXVkaWVuY2U6XCJjb2xsZWN0LWFuZHJvaWQtZ2F0ZXdheVwifSx7YWN0aW9uOlwiY2FsbGJhY2tcIn0se2V4dHJhOnRydWV9XSl7XG4gIGNvbnN0IGY9YXdhaXQgZml4dHVyZShHUkFOVCk7Y29uc3QgcmVzcG9uc2U9YXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYuc2lnbmVkKHsuLi5lbnZlbG9wZShcImRpc3BhdGNoX2dyYW50XCIsR1JBTlQucmVxdWVzdF9pZCx7fSksLi4ucGF0Y2h9KSk7YXNzZXJ0RXF1YWxzKHJlc3BvbnNlLnN0YXR1cyw0MDApO2Fzc2VydEVxdWFscyhmLmNhbGxzLmxlbmd0aCwwKTtcbiB9XG59KTtcbkRlbm8udGVzdChcInNpZ25lZCBkdXBsaWNhdGUgSlNPTiBrZXlzIGFyZSByZWplY3RlZCBiZWZvcmUgdmVyaWZpY2F0aW9uXCIsYXN5bmMoKT0+e1xuIGNvbnN0IGY9YXdhaXQgZml4dHVyZShHUkFOVCk7Y29uc3QgZT1lbnZlbG9wZShcImRpc3BhdGNoX2dyYW50XCIsR1JBTlQucmVxdWVzdF9pZCx7fSk7Y29uc3QgdGV4dD1KU09OLnN0cmluZ2lmeShlKS5yZXBsYWNlKCdcImNvbnRyYWN0X3ZlcnNpb25cIjoxJywnXCJjb250cmFjdF92ZXJzaW9uXCI6MSxcImNvbnRyYWN0X3ZlcnNpb25cIjoxJyk7YXNzZXJ0RXF1YWxzKChhd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoZSx0ZXh0KSkpLnN0YXR1cyw0MDApO2Fzc2VydEVxdWFscyhmLmNhbGxzLmxlbmd0aCwwKTtcbn0pO1xuRGVuby50ZXN0KFwib2xkIG9yZGluYXJ5IHJlY2VpcHRfaWQgYWxpYXMgYW5kIHBlcm1pc3NpdmUgcmVzdWx0IGV4dHJhcyBhcmUgdW5rbm93blwiLGFzeW5jKCk9PntcbiBmb3IoY29uc3QgcGF0Y2ggb2YgW3tyZWNlaXB0X2lkOkdSQU5ULnJvdXRlLmRpc3BhdGNoX2pvYl9pZH0se3JvdXRlOnsuLi5HUkFOVC5yb3V0ZSxleHRyYTp0cnVlfX0se3JvdXRlOnsuLi5HUkFOVC5yb3V0ZSxkaXNwYXRjaF9qb2JfaWQ6R1JBTlQucm91dGUucHJpbWFyeV9yZWNlaXB0X2lkfX0se2JvZHk6R1JBTlQuYm9keStcIiBcIn0se3NlbmRfYXV0aG9yaXR5OnRydWV9XSl7XG4gIGNvbnN0IGY9YXdhaXQgZml4dHVyZSh7Li4uR1JBTlQsLi4ucGF0Y2h9KTtjb25zdCByZXNwb25zZT1hd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoZW52ZWxvcGUoXCJkaXNwYXRjaF9ncmFudFwiLEdSQU5ULnJlcXVlc3RfaWQse30pKSk7YXNzZXJ0RXF1YWxzKHJlc3BvbnNlLnN0YXR1cyw1MDIpO2Fzc2VydEVxdWFscygoYXdhaXQgcmVzcG9uc2UuanNvbigpKS5zZW5kX2F1dGhvcml0eSxmYWxzZSk7XG4gfVxufSk7XG5EZW5vLnRlc3QoXCJmaW5hbCBhcm0gY2hhbmdlZCByb3V0ZSBvciByZXNlcnZhdGlvbiBjYW5ub3QgdmFsaWRhdGVcIixhc3luYygpPT57XG4gZm9yKGNvbnN0IHBhdGNoIG9mIFt7cm91dGU6ey4uLkFSTS5yb3V0ZSxhcHByb3ZhbF9pZDpjcnlwdG8ucmFuZG9tVVVJRCgpfX0se3Jlc2VydmF0aW9uX3NoYTI1NjpcIjBcIi5yZXBlYXQoNjQpfSx7c2VuZF9hdXRob3JpdHk6ZmFsc2V9LHtjYXJyaWVyX3Byb29mOnRydWV9XSlhc3NlcnRFcXVhbHMoYXdhaXQgcmVzdWx0KFwiYXJtX2Rpc3BhdGNoXCIsey4uLkFSTSwuLi5wYXRjaH0sZGV2aWNlLEFSTS5yZXF1ZXN0X2lkLGFybVBheWxvYWQoKSxEYXRlLnBhcnNlKEFSTS5hcm1lZF9hdCkpLGZhbHNlKTtcbn0pO1xuRGVuby50ZXN0KFwiZmluYWwgYXJtIHJlcGVhdGVkIGNhbGxiYWNrIElEcyBjYW5ub3QgcmVhY2ggU1FMXCIsYXN5bmMoKT0+e1xuIGNvbnN0IGY9YXdhaXQgZml4dHVyZShBUk0sRGF0ZS5wYXJzZShBUk0uYXJtZWRfYXQpKTtjb25zdCBwPWFybVBheWxvYWQoKTtjb25zdCBjYj0ocC5jYWxsYmFja3MgYXMgSnNvbltdKVswXTtjYi5kZWxpdmVyeV9jYWxsYmFja19pZD1jYi5zZW50X2NhbGxiYWNrX2lkO2NvbnN0IHJlc3BvbnNlPWF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnNpZ25lZChlbnZlbG9wZShcImFybV9kaXNwYXRjaFwiLEFSTS5yZXF1ZXN0X2lkLHAsQVJNLmFybWVkX2F0KSkpO2Fzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMsNDAwKTthc3NlcnRFcXVhbHMoZi5jYWxscy5sZW5ndGgsMCk7XG59KTtcbkRlbm8udGVzdChcInJlZGFjdGVkIGFybSByZXBsYXkgbmV2ZXIgcmVjb25zdHJ1Y3RzIGF1dGhvcml0eVwiLGFzeW5jKCk9PntcbiBjb25zdCByZWZ1c2FsPXtjb250cmFjdF92ZXJzaW9uOjEscHJvdG9jb2xfZmFtaWx5OkZBTUlMWSxvazpmYWxzZSxjb2RlOlwiT1JJR0lOQUxfUkVRVUVTVF9SRUNPUkRFRFwiLGRldmljZV9pZDpkZXZpY2UscmVxdWVzdF9pZDpBUk0ucmVxdWVzdF9pZCxyZXBsYXk6dHJ1ZSxzZW5kX2F1dGhvcml0eTpmYWxzZSxjYXJyaWVyX3Byb29mOmZhbHNlLGRlbGl2ZXJ5X3Byb3ZlbjpmYWxzZX07Y29uc3QgZj1hd2FpdCBmaXh0dXJlKHJlZnVzYWwsRGF0ZS5wYXJzZShBUk0uYXJtZWRfYXQpKTtjb25zdCByZXNwb25zZT1hd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoZW52ZWxvcGUoXCJhcm1fZGlzcGF0Y2hcIixBUk0ucmVxdWVzdF9pZCxhcm1QYXlsb2FkKCksQVJNLmFybWVkX2F0KSkpO2Fzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMsMjAwKTthc3NlcnRFcXVhbHMoKGF3YWl0IHJlc3BvbnNlLmpzb24oKSkucmVzdWx0LnNlbmRfYXV0aG9yaXR5LGZhbHNlKTtcbn0pO1xuRGVuby50ZXN0KFwicmV2b2tlZCBkZXZpY2UgcGVybWl0cyByZWFkb25seSBvcmlnaW5hbCBsb29rdXAgYW5kIHJlZnVzZXMgYXJtXCIsYXN5bmMoKT0+e1xuIGNvbnN0IGY9YXdhaXQgZml4dHVyZShBUk0sRGF0ZS5wYXJzZShBUk0uYXJtZWRfYXQpLFwicmV2b2tlZFwiKTthc3NlcnRFcXVhbHMoKGF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnNpZ25lZChlbnZlbG9wZShcImFybV9kaXNwYXRjaFwiLEFSTS5yZXF1ZXN0X2lkLGFybVBheWxvYWQoKSxBUk0uYXJtZWRfYXQpKSkpLnN0YXR1cyw0MDMpO2Fzc2VydEVxdWFscyhmLmNhbGxzLmxlbmd0aCwxKTtjb25zdCByZWFkPWF3YWl0IGZpeHR1cmUoUkVDT1ZFUlksRGF0ZS5wYXJzZShHUkFOVC5pc3N1ZWRfYXQpLFwicmV2b2tlZFwiKTthc3NlcnRFcXVhbHMoKGF3YWl0IHJlYWQuaGFuZGxlcihhd2FpdCByZWFkLnNpZ25lZChlbnZlbG9wZShcInJlY29uY2lsZVwiLGNyeXB0by5yYW5kb21VVUlEKCkse3RhcmdldF9yZXF1ZXN0X2lkOkdSQU5ULnJlcXVlc3RfaWR9KSkpKS5zdGF0dXMsMjAwKTtcbn0pO1xuRGVuby50ZXN0KFwiZXhwaXJlZCBncmFudCByZXN1bHQgaXMgdW5rbm93biB3aXRob3V0IGJvZHkgcmVsZWFzZVwiLGFzeW5jKCk9PntcbiBjb25zdCBmPWF3YWl0IGZpeHR1cmUoR1JBTlQsRGF0ZS5wYXJzZShHUkFOVC5leHBpcmVzX2F0KSsxKTtjb25zdCByZXNwb25zZT1hd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoZW52ZWxvcGUoXCJkaXNwYXRjaF9ncmFudFwiLEdSQU5ULnJlcXVlc3RfaWQse30sR1JBTlQuZXhwaXJlc19hdCkpKTthc3NlcnRFcXVhbHMocmVzcG9uc2Uuc3RhdHVzLDUwMik7YXNzZXJ0RXF1YWxzKFwicmVzdWx0XCJpbiBhd2FpdCByZXNwb25zZS5qc29uKCksZmFsc2UpO1xufSk7XG5EZW5vLnRlc3QoXCJ1bmtub3duIGxvb2t1cCBjYW5ub3QgaW52ZW50IGEgcm91dGUgb3IgcmVjb3JkZWQgcmVjZWlwdFwiLGFzeW5jKCk9PntcbiBjb25zdCB0YXJnZXQ9Y3J5cHRvLnJhbmRvbVVVSUQoKTtjb25zdCB2PXtjb250cmFjdF92ZXJzaW9uOjEscHJvdG9jb2xfZmFtaWx5OkZBTUlMWSx0YXJnZXRfcmVxdWVzdF9pZDp0YXJnZXQsb3V0Y29tZTpcInVua25vd25cIixyZWNvcmRlZF9hY3Rpb246bnVsbCxyZWNvcmRlZF9yb3V0ZTpudWxsLHJlY29yZGVkX3Jlc3VsdDpudWxsLHNlbmRfYXV0aG9yaXR5OmZhbHNlLGNhcnJpZXJfcHJvb2Y6ZmFsc2UsZGVsaXZlcnlfcHJvdmVuOmZhbHNlfTthc3NlcnRFcXVhbHMoYXdhaXQgcmVzdWx0KFwicmVjb25jaWxlXCIsdixkZXZpY2UsY3J5cHRvLnJhbmRvbVVVSUQoKSx7dGFyZ2V0X3JlcXVlc3RfaWQ6dGFyZ2V0fSxEYXRlLnBhcnNlKEdSQU5ULmlzc3VlZF9hdCkpLHRydWUpO2Fzc2VydEVxdWFscyhhd2FpdCByZXN1bHQoXCJyZWNvbmNpbGVcIix7Li4udixyZWNvcmRlZF9yb3V0ZTpHUkFOVC5yb3V0ZX0sZGV2aWNlLGNyeXB0by5yYW5kb21VVUlEKCkse3RhcmdldF9yZXF1ZXN0X2lkOnRhcmdldH0sRGF0ZS5wYXJzZShHUkFOVC5pc3N1ZWRfYXQpKSxmYWxzZSk7XG59KTtcbkRlbm8udGVzdChcImtub3duIHJlZnVzYWwgcmVjb3ZlcnkgcmV0YWlucyBhY3R1YWwgcmVmdXNhbCByYXRoZXIgdGhhbiBlbXB0eSBzdWNjZXNzXCIsYXN5bmMoKT0+e1xuIGNvbnN0IHRhcmdldD1jcnlwdG8ucmFuZG9tVVVJRCgpO2NvbnN0IHJlZnVzZWQ9e2NvbnRyYWN0X3ZlcnNpb246MSxwcm90b2NvbF9mYW1pbHk6RkFNSUxZLG9rOmZhbHNlLGNvZGU6XCJTVUNDRVNTT1JTX0RJU0FCTEVEXCIsZGV2aWNlX2lkOmRldmljZSxyZXF1ZXN0X2lkOnRhcmdldCxyZXBsYXk6ZmFsc2Usc2VuZF9hdXRob3JpdHk6ZmFsc2UsY2Fycmllcl9wcm9vZjpmYWxzZSxkZWxpdmVyeV9wcm92ZW46ZmFsc2V9O2NvbnN0IHY9e2NvbnRyYWN0X3ZlcnNpb246MSxwcm90b2NvbF9mYW1pbHk6RkFNSUxZLHRhcmdldF9yZXF1ZXN0X2lkOnRhcmdldCxvdXRjb21lOlwicmVjb3JkZWRcIixyZWNvcmRlZF9hY3Rpb246XCJkaXNwYXRjaF9ncmFudFwiLHJlY29yZGVkX3JvdXRlOm51bGwscmVjb3JkZWRfcmVzdWx0OnJlZnVzZWQsc2VuZF9hdXRob3JpdHk6ZmFsc2UsY2Fycmllcl9wcm9vZjpmYWxzZSxkZWxpdmVyeV9wcm92ZW46ZmFsc2V9O2Fzc2VydEVxdWFscyhhd2FpdCByZXN1bHQoXCJyZWNvbmNpbGVcIix2LGRldmljZSxjcnlwdG8ucmFuZG9tVVVJRCgpLHt0YXJnZXRfcmVxdWVzdF9pZDp0YXJnZXR9LERhdGUucGFyc2UoR1JBTlQuaXNzdWVkX2F0KSksdHJ1ZSk7XG59KTtcbkRlbm8udGVzdChcInNpZ25lZCBiYWNrZW5kIGRlbmlhbCBpcyBleHBsaWNpdCBhbmQgZ3JhbnRzIG5vIHJlc3BvbnNlIGF1dGhvcml0eVwiLGFzeW5jKCk9PntcbiBmb3IoY29uc3QgY29kZSBvZiBbXCI0MjUwMVwiLFwiMjIwMjNcIixcIjU1MDAwXCIsXCJYWDAwMFwiXSl7Y29uc3QgZj1hd2FpdCBmaXh0dXJlKG51bGwsRGF0ZS5wYXJzZShHUkFOVC5pc3N1ZWRfYXQpLFwiYWN0aXZlXCIse2NvZGV9KTtjb25zdCByZXNwb25zZT1hd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoZW52ZWxvcGUoXCJkaXNwYXRjaF9ncmFudFwiLEdSQU5ULnJlcXVlc3RfaWQse30pKSk7YXNzZXJ0RXF1YWxzKHJlc3BvbnNlLnN0YXR1cyxjb2RlPT09XCI0MjUwMVwiPzQwMzpjb2RlPT09XCJYWDAwMFwiPzUwMzo0MDkpO2Fzc2VydEVxdWFscygoYXdhaXQgcmVzcG9uc2UuanNvbigpKS5zZW5kX2F1dGhvcml0eSxmYWxzZSk7fVxufSk7XG5cbmltcG9ydCBDQUxMQkFDS1MgZnJvbSBcIi4vZml4dHVyZXMvb2JzZXJ2ZWQtbXVsdGlwYXJ0LWNhbGxiYWNrcy5qc29uXCIgd2l0aCB7IHR5cGU6IFwianNvblwiIH07XG5pbXBvcnQgT0JTR1JBTlQgZnJvbSBcIi4vZml4dHVyZXMvb2JzZXJ2ZWQtc3VjY2Vzc29yLWdyYW50Lmpzb25cIiB3aXRoIHsgdHlwZTogXCJqc29uXCIgfTtcbmltcG9ydCBBQ0sgZnJvbSBcIi4vZml4dHVyZXMvb2JzZXJ2ZWQtZXhhY3Qtc3VjY2Vzc29yLWFyY2hpdmUtYWNrLmpzb25cIiB3aXRoIHsgdHlwZTogXCJqc29uXCIgfTtcbmltcG9ydCBTVEFUVVMgZnJvbSBcIi4vZml4dHVyZXMvb2JzZXJ2ZWQtYXJtZWQtc3RhdHVzLmpzb25cIiB3aXRoIHsgdHlwZTogXCJqc29uXCIgfTtcbmltcG9ydCBMQVRFU1RBVFVTIGZyb20gXCIuL2ZpeHR1cmVzL29ic2VydmVkLWxhdGUtY29uZmxpY3Rpbmctc3RhdHVzLmpzb25cIiB3aXRoIHsgdHlwZTogXCJqc29uXCIgfTtcbmltcG9ydCBMQVRFUkVDT1ZFUlkgZnJvbSBcIi4vZml4dHVyZXMvb2JzZXJ2ZWQtbGF0ZS1vcmlnaW5hbC1yZXF1ZXN0LXJlY292ZXJ5Lmpzb25cIiB3aXRoIHsgdHlwZTogXCJqc29uXCIgfTtcbmltcG9ydCBJTkNPTVBMRVRFIGZyb20gXCIuL2ZpeHR1cmVzL29ic2VydmVkLWluY29tcGxldGUtYXJjaGl2ZS5qc29uXCIgd2l0aCB7IHR5cGU6IFwianNvblwiIH07XG5jb25zdCBhcmNoaXZlUGF5bG9hZCA9ICgpOiBKc29uID0+ICh7cm91dGU6QUNLLnJvdXRlLGF0dGVtcHRfaWQ6QUNLLmF0dGVtcHRfaWQsZmVuY2VfdmVyc2lvbjpBQ0suZmVuY2VfdmVyc2lvbixib2R5X3NoYTI1NjpBQ0suYm9keV9zaGEyNTYsZGVzdGluYXRpb25fc2hhMjU2OkFDSy5kZXN0aW5hdGlvbl9zaGEyNTYsY2FsbGJhY2tfcmVxdWVzdHM6QUNLLmNhbGxiYWNrX3JlcXVlc3RzfSk7XG5EZW5vLnRlc3QoXCJhY3R1YWwgU1FMIGNhbGxiYWNrIG9ic2VydmF0aW9ucyBzdXJ2aXZlIHJldm9rZWQgZGV2aWNlIGFuZCBleGFjdCByb3V0ZVwiLCBhc3luYygpPT57XG4gZm9yKGNvbnN0IGNiIG9mIENBTExCQUNLUyl7Y29uc3QgZj1hd2FpdCBmaXh0dXJlKGNiLnJlc3VsdCxEYXRlLnBhcnNlKGNiLnJlc3VsdC5yZWNvcmRlZF9hdCksXCJyZXZva2VkXCIsbnVsbCxPQlNHUkFOVC5kZXZpY2VfaWQpO2NvbnN0IGU9ey4uLmVudmVsb3BlKFwiY2FsbGJhY2tcIixjYi5yZXF1ZXN0X2lkLGNiLnBheWxvYWQsY2IucmVzdWx0LnJlY29yZGVkX2F0KSxkZXZpY2VfaWQ6T0JTR1JBTlQuZGV2aWNlX2lkfTtjb25zdCByPWF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnNpZ25lZChlKSk7YXNzZXJ0RXF1YWxzKHIuc3RhdHVzLDIwMCk7YXNzZXJ0RXF1YWxzKChhd2FpdCByLmpzb24oKSkucmVzdWx0LGNiLnJlc3VsdCk7YXNzZXJ0RXF1YWxzKGYuY2FsbHNbMV0ubmFtZSxcImdhdGV3YXlfcmVjZWlwdF9zdWNjZXNzb3JfY2FsbGJhY2tfdjFcIik7fVxufSk7XG5EZW5vLnRlc3QoXCJhY3R1YWwgU1FMIGN1cnJlbnQgYW5kIGxhdGUgY29udHJhZGljdG9yeSBzdGF0dXMgcmVtYWluIG5vbmF1dGhvcml6aW5nXCIsIGFzeW5jKCk9PntcbiBmb3IoY29uc3Qgc3Qgb2YgW1NUQVRVUyxMQVRFU1RBVFVTXSl7Y29uc3QgaWQ9Y3J5cHRvLnJhbmRvbVVVSUQoKTtjb25zdCBwPXtyb3V0ZTpzdC5yb3V0ZSxhdHRlbXB0X2lkOnN0LmF0dGVtcHRfaWQsZmVuY2VfdmVyc2lvbjpzdC5mZW5jZV92ZXJzaW9ufTtjb25zdCBmPWF3YWl0IGZpeHR1cmUoc3QsRGF0ZS5wYXJzZShPQlNHUkFOVC5pc3N1ZWRfYXQpLFwicmV2b2tlZFwiLG51bGwsT0JTR1JBTlQuZGV2aWNlX2lkKTtjb25zdCByPWF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnNpZ25lZCh7Li4uZW52ZWxvcGUoXCJhdHRlbXB0X3N0YXR1c1wiLGlkLHAsT0JTR1JBTlQuaXNzdWVkX2F0KSxkZXZpY2VfaWQ6T0JTR1JBTlQuZGV2aWNlX2lkfSkpO2Fzc2VydEVxdWFscyhyLnN0YXR1cywyMDApO2Fzc2VydEVxdWFscygoYXdhaXQgci5qc29uKCkpLnJlc3VsdCxzdCk7YXNzZXJ0RXF1YWxzKGYuY2FsbHNbMV0ubmFtZSxcImdhdGV3YXlfcmVjZWlwdF9zdWNjZXNzb3JfYXR0ZW1wdF9zdGF0dXNfdjFcIik7fVxufSk7XG5EZW5vLnRlc3QoXCJhY3R1YWwgU1FMIGFyY2hpdmUgQUNLIGJpbmRzIGV4YWN0IGNhbGxiYWNrIG9yaWdpbmFscyB3aXRob3V0IGRlbGl2ZXJ5IGNsYWltXCIsYXN5bmMoKT0+e1xuIGNvbnN0IGY9YXdhaXQgZml4dHVyZShBQ0ssRGF0ZS5wYXJzZShBQ0sucmVjb3JkZWRfYXQpLFwicmV2b2tlZFwiLG51bGwsT0JTR1JBTlQuZGV2aWNlX2lkKTtjb25zdCByPWF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnNpZ25lZCh7Li4uZW52ZWxvcGUoXCJhcmNoaXZlX2F0dGVtcHRcIixBQ0sucmVxdWVzdF9pZCxhcmNoaXZlUGF5bG9hZCgpLEFDSy5yZWNvcmRlZF9hdCksZGV2aWNlX2lkOk9CU0dSQU5ULmRldmljZV9pZH0pKTthc3NlcnRFcXVhbHMoci5zdGF0dXMsMjAwKTthc3NlcnRFcXVhbHMoKGF3YWl0IHIuanNvbigpKS5yZXN1bHQsQUNLKTthc3NlcnRFcXVhbHMoZi5jYWxsc1sxXS5uYW1lLFwiZ2F0ZXdheV9yZWNlaXB0X3N1Y2Nlc3Nvcl9hcmNoaXZlX3YxXCIpO2Fzc2VydEVxdWFscyhBQ0suZGVsaXZlcnlfcHJvdmVuLGZhbHNlKTtcbn0pO1xuRGVuby50ZXN0KFwiYWN0dWFsIFNRTCBpbmNvbXBsZXRlIGFyY2hpdmUgcmVtYWlucyBhbiBleHBsaWNpdCBpbW11dGFibGUgcmVmdXNhbFwiLGFzeW5jKCk9PntcbiBhc3NlcnRFcXVhbHMoYXdhaXQgcmVzdWx0KFwiYXJjaGl2ZV9hdHRlbXB0XCIsSU5DT01QTEVURSxJTkNPTVBMRVRFLmRldmljZV9pZCxJTkNPTVBMRVRFLnJlcXVlc3RfaWQsYXJjaGl2ZVBheWxvYWQoKSxEYXRlLnBhcnNlKEFDSy5yZWNvcmRlZF9hdCkpLHRydWUpO1xufSk7XG5EZW5vLnRlc3QoXCJhY3R1YWwgbGF0ZSBvcmlnaW5hbCBVVUlEIHJlY29uY2lsaWF0aW9uIGtlZXBzIGNvbnRyYWRpY3RvcnkgZmFjdHNcIixhc3luYygpPT57XG4gY29uc3QgaWQ9Y3J5cHRvLnJhbmRvbVVVSUQoKTtjb25zdCBmPWF3YWl0IGZpeHR1cmUoTEFURVJFQ09WRVJZLERhdGUucGFyc2UoT0JTR1JBTlQuaXNzdWVkX2F0KSxcInJldm9rZWRcIixudWxsLE9CU0dSQU5ULmRldmljZV9pZCk7Y29uc3Qgcj1hd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoey4uLmVudmVsb3BlKFwicmVjb25jaWxlXCIsaWQse3RhcmdldF9yZXF1ZXN0X2lkOkxBVEVSRUNPVkVSWS50YXJnZXRfcmVxdWVzdF9pZH0sT0JTR1JBTlQuaXNzdWVkX2F0KSxkZXZpY2VfaWQ6T0JTR1JBTlQuZGV2aWNlX2lkfSkpO2Fzc2VydEVxdWFscyhyLnN0YXR1cywyMDApO2Fzc2VydEVxdWFscygoYXdhaXQgci5qc29uKCkpLnJlc3VsdCxMQVRFUkVDT1ZFUlkpO1xufSk7XG5EZW5vLnRlc3QoXCJjYWxsYmFjayByb3V0ZSBhbmQgY2xvc2VkIGZhY3RzIGNhbm5vdCBpbnZlbnQgZGVsaXZlcnkgb3Igc2VuZCBwZXJtaXNzaW9uXCIsYXN5bmMoKT0+e1xuIGNvbnN0IGNiPUNBTExCQUNLU1swXTtmb3IoY29uc3QgcGF0Y2ggb2YgW3tkZWxpdmVyeV9wcm92ZW46dHJ1ZX0se3NlbmRfYXV0aG9yaXR5OnRydWV9LHtleHRyYTp0cnVlfSx7cm91dGU6ey4uLmNiLnJlc3VsdC5yb3V0ZSxkaXNwYXRjaF9qb2JfaWQ6Y3J5cHRvLnJhbmRvbVVVSUQoKX19LHtzZW50X29ic2VydmF0aW9uczoxMX1dKWFzc2VydEVxdWFscyhhd2FpdCByZXN1bHQoXCJjYWxsYmFja1wiLHsuLi5jYi5yZXN1bHQsLi4ucGF0Y2h9LE9CU0dSQU5ULmRldmljZV9pZCxjYi5yZXF1ZXN0X2lkLGNiLnBheWxvYWQsRGF0ZS5wYXJzZShjYi5yZXN1bHQucmVjb3JkZWRfYXQpKSxmYWxzZSk7XG59KTtcbkRlbm8udGVzdChcImFyY2hpdmUgYWx0ZXJlZCBleGFjdCBvcmlnaW5hbCByZWZlcmVuY2VzIGFuZCBvbGQgcmVjZWlwdCBhbGlhc2VzIGFyZSByZWZ1c2VkXCIsYXN5bmMoKT0+e1xuIGZvcihjb25zdCBwYXRjaCBvZiBbe3JlY2VpcHRfaWQ6QUNLLnJvdXRlLmRpc3BhdGNoX2pvYl9pZH0se2NhbGxiYWNrX3JlcXVlc3RzOkFDSy5jYWxsYmFja19yZXF1ZXN0cy5tYXAoKHYsaSk9Pmk/IHY6ey4uLnYscmVxdWVzdF9zaGEyNTY6XCIwXCIucmVwZWF0KDY0KX0pfSx7cm91dGU6ey4uLkFDSy5yb3V0ZSxhcHByb3ZhbF9pZDpjcnlwdG8ucmFuZG9tVVVJRCgpfX0se2pvdXJuYWxfYWNrOmZhbHNlfV0pYXNzZXJ0RXF1YWxzKGF3YWl0IHJlc3VsdChcImFyY2hpdmVfYXR0ZW1wdFwiLHsuLi5BQ0ssLi4ucGF0Y2h9LE9CU0dSQU5ULmRldmljZV9pZCxBQ0sucmVxdWVzdF9pZCxhcmNoaXZlUGF5bG9hZCgpLERhdGUucGFyc2UoQUNLLnJlY29yZGVkX2F0KSksZmFsc2UpO1xufSk7XG5EZW5vLnRlc3QoXCJyZWNvcmRlZCBjYWxsYmFjayBhbmQgYXJjaGl2ZSByZWNvbmNpbGlhdGlvbiByZWplY3RzIHBlcm1pc3NpdmUgbmVzdGVkIHJlc3VsdHNcIixhc3luYygpPT57XG4gY29uc3QgcD17dGFyZ2V0X3JlcXVlc3RfaWQ6TEFURVJFQ09WRVJZLnRhcmdldF9yZXF1ZXN0X2lkfTtmb3IoY29uc3QgcGF0Y2ggb2YgW3tyZWNvcmRlZF9yZXN1bHQ6ey4uLkxBVEVSRUNPVkVSWS5yZWNvcmRlZF9yZXN1bHQsZXh0cmE6dHJ1ZX19LHtyZWNvcmRlZF9yb3V0ZTp7Li4uTEFURVJFQ09WRVJZLnJlY29yZGVkX3JvdXRlLGFwcHJvdmFsX2lkOmNyeXB0by5yYW5kb21VVUlEKCl9fSx7cmVjb3JkZWRfcmVzdWx0OnsuLi5MQVRFUkVDT1ZFUlkucmVjb3JkZWRfcmVzdWx0LHNlbmRfYXV0aG9yaXR5OnRydWV9fV0pYXNzZXJ0RXF1YWxzKGF3YWl0IHJlc3VsdChcInJlY29uY2lsZVwiLHsuLi5MQVRFUkVDT1ZFUlksLi4ucGF0Y2h9LE9CU0dSQU5ULmRldmljZV9pZCxjcnlwdG8ucmFuZG9tVVVJRCgpLHAsRGF0ZS5wYXJzZShPQlNHUkFOVC5pc3N1ZWRfYXQpKSxmYWxzZSk7XG59KTtcbkRlbm8udGVzdChcIndyb25nIGV4YWN0IHNpZ25hdHVyZSBuZXZlciByZWFjaGVzIHRoZSBtdXRhdGlvbiBSUENcIixhc3luYygpPT57XG4gY29uc3QgZj1hd2FpdCBmaXh0dXJlKEdSQU5UKTtjb25zdCByZXF1ZXN0PWF3YWl0IGYuc2lnbmVkKGVudmVsb3BlKFwiZGlzcGF0Y2hfZ3JhbnRcIixHUkFOVC5yZXF1ZXN0X2lkLHt9KSk7Y29uc3QgaD1uZXcgSGVhZGVycyhyZXF1ZXN0LmhlYWRlcnMpO2guc2V0KFwiWC1Db2xsZWN0LUdhdGV3YXktU2lnbmF0dXJlXCIsYjY0KGRlcihuZXcgVWludDhBcnJheSg2NCkuZmlsbCgxKSkpKTtjb25zdCByPWF3YWl0IGYuaGFuZGxlcihuZXcgUmVxdWVzdChyZXF1ZXN0LnVybCx7bWV0aG9kOlwiUE9TVFwiLGhlYWRlcnM6aCxib2R5OmF3YWl0IHJlcXVlc3QuYXJyYXlCdWZmZXIoKX0pKTthc3NlcnRFcXVhbHMoci5zdGF0dXMsNDAxKTthc3NlcnRFcXVhbHMoZi5jYWxscy5sZW5ndGgsMSk7XG59KTtcbkRlbm8udGVzdChcImJvdW5kZWQgU1FMIHRpbWVvdXQgcmV0dXJucyB1bmtub3duIGFuZCBwZXJmb3JtcyBvbmUgbXV0YXRpb24gaW52b2NhdGlvblwiLGFzeW5jKCk9PntcbiBjb25zdCBmPWF3YWl0IGZpeHR1cmUoR1JBTlQpO2xldCBtdXRhdGlvbnM9MDtjb25zdCB0aW1lZD1jcmVhdGVTdWNjZXNzb3JHYXRld2F5SGFuZGxlcih7Li4uZi5kZXBzLHRpbWVvdXRNczo1LHJwYzoobmFtZSxhcmdzLHNpZ25hbCk9PntpZihuYW1lPT09XCJnYXRld2F5X2RldmljZV9rZXlfdjFcIilyZXR1cm4gZi5kZXBzLnJwYyhuYW1lLGFyZ3Msc2lnbmFsKTttdXRhdGlvbnMrKztyZXR1cm4gbmV3IFByb21pc2UoKCk9Pnt9KTt9fSk7Y29uc3Qgcj1hd2FpdCB0aW1lZChhd2FpdCBmLnNpZ25lZChlbnZlbG9wZShcImRpc3BhdGNoX2dyYW50XCIsR1JBTlQucmVxdWVzdF9pZCx7fSkpKTthc3NlcnRFcXVhbHMoci5zdGF0dXMsNTA0KTthc3NlcnRFcXVhbHMoKGF3YWl0IHIuanNvbigpKS5zZW5kX2F1dGhvcml0eSxmYWxzZSk7YXNzZXJ0RXF1YWxzKG11dGF0aW9ucywxKTthc3NlcnRFcXVhbHMoZi5jYWxscy5sZW5ndGgsMSk7XG59KTtcbkRlbm8udGVzdChcIm92ZXJzaXplZCBhbmQgbWFsZm9ybWVkIFVURjggYm9kaWVzIGFyZSByZWplY3RlZCBiZWZvcmUga2V5IGRpc2NvdmVyeVwiLGFzeW5jKCk9PntcbiBjb25zdCBmPWF3YWl0IGZpeHR1cmUoR1JBTlQpO2Zvcihjb25zdCBieXRlcyBvZiBbbmV3IFVpbnQ4QXJyYXkoODE5MykuZmlsbCgzMiksbmV3IFVpbnQ4QXJyYXkoWzB4ZmYsMHhmZV0pXSl7Y29uc3Qgcj1hd2FpdCBmLmhhbmRsZXIobmV3IFJlcXVlc3QoXCJodHRwczovL2dhdGV3YXkudGVzdFwiLHttZXRob2Q6XCJQT1NUXCIsaGVhZGVyczp7XCJjb250ZW50LXR5cGVcIjpcImFwcGxpY2F0aW9uL2pzb25cIn0sYm9keTpieXRlc30pKTthc3NlcnRFcXVhbHMoWzQwMCw0MTNdLmluY2x1ZGVzKHIuc3RhdHVzKSx0cnVlKTt9YXNzZXJ0RXF1YWxzKGYuY2FsbHMubGVuZ3RoLDApO1xufSk7XG4iXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IkFBQUEsU0FBUyxZQUFZLFFBQVEsNEJBQTRCO0FBQ3pELFNBQVMsNkJBQTZCLFFBQW9DLGVBQWU7QUFDekYsU0FBUyxRQUFRLEVBQUUsTUFBTSxFQUFFLE1BQU0sRUFBYSxNQUFNLEVBQUUsS0FBSyxRQUFRLFlBQVk7QUFDL0UsT0FBTyxXQUFXLHNEQUFzRDtFQUFFLE1BQU07QUFBTyxFQUFFO0FBQ3pGLE9BQU8sU0FBUyxvREFBb0Q7RUFBRSxNQUFNO0FBQU8sRUFBRTtBQUNyRixPQUFPLGNBQWMscURBQXFEO0VBQUUsTUFBTTtBQUFPLEVBQUU7QUFDM0YsTUFBTSxTQUFTLE1BQU0sU0FBUztBQUM5QixNQUFNLFNBQVMsSUFBSTtBQUNuQixNQUFNLE1BQU0sQ0FBQyxJQUFrQixLQUFLLE9BQU8sWUFBWSxJQUFJO0FBQzNELE1BQU0sT0FBTyxDQUFJLElBQVksZ0JBQWdCO0FBQzdDLFNBQVMsSUFBSSxHQUFlO0VBQzNCLE1BQU0sUUFBUTtJQUFDLElBQUksS0FBSyxDQUFDLEdBQUU7SUFBSSxJQUFJLEtBQUssQ0FBQztHQUFJLENBQUMsR0FB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
// denoCacheMetadata=1487968169689227354,7166962035504520752
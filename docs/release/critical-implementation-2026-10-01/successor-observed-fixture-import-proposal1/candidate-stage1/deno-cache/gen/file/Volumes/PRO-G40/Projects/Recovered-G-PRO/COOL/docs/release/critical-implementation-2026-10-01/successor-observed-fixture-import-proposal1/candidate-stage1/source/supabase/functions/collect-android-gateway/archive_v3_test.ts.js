import { assertEquals } from "../_shared/test_assert.ts";
import { createGatewayHandler } from "./handler.ts";
import { archivePayload, archiveResult } from "./archive_v3.ts";
const ID = (i)=>`ab770000-0000-4000-8000-${String(i).padStart(12, "0")}`;
const NOW = Date.parse("2026-10-01T13:00:00Z");
const TIME = new Date(NOW).toISOString();
const refs = [
  {
    callback_id: ID(5),
    request_id: ID(7),
    request_sha256: "d".repeat(64)
  },
  {
    callback_id: ID(6),
    request_id: ID(8),
    request_sha256: "e".repeat(64)
  }
];
function payload() {
  return {
    attempt_id: ID(3),
    fence_version: 1,
    body_sha256: "b".repeat(64),
    destination_sha256: "c".repeat(64),
    callback_requests: structuredClone(refs)
  };
}
function ack() {
  return {
    request_id: ID(2),
    device_id: ID(1),
    attempt_id: ID(3),
    fence_version: 1,
    ok: true,
    code: null,
    archive_ack_id: ID(9),
    receipt_id: ID(4),
    body_sha256: "b".repeat(64),
    destination_sha256: "c".repeat(64),
    segment_count: 1,
    callback_requests: structuredClone(refs),
    recorded_at: TIME,
    replay: false,
    evidence_kind: "complete_framework_callback_observations",
    carrier_proof: false,
    delivery_proven: false,
    send_authority: false
  };
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
const b64 = (b)=>btoa(String.fromCharCode(...b));
async function sha(b) {
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(b))), (x)=>x.toString(16).padStart(2, "0")).join("");
}
async function exercise(envelope, result = ack(), mutate) {
  const key = await crypto.subtle.generateKey({
    name: "ECDSA",
    namedCurve: "P-256"
  }, true, [
    "sign",
    "verify"
  ]);
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", key.publicKey));
  const fingerprint = await sha(spki);
  const calls = [];
  let receivedDigest = "";
  const handler = createGatewayHandler({
    now: ()=>NOW,
    rpc: (name, args)=>{
      calls.push(name);
      if (name === "gateway_device_key_v1") {
        return Promise.resolve({
          data: {
            device_id: envelope.device_id,
            state: "revoked",
            public_key_spki_base64: b64(spki),
            key_sha256: fingerprint,
            installation_id: ID(10),
            signing_certificate_sha256: "a".repeat(64)
          },
          error: null
        });
      }
      receivedDigest = String(args.p_request_sha256);
      return Promise.resolve({
        data: result,
        error: null
      });
    }
  });
  const bytes = new TextEncoder().encode(JSON.stringify(envelope));
  const signature = der(new Uint8Array(await crypto.subtle.sign({
    name: "ECDSA",
    hash: "SHA-256"
  }, key.privateKey, new Uint8Array(bytes))));
  const response = await handler(new Request("https://example.test", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "X-Collect-Gateway-Key-Id": fingerprint,
      "X-Collect-Gateway-Signature": b64(signature)
    },
    body: new Uint8Array(mutate ? mutate(bytes) : bytes)
  }));
  return {
    status: response.status,
    body: await response.json(),
    calls,
    receivedDigest,
    digest: await sha(bytes)
  };
}
const envelope = (p = payload(), patch = {})=>({
    contract_version: 3,
    action: "archive_attempt",
    device_id: ID(1),
    request_id: ID(2),
    issued_at: TIME,
    payload: p,
    ...patch
  });
Deno.test("archive v3 real P256 exact byte signature permits revoked prior evidence only", async ()=>{
  const r = await exercise(envelope());
  assertEquals(r.status, 200);
  assertEquals(r.body.contract_version, 3);
  assertEquals(r.calls, [
    "gateway_device_key_v1",
    "gateway_archive_attempt_v3"
  ]);
  assertEquals(r.receivedDigest, r.digest);
  assertEquals(r.body.result.delivery_proven, false);
  assertEquals(r.body.result.send_authority, false);
});
for (const [name, bad] of [
  [
    "caller destination",
    {
      ...payload(),
      destination_e164: "+250788000001"
    }
  ],
  [
    "fractional fence",
    {
      ...payload(),
      fence_version: 1.5
    }
  ],
  [
    "null references",
    {
      ...payload(),
      callback_requests: null
    }
  ],
  [
    "duplicate request UUID",
    {
      ...payload(),
      callback_requests: [
        refs[0],
        refs[0]
      ]
    }
  ],
  [
    "odd callback set",
    {
      ...payload(),
      callback_requests: [
        refs[0]
      ]
    }
  ],
  [
    "client outcome",
    {
      ...payload(),
      delivery_proven: true
    }
  ]
]){
  Deno.test(`archive v3 rejects ${name} before key lookup`, async ()=>{
    const r = await exercise(envelope(bad));
    assertEquals(r.status, 400);
    assertEquals(r.calls, []);
  });
}
for (const field of [
  "carrier_proof",
  "delivery_proven",
  "send_authority"
]){
  Deno.test(`archive v3 rejects invented ${field} on outbound result`, async ()=>{
    assertEquals((await exercise(envelope(), {
      ...ack(),
      [field]: true
    })).status, 502);
  });
}
for (const field of [
  "body",
  "destination_e164",
  "balances",
  "service_key"
]){
  Deno.test(`archive v3 redacts unexpected ${field}`, async ()=>{
    const r = await exercise(envelope(), {
      ...ack(),
      [field]: "private"
    });
    assertEquals(r.status, 502);
    assertEquals(JSON.stringify(r.body).includes("private"), false);
  });
}
for (const patch of [
  {
    request_id: ID(50)
  },
  {
    device_id: ID(50)
  },
  {
    fence_version: 2
  },
  {
    segment_count: 2
  },
  {
    callback_requests: refs.slice().reverse()
  }
]){
  Deno.test(`archive v3 binds outbound ${Object.keys(patch)[0]}`, async ()=>{
    assertEquals((await exercise(envelope(), {
      ...ack(),
      ...patch
    })).status, 502);
  });
}
Deno.test("archive v3 mutation tamper cannot become an ACK", async ()=>{
  assertEquals((await exercise(envelope(), ack(), (b)=>{
    const c = b.slice();
    c[c.length - 10] ^= 1;
    return c;
  })).status < 500, true);
});
Deno.test("archive v3 old signed timestamp refuses before lookup", async ()=>{
  assertEquals((await exercise(envelope(payload(), {
    issued_at: "2026-10-01T12:57:59Z"
  }))).status, 400);
});
Deno.test("archive v3 never adds grant action to new version", async ()=>{
  const r = await exercise(envelope({}, {
    action: "dispatch_grant"
  }));
  assertEquals(r.status, 400);
  assertEquals(r.calls, []);
});
Deno.test("archive v3 unknown original UUID lookup is truthful", async ()=>{
  const p = {
    target_request_id: ID(40)
  };
  const result = {
    target_request_id: ID(40),
    outcome: "unknown",
    recorded_result: null
  };
  const r = await exercise(envelope(p, {
    action: "archive_lookup"
  }), result);
  assertEquals(r.status, 200);
  assertEquals(r.calls[1], "gateway_archive_lookup_v3");
});
Deno.test("archive v3 lookup cannot disclose mismatched original receipt", async ()=>{
  const r = await exercise(envelope({
    target_request_id: ID(40)
  }, {
    action: "archive_lookup"
  }), {
    target_request_id: ID(40),
    outcome: "recorded",
    recorded_result: ack()
  });
  assertEquals(r.status, 502);
});
Deno.test("archive v3 lookup target must differ from read identity", ()=>{
  assertEquals(archivePayload("archive_lookup", {
    target_request_id: ID(2)
  }, ID(2)), false);
});
Deno.test("archive v3 refused evidence never exposes receipt or references", ()=>{
  const refusal = {
    ...ack(),
    ok: false,
    code: "CALLBACK_EVIDENCE_INCOMPLETE",
    archive_ack_id: null,
    receipt_id: null,
    callback_requests: null,
    evidence_kind: null
  };
  assertEquals(archiveResult("archive_attempt", refusal, ID(1), ID(2), payload()), true);
  assertEquals(archiveResult("archive_attempt", {
    ...refusal,
    receipt_id: ID(4)
  }, ID(1), ID(2), payload()), false);
});
for (const name of [
  "ack",
  "lookup",
  "unknown",
  "incomplete"
]){
  Deno.test(`archive v3 actual synthetic SQL ${name} satisfies signed outbound boundary`, async ()=>{
    const observed = JSON.parse(await Deno.readTextFile(`contracts/collect-android-attempt-archive-v3/fixtures/observed-${name}.json`));
    let e;
    if (name === "lookup" || name === "unknown") {
      const device = observed.recorded_result?.device_id ?? ID(1);
      e = envelope({
        target_request_id: observed.target_request_id
      }, {
        action: "archive_lookup",
        device_id: device
      });
    } else {
      const refs = observed.callback_requests ?? payload().callback_requests;
      e = envelope({
        attempt_id: observed.attempt_id,
        fence_version: observed.fence_version,
        body_sha256: observed.body_sha256,
        destination_sha256: observed.destination_sha256,
        callback_requests: refs
      }, {
        request_id: observed.request_id,
        device_id: observed.device_id
      });
    }
    const result = await exercise(e, observed);
    assertEquals(result.status, 200);
    assertEquals(result.body.result, observed);
  });
}
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2NvbGxlY3QtYW5kcm9pZC1nYXRld2F5L2FyY2hpdmVfdjNfdGVzdC50cyJdLCJzb3VyY2VzQ29udGVudCI6WyJpbXBvcnQgeyBhc3NlcnRFcXVhbHMgfSBmcm9tIFwiLi4vX3NoYXJlZC90ZXN0X2Fzc2VydC50c1wiO1xuaW1wb3J0IHsgY3JlYXRlR2F0ZXdheUhhbmRsZXIgfSBmcm9tIFwiLi9oYW5kbGVyLnRzXCI7XG5pbXBvcnQgeyBhcmNoaXZlUGF5bG9hZCwgYXJjaGl2ZVJlc3VsdCB9IGZyb20gXCIuL2FyY2hpdmVfdjMudHNcIjtcbnR5cGUgSnNvbiA9IFJlY29yZDxzdHJpbmcsIHVua25vd24+O1xuY29uc3QgSUQgPSAoaTogbnVtYmVyKSA9PlxuICBgYWI3NzAwMDAtMDAwMC00MDAwLTgwMDAtJHtTdHJpbmcoaSkucGFkU3RhcnQoMTIsIFwiMFwiKX1gO1xuY29uc3QgTk9XID0gRGF0ZS5wYXJzZShcIjIwMjYtMTAtMDFUMTM6MDA6MDBaXCIpO1xuY29uc3QgVElNRSA9IG5ldyBEYXRlKE5PVykudG9JU09TdHJpbmcoKTtcbmNvbnN0IHJlZnMgPSBbe1xuICBjYWxsYmFja19pZDogSUQoNSksXG4gIHJlcXVlc3RfaWQ6IElEKDcpLFxuICByZXF1ZXN0X3NoYTI1NjogXCJkXCIucmVwZWF0KDY0KSxcbn0sIHsgY2FsbGJhY2tfaWQ6IElEKDYpLCByZXF1ZXN0X2lkOiBJRCg4KSwgcmVxdWVzdF9zaGEyNTY6IFwiZVwiLnJlcGVhdCg2NCkgfV07XG5mdW5jdGlvbiBwYXlsb2FkKCk6IEpzb24ge1xuICByZXR1cm4ge1xuICAgIGF0dGVtcHRfaWQ6IElEKDMpLFxuICAgIGZlbmNlX3ZlcnNpb246IDEsXG4gICAgYm9keV9zaGEyNTY6IFwiYlwiLnJlcGVhdCg2NCksXG4gICAgZGVzdGluYXRpb25fc2hhMjU2OiBcImNcIi5yZXBlYXQoNjQpLFxuICAgIGNhbGxiYWNrX3JlcXVlc3RzOiBzdHJ1Y3R1cmVkQ2xvbmUocmVmcyksXG4gIH07XG59XG5mdW5jdGlvbiBhY2soKTogSnNvbiB7XG4gIHJldHVybiB7XG4gICAgcmVxdWVzdF9pZDogSUQoMiksXG4gICAgZGV2aWNlX2lkOiBJRCgxKSxcbiAgICBhdHRlbXB0X2lkOiBJRCgzKSxcbiAgICBmZW5jZV92ZXJzaW9uOiAxLFxuICAgIG9rOiB0cnVlLFxuICAgIGNvZGU6IG51bGwsXG4gICAgYXJjaGl2ZV9hY2tfaWQ6IElEKDkpLFxuICAgIHJlY2VpcHRfaWQ6IElEKDQpLFxuICAgIGJvZHlfc2hhMjU2OiBcImJcIi5yZXBlYXQoNjQpLFxuICAgIGRlc3RpbmF0aW9uX3NoYTI1NjogXCJjXCIucmVwZWF0KDY0KSxcbiAgICBzZWdtZW50X2NvdW50OiAxLFxuICAgIGNhbGxiYWNrX3JlcXVlc3RzOiBzdHJ1Y3R1cmVkQ2xvbmUocmVmcyksXG4gICAgcmVjb3JkZWRfYXQ6IFRJTUUsXG4gICAgcmVwbGF5OiBmYWxzZSxcbiAgICBldmlkZW5jZV9raW5kOiBcImNvbXBsZXRlX2ZyYW1ld29ya19jYWxsYmFja19vYnNlcnZhdGlvbnNcIixcbiAgICBjYXJyaWVyX3Byb29mOiBmYWxzZSxcbiAgICBkZWxpdmVyeV9wcm92ZW46IGZhbHNlLFxuICAgIHNlbmRfYXV0aG9yaXR5OiBmYWxzZSxcbiAgfTtcbn1cbmZ1bmN0aW9uIGRlcihyYXc6IFVpbnQ4QXJyYXkpOiBVaW50OEFycmF5IHtcbiAgY29uc3QgcGFydHMgPSBbcmF3LnNsaWNlKDAsIDMyKSwgcmF3LnNsaWNlKDMyKV0ubWFwKChwKSA9PiB7XG4gICAgd2hpbGUgKHAubGVuZ3RoID4gMSAmJiBwWzBdID09PSAwKSBwID0gcC5zbGljZSgxKTtcbiAgICBpZiAocFswXSAmIDEyOCkgcCA9IFVpbnQ4QXJyYXkuZnJvbShbMCwgLi4ucF0pO1xuICAgIHJldHVybiBVaW50OEFycmF5LmZyb20oWzIsIHAubGVuZ3RoLCAuLi5wXSk7XG4gIH0pO1xuICByZXR1cm4gVWludDhBcnJheS5mcm9tKFtcbiAgICA0OCxcbiAgICBwYXJ0c1swXS5sZW5ndGggKyBwYXJ0c1sxXS5sZW5ndGgsXG4gICAgLi4ucGFydHNbMF0sXG4gICAgLi4ucGFydHNbMV0sXG4gIF0pO1xufVxuY29uc3QgYjY0ID0gKGI6IFVpbnQ4QXJyYXkpID0+IGJ0b2EoU3RyaW5nLmZyb21DaGFyQ29kZSguLi5iKSk7XG5hc3luYyBmdW5jdGlvbiBzaGEoYjogVWludDhBcnJheSk6IFByb21pc2U8c3RyaW5nPiB7XG4gIHJldHVybiBBcnJheS5mcm9tKFxuICAgIG5ldyBVaW50OEFycmF5KGF3YWl0IGNyeXB0by5zdWJ0bGUuZGlnZXN0KFwiU0hBLTI1NlwiLCBuZXcgVWludDhBcnJheShiKSkpLFxuICAgICh4KSA9PiB4LnRvU3RyaW5nKDE2KS5wYWRTdGFydCgyLCBcIjBcIiksXG4gICkuam9pbihcIlwiKTtcbn1cbmFzeW5jIGZ1bmN0aW9uIGV4ZXJjaXNlKFxuICBlbnZlbG9wZTogSnNvbixcbiAgcmVzdWx0OiB1bmtub3duID0gYWNrKCksXG4gIG11dGF0ZT86IChieXRlczogVWludDhBcnJheSkgPT4gVWludDhBcnJheSxcbikge1xuICBjb25zdCBrZXkgPSBhd2FpdCBjcnlwdG8uc3VidGxlLmdlbmVyYXRlS2V5KFxuICAgIHsgbmFtZTogXCJFQ0RTQVwiLCBuYW1lZEN1cnZlOiBcIlAtMjU2XCIgfSxcbiAgICB0cnVlLFxuICAgIFtcInNpZ25cIiwgXCJ2ZXJpZnlcIl0sXG4gICk7XG4gIGNvbnN0IHNwa2kgPSBuZXcgVWludDhBcnJheShcbiAgICBhd2FpdCBjcnlwdG8uc3VidGxlLmV4cG9ydEtleShcInNwa2lcIiwga2V5LnB1YmxpY0tleSksXG4gICk7XG4gIGNvbnN0IGZpbmdlcnByaW50ID0gYXdhaXQgc2hhKHNwa2kpO1xuICBjb25zdCBjYWxsczogc3RyaW5nW10gPSBbXTtcbiAgbGV0IHJlY2VpdmVkRGlnZXN0ID0gXCJcIjtcbiAgY29uc3QgaGFuZGxlciA9IGNyZWF0ZUdhdGV3YXlIYW5kbGVyKHtcbiAgICBub3c6ICgpID0+IE5PVyxcbiAgICBycGM6IChuYW1lLCBhcmdzKSA9PiB7XG4gICAgICBjYWxscy5wdXNoKG5hbWUpO1xuICAgICAgaWYgKG5hbWUgPT09IFwiZ2F0ZXdheV9kZXZpY2Vfa2V5X3YxXCIpIHtcbiAgICAgICAgcmV0dXJuIFByb21pc2UucmVzb2x2ZSh7XG4gICAgICAgICAgZGF0YToge1xuICAgICAgICAgICAgZGV2aWNlX2lkOiBlbnZlbG9wZS5kZXZpY2VfaWQsXG4gICAgICAgICAgICBzdGF0ZTogXCJyZXZva2VkXCIsXG4gICAgICAgICAgICBwdWJsaWNfa2V5X3Nwa2lfYmFzZTY0OiBiNjQoc3BraSksXG4gICAgICAgICAgICBrZXlfc2hhMjU2OiBmaW5nZXJwcmludCxcbiAgICAgICAgICAgIGluc3RhbGxhdGlvbl9pZDogSUQoMTApLFxuICAgICAgICAgICAgc2lnbmluZ19jZXJ0aWZpY2F0ZV9zaGEyNTY6IFwiYVwiLnJlcGVhdCg2NCksXG4gICAgICAgICAgfSxcbiAgICAgICAgICBlcnJvcjogbnVsbCxcbiAgICAgICAgfSk7XG4gICAgICB9XG4gICAgICByZWNlaXZlZERpZ2VzdCA9IFN0cmluZyhhcmdzLnBfcmVxdWVzdF9zaGEyNTYpO1xuICAgICAgcmV0dXJuIFByb21pc2UucmVzb2x2ZSh7IGRhdGE6IHJlc3VsdCwgZXJyb3I6IG51bGwgfSk7XG4gICAgfSxcbiAgfSk7XG4gIGNvbnN0IGJ5dGVzID0gbmV3IFRleHRFbmNvZGVyKCkuZW5jb2RlKEpTT04uc3RyaW5naWZ5KGVudmVsb3BlKSk7XG4gIGNvbnN0IHNpZ25hdHVyZSA9IGRlcihcbiAgICBuZXcgVWludDhBcnJheShcbiAgICAgIGF3YWl0IGNyeXB0by5zdWJ0bGUuc2lnbihcbiAgICAgICAgeyBuYW1lOiBcIkVDRFNBXCIsIGhhc2g6IFwiU0hBLTI1NlwiIH0sXG4gICAgICAgIGtleS5wcml2YXRlS2V5LFxuICAgICAgICBuZXcgVWludDhBcnJheShieXRlcyksXG4gICAgICApLFxuICAgICksXG4gICk7XG4gIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgaGFuZGxlcihcbiAgICBuZXcgUmVxdWVzdChcImh0dHBzOi8vZXhhbXBsZS50ZXN0XCIsIHtcbiAgICAgIG1ldGhvZDogXCJQT1NUXCIsXG4gICAgICBoZWFkZXJzOiB7XG4gICAgICAgIFwiY29udGVudC10eXBlXCI6IFwiYXBwbGljYXRpb24vanNvblwiLFxuICAgICAgICBcIlgtQ29sbGVjdC1HYXRld2F5LUtleS1JZFwiOiBmaW5nZXJwcmludCxcbiAgICAgICAgXCJYLUNvbGxlY3QtR2F0ZXdheS1TaWduYXR1cmVcIjogYjY0KHNpZ25hdHVyZSksXG4gICAgICB9LFxuICAgICAgYm9keTogbmV3IFVpbnQ4QXJyYXkobXV0YXRlID8gbXV0YXRlKGJ5dGVzKSA6IGJ5dGVzKSxcbiAgICB9KSxcbiAgKTtcbiAgcmV0dXJuIHtcbiAgICBzdGF0dXM6IHJlc3BvbnNlLnN0YXR1cyxcbiAgICBib2R5OiBhd2FpdCByZXNwb25zZS5qc29uKCksXG4gICAgY2FsbHMsXG4gICAgcmVjZWl2ZWREaWdlc3QsXG4gICAgZGlnZXN0OiBhd2FpdCBzaGEoYnl0ZXMpLFxuICB9O1xufVxuY29uc3QgZW52ZWxvcGUgPSAocDogdW5rbm93biA9IHBheWxvYWQoKSwgcGF0Y2g6IEpzb24gPSB7fSk6IEpzb24gPT4gKHtcbiAgY29udHJhY3RfdmVyc2lvbjogMyxcbiAgYWN0aW9uOiBcImFyY2hpdmVfYXR0ZW1wdFwiLFxuICBkZXZpY2VfaWQ6IElEKDEpLFxuICByZXF1ZXN0X2lkOiBJRCgyKSxcbiAgaXNzdWVkX2F0OiBUSU1FLFxuICBwYXlsb2FkOiBwLFxuICAuLi5wYXRjaCxcbn0pO1xuRGVuby50ZXN0KFwiYXJjaGl2ZSB2MyByZWFsIFAyNTYgZXhhY3QgYnl0ZSBzaWduYXR1cmUgcGVybWl0cyByZXZva2VkIHByaW9yIGV2aWRlbmNlIG9ubHlcIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCByID0gYXdhaXQgZXhlcmNpc2UoZW52ZWxvcGUoKSk7XG4gIGFzc2VydEVxdWFscyhyLnN0YXR1cywgMjAwKTtcbiAgYXNzZXJ0RXF1YWxzKHIuYm9keS5jb250cmFjdF92ZXJzaW9uLCAzKTtcbiAgYXNzZXJ0RXF1YWxzKHIuY2FsbHMsIFtcbiAgICBcImdhdGV3YXlfZGV2aWNlX2tleV92MVwiLFxuICAgIFwiZ2F0ZXdheV9hcmNoaXZlX2F0dGVtcHRfdjNcIixcbiAgXSk7XG4gIGFzc2VydEVxdWFscyhyLnJlY2VpdmVkRGlnZXN0LCByLmRpZ2VzdCk7XG4gIGFzc2VydEVxdWFscyhyLmJvZHkucmVzdWx0LmRlbGl2ZXJ5X3Byb3ZlbiwgZmFsc2UpO1xuICBhc3NlcnRFcXVhbHMoci5ib2R5LnJlc3VsdC5zZW5kX2F1dGhvcml0eSwgZmFsc2UpO1xufSk7XG5mb3IgKFxuICBjb25zdCBbbmFtZSwgYmFkXSBvZiBbXG4gICAgW1wiY2FsbGVyIGRlc3RpbmF0aW9uXCIsIHsgLi4ucGF5bG9hZCgpLCBkZXN0aW5hdGlvbl9lMTY0OiBcIisyNTA3ODgwMDAwMDFcIiB9XSxcbiAgICBbXCJmcmFjdGlvbmFsIGZlbmNlXCIsIHsgLi4ucGF5bG9hZCgpLCBmZW5jZV92ZXJzaW9uOiAxLjUgfV0sXG4gICAgW1wibnVsbCByZWZlcmVuY2VzXCIsIHsgLi4ucGF5bG9hZCgpLCBjYWxsYmFja19yZXF1ZXN0czogbnVsbCB9XSxcbiAgICBbXCJkdXBsaWNhdGUgcmVxdWVzdCBVVUlEXCIsIHtcbiAgICAgIC4uLnBheWxvYWQoKSxcbiAgICAgIGNhbGxiYWNrX3JlcXVlc3RzOiBbcmVmc1swXSwgcmVmc1swXV0sXG4gICAgfV0sXG4gICAgW1wib2RkIGNhbGxiYWNrIHNldFwiLCB7IC4uLnBheWxvYWQoKSwgY2FsbGJhY2tfcmVxdWVzdHM6IFtyZWZzWzBdXSB9XSxcbiAgICBbXCJjbGllbnQgb3V0Y29tZVwiLCB7IC4uLnBheWxvYWQoKSwgZGVsaXZlcnlfcHJvdmVuOiB0cnVlIH1dLFxuICBdIGFzIGNvbnN0XG4pIHtcbiAgRGVuby50ZXN0KGBhcmNoaXZlIHYzIHJlamVjdHMgJHtuYW1lfSBiZWZvcmUga2V5IGxvb2t1cGAsIGFzeW5jICgpID0+IHtcbiAgICBjb25zdCByID0gYXdhaXQgZXhlcmNpc2UoZW52ZWxvcGUoYmFkKSk7XG4gICAgYXNzZXJ0RXF1YWxzKHIuc3RhdHVzLCA0MDApO1xuICAgIGFzc2VydEVxdWFscyhyLmNhbGxzLCBbXSk7XG4gIH0pO1xufVxuZm9yIChjb25zdCBmaWVsZCBvZiBbXCJjYXJyaWVyX3Byb29mXCIsIFwiZGVsaXZlcnlfcHJvdmVuXCIsIFwic2VuZF9hdXRob3JpdHlcIl0pIHtcbiAgRGVuby50ZXN0KGBhcmNoaXZlIHYzIHJlamVjdHMgaW52ZW50ZWQgJHtmaWVsZH0gb24gb3V0Ym91bmQgcmVzdWx0YCwgYXN5bmMgKCkgPT4ge1xuICAgIGFzc2VydEVxdWFscyhcbiAgICAgIChhd2FpdCBleGVyY2lzZShlbnZlbG9wZSgpLCB7IC4uLmFjaygpLCBbZmllbGRdOiB0cnVlIH0pKS5zdGF0dXMsXG4gICAgICA1MDIsXG4gICAgKTtcbiAgfSk7XG59XG5mb3IgKGNvbnN0IGZpZWxkIG9mIFtcImJvZHlcIiwgXCJkZXN0aW5hdGlvbl9lMTY0XCIsIFwiYmFsYW5jZXNcIiwgXCJzZXJ2aWNlX2tleVwiXSkge1xuICBEZW5vLnRlc3QoYGFyY2hpdmUgdjMgcmVkYWN0cyB1bmV4cGVjdGVkICR7ZmllbGR9YCwgYXN5bmMgKCkgPT4ge1xuICAgIGNvbnN0IHIgPSBhd2FpdCBleGVyY2lzZShlbnZlbG9wZSgpLCB7IC4uLmFjaygpLCBbZmllbGRdOiBcInByaXZhdGVcIiB9KTtcbiAgICBhc3NlcnRFcXVhbHMoci5zdGF0dXMsIDUwMik7XG4gICAgYXNzZXJ0RXF1YWxzKEpTT04uc3RyaW5naWZ5KHIuYm9keSkuaW5jbHVkZXMoXCJwcml2YXRlXCIpLCBmYWxzZSk7XG4gIH0pO1xufVxuZm9yIChcbiAgY29uc3QgcGF0Y2ggb2YgW1xuICAgIHsgcmVxdWVzdF9pZDogSUQoNTApIH0sXG4gICAgeyBkZXZpY2VfaWQ6IElEKDUwKSB9LFxuICAgIHsgZmVuY2VfdmVyc2lvbjogMiB9LFxuICAgIHsgc2VnbWVudF9jb3VudDogMiB9LFxuICAgIHsgY2FsbGJhY2tfcmVxdWVzdHM6IHJlZnMuc2xpY2UoKS5yZXZlcnNlKCkgfSxcbiAgXVxuKSB7XG4gIERlbm8udGVzdChgYXJjaGl2ZSB2MyBiaW5kcyBvdXRib3VuZCAke09iamVjdC5rZXlzKHBhdGNoKVswXX1gLCBhc3luYyAoKSA9PiB7XG4gICAgYXNzZXJ0RXF1YWxzKFxuICAgICAgKGF3YWl0IGV4ZXJjaXNlKGVudmVsb3BlKCksIHsgLi4uYWNrKCksIC4uLnBhdGNoIH0pKS5zdGF0dXMsXG4gICAgICA1MDIsXG4gICAgKTtcbiAgfSk7XG59XG5EZW5vLnRlc3QoXCJhcmNoaXZlIHYzIG11dGF0aW9uIHRhbXBlciBjYW5ub3QgYmVjb21lIGFuIEFDS1wiLCBhc3luYyAoKSA9PiB7XG4gIGFzc2VydEVxdWFscyhcbiAgICAoYXdhaXQgZXhlcmNpc2UoZW52ZWxvcGUoKSwgYWNrKCksIChiKSA9PiB7XG4gICAgICBjb25zdCBjID0gYi5zbGljZSgpO1xuICAgICAgY1tjLmxlbmd0aCAtIDEwXSBePSAxO1xuICAgICAgcmV0dXJuIGM7XG4gICAgfSkpLnN0YXR1cyA8IDUwMCxcbiAgICB0cnVlLFxuICApO1xufSk7XG5EZW5vLnRlc3QoXCJhcmNoaXZlIHYzIG9sZCBzaWduZWQgdGltZXN0YW1wIHJlZnVzZXMgYmVmb3JlIGxvb2t1cFwiLCBhc3luYyAoKSA9PiB7XG4gIGFzc2VydEVxdWFscyhcbiAgICAoYXdhaXQgZXhlcmNpc2UoZW52ZWxvcGUocGF5bG9hZCgpLCB7IGlzc3VlZF9hdDogXCIyMDI2LTEwLTAxVDEyOjU3OjU5WlwiIH0pKSlcbiAgICAgIC5zdGF0dXMsXG4gICAgNDAwLFxuICApO1xufSk7XG5EZW5vLnRlc3QoXCJhcmNoaXZlIHYzIG5ldmVyIGFkZHMgZ3JhbnQgYWN0aW9uIHRvIG5ldyB2ZXJzaW9uXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgciA9IGF3YWl0IGV4ZXJjaXNlKGVudmVsb3BlKHt9LCB7IGFjdGlvbjogXCJkaXNwYXRjaF9ncmFudFwiIH0pKTtcbiAgYXNzZXJ0RXF1YWxzKHIuc3RhdHVzLCA0MDApO1xuICBhc3NlcnRFcXVhbHMoci5jYWxscywgW10pO1xufSk7XG5EZW5vLnRlc3QoXCJhcmNoaXZlIHYzIHVua25vd24gb3JpZ2luYWwgVVVJRCBsb29rdXAgaXMgdHJ1dGhmdWxcIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCBwID0geyB0YXJnZXRfcmVxdWVzdF9pZDogSUQoNDApIH07XG4gIGNvbnN0IHJlc3VsdCA9IHtcbiAgICB0YXJnZXRfcmVxdWVzdF9pZDogSUQoNDApLFxuICAgIG91dGNvbWU6IFwidW5rbm93blwiLFxuICAgIHJlY29yZGVkX3Jlc3VsdDogbnVsbCxcbiAgfTtcbiAgY29uc3QgciA9IGF3YWl0IGV4ZXJjaXNlKGVudmVsb3BlKHAsIHsgYWN0aW9uOiBcImFyY2hpdmVfbG9va3VwXCIgfSksIHJlc3VsdCk7XG4gIGFzc2VydEVxdWFscyhyLnN0YXR1cywgMjAwKTtcbiAgYXNzZXJ0RXF1YWxzKHIuY2FsbHNbMV0sIFwiZ2F0ZXdheV9hcmNoaXZlX2xvb2t1cF92M1wiKTtcbn0pO1xuRGVuby50ZXN0KFwiYXJjaGl2ZSB2MyBsb29rdXAgY2Fubm90IGRpc2Nsb3NlIG1pc21hdGNoZWQgb3JpZ2luYWwgcmVjZWlwdFwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IHIgPSBhd2FpdCBleGVyY2lzZShcbiAgICBlbnZlbG9wZSh7IHRhcmdldF9yZXF1ZXN0X2lkOiBJRCg0MCkgfSwgeyBhY3Rpb246IFwiYXJjaGl2ZV9sb29rdXBcIiB9KSxcbiAgICB7IHRhcmdldF9yZXF1ZXN0X2lkOiBJRCg0MCksIG91dGNvbWU6IFwicmVjb3JkZWRcIiwgcmVjb3JkZWRfcmVzdWx0OiBhY2soKSB9LFxuICApO1xuICBhc3NlcnRFcXVhbHMoci5zdGF0dXMsIDUwMik7XG59KTtcbkRlbm8udGVzdChcImFyY2hpdmUgdjMgbG9va3VwIHRhcmdldCBtdXN0IGRpZmZlciBmcm9tIHJlYWQgaWRlbnRpdHlcIiwgKCkgPT4ge1xuICBhc3NlcnRFcXVhbHMoXG4gICAgYXJjaGl2ZVBheWxvYWQoXCJhcmNoaXZlX2xvb2t1cFwiLCB7IHRhcmdldF9yZXF1ZXN0X2lkOiBJRCgyKSB9LCBJRCgyKSksXG4gICAgZmFsc2UsXG4gICk7XG59KTtcbkRlbm8udGVzdChcImFyY2hpdmUgdjMgcmVmdXNlZCBldmlkZW5jZSBuZXZlciBleHBvc2VzIHJlY2VpcHQgb3IgcmVmZXJlbmNlc1wiLCAoKSA9PiB7XG4gIGNvbnN0IHJlZnVzYWwgPSB7XG4gICAgLi4uYWNrKCksXG4gICAgb2s6IGZhbHNlLFxuICAgIGNvZGU6IFwiQ0FMTEJBQ0tfRVZJREVOQ0VfSU5DT01QTEVURVwiLFxuICAgIGFyY2hpdmVfYWNrX2lkOiBudWxsLFxuICAgIHJlY2VpcHRfaWQ6IG51bGwsXG4gICAgY2FsbGJhY2tfcmVxdWVzdHM6IG51bGwsXG4gICAgZXZpZGVuY2Vfa2luZDogbnVsbCxcbiAgfTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIGFyY2hpdmVSZXN1bHQoXCJhcmNoaXZlX2F0dGVtcHRcIiwgcmVmdXNhbCwgSUQoMSksIElEKDIpLCBwYXlsb2FkKCkpLFxuICAgIHRydWUsXG4gICk7XG4gIGFzc2VydEVxdWFscyhcbiAgICBhcmNoaXZlUmVzdWx0KFxuICAgICAgXCJhcmNoaXZlX2F0dGVtcHRcIixcbiAgICAgIHsgLi4ucmVmdXNhbCwgcmVjZWlwdF9pZDogSUQoNCkgfSxcbiAgICAgIElEKDEpLFxuICAgICAgSUQoMiksXG4gICAgICBwYXlsb2FkKCksXG4gICAgKSxcbiAgICBmYWxzZSxcbiAgKTtcbn0pO1xuXG5mb3IgKGNvbnN0IG5hbWUgb2YgW1wiYWNrXCIsIFwibG9va3VwXCIsIFwidW5rbm93blwiLCBcImluY29tcGxldGVcIl0pIHtcbiAgRGVuby50ZXN0KGBhcmNoaXZlIHYzIGFjdHVhbCBzeW50aGV0aWMgU1FMICR7bmFtZX0gc2F0aXNmaWVzIHNpZ25lZCBvdXRib3VuZCBib3VuZGFyeWAsIGFzeW5jICgpID0+IHtcbiAgICBjb25zdCBvYnNlcnZlZCA9IEpTT04ucGFyc2UoXG4gICAgICBhd2FpdCBEZW5vLnJlYWRUZXh0RmlsZShcbiAgICAgICAgYGNvbnRyYWN0cy9jb2xsZWN0LWFuZHJvaWQtYXR0ZW1wdC1hcmNoaXZlLXYzL2ZpeHR1cmVzL29ic2VydmVkLSR7bmFtZX0uanNvbmAsXG4gICAgICApLFxuICAgICk7XG4gICAgbGV0IGU6IEpzb247XG4gICAgaWYgKG5hbWUgPT09IFwibG9va3VwXCIgfHwgbmFtZSA9PT0gXCJ1bmtub3duXCIpIHtcbiAgICAgIGNvbnN0IGRldmljZSA9IG9ic2VydmVkLnJlY29yZGVkX3Jlc3VsdD8uZGV2aWNlX2lkID8/IElEKDEpO1xuICAgICAgZSA9IGVudmVsb3BlKHsgdGFyZ2V0X3JlcXVlc3RfaWQ6IG9ic2VydmVkLnRhcmdldF9yZXF1ZXN0X2lkIH0sIHtcbiAgICAgICAgYWN0aW9uOiBcImFyY2hpdmVfbG9va3VwXCIsXG4gICAgICAgIGRldmljZV9pZDogZGV2aWNlLFxuICAgICAgfSk7XG4gICAgfSBlbHNlIHtcbiAgICAgIGNvbnN0IHJlZnMgPSBvYnNlcnZlZC5jYWxsYmFja19yZXF1ZXN0cyA/PyBwYXlsb2FkKCkuY2FsbGJhY2tfcmVxdWVzdHM7XG4gICAgICBlID0gZW52ZWxvcGUoe1xuICAgICAgICBhdHRlbXB0X2lkOiBvYnNlcnZlZC5hdHRlbXB0X2lkLFxuICAgICAgICBmZW5jZV92ZXJzaW9uOiBvYnNlcnZlZC5mZW5jZV92ZXJzaW9uLFxuICAgICAgICBib2R5X3NoYTI1Njogb2JzZXJ2ZWQuYm9keV9zaGEyNTYsXG4gICAgICAgIGRlc3RpbmF0aW9uX3NoYTI1Njogb2JzZXJ2ZWQuZGVzdGluYXRpb25fc2hhMjU2LFxuICAgICAgICBjYWxsYmFja19yZXF1ZXN0czogcmVmcyxcbiAgICAgIH0sIHsgcmVxdWVzdF9pZDogb2JzZXJ2ZWQucmVxdWVzdF9pZCwgZGV2aWNlX2lkOiBvYnNlcnZlZC5kZXZpY2VfaWQgfSk7XG4gICAgfVxuICAgIGNvbnN0IHJlc3VsdCA9IGF3YWl0IGV4ZXJjaXNlKGUsIG9ic2VydmVkKTtcbiAgICBhc3NlcnRFcXVhbHMocmVzdWx0LnN0YXR1cywgMjAwKTtcbiAgICBhc3NlcnRFcXVhbHMocmVzdWx0LmJvZHkucmVzdWx0LCBvYnNlcnZlZCk7XG4gIH0pO1xufVxuIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiJBQUFBLFNBQVMsWUFBWSxRQUFRLDRCQUE0QjtBQUN6RCxTQUFTLG9CQUFvQixRQUFRLGVBQWU7QUFDcEQsU0FBUyxjQUFjLEVBQUUsYUFBYSxRQUFRLGtCQUFrQjtBQUVoRSxNQUFNLEtBQUssQ0FBQyxJQUNWLENBQUMsd0JBQXdCLEVBQUUsT0FBTyxHQUFHLFFBQVEsQ0FBQyxJQUFJLE1BQU07QUFDMUQsTUFBTSxNQUFNLEtBQUssS0FBSyxDQUFDO0FBQ3ZCLE1BQU0sT0FBTyxJQUFJLEtBQUssS0FBSyxXQUFXO0FBQ3RDLE1BQU0sT0FBTztFQUFDO0lBQ1osYUFBYSxHQUFHO0lBQ2hCLFlBQVksR0FBRztJQUNmLGdCQUFnQixJQUFJLE1BQU0sQ0FBQztFQUM3QjtFQUFHO0lBQUUsYUFBYSxHQUFHO0lBQUksWUFBWSxHQUFHO0lBQUksZ0JBQWdCLElBQUksTUFBTSxDQUFDO0VBQUk7Q0FBRTtBQUM3RSxTQUFTO0VBQ1AsT0FBTztJQUNMLFlBQVksR0FBRztJQUNmLGVBQWU7SUFDZixhQUFhLElBQUksTUFBTSxDQUFDO0lBQ3hCLG9CQUFvQixJQUFJLE1BQU0sQ0FBQztJQUMvQixtQkFBbUIsZ0JBQWdCO0VBQ3JDO0FBQ0Y7QUFDQSxTQUFTO0VBQ1AsT0FBTztJQUNMLFlBQVksR0FBRztJ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
// denoCacheMetadata=2818966604078155038,6114266769984280958
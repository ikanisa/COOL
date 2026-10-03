import { assertEquals } from "../_shared/test_assert.ts";
import { createGatewayHandler } from "./handler.ts";
// Actual results of the task-private populated SQL UAT; these are synthetic
// contacts and financial records, never production rows or a current permit.
const fixtureRoot = new URL("../../../contracts/collect-android-dispatch-v2/fixtures/", import.meta.url);
const fixtures = {};
for (const name of [
  "grant",
  "arm",
  "grant-paused",
  "grant-reconciliation",
  "partial-callback",
  "complete-callback",
  "contradictory-callback",
  "status"
]){
  fixtures[name] = JSON.parse(await Deno.readTextFile(new URL(`observed-${name}.json`, fixtureRoot)));
}
const grant = fixtures.grant;
const encoder = new TextEncoder();
const b64 = (bytes)=>btoa(String.fromCharCode(...bytes));
async function digest(bytes) {
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes))), (n)=>n.toString(16).padStart(2, "0")).join("");
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
async function check(name, action, payload, patch = {}) {
  const result = {
    ...fixtures[name],
    ...patch
  };
  const recordedTime = result.issued_at ?? result.armed_at ?? result.recorded_at ?? grant.issued_at;
  const now = Date.parse(recordedTime);
  const requestId = result.request_id ?? "80ca0000-0000-4000-8000-000000000001";
  const pair = await crypto.subtle.generateKey({
    name: "ECDSA",
    namedCurve: "P-256"
  }, true, [
    "sign",
    "verify"
  ]);
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", pair.publicKey));
  const keyId = await digest(spki);
  const bytes = encoder.encode(JSON.stringify({
    contract_version: 2,
    action,
    device_id: grant.device_id,
    request_id: requestId,
    issued_at: new Date(now).toISOString(),
    payload
  }));
  const signature = der(new Uint8Array(await crypto.subtle.sign({
    name: "ECDSA",
    hash: "SHA-256"
  }, pair.privateKey, bytes)));
  const requestDigest = await digest(bytes);
  let called = "";
  const handler = createGatewayHandler({
    now: ()=>now,
    rpc: (name, args)=>{
      if (name === "gateway_device_key_v1") {
        return Promise.resolve({
          data: {
            device_id: grant.device_id,
            state: "active",
            public_key_spki_base64: b64(spki),
            key_sha256: keyId,
            installation_id: grant.run_id,
            signing_certificate_sha256: "f".repeat(64)
          },
          error: null
        });
      }
      called = name;
      assertEquals(args.p_request_sha256, requestDigest);
      return Promise.resolve({
        data: result,
        error: null
      });
    }
  });
  // No HTTP/network operation: Request is passed to the actual handler directly.
  const response = await handler(new Request("https://gateway.test/collect-android-gateway", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "X-Collect-Gateway-Key-Id": keyId,
      "X-Collect-Gateway-Signature": b64(signature)
    },
    body: bytes
  }));
  return {
    response,
    called,
    result
  };
}
const callbackPayload = (result)=>({
    callback_id: result.callback_id,
    attempt_id: grant.attempt_id,
    fence_version: grant.fence_version,
    segment_index: result.callback_id === fixtures["complete-callback"].callback_id ? 1 : 0,
    segment_count: grant.segment_count,
    body_sha256: grant.body_sha256,
    destination_sha256: grant.destination_sha256,
    callback_kind: "sent",
    result_code: result.state === "uncertain" ? 1 : -1,
    tp_status: null,
    occurred_at: result.recorded_at
  });
const cases = [
  [
    "grant",
    "dispatch_grant",
    {}
  ],
  [
    "grant-paused",
    "dispatch_grant",
    {}
  ],
  [
    "arm",
    "arm_dispatch",
    {
      attempt_id: grant.attempt_id,
      fence_version: grant.fence_version,
      body_sha256: grant.body_sha256,
      destination_sha256: grant.destination_sha256,
      reservation_sha256: fixtures.arm.reservation_sha256,
      callbacks: [
        0,
        1
      ].map((segment_index)=>({
          segment_index,
          sent_callback_id: segment_index ? fixtures["complete-callback"].callback_id : fixtures["partial-callback"].callback_id,
          delivery_callback_id: `80ca0000-0000-4000-8000-00000000000${segment_index + 2}`
        }))
    }
  ],
  [
    "grant-reconciliation",
    "reconcile",
    {
      target_request_id: grant.request_id
    }
  ],
  ...[
    "partial-callback",
    "complete-callback",
    "contradictory-callback"
  ].map((name)=>[
      name,
      "callback",
      callbackPayload(fixtures[name])
    ]),
  [
    "status",
    "attempt_status",
    {
      attempt_id: grant.attempt_id,
      fence_version: grant.fence_version
    }
  ]
];
for (const [name, action, payload] of cases){
  Deno.test(`actual populated SQL ${name} passes signed Edge output contract`, async ()=>{
    const { response, result } = await check(name, action, payload);
    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.result, result);
    assertEquals(response.headers.get("cache-control"), "no-store");
  });
}
Deno.test("actual SQL grant with corrupted immutable digest is unknown", async ()=>{
  const { response } = await check("grant", "dispatch_grant", {}, {
    body_sha256: "0".repeat(64)
  });
  assertEquals(response.status, 502);
});
Deno.test("actual SQL recovered request with leaked body is unknown", async ()=>{
  const source = fixtures["grant-reconciliation"];
  const { response } = await check("grant-reconciliation", "reconcile", {
    target_request_id: grant.request_id
  }, {
    recorded_result: {
      ...source.recorded_result,
      body: grant.body
    }
  });
  assertEquals(response.status, 502);
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2NvbGxlY3QtYW5kcm9pZC1nYXRld2F5L2Rpc3BhdGNoX29ic2VydmVkX3Rlc3QudHMiXSwic291cmNlc0NvbnRlbnQiOlsiaW1wb3J0IHsgYXNzZXJ0RXF1YWxzIH0gZnJvbSBcIi4uL19zaGFyZWQvdGVzdF9hc3NlcnQudHNcIjtcbmltcG9ydCB7IGNyZWF0ZUdhdGV3YXlIYW5kbGVyIH0gZnJvbSBcIi4vaGFuZGxlci50c1wiO1xuXG4vLyBBY3R1YWwgcmVzdWx0cyBvZiB0aGUgdGFzay1wcml2YXRlIHBvcHVsYXRlZCBTUUwgVUFUOyB0aGVzZSBhcmUgc3ludGhldGljXG4vLyBjb250YWN0cyBhbmQgZmluYW5jaWFsIHJlY29yZHMsIG5ldmVyIHByb2R1Y3Rpb24gcm93cyBvciBhIGN1cnJlbnQgcGVybWl0LlxuY29uc3QgZml4dHVyZVJvb3QgPSBuZXcgVVJMKFxuICBcIi4uLy4uLy4uL2NvbnRyYWN0cy9jb2xsZWN0LWFuZHJvaWQtZGlzcGF0Y2gtdjIvZml4dHVyZXMvXCIsXG4gIGltcG9ydC5tZXRhLnVybCxcbik7XG5jb25zdCBmaXh0dXJlczogUmVjb3JkPHN0cmluZywgUmVjb3JkPHN0cmluZywgdW5rbm93bj4+ID0ge307XG5mb3IgKFxuICBjb25zdCBuYW1lIG9mIFtcbiAgICBcImdyYW50XCIsXG4gICAgXCJhcm1cIixcbiAgICBcImdyYW50LXBhdXNlZFwiLFxuICAgIFwiZ3JhbnQtcmVjb25jaWxpYXRpb25cIixcbiAgICBcInBhcnRpYWwtY2FsbGJhY2tcIixcbiAgICBcImNvbXBsZXRlLWNhbGxiYWNrXCIsXG4gICAgXCJjb250cmFkaWN0b3J5LWNhbGxiYWNrXCIsXG4gICAgXCJzdGF0dXNcIixcbiAgXVxuKSB7XG4gIGZpeHR1cmVzW25hbWVdID0gSlNPTi5wYXJzZShcbiAgICBhd2FpdCBEZW5vLnJlYWRUZXh0RmlsZShuZXcgVVJMKGBvYnNlcnZlZC0ke25hbWV9Lmpzb25gLCBmaXh0dXJlUm9vdCkpLFxuICApO1xufVxuY29uc3QgZ3JhbnQgPSBmaXh0dXJlcy5ncmFudDtcbmNvbnN0IGVuY29kZXIgPSBuZXcgVGV4dEVuY29kZXIoKTtcbmNvbnN0IGI2NCA9IChieXRlczogVWludDhBcnJheSkgPT4gYnRvYShTdHJpbmcuZnJvbUNoYXJDb2RlKC4uLmJ5dGVzKSk7XG5hc3luYyBmdW5jdGlvbiBkaWdlc3QoYnl0ZXM6IFVpbnQ4QXJyYXkpIHtcbiAgcmV0dXJuIEFycmF5LmZyb20oXG4gICAgbmV3IFVpbnQ4QXJyYXkoXG4gICAgICBhd2FpdCBjcnlwdG8uc3VidGxlLmRpZ2VzdChcIlNIQS0yNTZcIiwgbmV3IFVpbnQ4QXJyYXkoYnl0ZXMpKSxcbiAgICApLFxuICAgIChuKSA9PiBuLnRvU3RyaW5nKDE2KS5wYWRTdGFydCgyLCBcIjBcIiksXG4gICkuam9pbihcIlwiKTtcbn1cbmZ1bmN0aW9uIGRlcihyYXc6IFVpbnQ4QXJyYXkpIHtcbiAgY29uc3QgcGFydHMgPSBbcmF3LnNsaWNlKDAsIDMyKSwgcmF3LnNsaWNlKDMyKV0ubWFwKChwYXJ0KSA9PiB7XG4gICAgd2hpbGUgKHBhcnQubGVuZ3RoID4gMSAmJiBwYXJ0WzBdID09PSAwKSBwYXJ0ID0gcGFydC5zbGljZSgxKTtcbiAgICBpZiAocGFydFswXSAmIDEyOCkgcGFydCA9IFVpbnQ4QXJyYXkuZnJvbShbMCwgLi4ucGFydF0pO1xuICAgIHJldHVybiBVaW50OEFycmF5LmZyb20oWzIsIHBhcnQubGVuZ3RoLCAuLi5wYXJ0XSk7XG4gIH0pO1xuICByZXR1cm4gVWludDhBcnJheS5mcm9tKFtcbiAgICA0OCxcbiAgICBwYXJ0c1swXS5sZW5ndGggKyBwYXJ0c1sxXS5sZW5ndGgsXG4gICAgLi4ucGFydHNbMF0sXG4gICAgLi4ucGFydHNbMV0sXG4gIF0pO1xufVxuXG5hc3luYyBmdW5jdGlvbiBjaGVjayhcbiAgbmFtZTogc3RyaW5nLFxuICBhY3Rpb246IHN0cmluZyxcbiAgcGF5bG9hZDogUmVjb3JkPHN0cmluZywgdW5rbm93bj4sXG4gIHBhdGNoOiBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPiA9IHt9LFxuKSB7XG4gIGNvbnN0IHJlc3VsdCA9IHsgLi4uZml4dHVyZXNbbmFtZV0sIC4uLnBhdGNoIH07XG4gIGNvbnN0IHJlY29yZGVkVGltZSA9XG4gICAgKHJlc3VsdC5pc3N1ZWRfYXQgPz8gcmVzdWx0LmFybWVkX2F0ID8/IHJlc3VsdC5yZWNvcmRlZF9hdCA/P1xuICAgICAgZ3JhbnQuaXNzdWVkX2F0KSBhcyBzdHJpbmc7XG4gIGNvbnN0IG5vdyA9IERhdGUucGFyc2UocmVjb3JkZWRUaW1lKTtcbiAgY29uc3QgcmVxdWVzdElkID1cbiAgICAocmVzdWx0LnJlcXVlc3RfaWQgPz8gXCI4MGNhMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDFcIikgYXMgc3RyaW5nO1xuICBjb25zdCBwYWlyID0gYXdhaXQgY3J5cHRvLnN1YnRsZS5nZW5lcmF0ZUtleShcbiAgICB7IG5hbWU6IFwiRUNEU0FcIiwgbmFtZWRDdXJ2ZTogXCJQLTI1NlwiIH0sXG4gICAgdHJ1ZSxcbiAgICBbXCJzaWduXCIsIFwidmVyaWZ5XCJdLFxuICApO1xuICBjb25zdCBzcGtpID0gbmV3IFVpbnQ4QXJyYXkoXG4gICAgYXdhaXQgY3J5cHRvLnN1YnRsZS5leHBvcnRLZXkoXCJzcGtpXCIsIHBhaXIucHVibGljS2V5KSxcbiAgKTtcbiAgY29uc3Qga2V5SWQgPSBhd2FpdCBkaWdlc3Qoc3BraSk7XG4gIGNvbnN0IGJ5dGVzID0gZW5jb2Rlci5lbmNvZGUoXG4gICAgSlNPTi5zdHJpbmdpZnkoe1xuICAgICAgY29udHJhY3RfdmVyc2lvbjogMixcbiAgICAgIGFjdGlvbixcbiAgICAgIGRldmljZV9pZDogZ3JhbnQuZGV2aWNlX2lkLFxuICAgICAgcmVxdWVzdF9pZDogcmVxdWVzdElkLFxuICAgICAgaXNzdWVkX2F0OiBuZXcgRGF0ZShub3cpLnRvSVNPU3RyaW5nKCksXG4gICAgICBwYXlsb2FkLFxuICAgIH0pLFxuICApO1xuICBjb25zdCBzaWduYXR1cmUgPSBkZXIoXG4gICAgbmV3IFVpbnQ4QXJyYXkoXG4gICAgICBhd2FpdCBjcnlwdG8uc3VidGxlLnNpZ24oXG4gICAgICAgIHsgbmFtZTogXCJFQ0RTQVwiLCBoYXNoOiBcIlNIQS0yNTZcIiB9LFxuICAgICAgICBwYWlyLnByaXZhdGVLZXksXG4gICAgICAgIGJ5dGVzLFxuICAgICAgKSxcbiAgICApLFxuICApO1xuICBjb25zdCByZXF1ZXN0RGlnZXN0ID0gYXdhaXQgZGlnZXN0KGJ5dGVzKTtcbiAgbGV0IGNhbGxlZCA9IFwiXCI7XG4gIGNvbnN0IGhhbmRsZXIgPSBjcmVhdGVHYXRld2F5SGFuZGxlcih7XG4gICAgbm93OiAoKSA9PiBub3csXG4gICAgcnBjOiAobmFtZSwgYXJncykgPT4ge1xuICAgICAgaWYgKG5hbWUgPT09IFwiZ2F0ZXdheV9kZXZpY2Vfa2V5X3YxXCIpIHtcbiAgICAgICAgcmV0dXJuIFByb21pc2UucmVzb2x2ZSh7XG4gICAgICAgICAgZGF0YToge1xuICAgICAgICAgICAgZGV2aWNlX2lkOiBncmFudC5kZXZpY2VfaWQsXG4gICAgICAgICAgICBzdGF0ZTogXCJhY3RpdmVcIixcbiAgICAgICAgICAgIHB1YmxpY19rZXlfc3BraV9iYXNlNjQ6IGI2NChzcGtpKSxcbiAgICAgICAgICAgIGtleV9zaGEyNTY6IGtleUlkLFxuICAgICAgICAgICAgaW5zdGFsbGF0aW9uX2lkOiBncmFudC5ydW5faWQsXG4gICAgICAgICAgICBzaWduaW5nX2NlcnRpZmljYXRlX3NoYTI1NjogXCJmXCIucmVwZWF0KDY0KSxcbiAgICAgICAgICB9LFxuICAgICAgICAgIGVycm9yOiBudWxsLFxuICAgICAgICB9KTtcbiAgICAgIH1cbiAgICAgIGNhbGxlZCA9IG5hbWU7XG4gICAgICBhc3NlcnRFcXVhbHMoYXJncy5wX3JlcXVlc3Rfc2hhMjU2LCByZXF1ZXN0RGlnZXN0KTtcbiAgICAgIHJldHVybiBQcm9taXNlLnJlc29sdmUoeyBkYXRhOiByZXN1bHQsIGVycm9yOiBudWxsIH0pO1xuICAgIH0sXG4gIH0pO1xuICAvLyBObyBIVFRQL25ldHdvcmsgb3BlcmF0aW9uOiBSZXF1ZXN0IGlzIHBhc3NlZCB0byB0aGUgYWN0dWFsIGhhbmRsZXIgZGlyZWN0bHkuXG4gIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgaGFuZGxlcihcbiAgICBuZXcgUmVxdWVzdChcImh0dHBzOi8vZ2F0ZXdheS50ZXN0L2NvbGxlY3QtYW5kcm9pZC1nYXRld2F5XCIsIHtcbiAgICAgIG1ldGhvZDogXCJQT1NUXCIsXG4gICAgICBoZWFkZXJzOiB7XG4gICAgICAgIFwiY29udGVudC10eXBlXCI6IFwiYXBwbGljYXRpb24vanNvblwiLFxuICAgICAgICBcIlgtQ29sbGVjdC1HYXRld2F5LUtleS1JZFwiOiBrZXlJZCxcbiAgICAgICAgXCJYLUNvbGxlY3QtR2F0ZXdheS1TaWduYXR1cmVcIjogYjY0KHNpZ25hdHVyZSksXG4gICAgICB9LFxuICAgICAgYm9keTogYnl0ZXMsXG4gICAgfSksXG4gICk7XG4gIHJldHVybiB7IHJlc3BvbnNlLCBjYWxsZWQsIHJlc3VsdCB9O1xufVxuXG5jb25zdCBjYWxsYmFja1BheWxvYWQgPSAocmVzdWx0OiBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPikgPT4gKHtcbiAgY2FsbGJhY2tfaWQ6IHJlc3VsdC5jYWxsYmFja19pZCxcbiAgYXR0ZW1wdF9pZDogZ3JhbnQuYXR0ZW1wdF9pZCxcbiAgZmVuY2VfdmVyc2lvbjogZ3JhbnQuZmVuY2VfdmVyc2lvbixcbiAgc2VnbWVudF9pbmRleDpcbiAgICByZXN1bHQuY2FsbGJhY2tfaWQgPT09IGZpeHR1cmVzW1wiY29tcGxldGUtY2FsbGJhY2tcIl0uY2FsbGJhY2tfaWQgPyAxIDogMCxcbiAgc2VnbWVudF9jb3VudDogZ3JhbnQuc2VnbWVudF9jb3VudCxcbiAgYm9keV9zaGEyNTY6IGdyYW50LmJvZHlfc2hhMjU2LFxuICBkZXN0aW5hdGlvbl9zaGEyNTY6IGdyYW50LmRlc3RpbmF0aW9uX3NoYTI1NixcbiAgY2FsbGJhY2tfa2luZDogXCJzZW50XCIsXG4gIHJlc3VsdF9jb2RlOiByZXN1bHQuc3RhdGUgPT09IFwidW5jZXJ0YWluXCIgPyAxIDogLTEsXG4gIHRwX3N0YXR1czogbnVsbCxcbiAgb2NjdXJyZWRfYXQ6IHJlc3VsdC5yZWNvcmRlZF9hdCxcbn0pO1xuY29uc3QgY2FzZXM6IFtzdHJpbmcsIHN0cmluZywgUmVjb3JkPHN0cmluZywgdW5rbm93bj5dW10gPSBbXG4gIFtcImdyYW50XCIsIFwiZGlzcGF0Y2hfZ3JhbnRcIiwge31dLFxuICBbXCJncmFudC1wYXVzZWRcIiwgXCJkaXNwYXRjaF9ncmFudFwiLCB7fV0sXG4gIFtcImFybVwiLCBcImFybV9kaXNwYXRjaFwiLCB7XG4gICAgYXR0ZW1wdF9pZDogZ3JhbnQuYXR0ZW1wdF9pZCxcbiAgICBmZW5jZV92ZXJzaW9uOiBncmFudC5mZW5jZV92ZXJzaW9uLFxuICAgIGJvZHlfc2hhMjU2OiBncmFudC5ib2R5X3NoYTI1NixcbiAgICBkZXN0aW5hdGlvbl9zaGEyNTY6IGdyYW50LmRlc3RpbmF0aW9uX3NoYTI1NixcbiAgICByZXNlcnZhdGlvbl9zaGEyNTY6IGZpeHR1cmVzLmFybS5yZXNlcnZhdGlvbl9zaGEyNTYsXG4gICAgY2FsbGJhY2tzOiBbMCwgMV0ubWFwKChzZWdtZW50X2luZGV4KSA9PiAoe1xuICAgICAgc2VnbWVudF9pbmRleCxcbiAgICAgIHNlbnRfY2FsbGJhY2tfaWQ6IHNlZ21lbnRfaW5kZXhcbiAgICAgICAgPyBmaXh0dXJlc1tcImNvbXBsZXRlLWNhbGxiYWNrXCJdLmNhbGxiYWNrX2lkXG4gICAgICAgIDogZml4dHVyZXNbXCJwYXJ0aWFsLWNhbGxiYWNrXCJdLmNhbGxiYWNrX2lkLFxuICAgICAgZGVsaXZlcnlfY2FsbGJhY2tfaWQ6IGA4MGNhMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMCR7XG4gICAgICAgIHNlZ21lbnRfaW5kZXggKyAyXG4gICAgICB9YCxcbiAgICB9KSksXG4gIH1dLFxuICBbXCJncmFudC1yZWNvbmNpbGlhdGlvblwiLCBcInJlY29uY2lsZVwiLCB7XG4gICAgdGFyZ2V0X3JlcXVlc3RfaWQ6IGdyYW50LnJlcXVlc3RfaWQsXG4gIH1dLFxuICAuLi5bXCJwYXJ0aWFsLWNhbGxiYWNrXCIsIFwiY29tcGxldGUtY2FsbGJhY2tcIiwgXCJjb250cmFkaWN0b3J5LWNhbGxiYWNrXCJdLm1hcCgoXG4gICAgbmFtZSxcbiAgKTogW3N0cmluZywgc3RyaW5nLCBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPl0gPT4gW1xuICAgIG5hbWUsXG4gICAgXCJjYWxsYmFja1wiLFxuICAgIGNhbGxiYWNrUGF5bG9hZChmaXh0dXJlc1tuYW1lXSksXG4gIF0pLFxuICBbXCJzdGF0dXNcIiwgXCJhdHRlbXB0X3N0YXR1c1wiLCB7XG4gICAgYXR0ZW1wdF9pZDogZ3JhbnQuYXR0ZW1wdF9pZCxcbiAgICBmZW5jZV92ZXJzaW9uOiBncmFudC5mZW5jZV92ZXJzaW9uLFxuICB9XSxcbl07XG5mb3IgKGNvbnN0IFtuYW1lLCBhY3Rpb24sIHBheWxvYWRdIG9mIGNhc2VzKSB7XG4gIERlbm8udGVzdChgYWN0dWFsIHBvcHVsYXRlZCBTUUwgJHtuYW1lfSBwYXNzZXMgc2lnbmVkIEVkZ2Ugb3V0cHV0IGNvbnRyYWN0YCwgYXN5bmMgKCkgPT4ge1xuICAgIGNvbnN0IHsgcmVzcG9uc2UsIHJlc3VsdCB9ID0gYXdhaXQgY2hlY2sobmFtZSwgYWN0aW9uLCBwYXlsb2FkKTtcbiAgICBhc3NlcnRFcXVhbHMocmVzcG9uc2Uuc3RhdHVzLCAyMDApO1xuICAgIGNvbnN0IGJvZHkgPSBhd2FpdCByZXNwb25zZS5qc29uKCk7XG4gICAgYXNzZXJ0RXF1YWxzKGJvZHkucmVzdWx0LCByZXN1bHQpO1xuICAgIGFzc2VydEVxdWFscyhyZXNwb25zZS5oZWFkZXJzLmdldChcImNhY2hlLWNvbnRyb2xcIiksIFwibm8tc3RvcmVcIik7XG4gIH0pO1xufVxuRGVuby50ZXN0KFwiYWN0dWFsIFNRTCBncmFudCB3aXRoIGNvcnJ1cHRlZCBpbW11dGFibGUgZGlnZXN0IGlzIHVua25vd25cIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCB7IHJlc3BvbnNlIH0gPSBhd2FpdCBjaGVjayhcImdyYW50XCIsIFwiZGlzcGF0Y2hfZ3JhbnRcIiwge30sIHtcbiAgICBib2R5X3NoYTI1NjogXCIwXCIucmVwZWF0KDY0KSxcbiAgfSk7XG4gIGFzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMsIDUwMik7XG59KTtcbkRlbm8udGVzdChcImFjdHVhbCBTUUwgcmVjb3ZlcmVkIHJlcXVlc3Qgd2l0aCBsZWFrZWQgYm9keSBpcyB1bmtub3duXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3Qgc291cmNlID0gZml4dHVyZXNbXCJncmFudC1yZWNvbmNpbGlhdGlvblwiXTtcbiAgY29uc3QgeyByZXNwb25zZSB9ID0gYXdhaXQgY2hlY2soXCJncmFudC1yZWNvbmNpbGlhdGlvblwiLCBcInJlY29uY2lsZVwiLCB7XG4gICAgdGFyZ2V0X3JlcXVlc3RfaWQ6IGdyYW50LnJlcXVlc3RfaWQsXG4gIH0sIHtcbiAgICByZWNvcmRlZF9yZXN1bHQ6IHtcbiAgICAgIC4uLihzb3VyY2UucmVjb3JkZWRfcmVzdWx0IGFzIFJlY29yZDxzdHJpbmcsIHVua25vd24+KSxcbiAgICAgIGJvZHk6IGdyYW50LmJvZHksXG4gICAgfSxcbiAgfSk7XG4gIGFzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMsIDUwMik7XG59KTtcbiJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiQUFBQSxTQUFTLFlBQVksUUFBUSw0QkFBNEI7QUFDekQsU0FBUyxvQkFBb0IsUUFBUSxlQUFlO0FBRXBELDRFQUE0RTtB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
// denoCacheMetadata=10566475804173815269,11088409576442743971
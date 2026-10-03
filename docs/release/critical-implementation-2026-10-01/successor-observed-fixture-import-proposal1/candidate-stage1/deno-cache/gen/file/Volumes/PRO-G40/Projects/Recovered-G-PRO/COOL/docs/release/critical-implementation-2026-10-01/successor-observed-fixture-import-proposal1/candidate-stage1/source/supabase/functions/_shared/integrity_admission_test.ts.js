import { assertEquals } from "./test_assert.ts";
import { PublicError } from "./production_contract.ts";
import { integrityAdmissionError, integrityAdmissionReceipt, integrityResult } from "./integrity_admission.ts";
const binding = {
  actorId: "99570000-0000-4000-8000-000000000001",
  sessionId: "99570000-0000-4000-8000-000000000011",
  nonce: "99570000-0000-4000-8000-000000000031",
  action: "sms.ingest",
  requestHash: "a".repeat(64),
  tokenHash: "b".repeat(64)
};
const future = ()=>new Date(Date.now() + 120_000).toISOString();
const receipt = ()=>({
    contract_version: 1,
    reservation_id: "99570000-0000-4000-8000-000000000041",
    actor_id: binding.actorId,
    session_id: binding.sessionId,
    nonce: binding.nonce,
    action: binding.action,
    request_hash: binding.requestHash,
    token_sha256: binding.tokenHash,
    state: "reserved",
    can_call: true,
    expires_at: future(),
    result: null
  });
const result = ()=>({
    status: "pass",
    action: binding.action,
    request_hash: binding.requestHash,
    package_name: "app.cool.mobile",
    app_verdict: "PLAY_RECOGNIZED",
    device_verdicts: [
      "MEETS_DEVICE_INTEGRITY"
    ],
    native_capability: "99570000-0000-4000-8000-000000000051",
    capability_expires_at: future()
  });
function denied(body, code, status) {
  try {
    body();
  } catch (e) {
    assertEquals(e instanceof PublicError, true);
    assertEquals(e.code, code);
    assertEquals(e.status, status);
    return;
  }
  throw new Error("Expected denial");
}
Deno.test("admission accepts only an exact server reservation and phase receipt", ()=>{
  const r = receipt();
  assertEquals(integrityAdmissionReceipt(r, binding, "reserved").reservationId, r.reservation_id);
  for (const state of [
    "oauth_started",
    "decode_started"
  ]){
    assertEquals(integrityAdmissionReceipt({
      ...r,
      state
    }, binding, state).reservationId, r.reservation_id);
  }
});
Deno.test("admission rejects missing, expanded, malformed and expired receipts", ()=>{
  for (const value of [
    null,
    [],
    {},
    {
      ...receipt(),
      extra: true
    },
    {
      ...receipt(),
      expires_at: "2050-02-30T10:00:00Z"
    },
    {
      ...receipt(),
      expires_at: "2050-01-01"
    },
    {
      ...receipt(),
      expires_at: new Date(Date.now() - 1).toISOString()
    },
    {
      ...receipt(),
      result: {}
    },
    {
      ...receipt(),
      can_call: false
    },
    {
      ...receipt(),
      contract_version: 2
    }
  ]){
    denied(()=>integrityAdmissionReceipt(value, binding, "reserved"), "integrity_admission_invalid", 503);
  }
});
Deno.test("admission rejects actor, exact session, purpose, nonce, content and token substitution", ()=>{
  for (const field of [
    "actor_id",
    "session_id",
    "nonce",
    "action",
    "request_hash",
    "token_sha256",
    "reservation_id",
    "state"
  ]){
    denied(()=>integrityAdmissionReceipt({
        ...receipt(),
        [field]: "substitution"
      }, binding, "reserved"), "integrity_admission_invalid", 503);
  }
});
Deno.test("completed reconciliation is bound and cannot grant transport permission", ()=>{
  const value = result();
  assertEquals(integrityResult(value, binding), value);
  assertEquals(integrityAdmissionReceipt({
    ...receipt(),
    state: "completed",
    can_call: false,
    result: value
  }, binding, "completed").result, value);
  denied(()=>integrityAdmissionReceipt({
      ...receipt(),
      state: "completed",
      can_call: true,
      result: value
    }, binding, "completed"), "integrity_admission_invalid", 503);
});
Deno.test("reconciled capability retains package, verdict, binding and validity requirements", ()=>{
  for (const value of [
    null,
    {},
    {
      ...result(),
      extra: true
    },
    {
      ...result(),
      action: "group.create"
    },
    {
      ...result(),
      request_hash: "c".repeat(64)
    },
    {
      ...result(),
      native_capability: "bad"
    },
    {
      ...result(),
      capability_expires_at: "invalid"
    },
    {
      ...result(),
      capability_expires_at: new Date(Date.now() - 1).toISOString()
    },
    {
      ...result(),
      package_name: "other"
    },
    {
      ...result(),
      app_verdict: "UNEVALUATED"
    },
    {
      ...result(),
      device_verdicts: [
        "MEETS_BASIC_INTEGRITY"
      ]
    },
    {
      ...result(),
      device_verdicts: Array(11).fill("MEETS_DEVICE_INTEGRITY")
    }
  ]){
    denied(()=>integrityResult(value, binding), "integrity_result_unavailable", 409);
  }
});
Deno.test("SQL errors expose stable public codes without private SQL or provider text", ()=>{
  for (const [code, expected, status] of [
    [
      "42501",
      "integrity_admission_forbidden",
      403
    ],
    [
      "22023",
      "invalid_integrity_request",
      400
    ],
    [
      "53300",
      "integrity_resource_limit",
      429
    ],
    [
      "55000",
      "integrity_reconciliation_required",
      409
    ],
    [
      "23505",
      "integrity_reconciliation_required",
      409
    ],
    [
      "PGRST202",
      "integrity_admission_unavailable",
      503
    ]
  ]){
    const error = integrityAdmissionError({
      code,
      message: "private SQL token"
    });
    assertEquals(error.code, expected);
    assertEquals(error.status, status);
  }
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL19zaGFyZWQvaW50ZWdyaXR5X2FkbWlzc2lvbl90ZXN0LnRzIl0sInNvdXJjZXNDb250ZW50IjpbImltcG9ydCB7IGFzc2VydEVxdWFscyB9IGZyb20gXCIuL3Rlc3RfYXNzZXJ0LnRzXCI7XG5pbXBvcnQgeyBQdWJsaWNFcnJvciB9IGZyb20gXCIuL3Byb2R1Y3Rpb25fY29udHJhY3QudHNcIjtcbmltcG9ydCB7XG4gIGludGVncml0eUFkbWlzc2lvbkVycm9yLFxuICBpbnRlZ3JpdHlBZG1pc3Npb25SZWNlaXB0LFxuICBpbnRlZ3JpdHlSZXN1bHQsXG59IGZyb20gXCIuL2ludGVncml0eV9hZG1pc3Npb24udHNcIjtcblxuY29uc3QgYmluZGluZyA9IHtcbiAgYWN0b3JJZDogXCI5OTU3MDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDFcIixcbiAgc2Vzc2lvbklkOiBcIjk5NTcwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAxMVwiLFxuICBub25jZTogXCI5OTU3MDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMzFcIixcbiAgYWN0aW9uOiBcInNtcy5pbmdlc3RcIixcbiAgcmVxdWVzdEhhc2g6IFwiYVwiLnJlcGVhdCg2NCksXG4gIHRva2VuSGFzaDogXCJiXCIucmVwZWF0KDY0KSxcbn07XG5jb25zdCBmdXR1cmUgPSAoKSA9PiBuZXcgRGF0ZShEYXRlLm5vdygpICsgMTIwXzAwMCkudG9JU09TdHJpbmcoKTtcbmNvbnN0IHJlY2VpcHQgPSAoKSA9PiAoe1xuICBjb250cmFjdF92ZXJzaW9uOiAxLFxuICByZXNlcnZhdGlvbl9pZDogXCI5OTU3MDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwNDFcIixcbiAgYWN0b3JfaWQ6IGJpbmRpbmcuYWN0b3JJZCxcbiAgc2Vzc2lvbl9pZDogYmluZGluZy5zZXNzaW9uSWQsXG4gIG5vbmNlOiBiaW5kaW5nLm5vbmNlLFxuICBhY3Rpb246IGJpbmRpbmcuYWN0aW9uLFxuICByZXF1ZXN0X2hhc2g6IGJpbmRpbmcucmVxdWVzdEhhc2gsXG4gIHRva2VuX3NoYTI1NjogYmluZGluZy50b2tlbkhhc2gsXG4gIHN0YXRlOiBcInJlc2VydmVkXCIsXG4gIGNhbl9jYWxsOiB0cnVlLFxuICBleHBpcmVzX2F0OiBmdXR1cmUoKSxcbiAgcmVzdWx0OiBudWxsLFxufSk7XG5jb25zdCByZXN1bHQgPSAoKSA9PiAoe1xuICBzdGF0dXM6IFwicGFzc1wiLFxuICBhY3Rpb246IGJpbmRpbmcuYWN0aW9uLFxuICByZXF1ZXN0X2hhc2g6IGJpbmRpbmcucmVxdWVzdEhhc2gsXG4gIHBhY2thZ2VfbmFtZTogXCJhcHAuY29vbC5tb2JpbGVcIixcbiAgYXBwX3ZlcmRpY3Q6IFwiUExBWV9SRUNPR05JWkVEXCIsXG4gIGRldmljZV92ZXJkaWN0czogW1wiTUVFVFNfREVWSUNFX0lOVEVHUklUWVwiXSxcbiAgbmF0aXZlX2NhcGFiaWxpdHk6IFwiOTk1NzAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDUxXCIsXG4gIGNhcGFiaWxpdHlfZXhwaXJlc19hdDogZnV0dXJlKCksXG59KTtcbmZ1bmN0aW9uIGRlbmllZChib2R5OiAoKSA9PiB1bmtub3duLCBjb2RlOiBzdHJpbmcsIHN0YXR1czogbnVtYmVyKSB7XG4gIHRyeSB7XG4gICAgYm9keSgpO1xuICB9IGNhdGNoIChlKSB7XG4gICAgYXNzZXJ0RXF1YWxzKGUgaW5zdGFuY2VvZiBQdWJsaWNFcnJvciwgdHJ1ZSk7XG4gICAgYXNzZXJ0RXF1YWxzKChlIGFzIFB1YmxpY0Vycm9yKS5jb2RlLCBjb2RlKTtcbiAgICBhc3NlcnRFcXVhbHMoKGUgYXMgUHVibGljRXJyb3IpLnN0YXR1cywgc3RhdHVzKTtcbiAgICByZXR1cm47XG4gIH1cbiAgdGhyb3cgbmV3IEVycm9yKFwiRXhwZWN0ZWQgZGVuaWFsXCIpO1xufVxuRGVuby50ZXN0KFwiYWRtaXNzaW9uIGFjY2VwdHMgb25seSBhbiBleGFjdCBzZXJ2ZXIgcmVzZXJ2YXRpb24gYW5kIHBoYXNlIHJlY2VpcHRcIiwgKCkgPT4ge1xuICBjb25zdCByID0gcmVjZWlwdCgpO1xuICBhc3NlcnRFcXVhbHMoXG4gICAgaW50ZWdyaXR5QWRtaXNzaW9uUmVjZWlwdChyLCBiaW5kaW5nLCBcInJlc2VydmVkXCIpLnJlc2VydmF0aW9uSWQsXG4gICAgci5yZXNlcnZhdGlvbl9pZCxcbiAgKTtcbiAgZm9yIChjb25zdCBzdGF0ZSBvZiBbXCJvYXV0aF9zdGFydGVkXCIsIFwiZGVjb2RlX3N0YXJ0ZWRcIl0pIHtcbiAgICBhc3NlcnRFcXVhbHMoXG4gICAgICBpbnRlZ3JpdHlBZG1pc3Npb25SZWNlaXB0KHsgLi4uciwgc3RhdGUgfSwgYmluZGluZywgc3RhdGUpLnJlc2VydmF0aW9uSWQsXG4gICAgICByLnJlc2VydmF0aW9uX2lkLFxuICAgICk7XG4gIH1cbn0pO1xuRGVuby50ZXN0KFwiYWRtaXNzaW9uIHJlamVjdHMgbWlzc2luZywgZXhwYW5kZWQsIG1hbGZvcm1lZCBhbmQgZXhwaXJlZCByZWNlaXB0c1wiLCAoKSA9PiB7XG4gIGZvciAoXG4gICAgY29uc3QgdmFsdWUgb2YgW1xuICAgICAgbnVsbCxcbiAgICAgIFtdLFxuICAgICAge30sXG4gICAgICB7IC4uLnJlY2VpcHQoKSwgZXh0cmE6IHRydWUgfSxcbiAgICAgIHsgLi4ucmVjZWlwdCgpLCBleHBpcmVzX2F0OiBcIjIwNTAtMDItMzBUMTA6MDA6MDBaXCIgfSxcbiAgICAgIHsgLi4ucmVjZWlwdCgpLCBleHBpcmVzX2F0OiBcIjIwNTAtMDEtMDFcIiB9LFxuICAgICAgeyAuLi5yZWNlaXB0KCksIGV4cGlyZXNfYXQ6IG5ldyBEYXRlKERhdGUubm93KCkgLSAxKS50b0lTT1N0cmluZygpIH0sXG4gICAgICB7IC4uLnJlY2VpcHQoKSwgcmVzdWx0OiB7fSB9LFxuICAgICAgeyAuLi5yZWNlaXB0KCksIGNhbl9jYWxsOiBmYWxzZSB9LFxuICAgICAgeyAuLi5yZWNlaXB0KCksIGNvbnRyYWN0X3ZlcnNpb246IDIgfSxcbiAgICBdXG4gICkge1xuICAgIGRlbmllZChcbiAgICAgICgpID0+IGludGVncml0eUFkbWlzc2lvblJlY2VpcHQodmFsdWUsIGJpbmRpbmcsIFwicmVzZXJ2ZWRcIiksXG4gICAgICBcImludGVncml0eV9hZG1pc3Npb25faW52YWxpZFwiLFxuICAgICAgNTAzLFxuICAgICk7XG4gIH1cbn0pO1xuRGVuby50ZXN0KFwiYWRtaXNzaW9uIHJlamVjdHMgYWN0b3IsIGV4YWN0IHNlc3Npb24sIHB1cnBvc2UsIG5vbmNlLCBjb250ZW50IGFuZCB0b2tlbiBzdWJzdGl0dXRpb25cIiwgKCkgPT4ge1xuICBmb3IgKFxuICAgIGNvbnN0IGZpZWxkIG9mIFtcbiAgICAgIFwiYWN0b3JfaWRcIixcbiAgICAgIFwic2Vzc2lvbl9pZFwiLFxuICAgICAgXCJub25jZVwiLFxuICAgICAgXCJhY3Rpb25cIixcbiAgICAgIFwicmVxdWVzdF9oYXNoXCIsXG4gICAgICBcInRva2VuX3NoYTI1NlwiLFxuICAgICAgXCJyZXNlcnZhdGlvbl9pZFwiLFxuICAgICAgXCJzdGF0ZVwiLFxuICAgIF1cbiAgKSB7XG4gICAgZGVuaWVkKFxuICAgICAgKCkgPT5cbiAgICAgICAgaW50ZWdyaXR5QWRtaXNzaW9uUmVjZWlwdChcbiAgICAgICAgICB7IC4uLnJlY2VpcHQoKSwgW2ZpZWxkXTogXCJzdWJzdGl0dXRpb25cIiB9LFxuICAgICAgICAgIGJpbmRpbmcsXG4gICAgICAgICAgXCJyZXNlcnZlZFwiLFxuICAgICAgICApLFxuICAgICAgXCJpbnRlZ3JpdHlfYWRtaXNzaW9uX2ludmFsaWRcIixcbiAgICAgIDUwMyxcbiAgICApO1xuICB9XG59KTtcbkRlbm8udGVzdChcImNvbXBsZXRlZCByZWNvbmNpbGlhdGlvbiBpcyBib3VuZCBhbmQgY2Fubm90IGdyYW50IHRyYW5zcG9ydCBwZXJtaXNzaW9uXCIsICgpID0+IHtcbiAgY29uc3QgdmFsdWUgPSByZXN1bHQoKTtcbiAgYXNzZXJ0RXF1YWxzKGludGVncml0eVJlc3VsdCh2YWx1ZSwgYmluZGluZyksIHZhbHVlKTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIGludGVncml0eUFkbWlzc2lvblJlY2VpcHQoXG4gICAgICB7IC4uLnJlY2VpcHQoKSwgc3RhdGU6IFwiY29tcGxldGVkXCIsIGNhbl9jYWxsOiBmYWxzZSwgcmVzdWx0OiB2YWx1ZSB9LFxuICAgICAgYmluZGluZyxcbiAgICAgIFwiY29tcGxldGVkXCIsXG4gICAgKS5yZXN1bHQsXG4gICAgdmFsdWUsXG4gICk7XG4gIGRlbmllZChcbiAgICAoKSA9PlxuICAgICAgaW50ZWdyaXR5QWRtaXNzaW9uUmVjZWlwdChcbiAgICAgICAgeyAuLi5yZWNlaXB0KCksIHN0YXRlOiBcImNvbXBsZXRlZFwiLCBjYW5fY2FsbDogdHJ1ZSwgcmVzdWx0OiB2YWx1ZSB9LFxuICAgICAgICBiaW5kaW5nLFxuICAgICAgICBcImNvbXBsZXRlZFwiLFxuICAgICAgKSxcbiAgICBcImludGVncml0eV9hZG1pc3Npb25faW52YWxpZFwiLFxuICAgIDUwMyxcbiAgKTtcbn0pO1xuRGVuby50ZXN0KFwicmVjb25jaWxlZCBjYXBhYmlsaXR5IHJldGFpbnMgcGFja2FnZSwgdmVyZGljdCwgYmluZGluZyBhbmQgdmFsaWRpdHkgcmVxdWlyZW1lbnRzXCIsICgpID0+IHtcbiAgZm9yIChcbiAgICBjb25zdCB2YWx1ZSBvZiBbXG4gICAgICBudWxsLFxuICAgICAge30sXG4gICAgICB7IC4uLnJlc3VsdCgpLCBleHRyYTogdHJ1ZSB9LFxuICAgICAgeyAuLi5yZXN1bHQoKSwgYWN0aW9uOiBcImdyb3VwLmNyZWF0ZVwiIH0sXG4gICAgICB7IC4uLnJlc3VsdCgpLCByZXF1ZXN0X2hhc2g6IFwiY1wiLnJlcGVhdCg2NCkgfSxcbiAgICAgIHsgLi4ucmVzdWx0KCksIG5hdGl2ZV9jYXBhYmlsaXR5OiBcImJhZFwiIH0sXG4gICAgICB7IC4uLnJlc3VsdCgpLCBjYXBhYmlsaXR5X2V4cGlyZXNfYXQ6IFwiaW52YWxpZFwiIH0sXG4gICAgICB7XG4gICAgICAgIC4uLnJlc3VsdCgpLFxuICAgICAgICBjYXBhYmlsaXR5X2V4cGlyZXNfYXQ6IG5ldyBEYXRlKERhdGUubm93KCkgLSAxKS50b0lTT1N0cmluZygpLFxuICAgICAgfSxcbiAgICAgIHsgLi4ucmVzdWx0KCksIHBhY2thZ2VfbmFtZTogXCJvdGhlclwiIH0sXG4gICAgICB7IC4uLnJlc3VsdCgpLCBhcHBfdmVyZGljdDogXCJVTkVWQUxVQVRFRFwiIH0sXG4gICAgICB7IC4uLnJlc3VsdCgpLCBkZXZpY2VfdmVyZGljdHM6IFtcIk1FRVRTX0JBU0lDX0lOVEVHUklUWVwiXSB9LFxuICAgICAge1xuICAgICAgICAuLi5yZXN1bHQoKSxcbiAgICAgICAgZGV2aWNlX3ZlcmRpY3RzOiBBcnJheSgxMSkuZmlsbChcIk1FRVRTX0RFVklDRV9JTlRFR1JJVFlcIiksXG4gICAgICB9LFxuICAgIF1cbiAgKSB7XG4gICAgZGVuaWVkKFxuICAgICAgKCkgPT4gaW50ZWdyaXR5UmVzdWx0KHZhbHVlLCBiaW5kaW5nKSxcbiAgICAgIFwiaW50ZWdyaXR5X3Jlc3VsdF91bmF2YWlsYWJsZVwiLFxuICAgICAgNDA5LFxuICAgICk7XG4gIH1cbn0pO1xuRGVuby50ZXN0KFwiU1FMIGVycm9ycyBleHBvc2Ugc3RhYmxlIHB1YmxpYyBjb2RlcyB3aXRob3V0IHByaXZhdGUgU1FMIG9yIHByb3ZpZGVyIHRleHRcIiwgKCkgPT4ge1xuICBmb3IgKFxuICAgIGNvbnN0IFtjb2RlLCBleHBlY3RlZCwgc3RhdHVzXSBvZiBbXG4gICAgICBbXCI0MjUwMVwiLCBcImludGVncml0eV9hZG1pc3Npb25fZm9yYmlkZGVuXCIsIDQwM10sXG4gICAgICBbXCIyMjAyM1wiLCBcImludmFsaWRfaW50ZWdyaXR5X3JlcXVlc3RcIiwgNDAwXSxcbiAgICAgIFtcIjUzMzAwXCIsIFwiaW50ZWdyaXR5X3Jlc291cmNlX2xpbWl0XCIsIDQyOV0sXG4gICAgICBbXCI1NTAwMFwiLCBcImludGVncml0eV9yZWNvbmNpbGlhdGlvbl9yZXF1aXJlZFwiLCA0MDldLFxuICAgICAgW1wiMjM1MDVcIiwgXCJpbnRlZ3JpdHlfcmVjb25jaWxpYXRpb25fcmVxdWlyZWRcIiwgNDA5XSxcbiAgICAgIFtcIlBHUlNUMjAyXCIsIFwiaW50ZWdyaXR5X2FkbWlzc2lvbl91bmF2YWlsYWJsZVwiLCA1MDNdLFxuICAgIF0gYXMgY29uc3RcbiAgKSB7XG4gICAgY29uc3QgZXJyb3IgPSBpbnRlZ3JpdHlBZG1pc3Npb25FcnJvcih7XG4gICAgICBjb2RlLFxuICAgICAgbWVzc2FnZTogXCJwcml2YXRlIFNRTCB0b2tlblwiLFxuICAgIH0pO1xuICAgIGFzc2VydEVxdWFscyhlcnJvci5jb2RlLCBleHBlY3RlZCk7XG4gICAgYXNzZXJ0RXF1YWxzKGVycm9yLnN0YXR1cywgc3RhdHVzKTtcbiAgfVxufSk7XG4iXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IkFBQUEsU0FBUyxZQUFZLFFBQVEsbUJBQW1CO0FBQ2hELFNBQVMsV0FBVyxRQUFRLDJCQUEyQjtBQUN2RCxTQUNFLHVCQUF1QixFQUN2Qix5QkFBeUIsRUFDekIsZUFBZSxRQUNWLDJCQUEyQjtBQUVsQyxNQUFNLFVBQVU7RUFDZCxTQUFTO0VBQ1QsV0FBVztFQUNYLE9BQU87RUFDUCxRQUFRO0VBQ1IsYUFBYSxJQUFJLE1BQU0sQ0FBQztFQUN4QixXQUFXLElBQUksTUFBTSxDQUFDO0FBQ3hCO0FBQ0EsTUFBTSxTQUFTLElBQU0sSUFBSSxLQUFLLEtBQUssR0FBRyxLQUFLLFNBQVMsV0FBVztBQUMvRCxNQUFNLFVBQVUsSUFBTSxDQUFDO0lBQ3JCLGtCQUFrQjtJQUNsQixnQkFBZ0I7SUFDaEIsVUFBVSxR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
// denoCacheMetadata=10149334490029246994,242815490517875389
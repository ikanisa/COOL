import { assertEquals } from "./test_assert.ts";
import { decodeRosterSource } from "./roster_decoder.ts";
import { PublicError } from "./production_contract.ts";
import { readRosterSource, rosterSha256 } from "./roster_provenance.ts";
import { rosterBudgetReceipt } from "./roster_resource_budget.ts";
const encoder = new TextEncoder(), secret = "synthetic-decoder-test-key-with-32-bytes", build = "d".repeat(64);
const requestId = "99700000-0000-4000-8000-000000000101", reservationId = "99700000-0000-4000-8000-000000000102";
const source = readRosterSource({
  contract_version: 1,
  request_id: requestId,
  source_type: "image",
  filename: "unit.png",
  mime_type: "image/png",
  content_base64: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAFElEQVR4nGOUS+lhYGBgYgADKAUAE/ABFCFAuesAAAAASUVORK5CYII=",
  ai_consent: true,
  consent_version: "roster-ai-extraction-v1"
});
function fake(patch, tamper = false) {
  return async (_url, init)=>{
    const input = JSON.parse(String(init?.body));
    const payload = JSON.stringify({
      contract_version: 1,
      ok: true,
      request_id: input.request_id,
      reservation_id: input.reservation_id,
      nonce: input.nonce,
      issued_at: Math.floor(Date.now() / 1000),
      kind: input.kind,
      mime: input.mime,
      policy_version: "collect-roster-decoder-v1",
      decoder_build_sha256: build,
      toolchain: {
        python: "3.12",
        pillow: "12.3.0",
        pypdfium2: "5.2.0",
        pypdf: "6.19.0",
        openpyxl: "3.1.5",
        defusedxml: "0.7.1"
      },
      source_sha256: input.source_sha256,
      source_size: source.bytes.length,
      derived_sha256: null,
      derived_content: null,
      frames: 1,
      pages: 0,
      pixels: 6,
      expanded_bytes: 24,
      ...patch
    });
    const key = await crypto.subtle.importKey("raw", encoder.encode(secret), {
      name: "HMAC",
      hash: "SHA-256"
    }, false, [
      "sign"
    ]);
    const signature = [
      ...new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(payload)))
    ].map((v)=>v.toString(16).padStart(2, "0")).join("");
    return new Response(JSON.stringify({
      payload,
      signature: tamper ? "0".repeat(64) : signature
    }));
  };
}
for (const [name, patch] of Object.entries({
  wrong_source: {
    source_sha256: "a".repeat(64)
  },
  wrong_request: {
    request_id: reservationId
  },
  wrong_reservation: {
    reservation_id: requestId
  },
  replayed_nonce: {
    nonce: reservationId
  },
  stale_signature: {
    issued_at: 1
  },
  wrong_policy: {
    policy_version: "client-claimed-safe"
  },
  wrong_build: {
    decoder_build_sha256: "e".repeat(64)
  },
  wrong_toolchain: {
    toolchain: {
      python: "3.12"
    }
  },
  old_pillow: {
    toolchain: {
      python: "3.12",
      pillow: "12.0.0",
      pypdfium2: "5.2.0",
      pypdf: "6.19.0",
      openpyxl: "3.1.5",
      defusedxml: "0.7.1"
    }
  },
  old_pypdf: {
    toolchain: {
      python: "3.12",
      pillow: "12.3.0",
      pypdfium2: "5.2.0",
      pypdf: "6.7.0",
      openpyxl: "3.1.5",
      defusedxml: "0.7.1"
    }
  },
  wrong_size: {
    source_size: 1
  },
  extra_key: {
    approved: true
  },
  frames_exceeded: {
    frames: 21
  },
  pixels_exceeded: {
    pixels: 40000001
  },
  negative_expansion: {
    expanded_bytes: -1
  },
  unexpected_derived: {
    derived_content: "fake",
    derived_sha256: "a".repeat(64)
  }
})){
  Deno.test(`decoder receipt rejects ${name} despite a valid synthetic HMAC`, async ()=>{
    try {
      await decodeRosterSource(source, await rosterSha256(source.bytes), reservationId, {
        url: "http://localhost/decode",
        secret,
        buildSha256: build
      }, fake(patch));
      throw new Error("Invalid receipt accepted");
    } catch (error) {
      assertEquals(error instanceof PublicError && error.code, "roster_decoder_receipt_invalid");
    }
  });
}
Deno.test("decoder receipt rejects tampered signature", async ()=>{
  try {
    await decodeRosterSource(source, await rosterSha256(source.bytes), reservationId, {
      url: "http://localhost/decode",
      secret,
      buildSha256: build
    }, fake({}, true));
    throw new Error("Tampered signature accepted");
  } catch (error) {
    assertEquals(error instanceof PublicError && error.code, "roster_decoder_receipt_invalid");
  }
});
const expected = {
  requestId,
  actorId: "99700000-0000-4000-8000-000000000001",
  sessionId: "99700000-0000-4000-8000-000000000011",
  sourceHash: "a".repeat(64)
};
const receipt = {
  contract_version: 1,
  ok: true,
  reservation_id: reservationId,
  request_id: expected.requestId,
  actor_id: expected.actorId,
  session_id: expected.sessionId,
  source_sha256: expected.sourceHash,
  state: "reserved",
  replayed: false,
  expires_at: "2099-01-01T00:00:00Z"
};
for (const patch of [
  {
    actor_id: reservationId
  },
  {
    session_id: reservationId
  },
  {
    source_sha256: "b".repeat(64)
  },
  {
    reservation_id: "bad"
  },
  {
    state: "active"
  },
  {
    expires_at: "January 1, 2099"
  },
  {
    ok: 1
  },
  {
    extra: true
  }
]){
  Deno.test(`resource acknowledgement rejects ${JSON.stringify(patch)}`, ()=>{
    try {
      rosterBudgetReceipt({
        ...receipt,
        ...patch
      }, expected);
      throw new Error("Invalid budget ACK accepted");
    } catch (error) {
      assertEquals(error instanceof PublicError && error.code, "roster_budget_receipt_invalid");
      assertEquals(error.status, 503);
    }
  });
}
Deno.test("replayed or expired active budget never releases provider work", ()=>{
  for (const patch of [
    {
      replayed: true
    },
    {
      expires_at: "2000-01-01T00:00:00Z"
    }
  ]){
    try {
      rosterBudgetReceipt({
        ...receipt,
        ...patch
      }, expected);
      throw new Error("In-progress reservation accepted");
    } catch (error) {
      assertEquals(error instanceof PublicError && error.code, "roster_resource_in_progress");
    }
  }
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL19zaGFyZWQvcm9zdGVyX2RlY29kZXJfdGVzdC50cyJdLCJzb3VyY2VzQ29udGVudCI6WyJpbXBvcnQgeyBhc3NlcnRFcXVhbHMgfSBmcm9tIFwiLi90ZXN0X2Fzc2VydC50c1wiO1xuaW1wb3J0IHsgZGVjb2RlUm9zdGVyU291cmNlIH0gZnJvbSBcIi4vcm9zdGVyX2RlY29kZXIudHNcIjtcbmltcG9ydCB7IFB1YmxpY0Vycm9yIH0gZnJvbSBcIi4vcHJvZHVjdGlvbl9jb250cmFjdC50c1wiO1xuaW1wb3J0IHsgcmVhZFJvc3RlclNvdXJjZSwgcm9zdGVyU2hhMjU2IH0gZnJvbSBcIi4vcm9zdGVyX3Byb3ZlbmFuY2UudHNcIjtcbmltcG9ydCB7IHJvc3RlckJ1ZGdldFJlY2VpcHQgfSBmcm9tIFwiLi9yb3N0ZXJfcmVzb3VyY2VfYnVkZ2V0LnRzXCI7XG5jb25zdCBlbmNvZGVyID0gbmV3IFRleHRFbmNvZGVyKCksXG4gIHNlY3JldCA9IFwic3ludGhldGljLWRlY29kZXItdGVzdC1rZXktd2l0aC0zMi1ieXRlc1wiLFxuICBidWlsZCA9IFwiZFwiLnJlcGVhdCg2NCk7XG5jb25zdCByZXF1ZXN0SWQgPSBcIjk5NzAwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDEwMVwiLFxuICByZXNlcnZhdGlvbklkID0gXCI5OTcwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAxMDJcIjtcbmNvbnN0IHNvdXJjZSA9IHJlYWRSb3N0ZXJTb3VyY2Uoe1xuICBjb250cmFjdF92ZXJzaW9uOiAxLFxuICByZXF1ZXN0X2lkOiByZXF1ZXN0SWQsXG4gIHNvdXJjZV90eXBlOiBcImltYWdlXCIsXG4gIGZpbGVuYW1lOiBcInVuaXQucG5nXCIsXG4gIG1pbWVfdHlwZTogXCJpbWFnZS9wbmdcIixcbiAgY29udGVudF9iYXNlNjQ6XG4gICAgXCJpVkJPUncwS0dnb0FBQUFOU1VoRVVnQUFBQUlBQUFBRENBSUFBQUEyaUVuV0FBQUFGRWxFUVZSNG5HT1VTK2xoWUdCZ1lnQURLQVVBRS9BQkZDRkF1ZXNBQUFBQVNVVk9SSzVDWUlJPVwiLFxuICBhaV9jb25zZW50OiB0cnVlLFxuICBjb25zZW50X3ZlcnNpb246IFwicm9zdGVyLWFpLWV4dHJhY3Rpb24tdjFcIixcbn0pO1xuZnVuY3Rpb24gZmFrZShwYXRjaDogUmVjb3JkPHN0cmluZywgdW5rbm93bj4sIHRhbXBlciA9IGZhbHNlKTogdHlwZW9mIGZldGNoIHtcbiAgcmV0dXJuIGFzeW5jIChfdXJsLCBpbml0KSA9PiB7XG4gICAgY29uc3QgaW5wdXQgPSBKU09OLnBhcnNlKFN0cmluZyhpbml0Py5ib2R5KSk7XG4gICAgY29uc3QgcGF5bG9hZCA9IEpTT04uc3RyaW5naWZ5KHtcbiAgICAgIGNvbnRyYWN0X3ZlcnNpb246IDEsXG4gICAgICBvazogdHJ1ZSxcbiAgICAgIHJlcXVlc3RfaWQ6IGlucHV0LnJlcXVlc3RfaWQsXG4gICAgICByZXNlcnZhdGlvbl9pZDogaW5wdXQucmVzZXJ2YXRpb25faWQsXG4gICAgICBub25jZTogaW5wdXQubm9uY2UsXG4gICAgICBpc3N1ZWRfYXQ6IE1hdGguZmxvb3IoRGF0ZS5ub3coKSAvIDEwMDApLFxuICAgICAga2luZDogaW5wdXQua2luZCxcbiAgICAgIG1pbWU6IGlucHV0Lm1pbWUsXG4gICAgICBwb2xpY3lfdmVyc2lvbjogXCJjb2xsZWN0LXJvc3Rlci1kZWNvZGVyLXYxXCIsXG4gICAgICBkZWNvZGVyX2J1aWxkX3NoYTI1NjogYnVpbGQsXG4gICAgICB0b29sY2hhaW46IHtcbiAgICAgICAgcHl0aG9uOiBcIjMuMTJcIixcbiAgICAgICAgcGlsbG93OiBcIjEyLjMuMFwiLFxuICAgICAgICBweXBkZml1bTI6IFwiNS4yLjBcIixcbiAgICAgICAgcHlwZGY6IFwiNi4xOS4wXCIsXG4gICAgICAgIG9wZW5weXhsOiBcIjMuMS41XCIsXG4gICAgICAgIGRlZnVzZWR4bWw6IFwiMC43LjFcIixcbiAgICAgIH0sXG4gICAgICBzb3VyY2Vfc2hhMjU2OiBpbnB1dC5zb3VyY2Vfc2hhMjU2LFxuICAgICAgc291cmNlX3NpemU6IHNvdXJjZS5ieXRlcy5sZW5ndGgsXG4gICAgICBkZXJpdmVkX3NoYTI1NjogbnVsbCxcbiAgICAgIGRlcml2ZWRfY29udGVudDogbnVsbCxcbiAgICAgIGZyYW1lczogMSxcbiAgICAgIHBhZ2VzOiAwLFxuICAgICAgcGl4ZWxzOiA2LFxuICAgICAgZXhwYW5kZWRfYnl0ZXM6IDI0LFxuICAgICAgLi4ucGF0Y2gsXG4gICAgfSk7XG4gICAgY29uc3Qga2V5ID0gYXdhaXQgY3J5cHRvLnN1YnRsZS5pbXBvcnRLZXkoXG4gICAgICBcInJhd1wiLFxuICAgICAgZW5jb2Rlci5lbmNvZGUoc2VjcmV0KSxcbiAgICAgIHsgbmFtZTogXCJITUFDXCIsIGhhc2g6IFwiU0hBLTI1NlwiIH0sXG4gICAgICBmYWxzZSxcbiAgICAgIFtcInNpZ25cIl0sXG4gICAgKTtcbiAgICBjb25zdCBzaWduYXR1cmUgPSBbXG4gICAgICAuLi5uZXcgVWludDhBcnJheShcbiAgICAgICAgYXdhaXQgY3J5cHRvLnN1YnRsZS5zaWduKFwiSE1BQ1wiLCBrZXksIGVuY29kZXIuZW5jb2RlKHBheWxvYWQpKSxcbiAgICAgICksXG4gICAgXS5tYXAoKHYpID0+IHYudG9TdHJpbmcoMTYpLnBhZFN0YXJ0KDIsIFwiMFwiKSkuam9pbihcIlwiKTtcbiAgICByZXR1cm4gbmV3IFJlc3BvbnNlKFxuICAgICAgSlNPTi5zdHJpbmdpZnkoe1xuICAgICAgICBwYXlsb2FkLFxuICAgICAgICBzaWduYXR1cmU6IHRhbXBlciA/IFwiMFwiLnJlcGVhdCg2NCkgOiBzaWduYXR1cmUsXG4gICAgICB9KSxcbiAgICApO1xuICB9O1xufVxuZm9yIChcbiAgY29uc3QgW25hbWUsIHBhdGNoXSBvZiBPYmplY3QuZW50cmllcyh7XG4gICAgd3Jvbmdfc291cmNlOiB7IHNvdXJjZV9zaGEyNTY6IFwiYVwiLnJlcGVhdCg2NCkgfSxcbiAgICB3cm9uZ19yZXF1ZXN0OiB7IHJlcXVlc3RfaWQ6IHJlc2VydmF0aW9uSWQgfSxcbiAgICB3cm9uZ19yZXNlcnZhdGlvbjogeyByZXNlcnZhdGlvbl9pZDogcmVxdWVzdElkIH0sXG4gICAgcmVwbGF5ZWRfbm9uY2U6IHsgbm9uY2U6IHJlc2VydmF0aW9uSWQgfSxcbiAgICBzdGFsZV9zaWduYXR1cmU6IHsgaXNzdWVkX2F0OiAxIH0sXG4gICAgd3JvbmdfcG9saWN5OiB7IHBvbGljeV92ZXJzaW9uOiBcImNsaWVudC1jbGFpbWVkLXNhZmVcIiB9LFxuICAgIHdyb25nX2J1aWxkOiB7IGRlY29kZXJfYnVpbGRfc2hhMjU2OiBcImVcIi5yZXBlYXQoNjQpIH0sXG4gICAgd3JvbmdfdG9vbGNoYWluOiB7IHRvb2xjaGFpbjogeyBweXRob246IFwiMy4xMlwiIH0gfSxcbiAgICBvbGRfcGlsbG93OiB7XG4gICAgICB0b29sY2hhaW46IHtcbiAgICAgICAgcHl0aG9uOiBcIjMuMTJcIixcbiAgICAgICAgcGlsbG93OiBcIjEyLjAuMFwiLFxuICAgICAgICBweXBkZml1bTI6IFwiNS4yLjBcIixcbiAgICAgICAgcHlwZGY6IFwiNi4xOS4wXCIsXG4gICAgICAgIG9wZW5weXhsOiBcIjMuMS41XCIsXG4gICAgICAgIGRlZnVzZWR4bWw6IFwiMC43LjFcIixcbiAgICAgIH0sXG4gICAgfSxcbiAgICBvbGRfcHlwZGY6IHtcbiAgICAgIHRvb2xjaGFpbjoge1xuICAgICAgICBweXRob246IFwiMy4xMlwiLFxuICAgICAgICBwaWxsb3c6IFwiMTIuMy4wXCIsXG4gICAgICAgIHB5cGRmaXVtMjogXCI1LjIuMFwiLFxuICAgICAgICBweXBkZjogXCI2LjcuMFwiLFxuICAgICAgICBvcGVucHl4bDogXCIzLjEuNVwiLFxuICAgICAgICBkZWZ1c2VkeG1sOiBcIjAuNy4xXCIsXG4gICAgICB9LFxuICAgIH0sXG4gICAgd3Jvbmdfc2l6ZTogeyBzb3VyY2Vfc2l6ZTogMSB9LFxuICAgIGV4dHJhX2tleTogeyBhcHByb3ZlZDogdHJ1ZSB9LFxuICAgIGZyYW1lc19leGNlZWRlZDogeyBmcmFtZXM6IDIxIH0sXG4gICAgcGl4ZWxzX2V4Y2VlZGVkOiB7IHBpeGVsczogNDAwMDAwMDEgfSxcbiAgICBuZWdhdGl2ZV9leHBhbnNpb246IHsgZXhwYW5kZWRfYnl0ZXM6IC0xIH0sXG4gICAgdW5leHBlY3RlZF9kZXJpdmVkOiB7XG4gICAgICBkZXJpdmVkX2NvbnRlbnQ6IFwiZmFrZVwiLFxuICAgICAgZGVyaXZlZF9zaGEyNTY6IFwiYVwiLnJlcGVhdCg2NCksXG4gICAgfSxcbiAgfSlcbikge1xuICBEZW5vLnRlc3QoYGRlY29kZXIgcmVjZWlwdCByZWplY3RzICR7bmFtZX0gZGVzcGl0ZSBhIHZhbGlkIHN5bnRoZXRpYyBITUFDYCwgYXN5bmMgKCkgPT4ge1xuICAgIHRyeSB7XG4gICAgICBhd2FpdCBkZWNvZGVSb3N0ZXJTb3VyY2UoXG4gICAgICAgIHNvdXJjZSxcbiAgICAgICAgYXdhaXQgcm9zdGVyU2hhMjU2KHNvdXJjZS5ieXRlcyksXG4gICAgICAgIHJlc2VydmF0aW9uSWQsXG4gICAgICAgIHsgdXJsOiBcImh0dHA6Ly9sb2NhbGhvc3QvZGVjb2RlXCIsIHNlY3JldCwgYnVpbGRTaGEyNTY6IGJ1aWxkIH0sXG4gICAgICAgIGZha2UocGF0Y2gpLFxuICAgICAgKTtcbiAgICAgIHRocm93IG5ldyBFcnJvcihcIkludmFsaWQgcmVjZWlwdCBhY2NlcHRlZFwiKTtcbiAgICB9IGNhdGNoIChlcnJvcikge1xuICAgICAgYXNzZXJ0RXF1YWxzKFxuICAgICAgICBlcnJvciBpbnN0YW5jZW9mIFB1YmxpY0Vycm9yICYmIGVycm9yLmNvZGUsXG4gICAgICAgIFwicm9zdGVyX2RlY29kZXJfcmVjZWlwdF9pbnZhbGlkXCIsXG4gICAgICApO1xuICAgIH1cbiAgfSk7XG59XG5EZW5vLnRlc3QoXCJkZWNvZGVyIHJlY2VpcHQgcmVqZWN0cyB0YW1wZXJlZCBzaWduYXR1cmVcIiwgYXN5bmMgKCkgPT4ge1xuICB0cnkge1xuICAgIGF3YWl0IGRlY29kZVJvc3RlclNvdXJjZShcbiAgICAgIHNvdXJjZSxcbiAgICAgIGF3YWl0IHJvc3RlclNoYTI1Nihzb3VyY2UuYnl0ZXMpLFxuICAgICAgcmVzZXJ2YXRpb25JZCxcbiAgICAgIHsgdXJsOiBcImh0dHA6Ly9sb2NhbGhvc3QvZGVjb2RlXCIsIHNlY3JldCwgYnVpbGRTaGEyNTY6IGJ1aWxkIH0sXG4gICAgICBmYWtlKHt9LCB0cnVlKSxcbiAgICApO1xuICAgIHRocm93IG5ldyBFcnJvcihcIlRhbXBlcmVkIHNpZ25hdHVyZSBhY2NlcHRlZFwiKTtcbiAgfSBjYXRjaCAoZXJyb3IpIHtcbiAgICBhc3NlcnRFcXVhbHMoXG4gICAgICBlcnJvciBpbnN0YW5jZW9mIFB1YmxpY0Vycm9yICYmIGVycm9yLmNvZGUsXG4gICAgICBcInJvc3Rlcl9kZWNvZGVyX3JlY2VpcHRfaW52YWxpZFwiLFxuICAgICk7XG4gIH1cbn0pO1xuY29uc3QgZXhwZWN0ZWQgPSB7XG4gIHJlcXVlc3RJZCxcbiAgYWN0b3JJZDogXCI5OTcwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDFcIixcbiAgc2Vzc2lvbklkOiBcIjk5NzAwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAxMVwiLFxuICBzb3VyY2VIYXNoOiBcImFcIi5yZXBlYXQoNjQpLFxufTtcbmNvbnN0IHJlY2VpcHQgPSB7XG4gIGNvbnRyYWN0X3ZlcnNpb246IDEsXG4gIG9rOiB0cnVlLFxuICByZXNlcnZhdGlvbl9pZDogcmVzZXJ2YXRpb25JZCxcbiAgcmVxdWVzdF9pZDogZXhwZWN0ZWQucmVxdWVzdElkLFxuICBhY3Rvcl9pZDogZXhwZWN0ZWQuYWN0b3JJZCxcbiAgc2Vzc2lvbl9pZDogZXhwZWN0ZWQuc2Vzc2lvbklkLFxuICBzb3VyY2Vfc2hhMjU2OiBleHBlY3RlZC5zb3VyY2VIYXNoLFxuICBzdGF0ZTogXCJyZXNlcnZlZFwiLFxuICByZXBsYXllZDogZmFsc2UsXG4gIGV4cGlyZXNfYXQ6IFwiMjA5OS0wMS0wMVQwMDowMDowMFpcIixcbn07XG5mb3IgKFxuICBjb25zdCBwYXRjaCBvZiBbXG4gICAgeyBhY3Rvcl9pZDogcmVzZXJ2YXRpb25JZCB9LFxuICAgIHsgc2Vzc2lvbl9pZDogcmVzZXJ2YXRpb25JZCB9LFxuICAgIHsgc291cmNlX3NoYTI1NjogXCJiXCIucmVwZWF0KDY0KSB9LFxuICAgIHsgcmVzZXJ2YXRpb25faWQ6IFwiYmFkXCIgfSxcbiAgICB7IHN0YXRlOiBcImFjdGl2ZVwiIH0sXG4gICAgeyBleHBpcmVzX2F0OiBcIkphbnVhcnkgMSwgMjA5OVwiIH0sXG4gICAgeyBvazogMSB9LFxuICAgIHsgZXh0cmE6IHRydWUgfSxcbiAgXVxuKSB7XG4gIERlbm8udGVzdChgcmVzb3VyY2UgYWNrbm93bGVkZ2VtZW50IHJlamVjdHMgJHtKU09OLnN0cmluZ2lmeShwYXRjaCl9YCwgKCkgPT4ge1xuICAgIHRyeSB7XG4gICAgICByb3N0ZXJCdWRnZXRSZWNlaXB0KHsgLi4ucmVjZWlwdCwgLi4ucGF0Y2ggfSwgZXhwZWN0ZWQpO1xuICAgICAgdGhyb3cgbmV3IEVycm9yKFwiSW52YWxpZCBidWRnZXQgQUNLIGFjY2VwdGVkXCIpO1xuICAgIH0gY2F0Y2ggKGVycm9yKSB7XG4gICAgICBhc3NlcnRFcXVhbHMoXG4gICAgICAgIGVycm9yIGluc3RhbmNlb2YgUHVibGljRXJyb3IgJiYgZXJyb3IuY29kZSxcbiAgICAgICAgXCJyb3N0ZXJfYnVkZ2V0X3JlY2VpcHRfaW52YWxpZFwiLFxuICAgICAgKTtcbiAgICAgIGFzc2VydEVxdWFscygoZXJyb3IgYXMgUHVibGljRXJyb3IpLnN0YXR1cywgNTAzKTtcbiAgICB9XG4gIH0pO1xufVxuRGVuby50ZXN0KFwicmVwbGF5ZWQgb3IgZXhwaXJlZCBhY3RpdmUgYnVkZ2V0IG5ldmVyIHJlbGVhc2VzIHByb3ZpZGVyIHdvcmtcIiwgKCkgPT4ge1xuICBmb3IgKFxuICAgIGNvbnN0IHBhdGNoIG9mIFt7IHJlcGxheWVkOiB0cnVlIH0sIHsgZXhwaXJlc19hdDogXCIyMDAwLTAxLTAxVDAwOjAwOjAwWlwiIH1dXG4gICkge1xuICAgIHRyeSB7XG4gICAgICByb3N0ZXJCdWRnZXRSZWNlaXB0KHsgLi4ucmVjZWlwdCwgLi4ucGF0Y2ggfSwgZXhwZWN0ZWQpO1xuICAgICAgdGhyb3cgbmV3IEVycm9yKFwiSW4tcHJvZ3Jlc3MgcmVzZXJ2YXRpb24gYWNjZXB0ZWRcIik7XG4gICAgfSBjYXRjaCAoZXJyb3IpIHtcbiAgICAgIGFzc2VydEVxdWFscyhcbiAgICAgICAgZXJyb3IgaW5zdGFuY2VvZiBQdWJsaWNFcnJvciAmJiBlcnJvci5jb2RlLFxuICAgICAgICBcInJvc3Rlcl9yZXNvdXJjZV9pbl9wcm9ncmVzc1wiLFxuICAgICAgKTtcbiAgICB9XG4gIH1cbn0pO1xuIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiJBQUFBLFNBQVMsWUFBWSxRQUFRLG1CQUFtQjtBQUNoRCxTQUFTLGtCQUFrQixRQUFRLHNCQUFzQjtBQUN6RCxTQUFTLFdBQVcsUUFBUSwyQkFBMkI7QUFDdkQsU0FBUyxnQkFBZ0IsRUFBRSxZQUFZLFFBQVEseUJBQXlCO0FBQ3hFLFNBQVMsbUJBQW1CLFFBQVEsOEJBQThCO0FBQ2xFLE1BQU0sVUFBVSxJQUFJLGVBQ2xCLFNBQVMsNENBQ1QsUUFBUSxJQUFJLE1BQU0sQ0FBQztBQUNyQixNQUFNLFlBQVksd0NBQ2hCLGdCQUFnQjtBQUNsQixNQUFNLFNBQVMsaUJBQWlCO0VBQzlCLGtCQUFrQjtFQUNsQixZQUFZO0VBQ1osYUFBYTtFQUNiLFVBQVU7RUFDVixXQUFXO0VBQ1gsZ0JBQ0U7RUFDRixZQUFZO0VBQ1osaUJBQWlCO0FBQ25CO0FBQ0EsU0FBUyxLQUFLLEtBQThCLEVB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
// denoCacheMetadata=6623437707931846641,2881229516104965301
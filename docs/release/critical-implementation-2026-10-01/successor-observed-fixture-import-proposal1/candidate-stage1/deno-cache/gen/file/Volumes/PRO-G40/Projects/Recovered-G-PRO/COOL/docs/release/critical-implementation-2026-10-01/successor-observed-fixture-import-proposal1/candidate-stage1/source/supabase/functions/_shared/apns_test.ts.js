import { assert, assertEquals, assertMatch } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createApnsJwt, sendApnsMessage } from "./apns.ts";
function encodedPem(pem) {
  return btoa(pem);
}
Deno.test("APNs JWT contains the configured key, team, and issued-at claims", async ()=>{
  const pair = await crypto.subtle.generateKey({
    name: "ECDSA",
    namedCurve: "P-256"
  }, true, [
    "sign",
    "verify"
  ]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let binary = "";
  for (const byte of pkcs8)binary += String.fromCharCode(byte);
  const derBase64 = btoa(binary);
  const pem = `-----BEGIN PRIVATE KEY-----\n${derBase64}\n-----END PRIVATE KEY-----`;
  const jwt = await createApnsJwt({
    keyId: "KEY123",
    teamId: "TEAM123",
    privateKeyBase64: encodedPem(pem)
  }, 1_700_000_000);
  const [header, claims, signature] = jwt.split(".");
  const decode = (value)=>JSON.parse(atob(value.replaceAll("-", "+").replaceAll("_", "/")));
  assertEquals(decode(header), {
    alg: "ES256",
    kid: "KEY123"
  });
  assertEquals(decode(claims), {
    iss: "TEAM123",
    iat: 1_700_000_000
  });
  assertMatch(signature, /^[A-Za-z0-9_-]+$/);
});
Deno.test("APNs sender emits a bounded alert payload and classifies retry", async ()=>{
  const requests = [];
  const result = await sendApnsMessage({
    keyId: "KEY123",
    teamId: "TEAM123",
    bundleId: "app.cool.mobile",
    privateKeyBase64: "unused"
  }, "signed-token", {
    token: "a".repeat(64),
    environment: "production",
    title: "Contribution confirmed",
    body: "RWF 5,000 has been confirmed.",
    recipientId: "99870000-0000-4000-8000-000000000001",
    eventId: "event-1",
    eventType: "contribution_confirmed",
    deepLink: "/groups/group-1/ledger"
  }, async (input, init)=>{
    requests.push(new Request(input, init));
    return new Response(JSON.stringify({
      reason: "TooManyRequests"
    }), {
      status: 429,
      headers: {
        "apns-id": "message-1"
      }
    });
  });
  const request = requests[0];
  assert(request);
  assertEquals(request.url, `https://api.push.apple.com/3/device/${"a".repeat(64)}`);
  assertEquals(request.headers.get("apns-topic"), "app.cool.mobile");
  assertEquals(request.headers.get("apns-push-type"), "alert");
  const payload = await request.json();
  assertEquals(payload.aps.alert, {
    title: "Collect",
    body: "Open Collect to view your updates"
  });
  assertEquals(payload.recipient_id, "99870000-0000-4000-8000-000000000001");
  assertEquals(payload.collect_push_version, "2");
  assertEquals(JSON.stringify(payload).includes("RWF 5,000"), false);
  assertEquals(payload.deep_link, "/groups/group-1/ledger");
  assertEquals(result.ok, false);
  assertEquals(result.retryable, true);
  assertEquals(result.errorCode, "TooManyRequests");
});
Deno.test("APNs retry floors follow 15-minute 5xx and throttled-token policy", async ()=>{
  for (const [status, reason, header, floor] of [
    [
      503,
      "Shutdown",
      "60",
      900
    ],
    [
      500,
      "InternalServerError",
      "1200",
      1200
    ],
    [
      429,
      "TooManyProviderTokenUpdates",
      "60",
      1200
    ],
    [
      429,
      "TooManyRequests",
      "120",
      120
    ],
    [
      410,
      "Unregistered",
      "900",
      null
    ]
  ]){
    const result = await sendApnsMessage({
      keyId: "synthetic",
      teamId: "synthetic",
      bundleId: "app.collect",
      privateKeyBase64: "unused"
    }, "synthetic", {
      token: "synthetic",
      environment: "production",
      title: "Private",
      body: "Private",
      recipientId: "99870000-0000-4000-8000-000000000001",
      eventId: "synthetic",
      eventType: "notice"
    }, ()=>Promise.resolve(new Response(JSON.stringify({
        reason
      }), {
        status,
        headers: {
          "retry-after": header
        }
      })));
    assertEquals(result.retryAfterSeconds, floor);
    assertEquals(result.retryable, status === 429 || status >= 500);
  }
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL19zaGFyZWQvYXBuc190ZXN0LnRzIl0sInNvdXJjZXNDb250ZW50IjpbImltcG9ydCB7XG4gIGFzc2VydCxcbiAgYXNzZXJ0RXF1YWxzLFxuICBhc3NlcnRNYXRjaCxcbn0gZnJvbSBcImh0dHBzOi8vZGVuby5sYW5kL3N0ZEAwLjIyNC4wL2Fzc2VydC9tb2QudHNcIjtcbmltcG9ydCB7IGNyZWF0ZUFwbnNKd3QsIHNlbmRBcG5zTWVzc2FnZSB9IGZyb20gXCIuL2FwbnMudHNcIjtcblxuZnVuY3Rpb24gZW5jb2RlZFBlbShwZW06IHN0cmluZyk6IHN0cmluZyB7XG4gIHJldHVybiBidG9hKHBlbSk7XG59XG5cbkRlbm8udGVzdChcIkFQTnMgSldUIGNvbnRhaW5zIHRoZSBjb25maWd1cmVkIGtleSwgdGVhbSwgYW5kIGlzc3VlZC1hdCBjbGFpbXNcIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCBwYWlyID0gYXdhaXQgY3J5cHRvLnN1YnRsZS5nZW5lcmF0ZUtleShcbiAgICB7IG5hbWU6IFwiRUNEU0FcIiwgbmFtZWRDdXJ2ZTogXCJQLTI1NlwiIH0sXG4gICAgdHJ1ZSxcbiAgICBbXCJzaWduXCIsIFwidmVyaWZ5XCJdLFxuICApO1xuICBjb25zdCBwa2NzOCA9IG5ldyBVaW50OEFycmF5KFxuICAgIGF3YWl0IGNyeXB0by5zdWJ0bGUuZXhwb3J0S2V5KFwicGtjczhcIiwgcGFpci5wcml2YXRlS2V5KSxcbiAgKTtcbiAgbGV0IGJpbmFyeSA9IFwiXCI7XG4gIGZvciAoY29uc3QgYnl0ZSBvZiBwa2NzOCkgYmluYXJ5ICs9IFN0cmluZy5mcm9tQ2hhckNvZGUoYnl0ZSk7XG4gIGNvbnN0IGRlckJhc2U2NCA9IGJ0b2EoYmluYXJ5KTtcbiAgY29uc3QgcGVtID1cbiAgICBgLS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tXFxuJHtkZXJCYXNlNjR9XFxuLS0tLS1FTkQgUFJJVkFURSBLRVktLS0tLWA7XG4gIGNvbnN0IGp3dCA9IGF3YWl0IGNyZWF0ZUFwbnNKd3Qoe1xuICAgIGtleUlkOiBcIktFWTEyM1wiLFxuICAgIHRlYW1JZDogXCJURUFNMTIzXCIsXG4gICAgcHJpdmF0ZUtleUJhc2U2NDogZW5jb2RlZFBlbShwZW0pLFxuICB9LCAxXzcwMF8wMDBfMDAwKTtcbiAgY29uc3QgW2hlYWRlciwgY2xhaW1zLCBzaWduYXR1cmVdID0gand0LnNwbGl0KFwiLlwiKTtcbiAgY29uc3QgZGVjb2RlID0gKHZhbHVlOiBzdHJpbmcpID0+XG4gICAgSlNPTi5wYXJzZShcbiAgICAgIGF0b2IodmFsdWUucmVwbGFjZUFsbChcIi1cIiwgXCIrXCIpLnJlcGxhY2VBbGwoXCJfXCIsIFwiL1wiKSksXG4gICAgKTtcbiAgYXNzZXJ0RXF1YWxzKGRlY29kZShoZWFkZXIpLCB7IGFsZzogXCJFUzI1NlwiLCBraWQ6IFwiS0VZMTIzXCIgfSk7XG4gIGFzc2VydEVxdWFscyhkZWNvZGUoY2xhaW1zKSwgeyBpc3M6IFwiVEVBTTEyM1wiLCBpYXQ6IDFfNzAwXzAwMF8wMDAgfSk7XG4gIGFzc2VydE1hdGNoKHNpZ25hdHVyZSwgL15bQS1aYS16MC05Xy1dKyQvKTtcbn0pO1xuXG5EZW5vLnRlc3QoXCJBUE5zIHNlbmRlciBlbWl0cyBhIGJvdW5kZWQgYWxlcnQgcGF5bG9hZCBhbmQgY2xhc3NpZmllcyByZXRyeVwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IHJlcXVlc3RzOiBSZXF1ZXN0W10gPSBbXTtcbiAgY29uc3QgcmVzdWx0ID0gYXdhaXQgc2VuZEFwbnNNZXNzYWdlKFxuICAgIHtcbiAgICAgIGtleUlkOiBcIktFWTEyM1wiLFxuICAgICAgdGVhbUlkOiBcIlRFQU0xMjNcIixcbiAgICAgIGJ1bmRsZUlkOiBcImFwcC5jb29sLm1vYmlsZVwiLFxuICAgICAgcHJpdmF0ZUtleUJhc2U2NDogXCJ1bnVzZWRcIixcbiAgICB9LFxuICAgIFwic2lnbmVkLXRva2VuXCIsXG4gICAge1xuICAgICAgdG9rZW46IFwiYVwiLnJlcGVhdCg2NCksXG4gICAgICBlbnZpcm9ubWVudDogXCJwcm9kdWN0aW9uXCIsXG4gICAgICB0aXRsZTogXCJDb250cmlidXRpb24gY29uZmlybWVkXCIsXG4gICAgICBib2R5OiBcIlJXRiA1LDAwMCBoYXMgYmVlbiBjb25maXJtZWQuXCIsXG4gICAgICByZWNpcGllbnRJZDogXCI5OTg3MDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDFcIixcbiAgICAgIGV2ZW50SWQ6IFwiZXZlbnQtMVwiLFxuICAgICAgZXZlbnRUeXBlOiBcImNvbnRyaWJ1dGlvbl9jb25maXJtZWRcIixcbiAgICAgIGRlZXBMaW5rOiBcIi9ncm91cHMvZ3JvdXAtMS9sZWRnZXJcIixcbiAgICB9LFxuICAgIGFzeW5jIChpbnB1dCwgaW5pdCkgPT4ge1xuICAgICAgcmVxdWVzdHMucHVzaChuZXcgUmVxdWVzdChpbnB1dCwgaW5pdCkpO1xuICAgICAgcmV0dXJuIG5ldyBSZXNwb25zZShKU09OLnN0cmluZ2lmeSh7IHJlYXNvbjogXCJUb29NYW55UmVxdWVzdHNcIiB9KSwge1xuICAgICAgICBzdGF0dXM6IDQyOSxcbiAgICAgICAgaGVhZGVyczogeyBcImFwbnMtaWRcIjogXCJtZXNzYWdlLTFcIiB9LFxuICAgICAgfSk7XG4gICAgfSxcbiAgKTtcbiAgY29uc3QgcmVxdWVzdCA9IHJlcXVlc3RzWzBdO1xuICBhc3NlcnQocmVxdWVzdCk7XG4gIGFzc2VydEVxdWFscyhcbiAgICByZXF1ZXN0LnVybCxcbiAgICBgaHR0cHM6Ly9hcGkucHVzaC5hcHBsZS5jb20vMy9kZXZpY2UvJHtcImFcIi5yZXBlYXQoNjQpfWAsXG4gICk7XG4gIGFzc2VydEVxdWFscyhyZXF1ZXN0LmhlYWRlcnMuZ2V0KFwiYXBucy10b3BpY1wiKSwgXCJhcHAuY29vbC5tb2JpbGVcIik7XG4gIGFzc2VydEVxdWFscyhyZXF1ZXN0LmhlYWRlcnMuZ2V0KFwiYXBucy1wdXNoLXR5cGVcIiksIFwiYWxlcnRcIik7XG4gIGNvbnN0IHBheWxvYWQgPSBhd2FpdCByZXF1ZXN0Lmpzb24oKTtcbiAgYXNzZXJ0RXF1YWxzKHBheWxvYWQuYXBzLmFsZXJ0LCB7XG4gICAgdGl0bGU6IFwiQ29sbGVjdFwiLFxuICAgIGJvZHk6IFwiT3BlbiBDb2xsZWN0IHRvIHZpZXcgeW91ciB1cGRhdGVzXCIsXG4gIH0pO1xuICBhc3NlcnRFcXVhbHMocGF5bG9hZC5yZWNpcGllbnRfaWQsIFwiOTk4NzAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAxXCIpO1xuICBhc3NlcnRFcXVhbHMocGF5bG9hZC5jb2xsZWN0X3B1c2hfdmVyc2lvbiwgXCIyXCIpO1xuICBhc3NlcnRFcXVhbHMoSlNPTi5zdHJpbmdpZnkocGF5bG9hZCkuaW5jbHVkZXMoXCJSV0YgNSwwMDBcIiksIGZhbHNlKTtcbiAgYXNzZXJ0RXF1YWxzKHBheWxvYWQuZGVlcF9saW5rLCBcIi9ncm91cHMvZ3JvdXAtMS9sZWRnZXJcIik7XG4gIGFzc2VydEVxdWFscyhyZXN1bHQub2ssIGZhbHNlKTtcbiAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5yZXRyeWFibGUsIHRydWUpO1xuICBhc3NlcnRFcXVhbHMocmVzdWx0LmVycm9yQ29kZSwgXCJUb29NYW55UmVxdWVzdHNcIik7XG59KTtcblxuRGVuby50ZXN0KFwiQVBOcyByZXRyeSBmbG9vcnMgZm9sbG93IDE1LW1pbnV0ZSA1eHggYW5kIHRocm90dGxlZC10b2tlbiBwb2xpY3lcIiwgYXN5bmMgKCkgPT4ge1xuICBmb3IgKFxuICAgIGNvbnN0IFtzdGF0dXMsIHJlYXNvbiwgaGVhZGVyLCBmbG9vcl0gb2YgW1xuICAgICAgWzUwMywgXCJTaHV0ZG93blwiLCBcIjYwXCIsIDkwMF0sXG4gICAgICBbNTAwLCBcIkludGVybmFsU2VydmVyRXJyb3JcIiwgXCIxMjAwXCIsIDEyMDBdLFxuICAgICAgWzQyOSwgXCJUb29NYW55UHJvdmlkZXJUb2tlblVwZGF0ZXNcIiwgXCI2MFwiLCAxMjAwXSxcbiAgICAgIFs0MjksIFwiVG9vTWFueVJlcXVlc3RzXCIsIFwiMTIwXCIsIDEyMF0sXG4gICAgICBbNDEwLCBcIlVucmVnaXN0ZXJlZFwiLCBcIjkwMFwiLCBudWxsXSxcbiAgICBdIGFzIGNvbnN0XG4gICkge1xuICAgIGNvbnN0IHJlc3VsdCA9IGF3YWl0IHNlbmRBcG5zTWVzc2FnZShcbiAgICAgIHtcbiAgICAgICAga2V5SWQ6IFwic3ludGhldGljXCIsXG4gICAgICAgIHRlYW1JZDogXCJzeW50aGV0aWNcIixcbiAgICAgICAgYnVuZGxlSWQ6IFwiYXBwLmNvbGxlY3RcIixcbiAgICAgICAgcHJpdmF0ZUtleUJhc2U2NDogXCJ1bnVzZWRcIixcbiAgICAgIH0sXG4gICAgICBcInN5bnRoZXRpY1wiLFxuICAgICAge1xuICAgICAgICB0b2tlbjogXCJzeW50aGV0aWNcIixcbiAgICAgICAgZW52aXJvbm1lbnQ6IFwicHJvZHVjdGlvblwiLFxuICAgICAgICB0aXRsZTogXCJQcml2YXRlXCIsXG4gICAgICAgIGJvZHk6IFwiUHJpdmF0ZVwiLFxuICAgICAgICByZWNpcGllbnRJZDogXCI5OTg3MDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDFcIixcbiAgICAgICAgZXZlbnRJZDogXCJzeW50aGV0aWNcIixcbiAgICAgICAgZXZlbnRUeXBlOiBcIm5vdGljZVwiLFxuICAgICAgfSxcbiAgICAgICgpID0+XG4gICAgICAgIFByb21pc2UucmVzb2x2ZShcbiAgICAgICAgICBuZXcgUmVzcG9uc2UoSlNPTi5zdHJpbmdpZnkoeyByZWFzb24gfSksIHtcbiAgICAgICAgICAgIHN0YXR1cyxcbiAgICAgICAgICAgIGhlYWRlcnM6IHsgXCJyZXRyeS1hZnRlclwiOiBoZWFkZXIgfSxcbiAgICAgICAgICB9KSxcbiAgICAgICAgKSxcbiAgICApO1xuICAgIGFzc2VydEVxdWFscyhyZXN1bHQucmV0cnlBZnRlclNlY29uZHMsIGZsb29yKTtcbiAgICBhc3NlcnRFcXVhbHMocmVzdWx0LnJldHJ5YWJsZSwgc3RhdHVzID09PSA0MjkgfHwgc3RhdHVzID49IDUwMCk7XG4gIH1cbn0pO1xuIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiJBQUFBLFNBQ0UsTUFBTSxFQUNOLFlBQVksRUFDWixXQUFXLFFBQ04sOENBQThDO0FBQ3JELFNBQVMsYUFBYSxFQUFFLGVBQWUsUUFBUSxZQUFZO0FBRTNELFNBQVMsV0FBVyxHQUFXO0VBQzdCLE9BQU8sS0FBSztBQUNkO0FBRUEsS0FBSyxJQUFJLENBQUMsb0VBQW9FO0VBQzVFLE1BQU0sT0FBTyxNQUFNLE9BQU8sTUFBTSxDQUFDLFdBQVcsQ0FDMUM7SUFBRSxNQUFNO0lBQVMsWUFBWTtFQUFRLEdBQ3JDLE1BQ0E7SUFBQztJQUFRO0dBQVM7RUFFcEIsTUFBTSxRQUFRLElBQUksV0FDaEIsTUFBTSxPQUFPLE1BQU0sQ0FBQyxTQUFTLENBQUMsU0FBUyxLQUFLLFVBQVU7RUFFeEQsSUFBSSxTQUFTO0VBQ2IsS0FBSyxNQUFNLFFBQVEsTUFBTyxVQUFVLE9BQU8sWUFBWSxDQUFDO0VBQ3hELE1BQU0sWUFBWSxLQUFLO0VBQ3ZCLE1BQU0sTUFDSixDQUFDLDZCQUE2QixFQUFFLFVBQVUsMkJBQTJCLENBQUM7RUFDeEUsTUFBTSxNQUFNLE1BQU0sY0FBYztJQUM5QixPQUFPO0lBQ1AsUUFBUTtJQUNSLGtCQUFrQixXQUFXO0VBQy9CLEdBQUc7RUFDSCxNQUFNLENBQUMsUUFBUSxRQUFRLFVBQVUsR0FBRyxJQUFJLEtBQUssQ0FBQztFQUM5QyxNQUFNLFNBQVMsQ0FBQyxRQUNkLEtBQUssS0FBSyxDQUNSLEtBQUssTUFBTSxVQUFVLENBQUMsS0FBSyxLQUFLLFVBQVUsQ0FBQyxLQUFLO0VBRXBELGFBQWEsT0FBTyxTQUFTO0lBQUUsS0FBSztJQUFTLEtB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
// denoCacheMetadata=15256460348032842885,16714320614657744606
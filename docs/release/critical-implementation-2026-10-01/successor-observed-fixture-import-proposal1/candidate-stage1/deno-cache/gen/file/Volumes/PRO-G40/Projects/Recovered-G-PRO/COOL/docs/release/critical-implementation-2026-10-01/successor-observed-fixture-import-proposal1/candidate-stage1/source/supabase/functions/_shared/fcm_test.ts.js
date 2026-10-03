import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { sendFcmMessage } from "./fcm.ts";
Deno.test("FCM sender emits private channel-routed data and classifies invalid tokens", async ()=>{
  const requests = [];
  const result = await sendFcmMessage({
    serviceAccountJson: JSON.stringify({
      project_id: "collect-project",
      client_email: "push@example.test",
      private_key: "unused"
    })
  }, "oauth-token", {
    token: "fcm-device-token",
    title: "Contribution confirmed",
    body: "RWF 5,000 has been confirmed.",
    recipientId: "99870000-0000-4000-8000-000000000001",
    eventId: "event-1",
    eventType: "contribution_confirmed",
    deepLink: "/groups/group-1/ledger"
  }, async (input, init)=>{
    requests.push(new Request(input, init));
    return new Response(JSON.stringify({
      error: {
        status: "NOT_FOUND",
        details: [
          {
            errorCode: "UNREGISTERED"
          }
        ]
      }
    }), {
      status: 404
    });
  });
  const request = requests[0];
  assert(request);
  assertEquals(request.url, "https://fcm.googleapis.com/v1/projects/collect-project/messages:send");
  const payload = await request.json();
  assertEquals(payload.message.notification, {
    title: "Collect",
    body: "Open Collect to view your updates"
  });
  assertEquals(payload.message.data.recipient_id, "99870000-0000-4000-8000-000000000001");
  assertEquals(payload.message.data.collect_push_version, "2");
  assertEquals(JSON.stringify(payload).includes("RWF 5,000"), false);
  assertEquals(payload.message.data.deep_link, "/groups/group-1/ledger");
  assertEquals(payload.message.android.notification.channel_id, "collect_contributions");
  assertEquals(payload.message.android.notification.visibility, "PRIVATE");
  assertEquals(result.ok, false);
  assertEquals(result.retryable, false);
  assertEquals(result.errorCode, "UNREGISTERED");
});
const syntheticCredentials = {
  serviceAccountJson: JSON.stringify({
    project_id: "collect-project",
    client_email: "push@example.test",
    private_key: "unused"
  })
};
const syntheticMessage = {
  token: "synthetic-device-token",
  title: "Synthetic",
  body: "Synthetic only",
  recipientId: "99870000-0000-4000-8000-000000000001",
  eventId: "event-1",
  eventType: "group_update"
};
for (const [label, response] of [
  [
    "unreadable stream",
    ()=>new Response(new ReadableStream({
        start (controller) {
          controller.error(new Error("private stream failure"));
        }
      }))
  ],
  [
    "oversized body",
    ()=>new Response("x".repeat(65537))
  ],
  [
    "invalid UTF-8",
    ()=>new Response(new Uint8Array([
        255
      ]))
  ],
  [
    "malformed JSON",
    ()=>new Response("not json")
  ],
  [
    "null payload",
    ()=>new Response("null")
  ],
  [
    "malformed error shape",
    ()=>new Response('{"error":{"details":3}}')
  ]
]){
  Deno.test(`FCM accepted ${label} never becomes a retryable send`, async ()=>{
    let sends = 0;
    const result = await sendFcmMessage(syntheticCredentials, "synthetic-oauth", syntheticMessage, ()=>{
      sends += 1;
      return Promise.resolve(response());
    });
    assertEquals(sends, 1);
    assertEquals(result.ok, true);
    assertEquals(result.retryable, false);
    assertEquals(result.messageId, null);
    assertEquals(result.errorCode, "accepted_response_unavailable");
  });
}
Deno.test("FCM accepted message retains its documented message name", async ()=>{
  const result = await sendFcmMessage(syntheticCredentials, "synthetic-oauth", syntheticMessage, ()=>Promise.resolve(new Response('{"name":"projects/collect-project/messages/0:123%abc"}')));
  assertEquals(result.ok, true);
  assertEquals(result.messageId, "projects/collect-project/messages/0:123%abc");
  assertEquals(result.errorCode, null);
});
for (const [status, body, code, retryable] of [
  [
    503,
    "null",
    "http_503",
    true
  ],
  [
    429,
    '{"error":{"details":7}}',
    "http_429",
    true
  ],
  [
    400,
    '{"error":{"status":"private account +250788123456"}}',
    "http_400",
    false
  ],
  [
    404,
    '{"error":{"details":[null,7,{"errorCode":"UNREGISTERED"}]}}',
    "UNREGISTERED",
    false
  ]
]){
  Deno.test(`FCM HTTP ${status} retains status classification with malformed details`, async ()=>{
    const result = await sendFcmMessage(syntheticCredentials, "synthetic-oauth", syntheticMessage, ()=>Promise.resolve(new Response(body, {
        status
      })));
    assertEquals(result.ok, false);
    assertEquals(result.retryable, retryable);
    assertEquals(result.errorCode, code);
  });
}
Deno.test("FCM retry metadata survives malformed error body and ignores accepted response Retry-After", async ()=>{
  for (const [status, header, floor] of [
    [
      429,
      "120",
      120
    ],
    [
      503,
      "300",
      300
    ],
    [
      429,
      "garbage",
      60
    ],
    [
      503,
      "999999",
      3601
    ],
    [
      200,
      "120",
      null
    ]
  ]){
    const result = await sendFcmMessage(syntheticCredentials, "synthetic", syntheticMessage, ()=>Promise.resolve(new Response("invalid-json", {
        status,
        headers: {
          "retry-after": header
        }
      })));
    assertEquals(result.retryAfterSeconds, floor);
  }
});
Deno.test("FCM rejects missing recipient before provider fetch", async ()=>{
  let sends = 0;
  let refused = false;
  try {
    await sendFcmMessage(syntheticCredentials, "synthetic", {
      ...syntheticMessage,
      recipientId: ""
    }, ()=>{
      sends++;
      throw new Error("no fetch");
    });
  } catch  {
    refused = true;
  }
  assertEquals(refused, true);
  assertEquals(sends, 0);
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL19zaGFyZWQvZmNtX3Rlc3QudHMiXSwic291cmNlc0NvbnRlbnQiOlsiaW1wb3J0IHtcbiAgYXNzZXJ0LFxuICBhc3NlcnRFcXVhbHMsXG59IGZyb20gXCJodHRwczovL2Rlbm8ubGFuZC9zdGRAMC4yMjQuMC9hc3NlcnQvbW9kLnRzXCI7XG5pbXBvcnQgeyBzZW5kRmNtTWVzc2FnZSB9IGZyb20gXCIuL2ZjbS50c1wiO1xuXG5EZW5vLnRlc3QoXCJGQ00gc2VuZGVyIGVtaXRzIHByaXZhdGUgY2hhbm5lbC1yb3V0ZWQgZGF0YSBhbmQgY2xhc3NpZmllcyBpbnZhbGlkIHRva2Vuc1wiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IHJlcXVlc3RzOiBSZXF1ZXN0W10gPSBbXTtcbiAgY29uc3QgcmVzdWx0ID0gYXdhaXQgc2VuZEZjbU1lc3NhZ2UoXG4gICAge1xuICAgICAgc2VydmljZUFjY291bnRKc29uOiBKU09OLnN0cmluZ2lmeSh7XG4gICAgICAgIHByb2plY3RfaWQ6IFwiY29sbGVjdC1wcm9qZWN0XCIsXG4gICAgICAgIGNsaWVudF9lbWFpbDogXCJwdXNoQGV4YW1wbGUudGVzdFwiLFxuICAgICAgICBwcml2YXRlX2tleTogXCJ1bnVzZWRcIixcbiAgICAgIH0pLFxuICAgIH0sXG4gICAgXCJvYXV0aC10b2tlblwiLFxuICAgIHtcbiAgICAgIHRva2VuOiBcImZjbS1kZXZpY2UtdG9rZW5cIixcbiAgICAgIHRpdGxlOiBcIkNvbnRyaWJ1dGlvbiBjb25maXJtZWRcIixcbiAgICAgIGJvZHk6IFwiUldGIDUsMDAwIGhhcyBiZWVuIGNvbmZpcm1lZC5cIixcbiAgICAgIHJlY2lwaWVudElkOiBcIjk5ODcwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwMVwiLFxuICAgICAgZXZlbnRJZDogXCJldmVudC0xXCIsXG4gICAgICBldmVudFR5cGU6IFwiY29udHJpYnV0aW9uX2NvbmZpcm1lZFwiLFxuICAgICAgZGVlcExpbms6IFwiL2dyb3Vwcy9ncm91cC0xL2xlZGdlclwiLFxuICAgIH0sXG4gICAgYXN5bmMgKGlucHV0LCBpbml0KSA9PiB7XG4gICAgICByZXF1ZXN0cy5wdXNoKG5ldyBSZXF1ZXN0KGlucHV0LCBpbml0KSk7XG4gICAgICByZXR1cm4gbmV3IFJlc3BvbnNlKFxuICAgICAgICBKU09OLnN0cmluZ2lmeSh7XG4gICAgICAgICAgZXJyb3I6IHtcbiAgICAgICAgICAgIHN0YXR1czogXCJOT1RfRk9VTkRcIixcbiAgICAgICAgICAgIGRldGFpbHM6IFt7IGVycm9yQ29kZTogXCJVTlJFR0lTVEVSRURcIiB9XSxcbiAgICAgICAgICB9LFxuICAgICAgICB9KSxcbiAgICAgICAgeyBzdGF0dXM6IDQwNCB9LFxuICAgICAgKTtcbiAgICB9LFxuICApO1xuICBjb25zdCByZXF1ZXN0ID0gcmVxdWVzdHNbMF07XG4gIGFzc2VydChyZXF1ZXN0KTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIHJlcXVlc3QudXJsLFxuICAgIFwiaHR0cHM6Ly9mY20uZ29vZ2xlYXBpcy5jb20vdjEvcHJvamVjdHMvY29sbGVjdC1wcm9qZWN0L21lc3NhZ2VzOnNlbmRcIixcbiAgKTtcbiAgY29uc3QgcGF5bG9hZCA9IGF3YWl0IHJlcXVlc3QuanNvbigpO1xuICBhc3NlcnRFcXVhbHMocGF5bG9hZC5tZXNzYWdlLm5vdGlmaWNhdGlvbiwge1xuICAgIHRpdGxlOiBcIkNvbGxlY3RcIixcbiAgICBib2R5OiBcIk9wZW4gQ29sbGVjdCB0byB2aWV3IHlvdXIgdXBkYXRlc1wiLFxuICB9KTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIHBheWxvYWQubWVzc2FnZS5kYXRhLnJlY2lwaWVudF9pZCxcbiAgICBcIjk5ODcwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwMVwiLFxuICApO1xuICBhc3NlcnRFcXVhbHMocGF5bG9hZC5tZXNzYWdlLmRhdGEuY29sbGVjdF9wdXNoX3ZlcnNpb24sIFwiMlwiKTtcbiAgYXNzZXJ0RXF1YWxzKEpTT04uc3RyaW5naWZ5KHBheWxvYWQpLmluY2x1ZGVzKFwiUldGIDUsMDAwXCIpLCBmYWxzZSk7XG4gIGFzc2VydEVxdWFscyhwYXlsb2FkLm1lc3NhZ2UuZGF0YS5kZWVwX2xpbmssIFwiL2dyb3Vwcy9ncm91cC0xL2xlZGdlclwiKTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIHBheWxvYWQubWVzc2FnZS5hbmRyb2lkLm5vdGlmaWNhdGlvbi5jaGFubmVsX2lkLFxuICAgIFwiY29sbGVjdF9jb250cmlidXRpb25zXCIsXG4gICk7XG4gIGFzc2VydEVxdWFscyhwYXlsb2FkLm1lc3NhZ2UuYW5kcm9pZC5ub3RpZmljYXRpb24udmlzaWJpbGl0eSwgXCJQUklWQVRFXCIpO1xuICBhc3NlcnRFcXVhbHMocmVzdWx0Lm9rLCBmYWxzZSk7XG4gIGFzc2VydEVxdWFscyhyZXN1bHQucmV0cnlhYmxlLCBmYWxzZSk7XG4gIGFzc2VydEVxdWFscyhyZXN1bHQuZXJyb3JDb2RlLCBcIlVOUkVHSVNURVJFRFwiKTtcbn0pO1xuXG5jb25zdCBzeW50aGV0aWNDcmVkZW50aWFscyA9IHtcbiAgc2VydmljZUFjY291bnRKc29uOiBKU09OLnN0cmluZ2lmeSh7XG4gICAgcHJvamVjdF9pZDogXCJjb2xsZWN0LXByb2plY3RcIixcbiAgICBjbGllbnRfZW1haWw6IFwicHVzaEBleGFtcGxlLnRlc3RcIixcbiAgICBwcml2YXRlX2tleTogXCJ1bnVzZWRcIixcbiAgfSksXG59O1xuY29uc3Qgc3ludGhldGljTWVzc2FnZSA9IHtcbiAgdG9rZW46IFwic3ludGhldGljLWRldmljZS10b2tlblwiLFxuICB0aXRsZTogXCJTeW50aGV0aWNcIixcbiAgYm9keTogXCJTeW50aGV0aWMgb25seVwiLFxuICByZWNpcGllbnRJZDogXCI5OTg3MDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDFcIixcbiAgZXZlbnRJZDogXCJldmVudC0xXCIsXG4gIGV2ZW50VHlwZTogXCJncm91cF91cGRhdGVcIixcbn07XG5cbmZvciAoXG4gIGNvbnN0IFtsYWJlbCwgcmVzcG9uc2VdIG9mIFtcbiAgICBbXCJ1bnJlYWRhYmxlIHN0cmVhbVwiLCAoKSA9PlxuICAgICAgbmV3IFJlc3BvbnNlKFxuICAgICAgICBuZXcgUmVhZGFibGVTdHJlYW0oe1xuICAgICAgICAgIHN0YXJ0KGNvbnRyb2xsZXIpIHtcbiAgICAgICAgICAgIGNvbnRyb2xsZXIuZXJyb3IobmV3IEVycm9yKFwicHJpdmF0ZSBzdHJlYW0gZmFpbHVyZVwiKSk7XG4gICAgICAgICAgfSxcbiAgICAgICAgfSksXG4gICAgICApXSxcbiAgICBbXCJvdmVyc2l6ZWQgYm9keVwiLCAoKSA9PiBuZXcgUmVzcG9uc2UoXCJ4XCIucmVwZWF0KDY1NTM3KSldLFxuICAgIFtcImludmFsaWQgVVRGLThcIiwgKCkgPT4gbmV3IFJlc3BvbnNlKG5ldyBVaW50OEFycmF5KFsyNTVdKSldLFxuICAgIFtcIm1hbGZvcm1lZCBKU09OXCIsICgpID0+IG5ldyBSZXNwb25zZShcIm5vdCBqc29uXCIpXSxcbiAgICBbXCJudWxsIHBheWxvYWRcIiwgKCkgPT4gbmV3IFJlc3BvbnNlKFwibnVsbFwiKV0sXG4gICAgW1wibWFsZm9ybWVkIGVycm9yIHNoYXBlXCIsICgpID0+IG5ldyBSZXNwb25zZSgne1wiZXJyb3JcIjp7XCJkZXRhaWxzXCI6M319JyldLFxuICBdIGFzIGNvbnN0XG4pIHtcbiAgRGVuby50ZXN0KGBGQ00gYWNjZXB0ZWQgJHtsYWJlbH0gbmV2ZXIgYmVjb21lcyBhIHJldHJ5YWJsZSBzZW5kYCwgYXN5bmMgKCkgPT4ge1xuICAgIGxldCBzZW5kcyA9IDA7XG4gICAgY29uc3QgcmVzdWx0ID0gYXdhaXQgc2VuZEZjbU1lc3NhZ2UoXG4gICAgICBzeW50aGV0aWNDcmVkZW50aWFscyxcbiAgICAgIFwic3ludGhldGljLW9hdXRoXCIsXG4gICAgICBzeW50aGV0aWNNZXNzYWdlLFxuICAgICAgKCkgPT4ge1xuICAgICAgICBzZW5kcyArPSAxO1xuICAgICAgICByZXR1cm4gUHJvbWlzZS5yZXNvbHZlKHJlc3BvbnNlKCkpO1xuICAgICAgfSxcbiAgICApO1xuICAgIGFzc2VydEVxdWFscyhzZW5kcywgMSk7XG4gICAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5vaywgdHJ1ZSk7XG4gICAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5yZXRyeWFibGUsIGZhbHNlKTtcbiAgICBhc3NlcnRFcXVhbHMocmVzdWx0Lm1lc3NhZ2VJZCwgbnVsbCk7XG4gICAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5lcnJvckNvZGUsIFwiYWNjZXB0ZWRfcmVzcG9uc2VfdW5hdmFpbGFibGVcIik7XG4gIH0pO1xufVxuXG5EZW5vLnRlc3QoXCJGQ00gYWNjZXB0ZWQgbWVzc2FnZSByZXRhaW5zIGl0cyBkb2N1bWVudGVkIG1lc3NhZ2UgbmFtZVwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IHJlc3VsdCA9IGF3YWl0IHNlbmRGY21NZXNzYWdlKFxuICAgIHN5bnRoZXRpY0NyZWRlbnRpYWxzLFxuICAgIFwic3ludGhldGljLW9hdXRoXCIsXG4gICAgc3ludGhldGljTWVzc2FnZSxcbiAgICAoKSA9PlxuICAgICAgUHJvbWlzZS5yZXNvbHZlKFxuICAgICAgICBuZXcgUmVzcG9uc2UoJ3tcIm5hbWVcIjpcInByb2plY3RzL2NvbGxlY3QtcHJvamVjdC9tZXNzYWdlcy8wOjEyMyVhYmNcIn0nKSxcbiAgICAgICksXG4gICk7XG4gIGFzc2VydEVxdWFscyhyZXN1bHQub2ssIHRydWUpO1xuICBhc3NlcnRFcXVhbHMocmVzdWx0Lm1lc3NhZ2VJZCwgXCJwcm9qZWN0cy9jb2xsZWN0LXByb2plY3QvbWVzc2FnZXMvMDoxMjMlYWJjXCIpO1xuICBhc3NlcnRFcXVhbHMocmVzdWx0LmVycm9yQ29kZSwgbnVsbCk7XG59KTtcblxuZm9yIChcbiAgY29uc3QgW3N0YXR1cywgYm9keSwgY29kZSwgcmV0cnlhYmxlXSBvZiBbXG4gICAgWzUwMywgXCJudWxsXCIsIFwiaHR0cF81MDNcIiwgdHJ1ZV0sXG4gICAgWzQyOSwgJ3tcImVycm9yXCI6e1wiZGV0YWlsc1wiOjd9fScsIFwiaHR0cF80MjlcIiwgdHJ1ZV0sXG4gICAgW1xuICAgICAgNDAwLFxuICAgICAgJ3tcImVycm9yXCI6e1wic3RhdHVzXCI6XCJwcml2YXRlIGFjY291bnQgKzI1MDc4ODEyMzQ1NlwifX0nLFxuICAgICAgXCJodHRwXzQwMFwiLFxuICAgICAgZmFsc2UsXG4gICAgXSxcbiAgICBbXG4gICAgICA0MDQsXG4gICAgICAne1wiZXJyb3JcIjp7XCJkZXRhaWxzXCI6W251bGwsNyx7XCJlcnJvckNvZGVcIjpcIlVOUkVHSVNURVJFRFwifV19fScsXG4gICAgICBcIlVOUkVHSVNURVJFRFwiLFxuICAgICAgZmFsc2UsXG4gICAgXSxcbiAgXSBhcyBjb25zdFxuKSB7XG4gIERlbm8udGVzdChgRkNNIEhUVFAgJHtzdGF0dXN9IHJldGFpbnMgc3RhdHVzIGNsYXNzaWZpY2F0aW9uIHdpdGggbWFsZm9ybWVkIGRldGFpbHNgLCBhc3luYyAoKSA9PiB7XG4gICAgY29uc3QgcmVzdWx0ID0gYXdhaXQgc2VuZEZjbU1lc3NhZ2UoXG4gICAgICBzeW50aGV0aWNDcmVkZW50aWFscyxcbiAgICAgIFwic3ludGhldGljLW9hdXRoXCIsXG4gICAgICBzeW50aGV0aWNNZXNzYWdlLFxuICAgICAgKCkgPT4gUHJvbWlzZS5yZXNvbHZlKG5ldyBSZXNwb25zZShib2R5LCB7IHN0YXR1cyB9KSksXG4gICAgKTtcbiAgICBhc3NlcnRFcXVhbHMocmVzdWx0Lm9rLCBmYWxzZSk7XG4gICAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5yZXRyeWFibGUsIHJldHJ5YWJsZSk7XG4gICAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5lcnJvckNvZGUsIGNvZGUpO1xuICB9KTtcbn1cblxuRGVuby50ZXN0KFwiRkNNIHJldHJ5IG1ldGFkYXRhIHN1cnZpdmVzIG1hbGZvcm1lZCBlcnJvciBib2R5IGFuZCBpZ25vcmVzIGFjY2VwdGVkIHJlc3BvbnNlIFJldHJ5LUFmdGVyXCIsIGFzeW5jICgpID0+IHtcbiAgZm9yIChcbiAgICBjb25zdCBbc3RhdHVzLCBoZWFkZXIsIGZsb29yXSBvZiBbXG4gICAgICBbNDI5LCBcIjEyMFwiLCAxMjBdLFxuICAgICAgWzUwMywgXCIzMDBcIiwgMzAwXSxcbiAgICAgIFs0MjksIFwiZ2FyYmFnZVwiLCA2MF0sXG4gICAgICBbNTAzLCBcIjk5OTk5OVwiLCAzNjAxXSxcbiAgICAgIFsyMDAsIFwiMTIwXCIsIG51bGxdLFxuICAgIF0gYXMgY29uc3RcbiAgKSB7XG4gICAgY29uc3QgcmVzdWx0ID0gYXdhaXQgc2VuZEZjbU1lc3NhZ2UoXG4gICAgICBzeW50aGV0aWNDcmVkZW50aWFscyxcbiAgICAgIFwic3ludGhldGljXCIsXG4gICAgICBzeW50aGV0aWNNZXNzYWdlLFxuICAgICAgKCkgPT5cbiAgICAgICAgUHJvbWlzZS5yZXNvbHZlKFxuICAgICAgICAgIG5ldyBSZXNwb25zZShcImludmFsaWQtanNvblwiLCB7XG4gICAgICAgICAgICBzdGF0dXMsXG4gICAgICAgICAgICBoZWFkZXJzOiB7IFwicmV0cnktYWZ0ZXJcIjogaGVhZGVyIH0sXG4gICAgICAgICAgfSksXG4gICAgICAgICksXG4gICAgKTtcbiAgICBhc3NlcnRFcXVhbHMocmVzdWx0LnJldHJ5QWZ0ZXJTZWNvbmRzLCBmbG9vcik7XG4gIH1cbn0pO1xuRGVuby50ZXN0KFwiRkNNIHJlamVjdHMgbWlzc2luZyByZWNpcGllbnQgYmVmb3JlIHByb3ZpZGVyIGZldGNoXCIsIGFzeW5jICgpID0+IHtcbiAgbGV0IHNlbmRzID0gMDtcbiAgbGV0IHJlZnVzZWQgPSBmYWxzZTtcbiAgdHJ5IHtcbiAgICBhd2FpdCBzZW5kRmNtTWVzc2FnZShzeW50aGV0aWNDcmVkZW50aWFscywgXCJzeW50aGV0aWNcIiwge1xuICAgICAgLi4uc3ludGhldGljTWVzc2FnZSxcbiAgICAgIHJlY2lwaWVudElkOiBcIlwiLFxuICAgIH0sICgpID0+IHtcbiAgICAgIHNlbmRzKys7XG4gICAgICB0aHJvdyBuZXcgRXJyb3IoXCJubyBmZXRjaFwiKTtcbiAgICB9KTtcbiAgfSBjYXRjaCB7XG4gICAgcmVmdXNlZCA9IHRydWU7XG4gIH1cbiAgYXNzZXJ0RXF1YWxzKHJlZnVzZWQsIHRydWUpO1xuICBhc3NlcnRFcXVhbHMoc2VuZHMsIDApO1xufSk7XG4iXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IkFBQUEsU0FDRSxNQUFNLEVBQ04sWUFBWSxRQUNQLDhDQUE4QztBQUNyRCxTQUFTLGNBQWMsUUFBUSxXQUFXO0FBRTFDLEtBQUssSUFBSSxDQUFDLDhFQUE4RTtFQUN0RixNQUFNLFdBQXNCLEVBQUU7RUFDOUIsTUFBTSxTQUFTLE1BQU0sZUFDbkI7SUFDRSxvQkFBb0IsS0FBSyxTQUFTLENBQUM7TUFDakMsWUFBWTtNQUNaLGNBQWM7TUFDZCxhQUFhO0lBQ2Y7RUFDRixHQUNBLGVBQ0E7SUFDRSxPQUFPO0lBQ1AsT0FBTztJQUNQLE1BQU07SUFDTixhQUFhO0lBQ2IsU0FBUztJQUNULFdBQVc7SUFDWCxVQUFVO0VBQ1osR0FDQSxPQUFPLE9BQU87SUFDWixTQUFTLElBQUksQ0FBQyxJQUFJLFFBQVEsT0FBTztJQUNqQyxPQUFPLElBQUksU0FDVCxLQUFLLFNBQVMsQ0FBQztNQUNiLE9BQU87UUFDTCxRQUFRO1FBQ1IsU0FBUztVQUFDO1lBQUUsV0FBVztVQUFlO1NBQUU7TUFDMUM7SUFDRixJQUNBO01BQUUsUUFBUTtJQUFJO0VBRWxCO0VBRUYsTUFBTSxVQUFVLFFBQVEsQ0FBQyxFQUFFO0VBQzNCLE9BQU87RUFDUCxhQUNFLFFBQVEsR0FBRyxFQUNYO0VBRUYsTUFBTSxVQUFVLE1BQU0sUUFBUSxJQUFJO0VBQ2xDLGFBQWEsUUFBUSxPQUFPLENBQUMsWUFBWSxFQUFFO0lBQ3pDLE9BQU87SUFDUCxNQUFNO0VBQ1I7RUFDQSxhQUNFLFFBQVEsT0FBTyxDQUFDLElBQUksQ0FBQyxZQUFZLEVBQ2pDO0VBRUYsYUFBYSxRQUFRLE9BQU8sQ0FBQyxJQUFJLENBQUMsb0JBQW9CLEVBQUU7RUFDeEQsYUFBYSxLQUFLLFNBQVMsQ0FBQyxTQUFTLFFBQVEsQ0FBQyxjQUFjO0VBQzVELGFBQWEsUUFBUSxPQUFPLENBQUMsSUFBSSxDQUFDLFNBQVMsRUFBRTtFQUM3QyxhQUNFLFFBQVEsT0FBTyxDQUFDLE9BQU8sQ0FBQyxZQUFZLENBQUMsVUFBVSxFQUMvQztFQUVGLGFBQWEsUUFBUSxPQUFPLENBQUMsT0FBTyxDQUFDLFlBQVksQ0FBQyxVQUFVLEVBQUU7RUFDOUQsYUFBYSxPQUFPLEVBQUUsRUFBRTtFQUN4QixhQUFhLE9BQU8sU0FBUyxFQUFFO0VBQy9CLGFBQWEsT0FBTyxTQUFTLEVBQUU7QUFDakM7QUFFQSxNQUFNLHVCQUF1QjtFQUMzQixvQkFBb0IsS0FBSyxTQUFTLENBQUM7SUFDakMsWUFBWTtJQUNaLGNBQWM7SUFDZCxhQUFhO0VBQ2Y7QUFDRjtBQUNBLE1BQU0sbUJBQW1CO0VBQ3ZCLE9BQU87RUFDUCxPQUFPO0VBQ1AsTUFBTTtFQUNOLGFBQWE7RUFDYixTQUFTO0VBQ1QsV0FBVztBQUNiO0FBRUEsS0FDRSxNQUFNLENBQUMsT0FBTyxTQUFTLElBQUk7RUFDekI7SUFBQztJQUFxQixJQUNwQixJQUFJLFNBQ0YsSUFBSSxlQUFlO1FBQ2pCLE9BQU0sVUFBVTtVQUNkLFdBQVcsS0FBSyxDQUFDLElBQUksTUFBTTtRQUM3QjtNQUNGO0dBQ0E7RUFDSjtJQUFDO0lBQWtCLElBQU0sSUFBSSxTQUFTLElBQUksTUFBTSxDQUFDO0dBQVE7RUFDekQ7SUFBQztJQUFpQixJQUFNLElBQUksU0FBUyxJQUFJLFdBQVc7UUFBQztPQUFJO0dBQUc7RUFDNUQ7SUFBQztJQUFrQixJQUFNLElBQUksU0FBUztHQUFZO0VBQ2xEO0lBQUM7SUFBZ0IsSUFBTSxJQUFJLFNBQVM7R0FBUTtFQUM1QztJQUFDO0lBQXlCLElBQU0sSUFBSSxTQUFTO0dBQTJCO0NBQ3pFLENBQ0Q7RUFDQSxLQUFLLElBQUksQ0FBQyxDQUFDLGFBQWEsRUFBRSxNQUFNLCtCQUErQixDQUFDLEVBQUU7SUFDaEUsSUFBSSxRQUFRO0lBQ1osTUFBTSxTQUFTLE1BQU0sZUFDbkIsc0JBQ0EsbUJBQ0Esa0JBQ0E7TUFDRSxTQUFTO01BQ1QsT0FBTyxRQUFRLE9BQU8sQ0FBQztJQUN6QjtJQUVGLGFBQWEsT0FBTztJQUNwQixhQUFhLE9BQU8sRUFBRSxFQUFFO0lBQ3hCLGFBQWEsT0FBTyxTQUFTLEVBQUU7SUFDL0IsYUFBYSxPQUFPLFNBQVMsRUFBRTtJQUMvQixhQUFhLE9BQU8sU0FBUyxFQUFFO0VBQ2pDO0FBQ0Y7QUFFQSxLQUFLLElBQUksQ0FBQyw0REFBNEQ7RUFDcEUsTUFBTSxTQUFTLE1BQU0sZUFDbkIsc0JBQ0EsbUJBQ0Esa0JBQ0EsSUFDRSxRQUFRLE9BQU8sQ0FDYixJQUFJLFNBQVM7RUFHbkIsYUFBYSxPQUFPLEVBQUUsRUFBRTtFQUN4QixhQUFhLE9BQU8sU0FBUyxFQUFFO0VBQy9CLGFBQWEsT0FBTyxTQUFTLEVBQUU7QUFDakM7QUFFQSxLQUNFLE1BQU0sQ0FBQyxRQUFRLE1BQU0sTUFBTSxVQUFVLElBQUk7RUFDdkM7SUFBQztJQUFLO0lBQVE7SUFBWTtHQUFLO0VBQy9CO0lBQUM7SUFBSztJQUEyQjtJQUFZO0dBQUs7RUFDbEQ7SUFDRTtJQUNBO0lBQ0E7SUFDQTtHQUNEO0VBQ0Q7SUFDRTtJQUNBO0lBQ0E7SUFDQTtHQUNEO0NBQ0YsQ0FDRDtFQUNBLEtBQUssSUFBSSxDQUFDLENBQUMsU0FBUyxFQUFFLE9BQU8scURBQXFELENBQUMsRUFBRTtJQUNuRixNQUFNLFNBQVMsTUFBTSxlQUNuQixzQkFDQSxtQkFDQSxrQkFDQSxJQUFNLFFBQVEsT0FBTyxDQUFDLElBQUksU0FBUyxNQUFNO1FBQUU7TUFBTztJQUVwRCxhQUFhLE9BQU8sRUFBRSxFQUFFO0lBQ3hCLGFBQWEsT0FBTyxTQUFTLEVBQUU7SUFDL0IsYUFBYSxPQUFPLFNBQVMsRUFBRTtFQUNqQztBQUNGO0FBRUEsS0FBSyxJQUFJLENBQUMsOEZBQThGO0VBQ3RHLEtBQ0UsTUFBTSxDQUFDLFFBQVEsUUFBUSxNQUFNLElBQUk7SUFDL0I7TUFBQztNQUFLO01BQU87S0FBSTtJQUNqQjtNQUFDO01BQUs7TUFBTztLQUFJO0lBQ2pCO01BQUM7TUFBSztNQUFXO0tBQUc7SUFDcEI7TUFBQztNQUFLO01BQVU7S0FBSztJQUNyQjtNQUFDO01BQUs7TUFBTztLQUFLO0dBQ25CLENBQ0Q7SUFDQSxNQUFNLFNBQVMsTUFBTSxlQUNuQixzQkFDQSxhQUNBLGtCQUNBLElBQ0UsUUFBUSxPQUFPLENBQ2IsSUFBSSxTQUFTLGdCQUFnQjtRQUMzQjtRQUNBLFNBQVM7VUFBRSxlQUFlO1FBQU87TUFDbkM7SUFHTixhQUFhLE9BQU8saUJBQWlCLEVBQUU7RUFDekM7QUFDRjtBQUNBLEtBQUssSUFBSSxDQUFDLHVEQUF1RDtFQUMvRCxJQUFJLFFBQVE7RUFDWixJQUFJLFVBQVU7RUFDZCxJQUFJO0lBQ0YsTUFBTSxlQUFlLHNCQUFzQixhQUFhO01BQ3RELEdBQUcsZ0JBQWdCO01BQ25CLGFBQWE7SUFDZixHQUFHO01BQ0Q7TUFDQSxNQUFNLElBQUksTUFBTTtJQUNsQjtFQUNGLEVBQUUsT0FBTTtJQUNOLFVBQVU7RUFDWjtFQUNBLGFBQWEsU0FBUztFQUN0QixhQUFhLE9BQU87QUFDdEIifQ==
// denoCacheMetadata=1152084665094897321,1167923457451190150
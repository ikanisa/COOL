import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { sendFcmMessage } from "./fcm.ts";

Deno.test("FCM sender emits private channel-routed data and classifies invalid tokens", async () => {
  const requests: Request[] = [];
  const result = await sendFcmMessage(
    {
      serviceAccountJson: JSON.stringify({
        project_id: "collect-project",
        client_email: "push@example.test",
        private_key: "unused",
      }),
    },
    "oauth-token",
    {
      token: "fcm-device-token",
      title: "Contribution confirmed",
      body: "RWF 5,000 has been confirmed.",
      recipientId: "99870000-0000-4000-8000-000000000001",
      eventId: "event-1",
      eventType: "contribution_confirmed",
      deepLink: "/groups/group-1/ledger",
    },
    async (input, init) => {
      requests.push(new Request(input, init));
      return new Response(
        JSON.stringify({
          error: {
            status: "NOT_FOUND",
            details: [{ errorCode: "UNREGISTERED" }],
          },
        }),
        { status: 404 },
      );
    },
  );
  const request = requests[0];
  assert(request);
  assertEquals(
    request.url,
    "https://fcm.googleapis.com/v1/projects/collect-project/messages:send",
  );
  const payload = await request.json();
  assertEquals(payload.message.notification, {
    title: "Collect",
    body: "Open Collect to view your updates",
  });
  assertEquals(
    payload.message.data.recipient_id,
    "99870000-0000-4000-8000-000000000001",
  );
  assertEquals(payload.message.data.collect_push_version, "2");
  assertEquals(JSON.stringify(payload).includes("RWF 5,000"), false);
  assertEquals(payload.message.data.deep_link, "/groups/group-1/ledger");
  assertEquals(
    payload.message.android.notification.channel_id,
    "collect_contributions",
  );
  assertEquals(payload.message.android.notification.visibility, "PRIVATE");
  assertEquals(result.ok, false);
  assertEquals(result.retryable, false);
  assertEquals(result.errorCode, "UNREGISTERED");
});

const syntheticCredentials = {
  serviceAccountJson: JSON.stringify({
    project_id: "collect-project",
    client_email: "push@example.test",
    private_key: "unused",
  }),
};
const syntheticMessage = {
  token: "synthetic-device-token",
  title: "Synthetic",
  body: "Synthetic only",
  recipientId: "99870000-0000-4000-8000-000000000001",
  eventId: "event-1",
  eventType: "group_update",
};

for (
  const [label, response] of [
    ["unreadable stream", () =>
      new Response(
        new ReadableStream({
          start(controller) {
            controller.error(new Error("private stream failure"));
          },
        }),
      )],
    ["oversized body", () => new Response("x".repeat(65537))],
    ["invalid UTF-8", () => new Response(new Uint8Array([255]))],
    ["malformed JSON", () => new Response("not json")],
    ["null payload", () => new Response("null")],
    ["malformed error shape", () => new Response('{"error":{"details":3}}')],
  ] as const
) {
  Deno.test(`FCM accepted ${label} never becomes a retryable send`, async () => {
    let sends = 0;
    const result = await sendFcmMessage(
      syntheticCredentials,
      "synthetic-oauth",
      syntheticMessage,
      () => {
        sends += 1;
        return Promise.resolve(response());
      },
    );
    assertEquals(sends, 1);
    assertEquals(result.ok, true);
    assertEquals(result.retryable, false);
    assertEquals(result.messageId, null);
    assertEquals(result.errorCode, "accepted_response_unavailable");
  });
}

Deno.test("FCM accepted message retains its documented message name", async () => {
  const result = await sendFcmMessage(
    syntheticCredentials,
    "synthetic-oauth",
    syntheticMessage,
    () =>
      Promise.resolve(
        new Response('{"name":"projects/collect-project/messages/0:123%abc"}'),
      ),
  );
  assertEquals(result.ok, true);
  assertEquals(result.messageId, "projects/collect-project/messages/0:123%abc");
  assertEquals(result.errorCode, null);
});

for (
  const [status, body, code, retryable] of [
    [503, "null", "http_503", true],
    [429, '{"error":{"details":7}}', "http_429", true],
    [
      400,
      '{"error":{"status":"private account +250788123456"}}',
      "http_400",
      false,
    ],
    [
      404,
      '{"error":{"details":[null,7,{"errorCode":"UNREGISTERED"}]}}',
      "UNREGISTERED",
      false,
    ],
  ] as const
) {
  Deno.test(`FCM HTTP ${status} retains status classification with malformed details`, async () => {
    const result = await sendFcmMessage(
      syntheticCredentials,
      "synthetic-oauth",
      syntheticMessage,
      () => Promise.resolve(new Response(body, { status })),
    );
    assertEquals(result.ok, false);
    assertEquals(result.retryable, retryable);
    assertEquals(result.errorCode, code);
  });
}

Deno.test("FCM retry metadata survives malformed error body and ignores accepted response Retry-After", async () => {
  for (
    const [status, header, floor] of [
      [429, "120", 120],
      [503, "300", 300],
      [429, "garbage", 60],
      [503, "999999", 3601],
      [200, "120", null],
    ] as const
  ) {
    const result = await sendFcmMessage(
      syntheticCredentials,
      "synthetic",
      syntheticMessage,
      () =>
        Promise.resolve(
          new Response("invalid-json", {
            status,
            headers: { "retry-after": header },
          }),
        ),
    );
    assertEquals(result.retryAfterSeconds, floor);
  }
});
Deno.test("FCM rejects missing recipient before provider fetch", async () => {
  let sends = 0;
  let refused = false;
  try {
    await sendFcmMessage(syntheticCredentials, "synthetic", {
      ...syntheticMessage,
      recipientId: "",
    }, () => {
      sends++;
      throw new Error("no fetch");
    });
  } catch {
    refused = true;
  }
  assertEquals(refused, true);
  assertEquals(sends, 0);
});

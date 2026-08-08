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
      eventId: "event-1",
      eventType: "contribution_confirmed",
      deepLink: "/groups/group-1/ledger",
    },
    async (input, init) => {
      requests.push(new Request(input, init));
      return new Response(JSON.stringify({
        error: {
          status: "NOT_FOUND",
          details: [{ errorCode: "UNREGISTERED" }],
        },
      }), { status: 404 });
    },
  );
  const request = requests[0];
  assert(request);
  assertEquals(
    request.url,
    "https://fcm.googleapis.com/v1/projects/collect-project/messages:send",
  );
  const payload = await request.json();
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

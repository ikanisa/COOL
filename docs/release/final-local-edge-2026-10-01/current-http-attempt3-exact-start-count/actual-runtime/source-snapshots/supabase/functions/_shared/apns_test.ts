import {
  assert,
  assertEquals,
  assertMatch,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createApnsJwt, sendApnsMessage } from "./apns.ts";

function encodedPem(pem: string): string {
  return btoa(pem);
}

Deno.test("APNs JWT contains the configured key, team, and issued-at claims", async () => {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", pair.privateKey),
  );
  let binary = "";
  for (const byte of pkcs8) binary += String.fromCharCode(byte);
  const derBase64 = btoa(binary);
  const pem =
    `-----BEGIN PRIVATE KEY-----\n${derBase64}\n-----END PRIVATE KEY-----`;
  const jwt = await createApnsJwt({
    keyId: "KEY123",
    teamId: "TEAM123",
    privateKeyBase64: encodedPem(pem),
  }, 1_700_000_000);
  const [header, claims, signature] = jwt.split(".");
  const decode = (value: string) =>
    JSON.parse(
      atob(value.replaceAll("-", "+").replaceAll("_", "/")),
    );
  assertEquals(decode(header), { alg: "ES256", kid: "KEY123" });
  assertEquals(decode(claims), { iss: "TEAM123", iat: 1_700_000_000 });
  assertMatch(signature, /^[A-Za-z0-9_-]+$/);
});

Deno.test("APNs sender emits a bounded alert payload and classifies retry", async () => {
  const requests: Request[] = [];
  const result = await sendApnsMessage(
    {
      keyId: "KEY123",
      teamId: "TEAM123",
      bundleId: "app.cool.mobile",
      privateKeyBase64: "unused",
    },
    "signed-token",
    {
      token: "a".repeat(64),
      environment: "production",
      title: "Contribution confirmed",
      body: "RWF 5,000 has been confirmed.",
      recipientId: "99870000-0000-4000-8000-000000000001",
      eventId: "event-1",
      eventType: "contribution_confirmed",
      deepLink: "/groups/group-1/ledger",
    },
    async (input, init) => {
      requests.push(new Request(input, init));
      return new Response(JSON.stringify({ reason: "TooManyRequests" }), {
        status: 429,
        headers: { "apns-id": "message-1" },
      });
    },
  );
  const request = requests[0];
  assert(request);
  assertEquals(
    request.url,
    `https://api.push.apple.com/3/device/${"a".repeat(64)}`,
  );
  assertEquals(request.headers.get("apns-topic"), "app.cool.mobile");
  assertEquals(request.headers.get("apns-push-type"), "alert");
  const payload = await request.json();
  assertEquals(payload.aps.alert, {
    title: "Collect",
    body: "Open Collect to view your updates",
  });
  assertEquals(payload.recipient_id, "99870000-0000-4000-8000-000000000001");
  assertEquals(payload.collect_push_version, "2");
  assertEquals(JSON.stringify(payload).includes("RWF 5,000"), false);
  assertEquals(payload.deep_link, "/groups/group-1/ledger");
  assertEquals(result.ok, false);
  assertEquals(result.retryable, true);
  assertEquals(result.errorCode, "TooManyRequests");
});

Deno.test("APNs retry floors follow 15-minute 5xx and throttled-token policy", async () => {
  for (
    const [status, reason, header, floor] of [
      [503, "Shutdown", "60", 900],
      [500, "InternalServerError", "1200", 1200],
      [429, "TooManyProviderTokenUpdates", "60", 1200],
      [429, "TooManyRequests", "120", 120],
      [410, "Unregistered", "900", null],
    ] as const
  ) {
    const result = await sendApnsMessage(
      {
        keyId: "synthetic",
        teamId: "synthetic",
        bundleId: "app.collect",
        privateKeyBase64: "unused",
      },
      "synthetic",
      {
        token: "synthetic",
        environment: "production",
        title: "Private",
        body: "Private",
        recipientId: "99870000-0000-4000-8000-000000000001",
        eventId: "synthetic",
        eventType: "notice",
      },
      () =>
        Promise.resolve(
          new Response(JSON.stringify({ reason }), {
            status,
            headers: { "retry-after": header },
          }),
        ),
    );
    assertEquals(result.retryAfterSeconds, floor);
    assertEquals(result.retryable, status === 429 || status >= 500);
  }
});

import { assertEquals } from "../_shared/test_assert.ts";
import { createGatewayHandler } from "./handler.ts";

// Actual results of the task-private populated SQL UAT; these are synthetic
// contacts and financial records, never production rows or a current permit.
const fixtureRoot = new URL(
  "../../../contracts/collect-android-dispatch-v2/fixtures/",
  import.meta.url,
);
const fixtures: Record<string, Record<string, unknown>> = {};
for (
  const name of [
    "grant",
    "arm",
    "grant-paused",
    "grant-reconciliation",
    "partial-callback",
    "complete-callback",
    "contradictory-callback",
    "status",
  ]
) {
  fixtures[name] = JSON.parse(
    await Deno.readTextFile(new URL(`observed-${name}.json`, fixtureRoot)),
  );
}
const grant = fixtures.grant;
const encoder = new TextEncoder();
const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
async function digest(bytes: Uint8Array) {
  return Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
    ),
    (n) => n.toString(16).padStart(2, "0"),
  ).join("");
}
function der(raw: Uint8Array) {
  const parts = [raw.slice(0, 32), raw.slice(32)].map((part) => {
    while (part.length > 1 && part[0] === 0) part = part.slice(1);
    if (part[0] & 128) part = Uint8Array.from([0, ...part]);
    return Uint8Array.from([2, part.length, ...part]);
  });
  return Uint8Array.from([
    48,
    parts[0].length + parts[1].length,
    ...parts[0],
    ...parts[1],
  ]);
}

async function check(
  name: string,
  action: string,
  payload: Record<string, unknown>,
  patch: Record<string, unknown> = {},
) {
  const result = { ...fixtures[name], ...patch };
  const recordedTime =
    (result.issued_at ?? result.armed_at ?? result.recorded_at ??
      grant.issued_at) as string;
  const now = Date.parse(recordedTime);
  const requestId =
    (result.request_id ?? "80ca0000-0000-4000-8000-000000000001") as string;
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const spki = new Uint8Array(
    await crypto.subtle.exportKey("spki", pair.publicKey),
  );
  const keyId = await digest(spki);
  const bytes = encoder.encode(
    JSON.stringify({
      contract_version: 2,
      action,
      device_id: grant.device_id,
      request_id: requestId,
      issued_at: new Date(now).toISOString(),
      payload,
    }),
  );
  const signature = der(
    new Uint8Array(
      await crypto.subtle.sign(
        { name: "ECDSA", hash: "SHA-256" },
        pair.privateKey,
        bytes,
      ),
    ),
  );
  const requestDigest = await digest(bytes);
  let called = "";
  const handler = createGatewayHandler({
    now: () => now,
    rpc: (name, args) => {
      if (name === "gateway_device_key_v1") {
        return Promise.resolve({
          data: {
            device_id: grant.device_id,
            state: "active",
            public_key_spki_base64: b64(spki),
            key_sha256: keyId,
            installation_id: grant.run_id,
            signing_certificate_sha256: "f".repeat(64),
          },
          error: null,
        });
      }
      called = name;
      assertEquals(args.p_request_sha256, requestDigest);
      return Promise.resolve({ data: result, error: null });
    },
  });
  // No HTTP/network operation: Request is passed to the actual handler directly.
  const response = await handler(
    new Request("https://gateway.test/collect-android-gateway", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "X-Collect-Gateway-Key-Id": keyId,
        "X-Collect-Gateway-Signature": b64(signature),
      },
      body: bytes,
    }),
  );
  return { response, called, result };
}

const callbackPayload = (result: Record<string, unknown>) => ({
  callback_id: result.callback_id,
  attempt_id: grant.attempt_id,
  fence_version: grant.fence_version,
  segment_index:
    result.callback_id === fixtures["complete-callback"].callback_id ? 1 : 0,
  segment_count: grant.segment_count,
  body_sha256: grant.body_sha256,
  destination_sha256: grant.destination_sha256,
  callback_kind: "sent",
  result_code: result.state === "uncertain" ? 1 : -1,
  tp_status: null,
  occurred_at: result.recorded_at,
});
const cases: [string, string, Record<string, unknown>][] = [
  ["grant", "dispatch_grant", {}],
  ["grant-paused", "dispatch_grant", {}],
  ["arm", "arm_dispatch", {
    attempt_id: grant.attempt_id,
    fence_version: grant.fence_version,
    body_sha256: grant.body_sha256,
    destination_sha256: grant.destination_sha256,
    reservation_sha256: fixtures.arm.reservation_sha256,
    callbacks: [0, 1].map((segment_index) => ({
      segment_index,
      sent_callback_id: segment_index
        ? fixtures["complete-callback"].callback_id
        : fixtures["partial-callback"].callback_id,
      delivery_callback_id: `80ca0000-0000-4000-8000-00000000000${
        segment_index + 2
      }`,
    })),
  }],
  ["grant-reconciliation", "reconcile", {
    target_request_id: grant.request_id,
  }],
  ...["partial-callback", "complete-callback", "contradictory-callback"].map((
    name,
  ): [string, string, Record<string, unknown>] => [
    name,
    "callback",
    callbackPayload(fixtures[name]),
  ]),
  ["status", "attempt_status", {
    attempt_id: grant.attempt_id,
    fence_version: grant.fence_version,
  }],
];
for (const [name, action, payload] of cases) {
  Deno.test(`actual populated SQL ${name} passes signed Edge output contract`, async () => {
    const { response, result } = await check(name, action, payload);
    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.result, result);
    assertEquals(response.headers.get("cache-control"), "no-store");
  });
}
Deno.test("actual SQL grant with corrupted immutable digest is unknown", async () => {
  const { response } = await check("grant", "dispatch_grant", {}, {
    body_sha256: "0".repeat(64),
  });
  assertEquals(response.status, 502);
});
Deno.test("actual SQL recovered request with leaked body is unknown", async () => {
  const source = fixtures["grant-reconciliation"];
  const { response } = await check("grant-reconciliation", "reconcile", {
    target_request_id: grant.request_id,
  }, {
    recorded_result: {
      ...(source.recorded_result as Record<string, unknown>),
      body: grant.body,
    },
  });
  assertEquals(response.status, 502);
});

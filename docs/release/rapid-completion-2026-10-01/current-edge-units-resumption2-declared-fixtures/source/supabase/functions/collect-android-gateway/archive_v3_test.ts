import { assertEquals } from "../_shared/test_assert.ts";
import { createGatewayHandler } from "./handler.ts";
import { archivePayload, archiveResult } from "./archive_v3.ts";
type Json = Record<string, unknown>;
const ID = (i: number) =>
  `ab770000-0000-4000-8000-${String(i).padStart(12, "0")}`;
const NOW = Date.parse("2026-10-01T13:00:00Z");
const TIME = new Date(NOW).toISOString();
const refs = [{
  callback_id: ID(5),
  request_id: ID(7),
  request_sha256: "d".repeat(64),
}, { callback_id: ID(6), request_id: ID(8), request_sha256: "e".repeat(64) }];
function payload(): Json {
  return {
    attempt_id: ID(3),
    fence_version: 1,
    body_sha256: "b".repeat(64),
    destination_sha256: "c".repeat(64),
    callback_requests: structuredClone(refs),
  };
}
function ack(): Json {
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
    send_authority: false,
  };
}
function der(raw: Uint8Array): Uint8Array {
  const parts = [raw.slice(0, 32), raw.slice(32)].map((p) => {
    while (p.length > 1 && p[0] === 0) p = p.slice(1);
    if (p[0] & 128) p = Uint8Array.from([0, ...p]);
    return Uint8Array.from([2, p.length, ...p]);
  });
  return Uint8Array.from([
    48,
    parts[0].length + parts[1].length,
    ...parts[0],
    ...parts[1],
  ]);
}
const b64 = (b: Uint8Array) => btoa(String.fromCharCode(...b));
async function sha(b: Uint8Array): Promise<string> {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(b))),
    (x) => x.toString(16).padStart(2, "0"),
  ).join("");
}
async function exercise(
  envelope: Json,
  result: unknown = ack(),
  mutate?: (bytes: Uint8Array) => Uint8Array,
) {
  const key = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const spki = new Uint8Array(
    await crypto.subtle.exportKey("spki", key.publicKey),
  );
  const fingerprint = await sha(spki);
  const calls: string[] = [];
  let receivedDigest = "";
  const handler = createGatewayHandler({
    now: () => NOW,
    rpc: (name, args) => {
      calls.push(name);
      if (name === "gateway_device_key_v1") {
        return Promise.resolve({
          data: {
            device_id: envelope.device_id,
            state: "revoked",
            public_key_spki_base64: b64(spki),
            key_sha256: fingerprint,
            installation_id: ID(10),
            signing_certificate_sha256: "a".repeat(64),
          },
          error: null,
        });
      }
      receivedDigest = String(args.p_request_sha256);
      return Promise.resolve({ data: result, error: null });
    },
  });
  const bytes = new TextEncoder().encode(JSON.stringify(envelope));
  const signature = der(
    new Uint8Array(
      await crypto.subtle.sign(
        { name: "ECDSA", hash: "SHA-256" },
        key.privateKey,
        new Uint8Array(bytes),
      ),
    ),
  );
  const response = await handler(
    new Request("https://example.test", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "X-Collect-Gateway-Key-Id": fingerprint,
        "X-Collect-Gateway-Signature": b64(signature),
      },
      body: new Uint8Array(mutate ? mutate(bytes) : bytes),
    }),
  );
  return {
    status: response.status,
    body: await response.json(),
    calls,
    receivedDigest,
    digest: await sha(bytes),
  };
}
const envelope = (p: unknown = payload(), patch: Json = {}): Json => ({
  contract_version: 3,
  action: "archive_attempt",
  device_id: ID(1),
  request_id: ID(2),
  issued_at: TIME,
  payload: p,
  ...patch,
});
Deno.test("archive v3 real P256 exact byte signature permits revoked prior evidence only", async () => {
  const r = await exercise(envelope());
  assertEquals(r.status, 200);
  assertEquals(r.body.contract_version, 3);
  assertEquals(r.calls, [
    "gateway_device_key_v1",
    "gateway_archive_attempt_v3",
  ]);
  assertEquals(r.receivedDigest, r.digest);
  assertEquals(r.body.result.delivery_proven, false);
  assertEquals(r.body.result.send_authority, false);
});
for (
  const [name, bad] of [
    ["caller destination", { ...payload(), destination_e164: "+250788000001" }],
    ["fractional fence", { ...payload(), fence_version: 1.5 }],
    ["null references", { ...payload(), callback_requests: null }],
    ["duplicate request UUID", {
      ...payload(),
      callback_requests: [refs[0], refs[0]],
    }],
    ["odd callback set", { ...payload(), callback_requests: [refs[0]] }],
    ["client outcome", { ...payload(), delivery_proven: true }],
  ] as const
) {
  Deno.test(`archive v3 rejects ${name} before key lookup`, async () => {
    const r = await exercise(envelope(bad));
    assertEquals(r.status, 400);
    assertEquals(r.calls, []);
  });
}
for (const field of ["carrier_proof", "delivery_proven", "send_authority"]) {
  Deno.test(`archive v3 rejects invented ${field} on outbound result`, async () => {
    assertEquals(
      (await exercise(envelope(), { ...ack(), [field]: true })).status,
      502,
    );
  });
}
for (const field of ["body", "destination_e164", "balances", "service_key"]) {
  Deno.test(`archive v3 redacts unexpected ${field}`, async () => {
    const r = await exercise(envelope(), { ...ack(), [field]: "private" });
    assertEquals(r.status, 502);
    assertEquals(JSON.stringify(r.body).includes("private"), false);
  });
}
for (
  const patch of [
    { request_id: ID(50) },
    { device_id: ID(50) },
    { fence_version: 2 },
    { segment_count: 2 },
    { callback_requests: refs.slice().reverse() },
  ]
) {
  Deno.test(`archive v3 binds outbound ${Object.keys(patch)[0]}`, async () => {
    assertEquals(
      (await exercise(envelope(), { ...ack(), ...patch })).status,
      502,
    );
  });
}
Deno.test("archive v3 mutation tamper cannot become an ACK", async () => {
  assertEquals(
    (await exercise(envelope(), ack(), (b) => {
      const c = b.slice();
      c[c.length - 10] ^= 1;
      return c;
    })).status < 500,
    true,
  );
});
Deno.test("archive v3 old signed timestamp refuses before lookup", async () => {
  assertEquals(
    (await exercise(envelope(payload(), { issued_at: "2026-10-01T12:57:59Z" })))
      .status,
    400,
  );
});
Deno.test("archive v3 never adds grant action to new version", async () => {
  const r = await exercise(envelope({}, { action: "dispatch_grant" }));
  assertEquals(r.status, 400);
  assertEquals(r.calls, []);
});
Deno.test("archive v3 unknown original UUID lookup is truthful", async () => {
  const p = { target_request_id: ID(40) };
  const result = {
    target_request_id: ID(40),
    outcome: "unknown",
    recorded_result: null,
  };
  const r = await exercise(envelope(p, { action: "archive_lookup" }), result);
  assertEquals(r.status, 200);
  assertEquals(r.calls[1], "gateway_archive_lookup_v3");
});
Deno.test("archive v3 lookup cannot disclose mismatched original receipt", async () => {
  const r = await exercise(
    envelope({ target_request_id: ID(40) }, { action: "archive_lookup" }),
    { target_request_id: ID(40), outcome: "recorded", recorded_result: ack() },
  );
  assertEquals(r.status, 502);
});
Deno.test("archive v3 lookup target must differ from read identity", () => {
  assertEquals(
    archivePayload("archive_lookup", { target_request_id: ID(2) }, ID(2)),
    false,
  );
});
Deno.test("archive v3 refused evidence never exposes receipt or references", () => {
  const refusal = {
    ...ack(),
    ok: false,
    code: "CALLBACK_EVIDENCE_INCOMPLETE",
    archive_ack_id: null,
    receipt_id: null,
    callback_requests: null,
    evidence_kind: null,
  };
  assertEquals(
    archiveResult("archive_attempt", refusal, ID(1), ID(2), payload()),
    true,
  );
  assertEquals(
    archiveResult(
      "archive_attempt",
      { ...refusal, receipt_id: ID(4) },
      ID(1),
      ID(2),
      payload(),
    ),
    false,
  );
});

for (const name of ["ack", "lookup", "unknown", "incomplete"]) {
  Deno.test(`archive v3 actual synthetic SQL ${name} satisfies signed outbound boundary`, async () => {
    const observed = JSON.parse(
      await Deno.readTextFile(
        `contracts/collect-android-attempt-archive-v3/fixtures/observed-${name}.json`,
      ),
    );
    let e: Json;
    if (name === "lookup" || name === "unknown") {
      const device = observed.recorded_result?.device_id ?? ID(1);
      e = envelope({ target_request_id: observed.target_request_id }, {
        action: "archive_lookup",
        device_id: device,
      });
    } else {
      const refs = observed.callback_requests ?? payload().callback_requests;
      e = envelope({
        attempt_id: observed.attempt_id,
        fence_version: observed.fence_version,
        body_sha256: observed.body_sha256,
        destination_sha256: observed.destination_sha256,
        callback_requests: refs,
      }, { request_id: observed.request_id, device_id: observed.device_id });
    }
    const result = await exercise(e, observed);
    assertEquals(result.status, 200);
    assertEquals(result.body.result, observed);
  });
}

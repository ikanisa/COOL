import { assertEquals } from "../_shared/test_assert.ts";
import {
  createGatewayHandler,
  derToP1363,
  type GatewayDependencies,
} from "./handler.ts";
const DEVICE = "99750000-0000-4000-8000-000000000001";
const REQUEST = "99750000-0000-4000-8000-000000000002";
const TARGET = "99750000-0000-4000-8000-000000000003";
const CALLBACK = "99750000-0000-4000-8000-000000000004";
const NOW = Date.parse("2026-09-30T21:00:00Z");
const TIME = new Date(NOW).toISOString();
const encode = new TextEncoder();
const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
async function sha(bytes: Uint8Array) {
  return Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
    ),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
}
function der(raw: Uint8Array): Uint8Array {
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
const heartbeat = () => ({
  sms_permission: true,
  network: "validated",
  telephony: "ready",
  sim_selected: true,
  sim_revision_sha256: "a".repeat(64),
  local_pause: false,
  reported_at: TIME,
});
const callback = () => ({
  callback_id: CALLBACK,
  attempt_id: TARGET,
  fence_version: 1,
  segment_index: 0,
  segment_count: 1,
  body_sha256: "b".repeat(64),
  destination_sha256: "c".repeat(64),
  callback_kind: "sent",
  result_code: -1,
  tp_status: null,
  occurred_at: TIME,
});
function envelope(
  action = "heartbeat",
  payload: unknown = heartbeat(),
  patch: Record<string, unknown> = {},
) {
  return {
    contract_version: 1,
    action,
    device_id: DEVICE,
    request_id: REQUEST,
    issued_at: TIME,
    payload,
    ...patch,
  };
}
async function fixture(state = "pending") {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const spki = new Uint8Array(
    await crypto.subtle.exportKey("spki", pair.publicKey),
  );
  const id = await sha(spki);
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  let result: unknown = {
    observation_id: TARGET,
    ingested_at: TIME,
    replay: false,
    carrier_proof: false,
  };
  let error: { code?: string } | null = null;
  const deps: GatewayDependencies = {
    now: () => NOW,
    timeoutMs: 50,
    rpc: async (name, args) => {
      calls.push({ name, args });
      if (name === "gateway_device_key_v1") {
        return {
          data: {
            device_id: DEVICE,
            state,
            public_key_spki_base64: b64(spki),
            key_sha256: id,
            installation_id: TARGET,
            signing_certificate_sha256: "d".repeat(64),
          },
          error: null,
        };
      }
      return { data: result, error };
    },
  };
  async function signed(
    value: unknown = envelope(),
    text?: string,
    patch: Record<string, string> = {},
  ) {
    const bytes = encode.encode(text ?? JSON.stringify(value));
    const signature = der(
      new Uint8Array(
        await crypto.subtle.sign(
          { name: "ECDSA", hash: "SHA-256" },
          pair.privateKey,
          bytes,
        ),
      ),
    );
    return new Request("https://gateway.test/collect-android-gateway", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "X-Collect-Gateway-Key-Id": id,
        "X-Collect-Gateway-Signature": b64(signature),
        ...patch,
      },
      body: bytes,
    });
  }
  return {
    pair,
    spki,
    id,
    calls,
    deps,
    signed,
    handler: createGatewayHandler(deps),
    setResult: (value: unknown) => result = value,
    setError: (value: { code?: string } | null) => error = value,
  };
}
Deno.test("real synthetic P-256 DER signature accepts pending key-possession health and server request SHA", async () => {
  const f = await fixture();
  const env = envelope();
  const response = await f.handler(await f.signed(env));
  assertEquals(response.status, 200);
  const parsed = await response.json();
  assertEquals(parsed.action, "heartbeat");
  assertEquals(parsed.result.carrier_proof, false);
  assertEquals(f.calls.map((x) => x.name), [
    "gateway_device_key_v1",
    "gateway_heartbeat_v1",
  ]);
  assertEquals(
    f.calls[1].args.p_request_sha256,
    await sha(encode.encode(JSON.stringify(env))),
  );
  assertEquals(response.headers.get("cache-control"), "no-store");
});
Deno.test("tampered signed UTF8 body cannot reach a mutation RPC", async () => {
  const f = await fixture();
  const signed = await f.signed();
  const response = await f.handler(
    new Request(signed.url, {
      method: "POST",
      headers: signed.headers,
      body: JSON.stringify(
        envelope("heartbeat", { ...heartbeat(), local_pause: true }),
      ),
    }),
  );
  assertEquals(response.status, 401);
  assertEquals(f.calls.length, 1);
});
Deno.test("different generated private key cannot authorize enrolled identity", async () => {
  const f = await fixture();
  const other = await fixture();
  const request = await other.signed(undefined, undefined, {
    "X-Collect-Gateway-Key-Id": f.id,
  });
  const response = await f.handler(request);
  assertEquals(response.status, 401);
  assertEquals(f.calls.length, 1);
});
Deno.test("wrong public-key header and malformed DER fail closed", async () => {
  const f = await fixture();
  assertEquals(
    (await f.handler(
      await f.signed(undefined, undefined, {
        "X-Collect-Gateway-Key-Id": "f".repeat(64),
      }),
    )).status,
    401,
  );
  assertEquals(
    (await f.handler(
      await f.signed(undefined, undefined, {
        "X-Collect-Gateway-Signature": b64(
          Uint8Array.from([48, 6, 2, 1, 0, 2, 1, 1]),
        ),
      }),
    )).status,
    400,
  );
  assertEquals(f.calls.length, 1);
});
Deno.test("canonical DER roundtrip and nonminimal integers are enforced", async () => {
  const f = await fixture();
  const raw = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      f.pair.privateKey,
      encode.encode("synthetic"),
    ),
  );
  assertEquals(Array.from(derToP1363(der(raw))), Array.from(raw));
  let refused = false;
  try {
    derToP1363(Uint8Array.from([48, 7, 2, 2, 0, 1, 2, 1, 1]));
  } catch {
    refused = true;
  }
  assertEquals(refused, true);
});
for (
  const [name, value] of [
    [
      "expired",
      envelope("heartbeat", heartbeat(), {
        issued_at: new Date(NOW - 120001).toISOString(),
      }),
    ],
    [
      "future",
      envelope("heartbeat", heartbeat(), {
        issued_at: new Date(NOW + 120001).toISOString(),
      }),
    ],
    [
      "invalid calendar",
      envelope("heartbeat", heartbeat(), { issued_at: "2026-02-31T21:00:00Z" }),
    ],
    ["unknown action", envelope("enroll", {})],
    [
      "wrong version",
      envelope("heartbeat", heartbeat(), { contract_version: 2 }),
    ],
    ["bad UUID", envelope("heartbeat", heartbeat(), { device_id: "unsafe" })],
    [
      "extra envelope",
      envelope("heartbeat", heartbeat(), { message_body: "private" }),
    ],
    [
      "permission string",
      envelope("heartbeat", { ...heartbeat(), sms_permission: "true" }),
    ],
    [
      "extra health field",
      envelope("heartbeat", { ...heartbeat(), destination: "private" }),
    ],
    [
      "null SIM revision selected",
      envelope("heartbeat", { ...heartbeat(), sim_revision_sha256: null }),
    ],
    [
      "unselected SIM with revision",
      envelope("heartbeat", { ...heartbeat(), sim_selected: false }),
    ],
    [
      "invalid network",
      envelope("heartbeat", { ...heartbeat(), network: "online" }),
    ],
    [
      "unsupported callback conclusion",
      envelope("callback", { ...callback(), delivered: true }),
    ],
    [
      "fractional segment",
      envelope("callback", { ...callback(), segment_index: 0.5 }),
    ],
    [
      "oversized segment count",
      envelope("callback", { ...callback(), segment_count: 11 }),
    ],
    [
      "segment beyond count",
      envelope("callback", { ...callback(), segment_index: 1 }),
    ],
    [
      "reused callback request UUID",
      envelope("callback", { ...callback(), callback_id: REQUEST }),
    ],
    [
      "callback result boolean",
      envelope("callback", { ...callback(), result_code: true }),
    ],
    [
      "callback TP overflow",
      envelope("callback", { ...callback(), tp_status: 256 }),
    ],
    [
      "grant with client body",
      envelope("dispatch_grant", { message_body: "private" }),
    ],
    [
      "reconcile invalid target",
      envelope("reconcile", { target_request_id: null }),
    ],
  ] as const
) {
  Deno.test("strict envelope/payload refuses " + name, async () => {
    const f = await fixture();
    assertEquals((await f.handler(await f.signed(value))).status, 400);
    assertEquals(f.calls.length, 0);
  });
}
Deno.test("duplicate JSON keys rejected before signature-authorized RPC", async () => {
  const f = await fixture();
  const text = JSON.stringify(envelope()).replace(
    '"contract_version":1',
    '"contract_version":1,"contract_version":1',
  );
  assertEquals((await f.handler(await f.signed(undefined, text))).status, 400);
  assertEquals(f.calls.length, 0);
});
Deno.test("signed Unicode tamper verifies exact bytes rather than reserialized JSON", async () => {
  const f = await fixture();
  const text = JSON.stringify(envelope()).replace(
    '"network":"validated"',
    '"network":"valid\\u0061ted"',
  );
  const response = await f.handler(await f.signed(undefined, text));
  assertEquals(response.status, 200);
  assertEquals(
    f.calls[1].args.p_request_sha256,
    await sha(encode.encode(text)),
  );
});
Deno.test("POST-only and oversized/invalid UTF8 bodies reach no RPC", async () => {
  const f = await fixture();
  assertEquals(
    (await f.handler(new Request("https://gateway.test", { method: "GET" })))
      .status,
    405,
  );
  assertEquals(
    (await f.handler(
      new Request("https://gateway.test", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: " ".repeat(8193),
      }),
    )).status,
    413,
  );
  assertEquals(
    (await f.handler(
      new Request("https://gateway.test", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: Uint8Array.from([255]),
      }),
    )).status,
    400,
  );
  assertEquals(f.calls.length, 0);
});
Deno.test("revoked key permits only bounded reconciliation and prior-arm callback routes", async () => {
  const f = await fixture("revoked");
  assertEquals((await f.handler(await f.signed())).status, 403);
  assertEquals(f.calls.length, 1);
  f.setResult({
    target_request_id: TARGET,
    outcome: "unknown",
    recorded_action: null,
    recorded_result: null,
  });
  assertEquals(
    (await f.handler(
      await f.signed(envelope("reconcile", { target_request_id: TARGET })),
    )).status,
    200,
  );
  f.setResult({
    callback_id: CALLBACK,
    recorded_at: TIME,
    replay: false,
    carrier_proof: false,
  });
  assertEquals(
    (await f.handler(await f.signed(envelope("callback", callback())))).status,
    200,
  );
  f.setError({ code: "42501" });
  assertEquals(
    (await f.handler(await f.signed(envelope("callback", callback())))).status,
    403,
  );
});
Deno.test("dispatch is stable authority-pending refusal with no body destination or grant", async () => {
  const f = await fixture("active");
  f.setResult({
    ok: false,
    code: "GATEWAY_DISPATCH_AUTHORITY_PENDING",
    device_id: DEVICE,
    request_id: REQUEST,
    replay: false,
  });
  const response = await f.handler(
    await f.signed(envelope("dispatch_grant", {})),
  );
  assertEquals(response.status, 200);
  assertEquals(Object.keys((await response.json()).result).sort(), [
    "code",
    "device_id",
    "ok",
    "replay",
    "request_id",
  ]);
});
Deno.test("stored request reconciliation validates nested bounded result rather than leaking extra keys", async () => {
  const f = await fixture();
  f.setResult({
    target_request_id: TARGET,
    outcome: "recorded",
    recorded_action: "dispatch_grant",
    recorded_result: {
      ok: false,
      code: "GATEWAY_DISPATCH_AUTHORITY_PENDING",
      device_id: DEVICE,
      request_id: TARGET,
      replay: false,
    },
  });
  assertEquals(
    (await f.handler(
      await f.signed(envelope("reconcile", { target_request_id: TARGET })),
    )).status,
    200,
  );
  f.setResult({
    target_request_id: TARGET,
    outcome: "recorded",
    recorded_action: "callback",
    recorded_result: {
      callback_id: CALLBACK,
      recorded_at: TIME,
      replay: false,
      carrier_proof: false,
      message_body: "private",
    },
  });
  const response = await f.handler(
    await f.signed(envelope("reconcile", { target_request_id: TARGET })),
  );
  assertEquals(response.status, 502);
  assertEquals(
    await response.text(),
    '{"ok":false,"code":"GATEWAY_OUTCOME_UNKNOWN"}',
  );
});
Deno.test("malformed success provider diagnostics and deadline return safe unknown without retry", async () => {
  const f = await fixture();
  f.setResult({
    observation_id: TARGET,
    ingested_at: TIME,
    replay: false,
    carrier_proof: false,
    destination: "private",
  });
  assertEquals((await f.handler(await f.signed())).status, 502);
  f.setError({ code: "XX000" });
  assertEquals((await f.handler(await f.signed())).status, 503);
  const old = f.deps.rpc;
  f.deps.rpc = (name, args, signal) =>
    name === "gateway_device_key_v1"
      ? old(name, args, signal)
      : new Promise(() => {});
  const response = await f.handler(await f.signed());
  assertEquals(response.status, 504);
  assertEquals((await response.json()).code, "GATEWAY_OUTCOME_UNKNOWN");
  assertEquals(
    f.calls.filter((c) => c.name === "gateway_heartbeat_v1").length,
    2,
  );
});
Deno.test("exact replay returns original observation rather than a second mutation route", async () => {
  const f = await fixture();
  const request = await f.signed();
  assertEquals((await f.handler(request)).status, 200);
  f.setResult({
    observation_id: TARGET,
    ingested_at: TIME,
    replay: true,
    carrier_proof: false,
  });
  const response = await f.handler(await f.signed());
  assertEquals(response.status, 200);
  assertEquals((await response.json()).result.replay, true);
});
Deno.test("slow body reader is bounded and cannot reach any service RPC", async () => {
  const f = await fixture();
  let canceled = false;
  const stream = new ReadableStream<Uint8Array>({
    cancel() {
      canceled = true;
    },
  });
  const request = new Request("https://gateway.test", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: stream,
  });
  const response = await f.handler(request);
  assertEquals(response.status >= 400, true);
  assertEquals(f.calls.length, 0);
  assertEquals(canceled, true);
});
Deno.test("malformed large service success stays outcome-unknown and redacted", async () => {
  const f = await fixture();
  f.setResult({ private_body: "private".repeat(2000) });
  const response = await f.handler(await f.signed());
  assertEquals(response.status, 502);
  assertEquals(
    await response.text(),
    '{"ok":false,"code":"GATEWAY_OUTCOME_UNKNOWN"}',
  );
});

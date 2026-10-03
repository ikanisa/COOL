import { assertEquals } from "../_shared/test_assert.ts";
import { createGatewayHandler, type GatewayDependencies } from "./handler.ts";

type Json = Record<string, unknown>;
const DEVICE = "aa750000-0000-4000-8000-000000000001";
const REQUEST = "aa750000-0000-4000-8000-000000000002";
const ATTEMPT = "aa750000-0000-4000-8000-000000000003";
const RECEIPT = "aa750000-0000-4000-8000-000000000004";
const RUN = "aa750000-0000-4000-8000-000000000005";
const CALLBACK = "aa750000-0000-4000-8000-000000000006";
const DELIVERY = "aa750000-0000-4000-8000-000000000007";
const TARGET = "aa750000-0000-4000-8000-000000000008";
const SECOND_SENT = "aa750000-0000-4000-8000-000000000009";
const SECOND_DELIVERY = "aa750000-0000-4000-8000-000000000010";
const NOW = Date.parse("2026-10-01T12:00:00Z");
const TIME = new Date(NOW).toISOString();
const EXPIRY = new Date(NOW + 30000).toISOString();
const ENCODER = new TextEncoder();
const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));

async function sha(value: string | Uint8Array): Promise<string> {
  const bytes = typeof value === "string" ? ENCODER.encode(value) : value;
  return Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
    ),
    (byte) => byte.toString(16).padStart(2, "0"),
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
function envelope(action: string, payload: unknown, patch: Json = {}): Json {
  return {
    contract_version: 2,
    action,
    device_id: DEVICE,
    request_id: REQUEST,
    issued_at: TIME,
    payload,
    ...patch,
  };
}
function arm(patch: Json = {}): Json {
  return {
    attempt_id: ATTEMPT,
    fence_version: 7,
    body_sha256: "b".repeat(64),
    destination_sha256: "c".repeat(64),
    callbacks: [{
      segment_index: 0,
      sent_callback_id: CALLBACK,
      delivery_callback_id: DELIVERY,
    }],
    reservation_sha256: "d".repeat(64),
    ...patch,
  };
}
function callback(patch: Json = {}): Json {
  return {
    callback_id: CALLBACK,
    attempt_id: ATTEMPT,
    fence_version: 7,
    segment_index: 0,
    segment_count: 1,
    body_sha256: "b".repeat(64),
    destination_sha256: "c".repeat(64),
    callback_kind: "sent",
    result_code: -1,
    tp_status: null,
    occurred_at: TIME,
    ...patch,
  };
}
async function grant(patch: Json = {}): Promise<Json> {
  const body = "BuriMunsi: Ubwizigame bwa 100 RWF bwanditswe.";
  const destination = "+250788000001";
  return {
    ok: true,
    code: "DISPATCH_GRANTED",
    device_id: DEVICE,
    request_id: REQUEST,
    attempt_id: ATTEMPT,
    receipt_id: RECEIPT,
    run_id: RUN,
    fence_version: 7,
    policy_revision: 8,
    issued_at: TIME,
    expires_at: EXPIRY,
    segment_count: 1,
    body,
    destination_e164: destination,
    body_sha256: await sha(body),
    destination_sha256: await sha(destination),
    sim_revision_sha256: "e".repeat(64),
    replay: false,
    ...patch,
  };
}
function armed(patch: Json = {}): Json {
  return {
    ok: true,
    code: "DISPATCH_ARMED",
    device_id: DEVICE,
    request_id: REQUEST,
    attempt_id: ATTEMPT,
    fence_version: 7,
    reservation_sha256: "d".repeat(64),
    armed_at: TIME,
    expires_at: EXPIRY,
    replay: false,
    carrier_proof: false,
    ...patch,
  };
}
function observed(patch: Json = {}): Json {
  return {
    callback_id: CALLBACK,
    recorded_at: TIME,
    replay: false,
    carrier_proof: false,
    state: "observed_sent",
    sent_observations: 1,
    delivery_observations: 0,
    conflicting_observations: false,
    ...patch,
  };
}
function status(patch: Json = {}): Json {
  return {
    attempt_id: ATTEMPT,
    fence_version: 7,
    state: "observed_sent",
    armed_at: TIME,
    segment_count: 1,
    sent_observations: 1,
    delivery_observations: 0,
    conflicting_observations: false,
    terminal_archive_ack: false,
    carrier_proof: false,
    ...patch,
  };
}
function refusal(code = "ORIGINAL_REQUEST_RECORDED", patch: Json = {}): Json {
  return {
    ok: false,
    code,
    device_id: DEVICE,
    request_id: REQUEST,
    replay: true,
    ...patch,
  };
}
async function fixture(state = "active") {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const spki = new Uint8Array(
    await crypto.subtle.exportKey("spki", pair.publicKey),
  );
  const keyId = await sha(spki);
  const calls: { name: string; args: Json }[] = [];
  let result: unknown = refusal();
  let error: { code?: string } | null = null;
  const deps: GatewayDependencies = {
    now: () => NOW,
    timeoutMs: 50,
    rpc: (name, args) => {
      calls.push({ name, args });
      if (name === "gateway_device_key_v1") {
        return Promise.resolve({
          data: {
            device_id: DEVICE,
            state,
            public_key_spki_base64: b64(spki),
            key_sha256: keyId,
            installation_id: RUN,
            signing_certificate_sha256: "f".repeat(64),
          },
          error: null,
        });
      }
      return Promise.resolve({ data: result, error });
    },
  };
  async function signed(value: Json, text = JSON.stringify(value)) {
    const bytes = ENCODER.encode(text);
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
        "X-Collect-Gateway-Key-Id": keyId,
        "X-Collect-Gateway-Signature": b64(signature),
      },
      body: bytes,
    });
  }
  return {
    calls,
    deps,
    signed,
    handler: createGatewayHandler(deps),
    setResult: (data: unknown) => result = data,
    setError: (value: { code?: string } | null) => error = value,
  };
}

for (
  const [action, payload, rpc, result] of [
    ["dispatch_grant", {}, "gateway_dispatch_grant_v2", await grant()],
    ["arm_dispatch", arm(), "gateway_arm_dispatch_v2", armed()],
    ["callback", callback(), "gateway_callback_v2", observed()],
    [
      "attempt_status",
      { attempt_id: ATTEMPT, fence_version: 7 },
      "gateway_attempt_status_v2",
      status(),
    ],
    ["reconcile", { target_request_id: TARGET }, "gateway_reconcile_v2", {
      target_request_id: TARGET,
      outcome: "unknown",
      recorded_action: null,
      recorded_result: null,
    }],
  ] as const
) {
  Deno.test("v2 real P-256 signature selects exactly " + rpc, async () => {
    const f = await fixture();
    f.setResult(result);
    const env = envelope(action, payload);
    const response = await f.handler(await f.signed(env));
    assertEquals(response.status, 200);
    assertEquals(f.calls.map((call) => call.name), [
      "gateway_device_key_v1",
      rpc,
    ]);
    assertEquals(Object.keys(f.calls[1].args).sort(), [
      "p_device_id",
      "p_payload",
      "p_request_id",
      "p_request_sha256",
    ]);
    assertEquals(f.calls[1].args.p_payload, payload);
    assertEquals(
      f.calls[1].args.p_request_sha256,
      await sha(JSON.stringify(env)),
    );
    const parsed = await response.json();
    assertEquals(parsed.contract_version, 2);
    assertEquals(parsed.result, result);
    assertEquals(response.headers.get("cache-control"), "no-store");
  });
}

for (
  const [name, action, payload, patch] of [
    ["v2 heartbeat", "heartbeat", {}, {}],
    ["v1 arm", "arm_dispatch", arm(), { contract_version: 1 }],
    ["v1 status", "attempt_status", { attempt_id: ATTEMPT, fence_version: 7 }, {
      contract_version: 1,
    }],
    ["caller grant body", "dispatch_grant", { body: "private" }, {}],
    [
      "caller arm destination",
      "arm_dispatch",
      arm({ destination_e164: "+250788000001" }),
      {},
    ],
    ["missing reservation", "arm_dispatch", {
      ...arm(),
      reservation_sha256: undefined,
    }, {}],
    [
      "uppercase reservation hash",
      "arm_dispatch",
      arm({ reservation_sha256: "A".repeat(64) }),
      {},
    ],
    ["zero fence", "arm_dispatch", arm({ fence_version: 0 }), {}],
    ["fractional fence", "attempt_status", {
      attempt_id: ATTEMPT,
      fence_version: 0.5,
    }, {}],
    ["status extra fields", "attempt_status", {
      attempt_id: ATTEMPT,
      fence_version: 7,
      body: "private",
    }, {}],
    ["empty callbacks", "arm_dispatch", arm({ callbacks: [] }), {}],
    [
      "noncontiguous callbacks",
      "arm_dispatch",
      arm({
        callbacks: [{
          segment_index: 1,
          sent_callback_id: CALLBACK,
          delivery_callback_id: DELIVERY,
        }],
      }),
      {},
    ],
    [
      "fractional segment index",
      "arm_dispatch",
      arm({
        callbacks: [{
          segment_index: 0.1,
          sent_callback_id: CALLBACK,
          delivery_callback_id: DELIVERY,
        }],
      }),
      {},
    ],
    [
      "callback extra field",
      "arm_dispatch",
      arm({
        callbacks: [{
          segment_index: 0,
          sent_callback_id: CALLBACK,
          delivery_callback_id: DELIVERY,
          body: "private",
        }],
      }),
      {},
    ],
    [
      "same sent and delivery UUID",
      "arm_dispatch",
      arm({
        callbacks: [{
          segment_index: 0,
          sent_callback_id: CALLBACK,
          delivery_callback_id: CALLBACK.toUpperCase(),
        }],
      }),
      {},
    ],
    [
      "callback UUID equals request",
      "arm_dispatch",
      arm({
        callbacks: [{
          segment_index: 0,
          sent_callback_id: REQUEST.toUpperCase(),
          delivery_callback_id: DELIVERY,
        }],
      }),
      {},
    ],
    [
      "callback UUID equals attempt",
      "arm_dispatch",
      arm({
        callbacks: [{
          segment_index: 0,
          sent_callback_id: CALLBACK,
          delivery_callback_id: ATTEMPT.toUpperCase(),
        }],
      }),
      {},
    ],
    [
      "duplicate cross-segment UUID",
      "arm_dispatch",
      arm({
        callbacks: [
          {
            segment_index: 0,
            sent_callback_id: CALLBACK,
            delivery_callback_id: DELIVERY,
          },
          {
            segment_index: 1,
            sent_callback_id: SECOND_SENT,
            delivery_callback_id: CALLBACK.toUpperCase(),
          },
        ],
      }),
      {},
    ],
    [
      "callback request UUID case reuse",
      "callback",
      callback({ callback_id: REQUEST.toUpperCase() }),
      {},
    ],
  ] as const
) {
  Deno.test("v2 rejects " + name + " before key lookup", async () => {
    const f = await fixture();
    assertEquals(
      (await f.handler(await f.signed(envelope(action, payload, patch))))
        .status,
      400,
    );
    assertEquals(f.calls.length, 0);
  });
}

Deno.test("v2 valid multipart plan binds distinct sent and delivery callback IDs", async () => {
  const f = await fixture();
  f.setResult(armed());
  const p = arm({
    callbacks: [
      {
        segment_index: 0,
        sent_callback_id: CALLBACK,
        delivery_callback_id: DELIVERY,
      },
      {
        segment_index: 1,
        sent_callback_id: SECOND_SENT,
        delivery_callback_id: SECOND_DELIVERY,
      },
    ],
  });
  assertEquals(
    (await f.handler(await f.signed(envelope("arm_dispatch", p)))).status,
    200,
  );
  assertEquals(f.calls[1].args.p_payload, p);
});

Deno.test("v2 UUID normalization preserves signed bytes and exact identity binding", async () => {
  const f = await fixture();
  f.setResult(armed());
  const p = arm({ attempt_id: ATTEMPT.toUpperCase() });
  const env = envelope("arm_dispatch", p, {
    device_id: DEVICE.toUpperCase(),
    request_id: REQUEST.toUpperCase(),
  });
  assertEquals((await f.handler(await f.signed(env))).status, 200);
  assertEquals(
    f.calls[1].args.p_request_sha256,
    await sha(JSON.stringify(env)),
  );
});

Deno.test("v2 signature covers version and exact payload bytes", async () => {
  const f = await fixture();
  const original = envelope("dispatch_grant", {});
  const request = await f.signed(original);
  const tampered = new Request(request.url, {
    method: "POST",
    headers: request.headers,
    body: JSON.stringify({ ...original, contract_version: 1 }),
  });
  assertEquals((await f.handler(tampered)).status, 401);
  assertEquals(f.calls.map((call) => call.name), ["gateway_device_key_v1"]);
});

Deno.test("v2 duplicate arm nested JSON keys fail before signature RPC", async () => {
  const f = await fixture();
  const env = envelope("arm_dispatch", arm());
  const text = JSON.stringify(env).replace(
    '"segment_index":0',
    '"segment_index":0,"segment_index":0',
  );
  assertEquals((await f.handler(await f.signed(env, text))).status, 400);
  assertEquals(f.calls.length, 0);
});

for (const action of ["dispatch_grant", "arm_dispatch"] as const) {
  Deno.test(
    "v2 revoked device refuses " + action + " before mutation",
    async () => {
      const f = await fixture("revoked");
      assertEquals(
        (await f.handler(
          await f.signed(
            envelope(action, action === "dispatch_grant" ? {} : arm()),
          ),
        )).status,
        403,
      );
      assertEquals(f.calls.map((call) => call.name), ["gateway_device_key_v1"]);
    },
  );
}
for (
  const [action, payload, result] of [
    ["callback", callback(), observed()],
    ["attempt_status", { attempt_id: ATTEMPT, fence_version: 7 }, status()],
    ["reconcile", { target_request_id: TARGET }, {
      target_request_id: TARGET,
      outcome: "unknown",
      recorded_action: null,
      recorded_result: null,
    }],
  ] as const
) {
  Deno.test(
    "v2 revoked identity may reconcile earlier " + action + " evidence",
    async () => {
      const f = await fixture("revoked");
      f.setResult(result);
      assertEquals(
        (await f.handler(await f.signed(envelope(action, payload)))).status,
        200,
      );
      f.setError({ code: "42501" });
      assertEquals(
        (await f.handler(await f.signed(envelope(action, payload)))).status,
        403,
      );
    },
  );
}

for (
  const [name, patch] of [
    ["body digest mismatch", { body_sha256: "0".repeat(64) }],
    ["destination digest mismatch", { destination_sha256: "0".repeat(64) }],
    ["grant body mutation", { body: "A different canonical receipt" }],
    ["foreign destination", { destination_e164: "+256788000001" }],
    ["body beyond character limit", { body: "x".repeat(1001) }],
    ["lease over thirty seconds", {
      expires_at: new Date(NOW + 30001).toISOString(),
    }],
    ["expired authority", {
      issued_at: new Date(NOW - 30001).toISOString(),
      expires_at: TIME,
    }],
    ["grant replay authority", { replay: true }],
    ["wrong result request", { request_id: TARGET }],
    ["extra private key", { private_key: "private" }],
  ] as const
) {
  Deno.test("v2 malformed grant stays redacted: " + name, async () => {
    const f = await fixture();
    f.setResult(await grant(patch));
    const response = await f.handler(
      await f.signed(envelope("dispatch_grant", {})),
    );
    assertEquals(response.status, 502);
    assertEquals(
      await response.text(),
      '{"ok":false,"code":"GATEWAY_OUTCOME_UNKNOWN"}',
    );
  });
}

Deno.test("v2 grant hashes full UTF8 body including supplementary Unicode", async () => {
  const f = await fixture();
  const body = "😀".repeat(1000);
  f.setResult(
    await grant({ body, body_sha256: await sha(body), segment_count: 10 }),
  );
  assertEquals(
    (await f.handler(await f.signed(envelope("dispatch_grant", {})))).status,
    200,
  );
});

for (
  const [name, patch] of [
    ["arm replay authority", { replay: true }],
    ["wrong arm attempt", { attempt_id: TARGET }],
    ["wrong arm fence", { fence_version: 8 }],
    ["wrong reservation", { reservation_sha256: "0".repeat(64) }],
    ["arm carrier delivery claim", { carrier_proof: true }],
    ["arm recovered body", { body: "private" }],
    ["arm lease over thirty seconds", {
      expires_at: new Date(NOW + 30001).toISOString(),
    }],
  ] as const
) {
  Deno.test("v2 malformed arm refuses " + name, async () => {
    const f = await fixture();
    f.setResult(armed(patch));
    assertEquals(
      (await f.handler(await f.signed(envelope("arm_dispatch", arm())))).status,
      502,
    );
  });
}

for (
  const code of [
    "OPERATIONS_PAUSED",
    "NO_CURRENT_RUN",
    "DEVICE_NOT_READY",
    "NO_ELIGIBLE_RECEIPT",
    "QUOTA_EXHAUSTED",
    "ORIGINAL_REQUEST_RECORDED",
  ]
) {
  Deno.test("v2 exact bounded dispatch refusal accepts " + code, async () => {
    const f = await fixture();
    f.setResult(refusal(code));
    assertEquals(
      (await f.handler(await f.signed(envelope("dispatch_grant", {})))).status,
      200,
    );
  });
}

for (const action of ["dispatch_grant", "arm_dispatch"] as const) {
  Deno.test(
    "v2 original " + action +
      " lookup stays redacted and cannot recover authority",
    async () => {
      const f = await fixture();
      const p = { target_request_id: TARGET };
      const result = {
        target_request_id: TARGET,
        outcome: "recorded",
        recorded_action: action,
        recorded_result: refusal("ORIGINAL_REQUEST_RECORDED", {
          request_id: TARGET,
        }),
      };
      f.setResult(result);
      assertEquals(
        (await f.handler(await f.signed(envelope("reconcile", p)))).status,
        200,
      );
      f.setResult({
        ...result,
        recorded_result: action === "dispatch_grant"
          ? await grant({ request_id: TARGET })
          : armed({ request_id: TARGET }),
      });
      const response = await f.handler(
        await f.signed(envelope("reconcile", p)),
      );
      assertEquals(response.status, 502);
      assertEquals(
        await response.text(),
        '{"ok":false,"code":"GATEWAY_OUTCOME_UNKNOWN"}',
      );
    },
  );
}

Deno.test("v2 lookup accepts recorded callback and attempt status, rejects nested extras", async () => {
  const f = await fixture();
  for (
    const [action, result] of [["callback", observed()], [
      "attempt_status",
      status(),
    ]] as const
  ) {
    const base = {
      target_request_id: TARGET,
      outcome: "recorded",
      recorded_action: action,
      recorded_result: result,
    };
    f.setResult(base);
    assertEquals(
      (await f.handler(
        await f.signed(envelope("reconcile", { target_request_id: TARGET })),
      )).status,
      200,
    );
    f.setResult({ ...base, recorded_result: { ...result, body: "private" } });
    assertEquals(
      (await f.handler(
        await f.signed(envelope("reconcile", { target_request_id: TARGET })),
      )).status,
      502,
    );
  }
});

Deno.test("v2 sent success requires every planned observation and no conflicts", async () => {
  const f = await fixture();
  f.setResult(observed({ sent_observations: 1 }));
  const p = callback({ segment_count: 2 });
  assertEquals(
    (await f.handler(await f.signed(envelope("callback", p)))).status,
    502,
  );
  f.setResult(observed({ sent_observations: 2 }));
  assertEquals(
    (await f.handler(await f.signed(envelope("callback", p)))).status,
    200,
  );
  f.setResult(
    observed({ sent_observations: 2, conflicting_observations: true }),
  );
  assertEquals(
    (await f.handler(await f.signed(envelope("callback", p)))).status,
    502,
  );
  f.setResult(
    observed({
      state: "uncertain",
      sent_observations: 1,
      conflicting_observations: true,
    }),
  );
  assertEquals(
    (await f.handler(await f.signed(envelope("callback", p)))).status,
    200,
  );
});

Deno.test("v2 status binds exact attempt fence and forbids fabricated archive or delivery conclusions", async () => {
  const f = await fixture();
  const p = { attempt_id: ATTEMPT, fence_version: 7 };
  for (
    const patch of [
      { attempt_id: TARGET },
      { fence_version: 8 },
      { terminal_archive_ack: true },
      { carrier_proof: true },
      { segment_count: 2, sent_observations: 1 },
      { delivery_observations: 2 },
      { conflicting_observations: true },
    ]
  ) {
    f.setResult(status(patch));
    assertEquals(
      (await f.handler(await f.signed(envelope("attempt_status", p)))).status,
      502,
    );
  }
  f.setResult(
    status({ state: "granted", armed_at: null, sent_observations: 0 }),
  );
  assertEquals(
    (await f.handler(await f.signed(envelope("attempt_status", p)))).status,
    200,
  );
});

Deno.test("v2 unknown service outcome preserves request and performs no automatic retry", async () => {
  const f = await fixture();
  const original = f.deps.rpc;
  f.deps.rpc = (name, args, signal) => {
    if (name === "gateway_device_key_v1") return original(name, args, signal);
    f.calls.push({ name, args });
    return new Promise(() => {});
  };
  const response = await f.handler(
    await f.signed(envelope("arm_dispatch", arm())),
  );
  assertEquals(response.status, 504);
  assertEquals(
    await response.text(),
    '{"ok":false,"code":"GATEWAY_OUTCOME_UNKNOWN"}',
  );
  assertEquals(f.calls.map((call) => call.name), [
    "gateway_device_key_v1",
    "gateway_arm_dispatch_v2",
  ]);
  assertEquals(f.calls[1].args.p_request_id, REQUEST);
});

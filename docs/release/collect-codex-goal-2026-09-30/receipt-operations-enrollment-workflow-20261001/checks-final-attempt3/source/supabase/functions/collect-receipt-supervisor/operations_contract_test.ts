import {
  createSupervisorHandler,
  type SupervisorDependencies,
} from "./handler.ts";
import {
  validateOperationPayload,
  validateOperationResult,
} from "./operations_contract.ts";
const PRINCIPAL = "99910000-0000-4000-8000-000000000001",
  REQUEST = "99910000-0000-4000-8000-000000000002",
  RUN = "99910000-0000-4000-8000-000000000003",
  EVENT = "99910000-0000-4000-8000-000000000004",
  RECEIPT = "99910000-0000-4000-8000-000000000005";
const NOW = Date.parse("2026-10-01T12:00:00Z"),
  TIME = new Date(NOW).toISOString(),
  EXPIRY = new Date(NOW + 86400000).toISOString();
const audience = "collect.receipt-supervisor.v2/lhbowpbcpwoiparwnwgt";
const base = (action: string, request = REQUEST) => ({
  contract_version: 2,
  principal_id: PRINCIPAL,
  request_id: request,
  action,
  observed_at: TIME,
});
const begin = () => ({
  ...base("begin_run"),
  ok: true,
  code: "RUN_STARTED",
  run_id: RUN,
  fence_version: 1,
  mode: "Live-limited",
  expires_at: new Date(NOW + 120000).toISOString(),
});
const fence = { run_id: RUN, fence_version: 1 };
const ensurePayload = { ...fence, event_id: EVENT, expected_source_version: 1 };
const ensure = () => ({
  ...base("ensure_receipt"),
  ...fence,
  event_id: EVENT,
  source_version: 1,
  ok: true,
  code: "RECEIPT_EXISTS",
  business_handled: true,
  receipt_id: RECEIPT,
});
const bytes = (v: unknown) => new TextEncoder().encode(JSON.stringify(v));
const b64 = (b: Uint8Array) => btoa(String.fromCharCode(...b));
function assert(v: unknown): asserts v {
  if (!v) throw Error("assertion_failed");
}
function equal(a: unknown, b: unknown) {
  assert(JSON.stringify(a) === JSON.stringify(b));
}
function der(raw: Uint8Array) {
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
async function fixture(state = "active") {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const spki = new Uint8Array(
    await crypto.subtle.exportKey("spki", pair.publicKey),
  );
  const hash = Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(spki))),
    (v) => v.toString(16).padStart(2, "0"),
  ).join("");
  let key: unknown = {
    contract_version: 1,
    principal_id: PRINCIPAL,
    state,
    scope: "rw_receipt_operations",
    public_key_spki_base64: b64(spki),
    key_sha256: hash,
    expires_at: EXPIRY,
  };
  let result: unknown = begin();
  let err: string | null = null;
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const deps: SupervisorDependencies = {
    now: () => NOW,
    rpc: async (name, args) => {
      calls.push({ name, args });
      return name === "receipt_supervisor_key_v1"
        ? { data: key, error: null }
        : { data: result, error: err ? { code: err } : null };
    },
  };
  const handler = createSupervisorHandler(deps);
  async function invoke(
    action = "begin_run",
    payload: unknown = {},
    patch: Record<string, unknown> = {},
  ) {
    const body = bytes({
      contract_version: 2,
      audience,
      action,
      principal_id: PRINCIPAL,
      request_id: REQUEST,
      issued_at: TIME,
      payload,
      ...patch,
    });
    const signature = der(
      new Uint8Array(
        await crypto.subtle.sign(
          { name: "ECDSA", hash: "SHA-256" },
          pair.privateKey,
          new Uint8Array(body),
        ),
      ),
    );
    return await handler(
      new Request("https://example.invalid/collect-receipt-supervisor", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "X-Collect-Supervisor-Key-Id": hash,
          "X-Collect-Supervisor-Signature": b64(signature),
        },
        body,
      }),
    );
  }
  return {
    invoke,
    calls,
    setResult: (v: unknown) => result = v,
    setKey: (v: unknown) => key = v,
    key: () => key,
    setError: (v: string) => err = v,
  };
}
Deno.test("real v2 P256 envelope binds business authority to exact service RPC", async () => {
  const f = await fixture();
  const response = await f.invoke();
  equal(response.status, 200);
  equal(f.calls.map((c) => c.name), [
    "receipt_supervisor_key_v1",
    "receipt_operations_execute_v2",
  ]);
  equal(f.calls[1].args.p_action, "begin_run");
  equal(f.calls[1].args.p_payload, {});
  equal((await response.json()).contract_version, 2);
});
Deno.test("v2 cannot borrow old Shadow key scope", async () => {
  const f = await fixture();
  f.setKey({
    ...f.key() as Record<string, unknown>,
    scope: "rw_receipt_shadow",
  });
  equal((await f.invoke()).status, 401);
  equal(f.calls.length, 1);
});
Deno.test("pending operations identity can prove possession but cannot start", async () => {
  const f = await fixture("pending");
  f.setResult({
    ...base("prove_key"),
    expires_at: EXPIRY,
    scope: "rw_receipt_operations",
    business_handled: false,
    financial_action: false,
    send_action: false,
  });
  equal((await f.invoke("prove_key")).status, 200);
  equal((await f.invoke()).status, 403);
});
for (
  const [name, payload] of Object.entries({
    extra: { ...ensurePayload, body: "untrusted" },
    recipient: { ...ensurePayload, recipient: "+250788000000" },
    version: { ...ensurePayload, expected_source_version: 0 },
    fraction: { ...ensurePayload, expected_source_version: 1.5 },
    missing: { run_id: RUN, fence_version: 1 },
    unknown: { ...ensurePayload, event_id: "unknown" },
  })
) {
  Deno.test(
    "closed v2 ensure rejects " + name + " before key lookup",
    async () => {
      const f = await fixture();
      equal((await f.invoke("ensure_receipt", payload)).status, 400);
      equal(f.calls.length, 0);
    },
  );
}
Deno.test("v2 exact existing receipt handled proof survives strict projection", async () => {
  const f = await fixture();
  f.setResult(ensure());
  equal((await f.invoke("ensure_receipt", ensurePayload)).status, 200);
});
for (
  const [name, patch] of Object.entries({
    rawContact: { destination: "secret" },
    rawText: { message_body: "secret" },
    falseHandled: { business_handled: false },
    missingReceipt: { receipt_id: null },
    foreignEvent: { event_id: RUN },
    foreignFence: { fence_version: 2 },
    wrongVersion: { source_version: 2 },
    unknownCode: { code: "SMS_SENT" },
  })
) {
  Deno.test(
    "v2 malformed post-proof ensure stays unknown: " + name,
    async () => {
      const f = await fixture();
      f.setResult({ ...ensure(), ...patch });
      const response = await f.invoke("ensure_receipt", ensurePayload);
      equal(response.status, 502);
      equal((await response.json()).code, "SUPERVISOR_OUTCOME_UNKNOWN");
    },
  );
}
Deno.test("SOURCE_CHANGED echoes retained expected version and creates no ACK", async () => {
  assert(
    validateOperationResult(
      {
        ...ensure(),
        source_version: 1,
        ok: false,
        code: "SOURCE_CHANGED",
        business_handled: false,
        receipt_id: null,
      },
      PRINCIPAL,
      REQUEST,
      "ensure_receipt",
      ensurePayload,
    ),
  );
});
for (
  const [name, patch] of Object.entries({
    future: { expires_at: new Date(NOW + 120001).toISOString() },
    renewed: { expires_at: EXPIRY },
    missingFence: { fence_version: null },
    pausedStarted: { mode: "Paused" },
    private: { phone: "secret" },
  })
) {
  Deno.test("lease result rejects " + name, async () => {
    const f = await fixture();
    f.setResult({ ...begin(), ...patch });
    equal((await f.invoke()).status, 502);
  });
}
Deno.test("retained pause refusal has no fabricated lease", async () => {
  const f = await fixture();
  f.setResult({
    ...begin(),
    ok: false,
    code: "OPERATIONS_PAUSED",
    mode: "Paused",
    run_id: null,
    fence_version: null,
    expires_at: null,
  });
  equal((await f.invoke()).status, 200);
});
Deno.test("historical request lookup keeps original result and grants no fresh run", async () => {
  const f = await fixture();
  f.setResult({
    contract_version: 2,
    target_request_id: EVENT,
    status: "recorded",
    receipt: {
      ...begin(),
      request_id: EVENT,
      observed_at: new Date(NOW - 300000).toISOString(),
      expires_at: new Date(NOW - 180000).toISOString(),
    },
  });
  const response = await f.invoke("reconcile_request", {
    target_request_id: EVENT,
  });
  equal(response.status, 200);
  equal(f.calls[1].args.p_payload, { target_request_id: EVENT });
});
for (const status of ["not_recorded", "in_progress"]) {
  Deno.test(
    "v2 lookup " + status +
      " remains no proof of absence or permission to retry",
    async () => {
      const f = await fixture();
      f.setResult({
        contract_version: 2,
        target_request_id: EVENT,
        status,
        receipt: null,
      });
      equal(
        (await f.invoke("reconcile_request", { target_request_id: EVENT }))
          .status,
        200,
      );
    },
  );
}
Deno.test("actual run policy fence refusal is stable redacted conflict", async () => {
  const f = await fixture();
  f.setError("55000");
  const response = await f.invoke();
  equal(response.status, 409);
  equal(await response.json(), {
    ok: false,
    code: "SUPERVISOR_REQUEST_REFUSED",
  });
});
Deno.test("strict event list filters private source data and duplicate UUIDs", () => {
  const event = {
    event_id: EVENT,
    source_version: 1,
    event_kind: "payment_posted",
    payment_id: RECEIPT,
    collection_id: RUN,
    source_state: "posted",
  };
  const result = {
    ...base("list_events"),
    ...fence,
    events: [event],
    more: false,
  };
  assert(
    validateOperationResult(result, PRINCIPAL, REQUEST, "list_events", {
      ...fence,
      limit: 1,
    }),
  );
  assert(
    !validateOperationResult(
      { ...result, events: [event, event] },
      PRINCIPAL,
      REQUEST,
      "list_events",
      { ...fence, limit: 2 },
    ),
  );
  assert(
    !validateOperationResult(
      { ...result, events: [{ ...event, collection_id: null }] },
      PRINCIPAL,
      REQUEST,
      "list_events",
      { ...fence, limit: 1 },
    ),
  );
});
Deno.test("completion derives bounded actual segment count and cannot handle deferred work", () => {
  const result = {
    ...base("complete_run"),
    ...fence,
    status: "completed",
    handled_count: 3,
    deferred_count: 0,
    action_count: 4,
    sms_segments: 2,
    business_handled: true,
  };
  assert(
    validateOperationResult(result, PRINCIPAL, REQUEST, "complete_run", fence),
  );
  assert(
    !validateOperationResult(
      { ...result, deferred_count: 1 },
      PRINCIPAL,
      REQUEST,
      "complete_run",
      fence,
    ),
  );
  assert(
    !validateOperationPayload("complete_run", { ...fence, handled_count: 3 }),
  );
});

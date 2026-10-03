import { reconciliationHandler, type RpcResult } from "./handler.ts";

const reviewId = "99890000-0000-4000-8000-000000000011";
const paymentId = "99890000-0000-4000-8000-000000000021";
const success = {
  review_id: reviewId,
  payment_id: paymentId,
  payment_status: "posted",
  replayed: false,
  evidence_level: "independently_reconciled",
};
function assert(ok: unknown, message: string) {
  if (!ok) throw new Error(message);
}
function request(body: unknown = { review_id: reviewId }, auth = true) {
  return new Request("https://example.invalid/reconciliation-finalize", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(auth ? { authorization: "Bearer synthetic-user-jwt" } : {}),
    },
    body: JSON.stringify(body),
  });
}
function fixture(
  auth: RpcResult = { data: true, error: null },
  finalized: RpcResult = { data: success, error: null },
) {
  const calls: string[] = [];
  return {
    calls,
    handler: reconciliationHandler({
      authorize: async (authorization, id) => {
        assert(authorization === "Bearer synthetic-user-jwt", "wrong bearer");
        assert(id === reviewId, "wrong review");
        calls.push("authorize");
        return auth;
      },
      finalize: async (id) => {
        assert(id === reviewId, "wrong finalization UUID");
        calls.push("finalize");
        return finalized;
      },
    }),
  };
}
Deno.test("only the authorized review UUID reaches the service finalizer", async () => {
  const f = fixture();
  const response = await f.handler(request());
  assert(response.status === 200, "not successful");
  assert(f.calls.join() === "authorize,finalize", "wrong call order");
  assert(
    JSON.stringify(await response.json()) === JSON.stringify(success),
    "wrong bounded output",
  );
  assert(
    response.headers.get("cache-control") === "no-store",
    "cacheable response",
  );
});
Deno.test("replay reports an already reversed payment truthfully", async () => {
  const data = { ...success, replayed: true, payment_status: "reversed" };
  const f = fixture(undefined, { data, error: null });
  const response = await f.handler(request());
  assert(
    response.status === 200 &&
      (await response.json()).payment_status === "reversed",
    "reversal hidden",
  );
});
for (
  const [label, body] of [
    ["missing review", {}],
    ["null review", { review_id: null }],
    ["malformed review", { review_id: "wrong" }],
    ["unapproved payment fields", { review_id: reviewId, amount_rwf: 2500 }],
    ["oversized payload", { review_id: "x".repeat(2200) }],
  ] as const
) {
  Deno.test(`rejects ${label} before authorization or posting`, async () => {
    const f = fixture();
    const response = await f.handler(request(body));
    assert(
      response.status >= 400 && response.status < 500,
      "invalid body accepted",
    );
    assert(f.calls.length === 0, "invalid request reached backend");
  });
}
Deno.test("missing credentials do not reach backend", async () => {
  const f = fixture();
  assert(
    (await f.handler(request(undefined, false))).status === 401,
    "missing auth accepted",
  );
  assert(f.calls.length === 0, "missing auth reached backend");
});
for (
  const [code, status] of [["42501", 403], ["PGRST301", 401], ["22023", 409], [
    "XX000",
    503,
  ]] as const
) {
  Deno.test(`authorization ${code} blocks posting and returns stable error`, async () => {
    const f = fixture({ data: null, error: { code } });
    const response = await f.handler(request());
    assert(response.status === status, "wrong stable status");
    assert(f.calls.join() === "authorize", "unauthorized posting attempted");
    assert(!(await response.text()).includes(code), "database code leaked");
  });
}
Deno.test("false authorization is denied", async () => {
  const f = fixture({ data: false, error: null });
  assert(
    (await f.handler(request())).status === 403,
    "false permission accepted",
  );
  assert(f.calls.join() === "authorize", "false permission posted");
});
Deno.test("revocation between authorization and finalization fails closed", async () => {
  const f = fixture(undefined, { data: null, error: { code: "42501" } });
  const response = await f.handler(request());
  assert(response.status === 403, "revocation ignored");
  assert(f.calls.join() === "authorize,finalize", "server recheck not reached");
});
for (
  const data of [
    { ...success, review_id: paymentId },
    { ...success, payment_id: "bad" },
    { ...success, replayed: "false" },
    { ...success, payment_status: "review" },
  ]
) {
  Deno.test(`rejects malformed service result ${JSON.stringify(data)}`, async () => {
    const f = fixture(undefined, { data, error: null });
    assert(
      (await f.handler(request())).status === 503,
      "malformed success accepted",
    );
  });
}
Deno.test("service outage details are not exposed", async () => {
  const handler = reconciliationHandler({
    authorize: async () => ({ data: true, error: null }),
    finalize: async () => {
      throw new Error("secret provider credential SQL detail");
    },
  });
  const response = await handler(request());
  assert(
    response.status === 503 && !(await response.text()).includes("secret"),
    "private error leaked",
  );
});
Deno.test("method/preflight handling never posts", async () => {
  const f = fixture();
  assert(
    (await f.handler(new Request("https://example.invalid"))).status === 405,
    "GET permitted",
  );
  assert(
    (await f.handler(
      new Request("https://example.invalid", { method: "OPTIONS" }),
    )).status === 200,
    "preflight failed",
  );
  assert(f.calls.length === 0, "non-POST posted");
});
Deno.test("step-up requirement has an explicit stable error", async () => {
  const f = fixture({
    data: null,
    error: { code: "42501", message: "reconciliation_step_up_required" },
  });
  const response = await f.handler(request());
  assert(
    response.status === 403 &&
      (await response.json()).error === "reconciliation_step_up_required",
    "step-up hidden",
  );
  assert(f.calls.join() === "authorize", "step-up bypassed");
});
Deno.test("unknown permission detail is not echoed", async () => {
  const f = fixture({
    data: null,
    error: { code: "42501", message: "secret private identity" },
  });
  const response = await f.handler(request());
  assert(
    !(await response.text()).includes("secret"),
    "permission detail leaked",
  );
});
for (const data of [null, [], { ...success, payment_status: "reversed" }]) {
  Deno.test(`invalid finalizer object ${JSON.stringify(data)} is unavailable`, async () => {
    const f = fixture(undefined, { data, error: null });
    assert(
      (await f.handler(request())).status === 503,
      "invalid server output accepted",
    );
  });
}

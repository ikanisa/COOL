import {
  createExceptionWorkerHandler,
  type WorkerDependencies,
} from "./handler.ts";
const ID = "99950000-0000-4000-8000-000000000001";
const SECRET = "SYNTHETIC-WORKER-CREDENTIAL-NEVER-A-REAL-SECRET";
const NOW = Date.parse("2026-10-01T12:00:00Z");
const stamp = (delta = 0) => new Date(NOW + delta).toISOString();
const execute = () => ({
  contract_version: 1,
  action: "execute",
  request_id: ID,
  configuration_revision: 2,
  expires_at: stamp(90000),
});
const receipt = () => ({
  contract_version: 1,
  request_id: ID,
  configuration_revision: 2,
  recorded_at: stamp(),
  expires_at: stamp(90000),
  status: "completed",
  scan: {
    contract_version: 1,
    request_id: ID,
    checked_at: stamp(),
    expires_at: stamp(90000),
    status: "processed",
    seeded: 1,
    processed: 1,
    refused: 0,
    observations_added: 1,
    activated: 1,
    cleared: 0,
    unchanged: 0,
    pending: 0,
    scan_epoch: 1,
    scan_phase: "receipt_event",
    source_scan_complete: false,
    financial_action: false,
    send_action: false,
  },
  escalation: {
    contract_version: 1,
    channel: "admin_inbox",
    delivered: 1,
    obsolete: 0,
    recipient_unavailable: 0,
    external_send: false,
  },
  financial_action: false,
  send_action: false,
  external_send: false,
});
const recorded = () => ({
  contract_version: 1,
  request_id: ID,
  status: "recorded",
  receipt: receipt(),
});
const lookup = (status = "recorded") => ({
  contract_version: 1,
  request_id: ID,
  checked_at: stamp(),
  sample_valid_until: stamp(60000),
  status,
  expires_at: stamp(90000),
  receipt: status === "recorded" ? receipt() : null,
});
function assert(v: unknown): asserts v {
  if (!v) throw Error("assertion_failed");
}
async function invoke(
  body: unknown,
  overrides: Partial<WorkerDependencies> = {},
  options: { method?: string; secret?: string; raw?: string } = {},
) {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const handler = createExceptionWorkerHandler({
    now: () => NOW,
    secret: () => SECRET,
    rpc: async (name, args, signal) => {
      assert(!signal.aborted);
      calls.push({ name, args });
      return overrides.rpc ? await overrides.rpc(name, args, signal) : {
        data: name.startsWith("execute_") ? recorded() : lookup(),
        error: null,
      };
    },
    ...Object.fromEntries(
      Object.entries(overrides).filter(([k]) => k !== "rpc"),
    ),
  });
  const r = await handler(
    new Request("https://worker.test/", {
      method: options.method ?? "POST",
      headers: { "x-collect-receipt-worker": options.secret ?? SECRET },
      body: options.method === "GET"
        ? undefined
        : options.raw ?? JSON.stringify(body),
    }),
  );
  return { status: r.status, body: await r.json(), calls, headers: r.headers };
}
Deno.test("actual HTTP entry boundary returns exact recorded SQL receipt without private payload", async () => {
  const handler = createExceptionWorkerHandler({
    secret: () => SECRET,
    now: () => NOW,
    rpc: async () => ({ data: recorded(), error: null }),
  });
  const server = Deno.serve({
    hostname: "127.0.0.1",
    port: 0,
    onListen: () => {},
  }, handler);
  try {
    const r = await fetch(`http://127.0.0.1:${server.addr.port}/`, {
      method: "POST",
      headers: { "x-collect-receipt-worker": SECRET },
      body: JSON.stringify(execute()),
    });
    assert(
      r.status === 200 &&
        JSON.stringify(await r.json()) === JSON.stringify(recorded()),
    );
    assert(r.headers.get("cache-control") === "no-store");
  } finally {
    await server.shutdown();
  }
});
Deno.test("method and unconfigured credential refuse before RPC", async () => {
  for (
    const v of [
      await invoke(execute(), {}, { method: "GET" }),
      await invoke(execute(), { secret: () => "" }),
      await invoke(execute(), { secret: () => "x".repeat(300) }),
    ]
  ) {
    assert(v.status >= 400 && v.calls.length === 0);
  }
});
Deno.test("general internal secret or JWT cannot authorize dedicated worker", async () => {
  const v = await invoke(execute(), {}, {
    secret: "DIFFERENT-INTERNAL-SECRET-THAT-IS-LONG",
  });
  assert(
    v.status === 401 && v.calls.length === 0 &&
      v.body.error === "WORKER_AUTH_REQUIRED",
  );
});
Deno.test("request allowlist rejects arbitrary action destination text quota and extra field", async () => {
  for (
    const body of [
      { ...execute(), action: "send_sms" },
      { ...execute(), destination: "+250788123456" },
      { ...execute(), text: "Hello" },
      { ...execute(), scan_limit: 100 },
      { ...execute(), request_id: "bad" },
      { ...execute(), contract_version: 2 },
      { ...execute(), configuration_revision: 1.5 },
    ]
  ) {
    const v = await invoke(body);
    assert(v.status === 400 && v.calls.length === 0);
  }
});
Deno.test("expired or excessive execute deadline refuses without mutation", async () => {
  for (
    const expiry of [
      stamp(-1),
      stamp(120001),
      "infinity",
      "2026-10-01T99:00:00Z",
    ]
  ) {
    assert((await invoke({ ...execute(), expires_at: expiry })).status === 400);
  }
});
Deno.test("bounded streamed input rejects oversized and malformed JSON before RPC", async () => {
  for (
    const raw of [
      "{",
      JSON.stringify({ ...execute(), extra: "x".repeat(3000) }),
    ]
  ) {
    const v = await invoke(null, {}, { raw });
    assert(v.status === 400 && v.calls.length === 0);
  }
});
Deno.test("execute sends only exact original job parameters", async () => {
  const v = await invoke(execute());
  assert(v.status === 200 && v.calls.length === 1);
  assert(
    JSON.stringify(v.calls[0]) ===
      JSON.stringify({
        name: "execute_receipt_exception_worker_v1",
        args: {
          p_request_id: ID,
          p_configuration_revision: 2,
          p_expires_at: stamp(90000),
        },
      }),
  );
});
Deno.test("authority refusal and original conflict are finite redacted refusals", async () => {
  for (const [code, status] of [["42501", 403], ["22023", 409]] as const) {
    const v = await invoke(execute(), {
      rpc: async () => ({ data: null, error: { code } }),
    });
    assert(
      v.status === status && v.calls.length === 1 &&
        Object.keys(v.body).length === 2,
    );
  }
});
Deno.test("lost mutation response reconciles recorded proof without rerunning execute", async () => {
  const v = await invoke(execute(), {
    rpc: async (name) => {
      if (name.startsWith("execute_")) {
        throw Error("transport_timeout_with_sensitive_body");
      }
      return { data: lookup(), error: null };
    },
  });
  assert(
    v.status === 200 && v.body.receipt.request_id === ID &&
      v.calls.length === 2 && v.calls[1].name.startsWith("get_"),
  );
  assert(!JSON.stringify(v.body).includes("sensitive"));
});
Deno.test("missing before original expiry preserves uncertain response and original deadline", async () => {
  const v = await invoke(execute(), {
    rpc: async (name) =>
      name.startsWith("execute_")
        ? { data: null, error: { code: "57014" } }
        : { data: lookup("not_recorded"), error: null },
  });
  assert(
    v.status === 202 && v.body.status === "not_recorded" &&
      v.body.expires_at === stamp(90000) && v.calls.length === 2,
  );
});
Deno.test("recorded recovery is bound to the exact requested configuration and deadline", async () => {
  const different = lookup();
  different.receipt!.configuration_revision = 3;
  const v = await invoke(execute(), {
    rpc: async (name) => {
      if (name.startsWith("execute_")) throw Error("network_timeout");
      return { data: different, error: null };
    },
  });
  assert(
    v.status === 409 && v.body.error === "WORKER_ORIGINAL_CONFLICT" &&
      v.calls.length === 2,
  );
});
Deno.test("global overlap returns explicit in_progress without additional mutation", async () => {
  const v = await invoke(execute(), {
    rpc: async () => ({
      data: {
        contract_version: 1,
        request_id: ID,
        status: "in_progress",
        receipt: null,
      },
      error: null,
    }),
  });
  assert(v.status === 202 && v.body.receipt === null && v.calls.length === 1);
});
Deno.test("unavailable original lookup retains uncertainty with no third attempt", async () => {
  const v = await invoke(execute(), {
    rpc: async () => {
      throw Error("network_timeout");
    },
  });
  assert(
    v.status === 202 && v.body.error === "WORKER_OUTCOME_UNKNOWN" &&
      v.calls.length === 2,
  );
});
Deno.test("reconcile calls only read and remains valid after execute expiry", async () => {
  const v = await invoke({
    contract_version: 1,
    action: "reconcile",
    request_id: ID,
  }, {
    now: () => NOW + 200000,
    rpc: async () => ({
      data: {
        ...lookup(),
        checked_at: stamp(200000),
        sample_valid_until: stamp(260000),
      },
      error: null,
    }),
  });
  assert(
    v.status === 200 && v.calls.length === 1 &&
      v.calls[0].name === "get_receipt_exception_worker_request_v1",
  );
});
Deno.test("stale or contradictory lookup cannot prove absence or expose raw response", async () => {
  for (
    const bad of [
      { ...lookup("not_recorded"), sample_valid_until: stamp(-1) },
      { ...lookup("not_recorded"), receipt: receipt() },
      { ...lookup(), checked_at: stamp(7000) },
      { ...lookup(), recipient: "private" },
    ]
  ) {
    const v = await invoke({
      contract_version: 1,
      action: "reconcile",
      request_id: ID,
    }, { rpc: async () => ({ data: bad, error: null }) });
    assert(
      v.status === 503 && v.body.error === "WORKER_LOOKUP_UNAVAILABLE" &&
        !JSON.stringify(v.body).includes("private"),
    );
  }
});
Deno.test("mismatched original or nonfinite nested counters cannot fabricate success", async () => {
  for (
    const change of [(r: ReturnType<typeof receipt>) => {
      r.configuration_revision = 3;
    }, (r: ReturnType<typeof receipt>) => {
      r.scan.processed = 26;
    }, (r: ReturnType<typeof receipt>) => {
      r.scan.refused = 2;
    }, (r: ReturnType<typeof receipt>) => {
      r.escalation.delivered = 21;
    }, (r: ReturnType<typeof receipt>) => {
      r.financial_action = true;
    }, (r: ReturnType<typeof receipt>) => {
      r.scan.source_scan_complete = true;
    }]
  ) {
    const r = receipt();
    change(r);
    const v = await invoke(execute(), {
      rpc: async (name) =>
        name.startsWith("execute_")
          ? { data: { ...recorded(), receipt: r }, error: null }
          : { data: lookup("not_recorded"), error: null },
    });
    assert(
      v.status === 202 && v.body.status === "not_recorded" &&
        v.calls.length === 2,
    );
  }
});

// Real loopback HTTP servers load the unmodified Edge entrypoints. Only their
// Auth/PostgREST dependency is a recording synthetic server; provider network
// access is denied by the launcher. This is not hosted or provider acceptance.
import { Webhook } from "npm:standardwebhooks@1.0.0";
import { hmacSha256Hex } from "../../supabase/functions/_shared/hmac.ts";

const userId = "98600000-0000-4000-8000-000000000001";
const internalSecret = crypto.randomUUID();
const emailSecret = crypto.randomUUID();
const hookSecret = btoa(crypto.randomUUID() + crypto.randomUUID());
const realServe = Deno.serve;
const servers: Deno.HttpServer<Deno.NetAddr>[] = [];
const controllers: AbortController[] = [];
const records: Array<Record<string, unknown>> = [];
const checks: Array<Record<string, unknown>> = [];
const entrypoints: Record<string, string> = {};
let mode = "normal";
let counter = 0;
let countReaders = 0;
let releaseReaders: (() => void) | undefined;
let readerBarrier: Promise<void> | undefined;

function json(
  value: unknown,
  status = 200,
  headers: Record<string, string> = {},
) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

const backendController = new AbortController();
controllers.push(backendController);
const backend = realServe({
  hostname: "127.0.0.1",
  port: 0,
  signal: backendController.signal,
  onListen() {},
}, async (request) => {
  const path = new URL(request.url).pathname;
  const text = await request.text();
  const payload = text ? JSON.parse(text) : null;
  const authorization = request.headers.get("authorization");
  records.push({
    path,
    method: request.method,
    payload,
    identity: authorization === "Bearer qa-user"
      ? "synthetic_user"
      : authorization === "Bearer qa-service"
      ? "synthetic_service"
      : "unrecognized",
  });
  if (path === "/auth/v1/user") {
    if (authorization !== "Bearer qa-user") {
      return json({ message: "invalid synthetic token" }, 401);
    }
    return json({
      id: userId,
      aud: "authenticated",
      role: "authenticated",
      created_at: new Date().toISOString(),
      app_metadata: {},
      user_metadata: {},
    });
  }
  if (path === "/rest/v1/rpc/admin_current_user") {
    return json({
      user_id: userId,
      permissions: mode === "denied" ? [] : [
        "notifications.read",
        "notifications.manage",
        "users.read",
        "collections.moderate",
      ],
    });
  }
  if (path === "/rest/v1/feature_flags") return json({ enabled: true });
  if (path === "/rest/v1/otp_rate_limits") {
    if (request.method === "HEAD") {
      if (mode === "count_error") return new Response(null, { status: 503 });
      const observed = counter;
      if (mode === "concurrent") {
        countReaders++;
        if (countReaders === 8) releaseReaders?.();
        await readerBarrier;
      }
      return new Response(null, {
        headers: { "content-range": `0-0/${observed}` },
      });
    }
    if (mode === "insert_error") {
      return json({
        code: "QA_FAILURE",
        message: "Synthetic limiter storage unavailable",
      }, 503);
    }
    counter++;
    return new Response(null, { status: 201 });
  }
  if (path === "/rest/v1/rpc/reserve_otp_request") {
    if (mode === "count_error" || mode === "insert_error") {
      return json({
        code: "QA_FAILURE",
        message: "Synthetic limiter storage unavailable",
      }, 503);
    }
    if (mode === "missing_rpc") {
      return json({ code: "PGRST202", message: "RPC not deployed" }, 404);
    }
    if (mode === "malformed_reservation") return json({ allowed: true });
    if (counter >= 5) return json(false);
    counter++;
    return json(true);
  }
  if (path === "/rest/v1/rpc/claim_notification_deliveries") return json([]);
  if (path === "/rest/v1/rpc/collect_notification_health") {
    return json({ pending: 0 });
  }
  if (path === "/rest/v1/rpc/attested_sms_contract_version") return json(1);
  if (path === "/rest/v1/rpc/ingest_bank_evidence") {
    return json({ id: "qa-evidence", status: "recorded" });
  }
  if (path === "/rest/v1/rpc/enqueue_notification_event") return json(null);
  return json({ code: "QA_UNEXPECTED_BACKEND_PATH", message: path }, 500);
});
servers.push(backend);

for (
  const [key, value] of Object.entries({
    SUPABASE_URL: `http://127.0.0.1:${backend.addr.port}`,
    SUPABASE_ANON_KEY: "qa-anon",
    SUPABASE_SERVICE_ROLE_KEY: "qa-service",
    INTERNAL_FUNCTION_SECRET: internalSecret,
    BANK_EMAIL_INGEST_HMAC_SECRET: emailSecret,
    SEND_SMS_HOOK_SECRET: hookSecret,
    WHATSAPP_CLOUD_DRY_RUN: "true",
    WHATSAPP_CLOUD_API_TOKEN: "qa-disabled-provider",
    WHATSAPP_PHONE_NUMBER_ID: "qa-disabled-provider",
    WHATSAPP_AUTH_TEMPLATE_NAME: "qa_disabled_provider",
  })
) Deno.env.set(key, value);

const report: Record<string, unknown> = {
  started_at: new Date().toISOString(),
  final_acceptance: false,
  mode:
    "real_edge_http_with_recording_synthetic_auth_postgrest_and_disabled_providers",
  checks,
  entrypoints,
  dependency_records: records,
  limitations: [
    "No platform verify_jwt gateway or real Auth sign-in",
    "Synthetic dependency responses do not prove SQL persistence or RLS",
    "No WhatsApp/APNs/FCM/Play/OpenAI/provider delivery or acceptance",
  ],
};

function check(
  label: string,
  passed: boolean,
  evidence: Record<string, unknown> = {},
) {
  checks.push({ label, status: passed ? "pass" : "fail", ...evidence });
  console.log(
    "QA_EDGE_PROGRESS=" +
      JSON.stringify({ label, passed, dependency_count: records.length }),
  );
}

async function request(
  slug: string,
  label: string,
  options: {
    method?: string;
    body?: string;
    headers?: Record<string, string>;
  } = {},
) {
  const start = records.length;
  const response = await fetch(entrypoints[slug], {
    method: options.method ?? "POST",
    body: options.body ?? "{}",
    headers: { "content-type": "application/json", ...options.headers },
    signal: AbortSignal.timeout(10_000),
  });
  const text = await response.text();
  let body: unknown = null;
  try {
    body = JSON.parse(text);
  } catch { /* OPTIONS body is plain text. */ }
  return {
    label,
    http_status: response.status,
    response: body,
    cors: response.headers.get("access-control-allow-origin"),
    dependencies: records.slice(start),
    no_store: response.headers.get("cache-control")?.includes("no-store") ??
      false,
  };
}

try {
  const config = await Deno.readTextFile(
    new URL("../../supabase/config.toml", import.meta.url),
  );
  const names = [...config.matchAll(/^\[functions\.([^\]]+)\]/gm)].map((
    match,
  ) => match[1]).sort();
  report.configured_functions = names;
  check(
    "external provider network denied",
    (await Deno.permissions.query({
      name: "net",
      host: "graph.facebook.com:443",
    })).state === "denied",
  );
  for (const slug of names) {
    // Change only the listening address. The repository's actual handler runs.
    Deno.serve = ((handler: Deno.ServeHandler<Deno.NetAddr>) => {
      const controller = new AbortController();
      controllers.push(controller);
      const server = realServe({
        hostname: "127.0.0.1",
        port: 0,
        signal: controller.signal,
        onListen() {},
      }, handler);
      servers.push(server);
      entrypoints[slug] = `http://127.0.0.1:${server.addr.port}`;
      return server;
    }) as typeof Deno.serve;
    await import(
      new URL(`../../supabase/functions/${slug}/index.ts`, import.meta.url).href
    );
  }
  Deno.serve = realServe;
  check(
    "every configured entrypoint started exactly once",
    names.length === 11 && Object.keys(entrypoints).length === names.length,
  );
  for (const slug of names) {
    const preflight = await request(slug, `${slug}: preflight`, {
      method: "OPTIONS",
    });
    check(
      preflight.label,
      preflight.http_status === 200 && preflight.cors === "*" &&
        preflight.dependencies.length === 0,
      preflight,
    );
    const method = await request(slug, `${slug}: wrong method`, {
      method: "PUT",
    });
    check(
      method.label,
      method.http_status === 405 && method.dependencies.length === 0,
      method,
    );
    const missing = await request(slug, `${slug}: missing authentication`);
    check(
      missing.label,
      missing.http_status === 401 && missing.dependencies.length === 0,
      missing,
    );
    const invalid = await request(slug, `${slug}: invalid authentication`, {
      headers: {
        authorization: "Bearer qa-invalid",
        "x-collect-signature": "qa-invalid",
        "x-hook-secret": "qa-invalid",
      },
    });
    check(
      invalid.label,
      invalid.http_status === 401 &&
        invalid.dependencies.every((r) => r.path === "/auth/v1/user"),
      invalid,
    );
  }
  for (
    const slug of ["collect-notification-operator", "prepare-roster-import"]
  ) {
    mode = "denied";
    const denied = await request(slug, `${slug}: member cannot operate`, {
      headers: { authorization: "Bearer qa-user" },
      body: JSON.stringify({
        action: "health",
        source_type: "text",
        content: "0788991001",
      }),
    });
    check(
      denied.label,
      denied.http_status === 403 &&
        denied.dependencies.every((r) =>
          ["/auth/v1/user", "/rest/v1/rpc/admin_current_user"].includes(
            String(r.path),
          )
        ),
      denied,
    );
    mode = "normal";
  }
  const health = await request(
    "collect-notification-operator",
    "operator: permission-bearing identity reaches health",
    {
      headers: { authorization: "Bearer qa-user" },
      body: JSON.stringify({ action: "health", operator_user_id: "forged" }),
    },
  );
  check(
    health.label,
    health.http_status === 200 && health.no_store &&
      health.dependencies.some((r) =>
        r.path === "/rest/v1/rpc/collect_notification_health" &&
        (r.payload as Record<string, unknown>)?.p_operator_user_id === userId
      ),
    health,
  );
  const dispatch = await request(
    "dispatch-notifications",
    "dispatcher: valid internal empty queue",
    { headers: { "x-collect-signature": internalSecret } },
  );
  check(
    dispatch.label,
    dispatch.http_status === 200 &&
      (dispatch.response as Record<string, unknown>)?.claimed === 0,
    dispatch,
  );
  const parsed = await request(
    "parse-payment-sms",
    "parser: valid internal request requires real UUID",
    { headers: { "x-collect-signature": internalSecret } },
  );
  check(
    parsed.label,
    parsed.http_status === 400 && parsed.dependencies.length === 0,
    parsed,
  );
  const noEnvelope = await request(
    "ingest-payment-sms",
    "SMS: current contract refuses unattested envelope",
    {
      headers: { authorization: "Bearer qa-user" },
      body: JSON.stringify({
        raw_sender: "M-Money",
        raw_body: "Synthetic raw message",
        receiver_momo_number: "0788991001",
      }),
    },
  );
  check(
    noEnvelope.label,
    noEnvelope.http_status === 400 &&
      noEnvelope.dependencies.every((r) =>
        ["/auth/v1/user", "/rest/v1/rpc/attested_sms_contract_version"]
          .includes(
            String(r.path),
          )
      ),
    noEnvelope,
  );
  const roster = await request(
    "prepare-roster-import",
    "roster: approved deterministic preview",
    {
      headers: { authorization: "Bearer qa-user" },
      body: JSON.stringify({ source_type: "text", content: "0788991001" }),
    },
  );
  check(
    roster.label,
    roster.http_status === 200 &&
      (roster.response as Record<string, unknown>)?.processing_method ===
        "deterministic",
    roster,
  );

  const emailPayload = JSON.stringify({
    source_uid: "qa-email",
    sender: "bank@example.invalid",
    subject: "Synthetic evidence",
    body: "Unrecognized synthetic statement",
    received_at: new Date().toISOString(),
  });
  for (
    const [label, offset, mutate] of [
      ["valid", 0, false],
      ["expired", -601, false],
      ["future", 601, false],
      ["modified body", 0, true],
    ] as const
  ) {
    const timestamp = String(Math.floor(Date.now() / 1000) + offset);
    const signature = "v1=" +
      await hmacSha256Hex(emailSecret, timestamp + "." + emailPayload);
    const result = await request("ingest-bank-email", `email HMAC: ${label}`, {
      headers: {
        "x-collect-timestamp": timestamp,
        "x-collect-email-signature": signature,
      },
      body: mutate ? emailPayload + " " : emailPayload,
    });
    check(
      result.label,
      result.http_status === (label === "valid" ? 200 : 401) &&
        (label === "valid" || result.dependencies.length === 0),
      result,
    );
  }
  const otpBody = JSON.stringify({
    user: { phone: "+250788991001" },
    sms: { otp: "987654" },
  });
  const webhook = new Webhook(hookSecret);
  for (
    const [label, offset, mutate] of [["valid", 0, false], [
      "expired",
      -601,
      false,
    ], ["modified body", 0, true]] as const
  ) {
    counter = 0;
    const when = new Date(Date.now() + offset * 1000);
    const id = "qa-hook-" + label.replaceAll(" ", "-");
    const result = await request(
      "auth-send-whatsapp-otp",
      `OTP signed hook: ${label}`,
      {
        body: mutate ? otpBody + " " : otpBody,
        headers: {
          "webhook-id": id,
          "webhook-timestamp": String(Math.floor(when.getTime() / 1000)),
          "webhook-signature": webhook.sign(id, when, otpBody),
        },
      },
    );
    check(
      result.label,
      result.http_status === (label === "valid" ? 200 : 401),
      result,
    );
  }
  for (
    const failure of [
      "count_error",
      "insert_error",
      "missing_rpc",
      "malformed_reservation",
    ]
  ) {
    mode = failure;
    counter = 0;
    const result = await request(
      "auth-send-whatsapp-otp",
      `OTP limiter ${failure}: fails closed`,
      { headers: { "x-hook-secret": hookSecret }, body: otpBody },
    );
    check(result.label, result.http_status === 502, result);
  }
  mode = "normal";
  counter = 5;
  const limit = await request(
    "auth-send-whatsapp-otp",
    "OTP sixth request refused",
    { headers: { "x-hook-secret": hookSecret }, body: otpBody },
  );
  check(limit.label, limit.http_status === 429 && counter === 5, limit);
  mode = "concurrent";
  counter = 4;
  countReaders = 0;
  readerBarrier = new Promise<void>((resolve) => {
    releaseReaders = resolve;
  });
  const concurrent = await Promise.all(
    Array.from(
      { length: 8 },
      (_, i) =>
        request("auth-send-whatsapp-otp", `OTP concurrent ${i}`, {
          headers: { "x-hook-secret": hookSecret },
          body: otpBody,
        }),
    ),
  );
  check(
    "OTP concurrency: one remaining reservation allows one request",
    concurrent.filter((r) => r.http_status === 200).length === 1 &&
      concurrent.filter((r) => r.http_status === 429).length === 7 &&
      counter === 5,
    {
      statuses: concurrent.map((r) => r.http_status),
      recorded_counter: counter,
      model:
        "recording dependency; SQL concurrency requires separate verification",
    },
  );
  mode = "normal";
  report.status = checks.every((r) => r.status === "pass") ? "pass" : "fail";
} catch (error) {
  report.status = "fail";
  report.error = error instanceof Error ? error.message : String(error);
} finally {
  Deno.serve = realServe;
  releaseReaders?.();
  console.log(
    "QA_EDGE_CLOSING=" +
      JSON.stringify({
        status: report.status,
        error: report.error,
        checks: checks.length,
        last_dependency_paths: records.slice(-10).map((record) => record.path),
      }),
  );
  // All scenario responses were consumed. Abort only this process's owned
  // test listeners, including keep-alive sockets, then await their completion.
  controllers.forEach((controller) => controller.abort());
  await Promise.all(servers.map((server) => server.finished));
  report.finished_at = new Date().toISOString();
  report.servers_closed = servers.length;
  report.cleanup_mode = "owned_listeners_aborted_after_scenario_responses";
  console.log("QA_EDGE_REPORT=" + JSON.stringify(report));
}
if (report.status !== "pass") Deno.exit(1);

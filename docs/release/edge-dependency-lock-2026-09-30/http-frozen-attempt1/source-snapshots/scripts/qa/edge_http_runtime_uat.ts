// Real loopback HTTP servers load the unmodified Edge entrypoints. Only their
// Auth/PostgREST dependency is a recording synthetic server; provider network
// access is denied by the launcher. This is not hosted or provider acceptance.
import { Webhook } from "npm:standardwebhooks@1.0.0";
import { hmacSha256Hex } from "../../supabase/functions/_shared/hmac.ts";
import { normalizeRosterCandidates } from "../../supabase/functions/_shared/roster_import.ts";
import { ROSTER_DECODER_TOOLCHAIN } from "../../supabase/functions/_shared/roster_decoder.ts";

const userId = "98600000-0000-4000-8000-000000000001";
const sessionId = "98600000-0000-4000-8000-000000000011";
const userToken = "e30." +
  btoa(
    JSON.stringify({
      sub: userId,
      session_id: sessionId,
      role: "authenticated",
    }),
  ).replaceAll("=", "").replaceAll("+", "-").replaceAll("/", "_") +
  ".synthetic";
const userAuthorization = "Bearer " + userToken;
const decoderSecret = "synthetic-loopback-only-" + crypto.randomUUID();
const decoderBuild = "d".repeat(64);
const png =
  "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAFElEQVR4nGOUS+lhYGBgYgADKAUAE/ABFCFAuesAAAAASUVORK5CYII=";
const providerAttempts: string[] = [];
const originalFetch = globalThis.fetch;
globalThis.fetch = ((input: Request | URL | string, options?: RequestInit) => {
  const url = input instanceof Request ? input.url : String(input);
  if (
    url.startsWith("https://graph.facebook.com/") ||
    url.startsWith("https://api.openai.com/")
  ) providerAttempts.push(url);
  return originalFetch(input, options);
}) as typeof fetch;
const internalSecret = crypto.randomUUID();
const hookSecret = btoa(crypto.randomUUID() + crypto.randomUUID());
const realServe = Deno.serve;
const servers: Deno.HttpServer<Deno.NetAddr>[] = [];
const controllers: AbortController[] = [];
const records: Array<Record<string, unknown>> = [];
const checks: Array<Record<string, unknown>> = [];
const entrypoints: Record<string, string> = {};
let mode = "normal";
let counter = 0;
const otpAttempts = new Map<string, Record<string, unknown>>();
const rosterBudgets = new Map<string, Record<string, unknown>>();
const rosterSources = new Map<string, Record<string, unknown>>();
const decoderReceipts = new Map<string, Record<string, unknown>>();
async function sha(text: string | Uint8Array) {
  const input = typeof text === "string"
    ? new TextEncoder().encode(text)
    : text;
  return [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", input as BufferSource),
    ),
  ].map((v) => v.toString(16).padStart(2, "0")).join("");
}
function rosterInput(patch: Record<string, unknown> = {}) {
  return {
    contract_version: 1,
    request_id: crypto.randomUUID(),
    source_type: "text",
    content:
      "Member name,MoMo name,MoMo number\nAline Uwase,ALINE UWASE,0788991001",
    ...patch,
  };
}
function rosterImage(patch: Record<string, unknown> = {}) {
  return rosterInput({
    source_type: "image",
    content: undefined,
    filename: "fixture.png",
    mime_type: "image/png",
    content_base64: png,
    ai_consent: true,
    consent_version: "roster-ai-extraction-v1",
    ...patch,
  });
}
function rosterPreview(
  source: Record<string, unknown>,
  candidates: Parameters<typeof normalizeRosterCandidates>[0],
) {
  return {
    contract_version: 1,
    ok: true,
    import_id: source.import_id,
    source_sha256: source.p_original_sha256,
    source_kind: source.p_source_kind,
    source_receipt: {
      request_id: source.p_request_id,
      source_size: source.p_original_size,
      client_filename: source.p_client_filename,
      declared_mime: source.p_declared_mime,
      detected_type: source.p_detected_type,
      derived_sha256: source.p_derived_sha256,
      derived_assurance: source.p_source_kind === "xlsx"
        ? "client_derived_tsv"
        : null,
      extraction_id: source.extraction_id,
      ai_consent: source.p_ai_consent,
      consent_version: source.p_consent_version,
      parser_version: "collect-roster-parser-v1",
      schema_version: "collect-roster-rows-v1",
    },
    revision_id: crypto.randomUUID(),
    parent_revision_id: null,
    revision_number: 1,
    reviewed_rows_sha256: "a".repeat(64),
    ...normalizeRosterCandidates(candidates),
    can_submit: false,
    requires_human_review: true,
    processing_method: source.p_ai_consent
      ? "openai_structured_extraction"
      : "deterministic",
    model: source.p_ai_consent ? "synthetic-model" : null,
    expires_at: "2099-01-01T00:00:00Z",
  };
}

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
    identity: authorization === userAuthorization
      ? "synthetic_user"
      : authorization === "Bearer qa-service"
      ? "synthetic_service"
      : "unrecognized",
  });
  if (path === "/auth/v1/user") {
    if (authorization !== userAuthorization) {
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
  if (path === "/rest/v1/rpc/authorize_reconciliation_finalization_v2") {
    return authorization === userAuthorization
      ? json(true)
      : json({ code: "PGRST301", message: "Synthetic invalid JWT" }, 401);
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
  if (path.endsWith("/reserve_signed_otp_v3")) {
    const args = payload as Record<string, unknown>;
    if (mode === "count_error" || mode === "insert_error") {
      return json({
        code: "QA_FAILURE",
        message: "Synthetic durable reservation unavailable",
      }, 503);
    }
    if (mode === "missing_rpc") {
      return json({ code: "PGRST202", message: "RPC not deployed" }, 404);
    }
    if (mode === "malformed_reservation") return json({ allowed: true });
    if (mode === "reserve_timeout") {
      await new Promise((resolve) => setTimeout(resolve, 4500));
      return json({ allowed: true });
    }
    const key = String(args.p_hook_id), existing = otpAttempts.get(key);
    if (existing) {
      if (existing.payload_hash !== args.p_payload_hash) {
        return json({ code: "22023", message: "otp_payload_conflict" }, 400);
      }
      return json(existing);
    }
    if (counter >= 5) return json("throttled");
    counter++;
    const receipt = {
      contract_version: 3,
      hook_id: args.p_hook_id,
      payload_hash: args.p_payload_hash,
      attempt_id: crypto.randomUUID(),
      state: mode === "already_accepted" ? "accepted" : "reserved",
      revision: 1,
      can_send: mode !== "already_accepted",
    };
    otpAttempts.set(key, receipt);
    return json(receipt);
  }
  if (
    path.endsWith("/begin_signed_otp_v3") ||
    path.endsWith("/record_signed_otp_v3")
  ) {
    const args = payload as Record<string, unknown>,
      key = String(args.p_hook_id),
      existing = otpAttempts.get(key);
    if (
      !existing || existing.payload_hash !== args.p_payload_hash ||
      existing.attempt_id !== args.p_attempt_id ||
      existing.revision !== args.p_revision
    ) return json({ code: "22023", message: "otp_identity_conflict" }, 400);
    if (path.endsWith("/begin_signed_otp_v3")) {
      const receipt = {
        ...existing,
        state: "sending",
        revision: Number(existing.revision) + 1,
        can_send: false,
      };
      otpAttempts.set(key, receipt);
      return json({ ...receipt, started: true });
    }
    if (mode === "lost_record_ack") {
      return json({
        code: "QA_FAILURE",
        message: "Synthetic recording acknowledgement lost",
      }, 503);
    }
    const receipt = {
      ...existing,
      state: args.p_outcome,
      revision: Number(existing.revision) + 1,
      can_send: false,
    };
    otpAttempts.set(key, receipt);
    return json(receipt);
  }
  if (path.endsWith("/reserve_roster_resources")) {
    const args = payload as Record<string, unknown>;
    if (mode === "denied") {
      return json({ code: "42501", message: "roster_import_forbidden" }, 403);
    }
    if (mode === "roster_quota") {
      return json({ code: "P0001", message: "roster_resource_limit" }, 429);
    }
    const existing = rosterBudgets.get(String(args.p_request_id));
    if (existing) return json({ ...existing, replayed: true });
    const receipt = {
      contract_version: 1,
      ok: true,
      reservation_id: crypto.randomUUID(),
      request_id: args.p_request_id,
      actor_id: args.p_actor_id,
      session_id: args.p_session_id,
      source_sha256: args.p_source_sha256,
      state: "reserved",
      replayed: false,
      expires_at: "2099-01-01T00:00:00Z",
    };
    rosterBudgets.set(String(args.p_request_id), receipt);
    return json(
      mode === "roster_bad_budget"
        ? { ...receipt, actor_id: crypto.randomUUID() }
        : receipt,
    );
  }
  if (path.endsWith("/verify_roster_source_integrity")) {
    const args = payload as Record<string, unknown>,
      proof = decoderReceipts.get(String(args.p_reservation_id));
    if (
      !proof || proof.receipt_sha256 !== args.p_decoder_receipt_sha256 ||
      proof.decoder_build_sha256 !== args.p_decoder_build_sha256 ||
      args.p_actor_id !== userId || args.p_session_id !== sessionId
    ) {
      return json({
        code: "22023",
        message: "roster_source_verification_invalid",
      }, 400);
    }
    return json({
      contract_version: 1,
      ok: true,
      reservation_id: args.p_reservation_id,
      source_sha256: proof.source_sha256,
      derived_sha256: proof.derived_sha256,
      decoder_receipt_sha256: mode === "roster_bad_verification"
        ? "f".repeat(64)
        : args.p_decoder_receipt_sha256,
      verified: true,
    });
  }
  if (path.endsWith("/finish_roster_resources")) {
    const args = payload as Record<string, unknown>,
      budget = [...rosterBudgets.values()].find((r) =>
        r.reservation_id === args.p_reservation_id
      );
    if (
      !budget || args.p_actor_id !== userId || args.p_session_id !== sessionId
    ) return json({ code: "42501", message: "roster_import_forbidden" }, 403);
    budget.state = "finished";
    return json({
      contract_version: 1,
      ok: true,
      reservation_id: args.p_reservation_id,
      outcome: args.p_outcome,
      charged: true,
    });
  }
  if (path.endsWith("/create_roster_import_source")) {
    const args = payload as Record<string, unknown>,
      existing = rosterSources.get(String(args.p_request_id));
    const source = existing ??
      {
        ...args,
        import_id: crypto.randomUUID(),
        extraction_id: args.p_ai_consent ? crypto.randomUUID() : null,
        state: "awaiting_preview",
        completed_preview: null,
        error_code: null,
      };
    rosterSources.set(String(args.p_request_id), source);
    return json({
      contract_version: 1,
      ok: true,
      request_id: args.p_request_id,
      import_id: source.import_id,
      source_sha256: args.p_original_sha256,
      source_size: args.p_original_size,
      source_kind: args.p_source_kind,
      extraction_id: source.extraction_id,
      expires_at: "2099-01-01T00:00:00Z",
      derived_sha256: args.p_derived_sha256,
      derived_assurance: args.p_source_kind === "xlsx"
        ? "client_derived_tsv"
        : null,
      state: source.state,
      replayed: !!existing,
      completed_preview: source.completed_preview,
      error_code: source.error_code,
    });
  }
  if (
    path.endsWith("/complete_roster_import_preview") ||
    path.endsWith("/fail_roster_import_preview")
  ) {
    const args = payload as Record<string, unknown>,
      source = [...rosterSources.values()].find((r) =>
        r.import_id === args.p_import_id
      );
    if (
      !source || args.p_actor_id !== userId || args.p_session_id !== sessionId
    ) return json({ code: "42501", message: "roster_import_forbidden" }, 403);
    if (path.endsWith("/fail_roster_import_preview")) {
      source.state = "failed";
      source.error_code = args.p_error_code;
      return json({
        contract_version: 1,
        ok: true,
        import_id: source.import_id,
        state: "failed",
        error_code: args.p_error_code,
        replayed: false,
      });
    }
    source.completed_preview = rosterPreview(
      source,
      args.p_candidates as Parameters<typeof normalizeRosterCandidates>[0],
    );
    source.state = "preview_ready";
    return json(source.completed_preview);
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

// Signed recording responses exercise exact HTTP/HMAC and durable-ACK
// prerequisites. This fixture does not parse codecs; actual sandbox decoding
// has its own independently executed malicious-corpus evidence.
const decoderController = new AbortController();
controllers.push(decoderController);
const decoder = realServe({
  hostname: "127.0.0.1",
  port: 0,
  signal: decoderController.signal,
  onListen() {},
}, async (request) => {
  const raw = await request.text(),
    input = JSON.parse(raw),
    bytes = Uint8Array.from(atob(input.content_base64), (c) => c.charCodeAt(0));
  records.push({
    path: "/decode",
    method: request.method,
    identity: "synthetic_signed_decoder",
    request_id: input.request_id,
    reservation_id: input.reservation_id,
    source_sha256: input.source_sha256,
  });
  if (
    request.headers.get("authorization") !==
      "Roster-HMAC " + await hmacSha256Hex(decoderSecret, raw)
  ) return json({ error: "roster_decoder_unavailable" }, 401);
  if (await sha(bytes) !== input.source_sha256) {
    return json({ error: "roster_invalid_file" }, 422);
  }
  if (mode === "roster_decoder_reject") {
    return json({ error: "roster_animation_limit" }, 422);
  }
  const receipt = {
    contract_version: 1,
    ok: true,
    request_id: input.request_id,
    reservation_id: input.reservation_id,
    nonce: mode === "roster_bad_nonce" ? crypto.randomUUID() : input.nonce,
    issued_at: input.issued_at,
    kind: input.kind,
    mime: input.mime,
    policy_version: input.policy_version,
    toolchain: ROSTER_DECODER_TOOLCHAIN,
    source_sha256: input.source_sha256,
    source_size: bytes.length,
    derived_sha256: null,
    derived_content: null,
    frames: 1,
    pages: 0,
    pixels: 6,
    expanded_bytes: 24,
    decoder_build_sha256: decoderBuild,
  };
  const text = JSON.stringify(receipt);
  decoderReceipts.set(input.reservation_id, {
    ...receipt,
    receipt_sha256: await sha(text),
  });
  return json({
    payload: text,
    signature: mode === "roster_bad_signature"
      ? "0".repeat(64)
      : await hmacSha256Hex(decoderSecret, text),
  });
});
servers.push(decoder);

for (
  const [key, value] of Object.entries({
    SUPABASE_URL: `http://127.0.0.1:${backend.addr.port}`,
    SUPABASE_ANON_KEY: "qa-anon",
    SUPABASE_SERVICE_ROLE_KEY: "qa-service",
    INTERNAL_FUNCTION_SECRET: internalSecret,
    SEND_SMS_HOOK_SECRET: hookSecret,
    WHATSAPP_CLOUD_DRY_RUN: "false",
    WHATSAPP_GRAPH_API_VERSION: "v25.0",
    WHATSAPP_CLOUD_OTP_AUTH_BUTTON: "true",
    WHATSAPP_AUTH_TEMPLATE_LANGUAGE: "en_US",
    WHATSAPP_CLOUD_API_TOKEN: "qa-disabled-provider",
    WHATSAPP_PHONE_NUMBER_ID: "1234",
    ROSTER_DECODER_URL: `http://127.0.0.1:${decoder.addr.port}/decode`,
    ROSTER_DECODER_SECRET: decoderSecret,
    ROSTER_DECODER_BUILD_SHA256: decoderBuild,
    OPENAI_ROSTER_MODEL: "synthetic-model",
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
  blocked_provider_attempts: providerAttempts,
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
  const sourceNames: string[] = [];
  for await (
    const entry of Deno.readDir(
      new URL("../../supabase/functions", import.meta.url),
    )
  ) {
    if (!entry.isDirectory) continue;
    try {
      if (
        (await Deno.stat(
          new URL(
            `../../supabase/functions/${entry.name}/index.ts`,
            import.meta.url,
          ),
        )).isFile
      ) sourceNames.push(entry.name);
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
  }
  sourceNames.sort();
  report.source_entrypoints = sourceNames;
  check(
    "configured functions exactly match existing executable entrypoints",
    JSON.stringify(names) === JSON.stringify(sourceNames),
  );
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
    JSON.stringify(names) ===
        JSON.stringify([
          "auth-send-whatsapp-otp",
          "collect-notification-operator",
          "dispatch-notifications",
          "ingest-payment-sms",
          "parse-payment-sms",
          "prepare-roster-import",
          "reconciliation-finalize",
          "send-notification",
          "verify-play-integrity",
        ]) && Object.keys(entrypoints).length === names.length,
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
      ...(slug === "reconciliation-finalize"
        ? {
          body: JSON.stringify({
            review_id: "98600000-0000-4000-8000-000000000021",
          }),
        }
        : {}),
      headers: {
        authorization: "Bearer qa-invalid",
        "x-collect-signature": "qa-invalid",
        "x-hook-secret": "qa-invalid",
      },
    });
    check(
      invalid.label,
      invalid.http_status === 401 &&
        invalid.dependencies.every((r) =>
          r.path === "/auth/v1/user" ||
          (slug === "reconciliation-finalize" &&
            r.path === "/rest/v1/rpc/authorize_reconciliation_finalization_v2")
        ),
      invalid,
    );
  }
  for (
    const slug of ["collect-notification-operator", "prepare-roster-import"]
  ) {
    mode = "denied";
    const denied = await request(slug, `${slug}: member cannot operate`, {
      headers: { authorization: userAuthorization },
      body: JSON.stringify(
        slug === "prepare-roster-import" ? rosterInput() : { action: "health" },
      ),
    });
    check(
      denied.label,
      denied.http_status === 403 &&
        denied.dependencies.every((r) =>
          [
            "/auth/v1/user",
            "/rest/v1/rpc/admin_current_user",
            "/rest/v1/rpc/reserve_roster_resources",
          ].includes(
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
      headers: { authorization: userAuthorization },
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
      headers: { authorization: userAuthorization },
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
  const deterministicInput = rosterInput();
  const roster = await request(
    "prepare-roster-import",
    "roster: approved deterministic preview",
    {
      headers: { authorization: userAuthorization },
      body: JSON.stringify(deterministicInput),
    },
  );
  check(
    roster.label,
    roster.http_status === 200 &&
      (roster.response as Record<string, unknown>)?.processing_method ===
        "deterministic",
    roster,
  );

  check(
    "roster: resource reservation and immutable preview finish in order",
    JSON.stringify(roster.dependencies.map((r) => r.path)) ===
        JSON.stringify([
          "/auth/v1/user",
          "/rest/v1/rpc/reserve_roster_resources",
          "/rest/v1/rpc/create_roster_import_source",
          "/rest/v1/rpc/complete_roster_import_preview",
          "/rest/v1/rpc/finish_roster_resources",
        ]) &&
      (roster.response as Record<string, unknown>)?.requires_human_review ===
        true &&
      (roster.response as Record<string, unknown>)?.can_submit === false,
    roster,
  );
  const replay = await request(
    "prepare-roster-import",
    "roster: finished preview replay performs no decoder/provider work",
    {
      headers: { authorization: userAuthorization },
      body: JSON.stringify(deterministicInput),
    },
  );
  check(
    replay.label,
    replay.http_status === 200 &&
      JSON.stringify(replay.response) === JSON.stringify(roster.response) &&
      JSON.stringify(replay.dependencies.map((r) => r.path)) ===
        JSON.stringify([
          "/auth/v1/user",
          "/rest/v1/rpc/reserve_roster_resources",
          "/rest/v1/rpc/create_roster_import_source",
        ]),
    replay,
  );
  for (
    const [scenario, status, code, expected] of [
      ["roster_quota", 429, "roster_resource_limit", [
        "/auth/v1/user",
        "/rest/v1/rpc/reserve_roster_resources",
      ]],
      ["roster_bad_budget", 503, "roster_budget_receipt_invalid", [
        "/auth/v1/user",
        "/rest/v1/rpc/reserve_roster_resources",
      ]],
      ["roster_bad_nonce", 503, "roster_decoder_receipt_invalid", [
        "/auth/v1/user",
        "/rest/v1/rpc/reserve_roster_resources",
        "/decode",
        "/rest/v1/rpc/finish_roster_resources",
      ]],
      ["roster_bad_signature", 503, "roster_decoder_receipt_invalid", [
        "/auth/v1/user",
        "/rest/v1/rpc/reserve_roster_resources",
        "/decode",
        "/rest/v1/rpc/finish_roster_resources",
      ]],
      ["roster_decoder_reject", 422, "roster_animation_limit", [
        "/auth/v1/user",
        "/rest/v1/rpc/reserve_roster_resources",
        "/decode",
        "/rest/v1/rpc/finish_roster_resources",
      ]],
      ["roster_bad_verification", 503, "roster_receipt_invalid", [
        "/auth/v1/user",
        "/rest/v1/rpc/reserve_roster_resources",
        "/decode",
        "/rest/v1/rpc/verify_roster_source_integrity",
        "/rest/v1/rpc/finish_roster_resources",
      ]],
      ["normal", 503, "roster_extraction_unavailable", [
        "/auth/v1/user",
        "/rest/v1/rpc/reserve_roster_resources",
        "/decode",
        "/rest/v1/rpc/verify_roster_source_integrity",
        "/rest/v1/rpc/create_roster_import_source",
        "/rest/v1/rpc/fail_roster_import_preview",
        "/rest/v1/rpc/finish_roster_resources",
      ]],
    ] as const
  ) {
    mode = scenario;
    const before = providerAttempts.length;
    const result = await request(
      "prepare-roster-import",
      `roster: ${scenario} enforces verification before transmission`,
      {
        headers: { authorization: userAuthorization },
        body: JSON.stringify(rosterImage()),
      },
    );
    check(
      result.label,
      result.http_status === status &&
        (result.response as Record<string, unknown>)?.error === code &&
        JSON.stringify(result.dependencies.map((r) => r.path)) ===
          JSON.stringify(expected) &&
        providerAttempts.length === before,
      result,
    );
  }
  mode = "normal";

  // The product owner retired the three bank-ingestion routes.
  // Preserve the boundary check as absence of source/config/listener, since
  // invoking deleted code would falsely inflate active surface acceptance.
  for (
    const retired of [
      "ingest-bank-email",
      "ingest-bank-sms",
      "ingest-bank-statement",
    ]
  ) {
    let sourceAbsent = false;
    try {
      await Deno.stat(
        new URL(
          `../../supabase/functions/${retired}/index.ts`,
          import.meta.url,
        ),
      );
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) sourceAbsent = true;
      else throw error;
    }
    check(
      `retired ${retired}: source/config/listener absent`,
      sourceAbsent && !names.includes(retired) && !(retired in entrypoints),
    );
  }

  const otpBody = JSON.stringify({
    user: { phone: "+250788991001" },
    sms: { otp: "987654" },
  });
  const webhook = new Webhook(hookSecret);
  function signedOtp(id: string, offset = 0, mutate = false) {
    const when = new Date(Date.now() + offset * 1000);
    return {
      body: mutate ? otpBody + " " : otpBody,
      headers: {
        "webhook-id": id,
        "webhook-timestamp": String(Math.floor(when.getTime() / 1000)),
        "webhook-signature": webhook.sign(id, when, otpBody),
      },
    };
  }
  for (
    const [label, offset, mutate] of [["valid", 0, false], [
      "expired",
      -601,
      false,
    ], ["modified-body", 0, true]] as const
  ) {
    counter = 0;
    mode = "already_accepted";
    const before = providerAttempts.length;
    const result = await request(
      "auth-send-whatsapp-otp",
      `OTP signed hook: ${label}`,
      signedOtp("qa-hook-" + label + "-" + crypto.randomUUID(), offset, mutate),
    );
    check(
      result.label,
      result.http_status === (label === "valid" ? 200 : 401) &&
        providerAttempts.length === before && (label === "valid"
          ? result.dependencies.map((r) =>
            r.path
          ).join() ===
            "/rest/v1/rpc/reserve_signed_otp_v3"
          : result.dependencies.length === 0),
      {
        ...result,
        model:
          "valid case returns a recorded accepted attempt; no provider dispatch",
      },
    );
  }
  mode = "normal";
  const legacy = await request(
    "auth-send-whatsapp-otp",
    "OTP legacy static secret cannot reserve or send",
    { headers: { "x-hook-secret": hookSecret }, body: otpBody },
  );
  check(
    legacy.label,
    legacy.http_status === 401 && legacy.dependencies.length === 0,
    legacy,
  );
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
    const before = providerAttempts.length;
    const result = await request(
      "auth-send-whatsapp-otp",
      `OTP limiter ${failure}: fails closed`,
      signedOtp("qa-failure-" + crypto.randomUUID()),
    );
    check(
      result.label,
      result.http_status === 503 && providerAttempts.length === before &&
        result.dependencies.length === 1 &&
        result.dependencies[0].path === "/rest/v1/rpc/reserve_signed_otp_v3",
      result,
    );
  }
  mode = "reserve_timeout";
  counter = 0;
  const timeoutStart = performance.now();
  const timed = await request(
    "auth-send-whatsapp-otp",
    "OTP durable reservation timeout aborts without sending",
    signedOtp("qa-timeout-" + crypto.randomUUID()),
  );
  const elapsed = performance.now() - timeoutStart;
  check(
    timed.label,
    timed.http_status === 503 && elapsed < 5000 &&
      timed.dependencies.length === 1,
    { ...timed, elapsed_ms: elapsed },
  );
  mode = "normal";
  counter = 5;
  const limit = await request(
    "auth-send-whatsapp-otp",
    "OTP sixth request refused",
    signedOtp("qa-limit-" + crypto.randomUUID()),
  );
  check(limit.label, limit.http_status === 429 && counter === 5, limit);
  counter = 4;
  const beforeConcurrent = providerAttempts.length;
  const concurrent = await Promise.all(
    Array.from({ length: 8 }, (_, i) =>
      request(
        "auth-send-whatsapp-otp",
        `OTP concurrent ${i}`,
        signedOtp("qa-concurrent-" + i + "-" + crypto.randomUUID()),
      )),
  );
  check(
    "OTP concurrency: one remaining reservation allows only one transport attempt",
    concurrent.filter((r) => r.http_status === 503).length === 1 &&
      concurrent.filter((r) => r.http_status === 429).length === 7 &&
      counter === 5 && providerAttempts.length - beforeConcurrent === 1,
    {
      statuses: concurrent.map((r) => r.http_status),
      recorded_counter: counter,
      model:
        "recording v3 dependency; real SQL races verified in the separate145 packet; network permissions block the single transport attempt",
    },
  );
  for (const scenario of ["normal", "lost_record_ack"]) {
    mode = scenario;
    counter = 0;
    const id = "qa-no-resend-" + crypto.randomUUID(),
      before = providerAttempts.length;
    const first = await request(
      "auth-send-whatsapp-otp",
      `OTP ${scenario}: denied provider is unresolved`,
      signedOtp(id),
    );
    const replay = await request(
      "auth-send-whatsapp-otp",
      `OTP ${scenario}: replay cannot resend`,
      signedOtp(id),
    );
    check(
      replay.label,
      first.http_status === 503 && replay.http_status === 503 &&
        counter === 1 && providerAttempts.length - before === 1 &&
        replay.dependencies.map((r) => r.path).join() ===
          "/rest/v1/rpc/reserve_signed_otp_v3",
      { first, replay },
    );
  }
  mode = "normal";
  report.status = checks.every((r) => r.status === "pass") ? "pass" : "fail";
} catch (error) {
  report.status = "fail";
  report.error = error instanceof Error ? error.message : String(error);
} finally {
  Deno.serve = realServe;
  globalThis.fetch = originalFetch;
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

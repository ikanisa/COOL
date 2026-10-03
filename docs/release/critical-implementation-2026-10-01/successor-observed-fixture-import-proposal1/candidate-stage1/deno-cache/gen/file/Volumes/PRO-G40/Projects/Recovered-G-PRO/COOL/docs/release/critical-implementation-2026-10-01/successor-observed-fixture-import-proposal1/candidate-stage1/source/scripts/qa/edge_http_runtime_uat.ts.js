// Real loopback HTTP servers load the unmodified Edge entrypoints. Only their
// Auth/PostgREST dependency is a recording synthetic server; provider network
// access is denied by the launcher. This is not hosted or provider acceptance.
import { Webhook } from "npm:standardwebhooks@1.0.0";
import { hmacSha256Hex } from "../../supabase/functions/_shared/hmac.ts";
import { normalizeRosterCandidates } from "../../supabase/functions/_shared/roster_import.ts";
import { ROSTER_DECODER_TOOLCHAIN } from "../../supabase/functions/_shared/roster_decoder.ts";
import { syntheticRosterAiApproval } from "../../supabase/functions/_shared/roster_ai_dispatch_test_fixture.ts";
// Literal imports let the frozen graph bind the same real handlers that are
// loaded after Deno.serve is redirected to the owned loopback listeners. A
// computed URL leaves SDK redirect aliases undiscovered by Deno 2.5.6's graph.
const entrypointLoaders = {
  "auth-send-whatsapp-otp": ()=>import("../../supabase/functions/auth-send-whatsapp-otp/index.ts"),
  "collect-android-gateway": ()=>import("../../supabase/functions/collect-android-gateway/index.ts"),
  "collect-notification-operator": ()=>import("../../supabase/functions/collect-notification-operator/index.ts"),
  "collect-receipt-exception-worker": ()=>import("../../supabase/functions/collect-receipt-exception-worker/index.ts"),
  "collect-receipt-successor-gateway": ()=>import("../../supabase/functions/collect-receipt-successor-gateway/index.ts"),
  "collect-receipt-supervisor": ()=>import("../../supabase/functions/collect-receipt-supervisor/index.ts"),
  "dispatch-notifications": ()=>import("../../supabase/functions/dispatch-notifications/index.ts"),
  "ingest-payment-sms": ()=>import("../../supabase/functions/ingest-payment-sms/index.ts"),
  "parse-payment-sms": ()=>import("../../supabase/functions/parse-payment-sms/index.ts"),
  "prepare-roster-import": ()=>import("../../supabase/functions/prepare-roster-import/index.ts"),
  "reconciliation-finalize": ()=>import("../../supabase/functions/reconciliation-finalize/index.ts"),
  "send-notification": ()=>import("../../supabase/functions/send-notification/index.ts"),
  "verify-play-integrity": ()=>import("../../supabase/functions/verify-play-integrity/index.ts")
};
const userId = "98600000-0000-4000-8000-000000000001";
const sessionId = "98600000-0000-4000-8000-000000000011";
const userToken = "e30." + btoa(JSON.stringify({
  sub: userId,
  session_id: sessionId,
  role: "authenticated"
})).replaceAll("=", "").replaceAll("+", "-").replaceAll("/", "_") + ".synthetic";
const userAuthorization = "Bearer " + userToken;
const decoderSecret = "synthetic-loopback-only-" + crypto.randomUUID();
const decoderBuild = "d".repeat(64);
const png = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAFElEQVR4nGOUS+lhYGBgYgADKAUAE/ABFCFAuesAAAAASUVORK5CYII=";
const providerAttempts = [];
const originalFetch = globalThis.fetch;
globalThis.fetch = (input, options)=>{
  const url = input instanceof Request ? input.url : String(input);
  if (url.startsWith("https://graph.facebook.com/") || url.startsWith("https://api.openai.com/")) providerAttempts.push(url);
  return originalFetch(input, options);
};
const internalSecret = crypto.randomUUID();
const hookSecret = btoa(crypto.randomUUID() + crypto.randomUUID());
const realServe = Deno.serve;
const servers = [];
const controllers = [];
const records = [];
const checks = [];
const entrypoints = {};
const starts = {};
let mode = "normal";
let counter = 0;
const otpAttempts = new Map();
const rosterBudgets = new Map();
const rosterSources = new Map();
const decoderReceipts = new Map();
async function sha(text) {
  const input = typeof text === "string" ? new TextEncoder().encode(text) : text;
  return [
    ...new Uint8Array(await crypto.subtle.digest("SHA-256", input))
  ].map((v)=>v.toString(16).padStart(2, "0")).join("");
}
function rosterInput(patch = {}) {
  return {
    contract_version: 1,
    request_id: crypto.randomUUID(),
    source_type: "text",
    content: "Member name,MoMo name,MoMo number\nAline Uwase,ALINE UWASE,0788991001",
    ...patch
  };
}
function rosterImage(patch = {}) {
  return rosterInput({
    source_type: "image",
    content: undefined,
    filename: "fixture.png",
    mime_type: "image/png",
    content_base64: png,
    ai_consent: true,
    consent_version: "roster-ai-extraction-v1",
    ...patch
  });
}
function rosterPreview(source, candidates) {
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
      derived_assurance: source.p_source_kind === "xlsx" ? "client_derived_tsv" : null,
      extraction_id: source.extraction_id,
      ai_consent: source.p_ai_consent,
      consent_version: source.p_consent_version,
      parser_version: "collect-roster-parser-v1",
      schema_version: "collect-roster-rows-v1"
    },
    revision_id: crypto.randomUUID(),
    parent_revision_id: null,
    revision_number: 1,
    reviewed_rows_sha256: "a".repeat(64),
    ...normalizeRosterCandidates(candidates),
    can_submit: false,
    requires_human_review: true,
    processing_method: source.p_ai_consent ? "openai_structured_extraction" : "deterministic",
    model: source.p_ai_consent ? "synthetic-model" : null,
    expires_at: "2099-01-01T00:00:00Z"
  };
}
function json(value, status = 200, headers = {}) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json",
      ...headers
    }
  });
}
const backendController = new AbortController();
controllers.push(backendController);
const backend = realServe({
  hostname: "127.0.0.1",
  port: 0,
  signal: backendController.signal,
  onListen () {}
}, async (request)=>{
  const path = new URL(request.url).pathname;
  const text = await request.text();
  const payload = text ? JSON.parse(text) : null;
  const authorization = request.headers.get("authorization");
  records.push({
    path,
    method: request.method,
    payload,
    identity: authorization === userAuthorization ? "synthetic_user" : authorization === "Bearer qa-service" ? "synthetic_service" : "unrecognized"
  });
  if (path === "/auth/v1/user") {
    if (authorization !== userAuthorization) {
      return json({
        message: "invalid synthetic token"
      }, 401);
    }
    return json({
      id: userId,
      aud: "authenticated",
      role: "authenticated",
      created_at: new Date().toISOString(),
      app_metadata: {},
      user_metadata: {}
    });
  }
  if (path === "/rest/v1/rpc/authorize_reconciliation_finalization_v2") {
    return authorization === userAuthorization ? json(true) : json({
      code: "PGRST301",
      message: "Synthetic invalid JWT"
    }, 401);
  }
  if (path === "/rest/v1/rpc/admin_current_user") {
    return json({
      user_id: userId,
      permissions: mode === "denied" ? [] : [
        "notifications.read",
        "notifications.manage",
        "users.read",
        "collections.moderate"
      ]
    });
  }
  if (path === "/rest/v1/feature_flags") return json({
    enabled: true
  });
  if (path.endsWith("/reserve_signed_otp_v3")) {
    const args = payload;
    if (mode === "count_error" || mode === "insert_error") {
      return json({
        code: "QA_FAILURE",
        message: "Synthetic durable reservation unavailable"
      }, 503);
    }
    if (mode === "missing_rpc") {
      return json({
        code: "PGRST202",
        message: "RPC not deployed"
      }, 404);
    }
    if (mode === "malformed_reservation") return json({
      allowed: true
    });
    if (mode === "reserve_timeout") {
      await new Promise((resolve)=>setTimeout(resolve, 4500));
      return json({
        allowed: true
      });
    }
    const key = String(args.p_hook_id), existing = otpAttempts.get(key);
    if (existing) {
      if (existing.payload_hash !== args.p_payload_hash) {
        return json({
          code: "22023",
          message: "otp_payload_conflict"
        }, 400);
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
      can_send: mode !== "already_accepted"
    };
    otpAttempts.set(key, receipt);
    return json(receipt);
  }
  if (path.endsWith("/begin_signed_otp_v3") || path.endsWith("/record_signed_otp_v3")) {
    const args = payload, key = String(args.p_hook_id), existing = otpAttempts.get(key);
    if (!existing || existing.payload_hash !== args.p_payload_hash || existing.attempt_id !== args.p_attempt_id || existing.revision !== args.p_revision) return json({
      code: "22023",
      message: "otp_identity_conflict"
    }, 400);
    if (path.endsWith("/begin_signed_otp_v3")) {
      const receipt = {
        ...existing,
        state: "sending",
        revision: Number(existing.revision) + 1,
        can_send: false
      };
      otpAttempts.set(key, receipt);
      return json({
        ...receipt,
        started: true
      });
    }
    if (mode === "lost_record_ack") {
      return json({
        code: "QA_FAILURE",
        message: "Synthetic recording acknowledgement lost"
      }, 503);
    }
    const receipt = {
      ...existing,
      state: args.p_outcome,
      revision: Number(existing.revision) + 1,
      can_send: false
    };
    otpAttempts.set(key, receipt);
    return json(receipt);
  }
  if (path.endsWith("/reserve_roster_resources")) {
    const args = payload;
    if (mode === "denied") {
      return json({
        code: "42501",
        message: "roster_import_forbidden"
      }, 403);
    }
    if (mode === "roster_quota") {
      return json({
        code: "P0001",
        message: "roster_resource_limit"
      }, 429);
    }
    const existing = rosterBudgets.get(String(args.p_request_id));
    if (existing) return json({
      ...existing,
      replayed: true
    });
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
      expires_at: "2099-01-01T00:00:00Z"
    };
    rosterBudgets.set(String(args.p_request_id), receipt);
    return json(mode === "roster_bad_budget" ? {
      ...receipt,
      actor_id: crypto.randomUUID()
    } : receipt);
  }
  if (path.endsWith("/verify_roster_source_integrity")) {
    const args = payload, proof = decoderReceipts.get(String(args.p_reservation_id));
    if (!proof || proof.receipt_sha256 !== args.p_decoder_receipt_sha256 || proof.decoder_build_sha256 !== args.p_decoder_build_sha256 || args.p_actor_id !== userId || args.p_session_id !== sessionId) {
      return json({
        code: "22023",
        message: "roster_source_verification_invalid"
      }, 400);
    }
    return json({
      contract_version: 1,
      ok: true,
      reservation_id: args.p_reservation_id,
      source_sha256: proof.source_sha256,
      derived_sha256: proof.derived_sha256,
      decoder_receipt_sha256: mode === "roster_bad_verification" ? "f".repeat(64) : args.p_decoder_receipt_sha256,
      verified: true
    });
  }
  if (path.endsWith("/finish_roster_resources")) {
    const args = payload, budget = [
      ...rosterBudgets.values()
    ].find((r)=>r.reservation_id === args.p_reservation_id);
    if (!budget || args.p_actor_id !== userId || args.p_session_id !== sessionId) return json({
      code: "42501",
      message: "roster_import_forbidden"
    }, 403);
    budget.state = "finished";
    return json({
      contract_version: 1,
      ok: true,
      reservation_id: args.p_reservation_id,
      outcome: args.p_outcome,
      charged: true
    });
  }
  if (path.endsWith("/create_roster_import_source")) {
    const args = payload, existing = rosterSources.get(String(args.p_request_id));
    const source = existing ?? {
      ...args,
      import_id: crypto.randomUUID(),
      extraction_id: args.p_ai_consent ? crypto.randomUUID() : null,
      state: "awaiting_preview",
      completed_preview: null,
      error_code: null
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
      derived_assurance: args.p_source_kind === "xlsx" ? "client_derived_tsv" : null,
      state: source.state,
      replayed: !!existing,
      completed_preview: source.completed_preview,
      error_code: source.error_code
    });
  }
  if (path.endsWith("/complete_roster_import_preview") || path.endsWith("/fail_roster_import_preview")) {
    const args = payload, source = [
      ...rosterSources.values()
    ].find((r)=>r.import_id === args.p_import_id);
    if (!source || args.p_actor_id !== userId || args.p_session_id !== sessionId) return json({
      code: "42501",
      message: "roster_import_forbidden"
    }, 403);
    if (path.endsWith("/fail_roster_import_preview")) {
      source.state = "failed";
      source.error_code = args.p_error_code;
      return json({
        contract_version: 1,
        ok: true,
        import_id: source.import_id,
        state: "failed",
        error_code: args.p_error_code,
        replayed: false
      });
    }
    source.completed_preview = rosterPreview(source, args.p_candidates);
    source.state = "preview_ready";
    return json(source.completed_preview);
  }
  if (path === "/rest/v1/rpc/claim_notification_deliveries") return json([]);
  if (path === "/rest/v1/rpc/collect_notification_health_v2") {
    return json({
      pending: 0
    });
  }
  if (path === "/rest/v1/rpc/attested_sms_contract_version") {
    return json(mode.startsWith("receipt_") ? 2 : 1);
  }
  if (path === "/rest/v1/rpc/accept_attested_receipt_v2") {
    const args = payload;
    return json({
      contract_version: 2,
      stored: true,
      raw_sms_id: crypto.randomUUID(),
      client_envelope_id: args.p_client_envelope_id,
      owner_user_id: mode === "receipt_bad_ack" ? crypto.randomUUID() : args.p_receiver_user_id,
      body_sha256: args.p_body_hash
    });
  }
  if (path === "/functions/v1/parse-payment-sms") {
    return json({
      ok: mode !== "receipt_deferred"
    });
  }
  if (path === "/rest/v1/rpc/record_operational_metric_v1") {
    if (mode === "receipt_metric_error") {
      return json({
        code: "synthetic_metric_failure",
        message: "secret-provider-canary"
      }, 500);
    }
    if (mode === "receipt_metric_timeout") {
      await new Promise((resolve)=>setTimeout(resolve, 500));
    }
    return json(true);
  }
  if (path === "/rest/v1/rpc/ingest_bank_evidence") {
    return json({
      id: "qa-evidence",
      status: "recorded"
    });
  }
  if (path === "/rest/v1/rpc/enqueue_notification_event") return json(null);
  return json({
    code: "QA_UNEXPECTED_BACKEND_PATH",
    message: path
  }, 500);
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
  onListen () {}
}, async (request)=>{
  const raw = await request.text(), input = JSON.parse(raw), bytes = Uint8Array.from(atob(input.content_base64), (c)=>c.charCodeAt(0));
  records.push({
    path: "/decode",
    method: request.method,
    identity: "synthetic_signed_decoder",
    request_id: input.request_id,
    reservation_id: input.reservation_id,
    source_sha256: input.source_sha256
  });
  if (request.headers.get("authorization") !== "Roster-HMAC " + await hmacSha256Hex(decoderSecret, raw)) return json({
    error: "roster_decoder_unavailable"
  }, 401);
  if (await sha(bytes) !== input.source_sha256) {
    return json({
      error: "roster_invalid_file"
    }, 422);
  }
  if (mode === "roster_decoder_reject") {
    return json({
      error: "roster_animation_limit"
    }, 422);
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
    decoder_build_sha256: decoderBuild
  };
  const text = JSON.stringify(receipt);
  decoderReceipts.set(input.reservation_id, {
    ...receipt,
    receipt_sha256: await sha(text)
  });
  return json({
    payload: text,
    signature: mode === "roster_bad_signature" ? "0".repeat(64) : await hmacSha256Hex(decoderSecret, text)
  });
});
servers.push(decoder);
// Synthetic approval only: bind the actual local fixture receipt tuple.
// It represents no owner/vendor acceptance and does not enable provider access.
const decoderUrl = `http://127.0.0.1:${decoder.addr.port}/decode`;
const rosterModel = "synthetic-model";
const rosterApproval = await syntheticRosterAiApproval(rosterModel, decoderUrl, decoderBuild);
const rosterApprovalEnvironment = Object.freeze({
  ROSTER_AI_APPROVAL_JSON: rosterApproval.aiApprovalJson,
  ROSTER_AI_APPROVAL_SHA256: rosterApproval.aiApprovalSha256,
  OPENAI_ORGANIZATION_ID: rosterApproval.openAiOrganizationId,
  OPENAI_PROJECT_ID: rosterApproval.openAiProjectId
});
for (const [key, value] of Object.entries({
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
  ROSTER_DECODER_URL: decoderUrl,
  ROSTER_DECODER_SECRET: decoderSecret,
  ROSTER_DECODER_BUILD_SHA256: decoderBuild,
  OPENAI_ROSTER_MODEL: rosterModel,
  ...rosterApprovalEnvironment,
  WHATSAPP_AUTH_TEMPLATE_NAME: "qa_disabled_provider"
}))Deno.env.set(key, value);
const report = {
  started_at: new Date().toISOString(),
  final_acceptance: false,
  mode: "real_edge_http_with_recording_synthetic_auth_postgrest_and_disabled_providers",
  checks,
  entrypoints,
  dependency_records: records,
  blocked_provider_attempts: providerAttempts,
  limitations: [
    "No platform verify_jwt gateway or real Auth sign-in",
    "Synthetic dependency responses do not prove SQL persistence or RLS",
    "No WhatsApp/APNs/FCM/Play/OpenAI/provider delivery or acceptance"
  ]
};
function check(label, passed, evidence = {}) {
  checks.push({
    label,
    status: passed ? "pass" : "fail",
    ...evidence
  });
  console.log("QA_EDGE_PROGRESS=" + JSON.stringify({
    label,
    passed,
    dependency_count: records.length
  }));
}
async function request(slug, label, options = {}) {
  const start = records.length;
  const response = await fetch(entrypoints[slug], {
    method: options.method ?? "POST",
    body: options.body ?? "{}",
    headers: {
      "content-type": "application/json",
      ...options.headers
    },
    signal: AbortSignal.timeout(10_000)
  });
  const text = await response.text();
  let body = null;
  try {
    body = JSON.parse(text);
  } catch  {}
  return {
    label,
    http_status: response.status,
    response: body,
    cors: response.headers.get("access-control-allow-origin"),
    dependencies: records.slice(start),
    no_store: response.headers.get("cache-control")?.includes("no-store") ?? false
  };
}
try {
  const config = await Deno.readTextFile(new URL("../../supabase/config.toml", import.meta.url));
  const names = [
    ...config.matchAll(/^\[functions\.([^\]]+)\]/gm)
  ].map((match)=>match[1]).sort();
  report.configured_functions = names;
  const sourceNames = [];
  for await (const entry of Deno.readDir(new URL("../../supabase/functions", import.meta.url))){
    if (!entry.isDirectory) continue;
    try {
      if ((await Deno.stat(new URL(`../../supabase/functions/${entry.name}/index.ts`, import.meta.url))).isFile) sourceNames.push(entry.name);
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
  }
  sourceNames.sort();
  report.source_entrypoints = sourceNames;
  const loaderNames = Object.keys(entrypointLoaders).sort();
  report.literal_loader_entrypoints = loaderNames;
  check("configured functions exactly match existing executable entrypoints", JSON.stringify(names) === JSON.stringify(sourceNames));
  const loaderParity = names.length > 0 && new Set(names).size === names.length && JSON.stringify(loaderNames) === JSON.stringify(names) && JSON.stringify(loaderNames) === JSON.stringify(sourceNames);
  check("literal loaders exactly match unique configured source entrypoints", loaderParity);
  if (!loaderParity) {
    throw new Error("Literal loader/config/source entrypoint parity required");
  }
  check("external provider network denied", (await Deno.permissions.query({
    name: "net",
    host: "graph.facebook.com:443"
  })).state === "denied");
  const infrastructureServerCount = servers.length;
  for (const slug of names){
    // Change only the listening address. The repository's actual handler runs.
    Deno.serve = (handler)=>{
      const controller = new AbortController();
      controllers.push(controller);
      const server = realServe({
        hostname: "127.0.0.1",
        port: 0,
        signal: controller.signal,
        onListen () {}
      }, handler);
      servers.push(server);
      starts[slug] = (starts[slug] ?? 0) + 1;
      entrypoints[slug] = `http://127.0.0.1:${server.addr.port}`;
      return server;
    };
    await entrypointLoaders[slug]();
  }
  Deno.serve = realServe;
  check("every configured entrypoint started exactly once", JSON.stringify(Object.keys(entrypoints).sort()) === JSON.stringify(names) && names.every((slug)=>starts[slug] === 1) && servers.length - infrastructureServerCount === names.length);
  for (const slug of names){
    if (slug === "collect-receipt-successor-gateway") {
      // The successor wire has its own audience/family and includes a false
      // send-authority field even in schema/method refusals. These unsigned
      // presence checks must stop before key lookup or any successor RPC.
      const body = JSON.stringify({
        contract_version: 1,
        protocol_family: "receipt_successor",
        audience: "collect-receipt-successor-gateway",
        action: "dispatch_grant",
        device_id: userId,
        request_id: crypto.randomUUID(),
        issued_at: new Date().toISOString(),
        payload: {}
      });
      for (const method of [
        "OPTIONS",
        "PUT"
      ]){
        const refusal = await request(slug, `${slug}: successor protocol refuses ${method}`, {
          method
        });
        check(refusal.label, refusal.http_status === 405 && refusal.cors === null && refusal.no_store && refusal.dependencies.length === 0 && JSON.stringify(refusal.response) === JSON.stringify({
          ok: false,
          code: "GATEWAY_POST_REQUIRED",
          send_authority: false
        }), refusal);
      }
      for (const [label, requestBody, headers] of [
        [
          "empty unsigned envelope",
          "{}",
          {}
        ],
        [
          "unsigned successor envelope",
          body,
          {}
        ],
        [
          "bearer cannot replace successor signature",
          body,
          {
            authorization: "Bearer qa-invalid"
          }
        ],
        [
          "malformed successor signature",
          body,
          {
            "X-Collect-Gateway-Key-Id": "a".repeat(64),
            "X-Collect-Gateway-Signature": btoa("malformed")
          }
        ]
      ]){
        const refusal = await request(slug, `${slug}: ${label}`, {
          body: requestBody,
          headers
        });
        check(refusal.label, refusal.http_status === 400 && refusal.cors === null && refusal.no_store && refusal.dependencies.length === 0 && JSON.stringify(refusal.response) === JSON.stringify({
          ok: false,
          code: "GATEWAY_REQUEST_INVALID",
          send_authority: false
        }), refusal);
      }
      continue;
    }
    if (slug === "collect-android-gateway" || slug === "collect-receipt-supervisor") {
      // Dedicated signed protocols do not accept browser CORS or bearer Auth.
      const supervisor = slug === "collect-receipt-supervisor";
      const prefix = supervisor ? "SUPERVISOR" : "GATEWAY";
      const header = supervisor ? "Supervisor" : "Gateway";
      const body = JSON.stringify(supervisor ? {
        contract_version: 1,
        audience: "collect.receipt-supervisor.v1/lhbowpbcpwoiparwnwgt",
        action: "prove_key",
        principal_id: userId,
        request_id: crypto.randomUUID(),
        issued_at: new Date().toISOString(),
        payload: {}
      } : {
        contract_version: 1,
        action: "reconcile",
        device_id: userId,
        request_id: crypto.randomUUID(),
        issued_at: new Date().toISOString(),
        payload: {
          target_request_id: crypto.randomUUID()
        }
      });
      for (const method of [
        "OPTIONS",
        "PUT"
      ]){
        const refusal = await request(slug, `${slug}: signed protocol refuses ${method}`, {
          method
        });
        check(refusal.label, refusal.http_status === 405 && refusal.cors === null && refusal.no_store && refusal.dependencies.length === 0 && JSON.stringify(refusal.response) === JSON.stringify({
          ok: false,
          code: prefix + (supervisor ? "_METHOD_REFUSED" : "_POST_REQUIRED")
        }), refusal);
      }
      for (const [label, headers] of [
        [
          "unsigned envelope",
          {}
        ],
        [
          "bearer cannot replace dedicated signature",
          {
            authorization: "Bearer qa-invalid"
          }
        ],
        [
          "malformed dedicated signature",
          {
            ["X-Collect-" + header + "-Key-Id"]: "a".repeat(64),
            ["X-Collect-" + header + "-Signature"]: btoa("malformed")
          }
        ]
      ]){
        const refusal = await request(slug, `${slug}: ${label}`, {
          body,
          headers
        });
        check(refusal.label, refusal.http_status === 400 && refusal.cors === null && refusal.no_store && refusal.dependencies.length === 0 && JSON.stringify(refusal.response) === JSON.stringify({
          ok: false,
          code: prefix + "_REQUEST_INVALID"
        }), refusal);
      }
      continue;
    }
    if (slug === "collect-receipt-exception-worker") {
      // This is a scheduler-only endpoint, not a browser/Auth endpoint. Its
      // production index refuses to configure a worker credential for the
      // loopback SUPABASE_URL. Preserve that binding and test its exact
      // unconfigured refusal; configured worker/HTTP/ACK paths have their
      // separately bound actual handler and observed SQL decoder suite.
      for (const method of [
        "OPTIONS",
        "PUT"
      ]){
        const refused = await request(slug, `${slug}: scheduler method ${method}`, {
          method
        });
        check(refused.label, refused.http_status === 405 && refused.cors === null && refused.no_store && refused.dependencies.length === 0 && JSON.stringify(refused.response) === JSON.stringify({
          error: "METHOD_NOT_ALLOWED"
        }), refused);
      }
      for (const [label, headers] of [
        [
          "missing worker credential",
          {}
        ],
        [
          "bearer cannot configure loopback worker",
          {
            authorization: "Bearer qa-invalid"
          }
        ]
      ]){
        const refused = await request(slug, `${slug}: ${label}`, {
          headers
        });
        check(refused.label, refused.http_status === 503 && refused.cors === null && refused.no_store && refused.dependencies.length === 0 && JSON.stringify(refused.response) === JSON.stringify({
          error: "WORKER_UNCONFIGURED"
        }), refused);
      }
      continue;
    }
    const preflight = await request(slug, `${slug}: preflight`, {
      method: "OPTIONS"
    });
    check(preflight.label, preflight.http_status === 200 && preflight.cors === "*" && preflight.dependencies.length === 0, preflight);
    const method = await request(slug, `${slug}: wrong method`, {
      method: "PUT"
    });
    check(method.label, method.http_status === 405 && method.dependencies.length === 0, method);
    const missing = await request(slug, `${slug}: missing authentication`);
    check(missing.label, missing.http_status === 401 && missing.dependencies.length === 0, missing);
    const invalid = await request(slug, `${slug}: invalid authentication`, {
      ...slug === "reconciliation-finalize" ? {
        body: JSON.stringify({
          review_id: "98600000-0000-4000-8000-000000000021"
        })
      } : {},
      headers: {
        authorization: "Bearer qa-invalid",
        "x-collect-signature": "qa-invalid",
        "x-hook-secret": "qa-invalid"
      }
    });
    check(invalid.label, invalid.http_status === 401 && invalid.dependencies.every((r)=>r.path === "/auth/v1/user" || slug === "reconciliation-finalize" && r.path === "/rest/v1/rpc/authorize_reconciliation_finalization_v2"), invalid);
  }
  for (const slug of [
    "collect-notification-operator",
    "prepare-roster-import"
  ]){
    mode = "denied";
    const denied = await request(slug, `${slug}: member cannot operate`, {
      headers: {
        authorization: userAuthorization
      },
      body: JSON.stringify(slug === "prepare-roster-import" ? rosterInput() : {
        action: "health"
      })
    });
    check(denied.label, denied.http_status === 403 && denied.dependencies.every((r)=>[
        "/auth/v1/user",
        "/rest/v1/rpc/admin_current_user",
        "/rest/v1/rpc/reserve_roster_resources"
      ].includes(String(r.path))), denied);
    mode = "normal";
  }
  const health = await request("collect-notification-operator", "operator: permission-bearing identity reaches health", {
    headers: {
      authorization: userAuthorization
    },
    body: JSON.stringify({
      action: "health",
      operator_user_id: "forged"
    })
  });
  check(health.label, health.http_status === 200 && health.no_store && health.dependencies.some((r)=>r.path === "/rest/v1/rpc/collect_notification_health_v2" && r.payload?.p_operator_user_id === userId && r.payload?.p_operator_session_id === sessionId), health);
  const dispatch = await request("dispatch-notifications", "dispatcher: valid internal empty queue", {
    headers: {
      "x-collect-signature": internalSecret
    }
  });
  check(dispatch.label, dispatch.http_status === 200 && dispatch.response?.claimed === 0, dispatch);
  const parsed = await request("parse-payment-sms", "parser: valid internal request requires real UUID", {
    headers: {
      "x-collect-signature": internalSecret
    }
  });
  check(parsed.label, parsed.http_status === 400 && parsed.dependencies.length === 0, parsed);
  const noEnvelope = await request("ingest-payment-sms", "SMS: current contract refuses unattested envelope", {
    headers: {
      authorization: userAuthorization
    },
    body: JSON.stringify({
      raw_sender: "M-Money",
      raw_body: "Synthetic raw message",
      receiver_momo_number: "0788991001"
    })
  });
  check(noEnvelope.label, noEnvelope.http_status === 400 && noEnvelope.dependencies.every((r)=>[
      "/auth/v1/user",
      "/rest/v1/rpc/attested_sms_contract_version",
      "/rest/v1/rpc/record_operational_metric_v1"
    ].includes(String(r.path))), noEnvelope);
  for (const scenario of [
    "receipt_success",
    "receipt_metric_error",
    "receipt_metric_timeout",
    "receipt_deferred",
    "receipt_bad_ack"
  ]){
    mode = scenario;
    const started = performance.now();
    const envelope = crypto.randomUUID();
    const result = await request("ingest-payment-sms", `SMS telemetry: ${scenario}`, {
      headers: {
        authorization: userAuthorization
      },
      body: JSON.stringify({
        raw_sender: "Synthetic sender canary",
        raw_body: "Synthetic private receipt canary",
        receiver_momo_number: "0788991001",
        client_envelope_id: envelope,
        native_capability: crypto.randomUUID()
      })
    });
    const elapsed = performance.now() - started;
    const samples = result.dependencies.filter((r)=>r.path === "/rest/v1/rpc/record_operational_metric_v1");
    const codes = samples.map((r)=>r.payload.p_event_code);
    const codeShape = samples.every((r)=>r.identity === "synthetic_service" && Object.keys(r.payload).sort().join() === "p_duration_ms,p_event_code" && !JSON.stringify(r.payload).includes("canary") && !JSON.stringify(r.payload).includes(envelope));
    const response = result.response;
    const success = scenario !== "receipt_deferred" && scenario !== "receipt_bad_ack";
    const expectedCodes = success ? [
      "receipt_processing_accepted",
      "receipt_ack_generated"
    ] : scenario === "receipt_deferred" ? [
      "receipt_processing_deferred"
    ] : [
      "receipt_rejected"
    ];
    const ack = response.receipt;
    check(result.label, result.http_status === (success ? 200 : 503) && codeShape && JSON.stringify(codes) === JSON.stringify(expectedCodes) && (success ? response.ok === true && ack?.stored === true && ack?.client_envelope_id === envelope && ack?.owner_user_id === userId : response.error === (scenario === "receipt_deferred" ? "receipt_stored_processing_retry" : "durable_receipt_not_verified")) && (scenario !== "receipt_metric_timeout" || elapsed < 1500) && !JSON.stringify(response).includes("secret-provider"), {
      ...result,
      elapsed_ms: elapsed
    });
  }
  mode = "normal";
  const deterministicInput = rosterInput();
  const roster = await request("prepare-roster-import", "roster: approved deterministic preview", {
    headers: {
      authorization: userAuthorization
    },
    body: JSON.stringify(deterministicInput)
  });
  check(roster.label, roster.http_status === 200 && roster.response?.processing_method === "deterministic", roster);
  check("roster: resource reservation and immutable preview finish in order", JSON.stringify(roster.dependencies.map((r)=>r.path)) === JSON.stringify([
    "/auth/v1/user",
    "/rest/v1/rpc/reserve_roster_resources",
    "/rest/v1/rpc/create_roster_import_source",
    "/rest/v1/rpc/complete_roster_import_preview",
    "/rest/v1/rpc/finish_roster_resources"
  ]) && roster.response?.requires_human_review === true && roster.response?.can_submit === false, roster);
  const replay = await request("prepare-roster-import", "roster: finished preview replay performs no decoder/provider work", {
    headers: {
      authorization: userAuthorization
    },
    body: JSON.stringify(deterministicInput)
  });
  check(replay.label, replay.http_status === 200 && JSON.stringify(replay.response) === JSON.stringify(roster.response) && JSON.stringify(replay.dependencies.map((r)=>r.path)) === JSON.stringify([
    "/auth/v1/user",
    "/rest/v1/rpc/reserve_roster_resources",
    "/rest/v1/rpc/create_roster_import_source"
  ]), replay);
  for (const [scenario, status, code, expected] of [
    [
      "roster_quota",
      429,
      "roster_resource_limit",
      [
        "/auth/v1/user",
        "/rest/v1/rpc/reserve_roster_resources"
      ]
    ],
    [
      "roster_bad_budget",
      503,
      "roster_budget_receipt_invalid",
      [
        "/auth/v1/user",
        "/rest/v1/rpc/reserve_roster_resources"
      ]
    ],
    [
      "roster_bad_nonce",
      503,
      "roster_decoder_receipt_invalid",
      [
        "/auth/v1/user",
        "/rest/v1/rpc/reserve_roster_resources",
        "/decode",
        "/rest/v1/rpc/finish_roster_resources"
      ]
    ],
    [
      "roster_bad_signature",
      503,
      "roster_decoder_receipt_invalid",
      [
        "/auth/v1/user",
        "/rest/v1/rpc/reserve_roster_resources",
        "/decode",
        "/rest/v1/rpc/finish_roster_resources"
      ]
    ],
    [
      "roster_decoder_reject",
      422,
      "roster_animation_limit",
      [
        "/auth/v1/user",
        "/rest/v1/rpc/reserve_roster_resources",
        "/decode",
        "/rest/v1/rpc/finish_roster_resources"
      ]
    ],
    [
      "roster_bad_verification",
      503,
      "roster_receipt_invalid",
      [
        "/auth/v1/user",
        "/rest/v1/rpc/reserve_roster_resources",
        "/decode",
        "/rest/v1/rpc/verify_roster_source_integrity",
        "/rest/v1/rpc/finish_roster_resources"
      ]
    ],
    [
      "normal",
      503,
      "roster_extraction_unavailable",
      [
        "/auth/v1/user",
        "/rest/v1/rpc/reserve_roster_resources",
        "/decode",
        "/rest/v1/rpc/verify_roster_source_integrity",
        "/rest/v1/rpc/create_roster_import_source",
        "/rest/v1/rpc/fail_roster_import_preview",
        "/rest/v1/rpc/finish_roster_resources"
      ]
    ]
  ]){
    mode = scenario;
    const before = providerAttempts.length;
    const result = await request("prepare-roster-import", `roster: ${scenario} enforces verification before transmission`, {
      headers: {
        authorization: userAuthorization
      },
      body: JSON.stringify(rosterImage())
    });
    check(result.label, result.http_status === status && result.response?.error === code && JSON.stringify(result.dependencies.map((r)=>r.path)) === JSON.stringify(expected) && providerAttempts.length === before, result);
  }
  mode = "normal";
  // The product owner retired the three bank-ingestion routes.
  // Preserve the boundary check as absence of source/config/listener, since
  // invoking deleted code would falsely inflate active surface acceptance.
  for (const retired of [
    "ingest-bank-email",
    "ingest-bank-sms",
    "ingest-bank-statement"
  ]){
    let sourceAbsent = false;
    try {
      await Deno.stat(new URL(`../../supabase/functions/${retired}/index.ts`, import.meta.url));
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) sourceAbsent = true;
      else throw error;
    }
    check(`retired ${retired}: source/config/listener absent`, sourceAbsent && !names.includes(retired) && !(retired in entrypoints));
  }
  const otpBody = JSON.stringify({
    user: {
      phone: "+250788991001"
    },
    sms: {
      otp: "987654"
    }
  });
  const webhook = new Webhook(hookSecret);
  function signedOtp(id, offset = 0, mutate = false) {
    const when = new Date(Date.now() + offset * 1000);
    return {
      body: mutate ? otpBody + " " : otpBody,
      headers: {
        "webhook-id": id,
        "webhook-timestamp": String(Math.floor(when.getTime() / 1000)),
        "webhook-signature": webhook.sign(id, when, otpBody)
      }
    };
  }
  for (const [label, offset, mutate] of [
    [
      "valid",
      0,
      false
    ],
    [
      "expired",
      -601,
      false
    ],
    [
      "modified-body",
      0,
      true
    ]
  ]){
    counter = 0;
    mode = "already_accepted";
    const before = providerAttempts.length;
    const result = await request("auth-send-whatsapp-otp", `OTP signed hook: ${label}`, signedOtp("qa-hook-" + label + "-" + crypto.randomUUID(), offset, mutate));
    check(result.label, result.http_status === (label === "valid" ? 200 : 401) && providerAttempts.length === before && (label === "valid" ? result.dependencies.map((r)=>r.path).join() === "/rest/v1/rpc/reserve_signed_otp_v3" : result.dependencies.length === 0), {
      ...result,
      model: "valid case returns a recorded accepted attempt; no provider dispatch"
    });
  }
  mode = "normal";
  const legacy = await request("auth-send-whatsapp-otp", "OTP legacy static secret cannot reserve or send", {
    headers: {
      "x-hook-secret": hookSecret
    },
    body: otpBody
  });
  check(legacy.label, legacy.http_status === 401 && legacy.dependencies.length === 0, legacy);
  for (const failure of [
    "count_error",
    "insert_error",
    "missing_rpc",
    "malformed_reservation"
  ]){
    mode = failure;
    counter = 0;
    const before = providerAttempts.length;
    const result = await request("auth-send-whatsapp-otp", `OTP limiter ${failure}: fails closed`, signedOtp("qa-failure-" + crypto.randomUUID()));
    check(result.label, result.http_status === 503 && providerAttempts.length === before && result.dependencies.length === 1 && result.dependencies[0].path === "/rest/v1/rpc/reserve_signed_otp_v3", result);
  }
  mode = "reserve_timeout";
  counter = 0;
  const timeoutStart = performance.now();
  const timed = await request("auth-send-whatsapp-otp", "OTP durable reservation timeout aborts without sending", signedOtp("qa-timeout-" + crypto.randomUUID()));
  const elapsed = performance.now() - timeoutStart;
  check(timed.label, timed.http_status === 503 && elapsed < 5000 && timed.dependencies.length === 1, {
    ...timed,
    elapsed_ms: elapsed
  });
  mode = "normal";
  counter = 5;
  const limit = await request("auth-send-whatsapp-otp", "OTP sixth request refused", signedOtp("qa-limit-" + crypto.randomUUID()));
  check(limit.label, limit.http_status === 429 && counter === 5, limit);
  counter = 4;
  const beforeConcurrent = providerAttempts.length;
  const concurrent = await Promise.all(Array.from({
    length: 8
  }, (_, i)=>request("auth-send-whatsapp-otp", `OTP concurrent ${i}`, signedOtp("qa-concurrent-" + i + "-" + crypto.randomUUID()))));
  check("OTP concurrency: one remaining reservation allows only one transport attempt", concurrent.filter((r)=>r.http_status === 503).length === 1 && concurrent.filter((r)=>r.http_status === 429).length === 7 && counter === 5 && providerAttempts.length - beforeConcurrent === 1, {
    statuses: concurrent.map((r)=>r.http_status),
    recorded_counter: counter,
    model: "recording v3 dependency; real SQL races verified in the separate145 packet; network permissions block the single transport attempt"
  });
  for (const scenario of [
    "normal",
    "lost_record_ack"
  ]){
    mode = scenario;
    counter = 0;
    const id = "qa-no-resend-" + crypto.randomUUID(), before = providerAttempts.length;
    const first = await request("auth-send-whatsapp-otp", `OTP ${scenario}: denied provider is unresolved`, signedOtp(id));
    const replay = await request("auth-send-whatsapp-otp", `OTP ${scenario}: replay cannot resend`, signedOtp(id));
    check(replay.label, first.http_status === 503 && replay.http_status === 503 && counter === 1 && providerAttempts.length - before === 1 && replay.dependencies.map((r)=>r.path).join() === "/rest/v1/rpc/reserve_signed_otp_v3", {
      first,
      replay
    });
  }
  mode = "normal";
  // Appended after every original HTTP assertion; synthetic policy only.
  // Each well-hashed tuple mismatch must fail before reserve/decode/provider.
  for (const [scenario, policyPatch, environmentPatch] of [
    [
      "missing policy",
      {},
      {
        ROSTER_AI_APPROVAL_JSON: undefined
      }
    ],
    [
      "missing hash",
      {},
      {
        ROSTER_AI_APPROVAL_SHA256: undefined
      }
    ],
    [
      "tampered hash",
      {},
      {
        ROSTER_AI_APPROVAL_SHA256: "0".repeat(64)
      }
    ],
    [
      "wrong model",
      {
        model: "synthetic-other-model"
      },
      {}
    ],
    [
      "wrong decoder URL",
      {
        decoder_url: "http://127.0.0.1:1/decode"
      },
      {}
    ],
    [
      "wrong decoder build",
      {
        decoder_build_sha256: "e".repeat(64)
      },
      {}
    ],
    [
      "wrong organization",
      {
        organization_id: "org_other_synthetic"
      },
      {}
    ],
    [
      "wrong project",
      {
        project_id: "proj_other_synthetic"
      },
      {}
    ],
    [
      "disabled policy",
      {
        enabled: false
      },
      {}
    ],
    [
      "revoked policy",
      {
        status: "revoked"
      },
      {}
    ],
    [
      "expired policy",
      {
        valid_until: "2021-01-01T00:00:00Z"
      },
      {}
    ],
    [
      "future approval",
      {
        approved_at: "2098-01-01T00:00:00Z"
      },
      {}
    ]
  ]){
    const negativeApproval = await syntheticRosterAiApproval(rosterModel, decoderUrl, decoderBuild, policyPatch);
    const negativeEnvironment = {
      ROSTER_AI_APPROVAL_JSON: negativeApproval.aiApprovalJson,
      ROSTER_AI_APPROVAL_SHA256: negativeApproval.aiApprovalSha256,
      OPENAI_ORGANIZATION_ID: negativeApproval.openAiOrganizationId,
      OPENAI_PROJECT_ID: negativeApproval.openAiProjectId
    };
    for (const [key, value] of Object.entries(environmentPatch)){
      negativeEnvironment[key] = value;
    }
    const before = providerAttempts.length;
    try {
      for (const [key, value] of Object.entries(negativeEnvironment)){
        if (typeof value === "string") Deno.env.set(key, value);
        else Deno.env.delete(key);
      }
      const result = await request("prepare-roster-import", `roster AI approval: ${scenario} refuses before work`, {
        headers: {
          authorization: userAuthorization
        },
        body: JSON.stringify(rosterImage())
      });
      check(result.label, result.http_status === 503 && result.response?.error === "roster_extraction_unavailable" && JSON.stringify(result.dependencies.map((r)=>r.path)) === JSON.stringify([
        "/auth/v1/user"
      ]) && providerAttempts.length === before && result.no_store === true, result);
    } finally{
      for (const [key, value] of Object.entries(rosterApprovalEnvironment)){
        Deno.env.set(key, value);
      }
    }
  }
  report.status = checks.every((r)=>r.status === "pass") ? "pass" : "fail";
} catch (error) {
  report.status = "fail";
  report.error = error instanceof Error ? error.message : String(error);
} finally{
  Deno.serve = realServe;
  globalThis.fetch = originalFetch;
  console.log("QA_EDGE_CLOSING=" + JSON.stringify({
    status: report.status,
    error: report.error,
    checks: checks.length,
    last_dependency_paths: records.slice(-10).map((record)=>record.path)
  }));
  // All scenario responses were consumed. Abort only this process's owned
  // test listeners, including keep-alive sockets, then await their completion.
  controllers.forEach((controller)=>controller.abort());
  await Promise.all(servers.map((server)=>server.finished));
  report.finished_at = new Date().toISOString();
  report.servers_closed = servers.length;
  report.cleanup_mode = "owned_listeners_aborted_after_scenario_responses";
  console.log("QA_EDGE_REPORT=" + JSON.stringify(report));
}
if (report.status !== "pass") Deno.exit(1);
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc2NyaXB0cy9xYS9lZGdlX2h0dHBfcnVudGltZV91YXQudHMiXSwic291cmNlc0NvbnRlbnQiOlsiLy8gUmVhbCBsb29wYmFjayBIVFRQIHNlcnZlcnMgbG9hZCB0aGUgdW5tb2RpZmllZCBFZGdlIGVudHJ5cG9pbnRzLiBPbmx5IHRoZWlyXG4vLyBBdXRoL1Bvc3RnUkVTVCBkZXBlbmRlbmN5IGlzIGEgcmVjb3JkaW5nIHN5bnRoZXRpYyBzZXJ2ZXI7IHByb3ZpZGVyIG5ldHdvcmtcbi8vIGFjY2VzcyBpcyBkZW5pZWQgYnkgdGhlIGxhdW5jaGVyLiBUaGlzIGlzIG5vdCBob3N0ZWQgb3IgcHJvdmlkZXIgYWNjZXB0YW5jZS5cbmltcG9ydCB7IFdlYmhvb2sgfSBmcm9tIFwibnBtOnN0YW5kYXJkd2ViaG9va3NAMS4wLjBcIjtcbmltcG9ydCB7IGhtYWNTaGEyNTZIZXggfSBmcm9tIFwiLi4vLi4vc3VwYWJhc2UvZnVuY3Rpb25zL19zaGFyZWQvaG1hYy50c1wiO1xuaW1wb3J0IHsgbm9ybWFsaXplUm9zdGVyQ2FuZGlkYXRlcyB9IGZyb20gXCIuLi8uLi9zdXBhYmFzZS9mdW5jdGlvbnMvX3NoYXJlZC9yb3N0ZXJfaW1wb3J0LnRzXCI7XG5pbXBvcnQgeyBST1NURVJfREVDT0RFUl9UT09MQ0hBSU4gfSBmcm9tIFwiLi4vLi4vc3VwYWJhc2UvZnVuY3Rpb25zL19zaGFyZWQvcm9zdGVyX2RlY29kZXIudHNcIjtcbmltcG9ydCB7IHN5bnRoZXRpY1Jvc3RlckFpQXBwcm92YWwgfSBmcm9tIFwiLi4vLi4vc3VwYWJhc2UvZnVuY3Rpb25zL19zaGFyZWQvcm9zdGVyX2FpX2Rpc3BhdGNoX3Rlc3RfZml4dHVyZS50c1wiO1xuXG4vLyBMaXRlcmFsIGltcG9ydHMgbGV0IHRoZSBmcm96ZW4gZ3JhcGggYmluZCB0aGUgc2FtZSByZWFsIGhhbmRsZXJzIHRoYXQgYXJlXG4vLyBsb2FkZWQgYWZ0ZXIgRGVuby5zZXJ2ZSBpcyByZWRpcmVjdGVkIHRvIHRoZSBvd25lZCBsb29wYmFjayBsaXN0ZW5lcnMuIEFcbi8vIGNvbXB1dGVkIFVSTCBsZWF2ZXMgU0RLIHJlZGlyZWN0IGFsaWFzZXMgdW5kaXNjb3ZlcmVkIGJ5IERlbm8gMi41LjYncyBncmFwaC5cbmNvbnN0IGVudHJ5cG9pbnRMb2FkZXJzOiBSZWNvcmQ8c3RyaW5nLCAoKSA9PiBQcm9taXNlPHVua25vd24+PiA9IHtcbiAgXCJhdXRoLXNlbmQtd2hhdHNhcHAtb3RwXCI6ICgpID0+XG4gICAgaW1wb3J0KFwiLi4vLi4vc3VwYWJhc2UvZnVuY3Rpb25zL2F1dGgtc2VuZC13aGF0c2FwcC1vdHAvaW5kZXgudHNcIiksXG4gIFwiY29sbGVjdC1hbmRyb2lkLWdhdGV3YXlcIjogKCkgPT5cbiAgICBpbXBvcnQoXCIuLi8uLi9zdXBhYmFzZS9mdW5jdGlvbnMvY29sbGVjdC1hbmRyb2lkLWdhdGV3YXkvaW5kZXgudHNcIiksXG4gIFwiY29sbGVjdC1ub3RpZmljYXRpb24tb3BlcmF0b3JcIjogKCkgPT5cbiAgICBpbXBvcnQoXCIuLi8uLi9zdXBhYmFzZS9mdW5jdGlvbnMvY29sbGVjdC1ub3RpZmljYXRpb24tb3BlcmF0b3IvaW5kZXgudHNcIiksXG4gIFwiY29sbGVjdC1yZWNlaXB0LWV4Y2VwdGlvbi13b3JrZXJcIjogKCkgPT5cbiAgICBpbXBvcnQoXCIuLi8uLi9zdXBhYmFzZS9mdW5jdGlvbnMvY29sbGVjdC1yZWNlaXB0LWV4Y2VwdGlvbi13b3JrZXIvaW5kZXgudHNcIiksXG4gIFwiY29sbGVjdC1yZWNlaXB0LXN1Y2Nlc3Nvci1nYXRld2F5XCI6ICgpID0+XG4gICAgaW1wb3J0KFwiLi4vLi4vc3VwYWJhc2UvZnVuY3Rpb25zL2NvbGxlY3QtcmVjZWlwdC1zdWNjZXNzb3ItZ2F0ZXdheS9pbmRleC50c1wiKSxcbiAgXCJjb2xsZWN0LXJlY2VpcHQtc3VwZXJ2aXNvclwiOiAoKSA9PlxuICAgIGltcG9ydChcIi4uLy4uL3N1cGFiYXNlL2Z1bmN0aW9ucy9jb2xsZWN0LXJlY2VpcHQtc3VwZXJ2aXNvci9pbmRleC50c1wiKSxcbiAgXCJkaXNwYXRjaC1ub3RpZmljYXRpb25zXCI6ICgpID0+XG4gICAgaW1wb3J0KFwiLi4vLi4vc3VwYWJhc2UvZnVuY3Rpb25zL2Rpc3BhdGNoLW5vdGlmaWNhdGlvbnMvaW5kZXgudHNcIiksXG4gIFwiaW5nZXN0LXBheW1lbnQtc21zXCI6ICgpID0+XG4gICAgaW1wb3J0KFwiLi4vLi4vc3VwYWJhc2UvZnVuY3Rpb25zL2luZ2VzdC1wYXltZW50LXNtcy9pbmRleC50c1wiKSxcbiAgXCJwYXJzZS1wYXltZW50LXNtc1wiOiAoKSA9PlxuICAgIGltcG9ydChcIi4uLy4uL3N1cGFiYXNlL2Z1bmN0aW9ucy9wYXJzZS1wYXltZW50LXNtcy9pbmRleC50c1wiKSxcbiAgXCJwcmVwYXJlLXJvc3Rlci1pbXBvcnRcIjogKCkgPT5cbiAgICBpbXBvcnQoXCIuLi8uLi9zdXBhYmFzZS9mdW5jdGlvbnMvcHJlcGFyZS1yb3N0ZXItaW1wb3J0L2luZGV4LnRzXCIpLFxuICBcInJlY29uY2lsaWF0aW9uLWZpbmFsaXplXCI6ICgpID0+XG4gICAgaW1wb3J0KFwiLi4vLi4vc3VwYWJhc2UvZnVuY3Rpb25zL3JlY29uY2lsaWF0aW9uLWZpbmFsaXplL2luZGV4LnRzXCIpLFxuICBcInNlbmQtbm90aWZpY2F0aW9uXCI6ICgpID0+XG4gICAgaW1wb3J0KFwiLi4vLi4vc3VwYWJhc2UvZnVuY3Rpb25zL3NlbmQtbm90aWZpY2F0aW9uL2luZGV4LnRzXCIpLFxuICBcInZlcmlmeS1wbGF5LWludGVncml0eVwiOiAoKSA9PlxuICAgIGltcG9ydChcIi4uLy4uL3N1cGFiYXNlL2Z1bmN0aW9ucy92ZXJpZnktcGxheS1pbnRlZ3JpdHkvaW5kZXgudHNcIiksXG59O1xuXG5jb25zdCB1c2VySWQgPSBcIjk4NjAwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwMVwiO1xuY29uc3Qgc2Vzc2lvbklkID0gXCI5ODYwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMTFcIjtcbmNvbnN0IHVzZXJUb2tlbiA9IFwiZTMwLlwiICtcbiAgYnRvYShcbiAgICBKU09OLnN0cmluZ2lmeSh7XG4gICAgICBzdWI6IHVzZXJJZCxcbiAgICAgIHNlc3Npb25faWQ6IHNlc3Npb25JZCxcbiAgICAgIHJvbGU6IFwiYXV0aGVudGljYXRlZFwiLFxuICAgIH0pLFxuICApLnJlcGxhY2VBbGwoXCI9XCIsIFwiXCIpLnJlcGxhY2VBbGwoXCIrXCIsIFwiLVwiKS5yZXBsYWNlQWxsKFwiL1wiLCBcIl9cIikgK1xuICBcIi5zeW50aGV0aWNcIjtcbmNvbnN0IHVzZXJBdXRob3JpemF0aW9uID0gXCJCZWFyZXIgXCIgKyB1c2VyVG9rZW47XG5jb25zdCBkZWNvZGVyU2VjcmV0ID0gXCJzeW50aGV0aWMtbG9vcGJhY2stb25seS1cIiArIGNyeXB0by5yYW5kb21VVUlEKCk7XG5jb25zdCBkZWNvZGVyQnVpbGQgPSBcImRcIi5yZXBlYXQoNjQpO1xuY29uc3QgcG5nID1cbiAgXCJpVkJPUncwS0dnb0FBQUFOU1VoRVVnQUFBQUlBQUFBRENBSUFBQUEyaUVuV0FBQUFGRWxFUVZSNG5HT1VTK2xoWUdCZ1lnQURLQVVBRS9BQkZDRkF1ZXNBQUFBQVNVVk9SSzVDWUlJPVwiO1xuY29uc3QgcHJvdmlkZXJBdHRlbXB0czogc3RyaW5nW10gPSBbXTtcbmNvbnN0IG9yaWdpbmFsRmV0Y2ggPSBnbG9iYWxUaGlzLmZldGNoO1xuZ2xvYmFsVGhpcy5mZXRjaCA9ICgoaW5wdXQ6IFJlcXVlc3QgfCBVUkwgfCBzdHJpbmcsIG9wdGlvbnM/OiBSZXF1ZXN0SW5pdCkgPT4ge1xuICBjb25zdCB1cmwgPSBpbnB1dCBpbnN0YW5jZW9mIFJlcXVlc3QgPyBpbnB1dC51cmwgOiBTdHJpbmcoaW5wdXQpO1xuICBpZiAoXG4gICAgdXJsLnN0YXJ0c1dpdGgoXCJodHRwczovL2dyYXBoLmZhY2Vib29rLmNvbS9cIikgfHxcbiAgICB1cmwuc3RhcnRzV2l0aChcImh0dHBzOi8vYXBpLm9wZW5haS5jb20vXCIpXG4gICkgcHJvdmlkZXJBdHRlbXB0cy5wdXNoKHVybCk7XG4gIHJldHVybiBvcmlnaW5hbEZldGNoKGlucHV0LCBvcHRpb25zKTtcbn0pIGFzIHR5cGVvZiBmZXRjaDtcbmNvbnN0IGludGVybmFsU2VjcmV0ID0gY3J5cHRvLnJhbmRvbVVVSUQoKTtcbmNvbnN0IGhvb2tTZWNyZXQgPSBidG9hKGNyeXB0by5yYW5kb21VVUlEKCkgKyBjcnlwdG8ucmFuZG9tVVVJRCgpKTtcbmNvbnN0IHJlYWxTZXJ2ZSA9IERlbm8uc2VydmU7XG5jb25zdCBzZXJ2ZXJzOiBEZW5vLkh0dHBTZXJ2ZXI8RGVuby5OZXRBZGRyPltdID0gW107XG5jb25zdCBjb250cm9sbGVyczogQWJvcnRDb250cm9sbGVyW10gPSBbXTtcbmNvbnN0IHJlY29yZHM6IEFycmF5PFJlY29yZDxzdHJpbmcsIHVua25vd24+PiA9IFtdO1xuY29uc3QgY2hlY2tzOiBBcnJheTxSZWNvcmQ8c3RyaW5nLCB1bmtub3duPj4gPSBbXTtcbmNvbnN0IGVudHJ5cG9pbnRzOiBSZWNvcmQ8c3RyaW5nLCBzdHJpbmc+ID0ge307XG5jb25zdCBzdGFydHM6IFJlY29yZDxzdHJpbmcsIG51bWJlcj4gPSB7fTtcbmxldCBtb2RlID0gXCJub3JtYWxcIjtcbmxldCBjb3VudGVyID0gMDtcbmNvbnN0IG90cEF0dGVtcHRzID0gbmV3IE1hcDxzdHJpbmcsIFJlY29yZDxzdHJpbmcsIHVua25vd24+PigpO1xuY29uc3Qgcm9zdGVyQnVkZ2V0cyA9IG5ldyBNYXA8c3RyaW5nLCBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPj4oKTtcbmNvbnN0IHJvc3RlclNvdXJjZXMgPSBuZXcgTWFwPHN0cmluZywgUmVjb3JkPHN0cmluZywgdW5rbm93bj4+KCk7XG5jb25zdCBkZWNvZGVyUmVjZWlwdHMgPSBuZXcgTWFwPHN0cmluZywgUmVjb3JkPHN0cmluZywgdW5rbm93bj4+KCk7XG5hc3luYyBmdW5jdGlvbiBzaGEodGV4dDogc3RyaW5nIHwgVWludDhBcnJheSkge1xuICBjb25zdCBpbnB1dCA9IHR5cGVvZiB0ZXh0ID09PSBcInN0cmluZ1wiXG4gICAgPyBuZXcgVGV4dEVuY29kZXIoKS5lbmNvZGUodGV4dClcbiAgICA6IHRleHQ7XG4gIHJldHVybiBbXG4gICAgLi4ubmV3IFVpbnQ4QXJyYXkoXG4gICAgICBhd2FpdCBjcnlwdG8uc3VidGxlLmRpZ2VzdChcIlNIQS0yNTZcIiwgaW5wdXQgYXMgQnVmZmVyU291cmNlKSxcbiAgICApLFxuICBdLm1hcCgodikgPT4gdi50b1N0cmluZygxNikucGFkU3RhcnQoMiwgXCIwXCIpKS5qb2luKFwiXCIpO1xufVxuZnVuY3Rpb24gcm9zdGVySW5wdXQocGF0Y2g6IFJlY29yZDxzdHJpbmcsIHVua25vd24+ID0ge30pIHtcbiAgcmV0dXJuIHtcbiAgICBjb250cmFjdF92ZXJzaW9uOiAxLFxuICAgIHJlcXVlc3RfaWQ6IGNyeXB0by5yYW5kb21VVUlEKCksXG4gICAgc291cmNlX3R5cGU6IFwidGV4dFwiLFxuICAgIGNvbnRlbnQ6XG4gICAgICBcIk1lbWJlciBuYW1lLE1vTW8gbmFtZSxNb01vIG51bWJlclxcbkFsaW5lIFV3YXNlLEFMSU5FIFVXQVNFLDA3ODg5OTEwMDFcIixcbiAgICAuLi5wYXRjaCxcbiAgfTtcbn1cbmZ1bmN0aW9uIHJvc3RlckltYWdlKHBhdGNoOiBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPiA9IHt9KSB7XG4gIHJldHVybiByb3N0ZXJJbnB1dCh7XG4gICAgc291cmNlX3R5cGU6IFwiaW1hZ2VcIixcbiAgICBjb250ZW50OiB1bmRlZmluZWQsXG4gICAgZmlsZW5hbWU6IFwiZml4dHVyZS5wbmdcIixcbiAgICBtaW1lX3R5cGU6IFwiaW1hZ2UvcG5nXCIsXG4gICAgY29udGVudF9iYXNlNjQ6IHBuZyxcbiAgICBhaV9jb25zZW50OiB0cnVlLFxuICAgIGNvbnNlbnRfdmVyc2lvbjogXCJyb3N0ZXItYWktZXh0cmFjdGlvbi12MVwiLFxuICAgIC4uLnBhdGNoLFxuICB9KTtcbn1cbmZ1bmN0aW9uIHJvc3RlclByZXZpZXcoXG4gIHNvdXJjZTogUmVjb3JkPHN0cmluZywgdW5rbm93bj4sXG4gIGNhbmRpZGF0ZXM6IFBhcmFtZXRlcnM8dHlwZW9mIG5vcm1hbGl6ZVJvc3RlckNhbmRpZGF0ZXM+WzBdLFxuKSB7XG4gIHJldHVybiB7XG4gICAgY29udHJhY3RfdmVyc2lvbjogMSxcbiAgICBvazogdHJ1ZSxcbiAgICBpbXBvcnRfaWQ6IHNvdXJjZS5pbXBvcnRfaWQsXG4gICAgc291cmNlX3NoYTI1Njogc291cmNlLnBfb3JpZ2luYWxfc2hhMjU2LFxuICAgIHNvdXJjZV9raW5kOiBzb3VyY2UucF9zb3VyY2Vfa2luZCxcbiAgICBzb3VyY2VfcmVjZWlwdDoge1xuICAgICAgcmVxdWVzdF9pZDogc291cmNlLnBfcmVxdWVzdF9pZCxcbiAgICAgIHNvdXJjZV9zaXplOiBzb3VyY2UucF9vcmlnaW5hbF9zaXplLFxuICAgICAgY2xpZW50X2ZpbGVuYW1lOiBzb3VyY2UucF9jbGllbnRfZmlsZW5hbWUsXG4gICAgICBkZWNsYXJlZF9taW1lOiBzb3VyY2UucF9kZWNsYXJlZF9taW1lLFxuICAgICAgZGV0ZWN0ZWRfdHlwZTogc291cmNlLnBfZGV0ZWN0ZWRfdHlwZSxcbiAgICAgIGRlcml2ZWRfc2hhMjU2OiBzb3VyY2UucF9kZXJpdmVkX3NoYTI1NixcbiAgICAgIGRlcml2ZWRfYXNzdXJhbmNlOiBzb3VyY2UucF9zb3VyY2Vfa2luZCA9PT0gXCJ4bHN4XCJcbiAgICAgICAgPyBcImNsaWVudF9kZXJpdmVkX3RzdlwiXG4gICAgICAgIDogbnVsbCxcbiAgICAgIGV4dHJhY3Rpb25faWQ6IHNvdXJjZS5leHRyYWN0aW9uX2lkLFxuICAgICAgYWlfY29uc2VudDogc291cmNlLnBfYWlfY29uc2VudCxcbiAgICAgIGNvbnNlbnRfdmVyc2lvbjogc291cmNlLnBfY29uc2VudF92ZXJzaW9uLFxuICAgICAgcGFyc2VyX3ZlcnNpb246IFwiY29sbGVjdC1yb3N0ZXItcGFyc2VyLXYxXCIsXG4gICAgICBzY2hlbWFfdmVyc2lvbjogXCJjb2xsZWN0LXJvc3Rlci1yb3dzLXYxXCIsXG4gICAgfSxcbiAgICByZXZpc2lvbl9pZDogY3J5cHRvLnJhbmRvbVVVSUQoKSxcbiAgICBwYXJlbnRfcmV2aXNpb25faWQ6IG51bGwsXG4gICAgcmV2aXNpb25fbnVtYmVyOiAxLFxuICAgIHJldmlld2VkX3Jvd3Nfc2hhMjU2OiBcImFcIi5yZXBlYXQoNjQpLFxuICAgIC4uLm5vcm1hbGl6ZVJvc3RlckNhbmRpZGF0ZXMoY2FuZGlkYXRlcyksXG4gICAgY2FuX3N1Ym1pdDogZmFsc2UsXG4gICAgcmVxdWlyZXNfaHVtYW5fcmV2aWV3OiB0cnVlLFxuICAgIHByb2Nlc3NpbmdfbWV0aG9kOiBzb3VyY2UucF9haV9jb25zZW50XG4gICAgICA/IFwib3BlbmFpX3N0cnVjdHVyZWRfZXh0cmFjdGlvblwiXG4gICAgICA6IFwiZGV0ZXJtaW5pc3RpY1wiLFxuICAgIG1vZGVsOiBzb3VyY2UucF9haV9jb25zZW50ID8gXCJzeW50aGV0aWMtbW9kZWxcIiA6IG51bGwsXG4gICAgZXhwaXJlc19hdDogXCIyMDk5LTAxLTAxVDAwOjAwOjAwWlwiLFxuICB9O1xufVxuXG5mdW5jdGlvbiBqc29uKFxuICB2YWx1ZTogdW5rbm93bixcbiAgc3RhdHVzID0gMjAwLFxuICBoZWFkZXJzOiBSZWNvcmQ8c3RyaW5nLCBzdHJpbmc+ID0ge30sXG4pIHtcbiAgcmV0dXJuIG5ldyBSZXNwb25zZShKU09OLnN0cmluZ2lmeSh2YWx1ZSksIHtcbiAgICBzdGF0dXMsXG4gICAgaGVhZGVyczogeyBcImNvbnRlbnQtdHlwZVwiOiBcImFwcGxpY2F0aW9uL2pzb25cIiwgLi4uaGVhZGVycyB9LFxuICB9KTtcbn1cblxuY29uc3QgYmFja2VuZENvbnRyb2xsZXIgPSBuZXcgQWJvcnRDb250cm9sbGVyKCk7XG5jb250cm9sbGVycy5wdXNoKGJhY2tlbmRDb250cm9sbGVyKTtcbmNvbnN0IGJhY2tlbmQgPSByZWFsU2VydmUoe1xuICBob3N0bmFtZTogXCIxMjcuMC4wLjFcIixcbiAgcG9ydDogMCxcbiAgc2lnbmFsOiBiYWNrZW5kQ29udHJvbGxlci5zaWduYWwsXG4gIG9uTGlzdGVuKCkge30sXG59LCBhc3luYyAocmVxdWVzdCkgPT4ge1xuICBjb25zdCBwYXRoID0gbmV3IFVSTChyZXF1ZXN0LnVybCkucGF0aG5hbWU7XG4gIGNvbnN0IHRleHQgPSBhd2FpdCByZXF1ZXN0LnRleHQoKTtcbiAgY29uc3QgcGF5bG9hZCA9IHRleHQgPyBKU09OLnBhcnNlKHRleHQpIDogbnVsbDtcbiAgY29uc3QgYXV0aG9yaXphdGlvbiA9IHJlcXVlc3QuaGVhZGVycy5nZXQoXCJhdXRob3JpemF0aW9uXCIpO1xuICByZWNvcmRzLnB1c2goe1xuICAgIHBhdGgsXG4gICAgbWV0aG9kOiByZXF1ZXN0Lm1ldGhvZCxcbiAgICBwYXlsb2FkLFxuICAgIGlkZW50aXR5OiBhdXRob3JpemF0aW9uID09PSB1c2VyQXV0aG9yaXphdGlvblxuICAgICAgPyBcInN5bnRoZXRpY191c2VyXCJcbiAgICAgIDogYXV0aG9yaXphdGlvbiA9PT0gXCJCZWFyZXIgcWEtc2VydmljZVwiXG4gICAgICA/IFwic3ludGhldGljX3NlcnZpY2VcIlxuICAgICAgOiBcInVucmVjb2duaXplZFwiLFxuICB9KTtcbiAgaWYgKHBhdGggPT09IFwiL2F1dGgvdjEvdXNlclwiKSB7XG4gICAgaWYgKGF1dGhvcml6YXRpb24gIT09IHVzZXJBdXRob3JpemF0aW9uKSB7XG4gICAgICByZXR1cm4ganNvbih7IG1lc3NhZ2U6IFwiaW52YWxpZCBzeW50aGV0aWMgdG9rZW5cIiB9LCA0MDEpO1xuICAgIH1cbiAgICByZXR1cm4ganNvbih7XG4gICAgICBpZDogdXNlcklkLFxuICAgICAgYXVkOiBcImF1dGhlbnRpY2F0ZWRcIixcbiAgICAgIHJvbGU6IFwiYXV0aGVudGljYXRlZFwiLFxuICAgICAgY3JlYXRlZF9hdDogbmV3IERhdGUoKS50b0lTT1N0cmluZygpLFxuICAgICAgYXBwX21ldGFkYXRhOiB7fSxcbiAgICAgIHVzZXJfbWV0YWRhdGE6IHt9LFxuICAgIH0pO1xuICB9XG4gIGlmIChwYXRoID09PSBcIi9yZXN0L3YxL3JwYy9hdXRob3JpemVfcmVjb25jaWxpYXRpb25fZmluYWxpemF0aW9uX3YyXCIpIHtcbiAgICByZXR1cm4gYXV0aG9yaXphdGlvbiA9PT0gdXNlckF1dGhvcml6YXRpb25cbiAgICAgID8ganNvbih0cnVlKVxuICAgICAgOiBqc29uKHsgY29kZTogXCJQR1JTVDMwMVwiLCBtZXNzYWdlOiBcIlN5bnRoZXRpYyBpbnZhbGlkIEpXVFwiIH0sIDQwMSk7XG4gIH1cbiAgaWYgKHBhdGggPT09IFwiL3Jlc3QvdjEvcnBjL2FkbWluX2N1cnJlbnRfdXNlclwiKSB7XG4gICAgcmV0dXJuIGpzb24oe1xuICAgICAgdXNlcl9pZDogdXNlcklkLFxuICAgICAgcGVybWlzc2lvbnM6IG1vZGUgPT09IFwiZGVuaWVkXCIgPyBbXSA6IFtcbiAgICAgICAgXCJub3RpZmljYXRpb25zLnJlYWRcIixcbiAgICAgICAgXCJub3RpZmljYXRpb25zLm1hbmFnZVwiLFxuICAgICAgICBcInVzZXJzLnJlYWRcIixcbiAgICAgICAgXCJjb2xsZWN0aW9ucy5tb2RlcmF0ZVwiLFxuICAgICAgXSxcbiAgICB9KTtcbiAgfVxuICBpZiAocGF0aCA9PT0gXCIvcmVzdC92MS9mZWF0dXJlX2ZsYWdzXCIpIHJldHVybiBqc29uKHsgZW5hYmxlZDogdHJ1ZSB9KTtcbiAgaWYgKHBhdGguZW5kc1dpdGgoXCIvcmVzZXJ2ZV9zaWduZWRfb3RwX3YzXCIpKSB7XG4gICAgY29uc3QgYXJncyA9IHBheWxvYWQgYXMgUmVjb3JkPHN0cmluZywgdW5rbm93bj47XG4gICAgaWYgKG1vZGUgPT09IFwiY291bnRfZXJyb3JcIiB8fCBtb2RlID09PSBcImluc2VydF9lcnJvclwiKSB7XG4gICAgICByZXR1cm4ganNvbih7XG4gICAgICAgIGNvZGU6IFwiUUFfRkFJTFVSRVwiLFxuICAgICAgICBtZXNzYWdlOiBcIlN5bnRoZXRpYyBkdXJhYmxlIHJlc2VydmF0aW9uIHVuYXZhaWxhYmxlXCIsXG4gICAgICB9LCA1MDMpO1xuICAgIH1cbiAgICBpZiAobW9kZSA9PT0gXCJtaXNzaW5nX3JwY1wiKSB7XG4gICAgICByZXR1cm4ganNvbih7IGNvZGU6IFwiUEdSU1QyMDJcIiwgbWVzc2FnZTogXCJSUEMgbm90IGRlcGxveWVkXCIgfSwgNDA0KTtcbiAgICB9XG4gICAgaWYgKG1vZGUgPT09IFwibWFsZm9ybWVkX3Jlc2VydmF0aW9uXCIpIHJldHVybiBqc29uKHsgYWxsb3dlZDogdHJ1ZSB9KTtcbiAgICBpZiAobW9kZSA9PT0gXCJyZXNlcnZlX3RpbWVvdXRcIikge1xuICAgICAgYXdhaXQgbmV3IFByb21pc2UoKHJlc29sdmUpID0+IHNldFRpbWVvdXQocmVzb2x2ZSwgNDUwMCkpO1xuICAgICAgcmV0dXJuIGpzb24oeyBhbGxvd2VkOiB0cnVlIH0pO1xuICAgIH1cbiAgICBjb25zdCBrZXkgPSBTdHJpbmcoYXJncy5wX2hvb2tfaWQpLCBleGlzdGluZyA9IG90cEF0dGVtcHRzLmdldChrZXkpO1xuICAgIGlmIChleGlzdGluZykge1xuICAgICAgaWYgKGV4aXN0aW5nLnBheWxvYWRfaGFzaCAhPT0gYXJncy5wX3BheWxvYWRfaGFzaCkge1xuICAgICAgICByZXR1cm4ganNvbih7IGNvZGU6IFwiMjIwMjNcIiwgbWVzc2FnZTogXCJvdHBfcGF5bG9hZF9jb25mbGljdFwiIH0sIDQwMCk7XG4gICAgICB9XG4gICAgICByZXR1cm4ganNvbihleGlzdGluZyk7XG4gICAgfVxuICAgIGlmIChjb3VudGVyID49IDUpIHJldHVybiBqc29uKFwidGhyb3R0bGVkXCIpO1xuICAgIGNvdW50ZXIrKztcbiAgICBjb25zdCByZWNlaXB0ID0ge1xuICAgICAgY29udHJhY3RfdmVyc2lvbjogMyxcbiAgICAgIGhvb2tfaWQ6IGFyZ3MucF9ob29rX2lkLFxuICAgICAgcGF5bG9hZF9oYXNoOiBhcmdzLnBfcGF5bG9hZF9oYXNoLFxuICAgICAgYXR0ZW1wdF9pZDogY3J5cHRvLnJhbmRvbVVVSUQoKSxcbiAgICAgIHN0YXRlOiBtb2RlID09PSBcImFscmVhZHlfYWNjZXB0ZWRcIiA/IFwiYWNjZXB0ZWRcIiA6IFwicmVzZXJ2ZWRcIixcbiAgICAgIHJldmlzaW9uOiAxLFxuICAgICAgY2FuX3NlbmQ6IG1vZGUgIT09IFwiYWxyZWFkeV9hY2NlcHRlZFwiLFxuICAgIH07XG4gICAgb3RwQXR0ZW1wdHMuc2V0KGtleSwgcmVjZWlwdCk7XG4gICAgcmV0dXJuIGpzb24ocmVjZWlwdCk7XG4gIH1cbiAgaWYgKFxuICAgIHBhdGguZW5kc1dpdGgoXCIvYmVnaW5fc2lnbmVkX290cF92M1wiKSB8fFxuICAgIHBhdGguZW5kc1dpdGgoXCIvcmVjb3JkX3NpZ25lZF9vdHBfdjNcIilcbiAgKSB7XG4gICAgY29uc3QgYXJncyA9IHBheWxvYWQgYXMgUmVjb3JkPHN0cmluZywgdW5rbm93bj4sXG4gICAgICBrZXkgPSBTdHJpbmcoYXJncy5wX2hvb2tfaWQpLFxuICAgICAgZXhpc3RpbmcgPSBvdHBBdHRlbXB0cy5nZXQoa2V5KTtcbiAgICBpZiAoXG4gICAgICAhZXhpc3RpbmcgfHwgZXhpc3RpbmcucGF5bG9hZF9oYXNoICE9PSBhcmdzLnBfcGF5bG9hZF9oYXNoIHx8XG4gICAgICBleGlzdGluZy5hdHRlbXB0X2lkICE9PSBhcmdzLnBfYXR0ZW1wdF9pZCB8fFxuICAgICAgZXhpc3RpbmcucmV2aXNpb24gIT09IGFyZ3MucF9yZXZpc2lvblxuICAgICkgcmV0dXJuIGpzb24oeyBjb2RlOiBcIjIyMDIzXCIsIG1lc3NhZ2U6IFwib3RwX2lkZW50aXR5X2NvbmZsaWN0XCIgfSwgNDAwKTtcbiAgICBpZiAocGF0aC5lbmRzV2l0aChcIi9iZWdpbl9zaWduZWRfb3RwX3YzXCIpKSB7XG4gICAgICBjb25zdCByZWNlaXB0ID0ge1xuICAgICAgICAuLi5leGlzdGluZyxcbiAgICAgICAgc3RhdGU6IFwic2VuZGluZ1wiLFxuICAgICAgICByZXZpc2lvbjogTnVtYmVyKGV4aXN0aW5nLnJldmlzaW9uKSArIDEsXG4gICAgICAgIGNhbl9zZW5kOiBmYWxzZSxcbiAgICAgIH07XG4gICAgICBvdHBBdHRlbXB0cy5zZXQoa2V5LCByZWNlaXB0KTtcbiAgICAgIHJldHVybiBqc29uKHsgLi4ucmVjZWlwdCwgc3RhcnRlZDogdHJ1ZSB9KTtcbiAgICB9XG4gICAgaWYgKG1vZGUgPT09IFwibG9zdF9yZWNvcmRfYWNrXCIpIHtcbiAgICAgIHJldHVybiBqc29uKHtcbiAgICAgICAgY29kZTogXCJRQV9GQUlMVVJFXCIsXG4gICAgICAgIG1lc3NhZ2U6IFwiU3ludGhldGljIHJlY29yZGluZyBhY2tub3dsZWRnZW1lbnQgbG9zdFwiLFxuICAgICAgfSwgNTAzKTtcbiAgICB9XG4gICAgY29uc3QgcmVjZWlwdCA9IHtcbiAgICAgIC4uLmV4aXN0aW5nLFxuICAgICAgc3RhdGU6IGFyZ3MucF9vdXRjb21lLFxuICAgICAgcmV2aXNpb246IE51bWJlcihleGlzdGluZy5yZXZpc2lvbikgKyAxLFxuICAgICAgY2FuX3NlbmQ6IGZhbHNlLFxuICAgIH07XG4gICAgb3RwQXR0ZW1wdHMuc2V0KGtleSwgcmVjZWlwdCk7XG4gICAgcmV0dXJuIGpzb24ocmVjZWlwdCk7XG4gIH1cbiAgaWYgKHBhdGguZW5kc1dpdGgoXCIvcmVzZXJ2ZV9yb3N0ZXJfcmVzb3VyY2VzXCIpKSB7XG4gICAgY29uc3QgYXJncyA9IHBheWxvYWQgYXMgUmVjb3JkPHN0cmluZywgdW5rbm93bj47XG4gICAgaWYgKG1vZGUgPT09IFwiZGVuaWVkXCIpIHtcbiAgICAgIHJldHVybiBqc29uKHsgY29kZTogXCI0MjUwMVwiLCBtZXNzYWdlOiBcInJvc3Rlcl9pbXBvcnRfZm9yYmlkZGVuXCIgfSwgNDAzKTtcbiAgICB9XG4gICAgaWYgKG1vZGUgPT09IFwicm9zdGVyX3F1b3RhXCIpIHtcbiAgICAgIHJldHVybiBqc29uKHsgY29kZTogXCJQMDAwMVwiLCBtZXNzYWdlOiBcInJvc3Rlcl9yZXNvdXJjZV9saW1pdFwiIH0sIDQyOSk7XG4gICAgfVxuICAgIGNvbnN0IGV4aXN0aW5nID0gcm9zdGVyQnVkZ2V0cy5nZXQoU3RyaW5nKGFyZ3MucF9yZXF1ZXN0X2lkKSk7XG4gICAgaWYgKGV4aXN0aW5nKSByZXR1cm4ganNvbih7IC4uLmV4aXN0aW5nLCByZXBsYXllZDogdHJ1ZSB9KTtcbiAgICBjb25zdCByZWNlaXB0ID0ge1xuICAgICAgY29udHJhY3RfdmVyc2lvbjogMSxcbiAgICAgIG9rOiB0cnVlLFxuICAgICAgcmVzZXJ2YXRpb25faWQ6IGNyeXB0by5yYW5kb21VVUlEKCksXG4gICAgICByZXF1ZXN0X2lkOiBhcmdzLnBfcmVxdWVzdF9pZCxcbiAgICAgIGFjdG9yX2lkOiBhcmdzLnBfYWN0b3JfaWQsXG4gICAgICBzZXNzaW9uX2lkOiBhcmdzLnBfc2Vzc2lvbl9pZCxcbiAgICAgIHNvdXJjZV9zaGEyNTY6IGFyZ3MucF9zb3VyY2Vfc2hhMjU2LFxuICAgICAgc3RhdGU6IFwicmVzZXJ2ZWRcIixcbiAgICAgIHJlcGxheWVkOiBmYWxzZSxcbiAgICAgIGV4cGlyZXNfYXQ6IFwiMjA5OS0wMS0wMVQwMDowMDowMFpcIixcbiAgICB9O1xuICAgIHJvc3RlckJ1ZGdldHMuc2V0KFN0cmluZyhhcmdzLnBfcmVxdWVzdF9pZCksIHJlY2VpcHQpO1xuICAgIHJldHVybiBqc29uKFxuICAgICAgbW9kZSA9PT0gXCJyb3N0ZXJfYmFkX2J1ZGdldFwiXG4gICAgICAgID8geyAuLi5yZWNlaXB0LCBhY3Rvcl9pZDogY3J5cHRvLnJhbmRvbVVVSUQoKSB9XG4gICAgICAgIDogcmVjZWlwdCxcbiAgICApO1xuICB9XG4gIGlmIChwYXRoLmVuZHNXaXRoKFwiL3ZlcmlmeV9yb3N0ZXJfc291cmNlX2ludGVncml0eVwiKSkge1xuICAgIGNvbnN0IGFyZ3MgPSBwYXlsb2FkIGFzIFJlY29yZDxzdHJpbmcsIHVua25vd24+LFxuICAgICAgcHJvb2YgPSBkZWNvZGVyUmVjZWlwdHMuZ2V0KFN0cmluZyhhcmdzLnBfcmVzZXJ2YXRpb25faWQpKTtcbiAgICBpZiAoXG4gICAgICAhcHJvb2YgfHwgcHJvb2YucmVjZWlwdF9zaGEyNTYgIT09IGFyZ3MucF9kZWNvZGVyX3JlY2VpcHRfc2hhMjU2IHx8XG4gICAgICBwcm9vZi5kZWNvZGVyX2J1aWxkX3NoYTI1NiAhPT0gYXJncy5wX2RlY29kZXJfYnVpbGRfc2hhMjU2IHx8XG4gICAgICBhcmdzLnBfYWN0b3JfaWQgIT09IHVzZXJJZCB8fCBhcmdzLnBfc2Vzc2lvbl9pZCAhPT0gc2Vzc2lvbklkXG4gICAgKSB7XG4gICAgICByZXR1cm4ganNvbih7XG4gICAgICAgIGNvZGU6IFwiMjIwMjNcIixcbiAgICAgICAgbWVzc2FnZTogXCJyb3N0ZXJfc291cmNlX3ZlcmlmaWNhdGlvbl9pbnZhbGlkXCIsXG4gICAgICB9LCA0MDApO1xuICAgIH1cbiAgICByZXR1cm4ganNvbih7XG4gICAgICBjb250cmFjdF92ZXJzaW9uOiAxLFxuICAgICAgb2s6IHRydWUsXG4gICAgICByZXNlcnZhdGlvbl9pZDogYXJncy5wX3Jlc2VydmF0aW9uX2lkLFxuICAgICAgc291cmNlX3NoYTI1NjogcHJvb2Yuc291cmNlX3NoYTI1NixcbiAgICAgIGRlcml2ZWRfc2hhMjU2OiBwcm9vZi5kZXJpdmVkX3NoYTI1NixcbiAgICAgIGRlY29kZXJfcmVjZWlwdF9zaGEyNTY6IG1vZGUgPT09IFwicm9zdGVyX2JhZF92ZXJpZmljYXRpb25cIlxuICAgICAgICA/IFwiZlwiLnJlcGVhdCg2NClcbiAgICAgICAgOiBhcmdzLnBfZGVjb2Rlcl9yZWNlaXB0X3NoYTI1NixcbiAgICAgIHZlcmlmaWVkOiB0cnVlLFxuICAgIH0pO1xuICB9XG4gIGlmIChwYXRoLmVuZHNXaXRoKFwiL2ZpbmlzaF9yb3N0ZXJfcmVzb3VyY2VzXCIpKSB7XG4gICAgY29uc3QgYXJncyA9IHBheWxvYWQgYXMgUmVjb3JkPHN0cmluZywgdW5rbm93bj4sXG4gICAgICBidWRnZXQgPSBbLi4ucm9zdGVyQnVkZ2V0cy52YWx1ZXMoKV0uZmluZCgocikgPT5cbiAgICAgICAgci5yZXNlcnZhdGlvbl9pZCA9PT0gYXJncy5wX3Jlc2VydmF0aW9uX2lkXG4gICAgICApO1xuICAgIGlmIChcbiAgICAgICFidWRnZXQgfHwgYXJncy5wX2FjdG9yX2lkICE9PSB1c2VySWQgfHwgYXJncy5wX3Nlc3Npb25faWQgIT09IHNlc3Npb25JZFxuICAgICkgcmV0dXJuIGpzb24oeyBjb2RlOiBcIjQyNTAxXCIsIG1lc3NhZ2U6IFwicm9zdGVyX2ltcG9ydF9mb3JiaWRkZW5cIiB9LCA0MDMpO1xuICAgIGJ1ZGdldC5zdGF0ZSA9IFwiZmluaXNoZWRcIjtcbiAgICByZXR1cm4ganNvbih7XG4gICAgICBjb250cmFjdF92ZXJzaW9uOiAxLFxuICAgICAgb2s6IHRydWUsXG4gICAgICByZXNlcnZhdGlvbl9pZDogYXJncy5wX3Jlc2VydmF0aW9uX2lkLFxuICAgICAgb3V0Y29tZTogYXJncy5wX291dGNvbWUsXG4gICAgICBjaGFyZ2VkOiB0cnVlLFxuICAgIH0pO1xuICB9XG4gIGlmIChwYXRoLmVuZHNXaXRoKFwiL2NyZWF0ZV9yb3N0ZXJfaW1wb3J0X3NvdXJjZVwiKSkge1xuICAgIGNvbnN0IGFyZ3MgPSBwYXlsb2FkIGFzIFJlY29yZDxzdHJpbmcsIHVua25vd24+LFxuICAgICAgZXhpc3RpbmcgPSByb3N0ZXJTb3VyY2VzLmdldChTdHJpbmcoYXJncy5wX3JlcXVlc3RfaWQpKTtcbiAgICBjb25zdCBzb3VyY2UgPSBleGlzdGluZyA/P1xuICAgICAge1xuICAgICAgICAuLi5hcmdzLFxuICAgICAgICBpbXBvcnRfaWQ6IGNyeXB0by5yYW5kb21VVUlEKCksXG4gICAgICAgIGV4dHJhY3Rpb25faWQ6IGFyZ3MucF9haV9jb25zZW50ID8gY3J5cHRvLnJhbmRvbVVVSUQoKSA6IG51bGwsXG4gICAgICAgIHN0YXRlOiBcImF3YWl0aW5nX3ByZXZpZXdcIixcbiAgICAgICAgY29tcGxldGVkX3ByZXZpZXc6IG51bGwsXG4gICAgICAgIGVycm9yX2NvZGU6IG51bGwsXG4gICAgICB9O1xuICAgIHJvc3RlclNvdXJjZXMuc2V0KFN0cmluZyhhcmdzLnBfcmVxdWVzdF9pZCksIHNvdXJjZSk7XG4gICAgcmV0dXJuIGpzb24oe1xuICAgICAgY29udHJhY3RfdmVyc2lvbjogMSxcbiAgICAgIG9rOiB0cnVlLFxuICAgICAgcmVxdWVzdF9pZDogYXJncy5wX3JlcXVlc3RfaWQsXG4gICAgICBpbXBvcnRfaWQ6IHNvdXJjZS5pbXBvcnRfaWQsXG4gICAgICBzb3VyY2Vfc2hhMjU2OiBhcmdzLnBfb3JpZ2luYWxfc2hhMjU2LFxuICAgICAgc291cmNlX3NpemU6IGFyZ3MucF9vcmlnaW5hbF9zaXplLFxuICAgICAgc291cmNlX2tpbmQ6IGFyZ3MucF9zb3VyY2Vfa2luZCxcbiAgICAgIGV4dHJhY3Rpb25faWQ6IHNvdXJjZS5leHRyYWN0aW9uX2lkLFxuICAgICAgZXhwaXJlc19hdDogXCIyMDk5LTAxLTAxVDAwOjAwOjAwWlwiLFxuICAgICAgZGVyaXZlZF9zaGEyNTY6IGFyZ3MucF9kZXJpdmVkX3NoYTI1NixcbiAgICAgIGRlcml2ZWRfYXNzdXJhbmNlOiBhcmdzLnBfc291cmNlX2tpbmQgPT09IFwieGxzeFwiXG4gICAgICAgID8gXCJjbGllbnRfZGVyaXZlZF90c3ZcIlxuICAgICAgICA6IG51bGwsXG4gICAgICBzdGF0ZTogc291cmNlLnN0YXRlLFxuICAgICAgcmVwbGF5ZWQ6ICEhZXhpc3RpbmcsXG4gICAgICBjb21wbGV0ZWRfcHJldmlldzogc291cmNlLmNvbXBsZXRlZF9wcmV2aWV3LFxuICAgICAgZXJyb3JfY29kZTogc291cmNlLmVycm9yX2NvZGUsXG4gICAgfSk7XG4gIH1cbiAgaWYgKFxuICAgIHBhdGguZW5kc1dpdGgoXCIvY29tcGxldGVfcm9zdGVyX2ltcG9ydF9wcmV2aWV3XCIpIHx8XG4gICAgcGF0aC5lbmRzV2l0aChcIi9mYWlsX3Jvc3Rlcl9pbXBvcnRfcHJldmlld1wiKVxuICApIHtcbiAgICBjb25zdCBhcmdzID0gcGF5bG9hZCBhcyBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPixcbiAgICAgIHNvdXJjZSA9IFsuLi5yb3N0ZXJTb3VyY2VzLnZhbHVlcygpXS5maW5kKChyKSA9PlxuICAgICAgICByLmltcG9ydF9pZCA9PT0gYXJncy5wX2ltcG9ydF9pZFxuICAgICAgKTtcbiAgICBpZiAoXG4gICAgICAhc291cmNlIHx8IGFyZ3MucF9hY3Rvcl9pZCAhPT0gdXNlcklkIHx8IGFyZ3MucF9zZXNzaW9uX2lkICE9PSBzZXNzaW9uSWRcbiAgICApIHJldHVybiBqc29uKHsgY29kZTogXCI0MjUwMVwiLCBtZXNzYWdlOiBcInJvc3Rlcl9pbXBvcnRfZm9yYmlkZGVuXCIgfSwgNDAzKTtcbiAgICBpZiAocGF0aC5lbmRzV2l0aChcIi9mYWlsX3Jvc3Rlcl9pbXBvcnRfcHJldmlld1wiKSkge1xuICAgICAgc291cmNlLnN0YXRlID0gXCJmYWlsZWRcIjtcbiAgICAgIHNvdXJjZS5lcnJvcl9jb2RlID0gYXJncy5wX2Vycm9yX2NvZGU7XG4gICAgICByZXR1cm4ganNvbih7XG4gICAgICAgIGNvbnRyYWN0X3ZlcnNpb246IDEsXG4gICAgICAgIG9rOiB0cnVlLFxuICAgICAgICBpbXBvcnRfaWQ6IHNvdXJjZS5pbXBvcnRfaWQsXG4gICAgICAgIHN0YXRlOiBcImZhaWxlZFwiLFxuICAgICAgICBlcnJvcl9jb2RlOiBhcmdzLnBfZXJyb3JfY29kZSxcbiAgICAgICAgcmVwbGF5ZWQ6IGZhbHNlLFxuICAgICAgfSk7XG4gICAgfVxuICAgIHNvdXJjZS5jb21wbGV0ZWRfcHJldmlldyA9IHJvc3RlclByZXZpZXcoXG4gICAgICBzb3VyY2UsXG4gICAgICBhcmdzLnBfY2FuZGlkYXRlcyBhcyBQYXJhbWV0ZXJzPHR5cGVvZiBub3JtYWxpemVSb3N0ZXJDYW5kaWRhdGVzPlswXSxcbiAgICApO1xuICAgIHNvdXJjZS5zdGF0ZSA9IFwicHJldmlld19yZWFkeVwiO1xuICAgIHJldHVybiBqc29uKHNvdXJjZS5jb21wbGV0ZWRfcHJldmlldyk7XG4gIH1cbiAgaWYgKHBhdGggPT09IFwiL3Jlc3QvdjEvcnBjL2NsYWltX25vdGlmaWNhdGlvbl9kZWxpdmVyaWVzXCIpIHJldHVybiBqc29uKFtdKTtcbiAgaWYgKHBhdGggPT09IFwiL3Jlc3QvdjEvcnBjL2NvbGxlY3Rfbm90aWZpY2F0aW9uX2hlYWx0aF92MlwiKSB7XG4gICAgcmV0dXJuIGpzb24oeyBwZW5kaW5nOiAwIH0pO1xuICB9XG4gIGlmIChwYXRoID09PSBcIi9yZXN0L3YxL3JwYy9hdHRlc3RlZF9zbXNfY29udHJhY3RfdmVyc2lvblwiKSB7XG4gICAgcmV0dXJuIGpzb24obW9kZS5zdGFydHNXaXRoKFwicmVjZWlwdF9cIikgPyAyIDogMSk7XG4gIH1cbiAgaWYgKHBhdGggPT09IFwiL3Jlc3QvdjEvcnBjL2FjY2VwdF9hdHRlc3RlZF9yZWNlaXB0X3YyXCIpIHtcbiAgICBjb25zdCBhcmdzID0gcGF5bG9hZCBhcyBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPjtcbiAgICByZXR1cm4ganNvbih7XG4gICAgICBjb250cmFjdF92ZXJzaW9uOiAyLFxuICAgICAgc3RvcmVkOiB0cnVlLFxuICAgICAgcmF3X3Ntc19pZDogY3J5cHRvLnJhbmRvbVVVSUQoKSxcbiAgICAgIGNsaWVudF9lbnZlbG9wZV9pZDogYXJncy5wX2NsaWVudF9lbnZlbG9wZV9pZCxcbiAgICAgIG93bmVyX3VzZXJfaWQ6IG1vZGUgPT09IFwicmVjZWlwdF9iYWRfYWNrXCJcbiAgICAgICAgPyBjcnlwdG8ucmFuZG9tVVVJRCgpXG4gICAgICAgIDogYXJncy5wX3JlY2VpdmVyX3VzZXJfaWQsXG4gICAgICBib2R5X3NoYTI1NjogYXJncy5wX2JvZHlfaGFzaCxcbiAgICB9KTtcbiAgfVxuICBpZiAocGF0aCA9PT0gXCIvZnVuY3Rpb25zL3YxL3BhcnNlLXBheW1lbnQtc21zXCIpIHtcbiAgICByZXR1cm4ganNvbih7IG9rOiBtb2RlICE9PSBcInJlY2VpcHRfZGVmZXJyZWRcIiB9KTtcbiAgfVxuICBpZiAocGF0aCA9PT0gXCIvcmVzdC92MS9ycGMvcmVjb3JkX29wZXJhdGlvbmFsX21ldHJpY192MVwiKSB7XG4gICAgaWYgKG1vZGUgPT09IFwicmVjZWlwdF9tZXRyaWNfZXJyb3JcIikge1xuICAgICAgcmV0dXJuIGpzb24oe1xuICAgICAgICBjb2RlOiBcInN5bnRoZXRpY19tZXRyaWNfZmFpbHVyZVwiLFxuICAgICAgICBtZXNzYWdlOiBcInNlY3JldC1wcm92aWRlci1jYW5hcnlcIixcbiAgICAgIH0sIDUwMCk7XG4gICAgfVxuICAgIGlmIChtb2RlID09PSBcInJlY2VpcHRfbWV0cmljX3RpbWVvdXRcIikge1xuICAgICAgYXdhaXQgbmV3IFByb21pc2UoKHJlc29sdmUpID0+IHNldFRpbWVvdXQocmVzb2x2ZSwgNTAwKSk7XG4gICAgfVxuICAgIHJldHVybiBqc29uKHRydWUpO1xuICB9XG4gIGlmIChwYXRoID09PSBcIi9yZXN0L3YxL3JwYy9pbmdlc3RfYmFua19ldmlkZW5jZVwiKSB7XG4gICAgcmV0dXJuIGpzb24oeyBpZDogXCJxYS1ldmlkZW5jZVwiLCBzdGF0dXM6IFwicmVjb3JkZWRcIiB9KTtcbiAgfVxuICBpZiAocGF0aCA9PT0gXCIvcmVzdC92MS9ycGMvZW5xdWV1ZV9ub3RpZmljYXRpb25fZXZlbnRcIikgcmV0dXJuIGpzb24obnVsbCk7XG4gIHJldHVybiBqc29uKHsgY29kZTogXCJRQV9VTkVYUEVDVEVEX0JBQ0tFTkRfUEFUSFwiLCBtZXNzYWdlOiBwYXRoIH0sIDUwMCk7XG59KTtcbnNlcnZlcnMucHVzaChiYWNrZW5kKTtcblxuLy8gU2lnbmVkIHJlY29yZGluZyByZXNwb25zZXMgZXhlcmNpc2UgZXhhY3QgSFRUUC9ITUFDIGFuZCBkdXJhYmxlLUFDS1xuLy8gcHJlcmVxdWlzaXRlcy4gVGhpcyBmaXh0dXJlIGRvZXMgbm90IHBhcnNlIGNvZGVjczsgYWN0dWFsIHNhbmRib3ggZGVjb2Rpbmdcbi8vIGhhcyBpdHMgb3duIGluZGVwZW5kZW50bHkgZXhlY3V0ZWQgbWFsaWNpb3VzLWNvcnB1cyBldmlkZW5jZS5cbmNvbnN0IGRlY29kZXJDb250cm9sbGVyID0gbmV3IEFib3J0Q29udHJvbGxlcigpO1xuY29udHJvbGxlcnMucHVzaChkZWNvZGVyQ29udHJvbGxlcik7XG5jb25zdCBkZWNvZGVyID0gcmVhbFNlcnZlKHtcbiAgaG9zdG5hbWU6IFwiMTI3LjAuMC4xXCIsXG4gIHBvcnQ6IDAsXG4gIHNpZ25hbDogZGVjb2RlckNvbnRyb2xsZXIuc2lnbmFsLFxuICBvbkxpc3RlbigpIHt9LFxufSwgYXN5bmMgKHJlcXVlc3QpID0+IHtcbiAgY29uc3QgcmF3ID0gYXdhaXQgcmVxdWVzdC50ZXh0KCksXG4gICAgaW5wdXQgPSBKU09OLnBhcnNlKHJhdyksXG4gICAgYnl0ZXMgPSBVaW50OEFycmF5LmZyb20oYXRvYihpbnB1dC5jb250ZW50X2Jhc2U2NCksIChjKSA9PiBjLmNoYXJDb2RlQXQoMCkpO1xuICByZWNvcmRzLnB1c2goe1xuICAgIHBhdGg6IFwiL2RlY29kZVwiLFxuICAgIG1ldGhvZDogcmVxdWVzdC5tZXRob2QsXG4gICAgaWRlbnRpdHk6IFwic3ludGhldGljX3NpZ25lZF9kZWNvZGVyXCIsXG4gICAgcmVxdWVzdF9pZDogaW5wdXQucmVxdWVzdF9pZCxcbiAgICByZXNlcnZhdGlvbl9pZDogaW5wdXQucmVzZXJ2YXRpb25faWQsXG4gICAgc291cmNlX3NoYTI1NjogaW5wdXQuc291cmNlX3NoYTI1NixcbiAgfSk7XG4gIGlmIChcbiAgICByZXF1ZXN0LmhlYWRlcnMuZ2V0KFwiYXV0aG9yaXphdGlvblwiKSAhPT1cbiAgICAgIFwiUm9zdGVyLUhNQUMgXCIgKyBhd2FpdCBobWFjU2hhMjU2SGV4KGRlY29kZXJTZWNyZXQsIHJhdylcbiAgKSByZXR1cm4ganNvbih7IGVycm9yOiBcInJvc3Rlcl9kZWNvZGVyX3VuYXZhaWxhYmxlXCIgfSwgNDAxKTtcbiAgaWYgKGF3YWl0IHNoYShieXRlcykgIT09IGlucHV0LnNvdXJjZV9zaGEyNTYpIHtcbiAgICByZXR1cm4ganNvbih7IGVycm9yOiBcInJvc3Rlcl9pbnZhbGlkX2ZpbGVcIiB9LCA0MjIpO1xuICB9XG4gIGlmIChtb2RlID09PSBcInJvc3Rlcl9kZWNvZGVyX3JlamVjdFwiKSB7XG4gICAgcmV0dXJuIGpzb24oeyBlcnJvcjogXCJyb3N0ZXJfYW5pbWF0aW9uX2xpbWl0XCIgfSwgNDIyKTtcbiAgfVxuICBjb25zdCByZWNlaXB0ID0ge1xuICAgIGNvbnRyYWN0X3ZlcnNpb246IDEsXG4gICAgb2s6IHRydWUsXG4gICAgcmVxdWVzdF9pZDogaW5wdXQucmVxdWVzdF9pZCxcbiAgICByZXNlcnZhdGlvbl9pZDogaW5wdXQucmVzZXJ2YXRpb25faWQsXG4gICAgbm9uY2U6IG1vZGUgPT09IFwicm9zdGVyX2JhZF9ub25jZVwiID8gY3J5cHRvLnJhbmRvbVVVSUQoKSA6IGlucHV0Lm5vbmNlLFxuICAgIGlzc3VlZF9hdDogaW5wdXQuaXNzdWVkX2F0LFxuICAgIGtpbmQ6IGlucHV0LmtpbmQsXG4gICAgbWltZTogaW5wdXQubWltZSxcbiAgICBwb2xpY3lfdmVyc2lvbjogaW5wdXQucG9saWN5X3ZlcnNpb24sXG4gICAgdG9vbGNoYWluOiBST1NURVJfREVDT0RFUl9UT09MQ0hBSU4sXG4gICAgc291cmNlX3NoYTI1NjogaW5wdXQuc291cmNlX3NoYTI1NixcbiAgICBzb3VyY2Vfc2l6ZTogYnl0ZXMubGVuZ3RoLFxuICAgIGRlcml2ZWRfc2hhMjU2OiBudWxsLFxuICAgIGRlcml2ZWRfY29udGVudDogbnVsbCxcbiAgICBmcmFtZXM6IDEsXG4gICAgcGFnZXM6IDAsXG4gICAgcGl4ZWxzOiA2LFxuICAgIGV4cGFuZGVkX2J5dGVzOiAyNCxcbiAgICBkZWNvZGVyX2J1aWxkX3NoYTI1NjogZGVjb2RlckJ1aWxkLFxuICB9O1xuICBjb25zdCB0ZXh0ID0gSlNPTi5zdHJpbmdpZnkocmVjZWlwdCk7XG4gIGRlY29kZXJSZWNlaXB0cy5zZXQoaW5wdXQucmVzZXJ2YXRpb25faWQsIHtcbiAgICAuLi5yZWNlaXB0LFxuICAgIHJlY2VpcHRfc2hhMjU2OiBhd2FpdCBzaGEodGV4dCksXG4gIH0pO1xuICByZXR1cm4ganNvbih7XG4gICAgcGF5bG9hZDogdGV4dCxcbiAgICBzaWduYXR1cmU6IG1vZGUgPT09IFwicm9zdGVyX2JhZF9zaWduYXR1cmVcIlxuICAgICAgPyBcIjBcIi5yZXBlYXQoNjQpXG4gICAgICA6IGF3YWl0IGhtYWNTaGEyNTZIZXgoZGVjb2RlclNlY3JldCwgdGV4dCksXG4gIH0pO1xufSk7XG5zZXJ2ZXJzLnB1c2goZGVjb2Rlcik7XG5cbi8vIFN5bnRoZXRpYyBhcHByb3ZhbCBvbmx5OiBiaW5kIHRoZSBhY3R1YWwgbG9jYWwgZml4dHVyZSByZWNlaXB0IHR1cGxlLlxuLy8gSXQgcmVwcmVzZW50cyBubyBvd25lci92ZW5kb3IgYWNjZXB0YW5jZSBhbmQgZG9lcyBub3QgZW5hYmxlIHByb3ZpZGVyIGFjY2Vzcy5cbmNvbnN0IGRlY29kZXJVcmwgPSBgaHR0cDovLzEyNy4wLjAuMToke2RlY29kZXIuYWRkci5wb3J0fS9kZWNvZGVgO1xuY29uc3Qgcm9zdGVyTW9kZWwgPSBcInN5bnRoZXRpYy1tb2RlbFwiO1xuY29uc3Qgcm9zdGVyQXBwcm92YWwgPSBhd2FpdCBzeW50aGV0aWNSb3N0ZXJBaUFwcHJvdmFsKFxuICByb3N0ZXJNb2RlbCxcbiAgZGVjb2RlclVybCxcbiAgZGVjb2RlckJ1aWxkLFxuKTtcbmNvbnN0IHJvc3RlckFwcHJvdmFsRW52aXJvbm1lbnQgPSBPYmplY3QuZnJlZXplKHtcbiAgUk9TVEVSX0FJX0FQUFJPVkFMX0pTT046IHJvc3RlckFwcHJvdmFsLmFpQXBwcm92YWxKc29uLFxuICBST1NURVJfQUlfQVBQUk9WQUxfU0hBMjU2OiByb3N0ZXJBcHByb3ZhbC5haUFwcHJvdmFsU2hhMjU2LFxuICBPUEVOQUlfT1JHQU5JWkFUSU9OX0lEOiByb3N0ZXJBcHByb3ZhbC5vcGVuQWlPcmdhbml6YXRpb25JZCxcbiAgT1BFTkFJX1BST0pFQ1RfSUQ6IHJvc3RlckFwcHJvdmFsLm9wZW5BaVByb2plY3RJZCxcbn0pO1xuXG5mb3IgKFxuICBjb25zdCBba2V5LCB2YWx1ZV0gb2YgT2JqZWN0LmVudHJpZXMoe1xuICAgIFNVUEFCQVNFX1VSTDogYGh0dHA6Ly8xMjcuMC4wLjE6JHtiYWNrZW5kLmFkZHIucG9ydH1gLFxuICAgIFNVUEFCQVNFX0FOT05fS0VZOiBcInFhLWFub25cIixcbiAgICBTVVBBQkFTRV9TRVJWSUNFX1JPTEVfS0VZOiBcInFhLXNlcnZpY2VcIixcbiAgICBJTlRFUk5BTF9GVU5DVElPTl9TRUNSRVQ6IGludGVybmFsU2VjcmV0LFxuICAgIFNFTkRfU01TX0hPT0tfU0VDUkVUOiBob29rU2VjcmV0LFxuICAgIFdIQVRTQVBQX0NMT1VEX0RSWV9SVU46IFwiZmFsc2VcIixcbiAgICBXSEFUU0FQUF9HUkFQSF9BUElfVkVSU0lPTjogXCJ2MjUuMFwiLFxuICAgIFdIQVRTQVBQX0NMT1VEX09UUF9BVVRIX0JVVFRPTjogXCJ0cnVlXCIsXG4gICAgV0hBVFNBUFBfQVVUSF9URU1QTEFURV9MQU5HVUFHRTogXCJlbl9VU1wiLFxuICAgIFdIQVRTQVBQX0NMT1VEX0FQSV9UT0tFTjogXCJxYS1kaXNhYmxlZC1wcm92aWRlclwiLFxuICAgIFdIQVRTQVBQX1BIT05FX05VTUJFUl9JRDogXCIxMjM0XCIsXG4gICAgUk9TVEVSX0RFQ09ERVJfVVJMOiBkZWNvZGVyVXJsLFxuICAgIFJPU1RFUl9ERUNPREVSX1NFQ1JFVDogZGVjb2RlclNlY3JldCxcbiAgICBST1NURVJfREVDT0RFUl9CVUlMRF9TSEEyNTY6IGRlY29kZXJCdWlsZCxcbiAgICBPUEVOQUlfUk9TVEVSX01PREVMOiByb3N0ZXJNb2RlbCxcbiAgICAuLi5yb3N0ZXJBcHByb3ZhbEVudmlyb25tZW50LFxuICAgIFdIQVRTQVBQX0FVVEhfVEVNUExBVEVfTkFNRTogXCJxYV9kaXNhYmxlZF9wcm92aWRlclwiLFxuICB9KVxuKSBEZW5vLmVudi5zZXQoa2V5LCB2YWx1ZSk7XG5cbmNvbnN0IHJlcG9ydDogUmVjb3JkPHN0cmluZywgdW5rbm93bj4gPSB7XG4gIHN0YXJ0ZWRfYXQ6IG5ldyBEYXRlKCkudG9JU09TdHJpbmcoKSxcbiAgZmluYWxfYWNjZXB0YW5jZTogZmFsc2UsXG4gIG1vZGU6XG4gICAgXCJyZWFsX2VkZ2VfaHR0cF93aXRoX3JlY29yZGluZ19zeW50aGV0aWNfYXV0aF9wb3N0Z3Jlc3RfYW5kX2Rpc2FibGVkX3Byb3ZpZGVyc1wiLFxuICBjaGVja3MsXG4gIGVudHJ5cG9pbnRzLFxuICBkZXBlbmRlbmN5X3JlY29yZHM6IHJlY29yZHMsXG4gIGJsb2NrZWRfcHJvdmlkZXJfYXR0ZW1wdHM6IHByb3ZpZGVyQXR0ZW1wdHMsXG4gIGxpbWl0YXRpb25zOiBbXG4gICAgXCJObyBwbGF0Zm9ybSB2ZXJpZnlfand0IGdhdGV3YXkgb3IgcmVhbCBBdXRoIHNpZ24taW5cIixcbiAgICBcIlN5bnRoZXRpYyBkZXBlbmRlbmN5IHJlc3BvbnNlcyBkbyBub3QgcHJvdmUgU1FMIHBlcnNpc3RlbmNlIG9yIFJMU1wiLFxuICAgIFwiTm8gV2hhdHNBcHAvQVBOcy9GQ00vUGxheS9PcGVuQUkvcHJvdmlkZXIgZGVsaXZlcnkgb3IgYWNjZXB0YW5jZVwiLFxuICBdLFxufTtcblxuZnVuY3Rpb24gY2hlY2soXG4gIGxhYmVsOiBzdHJpbmcsXG4gIHBhc3NlZDogYm9vbGVhbixcbiAgZXZpZGVuY2U6IFJlY29yZDxzdHJpbmcsIHVua25vd24+ID0ge30sXG4pIHtcbiAgY2hlY2tzLnB1c2goeyBsYWJlbCwgc3RhdHVzOiBwYXNzZWQgPyBcInBhc3NcIiA6IFwiZmFpbFwiLCAuLi5ldmlkZW5jZSB9KTtcbiAgY29uc29sZS5sb2coXG4gICAgXCJRQV9FREdFX1BST0dSRVNTPVwiICtcbiAgICAgIEpTT04uc3RyaW5naWZ5KHsgbGFiZWwsIHBhc3NlZCwgZGVwZW5kZW5jeV9jb3VudDogcmVjb3Jkcy5sZW5ndGggfSksXG4gICk7XG59XG5cbmFzeW5jIGZ1bmN0aW9uIHJlcXVlc3QoXG4gIHNsdWc6IHN0cmluZyxcbiAgbGFiZWw6IHN0cmluZyxcbiAgb3B0aW9uczoge1xuICAgIG1ldGhvZD86IHN0cmluZztcbiAgICBib2R5Pzogc3RyaW5nO1xuICAgIGhlYWRlcnM/OiBSZWNvcmQ8c3RyaW5nLCBzdHJpbmc+O1xuICB9ID0ge30sXG4pIHtcbiAgY29uc3Qgc3RhcnQgPSByZWNvcmRzLmxlbmd0aDtcbiAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBmZXRjaChlbnRyeXBvaW50c1tzbHVnXSwge1xuICAgIG1ldGhvZDogb3B0aW9ucy5tZXRob2QgPz8gXCJQT1NUXCIsXG4gICAgYm9keTogb3B0aW9ucy5ib2R5ID8/IFwie31cIixcbiAgICBoZWFkZXJzOiB7IFwiY29udGVudC10eXBlXCI6IFwiYXBwbGljYXRpb24vanNvblwiLCAuLi5vcHRpb25zLmhlYWRlcnMgfSxcbiAgICBzaWduYWw6IEFib3J0U2lnbmFsLnRpbWVvdXQoMTBfMDAwKSxcbiAgfSk7XG4gIGNvbnN0IHRleHQgPSBhd2FpdCByZXNwb25zZS50ZXh0KCk7XG4gIGxldCBib2R5OiB1bmtub3duID0gbnVsbDtcbiAgdHJ5IHtcbiAgICBib2R5ID0gSlNPTi5wYXJzZSh0ZXh0KTtcbiAgfSBjYXRjaCB7IC8qIE9QVElPTlMgYm9keSBpcyBwbGFpbiB0ZXh0LiAqLyB9XG4gIHJldHVybiB7XG4gICAgbGFiZWwsXG4gICAgaHR0cF9zdGF0dXM6IHJlc3BvbnNlLnN0YXR1cyxcbiAgICByZXNwb25zZTogYm9keSxcbiAgICBjb3JzOiByZXNwb25zZS5oZWFkZXJzLmdldChcImFjY2Vzcy1jb250cm9sLWFsbG93LW9yaWdpblwiKSxcbiAgICBkZXBlbmRlbmNpZXM6IHJlY29yZHMuc2xpY2Uoc3RhcnQpLFxuICAgIG5vX3N0b3JlOiByZXNwb25zZS5oZWFkZXJzLmdldChcImNhY2hlLWNvbnRyb2xcIik/LmluY2x1ZGVzKFwibm8tc3RvcmVcIikgPz9cbiAgICAgIGZhbHNlLFxuICB9O1xufVxuXG50cnkge1xuICBjb25zdCBjb25maWcgPSBhd2FpdCBEZW5vLnJlYWRUZXh0RmlsZShcbiAgICBuZXcgVVJMKFwiLi4vLi4vc3VwYWJhc2UvY29uZmlnLnRvbWxcIiwgaW1wb3J0Lm1ldGEudXJsKSxcbiAgKTtcbiAgY29uc3QgbmFtZXMgPSBbLi4uY29uZmlnLm1hdGNoQWxsKC9eXFxbZnVuY3Rpb25zXFwuKFteXFxdXSspXFxdL2dtKV0ubWFwKChcbiAgICBtYXRjaCxcbiAgKSA9PiBtYXRjaFsxXSkuc29ydCgpO1xuICByZXBvcnQuY29uZmlndXJlZF9mdW5jdGlvbnMgPSBuYW1lcztcbiAgY29uc3Qgc291cmNlTmFtZXM6IHN0cmluZ1tdID0gW107XG4gIGZvciBhd2FpdCAoXG4gICAgY29uc3QgZW50cnkgb2YgRGVuby5yZWFkRGlyKFxuICAgICAgbmV3IFVSTChcIi4uLy4uL3N1cGFiYXNlL2Z1bmN0aW9uc1wiLCBpbXBvcnQubWV0YS51cmwpLFxuICAgIClcbiAgKSB7XG4gICAgaWYgKCFlbnRyeS5pc0RpcmVjdG9yeSkgY29udGludWU7XG4gICAgdHJ5IHtcbiAgICAgIGlmIChcbiAgICAgICAgKGF3YWl0IERlbm8uc3RhdChcbiAgICAgICAgICBuZXcgVVJMKFxuICAgICAgICAgICAgYC4uLy4uL3N1cGFiYXNlL2Z1bmN0aW9ucy8ke2VudHJ5Lm5hbWV9L2luZGV4LnRzYCxcbiAgICAgICAgICAgIGltcG9ydC5tZXRhLnVybCxcbiAgICAgICAgICApLFxuICAgICAgICApKS5pc0ZpbGVcbiAgICAgICkgc291cmNlTmFtZXMucHVzaChlbnRyeS5uYW1lKTtcbiAgICB9IGNhdGNoIChlcnJvcikge1xuICAgICAgaWYgKCEoZXJyb3IgaW5zdGFuY2VvZiBEZW5vLmVycm9ycy5Ob3RGb3VuZCkpIHRocm93IGVycm9yO1xuICAgIH1cbiAgfVxuICBzb3VyY2VOYW1lcy5zb3J0KCk7XG4gIHJlcG9ydC5zb3VyY2VfZW50cnlwb2ludHMgPSBzb3VyY2VOYW1lcztcbiAgY29uc3QgbG9hZGVyTmFtZXMgPSBPYmplY3Qua2V5cyhlbnRyeXBvaW50TG9hZGVycykuc29ydCgpO1xuICByZXBvcnQubGl0ZXJhbF9sb2FkZXJfZW50cnlwb2ludHMgPSBsb2FkZXJOYW1lcztcbiAgY2hlY2soXG4gICAgXCJjb25maWd1cmVkIGZ1bmN0aW9ucyBleGFjdGx5IG1hdGNoIGV4aXN0aW5nIGV4ZWN1dGFibGUgZW50cnlwb2ludHNcIixcbiAgICBKU09OLnN0cmluZ2lmeShuYW1lcykgPT09IEpTT04uc3RyaW5naWZ5KHNvdXJjZU5hbWVzKSxcbiAgKTtcbiAgY29uc3QgbG9hZGVyUGFyaXR5ID0gbmFtZXMubGVuZ3RoID4gMCAmJiBuZXcgU2V0KG5hbWVzKS5zaXplID09PSBuYW1lcy5sZW5ndGggJiZcbiAgICBKU09OLnN0cmluZ2lmeShsb2FkZXJOYW1lcykgPT09IEpTT04uc3RyaW5naWZ5KG5hbWVzKSAmJlxuICAgIEpTT04uc3RyaW5naWZ5KGxvYWRlck5hbWVzKSA9PT0gSlNPTi5zdHJpbmdpZnkoc291cmNlTmFtZXMpO1xuICBjaGVjayhcbiAgICBcImxpdGVyYWwgbG9hZGVycyBleGFjdGx5IG1hdGNoIHVuaXF1ZSBjb25maWd1cmVkIHNvdXJjZSBlbnRyeXBvaW50c1wiLFxuICAgIGxvYWRlclBhcml0eSxcbiAgKTtcbiAgaWYgKCFsb2FkZXJQYXJpdHkpIHtcbiAgICB0aHJvdyBuZXcgRXJyb3IoXCJMaXRlcmFsIGxvYWRlci9jb25maWcvc291cmNlIGVudHJ5cG9pbnQgcGFyaXR5IHJlcXVpcmVkXCIpO1xuICB9XG4gIGNoZWNrKFxuICAgIFwiZXh0ZXJuYWwgcHJvdmlkZXIgbmV0d29yayBkZW5pZWRcIixcbiAgICAoYXdhaXQgRGVuby5wZXJtaXNzaW9ucy5xdWVyeSh7XG4gICAgICBuYW1lOiBcIm5ldFwiLFxuICAgICAgaG9zdDogXCJncmFwaC5mYWNlYm9vay5jb206NDQzXCIsXG4gICAgfSkpLnN0YXRlID09PSBcImRlbmllZFwiLFxuICApO1xuICBjb25zdCBpbmZyYXN0cnVjdHVyZVNlcnZlckNvdW50ID0gc2VydmVycy5sZW5ndGg7XG4gIGZvciAoY29uc3Qgc2x1ZyBvZiBuYW1lcykge1xuICAgIC8vIENoYW5nZSBvbmx5IHRoZSBsaXN0ZW5pbmcgYWRkcmVzcy4gVGhlIHJlcG9zaXRvcnkncyBhY3R1YWwgaGFuZGxlciBydW5zLlxuICAgIERlbm8uc2VydmUgPSAoKGhhbmRsZXI6IERlbm8uU2VydmVIYW5kbGVyPERlbm8uTmV0QWRkcj4pID0+IHtcbiAgICAgIGNvbnN0IGNvbnRyb2xsZXIgPSBuZXcgQWJvcnRDb250cm9sbGVyKCk7XG4gICAgICBjb250cm9sbGVycy5wdXNoKGNvbnRyb2xsZXIpO1xuICAgICAgY29uc3Qgc2VydmVyID0gcmVhbFNlcnZlKHtcbiAgICAgICAgaG9zdG5hbWU6IFwiMTI3LjAuMC4xXCIsXG4gICAgICAgIHBvcnQ6IDAsXG4gICAgICAgIHNpZ25hbDogY29udHJvbGxlci5zaWduYWwsXG4gICAgICAgIG9uTGlzdGVuKCkge30sXG4gICAgICB9LCBoYW5kbGVyKTtcbiAgICAgIHNlcnZlcnMucHVzaChzZXJ2ZXIpO1xuICAgICAgc3RhcnRzW3NsdWddID0gKHN0YXJ0c1tzbHVnXSA/PyAwKSArIDE7XG4gICAgICBlbnRyeXBvaW50c1tzbHVnXSA9IGBodHRwOi8vMTI3LjAuMC4xOiR7c2VydmVyLmFkZHIucG9ydH1gO1xuICAgICAgcmV0dXJuIHNlcnZlcjtcbiAgICB9KSBhcyB0eXBlb2YgRGVuby5zZXJ2ZTtcbiAgICBhd2FpdCBlbnRyeXBvaW50TG9hZGVyc1tzbHVnXSgpO1xuICB9XG4gIERlbm8uc2VydmUgPSByZWFsU2VydmU7XG4gIGNoZWNrKFxuICAgIFwiZXZlcnkgY29uZmlndXJlZCBlbnRyeXBvaW50IHN0YXJ0ZWQgZXhhY3RseSBvbmNlXCIsXG4gICAgSlNPTi5zdHJpbmdpZnkoT2JqZWN0LmtleXMoZW50cnlwb2ludHMpLnNvcnQoKSkgPT09IEpTT04uc3RyaW5naWZ5KG5hbWVzKSAmJlxuICAgICAgbmFtZXMuZXZlcnkoKHNsdWcpID0+IHN0YXJ0c1tzbHVnXSA9PT0gMSkgJiYgc2VydmVycy5sZW5ndGggLSBpbmZyYXN0cnVjdHVyZVNlcnZlckNvdW50ID09PSBuYW1lcy5sZW5ndGgsXG4gICk7XG4gIGZvciAoY29uc3Qgc2x1ZyBvZiBuYW1lcykge1xuICAgIGlmIChzbHVnID09PSBcImNvbGxlY3QtcmVjZWlwdC1zdWNjZXNzb3ItZ2F0ZXdheVwiKSB7XG4gICAgICAvLyBUaGUgc3VjY2Vzc29yIHdpcmUgaGFzIGl0cyBvd24gYXVkaWVuY2UvZmFtaWx5IGFuZCBpbmNsdWRlcyBhIGZhbHNlXG4gICAgICAvLyBzZW5kLWF1dGhvcml0eSBmaWVsZCBldmVuIGluIHNjaGVtYS9tZXRob2QgcmVmdXNhbHMuIFRoZXNlIHVuc2lnbmVkXG4gICAgICAvLyBwcmVzZW5jZSBjaGVja3MgbXVzdCBzdG9wIGJlZm9yZSBrZXkgbG9va3VwIG9yIGFueSBzdWNjZXNzb3IgUlBDLlxuICAgICAgY29uc3QgYm9keSA9IEpTT04uc3RyaW5naWZ5KHtcbiAgICAgICAgY29udHJhY3RfdmVyc2lvbjogMSxcbiAgICAgICAgcHJvdG9jb2xfZmFtaWx5OiBcInJlY2VpcHRfc3VjY2Vzc29yXCIsXG4gICAgICAgIGF1ZGllbmNlOiBcImNvbGxlY3QtcmVjZWlwdC1zdWNjZXNzb3ItZ2F0ZXdheVwiLFxuICAgICAgICBhY3Rpb246IFwiZGlzcGF0Y2hfZ3JhbnRcIixcbiAgICAgICAgZGV2aWNlX2lkOiB1c2VySWQsXG4gICAgICAgIHJlcXVlc3RfaWQ6IGNyeXB0by5yYW5kb21VVUlEKCksXG4gICAgICAgIGlzc3VlZF9hdDogbmV3IERhdGUoKS50b0lTT1N0cmluZygpLFxuICAgICAgICBwYXlsb2FkOiB7fSxcbiAgICAgIH0pO1xuICAgICAgZm9yIChjb25zdCBtZXRob2Qgb2YgW1wiT1BUSU9OU1wiLCBcIlBVVFwiXSkge1xuICAgICAgICBjb25zdCByZWZ1c2FsID0gYXdhaXQgcmVxdWVzdChcbiAgICAgICAgICBzbHVnLFxuICAgICAgICAgIGAke3NsdWd9OiBzdWNjZXNzb3IgcHJvdG9jb2wgcmVmdXNlcyAke21ldGhvZH1gLFxuICAgICAgICAgIHsgbWV0aG9kIH0sXG4gICAgICAgICk7XG4gICAgICAgIGNoZWNrKFxuICAgICAgICAgIHJlZnVzYWwubGFiZWwsXG4gICAgICAgICAgcmVmdXNhbC5odHRwX3N0YXR1cyA9PT0gNDA1ICYmIHJlZnVzYWwuY29ycyA9PT0gbnVsbCAmJlxuICAgICAgICAgICAgcmVmdXNhbC5ub19zdG9yZSAmJiByZWZ1c2FsLmRlcGVuZGVuY2llcy5sZW5ndGggPT09IDAgJiZcbiAgICAgICAgICAgIEpTT04uc3RyaW5naWZ5KHJlZnVzYWwucmVzcG9uc2UpID09PSBKU09OLnN0cmluZ2lmeSh7XG4gICAgICAgICAgICAgIG9rOiBmYWxzZSxcbiAgICAgICAgICAgICAgY29kZTogXCJHQVRFV0FZX1BPU1RfUkVRVUlSRURcIixcbiAgICAgICAgICAgICAgc2VuZF9hdXRob3JpdHk6IGZhbHNlLFxuICAgICAgICAgICAgfSksXG4gICAgICAgICAgcmVmdXNhbCxcbiAgICAgICAgKTtcbiAgICAgIH1cbiAgICAgIGZvciAoY29uc3QgW2xhYmVsLCByZXF1ZXN0Qm9keSwgaGVhZGVyc10gb2YgW1xuICAgICAgICBbXCJlbXB0eSB1bnNpZ25lZCBlbnZlbG9wZVwiLCBcInt9XCIsIHt9XSxcbiAgICAgICAgW1widW5zaWduZWQgc3VjY2Vzc29yIGVudmVsb3BlXCIsIGJvZHksIHt9XSxcbiAgICAgICAgW1wiYmVhcmVyIGNhbm5vdCByZXBsYWNlIHN1Y2Nlc3NvciBzaWduYXR1cmVcIiwgYm9keSwge1xuICAgICAgICAgIGF1dGhvcml6YXRpb246IFwiQmVhcmVyIHFhLWludmFsaWRcIixcbiAgICAgICAgfV0sXG4gICAgICAgIFtcIm1hbGZvcm1lZCBzdWNjZXNzb3Igc2lnbmF0dXJlXCIsIGJvZHksIHtcbiAgICAgICAgICBcIlgtQ29sbGVjdC1HYXRld2F5LUtleS1JZFwiOiBcImFcIi5yZXBlYXQoNjQpLFxuICAgICAgICAgIFwiWC1Db2xsZWN0LUdhdGV3YXktU2lnbmF0dXJlXCI6IGJ0b2EoXCJtYWxmb3JtZWRcIiksXG4gICAgICAgIH1dLFxuICAgICAgXSBhcyBBcnJheTxbc3RyaW5nLCBzdHJpbmcsIFJlY29yZDxzdHJpbmcsIHN0cmluZz5dPikge1xuICAgICAgICBjb25zdCByZWZ1c2FsID0gYXdhaXQgcmVxdWVzdChzbHVnLCBgJHtzbHVnfTogJHtsYWJlbH1gLCB7XG4gICAgICAgICAgYm9keTogcmVxdWVzdEJvZHksXG4gICAgICAgICAgaGVhZGVycyxcbiAgICAgICAgfSk7XG4gICAgICAgIGNoZWNrKFxuICAgICAgICAgIHJlZnVzYWwubGFiZWwsXG4gICAgICAgICAgcmVmdXNhbC5odHRwX3N0YXR1cyA9PT0gNDAwICYmIHJlZnVzYWwuY29ycyA9PT0gbnVsbCAmJlxuICAgICAgICAgICAgcmVmdXNhbC5ub19zdG9yZSAmJiByZWZ1c2FsLmRlcGVuZGVuY2llcy5sZW5ndGggPT09IDAgJiZcbiAgICAgICAgICAgIEpTT04uc3RyaW5naWZ5KHJlZnVzYWwucmVzcG9uc2UpID09PSBKU09OLnN0cmluZ2lmeSh7XG4gICAgICAgICAgICAgIG9rOiBmYWxzZSxcbiAgICAgICAgICAgICAgY29kZTogXCJHQVRFV0FZX1JFUVVFU1RfSU5WQUxJRFwiLFxuICAgICAgICAgICAgICBzZW5kX2F1dGhvcml0eTogZmFsc2UsXG4gICAgICAgICAgICB9KSxcbiAgICAgICAgICByZWZ1c2FsLFxuICAgICAgICApO1xuICAgICAgfVxuICAgICAgY29udGludWU7XG4gICAgfVxuICAgIGlmIChzbHVnID09PSBcImNvbGxlY3QtYW5kcm9pZC1nYXRld2F5XCIgfHwgc2x1ZyA9PT0gXCJjb2xsZWN0LXJlY2VpcHQtc3VwZXJ2aXNvclwiKSB7XG4gICAgICAvLyBEZWRpY2F0ZWQgc2lnbmVkIHByb3RvY29scyBkbyBub3QgYWNjZXB0IGJyb3dzZXIgQ09SUyBvciBiZWFyZXIgQXV0aC5cbiAgICAgIGNvbnN0IHN1cGVydmlzb3IgPSBzbHVnID09PSBcImNvbGxlY3QtcmVjZWlwdC1zdXBlcnZpc29yXCI7XG4gICAgICBjb25zdCBwcmVmaXggPSBzdXBlcnZpc29yID8gXCJTVVBFUlZJU09SXCIgOiBcIkdBVEVXQVlcIjtcbiAgICAgIGNvbnN0IGhlYWRlciA9IHN1cGVydmlzb3IgPyBcIlN1cGVydmlzb3JcIiA6IFwiR2F0ZXdheVwiO1xuICAgICAgY29uc3QgYm9keSA9IEpTT04uc3RyaW5naWZ5KHN1cGVydmlzb3IgPyB7XG4gICAgICAgIGNvbnRyYWN0X3ZlcnNpb246IDEsIGF1ZGllbmNlOiBcImNvbGxlY3QucmVjZWlwdC1zdXBlcnZpc29yLnYxL2xoYm93cGJjcHdvaXBhcndud2d0XCIsXG4gICAgICAgIGFjdGlvbjogXCJwcm92ZV9rZXlcIiwgcHJpbmNpcGFsX2lkOiB1c2VySWQsIHJlcXVlc3RfaWQ6IGNyeXB0by5yYW5kb21VVUlEKCksXG4gICAgICAgIGlzc3VlZF9hdDogbmV3IERhdGUoKS50b0lTT1N0cmluZygpLCBwYXlsb2FkOiB7fSxcbiAgICAgIH0gOiB7XG4gICAgICAgIGNvbnRyYWN0X3ZlcnNpb246IDEsIGFjdGlvbjogXCJyZWNvbmNpbGVcIiwgZGV2aWNlX2lkOiB1c2VySWQsXG4gICAgICAgIHJlcXVlc3RfaWQ6IGNyeXB0by5yYW5kb21VVUlEKCksIGlzc3VlZF9hdDogbmV3IERhdGUoKS50b0lTT1N0cmluZygpLFxuICAgICAgICBwYXlsb2FkOiB7dGFyZ2V0X3JlcXVlc3RfaWQ6IGNyeXB0by5yYW5kb21VVUlEKCl9LFxuICAgICAgfSk7XG4gICAgICBmb3IgKGNvbnN0IG1ldGhvZCBvZiBbXCJPUFRJT05TXCIsIFwiUFVUXCJdKSB7XG4gICAgICAgIGNvbnN0IHJlZnVzYWwgPSBhd2FpdCByZXF1ZXN0KHNsdWcsIGAke3NsdWd9OiBzaWduZWQgcHJvdG9jb2wgcmVmdXNlcyAke21ldGhvZH1gLCB7bWV0aG9kfSk7XG4gICAgICAgIGNoZWNrKHJlZnVzYWwubGFiZWwsIHJlZnVzYWwuaHR0cF9zdGF0dXMgPT09IDQwNSAmJiByZWZ1c2FsLmNvcnMgPT09IG51bGwgJiZcbiAgICAgICAgICByZWZ1c2FsLm5vX3N0b3JlICYmIHJlZnVzYWwuZGVwZW5kZW5jaWVzLmxlbmd0aCA9PT0gMCAmJlxuICAgICAgICAgIEpTT04uc3RyaW5naWZ5KHJlZnVzYWwucmVzcG9uc2UpID09PSBKU09OLnN0cmluZ2lmeSh7b2s6IGZhbHNlLFxuICAgICAgICAgICAgY29kZTogcHJlZml4ICsgKHN1cGVydmlzb3IgPyBcIl9NRVRIT0RfUkVGVVNFRFwiIDogXCJfUE9TVF9SRVFVSVJFRFwiKX0pLCByZWZ1c2FsKTtcbiAgICAgIH1cbiAgICAgIGZvciAoY29uc3QgW2xhYmVsLCBoZWFkZXJzXSBvZiBbXG4gICAgICAgIFtcInVuc2lnbmVkIGVudmVsb3BlXCIsIHt9XSxcbiAgICAgICAgW1wiYmVhcmVyIGNhbm5vdCByZXBsYWNlIGRlZGljYXRlZCBzaWduYXR1cmVcIiwge2F1dGhvcml6YXRpb246IFwiQmVhcmVyIHFhLWludmFsaWRcIn1dLFxuICAgICAgICBbXCJtYWxmb3JtZWQgZGVkaWNhdGVkIHNpZ25hdHVyZVwiLCB7XG4gICAgICAgICAgW1wiWC1Db2xsZWN0LVwiICsgaGVhZGVyICsgXCItS2V5LUlkXCJdOiBcImFcIi5yZXBlYXQoNjQpLFxuICAgICAgICAgIFtcIlgtQ29sbGVjdC1cIiArIGhlYWRlciArIFwiLVNpZ25hdHVyZVwiXTogYnRvYShcIm1hbGZvcm1lZFwiKSxcbiAgICAgICAgfV0sXG4gICAgICBdIGFzIEFycmF5PFtzdHJpbmcsIFJlY29yZDxzdHJpbmcsIHN0cmluZz5dPikge1xuICAgICAgICBjb25zdCByZWZ1c2FsID0gYXdhaXQgcmVxdWVzdChzbHVnLCBgJHtzbHVnfTogJHtsYWJlbH1gLCB7Ym9keSwgaGVhZGVyc30pO1xuICAgICAgICBjaGVjayhyZWZ1c2FsLmxhYmVsLCByZWZ1c2FsLmh0dHBfc3RhdHVzID09PSA0MDAgJiYgcmVmdXNhbC5jb3JzID09PSBudWxsICYmXG4gICAgICAgICAgcmVmdXNhbC5ub19zdG9yZSAmJiByZWZ1c2FsLmRlcGVuZGVuY2llcy5sZW5ndGggPT09IDAgJiZcbiAgICAgICAgICBKU09OLnN0cmluZ2lmeShyZWZ1c2FsLnJlc3BvbnNlKSA9PT0gSlNPTi5zdHJpbmdpZnkoe29rOiBmYWxzZSwgY29kZTogcHJlZml4ICsgXCJfUkVRVUVTVF9JTlZBTElEXCJ9KSwgcmVmdXNhbCk7XG4gICAgICB9XG4gICAgICBjb250aW51ZTtcbiAgICB9XG4gICAgaWYgKHNsdWcgPT09IFwiY29sbGVjdC1yZWNlaXB0LWV4Y2VwdGlvbi13b3JrZXJcIikge1xuICAgICAgLy8gVGhpcyBpcyBhIHNjaGVkdWxlci1vbmx5IGVuZHBvaW50LCBub3QgYSBicm93c2VyL0F1dGggZW5kcG9pbnQuIEl0c1xuICAgICAgLy8gcHJvZHVjdGlvbiBpbmRleCByZWZ1c2VzIHRvIGNvbmZpZ3VyZSBhIHdvcmtlciBjcmVkZW50aWFsIGZvciB0aGVcbiAgICAgIC8vIGxvb3BiYWNrIFNVUEFCQVNFX1VSTC4gUHJlc2VydmUgdGhhdCBiaW5kaW5nIGFuZCB0ZXN0IGl0cyBleGFjdFxuICAgICAgLy8gdW5jb25maWd1cmVkIHJlZnVzYWw7IGNvbmZpZ3VyZWQgd29ya2VyL0hUVFAvQUNLIHBhdGhzIGhhdmUgdGhlaXJcbiAgICAgIC8vIHNlcGFyYXRlbHkgYm91bmQgYWN0dWFsIGhhbmRsZXIgYW5kIG9ic2VydmVkIFNRTCBkZWNvZGVyIHN1aXRlLlxuICAgICAgZm9yIChjb25zdCBtZXRob2Qgb2YgW1wiT1BUSU9OU1wiLCBcIlBVVFwiXSkge1xuICAgICAgICBjb25zdCByZWZ1c2VkID0gYXdhaXQgcmVxdWVzdChzbHVnLCBgJHtzbHVnfTogc2NoZWR1bGVyIG1ldGhvZCAke21ldGhvZH1gLCB7IG1ldGhvZCB9KTtcbiAgICAgICAgY2hlY2socmVmdXNlZC5sYWJlbCwgcmVmdXNlZC5odHRwX3N0YXR1cyA9PT0gNDA1ICYmIHJlZnVzZWQuY29ycyA9PT0gbnVsbCAmJlxuICAgICAgICAgIHJlZnVzZWQubm9fc3RvcmUgJiYgcmVmdXNlZC5kZXBlbmRlbmNpZXMubGVuZ3RoID09PSAwICYmXG4gICAgICAgICAgSlNPTi5zdHJpbmdpZnkocmVmdXNlZC5yZXNwb25zZSkgPT09IEpTT04uc3RyaW5naWZ5KHsgZXJyb3I6IFwiTUVUSE9EX05PVF9BTExPV0VEXCIgfSksIHJlZnVzZWQpO1xuICAgICAgfVxuICAgICAgZm9yIChjb25zdCBbbGFiZWwsIGhlYWRlcnNdIG9mIFtcbiAgICAgICAgW1wibWlzc2luZyB3b3JrZXIgY3JlZGVudGlhbFwiLCB7fV0sXG4gICAgICAgIFtcImJlYXJlciBjYW5ub3QgY29uZmlndXJlIGxvb3BiYWNrIHdvcmtlclwiLCB7IGF1dGhvcml6YXRpb246IFwiQmVhcmVyIHFhLWludmFsaWRcIiB9XSxcbiAgICAgIF0gYXMgQXJyYXk8W3N0cmluZywgUmVjb3JkPHN0cmluZywgc3RyaW5nPl0+KSB7XG4gICAgICAgIGNvbnN0IHJlZnVzZWQgPSBhd2FpdCByZXF1ZXN0KHNsdWcsIGAke3NsdWd9OiAke2xhYmVsfWAsIHsgaGVhZGVycyB9KTtcbiAgICAgICAgY2hlY2socmVmdXNlZC5sYWJlbCwgcmVmdXNlZC5odHRwX3N0YXR1cyA9PT0gNTAzICYmIHJlZnVzZWQuY29ycyA9PT0gbnVsbCAmJlxuICAgICAgICAgIHJlZnVzZWQubm9fc3RvcmUgJiYgcmVmdXNlZC5kZXBlbmRlbmNpZXMubGVuZ3RoID09PSAwICYmXG4gICAgICAgICAgSlNPTi5zdHJpbmdpZnkocmVmdXNlZC5yZXNwb25zZSkgPT09IEpTT04uc3RyaW5naWZ5KHsgZXJyb3I6IFwiV09SS0VSX1VOQ09ORklHVVJFRFwiIH0pLCByZWZ1c2VkKTtcbiAgICAgIH1cbiAgICAgIGNvbnRpbnVlO1xuICAgIH1cbiAgICBjb25zdCBwcmVmbGlnaHQgPSBhd2FpdCByZXF1ZXN0KHNsdWcsIGAke3NsdWd9OiBwcmVmbGlnaHRgLCB7XG4gICAgICBtZXRob2Q6IFwiT1BUSU9OU1wiLFxuICAgIH0pO1xuICAgIGNoZWNrKFxuICAgICAgcHJlZmxpZ2h0LmxhYmVsLFxuICAgICAgcHJlZmxpZ2h0Lmh0dHBfc3RhdHVzID09PSAyMDAgJiYgcHJlZmxpZ2h0LmNvcnMgPT09IFwiKlwiICYmXG4gICAgICAgIHByZWZsaWdodC5kZXBlbmRlbmNpZXMubGVuZ3RoID09PSAwLFxuICAgICAgcHJlZmxpZ2h0LFxuICAgICk7XG4gICAgY29uc3QgbWV0aG9kID0gYXdhaXQgcmVxdWVzdChzbHVnLCBgJHtzbHVnfTogd3JvbmcgbWV0aG9kYCwge1xuICAgICAgbWV0aG9kOiBcIlBVVFwiLFxuICAgIH0pO1xuICAgIGNoZWNrKFxuICAgICAgbWV0aG9kLmxhYmVsLFxuICAgICAgbWV0aG9kLmh0dHBfc3RhdHVzID09PSA0MDUgJiYgbWV0aG9kLmRlcGVuZGVuY2llcy5sZW5ndGggPT09IDAsXG4gICAgICBtZXRob2QsXG4gICAgKTtcbiAgICBjb25zdCBtaXNzaW5nID0gYXdhaXQgcmVxdWVzdChzbHVnLCBgJHtzbHVnfTogbWlzc2luZyBhdXRoZW50aWNhdGlvbmApO1xuICAgIGNoZWNrKFxuICAgICAgbWlzc2luZy5sYWJlbCxcbiAgICAgIG1pc3NpbmcuaHR0cF9zdGF0dXMgPT09IDQwMSAmJiBtaXNzaW5nLmRlcGVuZGVuY2llcy5sZW5ndGggPT09IDAsXG4gICAgICBtaXNzaW5nLFxuICAgICk7XG4gICAgY29uc3QgaW52YWxpZCA9IGF3YWl0IHJlcXVlc3Qoc2x1ZywgYCR7c2x1Z306IGludmFsaWQgYXV0aGVudGljYXRpb25gLCB7XG4gICAgICAuLi4oc2x1ZyA9PT0gXCJyZWNvbmNpbGlhdGlvbi1maW5hbGl6ZVwiXG4gICAgICAgID8ge1xuICAgICAgICAgIGJvZHk6IEpTT04uc3RyaW5naWZ5KHtcbiAgICAgICAgICAgIHJldmlld19pZDogXCI5ODYwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMjFcIixcbiAgICAgICAgICB9KSxcbiAgICAgICAgfVxuICAgICAgICA6IHt9KSxcbiAgICAgIGhlYWRlcnM6IHtcbiAgICAgICAgYXV0aG9yaXphdGlvbjogXCJCZWFyZXIgcWEtaW52YWxpZFwiLFxuICAgICAgICBcIngtY29sbGVjdC1zaWduYXR1cmVcIjogXCJxYS1pbnZhbGlkXCIsXG4gICAgICAgIFwieC1ob29rLXNlY3JldFwiOiBcInFhLWludmFsaWRcIixcbiAgICAgIH0sXG4gICAgfSk7XG4gICAgY2hlY2soXG4gICAgICBpbnZhbGlkLmxhYmVsLFxuICAgICAgaW52YWxpZC5odHRwX3N0YXR1cyA9PT0gNDAxICYmXG4gICAgICAgIGludmFsaWQuZGVwZW5kZW5jaWVzLmV2ZXJ5KChyKSA9PlxuICAgICAgICAgIHIucGF0aCA9PT0gXCIvYXV0aC92MS91c2VyXCIgfHxcbiAgICAgICAgICAoc2x1ZyA9PT0gXCJyZWNvbmNpbGlhdGlvbi1maW5hbGl6ZVwiICYmXG4gICAgICAgICAgICByLnBhdGggPT09IFwiL3Jlc3QvdjEvcnBjL2F1dGhvcml6ZV9yZWNvbmNpbGlhdGlvbl9maW5hbGl6YXRpb25fdjJcIilcbiAgICAgICAgKSxcbiAgICAgIGludmFsaWQsXG4gICAgKTtcbiAgfVxuICBmb3IgKFxuICAgIGNvbnN0IHNsdWcgb2YgW1wiY29sbGVjdC1ub3RpZmljYXRpb24tb3BlcmF0b3JcIiwgXCJwcmVwYXJlLXJvc3Rlci1pbXBvcnRcIl1cbiAgKSB7XG4gICAgbW9kZSA9IFwiZGVuaWVkXCI7XG4gICAgY29uc3QgZGVuaWVkID0gYXdhaXQgcmVxdWVzdChzbHVnLCBgJHtzbHVnfTogbWVtYmVyIGNhbm5vdCBvcGVyYXRlYCwge1xuICAgICAgaGVhZGVyczogeyBhdXRob3JpemF0aW9uOiB1c2VyQXV0aG9yaXphdGlvbiB9LFxuICAgICAgYm9keTogSlNPTi5zdHJpbmdpZnkoXG4gICAgICAgIHNsdWcgPT09IFwicHJlcGFyZS1yb3N0ZXItaW1wb3J0XCIgPyByb3N0ZXJJbnB1dCgpIDogeyBhY3Rpb246IFwiaGVhbHRoXCIgfSxcbiAgICAgICksXG4gICAgfSk7XG4gICAgY2hlY2soXG4gICAgICBkZW5pZWQubGFiZWwsXG4gICAgICBkZW5pZWQuaHR0cF9zdGF0dXMgPT09IDQwMyAmJlxuICAgICAgICBkZW5pZWQuZGVwZW5kZW5jaWVzLmV2ZXJ5KChyKSA9PlxuICAgICAgICAgIFtcbiAgICAgICAgICAgIFwiL2F1dGgvdjEvdXNlclwiLFxuICAgICAgICAgICAgXCIvcmVzdC92MS9ycGMvYWRtaW5fY3VycmVudF91c2VyXCIsXG4gICAgICAgICAgICBcIi9yZXN0L3YxL3JwYy9yZXNlcnZlX3Jvc3Rlcl9yZXNvdXJjZXNcIixcbiAgICAgICAgICBdLmluY2x1ZGVzKFxuICAgICAgICAgICAgU3RyaW5nKHIucGF0aCksXG4gICAgICAgICAgKVxuICAgICAgICApLFxuICAgICAgZGVuaWVkLFxuICAgICk7XG4gICAgbW9kZSA9IFwibm9ybWFsXCI7XG4gIH1cbiAgY29uc3QgaGVhbHRoID0gYXdhaXQgcmVxdWVzdChcbiAgICBcImNvbGxlY3Qtbm90aWZpY2F0aW9uLW9wZXJhdG9yXCIsXG4gICAgXCJvcGVyYXRvcjogcGVybWlzc2lvbi1iZWFyaW5nIGlkZW50aXR5IHJlYWNoZXMgaGVhbHRoXCIsXG4gICAge1xuICAgICAgaGVhZGVyczogeyBhdXRob3JpemF0aW9uOiB1c2VyQXV0aG9yaXphdGlvbiB9LFxuICAgICAgYm9keTogSlNPTi5zdHJpbmdpZnkoeyBhY3Rpb246IFwiaGVhbHRoXCIsIG9wZXJhdG9yX3VzZXJfaWQ6IFwiZm9yZ2VkXCIgfSksXG4gICAgfSxcbiAgKTtcbiAgY2hlY2soXG4gICAgaGVhbHRoLmxhYmVsLFxuICAgIGhlYWx0aC5odHRwX3N0YXR1cyA9PT0gMjAwICYmIGhlYWx0aC5ub19zdG9yZSAmJlxuICAgICAgaGVhbHRoLmRlcGVuZGVuY2llcy5zb21lKChyKSA9PlxuICAgICAgICByLnBhdGggPT09IFwiL3Jlc3QvdjEvcnBjL2NvbGxlY3Rfbm90aWZpY2F0aW9uX2hlYWx0aF92MlwiICYmXG4gICAgICAgIChyLnBheWxvYWQgYXMgUmVjb3JkPHN0cmluZywgdW5rbm93bj4pPy5wX29wZXJhdG9yX3VzZXJfaWQgPT09IHVzZXJJZCAmJlxuICAgICAgICAoci5wYXlsb2FkIGFzIFJlY29yZDxzdHJpbmcsIHVua25vd24+KT8ucF9vcGVyYXRvcl9zZXNzaW9uX2lkID09PSBzZXNzaW9uSWRcbiAgICAgICksXG4gICAgaGVhbHRoLFxuICApO1xuICBjb25zdCBkaXNwYXRjaCA9IGF3YWl0IHJlcXVlc3QoXG4gICAgXCJkaXNwYXRjaC1ub3RpZmljYXRpb25zXCIsXG4gICAgXCJkaXNwYXRjaGVyOiB2YWxpZCBpbnRlcm5hbCBlbXB0eSBxdWV1ZVwiLFxuICAgIHsgaGVhZGVyczogeyBcIngtY29sbGVjdC1zaWduYXR1cmVcIjogaW50ZXJuYWxTZWNyZXQgfSB9LFxuICApO1xuICBjaGVjayhcbiAgICBkaXNwYXRjaC5sYWJlbCxcbiAgICBkaXNwYXRjaC5odHRwX3N0YXR1cyA9PT0gMjAwICYmXG4gICAgICAoZGlzcGF0Y2gucmVzcG9uc2UgYXMgUmVjb3JkPHN0cmluZywgdW5rbm93bj4pPy5jbGFpbWVkID09PSAwLFxuICAgIGRpc3BhdGNoLFxuICApO1xuICBjb25zdCBwYXJzZWQgPSBhd2FpdCByZXF1ZXN0KFxuICAgIFwicGFyc2UtcGF5bWVudC1zbXNcIixcbiAgICBcInBhcnNlcjogdmFsaWQgaW50ZXJuYWwgcmVxdWVzdCByZXF1aXJlcyByZWFsIFVVSURcIixcbiAgICB7IGhlYWRlcnM6IHsgXCJ4LWNvbGxlY3Qtc2lnbmF0dXJlXCI6IGludGVybmFsU2VjcmV0IH0gfSxcbiAgKTtcbiAgY2hlY2soXG4gICAgcGFyc2VkLmxhYmVsLFxuICAgIHBhcnNlZC5odHRwX3N0YXR1cyA9PT0gNDAwICYmIHBhcnNlZC5kZXBlbmRlbmNpZXMubGVuZ3RoID09PSAwLFxuICAgIHBhcnNlZCxcbiAgKTtcbiAgY29uc3Qgbm9FbnZlbG9wZSA9IGF3YWl0IHJlcXVlc3QoXG4gICAgXCJpbmdlc3QtcGF5bWVudC1zbXNcIixcbiAgICBcIlNNUzogY3VycmVudCBjb250cmFjdCByZWZ1c2VzIHVuYXR0ZXN0ZWQgZW52ZWxvcGVcIixcbiAgICB7XG4gICAgICBoZWFkZXJzOiB7IGF1dGhvcml6YXRpb246IHVzZXJBdXRob3JpemF0aW9uIH0sXG4gICAgICBib2R5OiBKU09OLnN0cmluZ2lmeSh7XG4gICAgICAgIHJhd19zZW5kZXI6IFwiTS1Nb25leVwiLFxuICAgICAgICByYXdfYm9keTogXCJTeW50aGV0aWMgcmF3IG1lc3NhZ2VcIixcbiAgICAgICAgcmVjZWl2ZXJfbW9tb19udW1iZXI6IFwiMDc4ODk5MTAwMVwiLFxuICAgICAgfSksXG4gICAgfSxcbiAgKTtcbiAgY2hlY2soXG4gICAgbm9FbnZlbG9wZS5sYWJlbCxcbiAgICBub0VudmVsb3BlLmh0dHBfc3RhdHVzID09PSA0MDAgJiZcbiAgICAgIG5vRW52ZWxvcGUuZGVwZW5kZW5jaWVzLmV2ZXJ5KChyKSA9PlxuICAgICAgICBbXG4gICAgICAgICAgXCIvYXV0aC92MS91c2VyXCIsXG4gICAgICAgICAgXCIvcmVzdC92MS9ycGMvYXR0ZXN0ZWRfc21zX2NvbnRyYWN0X3ZlcnNpb25cIixcbiAgICAgICAgICBcIi9yZXN0L3YxL3JwYy9yZWNvcmRfb3BlcmF0aW9uYWxfbWV0cmljX3YxXCIsXG4gICAgICAgIF1cbiAgICAgICAgICAuaW5jbHVkZXMoXG4gICAgICAgICAgICBTdHJpbmcoci5wYXRoKSxcbiAgICAgICAgICApXG4gICAgICApLFxuICAgIG5vRW52ZWxvcGUsXG4gICk7XG4gIGZvciAoXG4gICAgY29uc3Qgc2NlbmFyaW8gb2YgW1xuICAgICAgXCJyZWNlaXB0X3N1Y2Nlc3NcIixcbiAgICAgIFwicmVjZWlwdF9tZXRyaWNfZXJyb3JcIixcbiAgICAgIFwicmVjZWlwdF9tZXRyaWNfdGltZW91dFwiLFxuICAgICAgXCJyZWNlaXB0X2RlZmVycmVkXCIsXG4gICAgICBcInJlY2VpcHRfYmFkX2Fja1wiLFxuICAgIF1cbiAgKSB7XG4gICAgbW9kZSA9IHNjZW5hcmlvO1xuICAgIGNvbnN0IHN0YXJ0ZWQgPSBwZXJmb3JtYW5jZS5ub3coKTtcbiAgICBjb25zdCBlbnZlbG9wZSA9IGNyeXB0by5yYW5kb21VVUlEKCk7XG4gICAgY29uc3QgcmVzdWx0ID0gYXdhaXQgcmVxdWVzdChcbiAgICAgIFwiaW5nZXN0LXBheW1lbnQtc21zXCIsXG4gICAgICBgU01TIHRlbGVtZXRyeTogJHtzY2VuYXJpb31gLFxuICAgICAge1xuICAgICAgICBoZWFkZXJzOiB7IGF1dGhvcml6YXRpb246IHVzZXJBdXRob3JpemF0aW9uIH0sXG4gICAgICAgIGJvZHk6IEpTT04uc3RyaW5naWZ5KHtcbiAgICAgICAgICByYXdfc2VuZGVyOiBcIlN5bnRoZXRpYyBzZW5kZXIgY2FuYXJ5XCIsXG4gICAgICAgICAgcmF3X2JvZHk6IFwiU3ludGhldGljIHByaXZhdGUgcmVjZWlwdCBjYW5hcnlcIixcbiAgICAgICAgICByZWNlaXZlcl9tb21vX251bWJlcjogXCIwNzg4OTkxMDAxXCIsXG4gICAgICAgICAgY2xpZW50X2VudmVsb3BlX2lkOiBlbnZlbG9wZSxcbiAgICAgICAgICBuYXRpdmVfY2FwYWJpbGl0eTogY3J5cHRvLnJhbmRvbVVVSUQoKSxcbiAgICAgICAgfSksXG4gICAgICB9LFxuICAgICk7XG4gICAgY29uc3QgZWxhcHNlZCA9IHBlcmZvcm1hbmNlLm5vdygpIC0gc3RhcnRlZDtcbiAgICBjb25zdCBzYW1wbGVzID0gcmVzdWx0LmRlcGVuZGVuY2llcy5maWx0ZXIoKHIpID0+XG4gICAgICByLnBhdGggPT09IFwiL3Jlc3QvdjEvcnBjL3JlY29yZF9vcGVyYXRpb25hbF9tZXRyaWNfdjFcIlxuICAgICk7XG4gICAgY29uc3QgY29kZXMgPSBzYW1wbGVzLm1hcCgocikgPT5cbiAgICAgIChyLnBheWxvYWQgYXMgUmVjb3JkPHN0cmluZywgdW5rbm93bj4pLnBfZXZlbnRfY29kZVxuICAgICk7XG4gICAgY29uc3QgY29kZVNoYXBlID0gc2FtcGxlcy5ldmVyeSgocikgPT5cbiAgICAgIHIuaWRlbnRpdHkgPT09IFwic3ludGhldGljX3NlcnZpY2VcIiAmJlxuICAgICAgT2JqZWN0LmtleXMoci5wYXlsb2FkIGFzIFJlY29yZDxzdHJpbmcsIHVua25vd24+KS5zb3J0KCkuam9pbigpID09PVxuICAgICAgICBcInBfZHVyYXRpb25fbXMscF9ldmVudF9jb2RlXCIgJiZcbiAgICAgICFKU09OLnN0cmluZ2lmeShyLnBheWxvYWQpLmluY2x1ZGVzKFwiY2FuYXJ5XCIpICYmXG4gICAgICAhSlNPTi5zdHJpbmdpZnkoci5wYXlsb2FkKS5pbmNsdWRlcyhlbnZlbG9wZSlcbiAgICApO1xuICAgIGNvbnN0IHJlc3BvbnNlID0gcmVzdWx0LnJlc3BvbnNlIGFzIFJlY29yZDxzdHJpbmcsIHVua25vd24+O1xuICAgIGNvbnN0IHN1Y2Nlc3MgPSBzY2VuYXJpbyAhPT0gXCJyZWNlaXB0X2RlZmVycmVkXCIgJiZcbiAgICAgIHNjZW5hcmlvICE9PSBcInJlY2VpcHRfYmFkX2Fja1wiO1xuICAgIGNvbnN0IGV4cGVjdGVkQ29kZXMgPSBzdWNjZXNzXG4gICAgICA/IFtcInJlY2VpcHRfcHJvY2Vzc2luZ19hY2NlcHRlZFwiLCBcInJlY2VpcHRfYWNrX2dlbmVyYXRlZFwiXVxuICAgICAgOiBzY2VuYXJpbyA9PT0gXCJyZWNlaXB0X2RlZmVycmVkXCJcbiAgICAgID8gW1wicmVjZWlwdF9wcm9jZXNzaW5nX2RlZmVycmVkXCJdXG4gICAgICA6IFtcInJlY2VpcHRfcmVqZWN0ZWRcIl07XG4gICAgY29uc3QgYWNrID0gcmVzcG9uc2UucmVjZWlwdCBhcyBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPiB8IHVuZGVmaW5lZDtcbiAgICBjaGVjayhcbiAgICAgIHJlc3VsdC5sYWJlbCxcbiAgICAgIHJlc3VsdC5odHRwX3N0YXR1cyA9PT0gKHN1Y2Nlc3MgPyAyMDAgOiA1MDMpICYmIGNvZGVTaGFwZSAmJlxuICAgICAgICBKU09OLnN0cmluZ2lmeShjb2RlcykgPT09IEpTT04uc3RyaW5naWZ5KGV4cGVjdGVkQ29kZXMpICYmXG4gICAgICAgIChzdWNjZXNzXG4gICAgICAgICAgPyByZXNwb25zZS5vayA9PT0gdHJ1ZSAmJiBhY2s/LnN0b3JlZCA9PT0gdHJ1ZSAmJlxuICAgICAgICAgICAgYWNrPy5jbGllbnRfZW52ZWxvcGVfaWQgPT09IGVudmVsb3BlICYmXG4gICAgICAgICAgICBhY2s/Lm93bmVyX3VzZXJfaWQgPT09IHVzZXJJZFxuICAgICAgICAgIDogcmVzcG9uc2UuZXJyb3IgPT09XG4gICAgICAgICAgICAoc2NlbmFyaW8gPT09IFwicmVjZWlwdF9kZWZlcnJlZFwiXG4gICAgICAgICAgICAgID8gXCJyZWNlaXB0X3N0b3JlZF9wcm9jZXNzaW5nX3JldHJ5XCJcbiAgICAgICAgICAgICAgOiBcImR1cmFibGVfcmVjZWlwdF9ub3RfdmVyaWZpZWRcIikpICYmXG4gICAgICAgIChzY2VuYXJpbyAhPT0gXCJyZWNlaXB0X21ldHJpY190aW1lb3V0XCIgfHwgZWxhcHNlZCA8IDE1MDApICYmXG4gICAgICAgICFKU09OLnN0cmluZ2lmeShyZXNwb25zZSkuaW5jbHVkZXMoXCJzZWNyZXQtcHJvdmlkZXJcIiksXG4gICAgICB7IC4uLnJlc3VsdCwgZWxhcHNlZF9tczogZWxhcHNlZCB9LFxuICAgICk7XG4gIH1cbiAgbW9kZSA9IFwibm9ybWFsXCI7XG4gIGNvbnN0IGRldGVybWluaXN0aWNJbnB1dCA9IHJvc3RlcklucHV0KCk7XG4gIGNvbnN0IHJvc3RlciA9IGF3YWl0IHJlcXVlc3QoXG4gICAgXCJwcmVwYXJlLXJvc3Rlci1pbXBvcnRcIixcbiAgICBcInJvc3RlcjogYXBwcm92ZWQgZGV0ZXJtaW5pc3RpYyBwcmV2aWV3XCIsXG4gICAge1xuICAgICAgaGVhZGVyczogeyBhdXRob3JpemF0aW9uOiB1c2VyQXV0aG9yaXphdGlvbiB9LFxuICAgICAgYm9keTogSlNPTi5zdHJpbmdpZnkoZGV0ZXJtaW5pc3RpY0lucHV0KSxcbiAgICB9LFxuICApO1xuICBjaGVjayhcbiAgICByb3N0ZXIubGFiZWwsXG4gICAgcm9zdGVyLmh0dHBfc3RhdHVzID09PSAyMDAgJiZcbiAgICAgIChyb3N0ZXIucmVzcG9uc2UgYXMgUmVjb3JkPHN0cmluZywgdW5rbm93bj4pPy5wcm9jZXNzaW5nX21ldGhvZCA9PT1cbiAgICAgICAgXCJkZXRlcm1pbmlzdGljXCIsXG4gICAgcm9zdGVyLFxuICApO1xuXG4gIGNoZWNrKFxuICAgIFwicm9zdGVyOiByZXNvdXJjZSByZXNlcnZhdGlvbiBhbmQgaW1tdXRhYmxlIHByZXZpZXcgZmluaXNoIGluIG9yZGVyXCIsXG4gICAgSlNPTi5zdHJpbmdpZnkocm9zdGVyLmRlcGVuZGVuY2llcy5tYXAoKHIpID0+IHIucGF0aCkpID09PVxuICAgICAgICBKU09OLnN0cmluZ2lmeShbXG4gICAgICAgICAgXCIvYXV0aC92MS91c2VyXCIsXG4gICAgICAgICAgXCIvcmVzdC92MS9ycGMvcmVzZXJ2ZV9yb3N0ZXJfcmVzb3VyY2VzXCIsXG4gICAgICAgICAgXCIvcmVzdC92MS9ycGMvY3JlYXRlX3Jvc3Rlcl9pbXBvcnRfc291cmNlXCIsXG4gICAgICAgICAgXCIvcmVzdC92MS9ycGMvY29tcGxldGVfcm9zdGVyX2ltcG9ydF9wcmV2aWV3XCIsXG4gICAgICAgICAgXCIvcmVzdC92MS9ycGMvZmluaXNoX3Jvc3Rlcl9yZXNvdXJjZXNcIixcbiAgICAgICAgXSkgJiZcbiAgICAgIChyb3N0ZXIucmVzcG9uc2UgYXMgUmVjb3JkPHN0cmluZywgdW5rbm93bj4pPy5yZXF1aXJlc19odW1hbl9yZXZpZXcgPT09XG4gICAgICAgIHRydWUgJiZcbiAgICAgIChyb3N0ZXIucmVzcG9uc2UgYXMgUmVjb3JkPHN0cmluZywgdW5rbm93bj4pPy5jYW5fc3VibWl0ID09PSBmYWxzZSxcbiAgICByb3N0ZXIsXG4gICk7XG4gIGNvbnN0IHJlcGxheSA9IGF3YWl0IHJlcXVlc3QoXG4gICAgXCJwcmVwYXJlLXJvc3Rlci1pbXBvcnRcIixcbiAgICBcInJvc3RlcjogZmluaXNoZWQgcHJldmlldyByZXBsYXkgcGVyZm9ybXMgbm8gZGVjb2Rlci9wcm92aWRlciB3b3JrXCIsXG4gICAge1xuICAgICAgaGVhZGVyczogeyBhdXRob3JpemF0aW9uOiB1c2VyQXV0aG9yaXphdGlvbiB9LFxuICAgICAgYm9keTogSlNPTi5zdHJpbmdpZnkoZGV0ZXJtaW5pc3RpY0lucHV0KSxcbiAgICB9LFxuICApO1xuICBjaGVjayhcbiAgICByZXBsYXkubGFiZWwsXG4gICAgcmVwbGF5Lmh0dHBfc3RhdHVzID09PSAyMDAgJiZcbiAgICAgIEpTT04uc3RyaW5naWZ5KHJlcGxheS5yZXNwb25zZSkgPT09IEpTT04uc3RyaW5naWZ5KHJvc3Rlci5yZXNwb25zZSkgJiZcbiAgICAgIEpTT04uc3RyaW5naWZ5KHJlcGxheS5kZXBlbmRlbmNpZXMubWFwKChyKSA9PiByLnBhdGgpKSA9PT1cbiAgICAgICAgSlNPTi5zdHJpbmdpZnkoW1xuICAgICAgICAgIFwiL2F1dGgvdjEvdXNlclwiLFxuICAgICAgICAgIFwiL3Jlc3QvdjEvcnBjL3Jlc2VydmVfcm9zdGVyX3Jlc291cmNlc1wiLFxuICAgICAgICAgIFwiL3Jlc3QvdjEvcnBjL2NyZWF0ZV9yb3N0ZXJfaW1wb3J0X3NvdXJjZVwiLFxuICAgICAgICBdKSxcbiAgICByZXBsYXksXG4gICk7XG4gIGZvciAoXG4gICAgY29uc3QgW3NjZW5hcmlvLCBzdGF0dXMsIGNvZGUsIGV4cGVjdGVkXSBvZiBbXG4gICAgICBbXCJyb3N0ZXJfcXVvdGFcIiwgNDI5LCBcInJvc3Rlcl9yZXNvdXJjZV9saW1pdFwiLCBbXG4gICAgICAgIFwiL2F1dGgvdjEvdXNlclwiLFxuICAgICAgICBcIi9yZXN0L3YxL3JwYy9yZXNlcnZlX3Jvc3Rlcl9yZXNvdXJjZXNcIixcbiAgICAgIF1dLFxuICAgICAgW1wicm9zdGVyX2JhZF9idWRnZXRcIiwgNTAzLCBcInJvc3Rlcl9idWRnZXRfcmVjZWlwdF9pbnZhbGlkXCIsIFtcbiAgICAgICAgXCIvYXV0aC92MS91c2VyXCIsXG4gICAgICAgIFwiL3Jlc3QvdjEvcnBjL3Jlc2VydmVfcm9zdGVyX3Jlc291cmNlc1wiLFxuICAgICAgXV0sXG4gICAgICBbXCJyb3N0ZXJfYmFkX25vbmNlXCIsIDUwMywgXCJyb3N0ZXJfZGVjb2Rlcl9yZWNlaXB0X2ludmFsaWRcIiwgW1xuICAgICAgICBcIi9hdXRoL3YxL3VzZXJcIixcbiAgICAgICAgXCIvcmVzdC92MS9ycGMvcmVzZXJ2ZV9yb3N0ZXJfcmVzb3VyY2VzXCIsXG4gICAgICAgIFwiL2RlY29kZVwiLFxuICAgICAgICBcIi9yZXN0L3YxL3JwYy9maW5pc2hfcm9zdGVyX3Jlc291cmNlc1wiLFxuICAgICAgXV0sXG4gICAgICBbXCJyb3N0ZXJfYmFkX3NpZ25hdHVyZVwiLCA1MDMsIFwicm9zdGVyX2RlY29kZXJfcmVjZWlwdF9pbnZhbGlkXCIsIFtcbiAgICAgICAgXCIvYXV0aC92MS91c2VyXCIsXG4gICAgICAgIFwiL3Jlc3QvdjEvcnBjL3Jlc2VydmVfcm9zdGVyX3Jlc291cmNlc1wiLFxuICAgICAgICBcIi9kZWNvZGVcIixcbiAgICAgICAgXCIvcmVzdC92MS9ycGMvZmluaXNoX3Jvc3Rlcl9yZXNvdXJjZXNcIixcbiAgICAgIF1dLFxuICAgICAgW1wicm9zdGVyX2RlY29kZXJfcmVqZWN0XCIsIDQyMiwgXCJyb3N0ZXJfYW5pbWF0aW9uX2xpbWl0XCIsIFtcbiAgICAgICAgXCIvYXV0aC92MS91c2VyXCIsXG4gICAgICAgIFwiL3Jlc3QvdjEvcnBjL3Jlc2VydmVfcm9zdGVyX3Jlc291cmNlc1wiLFxuICAgICAgICBcIi9kZWNvZGVcIixcbiAgICAgICAgXCIvcmVzdC92MS9ycGMvZmluaXNoX3Jvc3Rlcl9yZXNvdXJjZXNcIixcbiAgICAgIF1dLFxuICAgICAgW1wicm9zdGVyX2JhZF92ZXJpZmljYXRpb25cIiwgNTAzLCBcInJvc3Rlcl9yZWNlaXB0X2ludmFsaWRcIiwgW1xuICAgICAgICBcIi9hdXRoL3YxL3VzZXJcIixcbiAgICAgICAgXCIvcmVzdC92MS9ycGMvcmVzZXJ2ZV9yb3N0ZXJfcmVzb3VyY2VzXCIsXG4gICAgICAgIFwiL2RlY29kZVwiLFxuICAgICAgICBcIi9yZXN0L3YxL3JwYy92ZXJpZnlfcm9zdGVyX3NvdXJjZV9pbnRlZ3JpdHlcIixcbiAgICAgICAgXCIvcmVzdC92MS9ycGMvZmluaXNoX3Jvc3Rlcl9yZXNvdXJjZXNcIixcbiAgICAgIF1dLFxuICAgICAgW1wibm9ybWFsXCIsIDUwMywgXCJyb3N0ZXJfZXh0cmFjdGlvbl91bmF2YWlsYWJsZVwiLCBbXG4gICAgICAgIFwiL2F1dGgvdjEvdXNlclwiLFxuICAgICAgICBcIi9yZXN0L3YxL3JwYy9yZXNlcnZlX3Jvc3Rlcl9yZXNvdXJjZXNcIixcbiAgICAgICAgXCIvZGVjb2RlXCIsXG4gICAgICAgIFwiL3Jlc3QvdjEvcnBjL3ZlcmlmeV9yb3N0ZXJfc291cmNlX2ludGVncml0eVwiLFxuICAgICAgICBcIi9yZXN0L3YxL3JwYy9jcmVhdGVfcm9zdGVyX2ltcG9ydF9zb3VyY2VcIixcbiAgICAgICAgXCIvcmVzdC92MS9ycGMvZmFpbF9yb3N0ZXJfaW1wb3J0X3ByZXZpZXdcIixcbiAgICAgICAgXCIvcmVzdC92MS9ycGMvZmluaXNoX3Jvc3Rlcl9yZXNvdXJjZXNcIixcbiAgICAgIF1dLFxuICAgIF0gYXMgY29uc3RcbiAgKSB7XG4gICAgbW9kZSA9IHNjZW5hcmlvO1xuICAgIGNvbnN0IGJlZm9yZSA9IHByb3ZpZGVyQXR0ZW1wdHMubGVuZ3RoO1xuICAgIGNvbnN0IHJlc3VsdCA9IGF3YWl0IHJlcXVlc3QoXG4gICAgICBcInByZXBhcmUtcm9zdGVyLWltcG9ydFwiLFxuICAgICAgYHJvc3RlcjogJHtzY2VuYXJpb30gZW5mb3JjZXMgdmVyaWZpY2F0aW9uIGJlZm9yZSB0cmFuc21pc3Npb25gLFxuICAgICAge1xuICAgICAgICBoZWFkZXJzOiB7IGF1dGhvcml6YXRpb246IHVzZXJBdXRob3JpemF0aW9uIH0sXG4gICAgICAgIGJvZHk6IEpTT04uc3RyaW5naWZ5KHJvc3RlckltYWdlKCkpLFxuICAgICAgfSxcbiAgICApO1xuICAgIGNoZWNrKFxuICAgICAgcmVzdWx0LmxhYmVsLFxuICAgICAgcmVzdWx0Lmh0dHBfc3RhdHVzID09PSBzdGF0dXMgJiZcbiAgICAgICAgKHJlc3VsdC5yZXNwb25zZSBhcyBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPik/LmVycm9yID09PSBjb2RlICYmXG4gICAgICAgIEpTT04uc3RyaW5naWZ5KHJlc3VsdC5kZXBlbmRlbmNpZXMubWFwKChyKSA9PiByLnBhdGgpKSA9PT1cbiAgICAgICAgICBKU09OLnN0cmluZ2lmeShleHBlY3RlZCkgJiZcbiAgICAgICAgcHJvdmlkZXJBdHRlbXB0cy5sZW5ndGggPT09IGJlZm9yZSxcbiAgICAgIHJlc3VsdCxcbiAgICApO1xuICB9XG4gIG1vZGUgPSBcIm5vcm1hbFwiO1xuXG4gIC8vIFRoZSBwcm9kdWN0IG93bmVyIHJldGlyZWQgdGhlIHRocmVlIGJhbmstaW5nZXN0aW9uIHJvdXRlcy5cbiAgLy8gUHJlc2VydmUgdGhlIGJvdW5kYXJ5IGNoZWNrIGFzIGFic2VuY2Ugb2Ygc291cmNlL2NvbmZpZy9saXN0ZW5lciwgc2luY2VcbiAgLy8gaW52b2tpbmcgZGVsZXRlZCBjb2RlIHdvdWxkIGZhbHNlbHkgaW5mbGF0ZSBhY3RpdmUgc3VyZmFjZSBhY2NlcHRhbmNlLlxuICBmb3IgKFxuICAgIGNvbnN0IHJldGlyZWQgb2YgW1xuICAgICAgXCJpbmdlc3QtYmFuay1lbWFpbFwiLFxuICAgICAgXCJpbmdlc3QtYmFuay1zbXNcIixcbiAgICAgIFwiaW5nZXN0LWJhbmstc3RhdGVtZW50XCIsXG4gICAgXVxuICApIHtcbiAgICBsZXQgc291cmNlQWJzZW50ID0gZmFsc2U7XG4gICAgdHJ5IHtcbiAgICAgIGF3YWl0IERlbm8uc3RhdChcbiAgICAgICAgbmV3IFVSTChcbiAgICAgICAgICBgLi4vLi4vc3VwYWJhc2UvZnVuY3Rpb25zLyR7cmV0aXJlZH0vaW5kZXgudHNgLFxuICAgICAgICAgIGltcG9ydC5tZXRhLnVybCxcbiAgICAgICAgKSxcbiAgICAgICk7XG4gICAgfSBjYXRjaCAoZXJyb3IpIHtcbiAgICAgIGlmIChlcnJvciBpbnN0YW5jZW9mIERlbm8uZXJyb3JzLk5vdEZvdW5kKSBzb3VyY2VBYnNlbnQgPSB0cnVlO1xuICAgICAgZWxzZSB0aHJvdyBlcnJvcjtcbiAgICB9XG4gICAgY2hlY2soXG4gICAgICBgcmV0aXJlZCAke3JldGlyZWR9OiBzb3VyY2UvY29uZmlnL2xpc3RlbmVyIGFic2VudGAsXG4gICAgICBzb3VyY2VBYnNlbnQgJiYgIW5hbWVzLmluY2x1ZGVzKHJldGlyZWQpICYmICEocmV0aXJlZCBpbiBlbnRyeXBvaW50cyksXG4gICAgKTtcbiAgfVxuXG4gIGNvbnN0IG90cEJvZHkgPSBKU09OLnN0cmluZ2lmeSh7XG4gICAgdXNlcjogeyBwaG9uZTogXCIrMjUwNzg4OTkxMDAxXCIgfSxcbiAgICBzbXM6IHsgb3RwOiBcIjk4NzY1NFwiIH0sXG4gIH0pO1xuICBjb25zdCB3ZWJob29rID0gbmV3IFdlYmhvb2soaG9va1NlY3JldCk7XG4gIGZ1bmN0aW9uIHNpZ25lZE90cChpZDogc3RyaW5nLCBvZmZzZXQgPSAwLCBtdXRhdGUgPSBmYWxzZSkge1xuICAgIGNvbnN0IHdoZW4gPSBuZXcgRGF0ZShEYXRlLm5vdygpICsgb2Zmc2V0ICogMTAwMCk7XG4gICAgcmV0dXJuIHtcbiAgICAgIGJvZHk6IG11dGF0ZSA/IG90cEJvZHkgKyBcIiBcIiA6IG90cEJvZHksXG4gICAgICBoZWFkZXJzOiB7XG4gICAgICAgIFwid2ViaG9vay1pZFwiOiBpZCxcbiAgICAgICAgXCJ3ZWJob29rLXRpbWVzdGFtcFwiOiBTdHJpbmcoTWF0aC5mbG9vcih3aGVuLmdldFRpbWUoKSAvIDEwMDApKSxcbiAgICAgICAgXCJ3ZWJob29rLXNpZ25hdHVyZVwiOiB3ZWJob29rLnNpZ24oaWQsIHdoZW4sIG90cEJvZHkpLFxuICAgICAgfSxcbiAgICB9O1xuICB9XG4gIGZvciAoXG4gICAgY29uc3QgW2xhYmVsLCBvZmZzZXQsIG11dGF0ZV0gb2YgW1tcInZhbGlkXCIsIDAsIGZhbHNlXSwgW1xuICAgICAgXCJleHBpcmVkXCIsXG4gICAgICAtNjAxLFxuICAgICAgZmFsc2UsXG4gICAgXSwgW1wibW9kaWZpZWQtYm9keVwiLCAwLCB0cnVlXV0gYXMgY29uc3RcbiAgKSB7XG4gICAgY291bnRlciA9IDA7XG4gICAgbW9kZSA9IFwiYWxyZWFkeV9hY2NlcHRlZFwiO1xuICAgIGNvbnN0IGJlZm9yZSA9IHByb3ZpZGVyQXR0ZW1wdHMubGVuZ3RoO1xuICAgIGNvbnN0IHJlc3VsdCA9IGF3YWl0IHJlcXVlc3QoXG4gICAgICBcImF1dGgtc2VuZC13aGF0c2FwcC1vdHBcIixcbiAgICAgIGBPVFAgc2lnbmVkIGhvb2s6ICR7bGFiZWx9YCxcbiAgICAgIHNpZ25lZE90cChcInFhLWhvb2stXCIgKyBsYWJlbCArIFwiLVwiICsgY3J5cHRvLnJhbmRvbVVVSUQoKSwgb2Zmc2V0LCBtdXRhdGUpLFxuICAgICk7XG4gICAgY2hlY2soXG4gICAgICByZXN1bHQubGFiZWwsXG4gICAgICByZXN1bHQuaHR0cF9zdGF0dXMgPT09IChsYWJlbCA9PT0gXCJ2YWxpZFwiID8gMjAwIDogNDAxKSAmJlxuICAgICAgICBwcm92aWRlckF0dGVtcHRzLmxlbmd0aCA9PT0gYmVmb3JlICYmIChsYWJlbCA9PT0gXCJ2YWxpZFwiXG4gICAgICAgICAgPyByZXN1bHQuZGVwZW5kZW5jaWVzLm1hcCgocikgPT5cbiAgICAgICAgICAgIHIucGF0aFxuICAgICAgICAgICkuam9pbigpID09PVxuICAgICAgICAgICAgXCIvcmVzdC92MS9ycGMvcmVzZXJ2ZV9zaWduZWRfb3RwX3YzXCJcbiAgICAgICAgICA6IHJlc3VsdC5kZXBlbmRlbmNpZXMubGVuZ3RoID09PSAwKSxcbiAgICAgIHtcbiAgICAgICAgLi4ucmVzdWx0LFxuICAgICAgICBtb2RlbDpcbiAgICAgICAgICBcInZhbGlkIGNhc2UgcmV0dXJucyBhIHJlY29yZGVkIGFjY2VwdGVkIGF0dGVtcHQ7IG5vIHByb3ZpZGVyIGRpc3BhdGNoXCIsXG4gICAgICB9LFxuICAgICk7XG4gIH1cbiAgbW9kZSA9IFwibm9ybWFsXCI7XG4gIGNvbnN0IGxlZ2FjeSA9IGF3YWl0IHJlcXVlc3QoXG4gICAgXCJhdXRoLXNlbmQtd2hhdHNhcHAtb3RwXCIsXG4gICAgXCJPVFAgbGVnYWN5IHN0YXRpYyBzZWNyZXQgY2Fubm90IHJlc2VydmUgb3Igc2VuZFwiLFxuICAgIHsgaGVhZGVyczogeyBcIngtaG9vay1zZWNyZXRcIjogaG9va1NlY3JldCB9LCBib2R5OiBvdHBCb2R5IH0sXG4gICk7XG4gIGNoZWNrKFxuICAgIGxlZ2FjeS5sYWJlbCxcbiAgICBsZWdhY3kuaHR0cF9zdGF0dXMgPT09IDQwMSAmJiBsZWdhY3kuZGVwZW5kZW5jaWVzLmxlbmd0aCA9PT0gMCxcbiAgICBsZWdhY3ksXG4gICk7XG4gIGZvciAoXG4gICAgY29uc3QgZmFpbHVyZSBvZiBbXG4gICAgICBcImNvdW50X2Vycm9yXCIsXG4gICAgICBcImluc2VydF9lcnJvclwiLFxuICAgICAgXCJtaXNzaW5nX3JwY1wiLFxuICAgICAgXCJtYWxmb3JtZWRfcmVzZXJ2YXRpb25cIixcbiAgICBdXG4gICkge1xuICAgIG1vZGUgPSBmYWlsdXJlO1xuICAgIGNvdW50ZXIgPSAwO1xuICAgIGNvbnN0IGJlZm9yZSA9IHByb3ZpZGVyQXR0ZW1wdHMubGVuZ3RoO1xuICAgIGNvbnN0IHJlc3VsdCA9IGF3YWl0IHJlcXVlc3QoXG4gICAgICBcImF1dGgtc2VuZC13aGF0c2FwcC1vdHBcIixcbiAgICAgIGBPVFAgbGltaXRlciAke2ZhaWx1cmV9OiBmYWlscyBjbG9zZWRgLFxuICAgICAgc2lnbmVkT3RwKFwicWEtZmFpbHVyZS1cIiArIGNyeXB0by5yYW5kb21VVUlEKCkpLFxuICAgICk7XG4gICAgY2hlY2soXG4gICAgICByZXN1bHQubGFiZWwsXG4gICAgICByZXN1bHQuaHR0cF9zdGF0dXMgPT09IDUwMyAmJiBwcm92aWRlckF0dGVtcHRzLmxlbmd0aCA9PT0gYmVmb3JlICYmXG4gICAgICAgIHJlc3VsdC5kZXBlbmRlbmNpZXMubGVuZ3RoID09PSAxICYmXG4gICAgICAgIHJlc3VsdC5kZXBlbmRlbmNpZXNbMF0ucGF0aCA9PT0gXCIvcmVzdC92MS9ycGMvcmVzZXJ2ZV9zaWduZWRfb3RwX3YzXCIsXG4gICAgICByZXN1bHQsXG4gICAgKTtcbiAgfVxuICBtb2RlID0gXCJyZXNlcnZlX3RpbWVvdXRcIjtcbiAgY291bnRlciA9IDA7XG4gIGNvbnN0IHRpbWVvdXRTdGFydCA9IHBlcmZvcm1hbmNlLm5vdygpO1xuICBjb25zdCB0aW1lZCA9IGF3YWl0IHJlcXVlc3QoXG4gICAgXCJhdXRoLXNlbmQtd2hhdHNhcHAtb3RwXCIsXG4gICAgXCJPVFAgZHVyYWJsZSByZXNlcnZhdGlvbiB0aW1lb3V0IGFib3J0cyB3aXRob3V0IHNlbmRpbmdcIixcbiAgICBzaWduZWRPdHAoXCJxYS10aW1lb3V0LVwiICsgY3J5cHRvLnJhbmRvbVVVSUQoKSksXG4gICk7XG4gIGNvbnN0IGVsYXBzZWQgPSBwZXJmb3JtYW5jZS5ub3coKSAtIHRpbWVvdXRTdGFydDtcbiAgY2hlY2soXG4gICAgdGltZWQubGFiZWwsXG4gICAgdGltZWQuaHR0cF9zdGF0dXMgPT09IDUwMyAmJiBlbGFwc2VkIDwgNTAwMCAmJlxuICAgICAgdGltZWQuZGVwZW5kZW5jaWVzLmxlbmd0aCA9PT0gMSxcbiAgICB7IC4uLnRpbWVkLCBlbGFwc2VkX21zOiBlbGFwc2VkIH0sXG4gICk7XG4gIG1vZGUgPSBcIm5vcm1hbFwiO1xuICBjb3VudGVyID0gNTtcbiAgY29uc3QgbGltaXQgPSBhd2FpdCByZXF1ZXN0KFxuICAgIFwiYXV0aC1zZW5kLXdoYXRzYXBwLW90cFwiLFxuICAgIFwiT1RQIHNpeHRoIHJlcXVlc3QgcmVmdXNlZFwiLFxuICAgIHNpZ25lZE90cChcInFhLWxpbWl0LVwiICsgY3J5cHRvLnJhbmRvbVVVSUQoKSksXG4gICk7XG4gIGNoZWNrKGxpbWl0LmxhYmVsLCBsaW1pdC5odHRwX3N0YXR1cyA9PT0gNDI5ICYmIGNvdW50ZXIgPT09IDUsIGxpbWl0KTtcbiAgY291bnRlciA9IDQ7XG4gIGNvbnN0IGJlZm9yZUNvbmN1cnJlbnQgPSBwcm92aWRlckF0dGVtcHRzLmxlbmd0aDtcbiAgY29uc3QgY29uY3VycmVudCA9IGF3YWl0IFByb21pc2UuYWxsKFxuICAgIEFycmF5LmZyb20oeyBsZW5ndGg6IDggfSwgKF8sIGkpID0+XG4gICAgICByZXF1ZXN0KFxuICAgICAgICBcImF1dGgtc2VuZC13aGF0c2FwcC1vdHBcIixcbiAgICAgICAgYE9UUCBjb25jdXJyZW50ICR7aX1gLFxuICAgICAgICBzaWduZWRPdHAoXCJxYS1jb25jdXJyZW50LVwiICsgaSArIFwiLVwiICsgY3J5cHRvLnJhbmRvbVVVSUQoKSksXG4gICAgICApKSxcbiAgKTtcbiAgY2hlY2soXG4gICAgXCJPVFAgY29uY3VycmVuY3k6IG9uZSByZW1haW5pbmcgcmVzZXJ2YXRpb24gYWxsb3dzIG9ubHkgb25lIHRyYW5zcG9ydCBhdHRlbXB0XCIsXG4gICAgY29uY3VycmVudC5maWx0ZXIoKHIpID0+IHIuaHR0cF9zdGF0dXMgPT09IDUwMykubGVuZ3RoID09PSAxICYmXG4gICAgICBjb25jdXJyZW50LmZpbHRlcigocikgPT4gci5odHRwX3N0YXR1cyA9PT0gNDI5KS5sZW5ndGggPT09IDcgJiZcbiAgICAgIGNvdW50ZXIgPT09IDUgJiYgcHJvdmlkZXJBdHRlbXB0cy5sZW5ndGggLSBiZWZvcmVDb25jdXJyZW50ID09PSAxLFxuICAgIHtcbiAgICAgIHN0YXR1c2VzOiBjb25jdXJyZW50Lm1hcCgocikgPT4gci5odHRwX3N0YXR1cyksXG4gICAgICByZWNvcmRlZF9jb3VudGVyOiBjb3VudGVyLFxuICAgICAgbW9kZWw6XG4gICAgICAgIFwicmVjb3JkaW5nIHYzIGRlcGVuZGVuY3k7IHJlYWwgU1FMIHJhY2VzIHZlcmlmaWVkIGluIHRoZSBzZXBhcmF0ZTE0NSBwYWNrZXQ7IG5ldHdvcmsgcGVybWlzc2lvbnMgYmxvY2sgdGhlIHNpbmdsZSB0cmFuc3BvcnQgYXR0ZW1wdFwiLFxuICAgIH0sXG4gICk7XG4gIGZvciAoY29uc3Qgc2NlbmFyaW8gb2YgW1wibm9ybWFsXCIsIFwibG9zdF9yZWNvcmRfYWNrXCJdKSB7XG4gICAgbW9kZSA9IHNjZW5hcmlvO1xuICAgIGNvdW50ZXIgPSAwO1xuICAgIGNvbnN0IGlkID0gXCJxYS1uby1yZXNlbmQtXCIgKyBjcnlwdG8ucmFuZG9tVVVJRCgpLFxuICAgICAgYmVmb3JlID0gcHJvdmlkZXJBdHRlbXB0cy5sZW5ndGg7XG4gICAgY29uc3QgZmlyc3QgPSBhd2FpdCByZXF1ZXN0KFxuICAgICAgXCJhdXRoLXNlbmQtd2hhdHNhcHAtb3RwXCIsXG4gICAgICBgT1RQICR7c2NlbmFyaW99OiBkZW5pZWQgcHJvdmlkZXIgaXMgdW5yZXNvbHZlZGAsXG4gICAgICBzaWduZWRPdHAoaWQpLFxuICAgICk7XG4gICAgY29uc3QgcmVwbGF5ID0gYXdhaXQgcmVxdWVzdChcbiAgICAgIFwiYXV0aC1zZW5kLXdoYXRzYXBwLW90cFwiLFxuICAgICAgYE9UUCAke3NjZW5hcmlvfTogcmVwbGF5IGNhbm5vdCByZXNlbmRgLFxuICAgICAgc2lnbmVkT3RwKGlkKSxcbiAgICApO1xuICAgIGNoZWNrKFxuICAgICAgcmVwbGF5LmxhYmVsLFxuICAgICAgZmlyc3QuaHR0cF9zdGF0dXMgPT09IDUwMyAmJiByZXBsYXkuaHR0cF9zdGF0dXMgPT09IDUwMyAmJlxuICAgICAgICBjb3VudGVyID09PSAxICYmIHByb3ZpZGVyQXR0ZW1wdHMubGVuZ3RoIC0gYmVmb3JlID09PSAxICYmXG4gICAgICAgIHJlcGxheS5kZXBlbmRlbmNpZXMubWFwKChyKSA9PiByLnBhdGgpLmpvaW4oKSA9PT1cbiAgICAgICAgICBcIi9yZXN0L3YxL3JwYy9yZXNlcnZlX3NpZ25lZF9vdHBfdjNcIixcbiAgICAgIHsgZmlyc3QsIHJlcGxheSB9LFxuICAgICk7XG4gIH1cbiAgbW9kZSA9IFwibm9ybWFsXCI7XG4gIC8vIEFwcGVuZGVkIGFmdGVyIGV2ZXJ5IG9yaWdpbmFsIEhUVFAgYXNzZXJ0aW9uOyBzeW50aGV0aWMgcG9saWN5IG9ubHkuXG4gIC8vIEVhY2ggd2VsbC1oYXNoZWQgdHVwbGUgbWlzbWF0Y2ggbXVzdCBmYWlsIGJlZm9yZSByZXNlcnZlL2RlY29kZS9wcm92aWRlci5cbiAgZm9yIChcbiAgICBjb25zdCBbc2NlbmFyaW8sIHBvbGljeVBhdGNoLCBlbnZpcm9ubWVudFBhdGNoXSBvZiBbXG4gICAgICBbXCJtaXNzaW5nIHBvbGljeVwiLCB7fSwgeyBST1NURVJfQUlfQVBQUk9WQUxfSlNPTjogdW5kZWZpbmVkIH1dLFxuICAgICAgW1wibWlzc2luZyBoYXNoXCIsIHt9LCB7IFJPU1RFUl9BSV9BUFBST1ZBTF9TSEEyNTY6IHVuZGVmaW5lZCB9XSxcbiAgICAgIFtcInRhbXBlcmVkIGhhc2hcIiwge30sIHsgUk9TVEVSX0FJX0FQUFJPVkFMX1NIQTI1NjogXCIwXCIucmVwZWF0KDY0KSB9XSxcbiAgICAgIFtcIndyb25nIG1vZGVsXCIsIHsgbW9kZWw6IFwic3ludGhldGljLW90aGVyLW1vZGVsXCIgfSwge31dLFxuICAgICAgW1wid3JvbmcgZGVjb2RlciBVUkxcIiwgeyBkZWNvZGVyX3VybDogXCJodHRwOi8vMTI3LjAuMC4xOjEvZGVjb2RlXCIgfSwge31dLFxuICAgICAgW1wid3JvbmcgZGVjb2RlciBidWlsZFwiLCB7IGRlY29kZXJfYnVpbGRfc2hhMjU2OiBcImVcIi5yZXBlYXQoNjQpIH0sIHt9XSxcbiAgICAgIFtcIndyb25nIG9yZ2FuaXphdGlvblwiLCB7IG9yZ2FuaXphdGlvbl9pZDogXCJvcmdfb3RoZXJfc3ludGhldGljXCIgfSwge31dLFxuICAgICAgW1wid3JvbmcgcHJvamVjdFwiLCB7IHByb2plY3RfaWQ6IFwicHJval9vdGhlcl9zeW50aGV0aWNcIiB9LCB7fV0sXG4gICAgICBbXCJkaXNhYmxlZCBwb2xpY3lcIiwgeyBlbmFibGVkOiBmYWxzZSB9LCB7fV0sXG4gICAgICBbXCJyZXZva2VkIHBvbGljeVwiLCB7IHN0YXR1czogXCJyZXZva2VkXCIgfSwge31dLFxuICAgICAgW1wiZXhwaXJlZCBwb2xpY3lcIiwgeyB2YWxpZF91bnRpbDogXCIyMDIxLTAxLTAxVDAwOjAwOjAwWlwiIH0sIHt9XSxcbiAgICAgIFtcImZ1dHVyZSBhcHByb3ZhbFwiLCB7IGFwcHJvdmVkX2F0OiBcIjIwOTgtMDEtMDFUMDA6MDA6MDBaXCIgfSwge31dLFxuICAgIF0gYXMgY29uc3RcbiAgKSB7XG4gICAgY29uc3QgbmVnYXRpdmVBcHByb3ZhbCA9IGF3YWl0IHN5bnRoZXRpY1Jvc3RlckFpQXBwcm92YWwoXG4gICAgICByb3N0ZXJNb2RlbCxcbiAgICAgIGRlY29kZXJVcmwsXG4gICAgICBkZWNvZGVyQnVpbGQsXG4gICAgICBwb2xpY3lQYXRjaCxcbiAgICApO1xuICAgIGNvbnN0IG5lZ2F0aXZlRW52aXJvbm1lbnQ6IFJlY29yZDxzdHJpbmcsIHN0cmluZyB8IHVuZGVmaW5lZD4gPSB7XG4gICAgICBST1NURVJfQUlfQVBQUk9WQUxfSlNPTjogbmVnYXRpdmVBcHByb3ZhbC5haUFwcHJvdmFsSnNvbixcbiAgICAgIFJPU1RFUl9BSV9BUFBST1ZBTF9TSEEyNTY6IG5lZ2F0aXZlQXBwcm92YWwuYWlBcHByb3ZhbFNoYTI1NixcbiAgICAgIE9QRU5BSV9PUkdBTklaQVRJT05fSUQ6IG5lZ2F0aXZlQXBwcm92YWwub3BlbkFpT3JnYW5pemF0aW9uSWQsXG4gICAgICBPUEVOQUlfUFJPSkVDVF9JRDogbmVnYXRpdmVBcHByb3ZhbC5vcGVuQWlQcm9qZWN0SWQsXG4gICAgfTtcbiAgICBmb3IgKGNvbnN0IFtrZXksIHZhbHVlXSBvZiBPYmplY3QuZW50cmllcyhlbnZpcm9ubWVudFBhdGNoKSkge1xuICAgICAgbmVnYXRpdmVFbnZpcm9ubWVudFtrZXldID0gdmFsdWU7XG4gICAgfVxuICAgIGNvbnN0IGJlZm9yZSA9IHByb3ZpZGVyQXR0ZW1wdHMubGVuZ3RoO1xuICAgIHRyeSB7XG4gICAgICBmb3IgKGNvbnN0IFtrZXksIHZhbHVlXSBvZiBPYmplY3QuZW50cmllcyhuZWdhdGl2ZUVudmlyb25tZW50KSkge1xuICAgICAgICBpZiAodHlwZW9mIHZhbHVlID09PSBcInN0cmluZ1wiKSBEZW5vLmVudi5zZXQoa2V5LCB2YWx1ZSk7XG4gICAgICAgIGVsc2UgRGVuby5lbnYuZGVsZXRlKGtleSk7XG4gICAgICB9XG4gICAgICBjb25zdCByZXN1bHQgPSBhd2FpdCByZXF1ZXN0KFxuICAgICAgICBcInByZXBhcmUtcm9zdGVyLWltcG9ydFwiLFxuICAgICAgICBgcm9zdGVyIEFJIGFwcHJvdmFsOiAke3NjZW5hcmlvfSByZWZ1c2VzIGJlZm9yZSB3b3JrYCxcbiAgICAgICAge1xuICAgICAgICAgIGhlYWRlcnM6IHsgYXV0aG9yaXphdGlvbjogdXNlckF1dGhvcml6YXRpb24gfSxcbiAgICAgICAgICBib2R5OiBKU09OLnN0cmluZ2lmeShyb3N0ZXJJbWFnZSgpKSxcbiAgICAgICAgfSxcbiAgICAgICk7XG4gICAgICBjaGVjayhcbiAgICAgICAgcmVzdWx0LmxhYmVsLFxuICAgICAgICByZXN1bHQuaHR0cF9zdGF0dXMgPT09IDUwMyAmJlxuICAgICAgICAgIChyZXN1bHQucmVzcG9uc2UgYXMgUmVjb3JkPHN0cmluZywgdW5rbm93bj4pPy5lcnJvciA9PT1cbiAgICAgICAgICAgIFwicm9zdGVyX2V4dHJhY3Rpb25fdW5hdmFpbGFibGVcIiAmJlxuICAgICAgICAgIEpTT04uc3RyaW5naWZ5KHJlc3VsdC5kZXBlbmRlbmNpZXMubWFwKChyKSA9PiByLnBhdGgpKSA9PT1cbiAgICAgICAgICAgIEpTT04uc3RyaW5naWZ5KFtcIi9hdXRoL3YxL3VzZXJcIl0pICYmXG4gICAgICAgICAgcHJvdmlkZXJBdHRlbXB0cy5sZW5ndGggPT09IGJlZm9yZSAmJiByZXN1bHQubm9fc3RvcmUgPT09IHRydWUsXG4gICAgICAgIHJlc3VsdCxcbiAgICAgICk7XG4gICAgfSBmaW5hbGx5IHtcbiAgICAgIGZvciAoY29uc3QgW2tleSwgdmFsdWVdIG9mIE9iamVjdC5lbnRyaWVzKHJvc3RlckFwcHJvdmFsRW52aXJvbm1lbnQpKSB7XG4gICAgICAgIERlbm8uZW52LnNldChrZXksIHZhbHVlKTtcbiAgICAgIH1cbiAgICB9XG4gIH1cbiAgcmVwb3J0LnN0YXR1cyA9IGNoZWNrcy5ldmVyeSgocikgPT4gci5zdGF0dXMgPT09IFwicGFzc1wiKSA/IFwicGFzc1wiIDogXCJmYWlsXCI7XG59IGNhdGNoIChlcnJvcikge1xuICByZXBvcnQuc3RhdHVzID0gXCJmYWlsXCI7XG4gIHJlcG9ydC5lcnJvciA9IGVycm9yIGluc3RhbmNlb2YgRXJyb3IgPyBlcnJvci5tZXNzYWdlIDogU3RyaW5nKGVycm9yKTtcbn0gZmluYWxseSB7XG4gIERlbm8uc2VydmUgPSByZWFsU2VydmU7XG4gIGdsb2JhbFRoaXMuZmV0Y2ggPSBvcmlnaW5hbEZldGNoO1xuICBjb25zb2xlLmxvZyhcbiAgICBcIlFBX0VER0VfQ0xPU0lORz1cIiArXG4gICAgICBKU09OLnN0cmluZ2lmeSh7XG4gICAgICAgIHN0YXR1czogcmVwb3J0LnN0YXR1cyxcbiAgICAgICAgZXJyb3I6IHJlcG9ydC5lcnJvcixcbiAgICAgICAgY2hlY2tzOiBjaGVja3MubGVuZ3RoLFxuICAgICAgICBsYXN0X2RlcGVuZGVuY3lfcGF0aHM6IHJlY29yZHMuc2xpY2UoLTEwKS5tYXAoKHJlY29yZCkgPT4gcmVjb3JkLnBhdGgpLFxuICAgICAgfSksXG4gICk7XG4gIC8vIEFsbCBzY2VuYXJpbyByZXNwb25zZXMgd2VyZSBjb25zdW1lZC4gQWJvcnQgb25seSB0aGlzIHByb2Nlc3MncyBvd25lZFxuICAvLyB0ZXN0IGxpc3RlbmVycywgaW5jbHVkaW5nIGtlZXAtYWxpdmUgc29ja2V0cywgdGhlbiBhd2FpdCB0aGVpciBjb21wbGV0aW9uLlxuICBjb250cm9sbGVycy5mb3JFYWNoKChjb250cm9sbGVyKSA9PiBjb250cm9sbGVyLmFib3J0KCkpO1xuICBhd2FpdCBQcm9taXNlLmFsbChzZXJ2ZXJzLm1hcCgoc2VydmVyKSA9PiBzZXJ2ZXIuZmluaXNoZWQpKTtcbiAgcmVwb3J0LmZpbmlzaGVkX2F0ID0gbmV3IERhdGUoKS50b0lTT1N0cmluZygpO1xuICByZXBvcnQuc2VydmVyc19jbG9zZWQgPSBzZXJ2ZXJzLmxlbmd0aDtcbiAgcmVwb3J0LmNsZWFudXBfbW9kZSA9IFwib3duZWRfbGlzdGVuZXJzX2Fib3J0ZWRfYWZ0ZXJfc2NlbmFyaW9fcmVzcG9uc2VzXCI7XG4gIGNvbnNvbGUubG9nKFwiUUFfRURHRV9SRVBPUlQ9XCIgKyBKU09OLnN0cmluZ2lmeShyZXBvcnQpKTtcbn1cbmlmIChyZXBvcnQuc3RhdHVzICE9PSBcInBhc3NcIikgRGVuby5leGl0KDEpO1xuIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiJBQUFBLDhFQUE4RTtBQUM5RSw4RUFBOEU7QUFDOUUsK0VBQStFO0FBQy9FLFNBQVMsT0FBTyxRQUFRLDZCQUE2QjtBQUNyRCxTQUFTLGFBQWEsUUFBUSwyQ0FBMkM7QUFDekUsU0FBUyx5QkFBeUIsUUFBUSxvREFBb0Q7QUFDOUYsU0FBUyx3QkFBd0IsUUFBUSxxREFBcUQ7QUFDOUYsU0FBUyx5QkFBeUIsUUFBUSxzRUFBc0U7QUFFaEgsNEVBQTRFO0FBQzVFLDJFQUEyRTtBQUMzRSwrRUFBK0U7QUFDL0UsTUFBTSxvQkFBNEQ7RUFDaEUsMEJBQTBCLElBQ3hCLE1BQU0sQ0FBQztFQUNULDJCQUEyQixJQUN6QixNQUFNLENBQUM7RUFDVCxpQ0FBaUMsSUFDL0IsTUFBTSxDQUFDO0VBQ1Qsb0NBQW9DLElBQ2xDLE1BQU0sQ0FBQztFQUNULHFDQUFxQyxJQUNuQyxNQUFNLENBQUM7RUFDVCw4QkFBOEIsSUFDNUIsTUFBTSxDQUFDO0VBQ1QsMEJBQTBCLElBQ3hCLE1BQU0sQ0FBQztFQUNULHNCQUFzQixJQUNwQixNQUFNLENBQUM7RUFDVCxxQkFBcUIsSUFDbkIsTUFBTSxDQUFD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
// denoCacheMetadata=8609206048186788972,808666995538893221
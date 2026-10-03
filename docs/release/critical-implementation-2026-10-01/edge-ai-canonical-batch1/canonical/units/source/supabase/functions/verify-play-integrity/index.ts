import {
  boundedJson,
  fetchJson,
  objectValue,
  PublicError,
} from "../_shared/production_contract.ts";
import { validateIntegrityVerdict } from "../_shared/integrity_policy.ts";
import { corsHeaders, jsonResponse, requireEnv } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";
import { rosterSession } from "../_shared/roster_provenance.ts";
import {
  integrityAdmissionError,
  integrityAdmissionReceipt,
  type IntegrityBinding,
  integrityResult,
} from "../_shared/integrity_admission.ts";
import {
  sha256Hex,
  smsCapabilityPayload,
  type SmsIntegrityRequest,
  smsIntegrityRequestHash,
} from "../_shared/play_integrity_binding.ts";

type ServiceAccount = {
  client_email: string;
  private_key: string;
  token_uri?: string;
};

const packageName = "app.cool.mobile";
const tokenUri = "https://oauth2.googleapis.com/token";
const playScope = "https://www.googleapis.com/auth/playintegrity";
class GoogleTransportError extends PublicError {
  constructor(readonly providerStatus: number) {
    super("play_integrity_unavailable", 503);
  }
}
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function base64Url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll(
    "=",
    "",
  );
}

function pemBuffer(pem: string): ArrayBuffer {
  const clean = pem.replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
  const binary = atob(clean);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

async function accessToken(): Promise<string> {
  const raw = Deno.env.get("PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON")?.trim() ||
    requireEnv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
  const account = JSON.parse(raw) as ServiceAccount;
  const now = Math.floor(Date.now() / 1_000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64Url(JSON.stringify({
    iss: account.client_email,
    scope: playScope,
    aud: tokenUri,
    exp: now + 3_600,
    iat: now,
  }));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemBuffer(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claim}`),
  );
  const response = await fetchJson(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claim}.${base64Url(signature)}`,
    }),
  });
  const result = objectValue(response.data);
  if (!response.ok || typeof result.access_token !== "string") {
    throw new GoogleTransportError(response.status);
  }
  return result.access_token;
}

async function decodeIntegrityToken(token: string, access: string) {
  const response = await fetchJson(
    `https://playintegrity.googleapis.com/v1/${packageName}:decodeIntegrityToken`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${access}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ integrityToken: token }),
    },
  );
  const result = objectValue(response.data);
  if (!response.ok) throw new GoogleTransportError(response.status);
  return {
    decoded: result.tokenPayloadExternal as Record<string, unknown>,
    providerStatus: response.status,
  };
}

function cleanString(value: unknown, _field: string, max: number): string {
  if (typeof value !== "string") {
    throw new PublicError("invalid_integrity_request", 400);
  }
  const clean = value.trim();
  if (!clean || clean.length > max) {
    throw new PublicError("invalid_integrity_request", 400);
  }
  return clean;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }
  let reservationId: string | undefined;
  let binding: IntegrityBinding | undefined;
  let decodeStartedAt: number | undefined;
  let providerStatus: number | null = null;
  const duration = () =>
    decodeStartedAt === undefined ? null : Math.min(
      120_000,
      Math.max(0, Math.ceil(performance.now() - decodeStartedAt)),
    );
  const rpc = async (name: string, params: Record<string, unknown>) => {
    const { data, error } = await serviceClient().rpc(name, params).abortSignal(
      AbortSignal.timeout(5_000),
    );
    if (error) throw integrityAdmissionError(error);
    return data;
  };
  try {
    const authorization = req.headers.get("authorization");
    const { user } = await requireUser(authorization);
    const caller = rosterSession(authorization, user.id);
    const payload = await boundedJson(req, 32768);
    const action = payload.action;
    if (
      (action !== "group.create" && action !== "sms.ingest") ||
      payload.subject_id !== user.id ||
      payload.sms_permission_granted !== true ||
      payload.sms_access_enabled !== true
    ) {
      return jsonResponse({ error: "Invalid Play Integrity request" }, 400);
    }
    const requestHash = cleanString(payload.request_hash, "request_hash", 64)
      .toLowerCase();
    const token = cleanString(
      payload.integrity_token,
      "integrity_token",
      20_000,
    );
    const nonce = cleanString(payload.nonce, "nonce", 36);
    const receiverHash = cleanString(
      payload.receiver_momo_number_hash,
      "receiver_momo_number_hash",
      64,
    ).toLowerCase();
    if (
      !/^[0-9a-f]{64}$/.test(requestHash) ||
      !/^[0-9a-f]{64}$/.test(receiverHash) ||
      !uuidPattern.test(nonce)
    ) {
      return jsonResponse({ error: "Invalid Play Integrity binding" }, 400);
    }
    let expectedHash: string;
    let capabilityPayload: Record<string, unknown>;
    if (action === "group.create") {
      const untrusted = payload.group_request;
      if (
        typeof untrusted !== "object" || untrusted == null ||
        Array.isArray(untrusted)
      ) {
        return jsonResponse({ error: "Group request is required" }, 400);
      }
      const group = untrusted as Record<string, unknown>;
      if (
        group.group_is_public !== false ||
        group.receiver_momo_number_hash !== receiverHash
      ) {
        return jsonResponse({
          error: "Only private Android groups are allowed",
        }, 400);
      }
      capabilityPayload = {
        group_name: cleanString(group.group_name, "group_name", 120),
        group_description: typeof group.group_description === "string"
          ? group.group_description.trim().slice(0, 2_000)
          : "",
        receiver_momo_number: cleanString(
          group.receiver_momo_number,
          "receiver_momo_number",
          40,
        ),
        receiver_momo_number_hash: receiverHash,
        receiver_label: cleanString(group.receiver_label, "receiver_label", 80),
        group_collection_type: cleanString(
          group.group_collection_type,
          "group_collection_type",
          64,
        ),
        group_category_subtype: typeof group.group_category_subtype === "string"
          ? group.group_category_subtype.trim() || null
          : null,
        group_purpose_label: typeof group.group_purpose_label === "string"
          ? group.group_purpose_label.trim() || null
          : null,
        group_is_public: false,
      };
      expectedHash = await sha256Hex(JSON.stringify({
        action,
        subject_id: user.id,
        nonce,
        receiver_momo_number_hash: receiverHash,
        sms_permission_granted: true,
        sms_access_enabled: true,
        group_request: capabilityPayload,
      }));
    } else {
      const untrusted = payload.sms_request;
      if (
        typeof untrusted !== "object" || untrusted == null ||
        Array.isArray(untrusted)
      ) {
        return jsonResponse({ error: "SMS request is required" }, 400);
      }
      const sms = untrusted as Record<string, unknown>;
      const clientEnvelopeId = cleanString(
        sms.client_envelope_id,
        "client_envelope_id",
        36,
      );
      const rawBodySha256 = cleanString(
        sms.raw_body_sha256,
        "raw_body_sha256",
        64,
      ).toLowerCase();
      const receivedAtDevice = sms.received_at_device == null
        ? null
        : cleanString(sms.received_at_device, "received_at_device", 64);
      if (
        !uuidPattern.test(clientEnvelopeId) ||
        !/^[0-9a-f]{64}$/.test(rawBodySha256) ||
        (receivedAtDevice != null && Number.isNaN(Date.parse(receivedAtDevice)))
      ) {
        return jsonResponse({ error: "Invalid SMS integrity binding" }, 400);
      }
      const smsInput: SmsIntegrityRequest = {
        subjectId: user.id,
        nonce,
        receiverMomoNumberHash: receiverHash,
        clientEnvelopeId,
        rawSender: cleanString(sms.raw_sender, "raw_sender", 96),
        rawBodySha256,
        receivedAtDevice,
      };
      expectedHash = await smsIntegrityRequestHash(smsInput);
      capabilityPayload = smsCapabilityPayload(smsInput);
    }
    if (expectedHash !== requestHash) {
      return jsonResponse({ error: "Request binding mismatch" }, 400);
    }

    const minimumVersion = Number(
      requireEnv("PLAY_INTEGRITY_MIN_VERSION_CODE"),
    );
    const certificates = new Set(
      requireEnv("PLAY_INTEGRITY_CERTIFICATE_SHA256").split(",").map((v) =>
        v.trim()
      ).filter(Boolean),
    );
    if (
      !Number.isSafeInteger(minimumVersion) || minimumVersion < 1 ||
      !certificates.size
    ) throw new PublicError("integrity_policy_unconfigured", 503);
    // Fail before reservations/Google if no account is configured. Key import
    // and signing remain inside the admitted OAuth phase.
    const accountRaw =
      Deno.env.get("PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON")?.trim() ||
      requireEnv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
    let account: ServiceAccount;
    try {
      account = JSON.parse(accountRaw) as ServiceAccount;
    } catch {
      throw new PublicError("integrity_policy_unconfigured", 503);
    }
    if (
      !account || typeof account.client_email !== "string" ||
      typeof account.private_key !== "string"
    ) throw new PublicError("integrity_policy_unconfigured", 503);
    binding = {
      actorId: caller.actorId,
      sessionId: caller.sessionId,
      nonce: nonce.toLowerCase(),
      action,
      requestHash,
      tokenHash: await sha256Hex(token),
    };
    const actorParams = {
      p_actor_id: caller.actorId,
      p_session_id: caller.sessionId,
    };
    const reserved = await rpc("reserve_play_integrity_admission_v1", {
      ...actorParams,
      p_nonce: binding.nonce,
      p_action: action,
      p_request_hash: requestHash,
      p_token_sha256: binding.tokenHash,
      p_receiver_hash: receiverHash,
      p_request_payload: capabilityPayload,
    });
    if (
      typeof reserved === "object" && reserved !== null &&
      (reserved as Record<string, unknown>).state === "completed"
    ) {
      const receipt = integrityAdmissionReceipt(reserved, binding, "completed");
      return jsonResponse(integrityResult(receipt.result, binding));
    }
    reservationId =
      integrityAdmissionReceipt(reserved, binding, "reserved").reservationId;
    const admissionParams = { ...actorParams, p_reservation_id: reservationId };
    integrityAdmissionReceipt(
      await rpc("begin_play_integrity_admission_v1", {
        ...admissionParams,
        p_phase: "oauth",
      }),
      binding,
      "oauth_started",
    );
    const access = await accessToken();
    // Revocation/expiry between OAuth and decode denies the second expensive
    // transport. Each phase is single-use and durable across handler restarts.
    integrityAdmissionReceipt(
      await rpc("begin_play_integrity_admission_v1", {
        ...admissionParams,
        p_phase: "decode",
      }),
      binding,
      "decode_started",
    );
    decodeStartedAt = performance.now();
    const transport = await decodeIntegrityToken(token, access);
    const decoded = transport.decoded;
    providerStatus = transport.providerStatus;
    const policy = validateIntegrityVerdict(decoded, requestHash, {
      packageName,
      minimumVersion,
      certificates,
      nowMs: Date.now(),
    });
    const verdictPackage = policy.packageName, appVerdict = policy.appVerdict;
    const deviceVerdicts = policy.deviceVerdicts,
      timestampMillis = policy.timestampMillis;
    const result = await rpc("complete_play_integrity_admission_v1", {
      ...admissionParams,
      p_request_payload: capabilityPayload,
      p_package_name: verdictPackage,
      p_app_verdict: appVerdict,
      p_device_verdicts: deviceVerdicts,
      p_verified_at: new Date(timestampMillis).toISOString(),
      p_decode_duration_ms: duration(),
      p_provider_status: providerStatus,
    });
    return jsonResponse(integrityResult(result, binding));
  } catch (error) {
    if (reservationId && binding) {
      // A lost completion ACK may already have minted a durable capability.
      // Cleanup never overwrites that completion or permits a Google retry.
      try {
        await rpc("finish_play_integrity_admission_v1", {
          p_actor_id: binding.actorId,
          p_session_id: binding.sessionId,
          p_reservation_id: reservationId,
          p_outcome: error instanceof PublicError &&
              error.code === "integrity_policy_rejected"
            ? "rejected"
            : "ambiguous",
          p_decode_duration_ms: duration(),
          p_provider_status: error instanceof GoogleTransportError
            ? error.providerStatus
            : providerStatus,
        });
      } catch { /* Durable phase/quota history still prevents redispatch. */ }
    }
    const message = error instanceof Error
      ? error.message
      : "Play Integrity failed";
    if (error instanceof PublicError) {
      return jsonResponse({
        error: error.code === "integrity_policy_unconfigured"
          ? "play_integrity_unavailable"
          : error.code,
      }, error.status);
    }
    if (message === "Authentication required") {
      return jsonResponse({ error: "authentication_required" }, 401);
    }
    if (/required env var/i.test(message)) {
      return jsonResponse({ error: "play_integrity_unavailable" }, 503);
    }
    return jsonResponse({ error: "Play Integrity verification failed" }, 502);
  }
});

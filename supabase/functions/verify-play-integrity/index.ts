import { corsHeaders, jsonResponse, requireEnv } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";
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
const maxTokenAgeMs = 5 * 60 * 1_000;
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
    aud: account.token_uri ?? tokenUri,
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
  const response = await fetch(account.token_uri ?? tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth2:grant-type:jwt-bearer",
      assertion: `${header}.${claim}.${base64Url(signature)}`,
    }),
  });
  const result = await response.json();
  if (!response.ok || typeof result.access_token !== "string") {
    throw new Error("Play Integrity token exchange failed");
  }
  return result.access_token;
}

async function decodeIntegrityToken(token: string) {
  const response = await fetch(
    `https://playintegrity.googleapis.com/v1/${packageName}:decodeIntegrityToken`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${await accessToken()}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ integrityToken: token }),
    },
  );
  const result = await response.json();
  if (!response.ok) throw new Error("Play Integrity decode failed");
  return result.tokenPayloadExternal as Record<string, unknown>;
}

function cleanString(value: unknown, field: string, max: number): string {
  if (typeof value !== "string") throw new Error(`${field} is required`);
  const clean = value.trim();
  if (!clean || clean.length > max) throw new Error(`${field} is invalid`);
  return clean;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }
  try {
    const { user } = await requireUser(req.headers.get("authorization"));
    const payload = await req.json() as Record<string, unknown>;
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
      !/^[0-9a-f-]{36}$/i.test(nonce)
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

    const decoded = await decodeIntegrityToken(token);
    const requestDetails = decoded.requestDetails as
      | Record<string, unknown>
      | undefined;
    const appIntegrity = decoded.appIntegrity as
      | Record<string, unknown>
      | undefined;
    const deviceIntegrity = decoded.deviceIntegrity as
      | Record<string, unknown>
      | undefined;
    const verdictPackage = String(appIntegrity?.packageName ?? "");
    const appVerdict = String(appIntegrity?.appRecognitionVerdict ?? "UNKNOWN");
    const tokenHash = String(requestDetails?.requestHash ?? "");
    const timestampMillis = Number(requestDetails?.timestampMillis ?? 0);
    const deviceVerdicts =
      Array.isArray(deviceIntegrity?.deviceRecognitionVerdict)
        ? (deviceIntegrity?.deviceRecognitionVerdict as unknown[]).map(String)
        : [];
    const recognizedDevice =
      deviceVerdicts.includes("MEETS_DEVICE_INTEGRITY") ||
      deviceVerdicts.includes("MEETS_STRONG_INTEGRITY");
    const fresh = timestampMillis > 0 &&
      Math.abs(Date.now() - timestampMillis) <= maxTokenAgeMs;
    if (
      verdictPackage !== packageName || appVerdict !== "PLAY_RECOGNIZED" ||
      tokenHash !== requestHash || !recognizedDevice || !fresh
    ) {
      return jsonResponse({
        status: "fail",
        action,
        request_hash: requestHash,
        package_name: verdictPackage,
        app_verdict: appVerdict,
        device_verdicts: deviceVerdicts,
      });
    }
    const { data: capability, error } = await serviceClient().rpc(
      "mint_native_action_capability",
      {
        capability_user_id: user.id,
        capability_action: action,
        capability_request_hash: requestHash,
        capability_request_payload: capabilityPayload,
        capability_receiver_hash: receiverHash,
        capability_package_name: verdictPackage,
        capability_app_verdict: appVerdict,
        capability_device_verdicts: deviceVerdicts,
        capability_verified_at: new Date(timestampMillis).toISOString(),
      },
    );
    if (error || typeof capability !== "string") {
      throw new Error("Native capability mint failed");
    }
    return jsonResponse({
      status: "pass",
      action,
      request_hash: requestHash,
      package_name: verdictPackage,
      app_verdict: appVerdict,
      device_verdicts: deviceVerdicts,
      native_capability: capability,
      capability_expires_at: new Date(timestampMillis + maxTokenAgeMs)
        .toISOString(),
    });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Play Integrity failed";
    if (message === "Authentication required") {
      return jsonResponse({ error: message }, 401);
    }
    if (/required env var/i.test(message)) {
      return jsonResponse({
        error: "Play Integrity verification unavailable",
        blocker: "play_integrity_service_account_missing",
      }, 503);
    }
    return jsonResponse({ error: "Play Integrity verification failed" }, 502);
  }
});

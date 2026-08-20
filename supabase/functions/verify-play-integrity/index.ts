import {
  corsHeaders,
  jsonResponse,
  requireEnv,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";

type VerifyIntegrityRequest = {
  action?: string;
  request_hash?: string;
  integrity_token?: string;
  subject_id?: string;
  nonce?: string;
  receiver_momo_number_hash?: string;
  sms_permission_granted?: boolean;
  sms_access_enabled?: boolean;
  group_request?: Record<string, unknown>;
};

type ServiceAccount = {
  client_email: string;
  private_key: string;
  token_uri?: string;
};

const playIntegrityScope = "https://www.googleapis.com/auth/playintegrity";
const tokenUri = "https://oauth2.googleapis.com/token";
const defaultPackageName = "app.cool.mobile";
const maxTokenAgeMs = 5 * 60 * 1000;

function boundedString(
  value: unknown,
  name: string,
  minLength: number,
  maxLength: number,
): string {
  if (typeof value !== "string") throw new Error(`${name} is required`);
  const clean = value.trim();
  if (clean.length < minLength || clean.length > maxLength) {
    throw new Error(`${name} is invalid`);
  }
  return clean;
}

function optionalBoundedString(
  value: unknown,
  name: string,
  maxLength: number,
): string | null {
  if (value == null || value === "") return null;
  return boundedString(value, name, 1, maxLength);
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

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

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

async function serviceAccountAccessToken(): Promise<string> {
  const raw = Deno.env.get("PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON")?.trim() ||
    requireEnv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
  const account = JSON.parse(raw) as ServiceAccount;
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64Url(JSON.stringify({
    iss: account.client_email,
    scope: playIntegrityScope,
    aud: account.token_uri ?? tokenUri,
    exp: now + 3600,
    iat: now,
  }));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claim}`),
  );
  const assertion = `${header}.${claim}.${base64Url(signature)}`;
  const response = await fetch(account.token_uri ?? tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const token = await response.json();
  if (!response.ok || !token.access_token) {
    throw new Error("Play Integrity token exchange failed");
  }
  return token.access_token as string;
}

async function decodeIntegrityToken(packageName: string, token: string) {
  const accessToken = await serviceAccountAccessToken();
  const response = await fetch(
    `https://playintegrity.googleapis.com/v1/${packageName}:decodeIntegrityToken`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ integrityToken: token }),
    },
  );
  const decoded = await response.json();
  if (!response.ok) {
    throw new Error("Play Integrity decode failed");
  }
  return decoded.tokenPayloadExternal ?? {};
}

function sanitizedVerdict(
  action: string,
  requestHash: string,
  packageName: string,
  payload: Record<string, unknown>,
) {
  const requestDetails = payload.requestDetails as
    | Record<string, unknown>
    | undefined;
  const appIntegrity = payload.appIntegrity as
    | Record<string, unknown>
    | undefined;
  const deviceIntegrity = payload.deviceIntegrity as
    | Record<string, unknown>
    | undefined;
  const accountDetails = payload.accountDetails as
    | Record<string, unknown>
    | undefined;
  const verdictPackage = String(appIntegrity?.packageName ?? "");
  const appVerdict = String(appIntegrity?.appRecognitionVerdict ?? "UNKNOWN");
  const tokenRequestHash = String(requestDetails?.requestHash ?? "");
  const timestampMillis = Number(requestDetails?.timestampMillis ?? 0);
  const deviceVerdicts =
    Array.isArray(deviceIntegrity?.deviceRecognitionVerdict)
      ? deviceIntegrity?.deviceRecognitionVerdict.map(String)
      : [];
  const licensingVerdict = String(
    accountDetails?.appLicensingVerdict ?? "UNKNOWN",
  );
  const tokenFresh = timestampMillis > 0 &&
    Math.abs(Date.now() - timestampMillis) <= maxTokenAgeMs;
  const recognizedDevice = deviceVerdicts.includes("MEETS_DEVICE_INTEGRITY") ||
    deviceVerdicts.includes("MEETS_STRONG_INTEGRITY");
  const passed = verdictPackage === packageName &&
    appVerdict === "PLAY_RECOGNIZED" &&
    tokenRequestHash === requestHash &&
    tokenFresh &&
    recognizedDevice;
  const failureReasons: string[] = [];
  if (verdictPackage !== packageName) {
    failureReasons.push("package_name_mismatch");
  }
  if (appVerdict !== "PLAY_RECOGNIZED") {
    failureReasons.push("app_not_play_recognized");
  }
  if (tokenRequestHash !== requestHash) {
    failureReasons.push("request_hash_mismatch");
  }
  if (!tokenFresh) failureReasons.push("token_stale_or_missing_timestamp");
  if (!recognizedDevice) failureReasons.push("device_integrity_not_met");

  return {
    status: passed ? "pass" : "fail",
    action,
    request_hash: requestHash,
    package_name: verdictPackage,
    app_verdict: appVerdict,
    device_verdicts: deviceVerdicts,
    licensing_verdict: licensingVerdict,
    timestamp_millis: timestampMillis,
    failure_reasons: failureReasons,
  };
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
    const packageName = Deno.env.get("PLAY_INTEGRITY_PACKAGE_NAME")?.trim() ||
      defaultPackageName;
    const payload = await req.json() as VerifyIntegrityRequest;
    const action = payload.action?.trim();
    const requestHash = payload.request_hash?.trim();
    const integrityToken = payload.integrity_token?.trim();
    const subjectId = payload.subject_id?.trim();
    const nonce = payload.nonce?.trim();
    const receiverHash = payload.receiver_momo_number_hash?.trim().toLowerCase();
    const untrustedGroupRequest = payload.group_request;
    if (
      action !== "group.create" ||
      !requestHash ||
      !integrityToken ||
      subjectId !== user.id ||
      !nonce ||
      !/^[0-9a-f-]{36}$/i.test(nonce) ||
      !receiverHash ||
      !/^[a-f0-9]{64}$/.test(receiverHash) ||
      payload.sms_permission_granted !== true ||
      payload.sms_access_enabled !== true ||
      typeof untrustedGroupRequest !== "object" ||
      untrustedGroupRequest == null ||
      Array.isArray(untrustedGroupRequest)
    ) {
      return jsonResponse({ error: "Invalid Play Integrity request" }, 400);
    }
    const groupRequest = {
      group_name: boundedString(
        untrustedGroupRequest.group_name,
        "group_name",
        2,
        120,
      ),
      group_description: boundedString(
        untrustedGroupRequest.group_description,
        "group_description",
        0,
        2_000,
      ),
      receiver_momo_number: boundedString(
        untrustedGroupRequest.receiver_momo_number,
        "receiver_momo_number",
        4,
        40,
      ),
      receiver_momo_number_hash: receiverHash,
      receiver_label: boundedString(
        untrustedGroupRequest.receiver_label,
        "receiver_label",
        1,
        80,
      ),
      group_collection_type: boundedString(
        untrustedGroupRequest.group_collection_type,
        "group_collection_type",
        2,
        64,
      ),
      group_category_subtype: optionalBoundedString(
        untrustedGroupRequest.group_category_subtype,
        "group_category_subtype",
        80,
      ),
      group_purpose_label: optionalBoundedString(
        untrustedGroupRequest.group_purpose_label,
        "group_purpose_label",
        160,
      ),
      group_is_public: untrustedGroupRequest.group_is_public,
    };
    if (groupRequest.group_is_public !== true && groupRequest.group_is_public !== false) {
      return jsonResponse({ error: "Invalid group visibility request" }, 400);
    }
    if (untrustedGroupRequest.receiver_momo_number_hash !== receiverHash) {
      return jsonResponse({ error: "Group receiver binding mismatch" }, 400);
    }
    if (!/^[a-f0-9]{64}$/i.test(requestHash)) {
      return jsonResponse({ error: "Invalid request hash" }, 400);
    }
    const expectedHash = await sha256Hex(JSON.stringify({
      action,
      subject_id: user.id,
      nonce,
      receiver_momo_number_hash: receiverHash,
      sms_permission_granted: true,
      sms_access_enabled: true,
      group_request: groupRequest,
    }));
    if (expectedHash !== requestHash.toLowerCase()) {
      return jsonResponse({ error: "Request binding mismatch" }, 400);
    }

    const decoded = await decodeIntegrityToken(packageName, integrityToken);
    const verdict = sanitizedVerdict(
      action,
      requestHash.toLowerCase(),
      packageName,
      decoded,
    );
    if (verdict.status !== "pass") {
      return jsonResponse(verdict);
    }

    const { data: capability, error: capabilityError } = await serviceClient()
      .rpc("mint_native_action_capability", {
        capability_user_id: user.id,
        capability_action: action,
        capability_request_hash: requestHash.toLowerCase(),
        capability_request_payload: groupRequest,
        capability_receiver_hash: receiverHash,
        capability_package_name: verdict.package_name,
        capability_app_verdict: verdict.app_verdict,
        capability_device_verdicts: verdict.device_verdicts,
        capability_verified_at: new Date(verdict.timestamp_millis)
          .toISOString(),
      });
    if (capabilityError || typeof capability !== "string") {
      throw new Error("Native capability mint failed");
    }

    return jsonResponse({
      ...verdict,
      native_capability: capability,
      capability_expires_at: new Date(
        verdict.timestamp_millis + maxTokenAgeMs,
      ).toISOString(),
    });
  } catch (error) {
    const message = safeErrorMessage(error);
    if (message === "Authentication required") {
      return jsonResponse({ error: message }, 401);
    }
    if (message.includes("Missing required env var")) {
      return jsonResponse({
        error: "Play Integrity verification unavailable",
        blocker: "play_integrity_service_account_missing",
      }, 503);
    }
    return jsonResponse({ error: "Play Integrity verification failed" }, 502);
  }
});

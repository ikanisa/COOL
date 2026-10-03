import { boundedJson, fetchJson, objectValue, PublicError } from "../_shared/production_contract.ts";
import { validateIntegrityVerdict } from "../_shared/integrity_policy.ts";
import { corsHeaders, jsonResponse, requireEnv } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";
import { rosterSession } from "../_shared/roster_provenance.ts";
import { integrityAdmissionError, integrityAdmissionReceipt, integrityResult } from "../_shared/integrity_admission.ts";
import { sha256Hex, smsCapabilityPayload, smsIntegrityRequestHash } from "../_shared/play_integrity_binding.ts";
const packageName = "app.cool.mobile";
const tokenUri = "https://oauth2.googleapis.com/token";
const playScope = "https://www.googleapis.com/auth/playintegrity";
class GoogleTransportError extends PublicError {
  providerStatus;
  constructor(providerStatus){
    super("play_integrity_unavailable", 503), this.providerStatus = providerStatus;
  }
}
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function base64Url(input) {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let binary = "";
  for (const byte of bytes)binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}
function pemBuffer(pem) {
  const clean = pem.replace(/-----BEGIN [^-]+-----/g, "").replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
  const binary = atob(clean);
  const bytes = new Uint8Array(binary.length);
  for(let index = 0; index < binary.length; index++){
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}
async function accessToken() {
  const raw = Deno.env.get("PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON")?.trim() || requireEnv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
  const account = JSON.parse(raw);
  const now = Math.floor(Date.now() / 1_000);
  const header = base64Url(JSON.stringify({
    alg: "RS256",
    typ: "JWT"
  }));
  const claim = base64Url(JSON.stringify({
    iss: account.client_email,
    scope: playScope,
    aud: tokenUri,
    exp: now + 3_600,
    iat: now
  }));
  const key = await crypto.subtle.importKey("pkcs8", pemBuffer(account.private_key), {
    name: "RSASSA-PKCS1-v1_5",
    hash: "SHA-256"
  }, false, [
    "sign"
  ]);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claim}`));
  const response = await fetchJson(tokenUri, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded"
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claim}.${base64Url(signature)}`
    })
  });
  const result = objectValue(response.data);
  if (!response.ok || typeof result.access_token !== "string") {
    throw new GoogleTransportError(response.status);
  }
  return result.access_token;
}
async function decodeIntegrityToken(token, access) {
  const response = await fetchJson(`https://playintegrity.googleapis.com/v1/${packageName}:decodeIntegrityToken`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${access}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      integrityToken: token
    })
  });
  const result = objectValue(response.data);
  if (!response.ok) throw new GoogleTransportError(response.status);
  return {
    decoded: result.tokenPayloadExternal,
    providerStatus: response.status
  };
}
function cleanString(value, _field, max) {
  if (typeof value !== "string") {
    throw new PublicError("invalid_integrity_request", 400);
  }
  const clean = value.trim();
  if (!clean || clean.length > max) {
    throw new PublicError("invalid_integrity_request", 400);
  }
  return clean;
}
Deno.serve(async (req)=>{
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders
    });
  }
  if (req.method !== "POST") {
    return jsonResponse({
      error: "Method not allowed"
    }, 405);
  }
  let reservationId;
  let binding;
  let decodeStartedAt;
  let providerStatus = null;
  const duration = ()=>decodeStartedAt === undefined ? null : Math.min(120_000, Math.max(0, Math.ceil(performance.now() - decodeStartedAt)));
  const rpc = async (name, params)=>{
    const { data, error } = await serviceClient().rpc(name, params).abortSignal(AbortSignal.timeout(5_000));
    if (error) throw integrityAdmissionError(error);
    return data;
  };
  try {
    const authorization = req.headers.get("authorization");
    const { user } = await requireUser(authorization);
    const caller = rosterSession(authorization, user.id);
    const payload = await boundedJson(req, 32768);
    const action = payload.action;
    if (action !== "group.create" && action !== "sms.ingest" || payload.subject_id !== user.id || payload.sms_permission_granted !== true || payload.sms_access_enabled !== true) {
      return jsonResponse({
        error: "Invalid Play Integrity request"
      }, 400);
    }
    const requestHash = cleanString(payload.request_hash, "request_hash", 64).toLowerCase();
    const token = cleanString(payload.integrity_token, "integrity_token", 20_000);
    const nonce = cleanString(payload.nonce, "nonce", 36);
    const receiverHash = cleanString(payload.receiver_momo_number_hash, "receiver_momo_number_hash", 64).toLowerCase();
    if (!/^[0-9a-f]{64}$/.test(requestHash) || !/^[0-9a-f]{64}$/.test(receiverHash) || !uuidPattern.test(nonce)) {
      return jsonResponse({
        error: "Invalid Play Integrity binding"
      }, 400);
    }
    let expectedHash;
    let capabilityPayload;
    if (action === "group.create") {
      const untrusted = payload.group_request;
      if (typeof untrusted !== "object" || untrusted == null || Array.isArray(untrusted)) {
        return jsonResponse({
          error: "Group request is required"
        }, 400);
      }
      const group = untrusted;
      if (group.group_is_public !== false || group.receiver_momo_number_hash !== receiverHash) {
        return jsonResponse({
          error: "Only private Android groups are allowed"
        }, 400);
      }
      capabilityPayload = {
        group_name: cleanString(group.group_name, "group_name", 120),
        group_description: typeof group.group_description === "string" ? group.group_description.trim().slice(0, 2_000) : "",
        receiver_momo_number: cleanString(group.receiver_momo_number, "receiver_momo_number", 40),
        receiver_momo_number_hash: receiverHash,
        receiver_label: cleanString(group.receiver_label, "receiver_label", 80),
        group_collection_type: cleanString(group.group_collection_type, "group_collection_type", 64),
        group_category_subtype: typeof group.group_category_subtype === "string" ? group.group_category_subtype.trim() || null : null,
        group_purpose_label: typeof group.group_purpose_label === "string" ? group.group_purpose_label.trim() || null : null,
        group_is_public: false
      };
      expectedHash = await sha256Hex(JSON.stringify({
        action,
        subject_id: user.id,
        nonce,
        receiver_momo_number_hash: receiverHash,
        sms_permission_granted: true,
        sms_access_enabled: true,
        group_request: capabilityPayload
      }));
    } else {
      const untrusted = payload.sms_request;
      if (typeof untrusted !== "object" || untrusted == null || Array.isArray(untrusted)) {
        return jsonResponse({
          error: "SMS request is required"
        }, 400);
      }
      const sms = untrusted;
      const clientEnvelopeId = cleanString(sms.client_envelope_id, "client_envelope_id", 36);
      const rawBodySha256 = cleanString(sms.raw_body_sha256, "raw_body_sha256", 64).toLowerCase();
      const receivedAtDevice = sms.received_at_device == null ? null : cleanString(sms.received_at_device, "received_at_device", 64);
      if (!uuidPattern.test(clientEnvelopeId) || !/^[0-9a-f]{64}$/.test(rawBodySha256) || receivedAtDevice != null && Number.isNaN(Date.parse(receivedAtDevice))) {
        return jsonResponse({
          error: "Invalid SMS integrity binding"
        }, 400);
      }
      const smsInput = {
        subjectId: user.id,
        nonce,
        receiverMomoNumberHash: receiverHash,
        clientEnvelopeId,
        rawSender: cleanString(sms.raw_sender, "raw_sender", 96),
        rawBodySha256,
        receivedAtDevice
      };
      expectedHash = await smsIntegrityRequestHash(smsInput);
      capabilityPayload = smsCapabilityPayload(smsInput);
    }
    if (expectedHash !== requestHash) {
      return jsonResponse({
        error: "Request binding mismatch"
      }, 400);
    }
    const minimumVersion = Number(requireEnv("PLAY_INTEGRITY_MIN_VERSION_CODE"));
    const certificates = new Set(requireEnv("PLAY_INTEGRITY_CERTIFICATE_SHA256").split(",").map((v)=>v.trim()).filter(Boolean));
    if (!Number.isSafeInteger(minimumVersion) || minimumVersion < 1 || !certificates.size) throw new PublicError("integrity_policy_unconfigured", 503);
    // Fail before reservations/Google if no account is configured. Key import
    // and signing remain inside the admitted OAuth phase.
    const accountRaw = Deno.env.get("PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON")?.trim() || requireEnv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
    let account;
    try {
      account = JSON.parse(accountRaw);
    } catch  {
      throw new PublicError("integrity_policy_unconfigured", 503);
    }
    if (!account || typeof account.client_email !== "string" || typeof account.private_key !== "string") throw new PublicError("integrity_policy_unconfigured", 503);
    binding = {
      actorId: caller.actorId,
      sessionId: caller.sessionId,
      nonce: nonce.toLowerCase(),
      action,
      requestHash,
      tokenHash: await sha256Hex(token)
    };
    const actorParams = {
      p_actor_id: caller.actorId,
      p_session_id: caller.sessionId
    };
    const reserved = await rpc("reserve_play_integrity_admission_v1", {
      ...actorParams,
      p_nonce: binding.nonce,
      p_action: action,
      p_request_hash: requestHash,
      p_token_sha256: binding.tokenHash,
      p_receiver_hash: receiverHash,
      p_request_payload: capabilityPayload
    });
    if (typeof reserved === "object" && reserved !== null && reserved.state === "completed") {
      const receipt = integrityAdmissionReceipt(reserved, binding, "completed");
      return jsonResponse(integrityResult(receipt.result, binding));
    }
    reservationId = integrityAdmissionReceipt(reserved, binding, "reserved").reservationId;
    const admissionParams = {
      ...actorParams,
      p_reservation_id: reservationId
    };
    integrityAdmissionReceipt(await rpc("begin_play_integrity_admission_v1", {
      ...admissionParams,
      p_phase: "oauth"
    }), binding, "oauth_started");
    const access = await accessToken();
    // Revocation/expiry between OAuth and decode denies the second expensive
    // transport. Each phase is single-use and durable across handler restarts.
    integrityAdmissionReceipt(await rpc("begin_play_integrity_admission_v1", {
      ...admissionParams,
      p_phase: "decode"
    }), binding, "decode_started");
    decodeStartedAt = performance.now();
    const transport = await decodeIntegrityToken(token, access);
    const decoded = transport.decoded;
    providerStatus = transport.providerStatus;
    const policy = validateIntegrityVerdict(decoded, requestHash, {
      packageName,
      minimumVersion,
      certificates,
      nowMs: Date.now()
    });
    const verdictPackage = policy.packageName, appVerdict = policy.appVerdict;
    const deviceVerdicts = policy.deviceVerdicts, timestampMillis = policy.timestampMillis;
    const result = await rpc("complete_play_integrity_admission_v1", {
      ...admissionParams,
      p_request_payload: capabilityPayload,
      p_package_name: verdictPackage,
      p_app_verdict: appVerdict,
      p_device_verdicts: deviceVerdicts,
      p_verified_at: new Date(timestampMillis).toISOString(),
      p_decode_duration_ms: duration(),
      p_provider_status: providerStatus
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
          p_outcome: error instanceof PublicError && error.code === "integrity_policy_rejected" ? "rejected" : "ambiguous",
          p_decode_duration_ms: duration(),
          p_provider_status: error instanceof GoogleTransportError ? error.providerStatus : providerStatus
        });
      } catch  {}
    }
    const message = error instanceof Error ? error.message : "Play Integrity failed";
    if (error instanceof PublicError) {
      return jsonResponse({
        error: error.code === "integrity_policy_unconfigured" ? "play_integrity_unavailable" : error.code
      }, error.status);
    }
    if (message === "Authentication required") {
      return jsonResponse({
        error: "authentication_required"
      }, 401);
    }
    if (/required env var/i.test(message)) {
      return jsonResponse({
        error: "play_integrity_unavailable"
      }, 503);
    }
    return jsonResponse({
      error: "Play Integrity verification failed"
    }, 502);
  }
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL3ZlcmlmeS1wbGF5LWludGVncml0eS9pbmRleC50cyJdLCJzb3VyY2VzQ29udGVudCI6WyJpbXBvcnQge1xuICBib3VuZGVkSnNvbixcbiAgZmV0Y2hKc29uLFxuICBvYmplY3RWYWx1ZSxcbiAgUHVibGljRXJyb3IsXG59IGZyb20gXCIuLi9fc2hhcmVkL3Byb2R1Y3Rpb25fY29udHJhY3QudHNcIjtcbmltcG9ydCB7IHZhbGlkYXRlSW50ZWdyaXR5VmVyZGljdCB9IGZyb20gXCIuLi9fc2hhcmVkL2ludGVncml0eV9wb2xpY3kudHNcIjtcbmltcG9ydCB7IGNvcnNIZWFkZXJzLCBqc29uUmVzcG9uc2UsIHJlcXVpcmVFbnYgfSBmcm9tIFwiLi4vX3NoYXJlZC9jb3JzLnRzXCI7XG5pbXBvcnQgeyByZXF1aXJlVXNlciwgc2VydmljZUNsaWVudCB9IGZyb20gXCIuLi9fc2hhcmVkL3N1cGFiYXNlLnRzXCI7XG5pbXBvcnQgeyByb3N0ZXJTZXNzaW9uIH0gZnJvbSBcIi4uL19zaGFyZWQvcm9zdGVyX3Byb3ZlbmFuY2UudHNcIjtcbmltcG9ydCB7XG4gIGludGVncml0eUFkbWlzc2lvbkVycm9yLFxuICBpbnRlZ3JpdHlBZG1pc3Npb25SZWNlaXB0LFxuICB0eXBlIEludGVncml0eUJpbmRpbmcsXG4gIGludGVncml0eVJlc3VsdCxcbn0gZnJvbSBcIi4uL19zaGFyZWQvaW50ZWdyaXR5X2FkbWlzc2lvbi50c1wiO1xuaW1wb3J0IHtcbiAgc2hhMjU2SGV4LFxuICBzbXNDYXBhYmlsaXR5UGF5bG9hZCxcbiAgdHlwZSBTbXNJbnRlZ3JpdHlSZXF1ZXN0LFxuICBzbXNJbnRlZ3JpdHlSZXF1ZXN0SGFzaCxcbn0gZnJvbSBcIi4uL19zaGFyZWQvcGxheV9pbnRlZ3JpdHlfYmluZGluZy50c1wiO1xuXG50eXBlIFNlcnZpY2VBY2NvdW50ID0ge1xuICBjbGllbnRfZW1haWw6IHN0cmluZztcbiAgcHJpdmF0ZV9rZXk6IHN0cmluZztcbiAgdG9rZW5fdXJpPzogc3RyaW5nO1xufTtcblxuY29uc3QgcGFja2FnZU5hbWUgPSBcImFwcC5jb29sLm1vYmlsZVwiO1xuY29uc3QgdG9rZW5VcmkgPSBcImh0dHBzOi8vb2F1dGgyLmdvb2dsZWFwaXMuY29tL3Rva2VuXCI7XG5jb25zdCBwbGF5U2NvcGUgPSBcImh0dHBzOi8vd3d3Lmdvb2dsZWFwaXMuY29tL2F1dGgvcGxheWludGVncml0eVwiO1xuY2xhc3MgR29vZ2xlVHJhbnNwb3J0RXJyb3IgZXh0ZW5kcyBQdWJsaWNFcnJvciB7XG4gIGNvbnN0cnVjdG9yKHJlYWRvbmx5IHByb3ZpZGVyU3RhdHVzOiBudW1iZXIpIHtcbiAgICBzdXBlcihcInBsYXlfaW50ZWdyaXR5X3VuYXZhaWxhYmxlXCIsIDUwMyk7XG4gIH1cbn1cbmNvbnN0IHV1aWRQYXR0ZXJuID1cbiAgL15bMC05YS1mXXs4fS1bMC05YS1mXXs0fS1bMS01XVswLTlhLWZdezN9LVs4OWFiXVswLTlhLWZdezN9LVswLTlhLWZdezEyfSQvaTtcblxuZnVuY3Rpb24gYmFzZTY0VXJsKGlucHV0OiBBcnJheUJ1ZmZlciB8IHN0cmluZyk6IHN0cmluZyB7XG4gIGNvbnN0IGJ5dGVzID0gdHlwZW9mIGlucHV0ID09PSBcInN0cmluZ1wiXG4gICAgPyBuZXcgVGV4dEVuY29kZXIoKS5lbmNvZGUoaW5wdXQpXG4gICAgOiBuZXcgVWludDhBcnJheShpbnB1dCk7XG4gIGxldCBiaW5hcnkgPSBcIlwiO1xuICBmb3IgKGNvbnN0IGJ5dGUgb2YgYnl0ZXMpIGJpbmFyeSArPSBTdHJpbmcuZnJvbUNoYXJDb2RlKGJ5dGUpO1xuICByZXR1cm4gYnRvYShiaW5hcnkpLnJlcGxhY2VBbGwoXCIrXCIsIFwiLVwiKS5yZXBsYWNlQWxsKFwiL1wiLCBcIl9cIikucmVwbGFjZUFsbChcbiAgICBcIj1cIixcbiAgICBcIlwiLFxuICApO1xufVxuXG5mdW5jdGlvbiBwZW1CdWZmZXIocGVtOiBzdHJpbmcpOiBBcnJheUJ1ZmZlciB7XG4gIGNvbnN0IGNsZWFuID0gcGVtLnJlcGxhY2UoLy0tLS0tQkVHSU4gW14tXSstLS0tLS9nLCBcIlwiKVxuICAgIC5yZXBsYWNlKC8tLS0tLUVORCBbXi1dKy0tLS0tL2csIFwiXCIpLnJlcGxhY2UoL1xccysvZywgXCJcIik7XG4gIGNvbnN0IGJpbmFyeSA9IGF0b2IoY2xlYW4pO1xuICBjb25zdCBieXRlcyA9IG5ldyBVaW50OEFycmF5KGJpbmFyeS5sZW5ndGgpO1xuICBmb3IgKGxldCBpbmRleCA9IDA7IGluZGV4IDwgYmluYXJ5Lmxlbmd0aDsgaW5kZXgrKykge1xuICAgIGJ5dGVzW2luZGV4XSA9IGJpbmFyeS5jaGFyQ29kZUF0KGluZGV4KTtcbiAgfVxuICByZXR1cm4gYnl0ZXMuYnVmZmVyO1xufVxuXG5hc3luYyBmdW5jdGlvbiBhY2Nlc3NUb2tlbigpOiBQcm9taXNlPHN0cmluZz4ge1xuICBjb25zdCByYXcgPSBEZW5vLmVudi5nZXQoXCJQTEFZX0lOVEVHUklUWV9TRVJWSUNFX0FDQ09VTlRfSlNPTlwiKT8udHJpbSgpIHx8XG4gICAgcmVxdWlyZUVudihcIkdPT0dMRV9QTEFZX1NFUlZJQ0VfQUNDT1VOVF9KU09OXCIpO1xuICBjb25zdCBhY2NvdW50ID0gSlNPTi5wYXJzZShyYXcpIGFzIFNlcnZpY2VBY2NvdW50O1xuICBjb25zdCBub3cgPSBNYXRoLmZsb29yKERhdGUubm93KCkgLyAxXzAwMCk7XG4gIGNvbnN0IGhlYWRlciA9IGJhc2U2NFVybChKU09OLnN0cmluZ2lmeSh7IGFsZzogXCJSUzI1NlwiLCB0eXA6IFwiSldUXCIgfSkpO1xuICBjb25zdCBjbGFpbSA9IGJhc2U2NFVybChKU09OLnN0cmluZ2lmeSh7XG4gICAgaXNzOiBhY2NvdW50LmNsaWVudF9lbWFpbCxcbiAgICBzY29wZTogcGxheVNjb3BlLFxuICAgIGF1ZDogdG9rZW5VcmksXG4gICAgZXhwOiBub3cgKyAzXzYwMCxcbiAgICBpYXQ6IG5vdyxcbiAgfSkpO1xuICBjb25zdCBrZXkgPSBhd2FpdCBjcnlwdG8uc3VidGxlLmltcG9ydEtleShcbiAgICBcInBrY3M4XCIsXG4gICAgcGVtQnVmZmVyKGFjY291bnQucHJpdmF0ZV9rZXkpLFxuICAgIHsgbmFtZTogXCJSU0FTU0EtUEtDUzEtdjFfNVwiLCBoYXNoOiBcIlNIQS0yNTZcIiB9LFxuICAgIGZhbHNlLFxuICAgIFtcInNpZ25cIl0sXG4gICk7XG4gIGNvbnN0IHNpZ25hdHVyZSA9IGF3YWl0IGNyeXB0by5zdWJ0bGUuc2lnbihcbiAgICBcIlJTQVNTQS1QS0NTMS12MV81XCIsXG4gICAga2V5LFxuICAgIG5ldyBUZXh0RW5jb2RlcigpLmVuY29kZShgJHtoZWFkZXJ9LiR7Y2xhaW19YCksXG4gICk7XG4gIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgZmV0Y2hKc29uKHRva2VuVXJpLCB7XG4gICAgbWV0aG9kOiBcIlBPU1RcIixcbiAgICBoZWFkZXJzOiB7IFwiQ29udGVudC1UeXBlXCI6IFwiYXBwbGljYXRpb24veC13d3ctZm9ybS11cmxlbmNvZGVkXCIgfSxcbiAgICBib2R5OiBuZXcgVVJMU2VhcmNoUGFyYW1zKHtcbiAgICAgIGdyYW50X3R5cGU6IFwidXJuOmlldGY6cGFyYW1zOm9hdXRoOmdyYW50LXR5cGU6and0LWJlYXJlclwiLFxuICAgICAgYXNzZXJ0aW9uOiBgJHtoZWFkZXJ9LiR7Y2xhaW19LiR7YmFzZTY0VXJsKHNpZ25hdHVyZSl9YCxcbiAgICB9KSxcbiAgfSk7XG4gIGNvbnN0IHJlc3VsdCA9IG9iamVjdFZhbHVlKHJlc3BvbnNlLmRhdGEpO1xuICBpZiAoIXJlc3BvbnNlLm9rIHx8IHR5cGVvZiByZXN1bHQuYWNjZXNzX3Rva2VuICE9PSBcInN0cmluZ1wiKSB7XG4gICAgdGhyb3cgbmV3IEdvb2dsZVRyYW5zcG9ydEVycm9yKHJlc3BvbnNlLnN0YXR1cyk7XG4gIH1cbiAgcmV0dXJuIHJlc3VsdC5hY2Nlc3NfdG9rZW47XG59XG5cbmFzeW5jIGZ1bmN0aW9uIGRlY29kZUludGVncml0eVRva2VuKHRva2VuOiBzdHJpbmcsIGFjY2Vzczogc3RyaW5nKSB7XG4gIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgZmV0Y2hKc29uKFxuICAgIGBodHRwczovL3BsYXlpbnRlZ3JpdHkuZ29vZ2xlYXBpcy5jb20vdjEvJHtwYWNrYWdlTmFtZX06ZGVjb2RlSW50ZWdyaXR5VG9rZW5gLFxuICAgIHtcbiAgICAgIG1ldGhvZDogXCJQT1NUXCIsXG4gICAgICBoZWFkZXJzOiB7XG4gICAgICAgIEF1dGhvcml6YXRpb246IGBCZWFyZXIgJHthY2Nlc3N9YCxcbiAgICAgICAgXCJDb250ZW50LVR5cGVcIjogXCJhcHBsaWNhdGlvbi9qc29uXCIsXG4gICAgICB9LFxuICAgICAgYm9keTogSlNPTi5zdHJpbmdpZnkoeyBpbnRlZ3JpdHlUb2tlbjogdG9rZW4gfSksXG4gICAgfSxcbiAgKTtcbiAgY29uc3QgcmVzdWx0ID0gb2JqZWN0VmFsdWUocmVzcG9uc2UuZGF0YSk7XG4gIGlmICghcmVzcG9uc2Uub2spIHRocm93IG5ldyBHb29nbGVUcmFuc3BvcnRFcnJvcihyZXNwb25zZS5zdGF0dXMpO1xuICByZXR1cm4ge1xuICAgIGRlY29kZWQ6IHJlc3VsdC50b2tlblBheWxvYWRFeHRlcm5hbCBhcyBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPixcbiAgICBwcm92aWRlclN0YXR1czogcmVzcG9uc2Uuc3RhdHVzLFxuICB9O1xufVxuXG5mdW5jdGlvbiBjbGVhblN0cmluZyh2YWx1ZTogdW5rbm93biwgX2ZpZWxkOiBzdHJpbmcsIG1heDogbnVtYmVyKTogc3RyaW5nIHtcbiAgaWYgKHR5cGVvZiB2YWx1ZSAhPT0gXCJzdHJpbmdcIikge1xuICAgIHRocm93IG5ldyBQdWJsaWNFcnJvcihcImludmFsaWRfaW50ZWdyaXR5X3JlcXVlc3RcIiwgNDAwKTtcbiAgfVxuICBjb25zdCBjbGVhbiA9IHZhbHVlLnRyaW0oKTtcbiAgaWYgKCFjbGVhbiB8fCBjbGVhbi5sZW5ndGggPiBtYXgpIHtcbiAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJpbnZhbGlkX2ludGVncml0eV9yZXF1ZXN0XCIsIDQwMCk7XG4gIH1cbiAgcmV0dXJuIGNsZWFuO1xufVxuXG5EZW5vLnNlcnZlKGFzeW5jIChyZXEpID0+IHtcbiAgaWYgKHJlcS5tZXRob2QgPT09IFwiT1BUSU9OU1wiKSB7XG4gICAgcmV0dXJuIG5ldyBSZXNwb25zZShcIm9rXCIsIHsgaGVhZGVyczogY29yc0hlYWRlcnMgfSk7XG4gIH1cbiAgaWYgKHJlcS5tZXRob2QgIT09IFwiUE9TVFwiKSB7XG4gICAgcmV0dXJuIGpzb25SZXNwb25zZSh7IGVycm9yOiBcIk1ldGhvZCBub3QgYWxsb3dlZFwiIH0sIDQwNSk7XG4gIH1cbiAgbGV0IHJlc2VydmF0aW9uSWQ6IHN0cmluZyB8IHVuZGVmaW5lZDtcbiAgbGV0IGJpbmRpbmc6IEludGVncml0eUJpbmRpbmcgfCB1bmRlZmluZWQ7XG4gIGxldCBkZWNvZGVTdGFydGVkQXQ6IG51bWJlciB8IHVuZGVmaW5lZDtcbiAgbGV0IHByb3ZpZGVyU3RhdHVzOiBudW1iZXIgfCBudWxsID0gbnVsbDtcbiAgY29uc3QgZHVyYXRpb24gPSAoKSA9PlxuICAgIGRlY29kZVN0YXJ0ZWRBdCA9PT0gdW5kZWZpbmVkID8gbnVsbCA6IE1hdGgubWluKFxuICAgICAgMTIwXzAwMCxcbiAgICAgIE1hdGgubWF4KDAsIE1hdGguY2VpbChwZXJmb3JtYW5jZS5ub3coKSAtIGRlY29kZVN0YXJ0ZWRBdCkpLFxuICAgICk7XG4gIGNvbnN0IHJwYyA9IGFzeW5jIChuYW1lOiBzdHJpbmcsIHBhcmFtczogUmVjb3JkPHN0cmluZywgdW5rbm93bj4pID0+IHtcbiAgICBjb25zdCB7IGRhdGEsIGVycm9yIH0gPSBhd2FpdCBzZXJ2aWNlQ2xpZW50KCkucnBjKG5hbWUsIHBhcmFtcykuYWJvcnRTaWduYWwoXG4gICAgICBBYm9ydFNpZ25hbC50aW1lb3V0KDVfMDAwKSxcbiAgICApO1xuICAgIGlmIChlcnJvcikgdGhyb3cgaW50ZWdyaXR5QWRtaXNzaW9uRXJyb3IoZXJyb3IpO1xuICAgIHJldHVybiBkYXRhO1xuICB9O1xuICB0cnkge1xuICAgIGNvbnN0IGF1dGhvcml6YXRpb24gPSByZXEuaGVhZGVycy5nZXQoXCJhdXRob3JpemF0aW9uXCIpO1xuICAgIGNvbnN0IHsgdXNlciB9ID0gYXdhaXQgcmVxdWlyZVVzZXIoYXV0aG9yaXphdGlvbik7XG4gICAgY29uc3QgY2FsbGVyID0gcm9zdGVyU2Vzc2lvbihhdXRob3JpemF0aW9uLCB1c2VyLmlkKTtcbiAgICBjb25zdCBwYXlsb2FkID0gYXdhaXQgYm91bmRlZEpzb24ocmVxLCAzMjc2OCk7XG4gICAgY29uc3QgYWN0aW9uID0gcGF5bG9hZC5hY3Rpb247XG4gICAgaWYgKFxuICAgICAgKGFjdGlvbiAhPT0gXCJncm91cC5jcmVhdGVcIiAmJiBhY3Rpb24gIT09IFwic21zLmluZ2VzdFwiKSB8fFxuICAgICAgcGF5bG9hZC5zdWJqZWN0X2lkICE9PSB1c2VyLmlkIHx8XG4gICAgICBwYXlsb2FkLnNtc19wZXJtaXNzaW9uX2dyYW50ZWQgIT09IHRydWUgfHxcbiAgICAgIHBheWxvYWQuc21zX2FjY2Vzc19lbmFibGVkICE9PSB0cnVlXG4gICAgKSB7XG4gICAgICByZXR1cm4ganNvblJlc3BvbnNlKHsgZXJyb3I6IFwiSW52YWxpZCBQbGF5IEludGVncml0eSByZXF1ZXN0XCIgfSwgNDAwKTtcbiAgICB9XG4gICAgY29uc3QgcmVxdWVzdEhhc2ggPSBjbGVhblN0cmluZyhwYXlsb2FkLnJlcXVlc3RfaGFzaCwgXCJyZXF1ZXN0X2hhc2hcIiwgNjQpXG4gICAgICAudG9Mb3dlckNhc2UoKTtcbiAgICBjb25zdCB0b2tlbiA9IGNsZWFuU3RyaW5nKFxuICAgICAgcGF5bG9hZC5pbnRlZ3JpdHlfdG9rZW4sXG4gICAgICBcImludGVncml0eV90b2tlblwiLFxuICAgICAgMjBfMDAwLFxuICAgICk7XG4gICAgY29uc3Qgbm9uY2UgPSBjbGVhblN0cmluZyhwYXlsb2FkLm5vbmNlLCBcIm5vbmNlXCIsIDM2KTtcbiAgICBjb25zdCByZWNlaXZlckhhc2ggPSBjbGVhblN0cmluZyhcbiAgICAgIHBheWxvYWQucmVjZWl2ZXJfbW9tb19udW1iZXJfaGFzaCxcbiAgICAgIFwicmVjZWl2ZXJfbW9tb19udW1iZXJfaGFzaFwiLFxuICAgICAgNjQsXG4gICAgKS50b0xvd2VyQ2FzZSgpO1xuICAgIGlmIChcbiAgICAgICEvXlswLTlhLWZdezY0fSQvLnRlc3QocmVxdWVzdEhhc2gpIHx8XG4gICAgICAhL15bMC05YS1mXXs2NH0kLy50ZXN0KHJlY2VpdmVySGFzaCkgfHxcbiAgICAgICF1dWlkUGF0dGVybi50ZXN0KG5vbmNlKVxuICAgICkge1xuICAgICAgcmV0dXJuIGpzb25SZXNwb25zZSh7IGVycm9yOiBcIkludmFsaWQgUGxheSBJbnRlZ3JpdHkgYmluZGluZ1wiIH0sIDQwMCk7XG4gICAgfVxuICAgIGxldCBleHBlY3RlZEhhc2g6IHN0cmluZztcbiAgICBsZXQgY2FwYWJpbGl0eVBheWxvYWQ6IFJlY29yZDxzdHJpbmcsIHVua25vd24+O1xuICAgIGlmIChhY3Rpb24gPT09IFwiZ3JvdXAuY3JlYXRlXCIpIHtcbiAgICAgIGNvbnN0IHVudHJ1c3RlZCA9IHBheWxvYWQuZ3JvdXBfcmVxdWVzdDtcbiAgICAgIGlmIChcbiAgICAgICAgdHlwZW9mIHVudHJ1c3RlZCAhPT0gXCJvYmplY3RcIiB8fCB1bnRydXN0ZWQgPT0gbnVsbCB8fFxuICAgICAgICBBcnJheS5pc0FycmF5KHVudHJ1c3RlZClcbiAgICAgICkge1xuICAgICAgICByZXR1cm4ganNvblJlc3BvbnNlKHsgZXJyb3I6IFwiR3JvdXAgcmVxdWVzdCBpcyByZXF1aXJlZFwiIH0sIDQwMCk7XG4gICAgICB9XG4gICAgICBjb25zdCBncm91cCA9IHVudHJ1c3RlZCBhcyBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPjtcbiAgICAgIGlmIChcbiAgICAgICAgZ3JvdXAuZ3JvdXBfaXNfcHVibGljICE9PSBmYWxzZSB8fFxuICAgICAgICBncm91cC5yZWNlaXZlcl9tb21vX251bWJlcl9oYXNoICE9PSByZWNlaXZlckhhc2hcbiAgICAgICkge1xuICAgICAgICByZXR1cm4ganNvblJlc3BvbnNlKHtcbiAgICAgICAgICBlcnJvcjogXCJPbmx5IHByaXZhdGUgQW5kcm9pZCBncm91cHMgYXJlIGFsbG93ZWRcIixcbiAgICAgICAgfSwgNDAwKTtcbiAgICAgIH1cbiAgICAgIGNhcGFiaWxpdHlQYXlsb2FkID0ge1xuICAgICAgICBncm91cF9uYW1lOiBjbGVhblN0cmluZyhncm91cC5ncm91cF9uYW1lLCBcImdyb3VwX25hbWVcIiwgMTIwKSxcbiAgICAgICAgZ3JvdXBfZGVzY3JpcHRpb246IHR5cGVvZiBncm91cC5ncm91cF9kZXNjcmlwdGlvbiA9PT0gXCJzdHJpbmdcIlxuICAgICAgICAgID8gZ3JvdXAuZ3JvdXBfZGVzY3JpcHRpb24udHJpbSgpLnNsaWNlKDAsIDJfMDAwKVxuICAgICAgICAgIDogXCJcIixcbiAgICAgICAgcmVjZWl2ZXJfbW9tb19udW1iZXI6IGNsZWFuU3RyaW5nKFxuICAgICAgICAgIGdyb3VwLnJlY2VpdmVyX21vbW9fbnVtYmVyLFxuICAgICAgICAgIFwicmVjZWl2ZXJfbW9tb19udW1iZXJcIixcbiAgICAgICAgICA0MCxcbiAgICAgICAgKSxcbiAgICAgICAgcmVjZWl2ZXJfbW9tb19udW1iZXJfaGFzaDogcmVjZWl2ZXJIYXNoLFxuICAgICAgICByZWNlaXZlcl9sYWJlbDogY2xlYW5TdHJpbmcoZ3JvdXAucmVjZWl2ZXJfbGFiZWwsIFwicmVjZWl2ZXJfbGFiZWxcIiwgODApLFxuICAgICAgICBncm91cF9jb2xsZWN0aW9uX3R5cGU6IGNsZWFuU3RyaW5nKFxuICAgICAgICAgIGdyb3VwLmdyb3VwX2NvbGxlY3Rpb25fdHlwZSxcbiAgICAgICAgICBcImdyb3VwX2NvbGxlY3Rpb25fdHlwZVwiLFxuICAgICAgICAgIDY0LFxuICAgICAgICApLFxuICAgICAgICBncm91cF9jYXRlZ29yeV9zdWJ0eXBlOiB0eXBlb2YgZ3JvdXAuZ3JvdXBfY2F0ZWdvcnlfc3VidHlwZSA9PT0gXCJzdHJpbmdcIlxuICAgICAgICAgID8gZ3JvdXAuZ3JvdXBfY2F0ZWdvcnlfc3VidHlwZS50cmltKCkgfHwgbnVsbFxuICAgICAgICAgIDogbnVsbCxcbiAgICAgICAgZ3JvdXBfcHVycG9zZV9sYWJlbDogdHlwZW9mIGdyb3VwLmdyb3VwX3B1cnBvc2VfbGFiZWwgPT09IFwic3RyaW5nXCJcbiAgICAgICAgICA/IGdyb3VwLmdyb3VwX3B1cnBvc2VfbGFiZWwudHJpbSgpIHx8IG51bGxcbiAgICAgICAgICA6IG51bGwsXG4gICAgICAgIGdyb3VwX2lzX3B1YmxpYzogZmFsc2UsXG4gICAgICB9O1xuICAgICAgZXhwZWN0ZWRIYXNoID0gYXdhaXQgc2hhMjU2SGV4KEpTT04uc3RyaW5naWZ5KHtcbiAgICAgICAgYWN0aW9uLFxuICAgICAgICBzdWJqZWN0X2lkOiB1c2VyLmlkLFxuICAgICAgICBub25jZSxcbiAgICAgICAgcmVjZWl2ZXJfbW9tb19udW1iZXJfaGFzaDogcmVjZWl2ZXJIYXNoLFxuICAgICAgICBzbXNfcGVybWlzc2lvbl9ncmFudGVkOiB0cnVlLFxuICAgICAgICBzbXNfYWNjZXNzX2VuYWJsZWQ6IHRydWUsXG4gICAgICAgIGdyb3VwX3JlcXVlc3Q6IGNhcGFiaWxpdHlQYXlsb2FkLFxuICAgICAgfSkpO1xuICAgIH0gZWxzZSB7XG4gICAgICBjb25zdCB1bnRydXN0ZWQgPSBwYXlsb2FkLnNtc19yZXF1ZXN0O1xuICAgICAgaWYgKFxuICAgICAgICB0eXBlb2YgdW50cnVzdGVkICE9PSBcIm9iamVjdFwiIHx8IHVudHJ1c3RlZCA9PSBudWxsIHx8XG4gICAgICAgIEFycmF5LmlzQXJyYXkodW50cnVzdGVkKVxuICAgICAgKSB7XG4gICAgICAgIHJldHVybiBqc29uUmVzcG9uc2UoeyBlcnJvcjogXCJTTVMgcmVxdWVzdCBpcyByZXF1aXJlZFwiIH0sIDQwMCk7XG4gICAgICB9XG4gICAgICBjb25zdCBzbXMgPSB1bnRydXN0ZWQgYXMgUmVjb3JkPHN0cmluZywgdW5rbm93bj47XG4gICAgICBjb25zdCBjbGllbnRFbnZlbG9wZUlkID0gY2xlYW5TdHJpbmcoXG4gICAgICAgIHNtcy5jbGllbnRfZW52ZWxvcGVfaWQsXG4gICAgICAgIFwiY2xpZW50X2VudmVsb3BlX2lkXCIsXG4gICAgICAgIDM2LFxuICAgICAgKTtcbiAgICAgIGNvbnN0IHJhd0JvZHlTaGEyNTYgPSBjbGVhblN0cmluZyhcbiAgICAgICAgc21zLnJhd19ib2R5X3NoYTI1NixcbiAgICAgICAgXCJyYXdfYm9keV9zaGEyNTZcIixcbiAgICAgICAgNjQsXG4gICAgICApLnRvTG93ZXJDYXNlKCk7XG4gICAgICBjb25zdCByZWNlaXZlZEF0RGV2aWNlID0gc21zLnJlY2VpdmVkX2F0X2RldmljZSA9PSBudWxsXG4gICAgICAgID8gbnVsbFxuICAgICAgICA6IGNsZWFuU3RyaW5nKHNtcy5yZWNlaXZlZF9hdF9kZXZpY2UsIFwicmVjZWl2ZWRfYXRfZGV2aWNlXCIsIDY0KTtcbiAgICAgIGlmIChcbiAgICAgICAgIXV1aWRQYXR0ZXJuLnRlc3QoY2xpZW50RW52ZWxvcGVJZCkgfHxcbiAgICAgICAgIS9eWzAtOWEtZl17NjR9JC8udGVzdChyYXdCb2R5U2hhMjU2KSB8fFxuICAgICAgICAocmVjZWl2ZWRBdERldmljZSAhPSBudWxsICYmIE51bWJlci5pc05hTihEYXRlLnBhcnNlKHJlY2VpdmVkQXREZXZpY2UpKSlcbiAgICAgICkge1xuICAgICAgICByZXR1cm4ganNvblJlc3BvbnNlKHsgZXJyb3I6IFwiSW52YWxpZCBTTVMgaW50ZWdyaXR5IGJpbmRpbmdcIiB9LCA0MDApO1xuICAgICAgfVxuICAgICAgY29uc3Qgc21zSW5wdXQ6IFNtc0ludGVncml0eVJlcXVlc3QgPSB7XG4gICAgICAgIHN1YmplY3RJZDogdXNlci5pZCxcbiAgICAgICAgbm9uY2UsXG4gICAgICAgIHJlY2VpdmVyTW9tb051bWJlckhhc2g6IHJlY2VpdmVySGFzaCxcbiAgICAgICAgY2xpZW50RW52ZWxvcGVJZCxcbiAgICAgICAgcmF3U2VuZGVyOiBjbGVhblN0cmluZyhzbXMucmF3X3NlbmRlciwgXCJyYXdfc2VuZGVyXCIsIDk2KSxcbiAgICAgICAgcmF3Qm9keVNoYTI1NixcbiAgICAgICAgcmVjZWl2ZWRBdERldmljZSxcbiAgICAgIH07XG4gICAgICBleHBlY3RlZEhhc2ggPSBhd2FpdCBzbXNJbnRlZ3JpdHlSZXF1ZXN0SGFzaChzbXNJbnB1dCk7XG4gICAgICBjYXBhYmlsaXR5UGF5bG9hZCA9IHNtc0NhcGFiaWxpdHlQYXlsb2FkKHNtc0lucHV0KTtcbiAgICB9XG4gICAgaWYgKGV4cGVjdGVkSGFzaCAhPT0gcmVxdWVzdEhhc2gpIHtcbiAgICAgIHJldHVybiBqc29uUmVzcG9uc2UoeyBlcnJvcjogXCJSZXF1ZXN0IGJpbmRpbmcgbWlzbWF0Y2hcIiB9LCA0MDApO1xuICAgIH1cblxuICAgIGNvbnN0IG1pbmltdW1WZXJzaW9uID0gTnVtYmVyKFxuICAgICAgcmVxdWlyZUVudihcIlBMQVlfSU5URUdSSVRZX01JTl9WRVJTSU9OX0NPREVcIiksXG4gICAgKTtcbiAgICBjb25zdCBjZXJ0aWZpY2F0ZXMgPSBuZXcgU2V0KFxuICAgICAgcmVxdWlyZUVudihcIlBMQVlfSU5URUdSSVRZX0NFUlRJRklDQVRFX1NIQTI1NlwiKS5zcGxpdChcIixcIikubWFwKCh2KSA9PlxuICAgICAgICB2LnRyaW0oKVxuICAgICAgKS5maWx0ZXIoQm9vbGVhbiksXG4gICAgKTtcbiAgICBpZiAoXG4gICAgICAhTnVtYmVyLmlzU2FmZUludGVnZXIobWluaW11bVZlcnNpb24pIHx8IG1pbmltdW1WZXJzaW9uIDwgMSB8fFxuICAgICAgIWNlcnRpZmljYXRlcy5zaXplXG4gICAgKSB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJpbnRlZ3JpdHlfcG9saWN5X3VuY29uZmlndXJlZFwiLCA1MDMpO1xuICAgIC8vIEZhaWwgYmVmb3JlIHJlc2VydmF0aW9ucy9Hb29nbGUgaWYgbm8gYWNjb3VudCBpcyBjb25maWd1cmVkLiBLZXkgaW1wb3J0XG4gICAgLy8gYW5kIHNpZ25pbmcgcmVtYWluIGluc2lkZSB0aGUgYWRtaXR0ZWQgT0F1dGggcGhhc2UuXG4gICAgY29uc3QgYWNjb3VudFJhdyA9XG4gICAgICBEZW5vLmVudi5nZXQoXCJQTEFZX0lOVEVHUklUWV9TRVJWSUNFX0FDQ09VTlRfSlNPTlwiKT8udHJpbSgpIHx8XG4gICAgICByZXF1aXJlRW52KFwiR09PR0xFX1BMQVlfU0VSVklDRV9BQ0NPVU5UX0pTT05cIik7XG4gICAgbGV0IGFjY291bnQ6IFNlcnZpY2VBY2NvdW50O1xuICAgIHRyeSB7XG4gICAgICBhY2NvdW50ID0gSlNPTi5wYXJzZShhY2NvdW50UmF3KSBhcyBTZXJ2aWNlQWNjb3VudDtcbiAgICB9IGNhdGNoIHtcbiAgICAgIHRocm93IG5ldyBQdWJsaWNFcnJvcihcImludGVncml0eV9wb2xpY3lfdW5jb25maWd1cmVkXCIsIDUwMyk7XG4gICAgfVxuICAgIGlmIChcbiAgICAgICFhY2NvdW50IHx8IHR5cGVvZiBhY2NvdW50LmNsaWVudF9lbWFpbCAhPT0gXCJzdHJpbmdcIiB8fFxuICAgICAgdHlwZW9mIGFjY291bnQucHJpdmF0ZV9rZXkgIT09IFwic3RyaW5nXCJcbiAgICApIHRocm93IG5ldyBQdWJsaWNFcnJvcihcImludGVncml0eV9wb2xpY3lfdW5jb25maWd1cmVkXCIsIDUwMyk7XG4gICAgYmluZGluZyA9IHtcbiAgICAgIGFjdG9ySWQ6IGNhbGxlci5hY3RvcklkLFxuICAgICAgc2Vzc2lvbklkOiBjYWxsZXIuc2Vzc2lvbklkLFxuICAgICAgbm9uY2U6IG5vbmNlLnRvTG93ZXJDYXNlKCksXG4gICAgICBhY3Rpb24sXG4gICAgICByZXF1ZXN0SGFzaCxcbiAgICAgIHRva2VuSGFzaDogYXdhaXQgc2hhMjU2SGV4KHRva2VuKSxcbiAgICB9O1xuICAgIGNvbnN0IGFjdG9yUGFyYW1zID0ge1xuICAgICAgcF9hY3Rvcl9pZDogY2FsbGVyLmFjdG9ySWQsXG4gICAgICBwX3Nlc3Npb25faWQ6IGNhbGxlci5zZXNzaW9uSWQsXG4gICAgfTtcbiAgICBjb25zdCByZXNlcnZlZCA9IGF3YWl0IHJwYyhcInJlc2VydmVfcGxheV9pbnRlZ3JpdHlfYWRtaXNzaW9uX3YxXCIsIHtcbiAgICAgIC4uLmFjdG9yUGFyYW1zLFxuICAgICAgcF9ub25jZTogYmluZGluZy5ub25jZSxcbiAgICAgIHBfYWN0aW9uOiBhY3Rpb24sXG4gICAgICBwX3JlcXVlc3RfaGFzaDogcmVxdWVzdEhhc2gsXG4gICAgICBwX3Rva2VuX3NoYTI1NjogYmluZGluZy50b2tlbkhhc2gsXG4gICAgICBwX3JlY2VpdmVyX2hhc2g6IHJlY2VpdmVySGFzaCxcbiAgICAgIHBfcmVxdWVzdF9wYXlsb2FkOiBjYXBhYmlsaXR5UGF5bG9hZCxcbiAgICB9KTtcbiAgICBpZiAoXG4gICAgICB0eXBlb2YgcmVzZXJ2ZWQgPT09IFwib2JqZWN0XCIgJiYgcmVzZXJ2ZWQgIT09IG51bGwgJiZcbiAgICAgIChyZXNlcnZlZCBhcyBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPikuc3RhdGUgPT09IFwiY29tcGxldGVkXCJcbiAgICApIHtcbiAgICAgIGNvbnN0IHJlY2VpcHQgPSBpbnRlZ3JpdHlBZG1pc3Npb25SZWNlaXB0KHJlc2VydmVkLCBiaW5kaW5nLCBcImNvbXBsZXRlZFwiKTtcbiAgICAgIHJldHVybiBqc29uUmVzcG9uc2UoaW50ZWdyaXR5UmVzdWx0KHJlY2VpcHQucmVzdWx0LCBiaW5kaW5nKSk7XG4gICAgfVxuICAgIHJlc2VydmF0aW9uSWQgPVxuICAgICAgaW50ZWdyaXR5QWRtaXNzaW9uUmVjZWlwdChyZXNlcnZlZCwgYmluZGluZywgXCJyZXNlcnZlZFwiKS5yZXNlcnZhdGlvbklkO1xuICAgIGNvbnN0IGFkbWlzc2lvblBhcmFtcyA9IHsgLi4uYWN0b3JQYXJhbXMsIHBfcmVzZXJ2YXRpb25faWQ6IHJlc2VydmF0aW9uSWQgfTtcbiAgICBpbnRlZ3JpdHlBZG1pc3Npb25SZWNlaXB0KFxuICAgICAgYXdhaXQgcnBjKFwiYmVnaW5fcGxheV9pbnRlZ3JpdHlfYWRtaXNzaW9uX3YxXCIsIHtcbiAgICAgICAgLi4uYWRtaXNzaW9uUGFyYW1zLFxuICAgICAgICBwX3BoYXNlOiBcIm9hdXRoXCIsXG4gICAgICB9KSxcbiAgICAgIGJpbmRpbmcsXG4gICAgICBcIm9hdXRoX3N0YXJ0ZWRcIixcbiAgICApO1xuICAgIGNvbnN0IGFjY2VzcyA9IGF3YWl0IGFjY2Vzc1Rva2VuKCk7XG4gICAgLy8gUmV2b2NhdGlvbi9leHBpcnkgYmV0d2VlbiBPQXV0aCBhbmQgZGVjb2RlIGRlbmllcyB0aGUgc2Vjb25kIGV4cGVuc2l2ZVxuICAgIC8vIHRyYW5zcG9ydC4gRWFjaCBwaGFzZSBpcyBzaW5nbGUtdXNlIGFuZCBkdXJhYmxlIGFjcm9zcyBoYW5kbGVyIHJlc3RhcnRzLlxuICAgIGludGVncml0eUFkbWlzc2lvblJlY2VpcHQoXG4gICAgICBhd2FpdCBycGMoXCJiZWdpbl9wbGF5X2ludGVncml0eV9hZG1pc3Npb25fdjFcIiwge1xuICAgICAgICAuLi5hZG1pc3Npb25QYXJhbXMsXG4gICAgICAgIHBfcGhhc2U6IFwiZGVjb2RlXCIsXG4gICAgICB9KSxcbiAgICAgIGJpbmRpbmcsXG4gICAgICBcImRlY29kZV9zdGFydGVkXCIsXG4gICAgKTtcbiAgICBkZWNvZGVTdGFydGVkQXQgPSBwZXJmb3JtYW5jZS5ub3coKTtcbiAgICBjb25zdCB0cmFuc3BvcnQgPSBhd2FpdCBkZWNvZGVJbnRlZ3JpdHlUb2tlbih0b2tlbiwgYWNjZXNzKTtcbiAgICBjb25zdCBkZWNvZGVkID0gdHJhbnNwb3J0LmRlY29kZWQ7XG4gICAgcHJvdmlkZXJTdGF0dXMgPSB0cmFuc3BvcnQucHJvdmlkZXJTdGF0dXM7XG4gICAgY29uc3QgcG9saWN5ID0gdmFsaWRhdGVJbnRlZ3JpdHlWZXJkaWN0KGRlY29kZWQsIHJlcXVlc3RIYXNoLCB7XG4gICAgICBwYWNrYWdlTmFtZSxcbiAgICAgIG1pbmltdW1WZXJzaW9uLFxuICAgICAgY2VydGlmaWNhdGVzLFxuICAgICAgbm93TXM6IERhdGUubm93KCksXG4gICAgfSk7XG4gICAgY29uc3QgdmVyZGljdFBhY2thZ2UgPSBwb2xpY3kucGFja2FnZU5hbWUsIGFwcFZlcmRpY3QgPSBwb2xpY3kuYXBwVmVyZGljdDtcbiAgICBjb25zdCBkZXZpY2VWZXJkaWN0cyA9IHBvbGljeS5kZXZpY2VWZXJkaWN0cyxcbiAgICAgIHRpbWVzdGFtcE1pbGxpcyA9IHBvbGljeS50aW1lc3RhbXBNaWxsaXM7XG4gICAgY29uc3QgcmVzdWx0ID0gYXdhaXQgcnBjKFwiY29tcGxldGVfcGxheV9pbnRlZ3JpdHlfYWRtaXNzaW9uX3YxXCIsIHtcbiAgICAgIC4uLmFkbWlzc2lvblBhcmFtcyxcbiAgICAgIHBfcmVxdWVzdF9wYXlsb2FkOiBjYXBhYmlsaXR5UGF5bG9hZCxcbiAgICAgIHBfcGFja2FnZV9uYW1lOiB2ZXJkaWN0UGFja2FnZSxcbiAgICAgIHBfYXBwX3ZlcmRpY3Q6IGFwcFZlcmRpY3QsXG4gICAgICBwX2RldmljZV92ZXJkaWN0czogZGV2aWNlVmVyZGljdHMsXG4gICAgICBwX3ZlcmlmaWVkX2F0OiBuZXcgRGF0ZSh0aW1lc3RhbXBNaWxsaXMpLnRvSVNPU3RyaW5nKCksXG4gICAgICBwX2RlY29kZV9kdXJhdGlvbl9tczogZHVyYXRpb24oKSxcbiAgICAgIHBfcHJvdmlkZXJfc3RhdHVzOiBwcm92aWRlclN0YXR1cyxcbiAgICB9KTtcbiAgICByZXR1cm4ganNvblJlc3BvbnNlKGludGVncml0eVJlc3VsdChyZXN1bHQsIGJpbmRpbmcpKTtcbiAgfSBjYXRjaCAoZXJyb3IpIHtcbiAgICBpZiAocmVzZXJ2YXRpb25JZCAmJiBiaW5kaW5nKSB7XG4gICAgICAvLyBBIGxvc3QgY29tcGxldGlvbiBBQ0sgbWF5IGFscmVhZHkgaGF2ZSBtaW50ZWQgYSBkdXJhYmxlIGNhcGFiaWxpdHkuXG4gICAgICAvLyBDbGVhbnVwIG5ldmVyIG92ZXJ3cml0ZXMgdGhhdCBjb21wbGV0aW9uIG9yIHBlcm1pdHMgYSBHb29nbGUgcmV0cnkuXG4gICAgICB0cnkge1xuICAgICAgICBhd2FpdCBycGMoXCJmaW5pc2hfcGxheV9pbnRlZ3JpdHlfYWRtaXNzaW9uX3YxXCIsIHtcbiAgICAgICAgICBwX2FjdG9yX2lkOiBiaW5kaW5nLmFjdG9ySWQsXG4gICAgICAgICAgcF9zZXNzaW9uX2lkOiBiaW5kaW5nLnNlc3Npb25JZCxcbiAgICAgICAgICBwX3Jlc2VydmF0aW9uX2lkOiByZXNlcnZhdGlvbklkLFxuICAgICAgICAgIHBfb3V0Y29tZTogZXJyb3IgaW5zdGFuY2VvZiBQdWJsaWNFcnJvciAmJlxuICAgICAgICAgICAgICBlcnJvci5jb2RlID09PSBcImludGVncml0eV9wb2xpY3lfcmVqZWN0ZWRcIlxuICAgICAgICAgICAgPyBcInJlamVjdGVkXCJcbiAgICAgICAgICAgIDogXCJhbWJpZ3VvdXNcIixcbiAgICAgICAgICBwX2RlY29kZV9kdXJhdGlvbl9tczogZHVyYXRpb24oKSxcbiAgICAgICAgICBwX3Byb3ZpZGVyX3N0YXR1czogZXJyb3IgaW5zdGFuY2VvZiBHb29nbGVUcmFuc3BvcnRFcnJvclxuICAgICAgICAgICAgPyBlcnJvci5wcm92aWRlclN0YXR1c1xuICAgICAgICAgICAgOiBwcm92aWRlclN0YXR1cyxcbiAgICAgICAgfSk7XG4gICAgICB9IGNhdGNoIHsgLyogRHVyYWJsZSBwaGFzZS9xdW90YSBoaXN0b3J5IHN0aWxsIHByZXZlbnRzIHJlZGlzcGF0Y2guICovIH1cbiAgICB9XG4gICAgY29uc3QgbWVzc2FnZSA9IGVycm9yIGluc3RhbmNlb2YgRXJyb3JcbiAgICAgID8gZXJyb3IubWVzc2FnZVxuICAgICAgOiBcIlBsYXkgSW50ZWdyaXR5IGZhaWxlZFwiO1xuICAgIGlmIChlcnJvciBpbnN0YW5jZW9mIFB1YmxpY0Vycm9yKSB7XG4gICAgICByZXR1cm4ganNvblJlc3BvbnNlKHtcbiAgICAgICAgZXJyb3I6IGVycm9yLmNvZGUgPT09IFwiaW50ZWdyaXR5X3BvbGljeV91bmNvbmZpZ3VyZWRcIlxuICAgICAgICAgID8gXCJwbGF5X2ludGVncml0eV91bmF2YWlsYWJsZVwiXG4gICAgICAgICAgOiBlcnJvci5jb2RlLFxuICAgICAgfSwgZXJyb3Iuc3RhdHVzKTtcbiAgICB9XG4gICAgaWYgKG1lc3NhZ2UgPT09IFwiQXV0aGVudGljYXRpb24gcmVxdWlyZWRcIikge1xuICAgICAgcmV0dXJuIGpzb25SZXNwb25zZSh7IGVycm9yOiBcImF1dGhlbnRpY2F0aW9uX3JlcXVpcmVkXCIgfSwgNDAxKTtcbiAgICB9XG4gICAgaWYgKC9yZXF1aXJlZCBlbnYgdmFyL2kudGVzdChtZXNzYWdlKSkge1xuICAgICAgcmV0dXJuIGpzb25SZXNwb25zZSh7IGVycm9yOiBcInBsYXlfaW50ZWdyaXR5X3VuYXZhaWxhYmxlXCIgfSwgNTAzKTtcbiAgICB9XG4gICAgcmV0dXJuIGpzb25SZXNwb25zZSh7IGVycm9yOiBcIlBsYXkgSW50ZWdyaXR5IHZlcmlmaWNhdGlvbiBmYWlsZWRcIiB9LCA1MDIpO1xuICB9XG59KTtcbiJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiQUFBQSxTQUNFLFdBQVcsRUFDWCxTQUFTLEVBQ1QsV0FBVyxFQUNYLFdBQVcsUUFDTixvQ0FBb0M7QUFDM0MsU0FBUyx3QkFBd0IsUUFBUSxpQ0FBaUM7QUFDMUUsU0FBUyxXQUFXLEVBQUUsWUFBWSxFQUFFLFVBQVUsUUFBUSxxQkFBcUI7QUFDM0UsU0FBUyxXQUFXLEVBQUUsYUFBYSxRQUFRLHlCQUF5QjtBQUNwRSxTQUFTLGFBQWEsUUFBUSxrQ0FBa0M7QUFDaEUsU0FDRSx1QkFBdUIsRUFDdkIseUJBQXlCLEVBRXpCLGVBQWUsUUFDVixvQ0FBb0M7QUFDM0MsU0FDRSxTQUFTLEVB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
// denoCacheMetadata=18208195775649228249,3234503773270055581
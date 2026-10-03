import {
  objectValue,
  PublicError,
  SHA256,
  UUID,
  zonedInstant,
} from "./production_contract.ts";

export type IntegrityBinding = {
  actorId: string;
  sessionId: string;
  nonce: string;
  action: string;
  requestHash: string;
  tokenHash: string;
};
function validFuture(value: unknown): value is string {
  try {
    return typeof value === "string" && zonedInstant(value) !== null &&
      Date.parse(value) > Date.now();
  } catch {
    return false;
  }
}

/** Exact server receipt, never caller-provided permission to contact Google. */
export function integrityAdmissionReceipt(
  value: unknown,
  binding: IntegrityBinding,
  state: string,
) {
  let r: Record<string, unknown>;
  try {
    r = objectValue(value);
  } catch {
    throw new PublicError("integrity_admission_invalid", 503);
  }
  const fields = [
    "contract_version",
    "reservation_id",
    "actor_id",
    "session_id",
    "nonce",
    "action",
    "request_hash",
    "token_sha256",
    "state",
    "can_call",
    "expires_at",
    "result",
  ];
  if (
    Object.keys(r).length !== fields.length || fields.some((k) => !(k in r)) ||
    r.contract_version !== 1 || typeof r.reservation_id !== "string" ||
    !UUID.test(r.reservation_id) ||
    r.actor_id !== binding.actorId || r.session_id !== binding.sessionId ||
    r.nonce !== binding.nonce ||
    r.action !== binding.action || r.request_hash !== binding.requestHash ||
    r.token_sha256 !== binding.tokenHash ||
    !SHA256.test(binding.requestHash) || !SHA256.test(binding.tokenHash) ||
    !validFuture(r.expires_at) || r.state !== state ||
    r.can_call !== (state !== "completed") ||
    (state !== "completed" && r.result !== null)
  ) {
    throw new PublicError("integrity_admission_invalid", 503);
  }
  return { reservationId: r.reservation_id, result: r.result };
}

export function integrityResult(value: unknown, binding: IntegrityBinding) {
  let r: Record<string, unknown>;
  try {
    r = objectValue(value);
  } catch {
    throw new PublicError("integrity_result_unavailable", 409);
  }
  const fields = [
    "status",
    "action",
    "request_hash",
    "package_name",
    "app_verdict",
    "device_verdicts",
    "native_capability",
    "capability_expires_at",
  ];
  if (
    Object.keys(r).length !== fields.length || fields.some((k) => !(k in r)) ||
    r.status !== "pass" || r.action !== binding.action ||
    r.request_hash !== binding.requestHash ||
    r.package_name !== "app.cool.mobile" ||
    r.app_verdict !== "PLAY_RECOGNIZED" ||
    !Array.isArray(r.device_verdicts) || r.device_verdicts.length > 10 ||
    !r.device_verdicts.every((v) => typeof v === "string" && v.length <= 80) ||
    !r.device_verdicts.some((v) =>
      v === "MEETS_DEVICE_INTEGRITY" || v === "MEETS_STRONG_INTEGRITY"
    ) ||
    typeof r.native_capability !== "string" ||
    !UUID.test(r.native_capability) ||
    !validFuture(r.capability_expires_at)
  ) throw new PublicError("integrity_result_unavailable", 409);
  return r;
}

export function integrityAdmissionError(error: unknown): PublicError {
  const e = typeof error === "object" && error !== null
    ? error as Record<string, unknown>
    : {};
  if (e.code === "42501") {
    return new PublicError("integrity_admission_forbidden", 403);
  }
  if (e.code === "22023") {
    return new PublicError("invalid_integrity_request", 400);
  }
  if (e.code === "53300") {
    return new PublicError("integrity_resource_limit", 429);
  }
  if (e.code === "55000" || e.code === "23505") {
    return new PublicError("integrity_reconciliation_required", 409);
  }
  return new PublicError("integrity_admission_unavailable", 503);
}

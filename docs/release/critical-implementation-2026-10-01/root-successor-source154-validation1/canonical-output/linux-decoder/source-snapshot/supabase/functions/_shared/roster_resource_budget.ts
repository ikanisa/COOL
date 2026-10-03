import {
  objectValue,
  PublicError,
  SHA256,
  uuid,
  zonedInstant,
} from "./production_contract.ts";

export type RosterBudget = {
  reservation_id: string;
  state: "reserved" | "finished";
  replayed: boolean;
  expires_at: string;
};
export function rosterBudgetReceipt(
  value: unknown,
  expected: {
    requestId: string;
    actorId: string;
    sessionId: string;
    sourceHash: string;
  },
): RosterBudget {
  let r: Record<string, unknown>;
  try {
    r = objectValue(value);
  } catch {
    throw new PublicError("roster_budget_receipt_invalid", 503);
  }
  const fields = [
    "contract_version",
    "ok",
    "reservation_id",
    "request_id",
    "actor_id",
    "session_id",
    "source_sha256",
    "state",
    "replayed",
    "expires_at",
  ];
  if (
    Object.keys(r).length !== fields.length || fields.some((k) => !(k in r)) ||
    r.contract_version !== 1 || r.ok !== true ||
    r.request_id !== expected.requestId || r.actor_id !== expected.actorId ||
    r.session_id !== expected.sessionId ||
    r.source_sha256 !== expected.sourceHash ||
    !SHA256.test(expected.sourceHash) ||
    !["reserved", "finished"].includes(String(r.state)) ||
    typeof r.replayed !== "boolean" || typeof r.expires_at !== "string" ||
    !Number.isFinite(Date.parse(r.expires_at))
  ) {
    throw new PublicError("roster_budget_receipt_invalid", 503);
  }
  let reservationId: string;
  try {
    reservationId = uuid(r.reservation_id, "roster_budget_receipt_invalid");
    if (zonedInstant(r.expires_at) === null) throw new Error();
  } catch {
    throw new PublicError("roster_budget_receipt_invalid", 503);
  }
  if (
    r.state === "reserved" &&
    (r.replayed !== false || Date.parse(r.expires_at) <= Date.now())
  ) {
    throw new PublicError("roster_resource_in_progress", 409);
  }
  return {
    reservation_id: reservationId,
    state: r.state as RosterBudget["state"],
    replayed: r.replayed as boolean,
    expires_at: r.expires_at,
  };
}

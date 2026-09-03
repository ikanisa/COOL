export type NotificationOperatorAction =
  | "health"
  | "list_pending"
  | "claim"
  | "get_claimed"
  | "confirm"
  | "record_send_start"
  | "record_outcome"
  | "release_claim"
  | "heartbeat";

export type NotificationOperatorCommand = {
  rpc: string;
  permission: "notifications.read" | "notifications.manage";
  sensitive: boolean;
  params: Record<string, unknown>;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const hashPattern = /^[0-9a-f]{64}$/;
const workerPattern = /^[A-Za-z0-9._:-]{3,80}$/;

function requiredUuid(payload: Record<string, unknown>, key: string): string {
  const value = payload[key];
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw new Error(`${key} must be a UUID`);
  }
  return value.toLowerCase();
}

function requiredText(
  payload: Record<string, unknown>,
  key: string,
  min: number,
  max: number,
): string {
  const value = payload[key];
  if (typeof value !== "string") throw new Error(`${key} is required`);
  const clean = value.trim();
  if (clean.length < min || clean.length > max) {
    throw new Error(`${key} must contain ${min} to ${max} characters`);
  }
  return clean;
}

function positiveInteger(
  payload: Record<string, unknown>,
  key: string,
): number {
  const value = payload[key];
  if (!Number.isSafeInteger(value) || Number(value) < 1) {
    throw new Error(`${key} must be a positive integer`);
  }
  return Number(value);
}

function requiredHash(payload: Record<string, unknown>, key: string): string {
  const value = payload[key];
  if (typeof value !== "string" || !hashPattern.test(value.toLowerCase())) {
    throw new Error(`${key} must be a SHA-256 digest`);
  }
  return value.toLowerCase();
}

function base(operatorUserId: string) {
  if (!uuidPattern.test(operatorUserId)) {
    throw new Error("Authenticated operator ID is invalid");
  }
  return { p_operator_user_id: operatorUserId.toLowerCase() };
}

export function notificationOperatorCommand(
  action: unknown,
  payload: Record<string, unknown>,
  operatorUserId: string,
): NotificationOperatorCommand {
  const common = base(operatorUserId);
  switch (action as NotificationOperatorAction) {
    case "health":
      return {
        rpc: "collect_notification_health",
        permission: "notifications.read",
        sensitive: false,
        params: common,
      };
    case "list_pending": {
      const limit = payload.limit == null
        ? 20
        : positiveInteger(payload, "limit");
      if (limit > 50) throw new Error("limit must be 50 or fewer");
      const cursor = payload.after_created_at;
      if (
        cursor != null &&
        (typeof cursor !== "string" || Number.isNaN(Date.parse(cursor)))
      ) {
        throw new Error("after_created_at must be an ISO timestamp");
      }
      return {
        rpc: "collect_list_pending_receipts",
        permission: "notifications.read",
        sensitive: false,
        params: {
          ...common,
          p_limit: limit,
          p_after_created_at: cursor ?? null,
        },
      };
    }
    case "claim": {
      const worker = requiredText(payload, "worker_id", 3, 80);
      if (!workerPattern.test(worker)) throw new Error("worker_id is invalid");
      return {
        rpc: "collect_claim_receipt",
        permission: "notifications.manage",
        sensitive: false,
        params: {
          ...common,
          p_job_id: requiredUuid(payload, "job_id"),
          p_worker_id: worker,
          p_request_id: requiredUuid(payload, "request_id"),
        },
      };
    }
    case "get_claimed":
      return {
        rpc: "collect_get_claimed_receipt",
        permission: "notifications.manage",
        sensitive: true,
        params: {
          ...common,
          p_job_id: requiredUuid(payload, "job_id"),
          p_claim_token: requiredUuid(payload, "claim_token"),
          p_fence_version: positiveInteger(payload, "fence_version"),
        },
      };
    case "confirm":
      if (payload.user_confirmation !== true) {
        throw new Error(
          "A current exact-recipient and exact-content confirmation is required",
        );
      }
      return {
        rpc: "collect_confirm_receipt",
        permission: "notifications.manage",
        sensitive: true,
        params: {
          ...common,
          p_job_id: requiredUuid(payload, "job_id"),
          p_claim_token: requiredUuid(payload, "claim_token"),
          p_fence_version: positiveInteger(payload, "fence_version"),
          p_destination_revision: positiveInteger(
            payload,
            "destination_revision",
          ),
          p_body_sha256: requiredHash(payload, "body_sha256"),
          p_confirmation_id: requiredUuid(payload, "confirmation_id"),
        },
      };
    case "record_send_start":
      return {
        rpc: "collect_record_send_start",
        permission: "notifications.manage",
        sensitive: true,
        params: {
          ...common,
          p_job_id: requiredUuid(payload, "job_id"),
          p_claim_token: requiredUuid(payload, "claim_token"),
          p_fence_version: positiveInteger(payload, "fence_version"),
          p_confirmation_id: requiredUuid(payload, "confirmation_id"),
        },
      };
    case "record_outcome": {
      const outcome = requiredText(payload, "outcome", 8, 32);
      if (!["observed_sent", "failed_no_send", "uncertain"].includes(outcome)) {
        throw new Error("outcome is invalid");
      }
      const note = payload.outcome_note;
      if (
        note != null && (typeof note !== "string" || note.trim().length > 500)
      ) {
        throw new Error("outcome_note must be 500 characters or fewer");
      }
      return {
        rpc: "collect_record_observed_outcome",
        permission: "notifications.manage",
        sensitive: false,
        params: {
          ...common,
          p_attempt_id: requiredUuid(payload, "attempt_id"),
          p_outcome: outcome,
          p_evidence_reference: requiredText(
            payload,
            "evidence_reference",
            8,
            500,
          ),
          p_outcome_note: typeof note === "string" ? note.trim() || null : null,
        },
      };
    }
    case "release_claim":
      return {
        rpc: "collect_release_unsent_claim",
        permission: "notifications.manage",
        sensitive: false,
        params: {
          ...common,
          p_job_id: requiredUuid(payload, "job_id"),
          p_claim_token: requiredUuid(payload, "claim_token"),
          p_fence_version: positiveInteger(payload, "fence_version"),
          p_reason: requiredText(payload, "reason", 8, 500),
        },
      };
    case "heartbeat": {
      const worker = requiredText(payload, "worker_id", 3, 80);
      if (!workerPattern.test(worker)) throw new Error("worker_id is invalid");
      const mode = requiredText(payload, "mode", 7, 20);
      if (!["no_send", "assisted_send"].includes(mode)) {
        throw new Error("mode is invalid");
      }
      return {
        rpc: "collect_worker_heartbeat",
        permission: "notifications.read",
        sensitive: false,
        params: {
          ...common,
          p_worker_id: worker,
          p_run_id: requiredUuid(payload, "run_id"),
          p_mode: mode,
          p_safe_status: { queue_checked: payload.queue_checked === true },
        },
      };
    }
    default:
      throw new Error("Unsupported notification operator action");
  }
}

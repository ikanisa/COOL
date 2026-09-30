import { UUID } from "../_shared/production_contract.ts";
export type ClaimedDelivery = {
  delivery_id: string;
  event_id: string;
  device_id: string;
  user_id: string;
  token: string;
  provider: "apns" | "fcm";
  environment: "sandbox" | "production";
  title: string;
  body: string;
  deep_link: string | null;
  event_type: string;
  attempt_number: number;
  claim_token: string;
};

export type DeliveryResult = {
  ok: boolean;
  retryable: boolean;
  messageId: string | null;
  errorCode: string | null;
  latencyMs: number | null;
  retryAfterSeconds?: number | null;
};

export type DispatchDependencies = {
  // Claim only work that this invocation is about to send. A large batch can
  // expire in the queue while earlier provider requests are still in flight.
  claim: () => Promise<ClaimedDelivery | null>;
  isCurrent: (delivery: ClaimedDelivery) => Promise<boolean>;
  send: (delivery: ClaimedDelivery) => Promise<DeliveryResult>;
  complete: (
    delivery: ClaimedDelivery,
    result: DeliveryResult,
  ) => Promise<void>;
  now?: () => number;
};

export const dispatchBudgetMs = 60_000;
// Four database/OAuth calls allow eight seconds each; FCM send allows ten.
// Reserve all five stages before taking another lease.
export const minimumDispatchRemainingMs = 43_000;

export async function dispatchNotifications(
  limit: number,
  dependencies: DispatchDependencies,
) {
  if (!Number.isInteger(limit) || limit < 1 || limit > 500) {
    throw new Error("invalid_notification_dispatch_limit");
  }
  const now = dependencies.now ?? (() => performance.now());
  const deadline = now() + dispatchBudgetMs;
  const counts = {
    claimed: 0,
    sent: 0,
    retrying: 0,
    failed: 0,
    completion_pending: 0,
    lease_lost: 0,
    budget_exhausted: false,
  };
  while (counts.claimed < limit) {
    if (deadline - now() < minimumDispatchRemainingMs) {
      counts.budget_exhausted = true;
      break;
    }
    const delivery = await dependencies.claim();
    if (!delivery) break;
    counts.claimed += 1;
    // An old database cannot silently downgrade the fenced worker contract.
    if (
      typeof delivery.user_id !== "string" || !UUID.test(delivery.user_id) ||
      typeof delivery.claim_token !== "string" || !delivery.claim_token ||
      !Number.isInteger(delivery.attempt_number) ||
      delivery.attempt_number < 1 ||
      delivery.attempt_number > 5 || !await dependencies.isCurrent(delivery)
    ) {
      counts.lease_lost += 1;
      break;
    }
    let result: DeliveryResult;
    try {
      result = await dependencies.send(delivery);
    } catch {
      // Provider transport failure is retryable under the database attempt
      // budget. Provider/body/credential error text must never reach logs.
      result = {
        ok: false,
        retryable: true,
        messageId: null,
        errorCode: "transport_exception",
        latencyMs: null,
      };
    }
    if (!result.ok && (result.retryAfterSeconds ?? 0) > 3600) {
      result = {
        ...result,
        retryable: false,
        errorCode: "retry_after_exceeds_budget",
      };
    }
    try {
      await dependencies.complete(delivery, result);
    } catch {
      // The provider might already have accepted this send, or the database
      // might have committed before the response was lost. Keep the lease for
      // recovery; never rewrite this result as a retryable provider failure.
      counts.completion_pending += 1;
      break;
    }
    if (result.ok) counts.sent += 1;
    else if (result.retryable && delivery.attempt_number < 5) {
      counts.retrying += 1;
    } else counts.failed += 1;
  }
  return counts;
}

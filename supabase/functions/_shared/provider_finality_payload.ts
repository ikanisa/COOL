const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_PATTERN = /^[0-9a-f]{64}$/i;

export class ProviderFinalityPayloadError extends Error {
  constructor() {
    super("Invalid provider finality payload");
    this.name = "ProviderFinalityPayloadError";
  }
}

type BaseEvent = {
  schemaVersion: 1;
  eventId: string;
  paymentId: string;
};

export type ProviderPaymentConfirmedEvent = BaseEvent & {
  eventType: "payment.confirmed";
  providerNetwork: string;
  transactionId: string;
  providerConfirmationId: string;
  receiverMomoNumberHash: string;
  amountRwf: number;
  occurredAt: string;
  evidenceSha256: string | null;
};

export type ProviderPaymentRejectedEvent = BaseEvent & {
  eventType: "payment.rejected";
  reason: string;
  providerReference: string | null;
};

export type ProviderFinalityEvent =
  | ProviderPaymentConfirmedEvent
  | ProviderPaymentRejectedEvent;

function fail(): never {
  throw new ProviderFinalityPayloadError();
}

function objectValue(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail();
  return value as Record<string, unknown>;
}

function boundedString(
  value: unknown,
  minimum: number,
  maximum: number,
): string {
  if (typeof value !== "string") fail();
  const clean = value.trim();
  if (clean.length < minimum || clean.length > maximum) fail();
  return clean;
}

function uuid(value: unknown): string {
  const clean = boundedString(value, 36, 36).toLowerCase();
  if (!UUID_PATTERN.test(clean)) fail();
  return clean;
}

function sha256(value: unknown): string {
  const clean = boundedString(value, 64, 64).toLowerCase();
  if (!SHA256_PATTERN.test(clean)) fail();
  return clean;
}

function optionalString(
  value: unknown,
  minimum: number,
  maximum: number,
): string | null {
  if (value === undefined || value === null) return null;
  return boundedString(value, minimum, maximum);
}

function exactKeys(
  value: Record<string, unknown>,
  allowed: ReadonlySet<string>,
): void {
  if (Object.keys(value).some((key) => !allowed.has(key))) fail();
}

const baseKeys = ["schema_version", "event_id", "event_type", "payment_id"];
const confirmedKeys = new Set([
  ...baseKeys,
  "provider_network",
  "transaction_id",
  "provider_confirmation_id",
  "receiver_momo_number_hash",
  "amount_rwf",
  "currency",
  "occurred_at",
  "evidence_sha256",
]);
const rejectedKeys = new Set([
  ...baseKeys,
  "reason",
  "provider_reference",
]);

export function parseProviderFinalityEvent(
  rawBody: string,
  authenticatedRequestId: string,
): ProviderFinalityEvent {
  let decoded: unknown;
  try {
    decoded = JSON.parse(rawBody);
  } catch {
    fail();
  }
  const value = objectValue(decoded);
  if (value.schema_version !== 1) fail();
  const eventId = uuid(value.event_id);
  if (eventId !== authenticatedRequestId.toLowerCase()) fail();
  const paymentId = uuid(value.payment_id);

  if (value.event_type === "payment.confirmed") {
    exactKeys(value, confirmedKeys);
    const providerNetwork = boundedString(value.provider_network, 2, 32)
      .toLowerCase();
    if (!/^[a-z0-9_]+$/.test(providerNetwork)) fail();
    if (value.currency !== "RWF") fail();
    if (
      !Number.isSafeInteger(value.amount_rwf) ||
      (value.amount_rwf as number) <= 0
    ) {
      fail();
    }
    const occurredAtValue = boundedString(value.occurred_at, 20, 40);
    const occurredAtMillis = Date.parse(occurredAtValue);
    if (!Number.isFinite(occurredAtMillis)) fail();

    return {
      schemaVersion: 1,
      eventId,
      eventType: "payment.confirmed",
      paymentId,
      providerNetwork,
      transactionId: boundedString(value.transaction_id, 3, 128),
      providerConfirmationId: boundedString(
        value.provider_confirmation_id,
        3,
        128,
      ),
      receiverMomoNumberHash: sha256(value.receiver_momo_number_hash),
      amountRwf: value.amount_rwf as number,
      occurredAt: new Date(occurredAtMillis).toISOString(),
      evidenceSha256: value.evidence_sha256 === undefined ||
          value.evidence_sha256 === null
        ? null
        : sha256(value.evidence_sha256),
    };
  }

  if (value.event_type === "payment.rejected") {
    exactKeys(value, rejectedKeys);
    return {
      schemaVersion: 1,
      eventId,
      eventType: "payment.rejected",
      paymentId,
      reason: boundedString(value.reason, 3, 500),
      providerReference: optionalString(value.provider_reference, 1, 128),
    };
  }

  return fail();
}

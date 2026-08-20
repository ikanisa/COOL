# Provider Finality Gateway Contract

Status: code-complete and locally tested; provider onboarding, sandbox
certification, production credentials, deployment, and real reconciliation are
not complete.

## Trust boundary

`provider-finality` is a server-to-server adapter. A trusted provider/bank
connector must independently validate settlement with the selected provider
before it signs a request. Flutter, Android, browser code, SMS content, OpenAI
parser output, group owners, and group admins must never receive either signing
key or call the service-role database RPC.

The shared HMAC contract proves that the request came from the provisioned
connector. It does not by itself prove that MTN MoMo or Airtel Money settled a
transaction. Provider certification must prove how the connector obtains and
validates that fact.

## Endpoint and authentication

Send `POST /functions/v1/provider-finality` with UTF-8 JSON and these headers:

- `content-type: application/json`
- `x-provider-finality-timestamp`: exactly ten decimal Unix seconds
- `x-provider-finality-request-id`: UUID, stable across delivery retries
- `x-provider-finality-signature`: `v1=<lowercase HMAC-SHA256 hex>`

The signed bytes are exactly:

```text
<timestamp>.<lowercase-request-id>.<exact-raw-request-body>
```

The function rejects timestamps outside a five-minute window, malformed UUIDs,
weak configured keys, invalid signatures, bodies over 64 KiB, request/body ID
mismatches, unknown fields, unsafe amounts, non-RWF currency, and invalid
state transitions. Signature comparison is constant-time. The exact raw body
SHA-256 is registered in the database; raw provider payloads are not stored in
the replay register.

`PAYMENT_PROVIDER_FINALITY_SECRET_CURRENT` is mandatory and must contain at
least 32 characters of high-entropy secret material. During rotation, configure
the old key as `PAYMENT_PROVIDER_FINALITY_SECRET_PREVIOUS`, configure and switch
the connector to the new current key, allow only the bounded retry interval,
then remove the previous key. Never put real key values in this repository,
Flutter defines, screenshots, logs, shell history, or release evidence.

## Version 1 confirmation event

```json
{
  "schema_version": 1,
  "event_id": "10000000-0000-4000-8000-000000000001",
  "event_type": "payment.confirmed",
  "payment_id": "20000000-0000-4000-8000-000000000001",
  "provider_network": "mtn_momo",
  "transaction_id": "PROVIDER-TRANSACTION-ID",
  "provider_confirmation_id": "PROVIDER-CONFIRMATION-ID",
  "receiver_momo_number_hash": "64-lowercase-hex-characters",
  "amount_rwf": 10000,
  "currency": "RWF",
  "occurred_at": "2026-08-15T10:00:00Z",
  "evidence_sha256": "optional-64-lowercase-hex-characters"
}
```

The database locks and matches the awaiting candidate by payment, provider
network, provider-global transaction ID, receiver hash, and amount. One valid
confirmation records one provider confirmation, posts exactly one collection
credit plus one member credit, marks the payment posted, and emits the existing
confirmation notification. A different confirmation cannot refinalize it.

## Version 1 rejection event

```json
{
  "schema_version": 1,
  "event_id": "10000000-0000-4000-8000-000000000002",
  "event_type": "payment.rejected",
  "payment_id": "20000000-0000-4000-8000-000000000001",
  "reason": "Provider reports transaction not settled",
  "provider_reference": "OPTIONAL-PROVIDER-REFERENCE"
}
```

A valid rejection changes only an awaiting candidate to reversed, cancels its
payment intent, posts no ledger entries, and records an audit event.

## Idempotency, retries, and failure behavior

- Retry the same exact raw body with the same request ID. Generate a fresh
  timestamp and signature for each retry; do not change the JSON bytes.
- The first successful database transaction returns `replayed: false`.
  Identical later deliveries return the original payment ID with
  `replayed: true` and cannot duplicate ledger or notifications.
- Reusing a request ID with different body bytes is rejected.
- A failed finalization rolls back its replay reservation, so a corrected,
  properly signed delivery can be retried safely.
- HTTP `401` means authentication failed, `400` means the versioned payload is
  invalid, `409` means the event conflicts with payment/provider state, `413`
  means the body is too large, and `500` means the gateway is not configured.
- The connector must use bounded exponential backoff and alert on sustained
  failures. It must not fall back to SMS or a native/browser confirmation.

## Provider onboarding and production acceptance

Before production, the payments owner and operator must add provider-specific
evidence for:

1. the authoritative settlement API/webhook and its provider authentication;
2. canonical transaction and confirmation identifiers and their uniqueness;
3. sandbox signing, success, rejection, delayed delivery, duplicate delivery,
   key rotation, outage, and credential-revocation tests;
4. a low-value authorized production transaction reconciled from provider
   reference to Collect payment, two ledger entries, payer balance, group
   balance, notification, and operational audit;
5. monitoring, dead-letter/retry ownership, reconciliation cadence, incident
   response, credential custody, and rollback approval.

Until those items and deployment approval exist, this adapter is production
readiness code—not evidence that real provider finality is live.

# Payment Integrations

Payment flows must separate guidance, evidence, review, confirmation, settlement, dispute, refund, and cancellation. No instruction screen, QR code, USSD route, or SMS message is a confirmed payment by itself.

## Current payment-related surfaces

| Area | Source | Status |
| --- | --- | --- |
| MoMo route and SMS evidence | Flutter MoMo services, `sms-ingest`, `parse-momo-sms`, reconciliation migrations | Active evidence pipeline. |
| Manual group allocation | Admin/mobile admin flows and allocation RPC/function contracts | Active with scoped permission requirements. |
| BioPay payment intents | BioPay screens, Edge Functions, payment intent migrations | Active contract; must distinguish intent/instruction from confirmation. |
| USSD/QR guidance | Dynamic MoMo/route migrations and mobile UI guidance | Active guidance, not settlement proof. |
| External provider webhooks | Not active as a generic gateway in this repo | Future provider integrations must verify signatures and idempotency. |

## Required payment states

Use the closest schema-supported states while preserving these semantics:

- `instruction_created`: user received QR/USSD/manual payment instructions.
- `pending_evidence`: evidence such as SMS or user-entered reference exists but is not confirmed.
- `manual_review`: evidence is ambiguous or needs authorized review.
- `manually_confirmed`: authorized actor confirmed based on accepted evidence.
- `paid`: verified settlement or accepted manual confirmation has completed.
- `disputed`: payment/evidence is challenged.
- `refunded`: funds returned or reversal completed.
- `cancelled`: payment intent/order no longer valid.
- `failed`: provider or validation failure.

Do not collapse disputed, refunded, cancelled, or failed into paid/fulfilled.

## Manual confirmation requirements

Every manual status change must capture:

- Actor id and role.
- Previous status and next status.
- Amount and currency where relevant.
- Method/source: SMS evidence, admin review, provider confirmation, support correction.
- Target id: payment intent, contribution, group transaction, order, or allocation.
- Timestamp from backend/database.
- Reason/reference.
- Audit event id.

## External provider requirements

Future payment providers must include:

- Webhook signature verification.
- Idempotency key or provider event id dedupe.
- Amount/currency/payee validation against expected intent.
- Explicit status mapping.
- Retry/backoff behavior.
- Audit events for accepted, rejected, duplicate, disputed, refunded, and failed events.

## Verification

```bash
bash scripts/migrations/validate_supabase_migrations.sh
scripts/dev/flutterw test test/docs/rls_payment_status_contract_test.dart
# Execute supabase/tests/rls_tenant_payment_status_contract.sql when DB is available.
deno test --allow-env=SUPABASE_SERVICE_ROLE_KEY $(find supabase/functions -type f -name '*_test.ts' | sort)
```

## Operations

- Review payment manual-review queues daily during launch.
- Monitor duplicate SMS/evidence rates and sender inventory acknowledgements.
- Keep payment instruction copy clear: instructions are pending until confirmed.
- Escalate cross-tenant payment visibility or unauthorized status changes as P0 incidents.

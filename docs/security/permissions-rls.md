# Permissions and RLS

Backend authorization is mandatory. UI checks improve user experience, but Supabase RLS, RPC checks, and Edge Function authorization are the enforcement layer.

## Permission model

| Actor | Expected access |
| --- | --- |
| Anonymous user | Public read-only content and invite previews explicitly allowed by RLS. No private data. |
| Authenticated user | Own profile/session data and group/payment records where membership or ownership allows it. |
| Group member | Scoped group visibility and contribution visibility according to membership. |
| Group owner or manager | Scoped management actions for their group or custodian boundary only. |
| Bank/admin role | Scoped operational review and allocation actions for assigned partner/custodian/group boundaries. |
| Platform admin | Explicit admin capabilities through role assignments and audited RPCs/functions. |
| Service role | Server-only automation. Never expose to clients. Every use must be narrow and logged where sensitive. |

## RLS rules

- Every client-accessible table must enable RLS.
- Policies must filter by user id, membership, partner/custodian scope, tenant scope, or explicit role assignment.
- Admin UI restrictions are never sufficient without database or Edge Function enforcement.
- Public/anonymous policies must be narrow, intentional, and covered by tests.
- Payment, campaign, role, app config, and allocation writes must be protected by explicit permission checks.
- Cross-tenant reads are P0 defects.

## Sensitive writes

Sensitive writes include:

- Role assignment, user status, profile privacy, account deletion.
- Payment status, manual allocation, refund/dispute/cancellation, reconciliation override.
- Campaign approval, notification send, outbound channel configuration.
- App configuration and feature flags.
- BioPay enrollment, match, revocation, and trust changes.
- File/OCR ingestion when it can expose identity, member lists, or payment evidence.

Each sensitive write must have backend authorization and an audit event.

## Required tests

```bash
bash scripts/migrations/validate_supabase_migrations.sh
supabase db lint --workdir supabase --local --schema public --fail-on error
# Execute supabase/tests/*.sql with pgTAP/RLS support when a database is available.
scripts/dev/flutterw test test/docs/rls_payment_status_contract_test.dart test/docs/security_privacy_hardening_test.dart
```

## Production-only note

In production-only mode, run RLS and permission tests only during a controlled window with backed-up data, named UAT accounts, and cleanup ownership. Production-only mode does not relax RLS requirements.

# Backend

Supabase is the authoritative backend for schema, RLS, RPCs, Edge Functions, storage policy, audit logs, and payment state protection.

## Layout

| Path | Purpose |
| --- | --- |
| `supabase/migrations` | Ordered SQL migrations. Every migration must be represented in `migration_manifest.yaml`. |
| `supabase/migrations/migration_manifest.yaml` | Purpose classification for migrations: schema, seed, mock, repair, fix, security, cleanup, observability. |
| `supabase/functions` | Deno Edge Functions and shared helpers in `_shared`. |
| `supabase/tests` | SQL contract tests for RLS, payment status, app config, and security privacy rules. |
| `supabase/policies` | Policy documentation and inventories. Migrations remain the source of truth. |
| `supabase/seed` | Local or environment-scoped seed files. |
| `supabase/docs` | Backend-specific notes and runbooks. |

## Core domains

- Identity and profiles.
- Admin roles, scoped permissions, and audit logs.
- Groups, group members, contributions, statements, and allocations.
- Partner/custodian routing and MoMo payment evidence.
- BioPay enrollment, matching, revocation, and payment intents.
- OTP, FCM tokens, notification preferences, and notification campaign events.
- Operational health, rate-limit events, reconciliation telemetry, and migration safety checks.
- App configuration and feature flags.

## Edge Functions

| Function | Purpose | Auth and safety contract |
| --- | --- | --- |
| `admin-create-user` | Create users from admin workflows. | Requires admin authorization, validates input, and must audit actor/action/target. |
| `allocate-contributions` | Allocate contribution/payment evidence to groups. | Requires scoped admin or authorized manager access; must not cross tenant/group boundaries. |
| `biopay-create-payment-intent` | Create BioPay payment intent records. | Requires authenticated context and valid amount/source; instruction is not confirmation. |
| `biopay-enroll` | Enroll biometric/payment profile data. | Requires authenticated user and trusted route checks; avoid logging biometric payloads. |
| `biopay-match` | Match BioPay input to an enrolled profile/payment route. | Rate limited and abuse hardened; returns only necessary match data. |
| `biopay-revoke` | Revoke BioPay enrollment or trust. | Requires actor authorization and audit log. |
| `delete-account` | Account deletion flow. | Validates requesting identity and records safe deletion outcome. |
| `evaluate-transfer-risk` | Evaluate risk signals for transfers/reconciliation. | Validates payload and avoids leaking private risk inputs. |
| `generate-ai-content` | Generate or update AI-assisted content. | Requires privileged role/config; audit generated content actions. |
| `parse-member-list` | Parse imported member lists/OCR-like files. | Validates MIME/shape/size and avoids unsafe logging. |
| `parse-momo-sms` | Parse MoMo SMS evidence into reconciliation records. | Treats SMS as evidence only; manual/verified confirmation is separate. |
| `record-operational-health` | Ingest app/ops health events. | Uses hardened ingestion policy and redacts sensitive context. |
| `send-notification` | Send notification campaign or direct notification events. | Requires approved campaign/permission where relevant; compares service tokens safely. |
| `send-otp` | Send OTP over configured channel. | Rate limited, abuse logged, secrets kept server-side. |
| `sms-ingest` | Ingest Android SMS evidence. | Authenticated/device-scoped ingestion, dedupe, safe parsing handoff. |
| `verify-otp` | Verify OTP challenge. | Rate limited, hashes secrets, returns minimal auth result. |

## Migration rules

- Name migrations with timestamp plus clear purpose.
- Update `supabase/migrations/migration_manifest.yaml` in the same change.
- Prefer forward-only migrations. If rollback is not straightforward, document the rollback in `docs/rollback/` or `docs/release/rollback.md`.
- Do not add mock/demo data to production-bound migrations unless it is explicitly classified and gated.
- Validate locally before applying to production:

```bash
bash scripts/migrations/validate_supabase_migrations.sh
supabase db lint --workdir supabase --local --schema public --fail-on error
```

If local Supabase is unavailable, record the blocker and run the SQL tests during a controlled database window.

## Edge Function verification

```bash
deno lint --rules-exclude=no-unversioned-import,require-await supabase/functions/**/*.ts
deno check $(find supabase/functions -type f -name '*.ts' | sort)
deno test --allow-env=SUPABASE_SERVICE_ROLE_KEY,AUTH_PHONE_PASSWORD_SECRET,OTP_CODE_HASH_SECRET,OTP_TEST_PHONE,OTP_TEST_CODE,GOOGLE_SERVICE_ACCOUNT_EMAIL,GOOGLE_PRIVATE_KEY,AI_AUDIT_SHEET_ID $(find supabase/functions -type f -name '*_test.ts' | sort)
```

## Database verification

```bash
bash scripts/migrations/validate_supabase_migrations.sh
# Requires a running Supabase local database or controlled linked database.
supabase db lint --workdir supabase --local --schema public --fail-on error
# Execute SQL tests in supabase/tests with pgTAP/RLS support when DB is available.
```

## Storage and realtime rules

- Storage buckets must be private by default and expose signed URLs only when required.
- File uploads must validate MIME type, size, owner, and purpose before persistence.
- Realtime subscriptions must be scoped by RLS; do not publish cross-tenant data to public channels.

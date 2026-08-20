# Supabase production readiness plan

Collect deploys directly to production; there is no staging environment. Every
deployment therefore runs the complete local gate before mutating production.

## Required gate

1. Flutter format, static analysis, complete tests and reviewed golden images.
2. Deno type checks and tests for the exact six Edge Functions.
3. Local Supabase reset plus bank-transfer rollback UAT proving RLS,
   maker-checker, idempotency, statement finality and balanced exact-once ledger.
4. Production secret inventory without printing values:
   `BANK_EMAIL_INGEST_HMAC_SECRET`, `FCM_SERVICE_ACCOUNT_JSON` and any configured
   APNs material.
5. Apply the reviewed bank-only migration and record its version.
6. Deploy the six allowlisted functions and delete every retired function.
7. Run linked production inventory, privilege, RLS and read-only readiness checks.
8. Build and deploy public web/Admin and verify production URLs.

Provider, bank-statement, real-device, store and accountable approval evidence
remain distinct from local automation and must not be inferred from a passing
build.

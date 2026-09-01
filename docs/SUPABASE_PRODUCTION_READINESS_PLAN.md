# Supabase production readiness plan

Collect deploys directly to production; there is no staging environment. Every
deployment therefore runs the complete local gate before mutating production.

## Required gate

1. Flutter format, static analysis, complete tests and reviewed golden images.
2. Deno type checks and tests for every function in the governed deployment allowlist.
3. Local Supabase reset plus MoMo and bank rollback UAT proving RLS, scoped
   parsing, unique allocation, maker-checker, idempotency, statement finality
   and balanced exact-once ledgers.
4. Production secret inventory without printing values:
   `BANK_EMAIL_INGEST_HMAC_SECRET`, `FCM_SERVICE_ACCOUNT_JSON` and any configured
   APNs material, plus `PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER` and server-side
   Play Integrity credentials/configuration.
5. Apply the reviewed hybrid migration chain and record every version.
6. Deploy the allowlisted MoMo, bank, auth and notification functions; remove
   only functions explicitly retired by the reviewed architecture.
7. Run linked production inventory, privilege, RLS and read-only readiness checks.
8. Build and deploy public web/Admin and verify production URLs.

Provider, bank-statement, real-device, store and accountable approval evidence
remain distinct from local automation and must not be inferred from a passing
build.

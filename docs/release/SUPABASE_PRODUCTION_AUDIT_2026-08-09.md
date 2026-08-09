# Collect Supabase Production Audit

Audit date: 2026-08-09
Project ref: `lhbowpbcpwoiparwnwgt`
Release candidate: `1.2.2+14`

## Verified live state

- Project `COOL` is `ACTIVE_HEALTHY` in `us-east-2` on PostgreSQL
  `17.6.1.021`.
- Local and remote migration histories match exactly: 62 local, 62 remote,
  zero missing, zero extra.
- The repository schema contract matches production exactly: 313 expected
  objects, 313 remote objects, zero missing, zero extra.
- All 58 public base tables have row-level security enabled. Production has
  153 policies and 92 public functions; the privilege/search-path contract
  passes.
- Linked rollback-only SMS-first and Admin/security UAT pass against the live
  database without retaining production customer data.
- Error-level Supabase security and performance advisors report no issues.
  Warning-level performance advisors are clean; the bounded security-warning
  inventory remains within the reviewed repository allowances.
- All 11 production Edge Functions were redeployed from the current repository
  and are `ACTIVE`. Auth verification is enabled except for the two deliberately
  custom-authenticated endpoints: `auth-send-whatsapp-otp` and
  `stripe-webhook`.
- A post-deployment source download compared 19 deployed files with their local
  counterparts and found zero mismatches.
- The Edge Function auth-contract test passes. Deno type-checking passes for
  every deployed entrypoint, formatting passes for all 22 function files, and
  all 7 APNs, FCM, and Stripe-signature unit tests pass.
- APNs is configured with a newly registered Collect production key. The four
  required APNs secret names are present in Supabase. The one-time downloaded
  private-key file was removed from the workstation after verification.
- The deprecated local `[inbucket]` configuration was migrated to
  `[local_smtp]` for current Supabase CLI compatibility.

## Remaining production blocker

The strict production-readiness gate now stops only on
`FCM_SERVICE_ACCOUNT_JSON`. Google Firebase's default Admin SDK service account
is at its key limit, and the available historical Play publisher credential is
revoked. A dedicated least-privilege `collect-fcm` service account must be
created after Google Cloud account re-verification, granted Firebase Cloud
Messaging send access, installed as `FCM_SERVICE_ACCOUNT_JSON`, and verified
with a physical Android token. This is an authenticated provider gate, not a
database, migration, RLS, policy, trigger, SQL-function, or Edge-source defect.

After the FCM credential is installed, rerun
`scripts/supabase_production_readiness.sh`, then prove APNs/FCM foreground,
background, terminated-state, token-refresh, opt-out, invalid-token retirement,
tap-routing, and deep-link behavior on physical devices.

## Credential-control finding

The supplied Google Sheet contains plaintext privileged credential classes,
including Supabase administrative/database credentials and third-party API
secrets. No value was copied into source, documentation, logs, screenshots, or
release artifacts. Treat every privileged value present there as compromised:
inventory dependencies, rotate or revoke each value through its owning
provider, update governed runtime secret stores, verify dependent services, and
remove plaintext values from the Sheet. Rotation must be impact-mapped because
some credentials may be shared by applications outside Collect.

## Evidence boundary

This audit proves current production schema, policy, migration, function-source,
secret-name, endpoint-auth, and provider-configuration state. It does not prove
physical-device push delivery, store approval, public release, or accountable
release-owner acceptance.

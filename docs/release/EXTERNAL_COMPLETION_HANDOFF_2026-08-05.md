# External Completion Handoff

Status date: 2026-08-05
Release baseline: `1.2.2+10`
Controlled source revision: `fb403a819fbe4bc23845cc27fa880bff185ef1bc`

All independently executable local engineering, deployment, backend-schema,
artifact, and release-document work is complete for E-081. The goal remains
blocked because the following actions require a live unlocked device, external
account authority, provider execution, an upstream toolchain, or accountable
human acceptance. Never place credentials, verification codes, or raw customer
data in this repository or its evidence pack.

## Required external actions

1. Keep the paired physical iPhone unlocked and awake, preferably connected by
   USB. Rerun the staging-only physical route, lifecycle, and Camera recovery
   targets. Complete human VoiceOver traversal and retain only sanitized
   markers/screenshots. E-081 is a rejected preflight: its build passed, but no
   runner started while the phone remained locked.
2. Have a GitHub organization owner restore Actions billing/policy/runner
   eligibility, then rerun the workflow for the controlled revision. Push run
   `30954970376` failed as `startup_failure` before job creation; repository
   configuration is enabled, while organization-level inspection is forbidden
   to the current credential.
3. Authenticate Google Play Developer Reporting and inspect the live Console
   surfaces. The local optimization gate is otherwise complete. Upload or
   submit only after explicit account-holder and release-owner approval.
4. Configure APNs securely in production Supabase and provide an Associated
   Domains-capable distribution profile plus App Store Connect authority. The
   strict readiness gate currently lacks `APNS_KEY_ID`, `APNS_TEAM_ID`,
   `APNS_BUNDLE_ID`, and `APNS_PRIVATE_KEY_BASE64`; do not commit their values.
5. Execute one provider-authorized MoMo validation using a controlled test plan
   and retain only sanitized transaction and reconciled-ledger evidence.
6. Record ten-persona UAT and named Product, privacy/security, and release-owner
   approvals tied to `1.2.2+10`, the current APK/AAB hashes, and the refreshed
   cross-platform manifest.
7. When governed Flutter 3.47 or later is available, enable built-in Kotlin and
   rerun the Android compatibility, build, route, and regression matrices.

## Closure rule

Do not convert simulator runs, an unsigned archive, a live unauthenticated web
check, a schema audit, or a local store packet into a physical-device, signed
distribution, provider, store-processing, or accountable-approval claim. The
goal may be resumed when any external dependency above changes.

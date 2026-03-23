# M-Money SMS Full-Stack Audit

Date: 2026-03-22
Scope: Android app access and onboarding, device-side SMS sync, Supabase ingestion/parsing/reconciliation, related tables, and user-facing M-Money SMS UX.

## Executive Summary

The M-Money SMS pipeline is valuable but high-risk. It reads restricted Android SMS data, persists raw payment confirmations server-side, invokes privileged Supabase Edge Functions, and mutates financial tables that feed statements, balances, savings ledgers, and partner reconciliation.

The strongest current concern is compliance and distribution risk, not just code correctness. As of 2026-03-22, Google Play still treats SMS permissions as high-risk and only allows them for tightly-scoped core functionality, typically default SMS/Phone/Assistant handlers. COOL is not implemented as a default SMS handler. That makes the current manifest-level SMS strategy a likely Play Store blocker unless distribution is private, sideloaded, enterprise-managed, or the product is re-architected around a non-SMS ingestion path.

Before this audit pass, the implementation also had correctness drift:

- SMS access defaulted on in app preferences even though product copy described explicit opt-in.
- Permission onboarding completion was stored but not respected after OTP verification.
- The one-time 12-month historical sync was only tracked in-memory, so it could re-run after relaunch.
- Users had no persistent sync audit/status view.
- Group contribution reconciliation drifted between `confirmed` and `completed`, which risked inconsistent totals across UI, database logic, and edge-function reconciliation.

This pass fixes the highest-impact correctness issues, adds a persistent sync audit trail, improves UI visibility, hardens compatibility across app and backend layers, and now stages data-retention minimization for raw SMS artifacts. It does not remove the fundamental Play policy risk, and the new retention controls still need to be applied in each Supabase environment.

## Current End-to-End Architecture

### App access and onboarding

- Android manifest declares `READ_SMS` and `RECEIVE_SMS`.
- App-level access is controlled by `AppAccessService`.
- OTP verification decides whether to route the user into app-access onboarding.
- Profile app-access controls can enable or disable SMS sync after onboarding.

### Device-side ingestion

- `MomoSmsAutoreadService` requests runtime SMS permission, starts Android foreground/background SMS listeners, performs initial 12-month inbox sync, and manually re-syncs approved sender IDs.
- The service converts approved messages into normalized `MomoSmsCapture` payloads and sends them to the `sms-ingest` Edge Function.
- Background failures are queued locally in Hive for retry on next foreground refresh.

### Supabase ingestion and parsing

- `sms-ingest` validates the sender, deduplicates by `device_message_key`, persists into `momo_sms_raw`, and triggers `parse-momo-sms`.
- `parse-momo-sms` writes normalized parse results into `momo_sms_parsed`, then reconciles them into financial records such as `momo_ledger_entries`, `group_contributions`, partner payments, or driver subscriptions.
- Reconciliation uses an admin client and privileged writes, so auth checks and idempotency are critical.

### User-facing surfaces

- Main MoMo hub.
- Statements screen.
- App-access onboarding.
- Profile app-access sheet.
- SMS rationale sheet.

## Findings

### 1. Google Play policy risk remains severe

Severity: Critical

Why it matters:

- Google Play says SMS permissions are high-risk/sensitive and must be removed if the app does not qualify.
- The documented permitted uses are narrow and center on default SMS, Phone, or Assistant handlers.
- COOL uses SMS to reconcile payments, not to function as a default messaging handler.

Assessment:

- If this app is intended for public Google Play distribution, the current SMS permission model is likely non-compliant.
- If the intended distribution is enterprise, private, closed testing, or sideloaded APKs, this becomes a product/distribution governance question rather than a code bug.

Recommendation:

- Decide explicitly whether this feature is allowed only outside public Play distribution.
- If public Play is required, design a non-SMS alternative for payment confirmation ingestion.

### 2. SMS opt-in behavior previously contradicted the product’s own privacy posture

Severity: High

Previous state:

- SMS access defaulted to enabled in app preferences.
- Copy in onboarding and profile access treated SMS as a deliberate opt-in.

Risk:

- Users could land in an inconsistent state where the product behaves as if SMS access is part of the normal baseline instead of explicit consent.
- This increased privacy, support, and disclosure risk.

Fix shipped:

- SMS access now defaults off.
- Copy was aligned to describe SMS as optional and scoped to approved M-Money confirmations.

### 3. Permission onboarding completion existed but was not actually enforced

Severity: High

Previous state:

- OTP verification always routed into app-access onboarding, even when onboarding had already been completed.

Risk:

- Repetitive onboarding flow.
- User confusion.
- Higher chance of accidental re-prompting and permission fatigue.

Fix shipped:

- OTP verification now checks the onboarding completion flag and routes directly to the redirect target or home when the flow is already complete.

### 4. The initial 12-month sync was not persistent across launches

Severity: High

Previous state:

- The “initial sync completed” flag was only stored in memory on the running service instance.
- App relaunches could cause another historical scan to be scheduled.

Risk:

- Duplicate scanning workload.
- Unnecessary inbox reads.
- Repeated device/server activity without user visibility.

Fix shipped:

- Added persisted local sync state in Hive.
- Manual sync now uses an overlap window based on the latest known device message timestamp instead of blindly re-reading a full year when incremental sync is possible.

### 5. There was no user-visible sync audit trail

Severity: Medium

Previous state:

- Users could not see whether the backfill ever completed, when the last sync ran, whether a sync failed, or whether the app was currently in incremental mode.

Risk:

- Hard to support operationally.
- Difficult for users to understand missing statements or stale balances.

Fix shipped:

- Added `momo_sms_sync_runs` with RLS.
- Added repository/provider/model support to load sync history.
- Added reusable sync status cards on the MoMo hub and statements screen.

### 6. Group contribution status drift was a real data integrity risk

Severity: High

Previous state:

- `confirm_contribution()` moved rows to `completed`.
- Much of the app, SQL, and reconciliation logic expected `confirmed`.
- Some screens already tolerated both, many did not.

Risk:

- Incorrect savings totals.
- Broken dashboard balances.
- Reconciliation ambiguity.
- Divergent admin and user views.

Fix shipped:

- Added migration to normalize legacy `completed` rows to `confirmed`.
- Replaced `confirm_contribution()` with a canonical `confirmed` implementation that still tolerates old data.
- Updated app and edge-function compatibility checks so existing rows do not silently disappear before/while the migration is rolled out.

### 7. Raw SMS storage is still broader than strictly necessary

Severity: High

Current state:

- `momo_sms_raw` stores full SMS body text.
- `momo_sms_parsed` stores parsed financial and phone details.
- `momo_parse_attempts` stores parse attempts and failures.

Risk:

- The system historically retained highly sensitive financial message contents longer than needed.
- Product copy previously understated this; disclosures are now more accurate, and retention remediation is now staged, but it still depends on migration rollout.

Fix shipped:

- Added a retention/redaction migration that:
  - redacts `momo_sms_raw.sms_body` after successful parse + matched reconciliation retention expiry
  - clears stored AI request/response payloads in `momo_parse_attempts`
  - schedules a daily pg_cron run where available

## Changes Shipped In This Pass

### App

- SMS access now defaults to explicit opt-in.
- OTP verification respects completed permission onboarding.
- SMS onboarding/profile/rationale copy now better reflects what is actually stored and synced.
- New sync status card surfaces state on the MoMo hub and statements screen.
- Statements refresh after sync completion.

### Device sync service

- Added persistent local sync state for:
  - initial 12-month backfill completion
  - last successful sync
  - latest known message timestamp
- Added durable retry queue writes for failed foreground/background ingestion.
- Added Supabase sync audit writes for successful and failed sync runs.
- Manual sync now narrows the scan window when incremental sync is possible.

### Supabase and edge functions

- Added `momo_sms_sync_runs` migration with RLS and indexes.
- Normalized canonical contribution status back to `confirmed`.
- Updated reconciliation logic and tests to tolerate legacy `completed` rows while returning canonical `confirmed`.
- Added a retention/redaction migration for raw SMS bodies and AI parse payloads.
- Added an admin-only generic manual-review queue and close actions for
  M-Money SMS reconciliations that do not map to bank custody allocations.
- Added an admin-only sender inventory so unsupported or legacy raw SMS
  senders are visible with parse and reconciliation outcomes instead of being
  discoverable only through direct table inspection.
- Added an admin acknowledgement path for legacy unsupported sender backlog so
  operators can resolve reviewed history without approving new senders or
  mutating the stored raw SMS records.
- Added focused sync-support tests for persisted local sync state, manual
  incremental cutoff planning, and Supabase sync-run audit payload writes.
- Added host-side sync contract coverage for successful initial backfill,
  successful manual incremental sync, and failed sync-run auditing in
  `momo_sms_autoread_service_test.dart` by making the service's platform,
  permission, and inbox-loading dependencies injectable for tests.
- Added a server-truth migration-safety metric to the M-Money SMS operations
  summary so legacy `group_contributions.status = 'completed'` rows surface in
  the admin dashboard instead of relying on ad hoc database checks.
- Added a scheduled Supabase migration-safety verifier that writes trusted
  `sms_ingest` operational health events and feeds the release dashboard with
  server-origin `SMS Ingest` health.
- Added `scripts/verify_momo_sms_supabase_rollout.sh` so future environments
  can be checked for migration presence, cron installation, summary integrity,
  trusted health events, and zero legacy `completed` contribution rows without
  replaying the full manual audit process.
- Wired the verifier into `scripts/release_readiness.sh` and the GitHub release
  workflow as an optional gate that activates automatically when
  `SUPABASE_DB_URL` is configured in CI.
- Added `scripts/check_momo_sms_contracts.sh` and a dedicated `M-Money SMS
  Contracts` CI job so app-access policy, sync execution, sender-policy
  alignment, admin observability, rollout verifier syntax, and reconciliation
  tests fail together as one focused contract lane.
- Added a device-backed Android emulator workflow and runner for
  `integration_test/momo_sms_inbox_sync_test.dart`, including seeded SMS inbox
  setup, runtime permission grants, sync-state assertions, and artifact capture
  for logcat and seeded inbox rows.

## Residual Gaps

1. Public Google Play distribution is still the main unresolved risk.
2. The new raw-SMS retention controls still need rollout validation in every Supabase environment.
3. Sync audit is completion/failure oriented, not full step-by-step execution tracing.
4. There is now an explicit admin operations summary for device sync, sender drift, retry-queue pressure, parse pressure, reconciliation pressure, retention backlog, generic manual-review closure, and unsupported sender inventory, with sender inventory now surfaced as server-truth rather than only as a secondary audit section. The remaining mobile-origin pieces are still telemetry rather than server-trusted release truth.
5. There is now a repo-level verifier and an optional CI gate for migration safety, but each environment still has to opt in by supplying the database secret and running the verifier against that target.
6. There is now both host-side execution coverage and a scheduled/manual Android-emulator lane for inbox sync, but the emulator lane is not part of every PR gate yet and still needs its first proven green production CI run.

## Recommended Next Actions

1. Product and compliance decision:
   - Decide whether M-Money SMS is public Play functionality, private distribution functionality, or a temporary internal bridge.

2. Data minimization rollout:
   - Apply the retention migration everywhere.
   - Verify that redaction only affects successfully reconciled rows and not unresolved/manual-review cases.

3. Operational visibility:
   - Keep the reconciliation summary aligned with operator actions so admin-closed reviews remain visible as resolved throughput instead of disappearing into ambiguous status.

4. Migration safety:
   - Run the new migration everywhere and confirm no `group_contributions.status = 'completed'` rows remain.
   - Enroll every Supabase environment in `scripts/verify_momo_sms_supabase_rollout.sh` or the CI gate by providing `SUPABASE_DB_URL`.
   - Verify every Supabase environment has the scheduled migration-safety cron job installed and producing trusted `sms_ingest` events.

5. Testing:
   - Keep the new sync-support unit coverage in place.
   - Keep the Android-emulator inbox-sync lane healthy and promote it into broader PR gating only after it proves stable.

## Research Notes

As of 2026-03-22, the strongest external guidance affecting this feature is:

- Android permission minimization guidance: prefer minimizing sensitive permissions, explain why permissions are needed, and handle denials clearly.
- Google Play SMS/Call Log policy: SMS permissions are restricted high-risk permissions and are generally limited to default handler use cases.
- Supabase security guidance: tables in exposed schemas should have RLS enabled, and privileged server-side operations must be tightly controlled.
- Supabase Edge Function guidance: edge functions should be designed as short-lived, idempotent operations with proper observability.

## Sources

- Android Developers, “Minimize your permission requests”:
  - https://developer.android.com/privacy-and-security/minimize-permission-requests
- Google Play Console Help, “Use of SMS or Call Log permission groups”:
  - https://support.google.com/googleplay/android-developer/answer/10208820?hl=en
- Supabase Docs, “Row Level Security”:
  - https://supabase.com/docs/guides/database/postgres/row-level-security
- Supabase Docs, “Edge Functions”:
  - https://supabase.com/docs/guides/functions

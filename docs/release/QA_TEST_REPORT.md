# Collect QA Test Report

Audit date: 2026-06-01

Scope: SMS-first Groups refactor for the Flutter mobile app, Admin PWA,
Supabase schema/functions, payment-intent allocation, and release evidence.

## Decision

Current status: **NO-GO for public launch** until Android SMS access UAT is run
with sanitized evidence, the linked sender-hash migration is applied, Android
signing/iOS scope evidence is recorded, product signoff is approved, and
release owner signoff is recorded.

Older Supabase platform blockers from the previous product definition are not
carried forward in this report. Any platform blocker must be reproduced by a
fresh readiness run.

## Commands And Results

| Command | Result | Notes |
| --- | --- | --- |
| `scripts/release_worktree_review_gate.sh --json` | Pass | Worktree review gate passed after the release approval evidence gate commit; branch remains ahead of origin until pushed. |
| `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub` | Pass | Analyzer clean after the Collect mobile UI and SMS-first app/admin refactor. |
| Full Flutter/release-doc suite | Pass | `101` tests passed across Admin PWA, app shell, phone/Public ID, widgets, persona smoke, repository, Supabase contract, and release-doc tests. |
| `scripts/admin_pwa_release_build.sh` | Pass | Built `build/web` for `lib/main_admin.dart` and passed Admin PWA manifest/hosting gates in `.cache/repo_wide_qa_uat/20260601T205424Z`. |
| `scripts/admin_pwa_render_smoke.sh` | Pass | Runtime/render evidence written to `.cache/repo_wide_qa_uat/20260601T205424Z/admin_pwa_render_smoke`; desktop and mobile screenshots are nonblank and show the Collect admin login. |
| `scripts/mobile_route_render_smoke.sh` | Pass | Flutter mobile web build captured viewport-controlled Chrome CDP 390x844 screenshots and JSON nonblank checks for 21 representative mobile routes at `.cache/mobile_route_render_smoke/20260602T040433Z`. |
| `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev ./scripts/admin_pwa_live_gate.sh --json` | Pass | Deployed Admin PWA responds over HTTPS with required headers, cache policy, manifest, service worker, and bundle responses. |
| `scripts/collect_edge_auth_contract_uat.sh` | Pass | Local Edge Function auth contract passed. |
| `deno check supabase/functions/...` | Pass | `parse-payment-sms`, `ingest-payment-sms`, and `allocate-payment` type-check. |
| `./scripts/migrations/validate_supabase_migrations.sh` | Pass | Local migration validation passes. |
| `scripts/collect_admin_security_uat.sh` | Pass | Linked rollback UAT for admin RBAC, raw-SMS reveal audit logging, payment-event reparse permission, and denial paths passed. |
| `scripts/collect_linked_uat.sh` | Blocked | Linked rollback UAT fails with `payment intent sender hash was not stored`; apply `supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql`. |
| `scripts/supabase_production_readiness.sh` | Blocked | Linked readiness cannot be green while linked contribution UAT fails. |
| `scripts/android_device_uat.sh` | Pass | Production-flavor integration smoke passed on device `13111JEC215558`; retained evidence at `.cache/android_device_uat/20260602T042542Z/summary.json`. |
| `scripts/flutter_mobile_release_gate.sh --json` | Blocked | APK/AAB artifacts are current; signing review and iOS scope remain pending. |
| `scripts/release_artifact_manifest.sh --json` | Pass | Current APK/AAB and Admin PWA artifacts are fresh; checksum manifest written to `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-06-02.sha256`. |

## QA Findings

- P0: Android MoMo SMS consent, ingestion, parse, allocation, exception,
  and ledger UAT must be executed on a real Android device with sanitized
  evidence.
- P0: Linked Supabase must apply
  `supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql`
  and pass `scripts/collect_linked_uat.sh`.
- P0: Stakeholder signoff is required for the corrected Groups product
  definition.
- P0: Android release signing review and iOS release-scope evidence are missing.
- P1: Release branch remains ahead of origin until pushed/reviewed.
- P1: Android release signing and any iOS release-scope decision still need
  current release-owner evidence.

## Refactor Coverage

- Mobile navigation is reduced to `Home`, `Groups`, and `Settings`.
- Public directory, campaign/category/target/cover flows, manual SMS paste,
  contributor-reported transaction IDs, and anonymity choices are removed from
  the current UX.
- Profile owns MoMo number and the generated 6-digit Collect ID.
- Group creation uses name, optional description, and profile-synced receiver
  MoMo with edit support.
- Group creation is Android-only; iPhone users receive exactly
  `group creation is available only on Android`.
- Contributions create Supabase payment intents and launch the MoMo USSD dialer.
- MoMo SMS is parsed through Edge Functions and allocation is based on
  payment intent, Collect ID, amount, receiver, and timing.
- Admin PWA is aligned to Groups, Members, Payment intents, SMS parsing,
  Allocations, Exceptions, Ledger, Receivers, SMS, Audit logs, Settings,
  Feature flags, System health, and Admin users.

## Next Verification

1. Run Android SMS access UAT with real MoMo notification scenarios.
2. Record Android signing review and iOS scope evidence, then rerun release gates.
3. Record product and release-owner signoff.
4. Regenerate release evidence from current commands only.

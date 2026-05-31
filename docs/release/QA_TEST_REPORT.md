# Collect QA Test Report

Audit date: 2026-05-31

Scope: SMS-first Groups refactor for the Flutter mobile app, Admin PWA,
Supabase schema/functions, payment-intent allocation, and release evidence.

## Decision

Current status: **NO-GO for public launch** until Android SMS access UAT is run
with sanitized evidence, Admin PWA live deployment is proven, Android
signing/iOS scope evidence is recorded, product signoff is approved, and
release owner signoff is recorded.

Older Supabase platform blockers from the previous product definition are not
carried forward in this report. Any platform blocker must be reproduced by a
fresh readiness run.

## Commands And Results

| Command | Result | Notes |
| --- | --- | --- |
| `git status --short` | Dirty | Large active refactor state. Public release still needs explicit worktree review and staging. |
| `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze` | Pass | Analyzer clean after the SMS-first app/admin refactor. |
| Full Flutter/release-doc suite | Pass | `83` tests passed across Admin PWA, app shell, phone/Public ID, widgets, persona smoke, repository, Supabase contract, and release-doc tests. |
| `scripts/admin_pwa_release_build.sh` | Pass | Built `build/web` for `lib/main_admin.dart` and passed Admin PWA manifest/hosting gates. |
| `scripts/admin_pwa_render_smoke.sh` | Pass | Runtime/render evidence written to `.cache/admin_pwa_render_smoke/20260527T041454Z-sms-first-current`; desktop and mobile screenshots are nonblank and show the Collect admin login. |
| `scripts/admin_pwa_live_gate.sh --json` | Blocked | `ADMIN_PWA_LIVE_URL` is missing; live deployment is not yet proven. |
| `scripts/collect_edge_auth_contract_uat.sh` | Pass | Local Edge Function auth contract passed. |
| `deno check supabase/functions/...` | Pass | `parse-payment-sms`, `ingest-payment-sms`, and `allocate-payment` type-check. |
| `./scripts/migrations/validate_supabase_migrations.sh` | Pass | Local migration validation passes. |
| `scripts/collect_admin_security_uat.sh` | Pass | Linked rollback UAT for admin RBAC, raw-SMS reveal audit logging, payment-event reparse permission, and denial paths passed. |
| `scripts/collect_linked_uat.sh` | Pass | SMS-first rollback UAT passed via linked database query. |
| `scripts/supabase_production_readiness.sh` | Pass | Linked migration history, schema inventory, advisors, grants, Edge Function inventory, admin UAT, and SMS-first rollback UAT pass. |
| `scripts/flutter_mobile_release_gate.sh --json` | Blocked | APK/AAB artifacts are current; signing review and iOS scope remain pending. |
| `scripts/release_artifact_manifest.sh --json` | Pass | Manifest wrote `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-31.sha256`. |

## QA Findings

- P0: Android MoMo SMS consent, ingestion, parse, allocation, exception,
  and ledger UAT must be executed on a real Android device with sanitized
  evidence.
- P0: Admin PWA live URL proof is missing.
- P0: Stakeholder signoff is required for the corrected Groups product
  definition.
- P0: Android release signing review and iOS release-scope evidence are missing.
- P1: Worktree/release branch review is required before staging a release.
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

1. Deploy Admin PWA and rerun live gate with `ADMIN_PWA_LIVE_URL`.
2. Run Android SMS access UAT with real MoMo notification scenarios.
3. Record Android signing review and iOS scope evidence, then rerun release gates.
4. Record product and release-owner signoff.
5. Regenerate release evidence from current commands only.

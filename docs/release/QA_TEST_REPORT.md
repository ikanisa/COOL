# Collect QA Test Report

Audit date: 2026-05-27

Scope: SMS-first Groups refactor for the Flutter mobile app, Admin PWA,
Supabase schema/functions, payment-intent allocation, and release evidence.

## Decision

Current status: **NO-GO for public launch** until the linked Supabase project is
updated to the current SMS-first migration contract, Android SMS access UAT is
run with sanitized evidence, Admin PWA live deployment is proven, Android
release APK/AAB artifacts are rebuilt from current sources, and release owner
signoff is recorded.

Older Supabase platform blockers from the previous product definition are not
carried forward in this report. Any platform blocker must be reproduced by a
fresh readiness run after the SMS-first migration is deployed to the linked
project.

## Commands And Results

| Command | Result | Notes |
| --- | --- | --- |
| `git status --short` | Dirty | Large active refactor state. Public release still needs explicit worktree review and staging. |
| `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze` | Pass | Analyzer clean after the SMS-first app/admin refactor. |
| Full Flutter/release-doc suite | Pass | `79` tests passed across admin placeholders, app shell, phone/Public ID, widgets, persona smoke, repository, Supabase contract, and release-doc tests. |
| `scripts/admin_pwa_release_build.sh` | Pass | Built `build/web` for `lib/main_admin.dart` and passed Admin PWA manifest/hosting gates. |
| `scripts/admin_pwa_render_smoke.sh` | Pass | Runtime/render evidence written to `.cache/admin_pwa_render_smoke/20260527T041454Z-sms-first-current`; desktop and mobile screenshots are nonblank and show the Collect admin login. |
| `scripts/admin_pwa_live_gate.sh --json` | Blocked | `ADMIN_PWA_LIVE_URL` is missing; live deployment is not yet proven. |
| `scripts/collect_edge_auth_contract_uat.sh` | Pass | Local Edge Function auth contract passed. |
| `deno check supabase/functions/...` | Pass | `parse-payment-sms`, `ingest-payment-sms`, and `allocate-payment` type-check. |
| `./scripts/migrations/validate_supabase_migrations.sh` | Pass | Local migration validation passes. |
| `scripts/collect_admin_security_uat.sh` | Pass | Linked rollback UAT for admin RBAC, raw-SMS reveal audit logging, payment-event reparse permission, and denial paths passed. |
| `scripts/collect_linked_uat.sh` | Blocked/fail | Linked project is missing the current `create_group_with_owner` RPC. |
| `supabase db push --dry-run` | Blocked | Direct dry-run failed from this operator network with Supabase tenant database allowlist error `EADDRNOTALLOWED`. |
| `scripts/flutter_mobile_release_gate.sh --json` | Blocked | Existing production APK/AAB artifacts are stale against current Android/mobile sources; signing review and iOS scope also remain pending. |
| `scripts/release_artifact_manifest.sh --json` | Blocked | Manifest refuses stale Android APK/AAB artifacts. |

## QA Findings

- P0: Linked Supabase must receive the SMS-first migration, then linked
  contribution/allocation UAT must pass.
- P0: Android MoMo SMS consent, ingestion, parse, allocation, exception,
  and ledger UAT must be executed on a real Android device with sanitized
  evidence.
- P0: Admin PWA live URL proof is missing.
- P0: Stakeholder signoff is required for the corrected Groups product
  definition.
- P0: Android release APK/AAB artifacts must be rebuilt from current sources.
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

1. Apply/dry-run the SMS-first migration from a database-allowed network.
2. Rerun `scripts/collect_linked_uat.sh`.
3. Deploy Admin PWA and rerun live gate with `ADMIN_PWA_LIVE_URL`.
4. Run Android SMS access UAT with real MoMo notification scenarios.
5. Rebuild Android release APK/AAB artifacts and rerun release artifact gates.
6. Regenerate release evidence from current commands only.

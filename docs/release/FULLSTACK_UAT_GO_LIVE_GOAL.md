# Fullstack UAT And Go-Live Goal

Prepared: 2026-06-01

## Goal

Execute and evidence production readiness for the corrected Collect platform:
a Collect ID-only SMS-first Groups product for MoMo contributions. The work must
validate the Flutter mobile app, Admin PWA, Supabase database, Supabase Edge
Functions, SMS parsing/allocation, ledger behavior, RBAC, release evidence, and
human operator workflows.

## Required Product Boundary

- Use `Groups`, not goals or active goals.
- Bottom navigation is `Home`, `Groups`, and `Settings`.
- Never ask for real names or anonymity choices; users are represented by a
  generated 6-digit Collect ID.
- Profile owns MoMo number and Collect ID; group/contribution flows fetch from
  profile instead of asking repeatedly.
- Group creation is Android-only and uses name, optional description, and
  receiver MoMo synced from profile.
- iPhone group creation warning is exactly
  `group creation is available only on Android`.
- Contributions create Supabase payment intents and launch MoMo USSD through
  `tel:`.
- MoMo SMS ingestion, OpenAI parsing, allocation, exceptions, and ledger
  posting are automated through Supabase; there is no manual SMS paste or
  contributor-reported transaction ID fallback.
- Admin PWA monitors Groups, Members, Payment intents, SMS parsing,
  Allocations, Exceptions, Ledger, Receivers, SMS, Audit logs, Settings,
  Feature flags, System health, and Admin users.

## Current Evidence Snapshot

- `flutter analyze`: pass.
- Full Flutter/release-doc tests: pass with `101` tests.
- `scripts/admin_pwa_release_build.sh`: pass.
- `scripts/admin_pwa_render_smoke.sh`: pass with evidence at
  `.cache/repo_wide_qa_uat/20260601T205424Z/admin_pwa_render_smoke`.
- `scripts/mobile_route_render_smoke.sh`: pass with retained 390x844
  screenshots and JSON nonblank checks at
  `.cache/mobile_route_render_smoke/20260602T040433Z`.
- `scripts/collect_edge_auth_contract_uat.sh`: pass.
- `deno check` for parser/ingestion/allocation functions: pass.
- `./scripts/migrations/validate_supabase_migrations.sh`: pass.
- `scripts/collect_admin_security_uat.sh`: pass through linked database query.
- `scripts/collect_linked_uat.sh`: pass after applying
  `supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql`
  through the linked Supabase query path.
- `scripts/supabase_production_readiness.sh`: pass.
- `scripts/supabase_go_live_gate.sh --json`: blocked on remaining approval,
  device-UAT, and release-scope gates.
- `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev ./scripts/admin_pwa_live_gate.sh --json`: pass.
- `scripts/flutter_mobile_release_gate.sh --json`: APK/AAB freshness and
  signature checks pass; blocked on Android release signing review and iOS
  release scope approval.
- `scripts/release_artifact_manifest.sh --json`: pass with current APK/AAB and
  Admin PWA artifacts.

## Required UAT

| Persona | Journey |
| --- | --- |
| Contributor | Open group, contribute amount, create payment intent, launch MoMo USSD, receive automated allocation/ledger confirmation. |
| Android creator | Complete profile, create group, grant SMS access, share link/QR/deep link/SMS. |
| iPhone user | Attempt group creation and see the exact Android-only warning. |
| Group member | Join/open shared group and contribute using Collect ID. |
| Android SMS device | Receive MoMo SMS and confirm automatic upload, parse, allocation, exception behavior, and no public raw SMS exposure. |
| Admin operator | Monitor groups, payment intents, SMS parsing, allocations, exceptions, ledger, and audit. |
| Payments admin | Handle ambiguous parsed event through reason-required reparse/review, not manual ledger posting. |
| Compliance admin | Reveal raw SMS only through permission-gated, reason-required, audited flow. |
| Non-admin | Confirm protected admin routes/RPCs deny access. |
| Edge-case user | Test invalid amount, expired intent, ambiguous amount, missing receiver authorization, failed Edge Function auth, and retry/idempotency. |

## GO Criteria

1. Corrected product definition is signed off.
2. Real Android SMS access UAT passes with sanitized evidence.
3. Android signing review and iOS release scope evidence pass release gates.
4. Release owner signs current evidence packet and worktree review.

Until all criteria pass, decision remains **NO-GO**.

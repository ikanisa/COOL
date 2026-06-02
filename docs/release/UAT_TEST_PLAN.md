# Collect UAT Test Plan

Audit date: 2026-06-02

Decision context: **NO-GO pending human approvals, Android SMS scenario
approval, Android signing review, iOS scope decision, and release-owner
signoff**.

This plan covers the corrected SMS-first Groups product definition. It excludes old
goals, campaign/public-directory flows, manual SMS paste, self-reported payment
IDs, and anonymity choices.

## Current Automated Evidence To Attach

- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze`: pass.
- Full Flutter/release-doc tests: `101` tests pass.
- `scripts/admin_pwa_release_build.sh`: pass.
- `scripts/admin_pwa_render_smoke.sh`: pass, evidence at
  `.cache/admin_pwa_render_smoke/20260602T081408Z`.
- `scripts/mobile_route_render_smoke.sh`: pass, evidence at
  `.cache/mobile_route_render_smoke/20260602T082935Z`.
- `scripts/collect_edge_auth_contract_uat.sh`: pass.
- `./scripts/migrations/validate_supabase_migrations.sh`: pass.
- `scripts/collect_admin_security_uat.sh`: pass.
- `scripts/collect_linked_uat.sh`: pass after applying
  `supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql`
  through the linked Supabase query path.
- `scripts/supabase_production_readiness.sh`: pass.
- `scripts/supabase_go_live_gate.sh --json`: NO-GO on remaining approval,
  device-UAT, and release-scope blockers.

Current blocked evidence:

- `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev ./scripts/admin_pwa_live_gate.sh --json`: pass.
- Production-flavor Pixel smoke passed at
  `.cache/android_device_uat/20260602T042542Z/summary.json`; real MoMo SMS
  scenario UAT is still pending.
- Android release signing, iOS scope, product signoff, and release-owner signoff
  are pending.

## Persona Tests

| ID | Persona | Steps | Expected | Automated evidence | Status |
| --- | --- | --- | --- | --- | --- |
| UAT-01 | Contributor | Open shared group, enter amount, tap Contribute, create intent, launch MoMo USSD. | Intent is linked to group, user id, Collect ID, amount, receiver, and contributor sender hash; no manual payment report is shown. | Local tests, mobile route render, and linked rollback UAT. | Automated/backend pass; real Android MoMo SMS scenario approval pending. |
| UAT-02 | Android creator | Complete profile, create group, grant SMS access, share link/QR/deep link/SMS. | Receiver MoMo syncs from profile and is editable; SMS consent starts automated MoMo SMS capture. | Local tests and mobile route render. | Automated local pass; Android walkthrough signoff pending. |
| UAT-03 | iPhone user | Tap group creation action. | Warning is exactly `group creation is available only on Android`. | Widget tests and mobile route render. | Automated local pass; iOS release-scope decision pending. |
| UAT-04 | Member | Join/open group through share link and contribute with Collect ID-only identity. | User is identified only by Collect ID. | Local tests, mobile route render, and repository contract. | Automated local pass; shared-link human walkthrough pending. |
| UAT-05 | Android SMS device | Receive MoMo SMS and allow automatic sync. | SMS row reaches Supabase, parser extracts payment fields and Collect ID when present, allocation runs automatically. | Edge/type checks and linked rollback UAT. | Device scenario approval pending; production-flavor Pixel smoke passed. |
| UAT-06 | Admin operator | Monitor groups, intents, SMS parsing, allocations, exceptions, ledger, and audit. | Admin sees operational state without raw SMS by default. | Admin PWA local render, live gate, and linked admin/security UAT. | Admin proof pass; human admin walkthrough/signoff pending. |
| UAT-07 | Payments admin | Handle ambiguous event. | Reparse/review actions are reason-required and audited; no manual ledger posting shortcut. | Linked admin/security UAT and Admin PWA live gate. | Linked/admin proof pass; human payments-admin signoff pending. |
| UAT-08 | Compliance admin | Reveal raw SMS through controlled path. | Raw SMS reveal is permission-gated, reason-required, and audited. | Linked admin/security UAT and Admin PWA live gate. | Linked/admin proof pass; sanitized compliance-admin signoff pending. |
| UAT-09 | Non-admin | Attempt protected admin access. | Access is denied without sensitive data leakage. | Linked admin/security UAT and Admin PWA live gate. | Linked/admin proof pass; live UI denial signoff pending. |
| UAT-10 | Edge case | Invalid amount, expired intent, ambiguous amount, missing receiver authorization, failed Edge auth. | Invalid/ambiguous/expired cases stay unposted or go to exception; auth failures return safe errors. | Unit/contract tests, mobile route render, Edge auth UAT, and linked rollback UAT. | Automated/backend pass; real Android MoMo SMS edge evidence pending. |

## Minimum GO Evidence

1. Product definition signoff recorded.
2. Linked Supabase migration and `scripts/collect_linked_uat.sh` pass remain
   current.
3. Android SMS access UAT passes with sanitized screenshots/logs and reviewer
   approval.
4. Admin PWA deployed URL passes live gate and any required admin walkthrough is
   signed off.
5. Android signing review and iOS release-scope decision are recorded.
6. Release owner approves the current release packet.

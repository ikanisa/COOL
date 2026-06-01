# Collect UAT Test Plan

Audit date: 2026-05-31

Decision context: **NO-GO pending current SMS-first evidence**.

This plan covers the corrected Groups product definition. It excludes old
goals, campaign/public-directory flows, manual SMS paste, self-reported payment
IDs, and anonymity choices.

## Current Automated Evidence To Attach

- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze`: pass.
- Full Flutter/release-doc tests: `101` tests pass.
- `scripts/admin_pwa_release_build.sh`: pass.
- `scripts/admin_pwa_render_smoke.sh`: pass, evidence at
  `.cache/admin_pwa_render_smoke/20260527T041454Z-sms-first-current`.
- `scripts/collect_edge_auth_contract_uat.sh`: pass.
- `./scripts/migrations/validate_supabase_migrations.sh`: pass.
- `scripts/collect_admin_security_uat.sh`: pass.
- `scripts/collect_linked_uat.sh`: pass via linked database query.
- `scripts/supabase_production_readiness.sh`: pass.

Current blocked evidence:

- `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev ./scripts/admin_pwa_live_gate.sh --json`: pass.
- Real Android SMS device UAT is pending.
- Android release signing, iOS scope, product signoff, and release-owner signoff
  are pending.

## Persona Tests

| ID | Persona | Steps | Expected | Automated evidence | Status |
| --- | --- | --- | --- | --- | --- |
| UAT-01 | Contributor | Open shared group, enter amount, tap Contribute, create intent, launch MoMo USSD. | Intent is linked to group, user id, Collect ID, amount, and receiver; no manual payment report is shown. | Local tests; linked rollback UAT. | Backend pass; device UAT pending. |
| UAT-02 | Android creator | Complete profile, create group, grant SMS access, share link/QR/deep link/SMS. | Receiver MoMo syncs from profile and is editable; SMS consent starts automated MoMo SMS capture. | Local tests. | Partial. |
| UAT-03 | iPhone user | Tap group creation action. | Warning is exactly `group creation is available only on Android`. | Widget tests. | Partial. |
| UAT-04 | Member | Join/open group through share link and contribute with Collect ID-only identity. | User is identified only by Collect ID. | Local tests. | Partial. |
| UAT-05 | Android SMS device | Receive MoMo SMS and allow automatic sync. | SMS row reaches Supabase, parser extracts payment fields and Collect ID when present, allocation runs automatically. | Edge/type checks; physical Android UAT pending. | Pending. |
| UAT-06 | Admin operator | Monitor groups, intents, SMS parsing, allocations, exceptions, ledger, and audit. | Admin sees operational state without raw SMS by default. | Admin PWA local render and linked admin/security UAT. | Partial. |
| UAT-07 | Payments admin | Handle ambiguous event. | Reparse/review actions are reason-required and audited; no manual ledger posting shortcut. | Linked admin/security UAT. | Partial. |
| UAT-08 | Compliance admin | Reveal raw SMS through controlled path. | Raw SMS reveal is permission-gated, reason-required, and audited. | Linked admin/security UAT. | Partial. |
| UAT-09 | Non-admin | Attempt protected admin access. | Access is denied without sensitive data leakage. | Linked admin/security UAT. | Partial. |
| UAT-10 | Edge case | Invalid amount, expired intent, ambiguous amount, missing receiver authorization, failed Edge auth. | Invalid/ambiguous/expired cases stay unposted or go to exception; auth failures return safe errors. | Unit/contract tests; linked rollback UAT. | Backend pass; device UAT pending. |

## Minimum GO Evidence

1. Product definition signoff recorded.
2. Linked Supabase migration applied and `scripts/collect_linked_uat.sh` passes.
3. Android SMS access UAT passes with sanitized screenshots/logs.
4. Admin PWA deployed URL passes live gate.
5. Release owner approves the current release packet.

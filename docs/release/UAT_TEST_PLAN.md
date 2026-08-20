# Collect UAT Test Plan

Audit date: 2026-08-05

Decision context: **NO-GO pending Google Play restricted-SMS approval, live
Android FCM evidence, Android SMS scenario evidence, Android signing review,
iOS scope evidence, and release-owner execution records**.

This plan covers the corrected SMS-first Groups product definition. It excludes old
goals, campaign/public-directory flows, manual SMS paste, self-reported payment
IDs, and anonymity choices.

## Current Automated Evidence To Attach

- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze`: pass.
- Flutter validation: 492 non-golden tests and 14 governed golden tests pass;
  the Deno Edge suite passes 11 tests.
- `scripts/admin_pwa_release_build.sh`: pass.
- `scripts/admin_pwa_render_smoke.sh`: pass, evidence at
  `.cache/admin_pwa_render_smoke/20260602T081408Z`.
- `scripts/mobile_route_render_smoke.sh`: pass, evidence at
  `.cache/mobile_route_render_smoke/20260602T210133Z`.
- `scripts/collect_edge_auth_contract_uat.sh`: pass.
- `./scripts/migrations/validate_supabase_migrations.sh`: pass.
- `scripts/collect_admin_security_uat.sh`: pass.
- `scripts/collect_linked_uat.sh`: pass after applying
  `supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql`
  through the linked Supabase query path.
- `scripts/supabase_production_readiness.sh`: migration, schema, RLS,
  privilege, advisor, Edge and rollback UAT gates pass; strict readiness fails
  closed on missing FCM and Stripe provider secrets.
- `scripts/supabase_go_live_gate.sh --json`: NO-GO on remaining approval,
  device-UAT, and release-scope blockers.

Current blocked evidence:

- `https://admin.collect.ikanisa.com`: deployed version
  `ff6801b3-447d-45d0-8d50-f5369dcbce2d` passes the live gate and exact bundle
  hash readback.
- Production-flavor Pixel smoke passed at
  `.cache/android_device_uat/20260602T042542Z/summary.json`; real MoMo SMS
  scenario UAT is still pending.
- The 2026-08-05 implementation adds production-scoped `RECEIVE_SMS` without
  `READ_SMS`, native permission/settings recovery, encrypted acknowledged
  queuing, Android notification channels, and FCM HTTP v1 transport. These are
  implementation/compile assertions until the current device and live-service
  evidence packet is attached.
- Google Play restricted-permission declaration approval and live Firebase
  server credentials/delivery evidence are pending. The deployed Stripe
  functions also require governed `STRIPE_SECRET_KEY` and
  `STRIPE_WEBHOOK_SECRET`, or an explicit release-scope exclusion.
- Android release signing, iOS scope, product signoff, and release-owner signoff
  are pending.

Use the guarded Android SMS recorder for real-device scenario evidence before
requesting UAT-05 signoff:

```bash
make record-android-sms-uat-evidence ARGS="--tester '<name>' --tested-at '<ISO-8601 UTC timestamp>' --device-label 'Pixel 4a UAT device' --scenarios consent,foreground_sms,background_sms,killed_app_sms,offline_retry,parser_allocation,exception_review,ledger_posting,balance_reconciliation,privacy --evidence-summary '<sanitized scenario summary>' --sanitized-evidence --no-production-customer-data --raw-sms-not-public --no-phone-or-momo --no-transaction-ids --balances-reconciled"
```

Financial evidence boundary: reconcile one raw receipt, one OpenAI parsed
event, one exact matched intent and payer, one posted payment, one group credit,
one payer credit, and the resulting group and payer balances.

## Persona Tests

| ID | Persona | Steps | Expected | Automated evidence | Status |
| --- | --- | --- | --- | --- | --- |
| UAT-01 | Contributor | Open shared group, enter amount, tap Contribute, create intent, launch MoMo USSD. | Intent is linked to group, user id, Collect ID, amount, receiver, and contributor sender hash; no manual payment report is shown. | Local tests, mobile route render, and linked rollback UAT. | Automated/backend pass; real Android MoMo SMS scenario approval pending. |
| UAT-02 | Android creator | Complete profile, create group, grant SMS access, share link/QR/deep link/SMS. | Receiver MoMo syncs from profile and is editable; SMS consent starts automated MoMo SMS capture. | Local tests and mobile route render. | Automated local pass; Android walkthrough signoff pending. |
| UAT-03 | iPhone user | Tap group creation action. | Warning is exactly `group creation is available only on Android`. | Widget tests and mobile route render. | Automated local pass; iOS release-scope decision pending. |
| UAT-04 | Member | Join/open group through share link and contribute with Collect ID-only identity. | User is identified only by Collect ID. | Local tests, mobile route render, and repository contract. | Automated local pass; shared-link human walkthrough pending. |
| UAT-05 | Android SMS device | Receive MoMo SMS and allow automatic sync. | SMS reaches Supabase, OpenAI extracts payment facts, one exact match posts the transaction and balanced ledger pair once, and payer/group balances reconcile; incomplete or ambiguous events stay in review. | Edge/type checks and linked rollback UAT. | Physical device scenario pending; production-flavor Pixel smoke passed. |
| UAT-06 | Admin operator | Monitor groups, intents, SMS parsing, allocations, exceptions, ledger, and audit. | Admin sees operational state without raw SMS by default. | Admin PWA local render, live gate, and linked admin/security UAT. | Admin proof pass; human admin walkthrough/signoff pending. |
| UAT-07 | Payments admin | Handle ambiguous event. | Reparse/review actions are reason-required and audited; no manual ledger posting shortcut. | Linked admin/security UAT and Admin PWA live gate. | Linked/admin proof pass; human payments-admin signoff pending. |
| UAT-08 | Compliance admin | Reveal raw SMS through controlled path. | Raw SMS reveal is permission-gated, reason-required, and audited. | Linked admin/security UAT and Admin PWA live gate. | Linked/admin proof pass; sanitized compliance-admin signoff pending. |
| UAT-09 | Non-admin | Attempt protected admin access. | Access is denied without sensitive data leakage. | Linked admin/security UAT and Admin PWA live gate. | Linked/admin proof pass; live UI denial signoff pending. |
| UAT-10 | Edge case | Invalid amount, expired intent, ambiguous amount, missing receiver authorization, failed Edge auth. | Invalid/ambiguous/expired cases stay unposted or go to exception; auth failures return safe errors. | Unit/contract tests, mobile route render, Edge auth UAT, and linked rollback UAT. | Automated/backend pass; real Android MoMo SMS edge evidence pending. |

## Minimum GO Evidence

1. Product definition signoff recorded.
2. Linked Supabase migration and `scripts/collect_linked_uat.sh` pass remain
   current.
3. Google Play approves the restricted SMS permission declaration and Android
   SMS access UAT passes with sanitized screenshots/logs and reviewer approval.
4. Admin PWA deployed URL passes live gate and any required admin walkthrough is
   signed off.
5. Android signing review and iOS release-scope decision are recorded.
6. Android FCM foreground, background, and notification-tap delivery passes
   with production server credentials and sanitized evidence.
7. Release owner approves the current release packet.

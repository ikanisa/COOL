# Collect UAT Execution Report

Audit date: 2026-06-02

Status: **AUTOMATED LOCAL, LINKED BACKEND, DEVICE SMOKE, AND ADMIN LIVE GATES
PASS; HUMAN RELEASE SIGNOFF PENDING**

Public launch remains **NO-GO** until real Android SMS access UAT is captured,
Android signing/iOS scope evidence is recorded, and stakeholder/release-owner
signoff is recorded.

## Build And Runtime Evidence

| Surface | Evidence | Result |
| --- | --- | --- |
| Flutter hygiene | `flutter analyze`; full Flutter/release-doc tests | Pass: analyzer clean; full local suite passed `101` tests. |
| Mobile route/widget smoke | Focused app shell, widgets, persona, repository, and phone/Public ID tests | Pass: current tests cover Home/Groups/Settings, group contribution copy, international phone normalization, and SMS-first product text. |
| Admin PWA local release/render | `scripts/admin_pwa_release_build.sh`; `scripts/admin_pwa_render_smoke.sh` | Pass: build, manifest/hosting gates, desktop/mobile screenshots, service-worker runtime, and asset checks passed. |
| Admin PWA live deployment | `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev ./scripts/admin_pwa_live_gate.sh --json` | Pass. |
| Edge Function auth contract | `scripts/collect_edge_auth_contract_uat.sh` | Pass. |
| Edge Function type-check | `deno check` for parser/ingestion/allocation functions | Pass. |
| Local Supabase migration validation | `./scripts/migrations/validate_supabase_migrations.sh` | Pass. |
| Linked admin/security UAT | `scripts/collect_admin_security_uat.sh` | Pass: admin RBAC, raw-SMS reveal audit, reparse permission, and denial paths verified in rollback. |
| Linked SMS-first contribution UAT | `scripts/collect_linked_uat.sh` | Pass: linked rollback UAT stores contributor sender hash and covers allocation edge cases. |
| Supabase readiness | `scripts/supabase_production_readiness.sh` | Pass: migration history, schema inventory, RLS, SQL privileges, linked UAT, admin/security UAT, Edge auth/deployment, secret names, and platform checks completed. |
| Supabase release gate | `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev ./scripts/supabase_go_live_gate.sh --json` | NO-GO on product signoff, Android SMS UAT, Android signing review, iOS scope, and release-owner signoff. |
| Real Android SMS access flow | Physical Android device with MoMo SMS scenarios | Pending real MoMo SMS scenario approval; production-flavor Pixel smoke passed at `.cache/android_device_uat/20260602T042542Z/summary.json`. |
| Android release artifacts | `scripts/release_artifact_manifest.sh --json` | Pass: current APK/AAB and Admin PWA artifacts are fresh. |
| Android signing / iOS scope | `scripts/flutter_mobile_release_gate.sh --json` | Blocked: APK/AAB signatures verify, but signing review and iOS release-scope approval are missing. |

## Persona Matrix

| ID | Persona | Required journey | Current evidence | Result | Remaining action |
| --- | --- | --- | --- | --- | --- |
| UAT-01 | Contributor | Open group, enter amount, create payment intent, launch MoMo USSD, and wait for SMS allocation. | Local repository/widget tests, mobile route render, and linked rollback UAT pass. | Automated/backend pass | Run live tester flow with real Android SMS evidence and approval. |
| UAT-02 | Android creator | Create group with profile-synced receiver MoMo and share link/QR/deep link/SMS. | Local UI/contract tests and mobile route render pass. | Automated local pass | Run Android walkthrough with SMS permission and share evidence. |
| UAT-03 | iPhone user | Tap inactive group creation action. | Widget tests verify warning copy; mobile route render covers the restricted creation path. | Automated local pass | Record iOS release-scope decision if iOS is included, or out-of-scope decision if Android-only. |
| UAT-04 | Group member | Join/open shared group and contribute using profile Collect ID. | Local tests, mobile route render, and repository contract pass. | Automated local pass | Complete shared-link human walkthrough against linked/staging if required by release owner. |
| UAT-05 | Android SMS device | Grant Android SMS access and allow automatic SMS upload. | Edge/auth contracts and linked rollback UAT pass; production-flavor Pixel smoke passed. | Device scenario approval pending | Run physical Android MoMo SMS access UAT. |
| UAT-06 | Admin operator | Monitor SMS parsing, allocations, exceptions, and ledger. | Admin PWA local render, live gate, and linked admin/security rollback UAT pass. | Admin proof pass | Complete human admin walkthrough/signoff. |
| UAT-07 | Payments admin | Review ambiguous parsed event and request reparse with reason. | Linked admin/security UAT passes and Admin PWA is live. | Linked/admin proof pass | Confirm with human payments-admin signoff. |
| UAT-08 | Compliance admin | Reveal raw SMS through permission-gated audited path. | Linked admin/security UAT passes and Admin PWA is live. | Linked/admin proof pass | Confirm with sanitized compliance-admin signoff. |
| UAT-09 | Non-admin | Attempt protected admin routes/functions. | Linked admin/security UAT covers denial paths and Admin PWA is live. | Linked/admin proof pass | Confirm UI denial in live Admin PWA if required by release owner. |
| UAT-10 | Edge-case user | Invalid amount, expired intent, ambiguous amount, missing receiver authorization, failed auth. | Unit/contract tests, mobile route render, Edge auth UAT, and linked rollback UAT pass. | Automated/backend pass | Capture physical Android MoMo SMS edge evidence where device scenarios are required. |

## Test Data Policy

Use synthetic users, synthetic MoMo/SMS data, hashed or masked phone values, and
rollback transactions wherever possible. Evidence must not expose raw SMS,
MoMo numbers, user phone numbers, service-role keys, OpenAI keys, WhatsApp/SMS
hook secrets, provider secrets, or production customer data.

## Remaining Launch Preconditions

1. Stakeholder signoff on the corrected product definition.
2. Run physical Android SMS access UAT with sanitized evidence.
3. Record Android signing review and iOS release scope evidence.
4. Refresh release evidence and release-owner signoff from current commands
   only.

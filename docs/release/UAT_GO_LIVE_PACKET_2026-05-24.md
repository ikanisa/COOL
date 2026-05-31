# Collect UAT And Go-Live Packet

Prepared: 2026-05-31

Decision: **NO-GO**

## Scope

This packet covers the corrected Collect product: Collect ID-only SMS-first Groups
for MoMo contributions, Flutter mobile app, Flutter Admin PWA, Supabase schema
and Edge Functions, payment-intent allocation, release evidence, and operator
UAT.

## Product Contract Under Test

- Users authenticate with WhatsApp-capable international phone numbers.
- Profile owns MoMo number and a generated 6-digit Collect ID.
- Mobile navigation is `Home`, `Groups`, and `Settings`.
- Android users can create groups; iPhone group creation shows exactly
  `group creation is available only on Android`.
- Group creation asks for group name, optional description, and receiver MoMo
  synced from profile with edit support.
- Members share groups through links, QR codes, deep links, chat apps, or SMS.
- Contribution creates a Supabase payment intent and opens MoMo USSD with
  `tel:`.
- Receiver Android SMS is uploaded to Supabase, parsed by Edge Functions/OpenAI,
  allocated against payment intents, and posted to the ledger when unambiguous.
- Admin PWA monitors groups, members, payment intents, SMS parsing,
  allocations, exceptions, ledger, receivers, audit logs, settings, feature
  flags, system health, and admin users.

## Command Evidence

| Area | Command | Result |
| --- | --- | --- |
| Analyze | `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze` | Pass. |
| Flutter tests | Full Flutter/release-doc suite | Pass: `78` tests. |
| Admin PWA build | `scripts/admin_pwa_release_build.sh` | Pass. |
| Admin PWA render | `scripts/admin_pwa_render_smoke.sh` | Pass; evidence at `.cache/admin_pwa_render_smoke/20260527T041454Z-sms-first-current`. |
| Admin PWA live | `scripts/admin_pwa_live_gate.sh --json` | Blocked: `ADMIN_PWA_LIVE_URL` missing. |
| Migration validation | `./scripts/migrations/validate_supabase_migrations.sh` | Pass. |
| Edge auth UAT | `scripts/collect_edge_auth_contract_uat.sh` | Pass. |
| Edge type-check | `deno check` parser/ingestion/allocation functions | Pass. |
| Admin/security UAT | `scripts/collect_admin_security_uat.sh` | Pass through linked database query mode. |
| Linked contribution UAT | `scripts/collect_linked_uat.sh` | Blocked/fail: linked database is missing `create_group_with_owner`. |
| Migration dry-run | `supabase db push --dry-run` | Blocked by database allowlist from current operator IP. |
| Android release gate | `scripts/flutter_mobile_release_gate.sh --json` | Blocked: signing review and iOS release scope. |
| Release artifact manifest | `scripts/release_artifact_manifest.sh --json` | Pass: current APK/AAB and Admin PWA artifacts are fresh; manifest written for 2026-05-31. |

## Device And Browser Matrix

| Target | Status | Release interpretation |
| --- | --- | --- |
| Flutter local tests | Pass | Local route, UI, repository, and contract coverage is green. |
| Admin PWA local Chrome render | Pass | Desktop and mobile screenshots are nonblank and show Collect admin login. |
| Admin PWA live URL | Blocked | Must be deployed and checked with `ADMIN_PWA_LIVE_URL`. |
| Android SMS access device | Pending | Real SMS access, ingestion, parse, allocation, and ledger evidence is required. |
| Android release APK/AAB | Pass | Release artifacts are current; signing and iOS scope evidence remain blocked. |
| iOS release scope | Pending | Since group creation is Android-only, iOS must either be scoped out for creator flows or separately signed off for contributor-only use. |

## Test Data Ledger

Use synthetic or sanitized data only. Evidence must not expose raw SMS, MoMo
numbers, phone numbers, service-role keys, OpenAI keys, WhatsApp/SMS hook
secrets, provider secrets, or production customer data.

## Risk Register

| Risk | Status | Action |
| --- | --- | --- |
| Linked Supabase behind local migration | Open P0 | Apply/dry-run migration from allowed DB network and rerun linked UAT. |
| Android MoMo SMS not freshly evidenced | Open P0 | Run controlled physical Android UAT. |
| Admin PWA not proven live | Open P0 | Deploy and pass live gate. |
| Android release signing / iOS scope | Open P0 | Record signing review and iOS scope evidence, then rerun release gates. |
| Product signoff missing | Open P0 | Approve corrected product definition. |
| Dirty worktree | Open P1 | Review/stage intended changes only. |

## Final GO Criteria

1. Stakeholder signs off corrected Groups product definition.
2. Linked SMS-first migration is applied and linked contribution UAT passes.
3. Physical Android SMS access UAT passes with sanitized evidence.
4. Admin PWA deployed URL passes live gate.
5. Android signing review and iOS release scope evidence pass release gates.
6. Release owner approves current packet and worktree/release branch.

Older evidence that refers to public campaigns, active goals, manual SMS paste,
manual transaction reporting, anonymity choices, or previous Supabase platform
blockers is historical and not used for current GO approval.

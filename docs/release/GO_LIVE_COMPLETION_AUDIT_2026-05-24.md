# Collect Go-Live Completion Audit

Audit date: 2026-05-24

Decision: **NO-GO**

This audit maps the active fullstack UAT/go-live objective to current evidence.
It does not replace the go-live packet; it is the requirement-by-requirement
completion check used to prevent a narrow green test from being treated as
production approval.

## Evidence Baseline

| Evidence | Current result |
| --- | --- |
| Flutter SDK | Flutter `3.44.0`, Dart `3.12.0`. |
| Format/analyze/tests | Format clean, `flutter analyze --no-pub` clean, `flutter test --no-pub --concurrency=1` passes `79` tests. |
| Android device smoke UAT | Earlier `2`-test launch/admin-boundary smoke passed on `Pixel_5_API_34_Lite`; expanded persona harness is implemented but current device rerun is blocked by emulator/simulator availability. |
| Android release artifacts | APK and AAB were built with JDK 17 Gradle release commands. |
| Admin web artifact | `build/web/main.dart.js` built from `lib/main_admin.dart`. |
| Supabase evidence bundle | `.cache/supabase_go_live_evidence/20260524T085150Z`. |
| Supabase acceptance matrix | `7` pass / `5` blocked; overall status `blocked`. |
| Latest release status | `NO-GO`, blocker key `database_connectivity`; platform controls are `unknown` in this latest runner. |
| Latest go-live gate | `NO-GO`, `go_live_approved=false`, blocker key `database_connectivity`. |
| Edge Function auth contract | `make supabase-edge-auth-uat` passes locally; remote endpoint and secret-name probes are blocked by `database_connectivity`. |

## Requirement Audit

| Requirement | Evidence status | Authoritative evidence | Gap or next action |
| --- | --- | --- | --- |
| Refresh non-destructive Flutter/Dart preflight evidence. | Proven | Flutter/Dart version, format, analyzer, and full test outputs recorded in the packet and latest test runs. | Keep rerunning after source, dependency, or build-config changes. |
| Fix analyzer hygiene blocker at `test/supabase_contract_test.dart:299`. | Proven | Analyzer is clean; full test suite passes. | None. |
| Add or scope device-level UAT automation. | Partially proven | `integration_test/app_uat_smoke_test.dart` exists, includes launch/admin-boundary smoke plus public supporter, contributor, creator share/invite, receiver/manual-SMS, and authorized admin moderator/payments/compliance/audit/system-health smoke paths, and is analyzer-clean. `test/persona_uat_smoke_test.dart` passes the same route/privacy/admin scope in the normal Flutter test suite. Earlier Android evidence passed the 2-test smoke. Current expanded device rerun is blocked because the Android emulator disappeared from ADB/Flutter and the iOS simulator stalled at BackBoard. | Restore stable Android or iOS simulator/device execution and rerun the expanded suite before device or full persona release claims. |
| Produce Android and admin web release artifacts. | Proven | APK, AAB, and admin web artifact paths are listed in the packet. | Release owner must still review signing/staging before distribution. |
| Execute ten persona UAT journeys. | Not complete | `docs/release/UAT_EXECUTION_REPORT.md`, `UAT_TEST_PLAN.md`, and `UAT_SIGNOFF_CHECKLIST_2026-05-24.md` map all ten personas. | Human persona signoff remains pending for contributor, creator, recurring admin, public supporter, receiver/SMS operator, moderator, payments admin, compliance admin, non-admin, and edge-case user. |
| Verify auth, public/private collection, public directory, contribution, MOMO instruction, QR/share/invite, SMS, parsing, allocation, ledger, raw-SMS reveal, moderation, role denial, audit logging, and system health. | Partially proven | Static/unit tests, `test/persona_uat_smoke_test.dart`, earlier Android launch/admin-boundary smoke UAT, expanded analyzer-clean integration harness, linked rollback UAT scripts, admin/security UAT script, operational report, and UAT report. | Trusted DB rerun, stable-device expanded integration run, and human persona walkthroughs are still required before GO. |
| Verify edge cases: duplicate SMS/transaction, invalid amount, non-Rwanda phone, expired intent, ambiguous amount, missing receiver authorization, failed Edge Function auth, retry/idempotency, and no raw SMS/phone/MOMO/secret leakage. | Partially proven | `scripts/collect_linked_uat.sh`, `scripts/collect_edge_auth_contract_uat.sh`, `test/core/phone_and_public_id_test.dart`, `test/shared/collect_repository_test.dart`, and `test/supabase_contract_test.dart`. | Linked DB edge cases need trusted/allow-listed rerun; human edge-case signoff remains pending. |
| Validate Supabase schema contract, RLS, function search path, advisors, operational report, and secret hygiene. | Partially proven | Latest bundle shows schema objects `160/160`, RLS `28/28`, functions with search path `57/57`, advisor warning inventory exit `0`, operational report exit `0`, and release secret scan exit `0`. | Full code-owned readiness cannot be finalized from this runner until `database_connectivity` is cleared. |
| Validate Edge Function auth/deployment/secret-name inventory. | Partially proven | Local Edge Function auth contract UAT passes and is included as `edge_auth_contract_uat.txt`. | Remote deployed endpoint and secret-name inventory probes are blocked by `database_connectivity`. |
| Preserve Flutter-visible secret boundary. | Proven by current tests | Security hygiene and release secret scan pass; tests reject obvious service-role, provider, JWT, database URL, and local-env leakage patterns. | Rerun scans after any config or release-build changes. |
| Treat admin client guards as convenience only and server-side RLS/RPC permissions as authoritative. | Partially proven | Supabase contract tests, admin/security UAT script, RLS inventory, RPC grants, and admin role tests. | Trusted DB rerun and human admin persona signoff remain required. |
| Resolve operator-owned Supabase blockers. | Not complete | Latest runner reports `database_connectivity`; earlier evidence showed CAPTCHA disabled, HIBP disabled, Free-plan organization, and PITR disabled. | Restore trusted DB verification, configure CAPTCHA, enable HIBP after plan upgrade, upgrade/exception plan risk, and enable/exception PITR after non-exceptionable blockers are fixed. |
| Produce final go-live packet with dated report, checklist, decision, blockers, evidence bundle path, artifacts, command summaries, device matrix, test data ledger, risk register, exceptions, rollback/incident plan, and exact next actions. | Partially proven | `UAT_GO_LIVE_PACKET_2026-05-24.md`, `UAT_EXECUTION_REPORT.md`, `PRODUCTION_READINESS_CHECKLIST.md`, `GO_NO_GO_DECISION.md`, `RELEASE_BLOCKERS.md`, and this audit. | Final packet must be regenerated/reviewed after platform blockers, trusted Supabase verification, and human signoff are complete. |
| Final GO criteria. | Not met | Latest `make supabase-go-live-gate-json` returns `go_live_approved=false`; human signoff pending. | GO only after Flutter hygiene remains green, persona UAT is signed, Supabase code-owned readiness passes from trusted connectivity, platform blockers are resolved or validly exceptioned where allowed, and the final gate approves. |

## Current Blocking Keys

- `database_connectivity`
- `auth_captcha_bot_protection` from earlier evidence; non-exceptionable
- `auth_hibp_leaked_password_protection` from earlier evidence; non-exceptionable
- `supabase_organization_plan` from earlier evidence; exceptionable only after non-exceptionable blockers are resolved
- `supabase_pitr` from earlier evidence; exceptionable only after non-exceptionable blockers are resolved
- human persona UAT signoff pending

## Completion Decision

The objective is not complete. The release remains **NO-GO** because the latest
Supabase release gate cannot complete trusted Postgres verification, the final
go-live gate is not approved, platform blockers remain unresolved or
unrefreshed, and human persona UAT signoff is not recorded.

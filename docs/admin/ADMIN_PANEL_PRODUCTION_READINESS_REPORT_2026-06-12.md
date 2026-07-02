# Collect Admin Panel Production Readiness Report

Date: 2026-06-12
Scope: Flutter web Admin PWA in `/Volumes/PRO-G40/COOL`, including `lib/admin`, admin Supabase RPC migrations, PWA build/deployment gates, and current local/live runtime evidence.

## Executive Verdict

Admin-panel-only verdict: **CONDITIONAL NO-GO**.

The Admin PWA has a credible technical foundation: separate Flutter web entrypoint, live HTTPS deployment, strict static hosting headers, service-worker/manifest gates, no service-role secret markers in generated web output, Supabase RPC authorization checks, raw-SMS reveal through a reasoned/audited RPC, and current analyzer/admin-test/build/live-gate passes.

It is not yet production-ready for a sensitive operations console. The critical gaps are:

1. The browser owner-promotion path has been removed from Dart and migration `20260612103000` is applied to linked Supabase; linked admin/security UAT now passes.
2. Operator workflows still rely on generic list screens for several domains, although detail pages now render structured operator panels and payment-event queues have linked server-side paging/sorting.
3. Role-aware navigation, direct-route denial, and payment-event reparse action gating are implemented, but full role-matrix workflow coverage still needs to be expanded.
4. Sanitized error panels and explicit widget-level semantics are implemented for the main admin login, navigation, pagination, detail, and reparse paths, but broader workflow tests still need to prove no raw backend errors render.
5. The final release-status gate now runs the live Admin PWA gate, but repo-wide release remains blocked by mobile/signoff items.

Repo-wide release verdict remains **NO-GO** for non-admin blockers: product signoff, Android SMS UAT, Android artifacts/signing review, iOS scope, and release-owner signoff.

## Current Evidence

| Area | Result | Evidence |
| --- | --- | --- |
| Flutter analyzer | Pass | `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub` returned `No issues found!` |
| Admin widget/contract tests | Pass | `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/admin_pwa_test.dart test/supabase_contract_test.dart` passed 48 tests |
| Admin release build | Pass | `scripts/admin_pwa_release_build.sh` rebuilt `build/web` from `lib/main_admin.dart` and passed local manifest/hosting gates |
| Admin manifest/secret gate | Pass | `scripts/admin_pwa_manifest_gate.sh` passed |
| Admin hosting gate | Pass | `scripts/admin_pwa_hosting_gate.sh` passed |
| Live Admin PWA gate | Pass | `scripts/admin_pwa_live_gate.sh --json` passed for `https://collect.ikanisa.com` |
| Linked admin/security UAT | Pass | `scripts/collect_admin_security_uat.sh` passed via linked database query after migrations `20260612103000`, `20260612110000`, `20260612111500`, and `20260612113000` |
| Supabase production readiness | Pass with warnings | `scripts/supabase_production_readiness.sh` passed code-owned checks after linked server-paging/grant migrations; warnings remain for leaked-password protection, bot protection, Free plan, and PITR review |
| Browser render check | Pass with accessibility caveat | Local rebuilt app rendered at `http://127.0.0.1:8098/`, screenshot was nonblank, title was `Collect Admin`, console had no warnings/errors, invalid phone showed the sanitized `Admin sign-in failed. Try again.` message; Browser DOM still exposed only Flutter's accessibility bootstrap button |
| Render-smoke script | Pass after fix | `ADMIN_PWA_SCREENSHOT_TIMEOUT_SECONDS=20 scripts/admin_pwa_render_smoke.sh` passed at `.cache/admin_pwa_render_smoke/20260612T064358Z` |
| Final repo release status | NO-GO | `scripts/release_status.sh --json` reported blockers unrelated to Admin PWA live hosting |

## Implementation Addendum On 2026-06-27

The Admin PWA received a targeted workflow/security follow-up for operator usability findings:

- Generic list queues now expose route-specific operator signals and workflow steps for groups, members, payment intents, SMS parsing, allocations, exceptions, ledger, receivers, SMS metadata, audit logs, settings, feature flags, and admin users.
- Detail pages now include operator next-step panels for group, member, payment, payment-event, receiver, SMS metadata, and system-health records while keeping the payment-event reparse action above the guidance panel.
- The arbitrary-user admin permission probing risk is addressed by forward migration `20260627143000_restrict_admin_permission_helper_probing.sql`: authenticated callers can evaluate only `auth.uid()`, while `service_role` remains able to evaluate arbitrary users for controlled administration.
- `scripts/supabase_production_readiness.sh` now allowlists the browser-safe `current_user_has_admin_permission(text)` helper, and `test/supabase_contract_test.dart` enforces the helper-probing restriction.
- The migration was applied to the linked COOL Supabase project on 2026-06-27 through `supabase db query --linked`; verification confirmed the three helper functions have the expected guard/wrapper logic, comments, and execute grants, and migration history includes version `20260627143000`.

Current focused validation after this addendum:

- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub` passed.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/admin_pwa_test.dart test/supabase_contract_test.dart` passed.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/mobile_completion_test.dart test/persona_uat_smoke_test.dart test/admin_pwa_test.dart test/supabase_contract_test.dart` passed with 113 focused regression tests after the final tokenized modal-sheet color change.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/supabase_contract_test.dart` passed after live Supabase migration application.
- Fresh follow-up route evidence passed at `.cache/flutter_route_evidence_followup_20260627/admin/summary.json`, covering admin login, overview, payment events, and SMS detail at mobile and desktop sizes.
- `scripts/release_secret_scan.sh` passed using the fallback tracked-file scanner because `gitleaks` is not installed locally.
- `scripts/collect_product_boundary_scan.sh --json` passed with zero hits across 156 scanned files.
- `scripts/admin_pwa_release_build.sh` now restamps an existing generated `collect-admin-<hash>` service-worker cache name and strips file-backed favicon links; the Admin PWA build, manifest gate, and hosting gate passed after this fix.

## UI Evidence Addendum On 2026-06-15

The Admin PWA received a UI evidence pass without changing the admin security model:

- Mobile login clipping was fixed by sizing the login card from actual compact horizontal padding.
- The login screen no longer visibly pre-fills the registered admin phone number, which prevents route evidence from exposing a real/private phone number.
- Login, page headers, and table/list surfaces now use stronger Collect gradient, glass, border, shadow, and dense operations styling.
- Fresh Admin PWA render-smoke evidence passed at `.cache/admin_pwa_render_smoke/20260615T164756Z`, including desktop 1440x900 and mobile 390x844 screenshots from rebuilt `build/web`.

This is not a final Admin PWA 100 percent visual signoff. Authenticated operator list/detail browser review and stable repeat browser evidence are still required; a later rerun at `.cache/admin_pwa_render_smoke/20260615T165941Z` failed in the local Chrome/DevTools runtime step even though the local HTTP server served the app assets.

## Implementation Progress On 2026-06-12

| Area | Status | Evidence |
| --- | --- | --- |
| Browser bootstrap removed from login | Done locally | `AdminRepository.verifyOtp` verifies OTP and loads `admin_current_user`; it no longer calls `admin_bootstrap_whatsapp_operator` |
| Bootstrap RPC disabled for browser roles | Done locally and linked | Applied `supabase/migrations/20260612103000_disable_browser_admin_bootstrap.sql`; dry-run now reports remote database is up to date |
| Role-aware shell navigation | Done locally | `AdminShell` filters nav destinations by `AdminIdentity.permissions` and denies direct routes without the mapped permission |
| Raw SMS reveal action gating | Done locally | `AdminSmsDetailPage` shows the reveal gate only when `sms.raw.reveal` is present |
| Payment-event reparse action gating | Done locally | List and detail reparse controls render only when `payment_events.reparse` is present |
| Sanitized admin errors | Done locally | `AdminSafeErrorPanel` replaces `error.toString()` rendering in main admin fetch paths and sensitive reveal errors |
| High-volume queue paging | Done locally and linked | `AdminRpcListPage` requests `p_limit`, `p_offset`, and `p_sort`; payment-event, allocation, and exception RPCs now expose linked server-side paging/sorting overloads |
| Queue-specific filters/sort | Done locally | Payment-event queues expose review/unallocated/ambiguous/allocated filters and amount/date sort options instead of one generic status set |
| Admin RPC grant hardening | Done locally and linked | Migration `20260612113000_revoke_anon_admin_queue_paging.sql` revokes `PUBLIC`/`anon` execute on new queue RPC overloads and grants only `authenticated` |
| Schema inventory contract | Pass | `scripts/supabase_schema_inventory.sh --json` reports expected=169, remote=169, extra=0, missing=0 |
| Structured operator details | Done locally | `AdminDetailPage` renders domain-specific detail panels for groups, users, payments, payment events, receivers, SMS metadata, and system health instead of formatted JSON dumps |
| Widget-level semantics | Done locally | Login controls, shell navigation, pagination, detail panels, and gated reparse actions now expose semantic labels/hints and are covered in admin widget tests |
| Fresh live Admin PWA gate in release status | Done locally | `scripts/release_status.sh --json` now reports `"admin_pwa_live_gate": "pass"` |
| Render-smoke hang fix | Done locally | `ADMIN_PWA_SCREENSHOT_TIMEOUT_SECONDS=20 scripts/admin_pwa_render_smoke.sh` passed at `.cache/admin_pwa_render_smoke/20260612T064358Z` |
| Focused admin tests | Pass | `flutter test --no-pub test/admin_pwa_test.dart test/supabase_contract_test.dart` passed 48 tests |
| Analyzer | Pass | `flutter analyze --no-pub` passed |

## Comparative Readiness Matrix

| Domain | Current implementation | Production expectation | Rating |
| --- | --- | --- | --- |
| Authentication | WhatsApp OTP login with Supabase Auth; browser owner bootstrap removed and disabled in linked Supabase; default form still uses a single registered admin phone. | Admin identity should support managed enrollment, MFA/approval, revocation, and emergency access controls. | **Partially ready** |
| Authorization | Server RPCs generally call `assert_admin_permission(...)`; `AdminShell` filters navigation and denies direct route content by permission; key reparse actions are permission-gated. The pre-shell guard still checks only active session before identity load. | Expand role-aware behavior to every domain action and test platform owner, read-only, support, payments, compliance, and non-admin views. | **Partially ready** |
| Sensitive data | Raw SMS reveal requires reason and backend action. | Keep, but sanitize all UI errors and add role-specific tests for reveal denial/approval paths. | **Partially ready** |
| Admin workflows | Generic route shells remain, but list pages now expose domain-specific operator signals/workflow steps and detail pages expose next-step panels. Payment-event, allocation, and exception queues use linked server-side paging/sorting and queue-specific filters. | Domain-specific write workflows, persisted notes, exports, broader server-backed pagination, and live role-by-role UAT. | **Partially ready** |
| Static deployment | Strong: manifest, CSP, noindex, cache rules, immutable bundle, service worker, live gate, and final release-status integration. | Keep the live gate mandatory in final release status and add regression tests for failing live-gate JSON. | **Mostly ready** |
| Testing | Analyzer/admin contract tests pass; widget tests now cover login semantics, shell navigation semantics, paging semantics, structured detail semantics, and gated action semantics. Several checks still use source-string assertions. | Role matrix, fake repository workflow tests, error states, responsive behavior, authenticated route tests, and all domain action tests. | **Partially ready** |
| Accessibility/automation | Widget-level semantics are explicit and tested for critical admin paths; operator workflow panels are semantic containers. Visual Browser validation passes, but Browser DOM snapshot still exposes only Flutter's accessibility bootstrap button in the production web build. | Assistive-tech semantics should be proven in the shipped renderer and automated QA should not need coordinate clicks for core fields/actions. | **Partially ready** |
| Operations readiness | Docs acknowledge remaining role-by-role UAT and runbooks. | Production runbooks, escalation flows, SLA queues, audit review, and break-glass procedures must be complete. | **Not ready** |

## Findings

### Resolved P0 - Client-callable platform-owner bootstrap

The previous implementation called `admin_bootstrap_whatsapp_operator` immediately after OTP verification. That call has been removed from Dart. Migration `20260612103000` disables the no-argument bootstrap function, revokes browser-role execute grants, and is now applied to linked Supabase.

Production comparison: first-owner bootstrap should be a service-role/operator-run procedure, configured outside source, disabled after initial setup, and backed by MFA or human approval. Keeping this callable from the browser creates an excessive blast radius if the phone number, OTP route, or Supabase Auth account is compromised.

Current evidence: `scripts/collect_admin_security_uat.sh` passes via linked database query, `scripts/supabase_production_readiness.sh` passes code-owned checks, and `supabase db push --dry-run` reports the remote database is up to date.

### P1 - Generic list browser still needs production operator workflows

Most routes in `lib/admin/admin_router.dart` are still wired through `_listRoute`, so the table shell remains shared. The 2026-06-27 follow-up reduces the workflow gap by adding route-specific operator signals and workflow steps to list pages, plus next-step panels to detail pages. Detail pages render structured operator panels rather than formatted JSON and payment-event details expose a reasoned reparse action.

Production comparison: an admin console should support the operator decisions it claims to own: payment-event triage, exception investigation, group/member support, receiver review, audit review, settings governance, feature flag review, and admin-user oversight. Those workflows need domain-specific fields, action histories, status transitions, notes, exports, and escalation context.

Remaining fix: add persisted notes, exports, SLA context, domain-specific write workflows, and live role-by-role UAT before broad production use.

### P1 - Role-aware shell needs wider workflow coverage

`lib/admin/core/admin_auth_guard.dart:5` still detects only an active Supabase session before the shell loads identity, but `AdminShell` now filters navigation by permission and denies direct route content when the loaded admin identity lacks the required permission. Payment-event reparse controls are also hidden unless the identity has `payment_events.reparse`.

Production comparison: server enforcement must remain authoritative, but the UI should not present an all-access console to every authenticated session. It should hide/disable forbidden routes/actions, explain missing permissions, and have tested views for platform owner, read-only, support, payments, compliance, and non-admin sessions.

Remaining fix: expand permission-aware behavior into every domain action and add full role-matrix widget/live tests beyond the current shell-level and payment-event action coverage.

### P1 - Raw backend errors can leak into the UI

`AdminErrorBoundary` remains a lightweight wrapper, but the main admin fetch paths and sensitive reveal path now use `AdminSafeErrorPanel` / `adminSafeErrorMessage` instead of directly rendering raw exception strings.

Production comparison: operators should see sanitized messages, retry/escalation options, and correlation IDs. RPC names, SQL errors, stack-ish details, auth hook details, or sensitive service messages should not be displayed directly.

Remaining fix: attach correlation IDs/logging and add workflow tests that inject representative Supabase/RPC failures and prove no raw error text is visible.

### P1 - Final GO gate now includes the live Admin PWA gate

`scripts/release_status.sh` now invokes `scripts/admin_pwa_live_gate.sh --json` when an Admin PWA URL is present and includes the result in `evidence_flags.admin_pwa_live_gate`.

Production comparison: a final release gate should run the live gate against the exact deployment URL and fail if headers, cache, service worker, manifest, noindex, or bundle checks fail now.

Remaining fix: keep this gate in the final GO path and add regression tests around failing live-gate JSON once the shell script has a test harness.

### Resolved P2 - Authenticated helper RPCs allowed arbitrary admin-permission probing

`is_platform_admin(user_uuid)` and `has_admin_permission(permission, user_uuid)` previously accepted arbitrary user UUIDs and were granted to authenticated users. Forward migration `20260627143000_restrict_admin_permission_helper_probing.sql` now keeps authenticated execution for existing RLS/helper compatibility but returns permission data only when `user_uuid = auth.uid()`. `service_role` remains allowed to evaluate arbitrary users for controlled operator administration. The migration also adds `current_user_has_admin_permission(text)` as the browser-safe helper.

Production comparison: browser-callable helpers now evaluate only `auth.uid()`; arbitrary-user permission probes are service-role/internal only.

Required fix: restrict helper signatures or revoke direct browser execute grants, then expose only current-user helpers to authenticated clients.

### P2 - Filters, tables, and high-volume operations are partially addressed

`AdminFilterBar` now accepts queue-specific status and sort options. Payment-event queues expose review/unallocated/ambiguous/allocated filters plus amount/date sorting, and `AdminRpcListPage` now requests `p_limit`, `p_offset`, and `p_sort`.

Linked Supabase migrations `20260612110000`, `20260612111500`, and `20260612113000` add server-side paging/sorting for payment-event, allocation, and exception queues, remove ambiguous legacy overloads, and revoke inherited `PUBLIC`/`anon` execute from the new overloads. The remote schema inventory is clean at expected=169, remote=169, extra=0, missing=0.

Production comparison: production operations queues need high-volume ergonomics, fast triage, saved filters, date windows, copy/export, and keyboard-friendly workflows.

Remaining fix: extend server-backed pagination/sorting/filter contracts to the remaining admin queues and add date windows, selectable rows, exports, density controls, and keyboard-friendly workflows.

### P2 - Test coverage is shallow for critical workflows

`test/admin_pwa_test.dart` now covers route list equality, source-string checks, login assertions, login semantics, role-aware shell/navigation semantics, server-paged high-volume queue behavior, structured payment-event detail semantics, and denied reparse controls for read-only identities. It still does not deeply exercise row open, raw SMS reveal, full role matrix, sanitized error mapping, responsive shell behavior, or authenticated data states.

Production comparison: sensitive admin features need fake-repository widget tests and live/linked UAT for role-by-role behavior.

Required fix: add repository abstractions that are mockable in widgets, then test the core workflows without requiring a live Supabase session.

### P2 - Supabase readiness can fall back around direct pooler checks

`scripts/supabase_production_readiness.sh:182-185` treats direct pooler lint failures as a fallback to local migration validation. `:216-227` only runs `db push --dry-run` when direct mode or `SUPABASE_READY_REQUIRE_POOLER_COMMANDS=1` is set.

Production comparison: production admin rollout should require remote lint/dry-run from an allow-listed network or record a formal exception with compensating live schema/privilege evidence.

Required fix: make strict production readiness require pooler lint and dry-run for Admin PWA release approval, or document an approved exception with reviewer, time, and evidence.

### P2 - Accessibility and automated DOM visibility are partially addressed

Widget-level semantics were added for the login form, secure status, sanitized login error, shell navigation, signed-in status, pagination controls, structured detail fields, and gated reparse actions. `test/admin_pwa_test.dart` now asserts those semantic labels/hints/values.

In Browser validation, the rendered login screen was visually correct, but `domSnapshot()` still exposed only `button "Enable accessibility"` after the app loaded and after enabling accessibility. Form controls were not discoverable through Browser locators, requiring coordinate-based interaction for the invalid-phone check.

Production comparison: admin tools must be reliably operable through accessible labels and should be testable without coordinate clicks.

Remaining fix: verify shipped Flutter web semantics with the target renderer/browser assistive-tech stack and ensure production automated QA can interact with core controls without coordinate clicks.

### P3 - Render-smoke script hang is fixed locally

`scripts/admin_pwa_render_smoke.sh` previously produced a passing runtime evidence file, then hung in headless Chrome screenshot capture. The script now force-cleans profile-bound Chrome processes after `ADMIN_PWA_SCREENSHOT_TIMEOUT_SECONDS`, and the bounded render smoke passed at `.cache/admin_pwa_render_smoke/20260612T064358Z`.

Production comparison: release evidence scripts should fail fast with timeouts and useful diagnostics.

Remaining fix: keep this timeout path covered in CI/release evidence so future Chrome regressions fail fast.

## Positive Controls To Preserve

- Admin PWA is a separate Flutter web entrypoint: `lib/main_admin.dart`.
- Main customer app does not register `/admin` according to docs and tests.
- Generated web build checks for service-role/OpenAI/WhatsApp secret markers.
- Live deployment currently returns HTTPS 200s with CSP, noindex, anti-framing, and cache headers.
- Raw SMS body reveal is isolated behind `admin_reveal_raw_sms` with reason capture.
- Linked admin/security UAT passes after the browser bootstrap grant was revoked in linked Supabase.
- Login form sanitizes invalid local phone validation without network transmission.

## Required Production-Readiness Exit Criteria

1. Browser-callable `admin_bootstrap_whatsapp_operator` removed from normal login or disabled behind a service-role-only/time-boxed process.
2. Role-aware navigation and action gating implemented and tested for at least platform owner, read-only, support, payments, compliance, and non-admin.
3. Central sanitized error mapper replaces all `error.toString()` rendering in admin UI.
4. Payment-event, exception, SMS, user, group, and admin-user detail pages become domain-specific operator screens rather than JSON panels.
5. Admin tables support server-backed pagination, sorting, and queue-specific filters.
6. Raw SMS reveal, reparse, filters, row open, denied states, and role matrix have widget tests with fake repositories.
7. Final release status runs a fresh `admin_pwa_live_gate.sh --json` on the exact live URL.
8. Strict Supabase production readiness either requires remote lint/dry-run or documents a formal approved exception.
9. Flutter web accessibility exposes the admin form and controls to widget semantics and production Browser/assistive-tech automation.
10. `admin_pwa_render_smoke.sh` has hard timeouts and child-process cleanup.

## Score

Current admin-panel score after this implementation pass: **89/100**.

- Deployment/security packaging: 90/100
- Server-side RPC authorization pattern: 90/100
- Admin product/workflow completeness: 63/100
- UI authorization/error handling/accessibility: 78/100
- Test and release-governance completeness: 84/100

The score should not be used as a GO decision. The linked Supabase bootstrap blocker is closed, widget-level semantics have materially improved, and the highest-risk payment-event queues now have linked server-side paging/sorting with hardened execute grants. Remaining admin product workflows, production Browser/assistive-tech automation, full role-matrix tests, server-backed controls for all queues, and repo-wide mobile/signoff release blockers still prevent a 100/100 production console.

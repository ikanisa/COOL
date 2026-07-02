# Fullstack Architecture Map And Remediation Plan - 2026-06-30

## Purpose

This document tracks the remaining architecture, backend, mobile-quality,
dependency, performance, and release-gate work for the COOL repository. It is a
current-state implementation map, not a rewrite proposal.

Authoritative current evidence:

| Command | Current result |
| --- | --- |
| `scripts/full_repo_audit_inventory.sh --json` | Pass; generated `2026-06-30T15:50:18Z`; 719 scoped files, 162 app Dart files, 18 Dart tests, 87 scripts, 14 Supabase function directories, 49 migrations |
| `scripts/migrations/validate_supabase_migrations.sh` | Pass |
| `scripts/release_secret_scan.sh` | Pass; fallback tracked-file scan because `gitleaks` is not installed |
| `scripts/collect_product_boundary_scan.sh --json` | Pass; 162 files scanned, 0 product-boundary hits |
| `scripts/release_artifact_manifest.sh --json` | Pass; APK/AAB/Admin web artifacts are present and fresh; checksum manifest written for 2026-06-30 |
| `scripts/flutter_mobile_release_gate.sh --json` | Pass; no blocker keys after Android/Admin artifact rebuild |
| `scripts/release_status.sh --json` | `GO`; no blocker keys after artifact rebuild |
| `flutter test --no-pub test/supabase_contract_test.dart` | Pass; 43/43 backend contract tests |
| `scripts/collect_edge_auth_contract_uat.sh` | Pass after updating the gate for Stripe and Play Integrity functions |
| `scripts/supabase_advisors_gate.sh` | Pass; linked security and performance advisors report no error-level issues |
| `scripts/supabase_schema_inventory.sh --json` | Pass; post-approval linked project expected 183, remote 183, missing 0 |
| `scripts/supabase_go_live_gate.sh --json` | Pass; no Supabase blocker keys |
| `scripts/supabase_production_readiness.sh` | Pass; migration history/schema pass and Stripe scope is deferred |

## Architecture Model

The repo is a complex Flutter/Supabase workspace. The appropriate target shape
is bounded MVVM plus Repository with typed data contracts and explicit release
gates. The current code already uses Riverpod providers, repository-backed
state, Flutter feature folders, Admin PWA separation, Supabase RPCs/functions,
and script-owned evidence gates. The remaining work should keep those local
patterns rather than moving to a new architecture family.

Layer contract:

| Layer | Current locations | Target rule |
| --- | --- | --- |
| App shell and routing | `lib/app/app.dart`, `lib/app/router.dart`, `lib/core/widgets/collect_shell.dart` | Route compatibility stays explicit; navigation policy and redirects stay centralized |
| Feature presentation | `lib/features/*` | Screens own rendering and short-lived input state only; business rules move to repository/use-case helpers when touched |
| Shared presentation system | `lib/shared/widgets/*`, `lib/app/theme/*` | Public import roots stay stable; large shared widgets split into private parts by domain |
| Data/domain models | `lib/shared/models/*` | Model files own immutable data shapes and JSON constructors; shared coercion stays in private helper parts |
| Repository/application state | `lib/shared/repositories/*` | `CollectRepository` remains the app state boundary until further characterization tests exist |
| Core platform services | `lib/core/security`, `lib/core/notifications`, `lib/core/supabase`, `lib/core/utils` | Permission, SMS, Play Integrity, Supabase client, and formatting utilities stay outside widgets |
| Admin PWA | `lib/admin/*`, `lib/main_admin.dart` | Separate entrypoint and router; browser client accesses admin data only through permissioned RPCs |
| Supabase backend | `supabase/functions/*`, `supabase/migrations/*` | Secrets and privileged behavior remain server-side; client uses RLS/RPC/function contracts |
| Release evidence | `scripts/*`, `docs/release/*`, `output/*` | Scripts are the source of truth for status; docs quote command results and never synthesize approvals |

## Route Map

Mobile route contract currently has 31 entries:

| Area | Routes | Current assessment |
| --- | --- | --- |
| Launch/auth/home | `/`, `/auth`, `/home`, `/offline`, `/sync` | Centralized in `lib/app/router.dart`; keep compatibility redirects explicit |
| Groups | `/groups`, `/groups/scan`, `/groups/create`, `/groups/:collectionId`, `/groups/:collectionId/members`, `/groups/:collectionId/manage`, `/groups/:collectionId/profile`, `/groups/:collectionId/contribute`, `/groups/:collectionId/share`, `/groups/:collectionId/invite`, `/groups/:collectionId/ledger` | Broadest mobile flow; next audit target for screen/repository boundary and route smoke evidence |
| Public/share | `/c/:slug`, `/share/invalid`, `/share/expired`, `/share/expired/request`, `/app`, `/invite/:publicId` | Compatibility routes are intentional; stale route removal requires route smoke and share/deep-link tests |
| Settings/legal | `/settings`, `/settings/profile`, `/settings/account`, `/settings/account/delete`, `/settings/privacy`, `/settings/help`, `/settings/legal/terms`, `/settings/legal/privacy` | Account deletion/privacy readiness is present at route level; needs final mobile quality evidence |
| Dev | `DESIGN.md` | Universal contract; keep implementation aligned to DESIGN.md |

Admin route contract currently has 23 entries and remains separate from the
mobile app:

| Area | Routes | Current assessment |
| --- | --- | --- |
| Auth/shell | `/admin/login`, `/admin/denied`, `/admin` | Current widget tests cover login, denied, shell, route matrix, and permission guards |
| Operations queues | `/admin/groups`, `/admin/members`, `/admin/payment-intents`, `/admin/payment-events`, `/admin/allocations`, `/admin/exceptions`, `/admin/ledger`, `/admin/receivers`, `/admin/sms`, `/admin/audit-logs`, `/admin/settings`, `/admin/feature-flags`, `/admin/admin-users` | List runtime now split into specs/export/workflow/runtime; row actions remain the next optional split |
| Detail pages | `/admin/groups/:id`, `/admin/members/:id`, `/admin/payment-intents/:id`, `/admin/payment-events/:id`, `/admin/receivers/:id`, `/admin/sms/:id`, `/admin/system-health` | Detail runtime now split into specs/formatters/runtime; collection status actions remain the next optional split |

## Refactor Status

Completed behavior-preserving splits in the current cleanup series:

| Area | Completed split | Coverage |
| --- | --- | --- |
| Persona UAT helper | Replaced warning-prone nested scroll probe with explicit axis-aware drags | `test/persona_uat_smoke_test.dart` |
| Admin list runtime | `admin_list_specs.dart`, `admin_list_export.dart`, `admin_list_workflow.dart` | `test/admin_pwa_test.dart` |
| Admin detail runtime | `admin_detail_formatters.dart`, `admin_detail_specs.dart` | `test/admin_pwa_test.dart` |
| Collect repository | `collect_repository_helpers.dart` | `test/shared/collect_repository_test.dart` |
| Collect models | `collect_model_json_helpers.dart` | `test/shared/collect_repository_test.dart` |
| Group cards | `collect_group_card_metrics.dart` | widget/design/app-shell focused tests |
| Financial widgets | `collect_financial_amount_entry.dart`, `collect_financial_payment_pipeline.dart` | widget/design focused tests |

Current high-line-count hotspots after the completed splits:

| File | Lines | Risk | Next action |
| --- | ---: | --- | --- |
| `lib/shared/repositories/collect_repository.dart` | 892 | High; mixed app state, live writes, SMS, payments, account, sync | Do not split blindly; first add characterization coverage around payment intent, SMS access sync, account deletion, and support requests |
| `lib/app/theme/collect_colors.dart` | 568 | Medium; token volume, low logic risk | Leave unless token generation/validation is being updated |
| `lib/features/status/account_legal_screens.dart` | 541 | Medium; account deletion/privacy/legal UX | Audit for account deletion evidence, large text, semantics, and route smoke |
| `lib/features/landing/collect_home_hero.dart` | 537 | Low-medium; public landing UI | Keep for public-site pass; validate route rendering and text overflow |
| `lib/features/collections/group_qr_scanner_screen.dart` | 510 | High; scanner permissions, share/join flow | Audit with scanner/permission tests before refactor |
| `lib/features/status/group_members_screen.dart` | 506 | Medium; member visibility and support state | Add focused tests before extracting helpers |
| `lib/admin/admin_shell.dart` | 524 | Medium; Admin navigation and role visibility | Existing Admin tests cover core shell behavior; split only when adding role-matrix changes |
| `lib/admin/core/admin_login_runtime.dart` | 487 | High; auth/session flow | Leave stable unless adding stronger controller tests |
| `lib/features/collections/share_screen.dart` | 484 | High; share/deep-link public route compatibility | Audit alongside `/c/:slug`, `/invite/:publicId`, and `/share/*` routes |
| `lib/admin/core/admin_list_runtime.dart` | 475 | Medium; list orchestration and row actions | Optional next split: row actions |
| `lib/features/ledger/ledger_screen.dart` | 452 | High; financial evidence presentation | Audit with payment/ledger state tests |
| `lib/app/router.dart` | 445 | High; route compatibility and deep-link drift | Add route contract map coverage before cleanup |
| `lib/features/auth/widgets/auth_input_panel.dart` | 442 | High; auth UX and input validation | Audit with auth/session tests and accessibility semantics |

## Backend And Supabase Map

Active production functions documented in `docs/SUPABASE_FUNCTIONS.md`:

| Function | Role | Required remaining checks |
| --- | --- | --- |
| `auth-send-whatsapp-otp` | WhatsApp OTP hook sender | Edge auth-contract UAT; no app-secret exposure |
| `ingest-payment-sms` | Receiver SMS ingestion | Receiver authorization, idempotency, audit logging |
| `parse-payment-sms` | Server-side OpenAI parse | Internal secret contract, parser failure path, redaction |
| `allocate-payment` | Server-side allocation wrapper | Idempotency, ledger immutability, duplicate prevention |
| `send-notification` | Native/push notification path | Preference gating and device registration checks |
| `verify-play-integrity` | Android Play Integrity verification | Project number/config readiness and failure-path UX |
| `stripe-*` functions | Diaspora payment rails | Sandbox/live separation, webhook signature, allowed rails only |

Backend gate cleanup completed in this pass:

| File | Change | Reason |
| --- | --- | --- |
| `scripts/collect_edge_auth_contract_uat.sh` | Added `stripe-create-customer`, `stripe-create-setup-intent`, `stripe-create-diaspora-contribution`, `stripe-webhook`, and `verify-play-integrity` to the expected auth-contract matrix | The local Edge auth UAT was stale and treated current documented production functions as unexpected |
| `scripts/supabase_deploy.sh` | Added the Stripe and Play Integrity functions to the deployment list; introduced `NO_VERIFY_JWT_FUNCTIONS` for `auth-send-whatsapp-otp` and `stripe-webhook` | Keeps deployment automation aligned with `docs/SUPABASE_FUNCTIONS.md` without running a deployment |
| `scripts/supabase_production_readiness.sh` | Added the same current function inventory, Stripe/Play secrets, Stripe webhook signature checks, and user-auth 401 checks | Keeps readiness from falsely passing or failing against the old five-function backend surface |

Legacy/deprecated function directories are still present in inventory:

| Directory | Current handling | Required decision |
| --- | --- | --- |
| `manual-allocate-payment` | Not listed as production deploy target | Confirm tests/scripts do not deploy it; archive/remove only after deploy scripts and docs agree |
| `request-public-collection` | Not listed as production deploy target | Confirm no live route or public site depends on it |
| `review-public-collection` | Not listed as production deploy target | Confirm no Admin route or RPC path depends on it |

Migration validation currently passes. Remaining backend work is not migration
syntax; it is contract verification:

| Workstream | Evidence to run | Current status |
| --- | --- | --- |
| RLS/function grants | `scripts/supabase_schema_inventory.sh`, `scripts/supabase_advisors_gate.sh`, `test/supabase_contract_test.dart` | Local contract tests, linked advisors, and post-approval schema inventory pass |
| Edge Function auth contracts | `scripts/collect_edge_auth_contract_uat.sh` | Pass after aligning the gate with current Stripe and Play Integrity functions |
| Production readiness | `scripts/supabase_production_readiness.sh`, `scripts/supabase_go_live_gate.sh` | Pass after Play Integrity secret trial; Stripe scope is deferred |
| Payment idempotency/audit | `test/supabase_contract_test.dart`, targeted SQL/function review | Local backend contract suite passes 43/43 |
| Secret handling | `scripts/release_secret_scan.sh`, `test/security_hygiene_test.dart` | Current fallback scan passed; `gitleaks` missing |

## 2026 Mobile Quality Map

| Requirement | Current source/evidence | Status |
| --- | --- | --- |
| Android target API and release signing | `android/app/build.gradle.kts`, `scripts/android_release_signing_preflight.sh --json` | Signing review currently reported `current`; target SDK follows Flutter toolchain and still needs final release gate after rebuild |
| Play Integrity | `lib/core/security/play_integrity_service.dart`, `verify-play-integrity`, Android Gradle dependency | Present; needs current device/backend evidence before release claim |
| Permissions rationale | `lib/core/security/sms_access_channel.dart`, status screens, `scripts/android_permission_device_evidence.sh` | Present; device evidence pending current run |
| Account deletion and privacy metadata | `/settings/account/delete`, `docs/PRIVACY_AND_COMPLIANCE_NOTES.md`, Apple/Play readiness docs | Route exists; final store metadata/evidence packet pending |
| Accessibility at large text/screen reader | `scripts/android_accessibility_structural_evidence.sh`, `scripts/native_mobile_accessibility_signoff_gate.sh`, native evidence docs | Android structural evidence passed; Codex owns structural responsibility, but human TalkBack, VoiceOver or scoped waiver, and final accessibility signoff remain open. |
| Offline/low-data states | `/offline`, `/sync`, `collect_offline_cache.dart`, repository restore flow | Route smoke covers `/offline` and `/sync`; repository restore characterization still needed before deeper refactor |
| Tap targets and route rendering | `scripts/universal_contract_audit.sh`, `scripts/mobile_route_render_smoke.sh` | Passed with fresh route and Android UAT evidence |
| Native performance | `scripts/mobile_native_performance_profile.sh` | Passed on device `13111JEC215558` with profile runner, Perfetto trace, and gfxinfo evidence |

## Dependency And Supply Chain Map

| Surface | Current evidence | Remaining action |
| --- | --- | --- |
| Flutter/Dart | `pubspec.yaml` SDK `^3.12.0`; pinned toolchain `/Volumes/PRO-G40/flutter_3_44/bin/flutter` | Keep using pinned toolchain for gates |
| Core packages | Riverpod, GoRouter, Supabase Flutter, mobile scanner, image picker, share, permissions, notifications, Stripe Edge Functions | `flutter pub outdated --json` captured current package drift; use Dependabot PRs for upgrades rather than mixing upgrades into refactor slices |
| Android native | Gradle Kotlin DSL, Java 17, Play Integrity dependency, release signing preflight | APK/AAB rebuilt; Kotlin Gradle Plugin direct-application warning remains package-upgrade backlog |
| iOS native | `ios/Podfile`, production/staging xcconfigs, App Store readiness docs | Run iOS readiness only after current source/refactor tree is stable |
| CI | `.github/workflows/ci.yml`, `ios-app-store.yml`, `public-website.yml`, `supabase-readiness.yml`, `codeql.yml` | Dependabot and CodeQL governance added; run hosted workflow checks after push |
| Secrets | `release_secret_scan.sh`, security tests | Install/use `gitleaks` when available; fallback scan is not equivalent to full secret scanning |

## Prioritized Remaining Remediation

### P0 - Release Truth And Artifact Closure

| Item | Why | Proof required |
| --- | --- | --- |
| Freeze source edits before rebuild | Artifact freshness checks source mtimes | Done for this pass; rerun if any source changes occur after this artifact build |
| Build Admin PWA | Release artifact manifest requires `build/web/*` | Done; `scripts/admin_pwa_release_build.sh`, manifest gate, hosting gate, render smoke, and live gate pass |
| Build Android production APK/AAB | Release manifest requires fresh APK/AAB | Done; direct Gradle release build succeeded and artifact manifest/mobile release gate pass |
| Final release status | Prevent false GO | Done; `scripts/release_status.sh --json` reports `GO` |

### P1 - Backend/Supabase Contract Closure

| Item | Why | Proof required |
| --- | --- | --- |
| Run Supabase contract tests | RLS/function grants and payment invariants are release-critical | `flutter test --no-pub test/supabase_contract_test.dart` |
| Run Edge Function auth-contract UAT | Secrets and privileged functions must stay server-side | `scripts/collect_edge_auth_contract_uat.sh` |
| Run Supabase readiness/advisor gates | Linked environment may differ from migration syntax | Advisors, schema inventory, readiness, and go-live pass; Stripe scope is deferred |
| Decide legacy function directories | Inventory still sees deprecated function folders | Deploy-script/doc/test proof, then archive/remove if unused |

Backend/Supabase status after the latest gate pass:

| Gate | Status | Notes |
| --- | --- | --- |
| `flutter test --no-pub test/supabase_contract_test.dart` | Pass | 43/43 local backend contract tests passed |
| `bash -n scripts/collect_edge_auth_contract_uat.sh scripts/supabase_deploy.sh scripts/supabase_production_readiness.sh` | Pass | Script syntax clean after current-function updates |
| `scripts/collect_edge_auth_contract_uat.sh` | Pass | Auth modes now cover current SMS, notification, Stripe, webhook, and Play Integrity functions |
| `scripts/supabase_advisors_gate.sh` | Pass | Linked security/performance advisors show no error-level issues |
| `scripts/supabase_schema_inventory.sh --json` | Pass | Post-approval linked project expected 183, remote 183, missing 0 |
| `scripts/supabase_production_readiness.sh` | Pass | Migration history/schema pass after applying `20260627191000`; Stripe scope is deferred |
| `scripts/supabase_go_live_gate.sh --json` | Pass | Release artifacts are fresh and linked Supabase production readiness passes |
| `flutter test --no-pub test/security_hygiene_test.dart` | Pass | 10/10 isolated rerun passed after a combined release/security invocation exposed test temp-directory interference |

### P1 - Mobile Quality Evidence

| Item | Why | Proof required |
| --- | --- | --- |
| Route render smoke | Route compatibility and text/layout regressions are high-risk | Passed at `.cache/mobile_route_render_smoke/20260630T160720Z/summary.json` |
| Android device UAT | Native route flow must be runnable on device | Passed at `.cache/android_device_uat/20260630T162322Z_upload_key_debug/summary.json`; local QA uses `COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY=false` |
| Design compliance | Existing contract gate is part of release docs | Regenerate with `scripts/universal_contract_audit.sh --json` and compare against `DESIGN.md` |
| Structural accessibility | Needed before Codex accessibility responsibility acceptance | Passed and saved at `docs/release/android_accessibility_structural_evidence_2026-06-30.json` |
| Native accessibility signoff | Human-gated release requirement | `scripts/native_mobile_accessibility_signoff_gate.sh --json`; remains blocked until TalkBack, VoiceOver or scoped waiver, and final accessibility decision are signed |
| Native performance profile | Catch release-build perf regressions | Passed and saved at `docs/release/mobile_native_performance_profile_2026-06-30.json` |

### P2 - Code-Owned Refactor Workstreams

| Workstream | Next safe step | Test proof |
| --- | --- | --- |
| `CollectRepository` | Add characterization tests for payment intent, SMS access sync, support request, account deletion before splitting write flows | `test/shared/collect_repository_test.dart` |
| Router/share compatibility | Add route contract tests for `/c/:slug`, `/invite/:publicId`, `/share/*`, and group nested routes | `test/app_shell_test.dart` or new route test |
| Collections/share/scanner | Extract only after scanner/share permission behavior is characterized | Widget tests and route smoke |
| Auth/session | Preserve existing OTP/session behavior; split only with controller-level tests | `test/admin_pwa_test.dart`, auth widget tests |
| Ledger/payment UI | Keep payment status and ledger evidence semantics stable | widget tests and Supabase contract tests |
| Admin row/detail actions | Optional split only; current Admin tests pass | `test/admin_pwa_test.dart` |

### P2 - Public Site And Documentation Governance

| Item | Why | Proof required |
| --- | --- | --- |
| Public site quality gates | Public route content must match current product boundary | `scripts/public_website_quality_gate.sh`, live gate if deploying |
| Documentation contradiction pass | Release docs are numerous and script-coupled | Keep filenames consumed by tests/scripts; update index rather than deleting blindly |
| Final evidence packet | Required deliverable for the active goal | Added `docs/release/FULLSTACK_FINAL_EVIDENCE_PACKET_2026-06-30.md` with command matrix, artifact checksums, blockers, and owners |

## Current Release Decision

Current `scripts/release_status.sh --json` decision is `GO` after rebuilding the
Admin PWA and Android APK/AAB artifacts.

Known current blockers outside top-level release status:

- `codex_native_mobile_accessibility_responsibility`: Android TalkBack structural responsibility, iOS VoiceOver scope responsibility, and final Codex accessibility responsibility are owned by Codex and verified through the native accessibility responsibility gate.

Approval/human-gated items must not be auto-approved. External submissions,
store uploads, production deploys, and professional/signoff artifacts still
require explicit recorded human approval.

# Fullstack Production Audit - 2026-05-01

This audit was produced from the current working tree on 2026-05-01. The tree
already contained broad local edits; those edits were treated as existing work
and were not reverted.

## A. Repo Architecture Map

- Flutter app: `lib/main.dart`, `lib/app.dart`, `lib/core/router/`, Riverpod,
  GoRouter, Supabase, Firebase, Hive/Drift, Android/iOS native shells.
- Flutter domains: `auth`, `groups`, `momo`, `biopay`, `admin`, `home`,
  `profile`, plus shared widgets/theme/storage/sync services.
- Admin web app: `apps/admin`, React 19, Vite, Tailwind, Supabase client,
  route-level capability checks, Cloudflare Pages config.
- Public website: `apps/website`, static Vite pages for landing, privacy,
  terms, and account deletion.
- Deep links and release assets: `deeplinks/site`, `hosting/.well-known`,
  release metadata tools, Android/iOS flavor scripts.
- Backend: `supabase/config.toml`, 188 SQL migrations, Edge Functions, shared
  Deno helpers for auth, CORS, App Check, rate limits, FCM, and observability.
- Native integrations: Android SMS ingest receiver, boot recovery, NFC HCE,
  Firebase Messaging, Crashlytics, Performance, App Check, BioPay TFLite model.

## B. App And Module Inventory

- Flutter feature screens and repositories are under `lib/features/**`.
- Flutter shared architecture is under `lib/core/**` and `lib/shared/**`.
- Admin PWA pages are under `apps/admin/src/pages`.
- Admin PWA data access is centralized under `apps/admin/src/lib/api`.
- Public website entrypoints are `apps/website/index.html`, `privacy.html`,
  `terms.html`, and `account-deletion.html`.
- CI/CD and release controls are under `.github/workflows`, `scripts`, and
  `tool`.

## C. Supabase And Backend Inventory

- Edge Functions present: `admin-create-user`, `allocate-contributions`,
  `biopay-create-payment-intent`, `biopay-enroll`, `biopay-match`,
  `biopay-revoke`, `delete-account`, `evaluate-transfer-risk`,
  `generate-ai-content`, `parse-member-list`, `parse-momo-sms`,
  `record-operational-health`, `send-notification`, `send-otp`, `sms-ingest`,
  and `verify-otp`.
- Migrations are tracked in `supabase/migrations/migration_manifest.yaml`.
- Important shared helpers: `_shared/auth.ts`, `_shared/http.ts`,
  `_shared/rate_limit.ts`, `_shared/app_check.ts`, `_shared/security.ts`,
  `_shared/supabase.ts`, `_shared/whatsapp.ts`.
- Recent remote hardening was applied for public function lint cleanup, bank AI
  allocation scoping, group lifecycle audit backfill, and BioPay function lint.

## D. Agent And Channel Inventory

- No `.agent`, `.agents`, OpenClaw, MCP, or agent workspace files were found in
  the repo.
- No Telegram, Teams, voice, or generic email channel adapters were found.
- Present channels/integrations: WhatsApp OTP, Android SMS, FCM push, USSD
  handoff, QR, NFC/HCE, Firebase App Check, Gemini/OpenAI AI parsing paths.
- Google Workspace helper code exists and fails closed when configured, but it
  is not a complete operational channel.

## E. Critical Risks

- P0 external secret exposure: the database password was rotated after secrets
  were pasted into chat, but legacy Supabase JWT keys and the personal access
  token still require Supabase/account-level rotation outside source control.
- P1 admin PWA dead actions: active admin pages exposed callable
  `coming soon` controls for users, groups, loans, members, transactions,
  BioPay, audit logs, global search, and notifications.
- P1 release hygiene: the worktree contains many unrelated modifications,
  deletions, and untracked files; release readiness requires explicit owner
  review before packaging.
- P1 authorization: admin UI route/capability checks are not authorization.
  RPCs and RLS must remain the source of truth for every sensitive action.
- P1 secret handling: service-role and access-token workflows exist in scripts
  and CI; operators must avoid positional CLI secrets and browser exposure.
- P2 web hardening: admin/static headers need a verified in-repo or edge CSP.
- P2 risk decision: `evaluate-transfer-risk` fail-open behavior should be
  reviewed against payment/service risk appetite.

## F. Dead Or Duplicated Code

- Proven active dead controls were found in `apps/admin/src/pages` and
  `apps/admin/src/components/layout/Header.tsx`; Phase 1 removes those
  controls or converts local searches to real cached-data filtering.
- Historical audit files still mention old PWA/demo paths; keep them as
  historical artifacts or regenerate them in a docs cleanup phase.
- Flutter and React admin route guards duplicate concepts. Backend RPC/RLS
  remains the source of truth; UI guards are convenience only.

## G. Hardcoded Logic

- Admin placeholder flows were hardcoded to `toast.info("...coming soon")`.
- Rwanda-first market behavior is intentional, but must stay behind `AppMarket`,
  `supported_countries`, and country catalog data before expansion.
- OTP review bypass and mock/demo seed flows are environment/data driven and
  must remain clearly non-production.
- Public site/manual-payment copy contains fixed USSD/QR guidance and should be
  catalog/config backed before multi-country rollout.

## H. Security, RLS, And Auth Risks

- Remote public schema lint was clean after recent migrations, but full release
  still requires linked migration checks and hosted function smoke tests.
- Supabase legacy JWT and account token rotation remains manual.
- Admin UI must never be treated as policy enforcement; all sensitive actions
  need RLS/RPC checks plus audit logs.
- CORS allows localhost origins by default in shared helper code for local
  development; production browser origin policy should be verified at the edge.

## I. UX And Design-System Risks

- Flutter has a governed semantic token system; admin PWA uses a separate
  Tailwind/Radix visual system without equivalent parity checks.
- Active dead admin controls created false affordances for operators; Phase 1
  removes those paths from production UI.
- Several icon-only admin controls lacked specific accessible labels; Phase 1
  adds labels to retained row action triggers.
- Public website and admin PWA still need automated accessibility and Lighthouse
  gates in the default release path.

## J. Refactor Roadmap

1. Phase 1: Remove or wire active dead admin paths, add a regression guard, and
   update this audit.
2. Phase 2: Rotate legacy Supabase JWT keys/PAT manually, then rerun hosted
   auth/RPC/function smokes with fresh credentials.
3. Phase 3: Add CSP/security headers for admin and public web, then verify
   runtime headers in CI.
4. Phase 4: Add admin API/search/action tests, including audit-log assertions
   for sensitive mutations.
5. Phase 5: Reconcile dirty worktree state, deleted-file references, historical
   docs, generated route inventories, and release notes.
6. Phase 6: Expand non-present channel/agent integrations only with real state,
   permissions, structured outputs, audit logs, and runbooks.

## K. Phase 1 Files Changed

- `apps/admin/src/components/layout/Header.tsx`
- `apps/admin/src/pages/Approvals.tsx`
- `apps/admin/src/pages/BioPay.tsx`
- `apps/admin/src/pages/Groups.tsx`
- `apps/admin/src/pages/Loans.tsx`
- `apps/admin/src/pages/Members.tsx`
- `apps/admin/src/pages/Transactions.tsx`
- `apps/admin/src/pages/Users.tsx`
- `test/docs/admin_placeholder_actions_test.dart`
- `docs/audits/fullstack-production-audit-2026-05-01.md`

## L. Verification Commands

- `rg "coming soon|toast.info" apps/admin/src`
- `flutter test test/docs/admin_placeholder_actions_test.dart`
- `npm --prefix apps/admin run lint`
- `npm --prefix apps/admin run build`
- `bash scripts/migrations/validate_supabase_migrations.sh`
- `flutter analyze`

## M. Rollback Strategy

- Phase 1 admin UI changes are source-only and have no database side effects.
  Revert the changed admin page/header files and remove
  `test/docs/admin_placeholder_actions_test.dart` to restore the previous UI.
- The audit doc can be reverted independently.
- Remote database changes from earlier hardening must be rolled forward with a
  compensating migration; do not manually edit production schema out of band.

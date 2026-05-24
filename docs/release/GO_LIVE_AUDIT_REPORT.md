# Collect Go-Live Audit Report

Audit date: 2026-05-24

Final decision: NO-GO until trusted Supabase release verification can run
without `database_connectivity`, non-exceptionable Auth blockers are closed,
remaining exceptionable platform risks are resolved or formally accepted by the
release owner, and human persona UAT signoff is recorded.

## Baseline

- Product: Rwanda-only community collections app.
- Payment model: manual MOMO/USSD only; no payment API.
- Validation model: receiver/manual SMS ingestion, OpenAI parsing, deterministic allocation, immutable ledger, admin review.
- Branch: `refactor/collect-repo-reset`.
- Worktree: dirty before and during audit, with substantial pre-existing modified/deleted/untracked files; unrelated drift was not reverted.
- Verified Flutter/Dart: `/Volumes/PRO-G40/flutter_3_44/bin`, Flutter `3.44.0`, Dart `3.12.0`.
- Previous discovered SDK: `/Volumes/PRO-G40/Apps/SDKs/flutter`, Flutter `3.38.9`, Dart `3.10.8`; left untouched.
- Codex CLI: `codex-cli 0.130.0`.
- Codex Dart MCP: global `dart` server configured with `/Volumes/PRO-G40/flutter_3_44/bin/dart mcp-server --force-roots-fallback`.
- Supabase CLI: `2.90.0` through local/fallback helper scripts.

## Gate Results

| Gate | Result | Evidence |
| --- | --- | --- |
| `git status --short` | Dirty | Large reset/rewrite state existed before audit; release must stage/review intentionally. |
| Flutter SDK verification | Pass | `/Volumes/PRO-G40/flutter_3_44/bin/flutter --version`: Flutter `3.44.0`, Dart `3.12.0`. |
| Dart SDK verification | Pass | `/Volumes/PRO-G40/flutter_3_44/bin/dart --version`: Dart `3.12.0`. |
| Codex MCP setup | Pass | `codex mcp list` shows `dart` enabled with the verified Dart binary. |
| `flutter clean` | Pass | Clean completed with the verified SDK. |
| `flutter pub get` | Pass | Dependencies resolved under Flutter `3.44.0` / Dart `3.12.0`. |
| `flutter pub outdated` | Pass with classified drift | Riverpod/go_router major drift and transitive updates remain for a later intentional dependency migration. |
| `dart format . --set-exit-if-changed` | Pass | Final formatting gate passes with no changed files. |
| `flutter analyze --no-pub` | Pass | No analyzer issues under the verified SDK. |
| `flutter test --no-pub --concurrency=1` | Pass | `87` tests pass, including release docs, security hygiene, app shell, admin runtime, RWF formatting, and repository contract coverage. |
| Android integration smoke UAT | Prior pass; expanded rerun blocked | Earlier `flutter test --no-pub -d emulator-5554 --flavor production integration_test/app_uat_smoke_test.dart` passed `2` launch/admin-boundary integration tests on `Pixel_5_API_34_Lite`. The expanded persona harness is implemented and analyzer-clean, but current device execution is blocked by Android emulator disappearance and iOS simulator boot stall. |
| Android APK release | Pass | `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build apk --release --flavor production --no-pub` produced `build/app/outputs/flutter-apk/app-production-release.apk`; checksum manifest recorded. |
| Android appbundle release | Pass | `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build appbundle --release --flavor production --no-pub` produced `build/app/outputs/bundle/productionRelease/app-production-release.aab`; checksum manifest recorded. |
| Admin web release | Pass | `flutter build web --release -t lib/main_admin.dart --no-wasm-dry-run --no-pub` produced `build/web/main.dart.js`; checksum manifest recorded. |
| Production SMS permissions | Pass | Tests and manifest review confirm production excludes `READ_SMS` and `RECEIVE_SMS`; restricted SMS permissions are isolated to `internal_receiver`. |
| Secret hygiene | Pass | Tests cover obvious checked-in secret patterns, ignored local env files, placeholder-only Codex environment config, and `make release-secret-scan` now provides a redacted gitleaks-or-fallback release scan. |
| Admin/security rollback UAT | Pass in earlier linked evidence | `scripts/collect_admin_security_uat.sh` proves linked admin RBAC, raw-SMS reveal audit logging, moderation approval, payments-admin allocation, and read-only/support denial paths in one rolled-back transaction. Latest final release refresh still needs trusted DB connectivity. |
| Linked Supabase readiness | Blocked on latest runner | Earlier linked project health, migrations, schema, RLS, rollback UAT, Edge Function, and code-owned readiness checks passed. Latest evidence bundle is blocked by `database_connectivity`, so final release approval needs a trusted/allow-listed rerun. |
| Edge Function auth contract UAT | Pass locally | `make supabase-edge-auth-uat` passes and latest evidence includes `edge_auth_contract_uat.txt`; remote deployed endpoint and secret-name probes remain blocked by `database_connectivity`. |
| Supabase advisor gate | Pass | `make supabase-advisors` passes linked security and performance advisors at error level after converting public/member views to `security_invoker=true`, pinning helper function `search_path` settings, and removing the remaining code-owned performance policy warnings. `make supabase-advisor-warnings` freezes the warning-level advisor inventory so warning debt cannot grow silently. |
| Supabase operational report | Pass | `make supabase-operational-report` returns read-only cache, table, index, and slow-query visibility without printing secrets. |
| Strict Supabase readiness | Blocked/NO-GO | Latest strict refresh cannot complete Postgres checks because this runner is rejected by the tenant allow-list; earlier strict evidence also failed CAPTCHA/bot protection, HIBP leaked-password protection, organization Free plan, and PITR. |
| Release status summary | Pass command, NO-GO result | `make release-status` and `make release-status-json` summarize NO-GO without printing secrets. Latest blocker key is `database_connectivity`; earlier platform-control statuses showed CAPTCHA/HIBP/plan/PITR blockers. |
| Supabase evidence bundle | Pass command, NO-GO bundle | `.cache/supabase_go_live_evidence/20260524T085150Z` records final gate NO-GO and acceptance matrix `7` pass / `5` blocked. |

## Safe Fixes Made

- Installed and verified an isolated Flutter `3.44.0` / Dart `3.12.0` SDK without overwriting the existing `/Volumes/PRO-G40/Apps/SDKs/flutter` SDK.
- Updated project tooling references for the verified SDK path, including `.fvmrc`, VS Code settings, local Android properties guidance, README, and environment docs.
- Configured the official Dart/Flutter MCP through Codex using the verified Dart binary.
- Replaced project Codex environment content with placeholder-only values and added tests to prevent local secret files from becoming tracked.
- Updated the Dart SDK constraint to `^3.12.0` and added the missing `cupertino_icons` dependency used by release builds.
- Migrated the Android app module away from applying the Kotlin Gradle Plugin directly while preserving Flutter validation metadata for dependencies.
- Added local Supabase CLI/psql fallback helpers for readiness, deployment, hardening, network restriction, and linked UAT scripts.
- Added release status commands for no-secret human and machine-readable GO/NO-GO summaries, including stable platform blocker keys for automation.
- Added `make release-secret-scan` for redacted gitleaks scanning where available and a no-value-printing tracked-file fallback where it is not.
- Tightened admin RBAC role permissions and added linked rollback UAT for admin/security role boundaries.
- Converted public/member views to `security_invoker=true`, added the required caller-context grants/RLS, and wired Supabase security/performance advisors into readiness.
- Pinned `search_path` for remaining helper/trigger functions reported by Supabase advisor lint `0011_function_search_path_mutable`.
- Split broad admin `FOR ALL` RLS policies into single-action write policies and wrapped the remaining auth/helper calls so linked Supabase performance advisors report no warning-level issues for the code-owned schema.
- Removed anonymous direct RPC execute access from the platform-admin helper while preserving the anonymous collection-scope helpers required by public read views.
- Explicitly disabled GraphQL introspection on the `public` schema, removed `graphql_public` from the local exposed-schema config, and added a linked warning-level advisor inventory gate.
- Added focused release, security, manifest, RWF formatting, admin, app shell, repository, and design-system tests.
- Reduced avoidable Riverpod rebuild breadth in collection, home, ledger, payment, and admin views while preserving financial and authorization behavior.
- Replaced the earlier title-only admin shell with Supabase-backed admin runtime pages, RPC-backed lists/details/actions, permission gating, and audited raw-SMS reveal.
- Added migration `202605230017_admin_list_filter_contracts.sql` and pushed it to the linked project so admin list RPC search/status filters are real and linked SQL lint is clean.
- Added `make supabase-operational-report` for read-only live database health and performance evidence.

## Remaining Blockers

| ID | Area | Severity | Finding | Required action |
| --- | --- | --- | --- | --- |
| P0-001 | Supabase Auth | P0 | Latest runner cannot confirm live Auth status because of `database_connectivity`; local CAPTCHA provider, site key, and secret are not configured, and earlier evidence showed CAPTCHA/bot protection disabled. | Choose hCaptcha or Cloudflare Turnstile, store secrets outside the repo, run `AUTH_CAPTCHA_PROVIDER=<provider> AUTH_CAPTCHA_SITE_KEY=<site-key> AUTH_CAPTCHA_SECRET=<secret> make supabase-auth-harden`, build the Flutter auth client with CAPTCHA enabled, then rerun `make supabase-ready-strict` from a trusted/allow-listed database path. |
| P0-002 | Supabase Auth | P0 | Latest runner cannot confirm live Auth status because of `database_connectivity`; earlier evidence showed HIBP leaked-password protection disabled and the Free plan rejected enabling it with HTTP 402. | Upgrade the Supabase organization to a paid plan, rerun `make supabase-auth-harden`, and confirm `password_hibp_enabled=true` from a trusted/allow-listed database path. |
| P0-003 | Supabase backups | P0 | Latest runner cannot confirm live backup status because of `database_connectivity`; earlier evidence showed PITR disabled. | Enable PITR in Supabase project settings if low RPO is required, or record a signed recovery objective exception after non-exceptionable blockers are resolved. |
| P0-004 | Supabase billing/plan | P0 | Latest runner cannot confirm live plan status because of `database_connectivity`; earlier evidence showed the organization on the Free plan. | Upgrade the Supabase organization before launch, or record an accepted project-pause risk exception after non-exceptionable blockers are resolved. |
| P0-005 | Release verification | P0 | Latest release refresh reports `database_connectivity`; this runner cannot complete strict Postgres checks or remote Edge Function/platform verification. | Rerun release gates from trusted linked query mode or an allow-listed Supavisor/direct database path before approval. |

## Conditional Follow-Ups

- Complete remaining human-operated admin persona UAT and attach sanitized evidence before public launch.
- Ensure CI linked readiness runs only from trusted branches/runners with production Supabase secrets.
- If GraphQL is not a product requirement, disable GraphQL exposure in the Supabase API settings; the hosted project still reports GraphQL visibility warnings because public REST/view grants intentionally expose the app's required public/member API surfaces.
- Track the transitive `shared_preferences_android` Built-in Kotlin warning and upgrade when an upstream-compatible plugin release is available.
- Review the large dirty worktree and stage only the intended release changes.

## Decision Basis

NO-GO. The Flutter/Dart `3.44.0` / `3.12.0` migration, analyzer, test suite,
Android release artifacts, admin web artifact, production SMS permission
posture, secret hygiene tests, release secret scan, local Edge Function auth
contract UAT, Supabase schema inventory, advisor inventory, and operational
report have pass evidence. Public production launch remains blocked by latest
release-verification connectivity plus the unresolved operator-owned Supabase
platform settings: CAPTCHA/bot protection, HIBP leaked-password protection on a
paid plan, Free-plan project-pause risk, and PITR.

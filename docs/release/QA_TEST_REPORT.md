# Collect QA Test Report

Audit date: 2026-05-24

## Commands And Results

| Command | Result | Notes |
| --- | --- | --- |
| `git status --short` | Dirty | Substantial pre-existing reset/rewrite state; release staging still needs human review. |
| `git branch --show-current` | Pass | `refactor/collect-repo-reset`. |
| `/Volumes/PRO-G40/flutter_3_44/bin/flutter --version` | Pass | Flutter `3.44.0`, Dart `3.12.0`. |
| `/Volumes/PRO-G40/flutter_3_44/bin/dart --version` | Pass | Dart `3.12.0`. |
| `codex --version` / `codex mcp list` | Pass | Codex `0.130.0`; global `dart` MCP uses `/Volumes/PRO-G40/flutter_3_44/bin/dart mcp-server --force-roots-fallback`. |
| `/Volumes/PRO-G40/flutter_3_44/bin/flutter clean` | Pass | Clean completed during the SDK upgrade run. |
| `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get` | Pass | Dependencies resolved under Dart `3.12.0`. |
| `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub outdated` | Pass with classified drift | Riverpod/go_router major drift and transitive drift remain for a separate intentional migration. |
| `/Volumes/PRO-G40/flutter_3_44/bin/dart format --set-exit-if-changed .` | Pass | Final result: `103` files checked, `0` changed. |
| `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub` | Pass | No issues found. |
| `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub --concurrency=1` | Pass | `87` tests passed. |
| `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub -d emulator-5554 --flavor production integration_test/app_uat_smoke_test.dart` | Prior pass; expanded rerun blocked | Earlier `2`-test launch/admin-boundary smoke passed on `Pixel_5_API_34_Lite`. The expanded persona integration harness is implemented and analyzer-clean, but the current device rerun is blocked because the Android emulator disappeared from ADB/Flutter and the iOS simulator stalled at BackBoard. |
| `make release-secret-scan` | Pass | `gitleaks` is not installed locally, so the command used the no-value-printing tracked/untracked file fallback and passed. |
| `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build apk --release --flavor production --no-pub` | Pass | Produced `build/app/outputs/flutter-apk/app-production-release.apk`; hash recorded in `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-24.sha256`. |
| `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build appbundle --release --flavor production --no-pub` | Pass | Produced `build/app/outputs/bundle/productionRelease/app-production-release.aab`; hash recorded in `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-24.sha256`. |
| `/Volumes/PRO-G40/flutter_3_44/bin/flutter build web --release -t lib/main_admin.dart --no-wasm-dry-run --no-pub` | Pass | Produced `build/web/main.dart.js`. |
| `make supabase-ready` | Earlier pass; latest release refresh blocked | Earlier linked code-owned readiness passed project health, migrations, schema, RLS, rollback UAT, Edge Function checks, and readiness probes. Latest release evidence must be rerun from trusted linked query mode or an allow-listed DB path because this runner now reports `database_connectivity`. |
| `make supabase-advisors` | Pass | Linked security/performance advisors report no error-level findings after public/member views were switched to caller-context `security_invoker=true`, helper function `search_path` settings were pinned, and broad admin write policies were split by action. |
| `make supabase-advisor-warnings` | Pass | Warning-level performance advisors remain clean, and known warning-level security advisor inventory is capped so new warning debt fails readiness. |
| `make supabase-operational-report` | Pass | Read-only report returned cache hit ratio, table estimates, index usage, and `pg_stat_statements` slow-query visibility without printing secrets. |
| `scripts/collect_admin_security_uat.sh` | Pass | Linked rollback UAT proved admin RBAC, raw-SMS reveal audit logging, moderation approval, payments-admin allocation, and support/read-only denial paths. |
| `make supabase-edge-auth-uat` | Pass | Local Edge Function auth contract passed and is included in `.cache/supabase_go_live_evidence/20260524T085150Z/edge_auth_contract_uat.txt`. |
| `make release-status-json` | Pass command, NO-GO result | Latest redacted summary reports `database_connectivity`; earlier evidence reports CAPTCHA/bot protection, HIBP leaked-password protection, Free-plan project-pause risk, and PITR as strict blockers with stable blocker keys. |
| `make supabase-go-live-evidence` | Pass command, NO-GO bundle | Generated `.cache/supabase_go_live_evidence/20260524T085150Z`; acceptance matrix is `7` pass / `5` blocked with blocker key `database_connectivity`. |
| `make supabase-ready-strict` | Blocked/NO-GO | Latest release verification cannot complete strict Postgres checks from this runner; earlier strict release gate failed on CAPTCHA/bot protection, HIBP leaked-password protection, Free-plan project-pause risk, and PITR. |

## QA Findings

- P0: Supabase CAPTCHA/bot protection must be configured before public launch.
- P0: Supabase HIBP leaked-password protection must be enabled after upgrading to a paid plan.
- P0: Supabase organization plan must be upgraded, or project-pause risk must be accepted in writing before public launch.
- P0: Supabase PITR must be enabled, or a signed recovery objective exception must be recorded before public launch.
- P1: Admin human persona UAT still needs live signoff; linked rollback admin/security UAT now passes.
- P1: `shared_preferences_android` still emits a transitive Built-in Kotlin warning for future Flutter releases.
- P2: Dependency drift remains intentionally deferred outside this SDK migration.
- Supabase SQL lint previously passed cleanly after admin list filters were wired to the shared search/status controls; final release approval still needs a trusted rerun because the latest runner reports `database_connectivity`.

## Fixes Made During QA

- Installed and verified the isolated Flutter `3.44.0` / Dart `3.12.0` SDK.
- Updated toolchain references, SDK constraints, MCP setup docs, README, environment docs, and release docs.
- Repaired compile/analyzer drift and added focused release, security, admin, app shell, RWF, repository, and Supabase contract tests.
- Added no-secret release status commands.
- Added `make release-secret-scan` with redacted gitleaks support and a no-value-printing fallback scanner.
- Tightened admin RBAC role permissions and added linked rollback admin/security UAT.
- Added linked Supabase advisor gate and fixed security-definer view advisor errors with `security_invoker=true` views.
- Fixed remaining mutable helper function `search_path` warnings reported by Supabase security advisors.
- Fixed code-owned Supabase performance advisor warnings by splitting broad permissive admin write policies and wrapping auth/helper calls in RLS policies.
- Removed anonymous direct execute access from `current_user_is_platform_admin()` after linked rollback checks proved anonymous public read surfaces do not require it.
- Disabled GraphQL introspection for the public schema, removed `graphql_public` from local exposed schemas, and added a warning-level Supabase advisor inventory gate.
- Added linked Supabase query readiness with direct Postgres/pooler fallback for operator scripts.
- Added migration `202605230017_admin_list_filter_contracts.sql` so admin list RPC search/status parameters are consumed by the remote schema.
- Added `make supabase-operational-report` for live read-only database health and performance evidence.
- Preserved payment, allocation, ledger, RLS, production data, and external integration behavior except where tests/docs were added to prevent exposure or permission regression.

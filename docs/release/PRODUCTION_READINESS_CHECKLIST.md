# Collect Production Readiness Checklist

Audit date: 2026-05-24

| Check | Status | Evidence |
| --- | --- | --- |
| Verified Flutter SDK | Pass | `/Volumes/PRO-G40/flutter_3_44/bin/flutter --version`: Flutter `3.44.0`, Dart `3.12.0`. |
| Verified Dart SDK | Pass | `/Volumes/PRO-G40/flutter_3_44/bin/dart --version`: Dart `3.12.0`. |
| Codex Dart/Flutter MCP | Pass | `codex mcp list` shows `dart` enabled with `/Volumes/PRO-G40/flutter_3_44/bin/dart mcp-server --force-roots-fallback`. |
| Format | Pass | `dart format . --set-exit-if-changed`: pass. |
| Analyze | Pass | `flutter analyze --no-pub`: no issues. |
| Tests | Pass | `flutter test --no-pub --concurrency=1`: `87` tests pass. |
| Android integration smoke UAT | Pass | `flutter test --no-pub -d emulator-5554 --flavor production integration_test/app_uat_smoke_test.dart`: `2` integration tests pass on `Pixel_5_API_34_Lite`. |
| Android APK release | Pass | `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build apk --release --flavor production --no-pub`: `build/app/outputs/flutter-apk/app-production-release.apk`; checksum recorded in `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-24.sha256`. |
| Android appbundle release | Pass | `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build appbundle --release --flavor production --no-pub`: `build/app/outputs/bundle/productionRelease/app-production-release.aab`; checksum recorded in `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-24.sha256`. |
| Admin web release | Pass | `flutter build web --release -t lib/main_admin.dart --no-wasm-dry-run --no-pub`: `build/web/main.dart.js`. |
| Production Android SMS permissions | Pass | Test and manifest review confirm production manifest excludes `READ_SMS`/`RECEIVE_SMS`; restricted permissions are isolated to `internal_receiver`. |
| Money handling | Pass | RWF formatter tests cover integer-only display; no floats introduced for money in the upgrade work. |
| Secret hygiene | Pass | Security tests cover obvious live secret patterns, ignored local env files, placeholder-only Codex env config, and `make release-secret-scan` runs a redacted gitleaks-or-fallback release scan. |
| Supabase linked code readiness | Blocked on latest runner | Earlier linked readiness passed, but latest refreshed evidence reports `database_connectivity`; rerun `make supabase-ready` from trusted linked query mode or an allow-listed DB path before final approval. |
| Supabase live schema inventory | Pass | `make supabase-schema-inventory` reports expected public objects `160`, remote public objects `160`, extra `0`, missing `0`, RLS `28/28`, policies `61`, views `9`, functions `57`, and pinned function search paths `57/57`. |
| Supabase advisor gate | Pass | `make supabase-advisors` passes linked security/performance advisors at error level; public/member views now use `security_invoker=true`, helper function `search_path` settings are pinned, and code-owned performance policy warnings have been removed. |
| Supabase advisor warning inventory | Pass | `make supabase-advisor-warnings` requires warning-level performance advisors to stay clean and fails if known warning-level security advisor debt grows. |
| Supabase anonymous RPC surface | Pass | Anonymous direct execute access is limited to collection-scope helpers still required by public read views; `current_user_is_platform_admin()` is no longer executable by `anon`. |
| Supabase operational report | Pass | `make supabase-operational-report` returns read-only JSON for cache hit ratio, table row/dead-row estimates, index usage, and slow-query visibility. |
| Supabase final go-live gate | Blocked/NO-GO | `make supabase-go-live-gate` combines strict status and signed exception validation. Latest `make supabase-go-live-gate-json` reports `database_connectivity`; earlier evidence still showed CAPTCHA and HIBP as non-exceptionable blockers. |
| Supabase latest runner gate refresh | Blocked | Latest `make release-status-json` and `make supabase-go-live-gate-json` report `database_connectivity`; the Supabase tenant allow-list rejected this runner address, so final platform status must be refreshed from trusted linked query mode or an allow-listed DB path. |
| Supabase go-live evidence bundle | Pass | `make supabase-go-live-evidence` creates a local redacted bundle with strict status, final go-live gate result, platform packet, platform exception-gate result, live schema inventory, advisor warnings, operational report, code-owned readiness, secret scan, command exit codes, and summary JSON under `.cache/`. |
| Supabase Edge Function auth contract UAT | Pass locally | `make supabase-edge-auth-uat` passes and is included in the latest evidence bundle as `edge_auth_contract_uat.txt`; remote endpoint and secret-name verification still need trusted database connectivity. |
| Supabase platform exception gate | Blocked/NO-GO | `make supabase-platform-exception-gate` validates signed exception records only for Free-plan project-pause risk and PITR/RPO risk. Latest evidence is blocked by `database_connectivity`; after trusted verification is restored, it must still fail while CAPTCHA or HIBP remain strict blockers because those are non-exceptionable. |
| Supabase admin/security UAT | Pass | `scripts/collect_admin_security_uat.sh` passes linked rollback UAT for admin RBAC, raw-SMS reveal audit logging, moderation approval, payments-admin allocation, and denial paths. |
| Supabase strict production readiness | Blocked/NO-GO | Latest `make release-status-json` reports `database_connectivity`, so strict Postgres checks and live platform controls are not currently confirmable from this runner. Earlier strict evidence failed because CAPTCHA/bot protection was disabled, HIBP leaked-password protection was disabled, the organization was on the Free plan, and PITR was disabled. |
| Supabase release verification path | Blocked | Latest runner refresh cannot complete strict Postgres checks and reports blocker key `database_connectivity`. |
| Supabase CAPTCHA/bot protection | Blocked | Latest runner cannot confirm live Auth status because of `database_connectivity`; local CAPTCHA provider, site key, and secret inputs are still missing and earlier evidence showed CAPTCHA disabled. |
| Supabase HIBP leaked-password protection | Blocked | Latest runner cannot confirm live Auth status because of `database_connectivity`; earlier evidence showed `password_hibp_enabled=false`, and enabling it requires a paid Supabase plan. |
| Supabase PITR | Blocked | Latest runner cannot confirm live backup status because of `database_connectivity`; earlier evidence showed PITR disabled. Enable PITR or record a signed recovery-objective exception after non-exceptionable blockers are resolved. |
| Supabase organization plan | Blocked | Latest runner cannot confirm live plan status because of `database_connectivity`; earlier Management API evidence showed the organization on the Free plan. Upgrade or record an accepted Free-plan project-pause risk exception after non-exceptionable blockers are resolved. |
| Supabase GraphQL exposure | Conditional | The app does not use GraphQL. GraphQL introspection is explicitly disabled for `public`, and local exposed schemas exclude `graphql_public`. Disable GraphQL/Data API exposure in Supabase API settings before public launch if REST/RPC remains the only supported API surface. |
| Android Built-in Kotlin app migration | Pass with transitive warning | App module no longer applies KGP and release builds pass; Flutter still warns that `shared_preferences_android` applies KGP. |
| Dependency drift | Conditional | `flutter pub outdated` passes and classifies Riverpod/go_router major updates and transitive drift for later migration. |
| CI/CD linked readiness | Conditional | Readiness database checks use `supabase db query --linked` by default, so IPv6-only direct Postgres access is no longer required for normal linked readiness. Release approval still requires a trusted runner or allow-listed database path because the latest local refresh reports `database_connectivity`. `SUPABASE_READINESS_DATABASE_URL` or `DATABASE_POOLER_URL` remains available as a fallback when `SUPABASE_DB_QUERY_MODE=direct` is used. |
| UAT | Pending human signoff | Release artifacts, Android device smoke UAT, linked rollback database/admin UAT, and persona evidence mapping pass. Full operator/persona signoff still needs to be recorded in `docs/release/UAT_SIGNOFF_CHECKLIST_2026-05-24.md` before public launch. |

## Release Approval Command

Informational summary:

```sh
make release-status
```

This command runs the strict gate, prints only presence/missing flags for CAPTCHA inputs, and summarizes blockers without printing secrets. For automation, use:

```sh
make release-status-json
```

The JSON output includes redacted CAPTCHA input presence, stable `blocker_keys`,
and a `platform` object for `auth_captcha_bot_protection`,
`auth_hibp_leaked_password_protection`, `supabase_organization_plan`, and
`supabase_pitr`.

Operator handoff:

```sh
make supabase-platform-packet
make supabase-platform-packet-json
```

This prints a redacted platform remediation packet with required inputs, safe
commands, verification commands, and Supabase documentation links for each
strict blocker.

Post-operator verification:

```sh
make supabase-post-operator-checklist
make supabase-post-operator-checklist-json
```

Use this after the operator changes Supabase billing/Auth/backup settings. It
prints a redacted checklist with pass conditions and final verification commands
for each remaining strict blocker.

Live schema inventory:

```sh
make supabase-schema-inventory
make supabase-schema-inventory-json
```

This is the release evidence for the current public schema object contract and
RLS/policy/function posture.

Go-live evidence bundle:

```sh
make supabase-go-live-evidence
```

Use this before release review so the redacted evidence is collected in one
local `.cache/supabase_go_live_evidence/` folder. The bundle includes
`post_operator_checklist.json` and `acceptance_matrix.json` so release review
can see the exact follow-up path and requirement-by-requirement status without
exposing secrets.

Acceptance matrix:

```sh
make supabase-acceptance-matrix
make supabase-acceptance-matrix-json
```

Use this against the latest evidence bundle before any release review. It
separates completed code/schema controls from platform/operator blockers.

Final go-live gate:

```sh
make supabase-go-live-gate
make supabase-go-live-gate-json
```

This is the final release approval command. It can approve a release only when
strict Supabase readiness passes, or when every remaining blocker is
exceptionable and covered by a valid signed exception file.

Platform exception gate:

```sh
make supabase-platform-exception-gate
```

Use this only after CAPTCHA and HIBP are resolved. It validates a signed
`docs/release/SUPABASE_PLATFORM_EXCEPTIONS.json` record for any remaining
Free-plan or PITR/RPO exception.

Secret release scan:

```sh
make release-secret-scan
```

This command runs `gitleaks detect --redact` when available. If `gitleaks` is
not installed, it scans tracked and non-ignored untracked release files with a
no-value-printing fallback.

Release gate:

```sh
make supabase-ready-strict
```

This is the current release gate. It must pass from a trusted/allow-listed
database path, or the remaining exceptionable Supabase platform risks must be
accepted in writing by the release owner after non-exceptionable blockers are
resolved.

## Remaining P0 Actions

1. Enable Supabase CAPTCHA/bot protection.
   - Reference: https://supabase.com/docs/guides/auth/auth-captcha
   - Command after obtaining the provider secret:

```sh
AUTH_CAPTCHA_PROVIDER=hcaptcha AUTH_CAPTCHA_SITE_KEY="<provider-site-key>" AUTH_CAPTCHA_SECRET="<provider-secret>" make supabase-auth-harden
```

2. Enable HIBP leaked-password protection after plan upgrade.

```sh
make supabase-auth-harden
```

3. Enable PITR or document accepted RPO.
   - Reference: https://supabase.com/docs/guides/platform/backups
   - Usage/billing reference: https://supabase.com/docs/guides/platform/manage-your-usage/point-in-time-recovery
   - Guarded helper: `PITR_ADDON_VARIANT=pitr_7 CONFIRM_ENABLE_PITR="$SUPABASE_PROJECT_REF:pitr_7" make supabase-pitr-enable`
   - Signed exception template: `docs/release/SUPABASE_PLATFORM_EXCEPTIONS.example.json`

4. Upgrade Supabase organization plan or record an accepted Free-plan project-pause risk exception.
   - Signed exception template: `docs/release/SUPABASE_PLATFORM_EXCEPTIONS.example.json`

5. Rerun:

```sh
make supabase-ready-strict
```

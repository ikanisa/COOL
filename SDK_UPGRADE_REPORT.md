# SDK Upgrade Report

## SDK

- Installed isolated SDK: `/Volumes/PRO-G40/flutter_3_44`
- Flutter: `3.44.0`
- Dart: `3.12.0`
- Previous discovered `/Volumes/PRO-G40` SDK: `/Volumes/PRO-G40/Apps/SDKs/flutter`, Flutter `3.38.9`, Dart `3.10.8`

## Tooling Changes

- Updated `.fvmrc` to Flutter `3.44.0`.
- Updated `pubspec.yaml` SDK constraint to `^3.12.0`.
- Updated VS Code settings and local Android `flutter.sdk` to `/Volumes/PRO-G40/flutter_3_44`.
- CI keeps the existing `.fvmrc`-driven Flutter setup; `.fvmrc` now resolves to Flutter `3.44.0`.
- Updated README and environment docs with absolute verified SDK commands.
- Removed the app module's applied `kotlin-android` plugin and migrated app Kotlin compiler options to the `kotlin { compilerOptions { ... } }` DSL. The Kotlin plugin version remains declared in `settings.gradle.kts` for Flutter dependency validation metadata.
- Added shared Supabase CLI helpers so readiness, deployment, auth hardening, network restriction, and linked UAT scripts use `SUPABASE_BIN`, a `supabase` command on `PATH`, or `npx -y supabase`; linked database scripts also use `PSQL_BIN`, `psql` on `PATH`, or `/Library/PostgreSQL/15/bin/psql`.
- Added `make release-status` and `make release-status-json` for no-secret GO/NO-GO summaries that run the strict Supabase gate and report CAPTCHA input presence.

## MCP

- Verified `codex --version`: `codex-cli 0.130.0`.
- Added global Dart MCP server using `/Volumes/PRO-G40/flutter_3_44/bin/dart mcp-server --force-roots-fallback`.
- `codex mcp list` reports `dart` as enabled.

## Safety

- Replaced project `.codex/environments/environment.toml` with placeholder-only values.
- Added tests that assert production Android does not request SMS permissions.
- Added repository secret-pattern guard for obvious API key, token, JWT, and database URL shapes.
- Added tests that assert `.env`, `.env.local`, and `.env.json` remain untracked/ignored, and that Codex environment placeholders do not contain sensitive values.
- Added tests that assert Supabase operator scripts keep using local CLI fallback helpers instead of bare `supabase`/`psql` calls.

## Dependency Changes

- Removed the unused platform-icon dependency after the application
  migrated all owned controls to the central Material semantic-icon layer.
- `supabase_flutter` resolved to `2.12.4`.
- Supabase transitive packages were refreshed by `flutter pub get`.
- `flutter_riverpod` and `go_router` were left on their current major versions because newer releases require intentional migration work outside this SDK compatibility pass.

## Validation

All commands below were run with `/Volumes/PRO-G40/flutter_3_44/bin/flutter` or `/Volumes/PRO-G40/flutter_3_44/bin/dart`.

- PASS: `flutter clean`
- PASS: `flutter pub get`
- PASS: `flutter pub outdated`
- PASS: `dart format . --set-exit-if-changed`
- PASS: `flutter analyze`
- PASS: `flutter test --no-pub --concurrency=1` completed with `62` tests passing after the dependency refresh and script fallback guard addition.
- PASS: focused `test/security_hygiene_test.dart` completed with `4` passing tests after adding the Supabase operator-script fallback guard.
- PASS: `flutter build apk --release --flavor production` completed after the app-side Kotlin migration in `515.6s` and produced `build/app/outputs/flutter-apk/app-production-release.apk`.
- PASS: `flutter build appbundle --release --flavor production` completed after the app-side Kotlin migration in `120.7s` and produced `build/app/outputs/bundle/productionRelease/app-production-release.aab`.
- PASS: `flutter build web --release -t lib/main_admin.dart --no-wasm-dry-run` completed after the dependency refresh and produced `build/web/main.dart.js`.
- PASS: `make supabase-ready` ran with local fallback tooling, confirmed the linked Supabase project is active/healthy, remote migrations are up to date, schema contract is exact, RLS is enabled on `28/28` public base tables, linked rollback UAT passed, Edge Function auth/endpoints/secrets passed, and code-owned readiness checks passed.
- BLOCKED: `make supabase-ready-strict` fails on platform settings outside the repo: CAPTCHA/bot protection is disabled and PITR is disabled.

## Warnings

- Android builds no longer warn that the app module applies the Kotlin Gradle Plugin. They still warn that `shared_preferences_android` applies KGP; this must be resolved by a compatible plugin release or dependency strategy before future Flutter versions make it fatal.
- A clean dependency resolution contains no legacy platform-icon package. Current
  release artifacts bundle Inter for product typography and the tree-shaken
  Material icon font for semantic controls; no Cupertino font is packaged.
- Supabase DB lint reports warning-level unused parameters in several admin RPCs; `--fail-on error` passes.

## Production Readiness Impact

- SDK migration, analyzer, unit/widget tests, Android release packaging, and admin web release packaging are resolved on Flutter `3.44.0` / Dart `3.12.0`.
- Code-owned Supabase linked readiness passes. Strict production readiness remains blocked until CAPTCHA/bot protection and PITR are enabled in Supabase project settings.
- Production SMS permission posture is protected by tests: production manifest must remain free of `READ_SMS` and `RECEIVE_SMS`, while the internal receiver flavor owns SMS permissions.

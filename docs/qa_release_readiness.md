# QA / Release Readiness

This checklist tracks the current release gates for the Cool mobile app.

Google Wallet is deferred to Phase 2 and is not part of the current release
candidate gate.

## Required Release Gates

No build is release-candidate quality unless every gate below is green.

| Gate | Requirement | Source of truth |
|---|---|---|
| **Supabase backend contract** | **The production Supabase URL/key pair MUST be set** before building any APK or AAB. `SUPABASE_STAGING_*` is optional and only required when you intentionally maintain a separate staging backend. Build scripts validate `SUPABASE_PRODUCTION_*`, optionally validate staging when provided, and Dart runtime validates the baked project ref. | `scripts/validate_backend_config.sh`, `scripts/_android_release_build.sh`, `scripts/build_staging.sh`, `lib/core/config/env_config.dart` |
| Hosted function secrets | Hosted Supabase function secrets are synced from CI before the release gate runs, and the hosted smoke must pass when `SUPABASE_PROJECT_REF` + `SUPABASE_ACCESS_TOKEN` are configured | `scripts/sync_supabase_function_secrets.sh`, `.github/workflows/release.yml`, `scripts/supabase_contract_smoke.sh` |
| Static analysis | `flutter analyze` passes with zero issues | `scripts/release_readiness.sh` |
| Flutter tests | `flutter test` passes with zero failures | `scripts/release_readiness.sh` |
| Deep-link assets | `dart tool/deep_link_release_assets.dart --check` passes against `deeplinks/release_metadata.json`. Android Play-signing metadata is always required; iOS Team/App Store metadata is required only when an iOS release is being validated (`COOL_REQUIRE_IOS_RELEASE_METADATA=1`). | `scripts/release_readiness.sh` and hosted `.well-known` files |
| Edge-function checks | Deno checks for critical Supabase functions pass | `scripts/release_readiness.sh` plus targeted `deno check` / `deno test` |
| Operational dashboard | Admin > Operations shows no critical triage issues and no failing server-trusted surfaces | `/admin/operations` and `docs/OPERATIONAL_OBSERVABILITY.md` |
| Route governance | Any route change updates `docs/ROUTE_INVENTORY.md` | PR review |
| Screen governance | New routes stay within `docs/SCREEN_BUDGETS.md` budget | PR review |
| Smoke coverage | Every new user-facing route has at least one route, widget, or flow smoke test | PR review |

## Automated Gates

Run the consolidated check:

```bash
bash scripts/release_readiness.sh
```

That covers:

- `flutter analyze --fatal-infos`
- `bash scripts/validate_backend_config.sh`
- `flutter test --exclude-tags=integration`
- `flutter test test/integration_smoke`
- `dart tool/deep_link_release_assets.dart --generate --check`
- `bash scripts/validate_supabase_migrations.sh`
- `dart tool/biopay_model_contract.dart --check`
- `dart tool/governance_docs.dart --check`
- Android and iOS flavor verification builds
- `deno test` across every `supabase/functions/*_test.ts`
- `deno check` across every TypeScript edge-function source file

When release metadata changes, regenerate the committed association files first:

```bash
dart tool/deep_link_release_assets.dart --generate
```

Supporting governance docs:

- [`ROUTE_INVENTORY.md`](./ROUTE_INVENTORY.md)
- [`SCREEN_BUDGETS.md`](./SCREEN_BUDGETS.md)
- [`RELEASE_PROCESS.md`](./RELEASE_PROCESS.md)
- [`OPERATIONAL_OBSERVABILITY.md`](./OPERATIONAL_OBSERVABILITY.md)

Optional migration apply:

```bash
RUN_MIGRATION_APPLY=1 DATABASE_URL="postgresql://..." bash scripts/release_readiness.sh
```

Optional but recommended release gates:

```bash
RUN_ANDROID_MINIFY_CANARY=1 \
RUN_REMOTE_SMOKE=1 \
RUN_MOMO_SMS_ROLLOUT_VERIFY=1 \
bash scripts/release_readiness.sh
```

These enable the production minify canary, linked-project remote smoke, and
M-Money rollout verification when the required secrets are available.

For a real Android release-candidate pass, use the stricter wrapper:

```bash
RUN_ANDROID_MINIFY_CANARY=1 \
RUN_REMOTE_SMOKE=1 \
RUN_MOMO_SMS_ROLLOUT_VERIFY=1 \
bash scripts/run_release_candidate.sh
```

That command additionally verifies:

- `deeplinks/release_metadata.json` against release signing metadata
- Firebase App Check provider registration for the Android production app
- signed Android APK and AAB artifact generation

iOS store release automation is explicitly de-scoped in the current repo. Keep
`COOL_IOS_RELEASE_ENABLED=0` until a signed TestFlight / App Store lane exists.

Production-only release mode is supported. If `SUPABASE_STAGING_*` is unset,
backend validation skips staging and treats production as the only required
release backend target.

If repo-local env files still define `SUPABASE_STAGING_*`, set
`COOL_SKIP_STAGING_BACKEND_VALIDATION=1` to force the same production-only
behavior during release validation.

## QA Matrix

| ID | Scope | Status | Notes |
|---|---|---|---|
| QA-01 | Payment confirmation idempotency | Automated | Duplicate MoMo confirmations are covered by the `parse-momo-sms` reconciliation tests. |
| QA-02 | Auth routing and profile gating | Automated | Route gating and redirect preservation are covered by `test/core/app_router_feature_gate_test.dart` and `test/integration_smoke/deep_link_test.dart`. |
| QA-03 | Critical journey smoke coverage | Automated + manual | Host-side smoke tests cover boot, deep links, and MoMo route smoke; a connected-device UI pass is still required for real payment and SMS behavior. |
| QA-04 | Release readiness review | Mixed | Automated checks are scripted. Route inventory, screen budget, smoke coverage, and the operations dashboard are PR/release gates. |

## Manual Critical Journey Pass

Run these on an Android release build before submission:

1. Sign in from a cold start and confirm splash, onboarding, OTP, invite, and register transitions preserve the intended target and prefilled context.
2. Open Home, Contribution Circles, and MoMo statements; verify each surface renders without placeholder or empty-state regressions.
3. Start a contribution flow and confirm the MoMo handoff displays the expected amount and route details.
4. Complete the SMS confirmation flow and verify the reconciled transaction appears in statements without duplication.
5. Open BioPay register, scan, and NFC entry points and verify unsupported-device messaging is graceful where required.
6. Open Admin > Workspaces and confirm platform and bank access gates only show authorized destinations.
7. Open at least one bank workspace and verify allocations, group ledgers, and export actions render without missing data.
8. Open Admin > Operations and confirm there are no critical payment sync, Edge Function, or config triage items.

## Permission Review

Confirm before submission:

- Android manifest only declares `READ_SMS` and `RECEIVE_SMS` for M-Money verification.
- In-app disclosure says only approved M-Money sender IDs are processed.
- Play Console declarations match the actual SMS usage and data handling flow.
- `deeplinks/release_metadata.json` contains the real Apple Team ID, App Store listing ID, and Android signing fingerprints for the build being submitted.

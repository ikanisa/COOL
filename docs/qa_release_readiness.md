# QA / Release Readiness

This checklist tracks the current release gates for the Cool mobile app.

Google Wallet is deferred to Phase 2 and is not part of the current release
candidate gate.

## Required Release Gates

No build is release-candidate quality unless every gate below is green.

| Gate | Requirement | Source of truth |
|---|---|---|
| **Supabase env vars** | **`SUPABASE_URL` and `SUPABASE_ANON_KEY` MUST be set** before building any APK or AAB. Build scripts abort without them; Dart runtime shows config error screen if empty. | `scripts/_android_release_build.sh`, `scripts/build_staging.sh`, `lib/core/config/env_config.dart` |
| Static analysis | `flutter analyze` passes with zero issues | `scripts/release_readiness.sh` |
| Flutter tests | `flutter test` passes with zero failures | `scripts/release_readiness.sh` |
| Deep-link assets | `dart tool/deep_link_release_assets.dart --check` passes against `deeplinks/release_metadata.json`, with populated AASA details and no placeholder store metadata | `scripts/release_readiness.sh` and hosted `.well-known` files |
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

- `flutter analyze`
- `flutter test`
- `dart tool/deep_link_release_assets.dart --check`
- `deno test supabase/functions/parse-momo-sms/reconciliation_test.ts`

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

## QA Matrix

| ID | Scope | Status | Notes |
|---|---|---|---|
| QA-01 | Payment confirmation idempotency | Automated | Duplicate MoMo confirmations are covered by the `parse-momo-sms` reconciliation tests. |
| QA-02 | Auth routing and profile gating | Automated | Route gating and redirect preservation are covered by `test/core/app_router_feature_gate_test.dart` and `test/integration_smoke/deep_link_test.dart`. |
| QA-03 | Critical journey smoke coverage | Automated + manual | Host-side smoke tests cover boot, deep links, and MoMo; a connected-device UI pass is still required. |
| QA-04 | Release readiness review | Mixed | Automated checks are scripted. Route inventory, screen budget, smoke coverage, and the operations dashboard are PR/release gates. |

## Manual Critical Journey Pass

Run these on an Android release build before submission:

1. Sign in from a cold start and confirm splash, onboarding, OTP, and register transitions preserve the intended redirect target.
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

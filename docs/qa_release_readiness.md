# QA / Release Readiness

This checklist tracks the current release gates for the Cool mobile app.

## Required Release Gates

No build is release-candidate quality unless every gate below is green.

| Gate | Requirement | Source of truth |
|---|---|---|
| Static analysis | `flutter analyze` passes with zero issues | `scripts/release_readiness.sh` |
| Flutter tests | `flutter test` passes with zero failures | `scripts/release_readiness.sh` |
| Edge-function checks | Deno checks for critical Supabase functions pass | `scripts/release_readiness.sh` plus targeted `deno check` / `deno test` |
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
- `deno test supabase/functions/parse-momo-sms/rayon_confirmation_test.ts`

Supporting governance docs:

- [`ROUTE_INVENTORY.md`](./ROUTE_INVENTORY.md)
- [`SCREEN_BUDGETS.md`](./SCREEN_BUDGETS.md)
- [`RELEASE_PROCESS.md`](./RELEASE_PROCESS.md)

Optional migration apply:

```bash
RUN_MIGRATION_APPLY=1 DATABASE_URL="postgresql://..." bash scripts/release_readiness.sh
```

## QA Matrix

| ID | Scope | Status | Notes |
|---|---|---|---|
| QA-01 | Payment confirmation idempotency | Automated | Duplicate Rayon ticket, shop, and support confirmations are covered by `rayon_confirmation_test.ts`. |
| QA-02 | Auth routing and profile gating | Automated | Redirect rules are covered by `test/core/app_router_redirect_test.dart`. |
| QA-03 | Rayon flow smoke coverage | Automated + manual | Notifier smoke tests cover membership load, clubs, tickets, shop, and support. Manual UI pass is still required on device. |
| QA-04 | Release readiness review | Mixed | Automated checks are scripted. Route inventory, screen budget, and smoke coverage are PR review gates. |

## Manual Rayon Smoke Pass

Run these on an Android release build before submission:

1. Sign in from a cold start and confirm splash, onboarding, OTP, and register transitions preserve the intended redirect target.
2. Open Rayon Sports and verify membership card, profile, and registry load without placeholder or empty-state regressions.
3. Join a fan club and confirm the success state survives app resume.
4. Add shop items to cart, start checkout, and confirm the MoMo handoff message shows the expected amount and MTN code.
5. Open support initiatives, start a contribution, and confirm the MoMo handoff appears with the expected amount.
6. Buy a ticket, confirm the pending ticket appears, and complete the SMS confirmation flow until the ticket becomes valid.
7. Open My Tickets and Ticket Confirmation, then verify the QR and status surfaces render without missing data.

## Permission Review

Confirm before submission:

- Android manifest only declares `READ_SMS` and `RECEIVE_SMS` for M-Money verification.
- In-app disclosure says only approved M-Money sender IDs are processed.
- Play Console declarations match the actual SMS usage and data handling flow.

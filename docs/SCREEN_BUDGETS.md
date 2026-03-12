# Screen Budgets

Last updated: March 12, 2026

This document sets the composition budget for Flutter screens under
`lib/features/**/screens/*.dart`.

Why this exists:

- The app currently has multiple routes above `1,000` LOC.
- Feature sprawl is now a bigger risk than missing capability.
- New work needs a hard guardrail before more routes become multi-product
  surfaces.

## Budget Rules

### New Screens

| Budget | Threshold | Requirement |
|---|---|---|
| Target | `<= 400` LOC | Normal case for new user-facing routes |
| Review | `401-700` LOC | Allowed only with extracted widgets/services and a justification in PR notes |
| Block | `> 700` LOC | Do not merge as a new route without splitting the flow |

### Existing Screens

| Budget | Threshold | Requirement |
|---|---|---|
| Stable | `<= 700` LOC | Can evolve normally |
| Debt | `701-1000` LOC | Any new work must reduce or at least not increase route responsibility |
| Hotspot | `> 1000` LOC | Do not grow the file unless the PR is explicitly simplifying or extracting it |

## Required Counterweights

If a PR touches a screen over budget, it must include at least one of:

- widget extraction that removes route-level branching
- service/provider extraction that removes side effects from the screen file
- route split into focused subroutes or steps
- smoke coverage for the changed primary flow

If a PR adds a new route, it must also:

- update [`ROUTE_INVENTORY.md`](./ROUTE_INVENTORY.md)
- add at least one route smoke, widget smoke, or routing regression test
- stay within the new-screen budget above

## Current Hotspots

Measured on March 12, 2026 from `lib/features/**/screens/*.dart`.

| Screen | LOC | Status |
|---|---|---|
| `schedule_trip_screen.dart` | `2670` | Hotspot |
| `profile_screen.dart` | `1823` | Hotspot |
| `driver_profile_screen.dart` | `1595` | Hotspot |
| `trip_board_screen.dart` | `1529` | Hotspot |
| `mobility_home_screen.dart` | `1376` | Hotspot |
| `bank_partner_screen.dart` | `1349` | Hotspot |
| `credit_score_screen.dart` | `1318` | Hotspot |
| `credit_readiness_screen.dart` | `1258` | Hotspot |
| `prisma_partner_screen.dart` | `1241` | Hotspot |
| `momo_screen.dart` | `1198` | Hotspot |
| `support_detail_screen.dart` | `1126` | Hotspot |
| `fan_profile_screen.dart` | `1018` | Hotspot |

## Operating Guidance

- Keep one primary job per route.
- Move orchestration, polling, listeners, and deep-link handling into services.
- Prefer route-level composition from focused sections over giant private widget trees.
- If a screen needs tabs, chips, cards, and multiple CTA clusters, it is
  probably multiple routes sharing one file.

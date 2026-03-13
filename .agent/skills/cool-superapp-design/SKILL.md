---
name: cool-superapp-design
description: >
  Comprehensive design, review, and implementation skill for the COOL Flutter
  super-app. Covers UI/UX, navigation, interaction design, product logic,
  frontend architecture, Supabase and edge-function contracts, permissions,
  offline behavior, analytics, and release-quality QA/UAT across Home, MoMo,
  Groups, Mobility, Partners, Rayon, Credit, Profile, Basket, and Admin.
---

# COOL Super-App Design

Use this skill when the task involves designing, redesigning, reviewing, or
implementing any COOL surface and the answer must stay grounded in the real app,
not generic super-app patterns.

This skill is for:

- UI and UX redesigns
- feature and flow specifications
- Flutter screen and state architecture guidance
- route and navigation decisions
- payment, mobility, partner, and admin flow design
- fullstack contract review between frontend and Supabase
- release-quality QA and device-backed UAT planning

This skill is not for:

- generic React, React Native, or PWA guidance
- imaginary wallet, card, exchange, or investment products not present in COOL
- assuming backend deployment state from local code alone
- proposing map-heavy UX when the build cannot support live maps

## Product Truths

These are non-negotiable:

- COOL is a Flutter mobile app, Android-first, dark-first, EN/FR.
- Primary shell is `Home`, `Groups`, center `MoMo`, `Mobility`, `Profile`.
- `MoMo` is a pushed standalone route, not a shell branch.
- Payments are payer-owned USSD handoff plus Android SMS verification.
- COOL does not use MoMo APIs, MoMo webhooks, or server-side callback payment completion.
- WhatsApp OTP is the auth path.
- Repository and service boundaries matter. Widgets should not own backend logic.
- Maps are conditional. When unavailable, list and route-summary fallbacks are mandatory.
- Pending, draft, parsed, posted, blocked, offline, and disabled states must be shown honestly.

## Source Of Truth

Prefer repo truth over benchmark intuition. Load only what is needed.

### Skill References

| File | Use when |
| --- | --- |
| `references/product-surfaces.md` | module map, route placement, user journeys, shell vs standalone decisions |
| `references/ui-ux-system.md` | visual system, composition, accessibility, localization, trust design |
| `references/interaction-intelligence-and-operations.md` | adaptive behavior, lifecycle, notifications, engagement, analytics, operational UX |
| `references/frontend-fullstack-architecture.md` | Flutter app structure, Riverpod ownership, router, services, sync, implementation boundaries |
| `references/backend-contracts.md` | Supabase tables, RPCs, edge functions, remote verification, secret and deployment constraints |
| `references/quality-and-uat.md` | release gates, QA coverage, permissions, offline QA, module UAT, acceptance review |

### Repo References

| File | Use when |
| --- | --- |
| `docs/ROUTE_INVENTORY.md` | adding, moving, or auditing routes |
| `docs/SCREEN_BUDGETS.md` | simplifying large screens and avoiding route bloat |
| `docs/PERMISSIONS.md` | location, SMS, contacts, NFC, camera access behavior |
| `docs/OFFLINE_POLICY.md` | queued writes, sync expectations, stale-state handling |
| `docs/PERFORMANCE_BUDGETS.md` | startup, jank, TTFB, crash and ANR targets |
| `docs/ANALYTICS_TAXONOMY.md` | event naming, critical telemetry, interaction logging |
| `docs/qa_release_readiness.md` | release-readiness process and validation scope |

## Workflow

### 1. Classify the task

Identify:

- module or route
- user state
- risk level
- whether the issue is visual, interaction, data, route, or backend-contract driven
- whether the change is shell, standalone route, sheet, or widget-level only

### 2. Read the minimum relevant references

Examples:

- Home redesign: `product-surfaces` + `ui-ux-system`
- MoMo bug review: `product-surfaces` + `frontend-fullstack-architecture` + `backend-contracts` + `quality-and-uat`
- release or UAT audit: `quality-and-uat` plus the module-specific reference
- route cleanup: `product-surfaces` + `frontend-fullstack-architecture` + `docs/ROUTE_INVENTORY.md`

When the task spans the whole app, read the references in this order:

1. `references/product-surfaces.md`
2. `references/ui-ux-system.md`
3. `references/interaction-intelligence-and-operations.md`
4. `references/frontend-fullstack-architecture.md`
5. `references/backend-contracts.md`
6. `references/quality-and-uat.md`

### 3. Ground the answer in COOL-specific constraints

Always account for:

- USSD plus SMS payment truth
- shell versus standalone route behavior
- rollout and unavailable states
- permission and offline realities
- partner and Rayon sub-brand constraints
- backend deployment and secret gaps when relevant

### 4. Design or review the full stack, not just the surface

For any meaningful feature, cover:

- route ownership
- screen anatomy
- primary and secondary actions
- state matrix
- provider, repository, and service boundaries
- backend tables, RPCs, or edge functions involved
- analytics and observability
- QA and UAT scope

### 5. Keep output implementable

Do not stop at visual critique. Specify:

- what changes in UI
- what changes in state ownership
- what backend contract is required
- how the feature degrades when config, permission, or deployment is missing
- how to verify it on device

## Module Coverage

This skill must be able to cover all app modules:

- Auth
- Home
- MoMo
- Groups
- Mobility
- Partners
- Rayon Sports
- Credit
- Profile and app access
- Basket and checkout
- Admin and validation tooling

## Design Rules

### UX and trust

- One dominant job per screen.
- Money, identity, permissions, and mobility state must be explicit.
- Standalone routes must always expose a visible exit path.
- Empty states must be real, not caused by filtering bugs.
- Partner branding never outranks system trust or clarity.

### Frontend architecture

- Widgets render and dispatch intent.
- Providers coordinate state.
- Repositories own Supabase reads and writes.
- Services own lifecycle, device APIs, and cross-screen behaviors.
- Route additions or major moves should update route inventory.
- Oversized screens should be simplified before they are expanded.

### Backend and operational truth

- Local function code is not proof of deployment.
- Remote tables, RPCs, functions, and secrets must be verified before claiming a feature is live.
- UI must degrade honestly when a backend contract or edge function is unavailable.
- Payment, ticketing, wallet-pass, and maps behavior must reflect real operational state.

### QA and release quality

- Design every critical state, not only the happy path.
- Payment, access, scanner, lifecycle, and map-sensitive flows require device-backed UAT.
- New user-facing routes should have smoke coverage.
- Release work should respect analyzer, tests, route inventory, screen budgets, and readiness scripts.

## Anti-Patterns

Reject these unless the repo clearly requires them:

- generic “super-app” advice that ignores COOL’s payment model
- shell-tab treatment for every route
- map-first UX without a working fallback
- fake permission surfaces or counts
- marketing-heavy partner screens that hide transactional clarity
- giant multi-purpose profile, home, or admin screens that keep growing
- UI proposals that assume background magic sync the app does not have
- “completed” payment or order states before SMS or backend confirmation exists

## Output Standards

When responding with a design, implementation plan, or review, structure the answer around:

1. product goal or bug being solved
2. relevant module and route ownership
3. current risk, clutter, or contract gap
4. proposed UI and UX changes
5. frontend ownership boundaries
6. backend contract or deployment dependencies
7. state matrix and fallback behavior
8. verification and UAT scope

If the user asks for a review, findings come first and should identify:

- broken trust or navigation
- incorrect state handling
- backend-contract mismatch
- missing deployment or secret configuration
- missing tests or UAT

The skill is successful only when the output is specific enough to implement in
this repo without guessing.

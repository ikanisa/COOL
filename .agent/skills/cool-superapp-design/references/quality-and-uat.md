# Quality And UAT

Use this file when the task requires release readiness, QA coverage, analytics, permissions, performance, or device-backed acceptance checks.

## Release Gates

Release-candidate quality requires all of the following:

- `flutter analyze` passes clean
- `flutter test` passes clean
- critical Deno checks for Supabase functions pass
- route changes update `docs/ROUTE_INVENTORY.md`
- screen changes respect `docs/SCREEN_BUDGETS.md`
- new user-facing routes ship with smoke coverage

Primary consolidated command:

```sh
bash scripts/release_readiness.sh
```

## Quality Categories

### Static quality

- no analyzer issues
- no failing widget or provider tests
- no broken route inventory or screen-budget governance

### UX quality

- one dominant task per screen
- truthful states
- explicit trust language where money, access, or identity is involved
- accessibility and localization not deferred

### Operational quality

- backend contracts verified
- edge functions deployed when needed
- secrets present when required
- rollout and unavailable states covered

## Performance Budgets

Watch these targets:

- cold start P90 under `3s`
- warm start P90 under `1.5s`
- jank P90 under `5%`
- crash-free sessions above `99.5%`
- ANR under `0.5%`
- network TTFB P90 under `500ms`

Design implication:

- avoid spinner-only loads
- keep above-the-fold payloads light
- avoid unnecessary startup work on critical paths
- do not add decorative complexity to already-hot screens

## Permission QA

Permission design and QA should verify:

- prompts happen only at feature use, not on first launch
- rationale exists before system request where appropriate
- fallback exists when supported
- permanently denied state guides users to settings
- Play-review disclosures match real behavior

Current critical permissions include:

- location for mobility
- camera for QR scanning
- contacts for invite flows
- NFC for tap flows
- Android SMS for M-Money confirmation

## Offline QA

This app uses explicit queued sync, not background magic.

Test:

1. perform write while offline
2. confirm pending or queued behavior is understandable
3. reconnect
4. trigger the owning flow or flush path
5. confirm final server-backed state appears

Do not mark queued writes as definitively complete before reconciliation.

## Analytics And Observability

Important telemetry sources:

- engagement tracker events
- Firebase Performance
- Crashlytics
- FCM/open and deep-link events

When designing or changing flows:

- define meaningful analytics events only for important user intent
- avoid noisy event spam
- ensure sensitive financial states are logged carefully and without leaking amounts where not appropriate

## UAT Rules By Module

### Auth

- cold-start splash and onboarding path
- OTP request
- OTP verification
- redirect after auth
- optional profile-completion path remains voluntary

### Home

- quick actions open the intended destinations
- recent activity reflects real backend-backed data
- no stale placeholder empty state when activity exists

### Groups

- create group
- open group detail
- contribution handoff
- invite generation and invite acceptance

### MoMo

- USSD launch path
- SMS permission state
- inbox recovery or live SMS ingestion
- statement rendering for draft and confirmed rows
- QR and NFC utilities
- escape routes back to app home

### Mobility

- entry into mobility branch
- permission gating
- place search
- map fallback behavior
- schedule trip flow
- trip board and driver flow behavior

### Partners And Rayon

- partner discovery
- bank partner detail load
- Rayon membership, registry, clubs
- ticket purchase and pending state
- shop checkout and pending state
- support contribution and pending state
- ticket scan verification when relevant

### Credit

- score load
- readiness flow
- refresh path
- application path if enabled

### Basket

- line items and totals render correctly
- quantity and removal behavior works
- checkout launches the expected payment flow
- pending order state remains visible after return from USSD

### Profile

- travel role control
- app access sheet
- MoMo setup sheet
- support and destructive actions

### Admin

- app config edits
- country and routing config
- validation issue visibility
- repair action behavior

## Acceptance Checklist

Before closing work, verify:

- the main path is obvious
- high-risk states are covered
- trust copy is explicit
- accessibility and French expansion do not break the layout
- backend dependencies are named
- smoke coverage exists for the changed user-facing path
- device-backed UAT exists for payment, permission, scanner, or lifecycle-sensitive changes

## Review Prompts

Use these when critiquing a change:

- Is this screen solving one job or several?
- Is the empty state real, or is the data just filtered away?
- Does the user know who gets paid, how, and what status the payment is in?
- If maps are unavailable, does the task still work?
- If a permission is denied, does the task still degrade honestly?
- If the backend contract is missing, does the UI say so clearly?

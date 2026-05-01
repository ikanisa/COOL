# COOL Admin PWA Remediation Plan

Date: 2026-04-11
Input: `docs/audits/admin-pwa-production-readiness-audit-2026-04-11.md`
Goal: take the admin PWA from strong internal beta to production-ready admin control plane.

## Plan Summary

This plan is organized around ten workstreams and three release gates:

- Gate 1: launch blockers removed
- Gate 2: production-safe control plane
- Gate 3: operator-grade admin product

Recommended execution order:

1. local/live parity and test reliability
2. auth/session hardening
3. authorization and access-governance completion
4. privileged-write UX hardening
5. observability and auditability
6. data-surface scaling and investigation UX
7. offline/PWA scope correction
8. notifications and incident flows
9. accessibility, productivity, and design-system refinement
10. documentation, policy, and operational readiness

## Delivery Model

Recommended owner groups:

- frontend: shell, flows, forms, telemetry, accessibility
- backend/functions: auth/session endpoints, admin APIs, validation, logging
- database: migrations, RPC guards, RLS, audit schema, pagination functions
- platform/release: CI, smoke tests, deploy gates, runbooks, alerting
- product/design: personas, operator journeys, UX safety rails, IA

Recommended release cadence:

- Sprint 1-2: Gate 1
- Sprint 3-4: Gate 2
- Sprint 5-6: Gate 3

Do not ship broad production access before Gate 2 is complete.

## Gate Definitions

### Gate 1: Launch Blockers Removed

Exit criteria:

- localhost and preview environments can exercise real auth and Pages Functions in browser
- legacy `users.is_admin` accounts are fully migrated or fully blocked from the admin surface
- session issuance and refresh flows are hardened
- privileged writes have validation, confirmation, and audit-safe metadata
- CI blocks deploys on integration and smoke failures

### Gate 2: Production-Safe Control Plane

Exit criteria:

- browser, API, auth, and mutation telemetry flow to central observability
- audit trails are searchable and exportable enough for incident review
- users/config/audit data is paginated and server-filtered
- offline messaging is truthful and bounded
- access policies, runbooks, retention, and incident docs exist

### Gate 3: Operator-Grade Admin Product

Exit criteria:

- scoped admin journeys are real, not implied
- keyboard-first and high-frequency workflows are efficient
- conflict awareness and collaborative editing safeguards exist
- notifications are real operational tooling, not demo plumbing
- design system supports dense expert workflows without losing clarity

## Workstream 1: Local/Live Parity And Test Reliability

Objective: make local and preview testing exercise the real product path.

### Problems solved

- localhost forces static preview mode
- integration harness is unreliable
- CI does not test real authenticated/admin flows

### Implementation

1. Replace `isStaticLocalPreview()` with an explicit preview mode switch.
- Add one source of truth such as `meta[name="admin-runtime-mode"]` or `window.__COOL_ADMIN_RUNTIME__`.
- Modes:
  - `live`
  - `static-preview`
  - `maintenance`
- Remove localhost heuristics from `assets/js/admin_api.js`.

2. Split static preview from live runtime intentionally.
- Keep `npm run serve` as static preview only.
- Keep `wrangler pages dev` as live mode.
- Make the shell render a visible mode badge so testers know which path is active.

3. Rebuild the integration suite around explicit health readiness.
- Add a dedicated health endpoint such as `/api/healthz`.
- Update `scripts/integration-test.mjs` to wait for that endpoint instead of generic fetch readiness.
- Capture and print wrangler stderr/stdout on timeout.

4. Add authenticated preview smoke coverage.
- Add a preview deploy test that exercises:
  - send OTP
  - verify OTP
  - session probe
  - at least one safe read route
  - at least one mutation path in a seeded preview environment

### Files likely touched

- `apps/pwa/assets/js/admin_api.js`
- `apps/pwa/assets/js/app.js`
- `apps/pwa/README.md`
- `apps/pwa/scripts/integration-test.mjs`
- `apps/pwa/package.json`
- `.github/workflows/cool-pwa-ci.yml`
- `.github/workflows/cool-pwa-deploy.yml`
- new `apps/pwa/functions/api/healthz.js`

### Tests

- contract test for runtime mode selection
- integration test for health endpoint
- preview smoke test with real Pages Functions

### Exit criteria

- live auth/session can be tested locally in browser with no special hacks
- integration suite is stable across CI runs

## Workstream 2: Auth And Session Hardening

Objective: move from a workable session model to an admin-safe session model.

### Problems solved

- raw access and refresh tokens stored together in one cookie payload
- refresh-token body fallback
- admin entitlement checked after session issuance
- auth enumeration risk
- no throttling or re-authentication strategy

### Implementation

1. Change session architecture.
- Replace token JSON cookie with opaque server session ID.
- Store session state server-side in a session table or edge/session store.
- Session record should contain:
  - session id
  - auth user id
  - issued at
  - expires at
  - refresh token or rotation reference
  - risk flags
  - last verified admin access snapshot
  - last activity metadata

2. Rework `/api/auth/verify-otp`.
- Verify OTP.
- Immediately re-check admin access before issuing any session.
- Deny session creation if the account is not authorized.
- Log the denial without exposing whether the phone belongs to an admin.

3. Remove refresh-token body fallback from `/api/auth/refresh`.
- Refresh must only work off the server-side session state.
- Rotate the session and upstream tokens atomically.

4. Normalize authentication responses.
- Return one generic error for OTP send/verify failures where possible.
- Keep detailed reason only in logs, not in user-facing responses.
- Remove the current `NOT_ADMIN_PHONE` discrepancy in public responses.

5. Add anti-automation controls.
- rate limiting per phone, IP, and device fingerprint bucket
- cooldown window after repeated failed OTP verifications
- optional CAPTCHA or challenge after threshold

6. Add re-authentication for high-risk actions.
- require fresh step-up verification for:
  - assigning or revoking platform access
  - editing sensitive config keys
  - partner/payment routing changes
  - break-glass or emergency actions

7. Add explicit session revocation and invalidation.
- logout should revoke server session first, then clear cookie
- revoking admin access should revoke all active admin sessions for that user

### Files likely touched

- `apps/pwa/functions/_shared/supabase.js`
- `apps/pwa/functions/api/auth/send-otp.js`
- `apps/pwa/functions/api/auth/verify-otp.js`
- `apps/pwa/functions/api/auth/refresh.js`
- `apps/pwa/functions/api/auth/logout.js`
- `apps/pwa/functions/api/admin/session.js`
- `apps/pwa/assets/js/admin_api.js`
- new session migrations and server session helpers

### Database work

- create `admin_sessions`
- create `admin_auth_attempts` or equivalent throttle table
- add session-revocation helper functions

### Tests

- no session issued to non-admin user after valid OTP
- generic auth responses do not leak account state
- refresh only works with valid active server session
- access revocation kills active sessions

### Exit criteria

- browser never stores raw bearer/refresh credentials in a readable form
- no distinct user-facing response reveals privileged-account existence
- high-risk actions can require step-up auth

## Workstream 3: Authorization And Access Governance Completion

Objective: finish the migration from legacy admin access to explicit role assignments.

### Problems solved

- legacy `users.is_admin` rows are not revocable in-browser
- scoped-admin product promise is incomplete
- role model is too coarse for real operations

### Implementation

1. Complete legacy admin migration.
- Create migration that:
  - inserts corresponding `admin_role_assignments` for every legacy admin
  - preserves grant provenance and notes where possible
  - clears `users.is_admin` after backfill
- make browser revocation work for every privileged account

2. Define target role model.
- `platform_admin`
- `bank_admin`
- `auditor_readonly`
- `ops_responder`
- optional narrower roles for config, release, and support

3. Rework `get_admin_access_for_user`.
- Return explicit capability set, not only boolean flags.
- Example capability keys:
  - `can_manage_users`
  - `can_manage_roles`
  - `can_edit_config`
  - `can_view_audit`
  - `can_export_audit`
  - `can_manage_partner_routes`

4. Rework route gating.
- Gate by capabilities, not broad route name.
- Build bank-scoped routes or remove bank access from the current shell until implemented.

5. Add authorization tests for every admin RPC.
- unauthorized caller
- wrong role
- scoped role outside allowed partner scope
- successful path

### Files likely touched

- `supabase/migrations/*`
- `apps/pwa/functions/_shared/supabase.js`
- `apps/pwa/functions/api/admin/data.js`
- `apps/pwa/functions/api/admin/mutate.js`
- admin role and session UI surfaces

### Exit criteria

- every privileged account is explicitly assigned and revocable
- route access and mutation access are capability-based
- bank-scoped access is either fully real or fully removed from current claims

## Workstream 4: Privileged-Write UX Hardening

Objective: make high-risk actions hard to do accidentally and easy to audit.

### Problems solved

- free-text role/config forms
- no confirmation or diff preview
- no write rationale enforcement for sensitive actions

### Implementation

1. Replace free-text inputs with structured controls.
- role assignment:
  - searchable user picker
  - role select
  - partner select when scoped
  - required rationale
- config editing:
  - config key picker or validated key entry
  - scope select
  - typed value editor by config schema
  - required change reason

2. Add a review step before commit.
- Show current value, proposed value, environment/scope, risk label, and actor.
- Require confirmation for destructive or privilege-changing writes.

3. Add step-up auth for highest-risk changes.
- prompt for fresh OTP or second approval on:
  - platform access grants/revokes
  - payment route changes
  - security/config toggles marked critical

4. Add post-change verification and rollback affordance.
- After mutation, show:
  - success state
  - audit reference id
  - “view in audit log”
  - “revert” where safe

5. Add schema and policy to config keys.
- maintain a registry of config keys with:
  - allowed data type
  - environment scope
  - default value
  - sensitivity tier
  - requires step-up auth boolean

### Files likely touched

- `apps/pwa/admin/roles/index.html`
- `apps/pwa/admin/app-config/index.html`
- `apps/pwa/assets/js/admin_views.js`
- `apps/pwa/assets/js/app.js`
- `apps/pwa/functions/api/admin/mutate.js`
- new config schema source

### Exit criteria

- no sensitive mutation is a one-click blind write
- every high-risk change captures rationale and audit metadata

## Workstream 5: Observability, Auditability, And Logging

Objective: make admin operations observable enough for real incident response and compliance.

### Problems solved

- browser telemetry mostly local-only
- shallow audit-log UI
- missing structured API/security logs

### Implementation

1. Wire browser telemetry to a real endpoint.
- Add `meta[name="analytics-endpoint"]` and `meta[name="app-version"]`.
- Send structured events for:
  - auth attempt
  - auth failure
  - session refresh
  - route load
  - mutation requested
  - mutation confirmed
  - mutation failed
  - offline mode entered
  - sync succeeded/failed
  - browser errors

2. Add server-side structured logs.
- Every auth and admin endpoint should log:
  - interaction id
  - actor/session id
  - route
  - action
  - result
  - latency
  - authorization decision
  - risk classification

3. Expand audit log model.
- ensure audit captures:
  - actor
  - target object
  - before/after summary
  - scope/environment
  - reason
  - source channel
  - request id

4. Rebuild audit-log UI as investigation tooling.
- server-side pagination
- filters for actor, object type, action type, date range, success/failure
- export path for incident/compliance use

5. Add dashboards and alerts.
- auth anomalies
- access-denied spikes
- config-change spikes
- repeated mutation failures
- session refresh failures

### Files likely touched

- `apps/pwa/assets/js/app.js`
- admin HTML templates
- `apps/pwa/functions/api/auth/*`
- `apps/pwa/functions/api/admin/*`
- audit-related DB functions/migrations
- docs: observability and incident runbooks

### Exit criteria

- browser and API events are centrally visible
- audit screen supports real investigations

## Workstream 6: Data-Surface Scaling And Admin APIs

Objective: move away from “download everything and filter in browser.”

### Problems solved

- full users dataset returned to browser
- shallow audit queries
- no server filtering or pagination

### Implementation

1. Introduce paginated admin APIs.
- users:
  - query
  - status
  - role
  - scope
  - cursor/page
- audit:
  - actor
  - action
  - target
  - date range
  - cursor/page

2. Minimize returned fields by use case.
- list view returns summary fields only
- detail view fetches expanded record on demand

3. Add server-side sort and stable cursors.

4. Add admin query performance review.
- index support for filters
- RPC performance profiling
- payload-size budgets

5. Add dedicated object-detail pages where needed.
- user detail
- config entry detail/history
- audit event detail

### Files likely touched

- `apps/pwa/functions/api/admin/data.js`
- `apps/pwa/assets/js/admin_views.js`
- `apps/pwa/assets/js/app.js`
- new DB functions for paginated list endpoints

### Exit criteria

- large environments do not require full-dataset fetches
- user and audit investigations are server-driven

## Workstream 7: Offline And PWA Scope Correction

Objective: make the offline story truthful, bounded, and useful.

### Problems solved

- offline claims exceed actual live behavior
- queue framework does not back the active admin forms
- service worker ignores live admin APIs

### Implementation

1. Decide product truth for offline mode.
- recommended policy:
  - offline shell, cached docs, and read-only last-known summaries are supported
  - privileged live mutations require connectivity
  - only explicitly designed safe drafts/requests may queue offline

2. Update service worker behavior.
- cache offline shell and explicit fallback assets
- do not imply live session availability when offline
- optionally support last-known read snapshots for selected routes with stale labels

3. Rework queueing semantics.
- only queue actions explicitly marked safe
- add per-action queue policy:
  - allowed offline
  - not allowed offline
  - requires reconfirmation when online again

4. Update route copy and banners.
- remove claims like “keep permissions management available offline” unless fully true
- add clear stale-data markers and reconnect prompts

5. Add offline-specific tests.
- shell loads offline
- stale route label renders
- forbidden mutation cannot be queued silently

### Files likely touched

- `apps/pwa/service-worker.js`
- `apps/pwa/assets/js/app.js`
- route HTML copy
- `docs/OFFLINE_POLICY.md`
- `docs/cool-pwa-world-class-checklist.md`

### Exit criteria

- offline UX matches actual capability
- no privileged path silently degrades into unsafe behavior

## Workstream 8: Notifications And Incident Workflows

Objective: turn notifications from demo plumbing into an actual operator channel.

### Problems solved

- no push subscription flow
- no delivery pipeline
- alerts are mostly local demo notifications

### Implementation

1. Decide whether push notifications are in scope for v1.
- If yes:
  - implement `PushManager.subscribe`
  - store subscriptions server-side
  - add VAPID/web-push delivery path
  - add subscription lifecycle management
- If no:
  - remove production claims and keep alerts strictly in-app

2. Separate alert types.
- informational
- action required
- incident critical

3. Add operator alert center.
- unread/read state
- acknowledge
- assign
- link to related object or incident

4. Add delivery observability.
- sent
- delivered attempt
- failed
- unsubscribed

### Files likely touched

- `apps/pwa/assets/js/app_notifications.js`
- `apps/pwa/service-worker.js`
- new backend/subscription endpoints
- migrations for subscriptions and alerts

### Exit criteria

- alerts are either fully real or explicitly positioned as in-app only

## Workstream 9: Accessibility, Operator Productivity, And Design Refinement

Objective: preserve polish but adapt the UI for expert operators.

### Problems solved

- visual system is coherent but too repetitive for dense admin tasks
- limited keyboard/productivity support
- no conflict awareness

### Implementation

1. Build route-level UX audits by persona.
- platform admin
- scoped admin
- auditor
- incident responder

2. Introduce productivity features.
- keyboard shortcuts
- quick switcher
- saved filters/views
- command palette for common tasks

3. Improve dense-data layouts.
- table/list hybrid views where appropriate
- pinned filters
- better scan hierarchy for statuses and timestamps

4. Add conflict awareness.
- last editor and last changed at
- warning when editing stale object state
- optional optimistic concurrency token on sensitive writes

5. Expand accessibility testing.
- keyboard-only route completion
- screen-reader labels on forms and stateful panels
- contrast checks in both themes

### Files likely touched

- `apps/pwa/assets/css/app.css`
- `apps/pwa/assets/js/app.js`
- `apps/pwa/assets/js/admin_views.js`
- route HTML pages

### Exit criteria

- core operator journeys are fast without becoming risky
- accessibility passes move beyond shell-level checks

## Workstream 10: Documentation, Policy, And Release Readiness

Objective: align docs and operations with what the product actually does.

### Problems solved

- docs overstate readiness
- incomplete runbooks/policies
- unclear support and retention boundaries

### Implementation

1. Update product docs to match reality.
- `README.md`
- world-class checklist
- offline policy
- release process
- observability docs

2. Add admin PWA runbooks.
- auth outage
- session refresh failures
- revoke compromised admin
- rollback release
- stale service worker recovery
- incident response for unsafe config change

3. Add governance docs.
- admin access provisioning standard
- admin access review cadence
- telemetry retention and privacy rules
- audit-log retention policy
- break-glass access policy

4. Add release gate docs.
- Gate 1 checklist
- Gate 2 checklist
- Gate 3 checklist

### Files likely touched

- `docs/README-style docs`
- `docs/OPERATIONAL_OBSERVABILITY.md`
- `docs/OFFLINE_POLICY.md`
- `docs/RELEASE_PROCESS.md`
- new admin-specific runbooks

### Exit criteria

- docs do not claim capabilities the product does not have
- on-call and platform teams can operate the admin PWA safely

## Cross-Cutting Test Strategy

Every workstream should add or update tests in four layers:

### Unit

- session helper behavior
- capability mapping
- form validation and confirmation state
- telemetry payload generation

### Integration

- auth flow
- refresh flow
- access-denied behavior
- mutation endpoints with valid and invalid roles
- audit entry generation

### Browser/E2E

- OTP sign-in
- role assignment with confirmation
- config change with diff preview
- logout and revoke-session behavior
- offline shell and stale-state messaging

### Operational

- preview smoke test after deploy
- rollback smoke
- alerting path verification
- rate-limit behavior verification

## Prioritized Backlog

### P0: Must Fix Before Broad Production Use

- remove localhost static-preview heuristic
- add real health endpoint and stabilize integration tests
- migrate legacy admins to explicit revocable assignments
- harden verify/refresh/logout session model
- normalize auth error responses and add throttling
- add confirmation plus rationale for privilege/config writes
- add central telemetry endpoint and server-side auth/mutation logs
- gate deploys on integration plus smoke

### P1: Must Fix Before Calling It Production-Safe

- paginated users and audit APIs
- searchable audit-log UI
- explicit offline policy and corrected copy
- scoped role capability model
- config key schema and typed editing
- operator runbooks and retention policies

### P2: Operator-Grade Enhancements

- real bank-scoped journeys
- command palette and keyboard workflows
- conflict-awareness patterns
- real push notifications with delivery monitoring
- richer investigation screens and exports

## Suggested Branching And Rollout Strategy

1. Create a hardening branch for Gate 1.
2. Hide incomplete features behind internal-only flags during transition.
3. Roll out to a narrow internal admin cohort first.
4. Review telemetry and auth anomalies for at least one full cycle.
5. Only then expand to full internal production use.
6. Only market offline, alerts, and scoped admin features that are fully implemented.

## Definition Of Done

The admin PWA can be considered ready for production when all of the following are true:

- real admin auth and session flows are testable locally, in preview, and in CI
- all privileged access is explicit, revocable, and capability-scoped
- high-risk writes require structured input, rationale, confirmation, and full auditability
- telemetry and logs support incident response
- large datasets are server-driven, paginated, and filtered
- offline behavior is bounded and truthful
- docs, runbooks, and release gates match reality

Until then, treat it as an internal beta control surface, not the definitive production admin console.

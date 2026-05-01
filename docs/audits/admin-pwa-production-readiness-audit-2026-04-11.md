# COOL Admin PWA Production Readiness Audit

Date: 2026-04-11
Scope: full repo review with focus on `apps/pwa/` as the admin control plane, plus relevant Supabase migrations and CI/CD workflows.

## Executive Verdict

Status: not production-ready for broad go-live as the primary admin control plane.

Current state: the admin PWA is a credible internal beta with a strong static shell, solid baseline headers, good installability, and better-than-average frontend polish. It is not yet ready to be treated as the authoritative production admin console because the highest-risk parts of an admin system are still incomplete: real local/live QA, sensitive-action safety rails, access revocation, offline semantics, browser telemetry, and operational alerting.

The repo is strongest in:

- shell quality, responsive layout, basic accessibility hooks, and install UX
- baseline hosting hardening through `_headers` and `functions/index.js`
- Supabase-side movement toward role-based admin access instead of legacy `users.is_admin`
- basic CI, browser verification, and Lighthouse coverage

The repo is weakest in:

- session/auth architecture for a privileged admin surface
- permission governance and revocation completeness
- operational observability and push/alert plumbing
- server-driven data handling for users and audit trails
- safety and usability of privileged mutations
- documentation accuracy versus actual behavior

## Highest-Risk Findings

### Critical

- Local live QA is effectively disabled in normal browser use. `getAdminSessionState()` hard-switches localhost over HTTP into static preview mode, so normal local browser testing never exercises real auth/session/function flows. Evidence: `apps/pwa/assets/js/admin_api.js:10-16`, `apps/pwa/assets/js/admin_api.js:115-122`. This conflicts with the local-run guidance in `apps/pwa/README.md:23-28`.

- Offline support is overstated for authenticated admin work. The shell caches routes and static data, but the live admin boot path still depends on live API calls and `requestJson()` has no network-failure guard. Service worker fetch handling does not cover admin API routes. Evidence: `apps/pwa/assets/js/admin_api.js:18-36`, `apps/pwa/assets/js/app.js:164-205`, `apps/pwa/service-worker.js:92-116`, `apps/pwa/service-worker.js:185-213`. Current copy such as “Keep rollout control available even when you are off-network” overpromises this behavior (`apps/pwa/admin/app-config/index.html:69`).

- Full browser-based access governance is incomplete. Legacy admins backed only by `users.is_admin` cannot be revoked from the PWA. Evidence: `apps/pwa/functions/api/admin/mutate.js:115-128`. For a production admin console, non-revocable privileged accounts are a launch blocker.

### High

- Privileged writes have weak human-factor controls. Role assignment and config mutation are immediate free-text form submissions with no confirmation dialog, no typed validation beyond presence, no diff preview, no second-factor step for critical changes, and no reversible workflow. Evidence: `apps/pwa/admin/roles/index.html:55-63`, `apps/pwa/admin/app-config/index.html:55-63`, `apps/pwa/assets/js/app.js:373-430`. This is below the standard set by mature admin products for destructive or privilege-changing operations.

- The session model is still too brittle for a high-trust admin surface. The cookie stores raw access and refresh tokens together as JSON, refresh still supports a body token fallback, and OTP verification sets the cookie before admin entitlement is re-checked. Evidence: `apps/pwa/functions/_shared/supabase.js:135-157`, `apps/pwa/functions/api/auth/refresh.js:4-10`, `apps/pwa/functions/api/auth/verify-otp.js:24-45`, `apps/pwa/functions/api/admin/session.js:3-14`. This is functional, but it is not a world-class admin-session design.

- The sign-in flow leaks admin-account existence. The send-OTP endpoint returns a distinct `NOT_ADMIN_PHONE` response and the UI renders a dedicated “request access” state for non-admin phones. Evidence: `apps/pwa/functions/api/auth/send-otp.js:23-33`, `apps/pwa/assets/js/admin_views.js:67-97`. For a privileged entrypoint, this creates avoidable user-enumeration risk.

- Notification and alerting are mostly demo-grade. The frontend requests permission and can show demo notifications, and the service worker can receive `push`, but the repo does not implement push subscription capture, subscription persistence, VAPID config, or delivery plumbing. Evidence: `apps/pwa/assets/js/app_notifications.js:10-83`, `apps/pwa/service-worker.js:145-183`. Operational alerts are therefore not production-complete.

- Browser telemetry is mostly local-only. Events are pushed to `window.dataLayer` and IndexedDB, but the pages do not define the `meta[name="analytics-endpoint"]` or `meta[name="app-version"]` tags required for network export. Evidence: `apps/pwa/assets/js/app.js:729-753`. This means production browser errors, install success, sync results, and admin-route failures are not reliably sent to a central system.

- Scoped/bank admin access is not a credible product journey yet. The data model and shell imply bank-scoped access, but every meaningful route is platform-only, leaving scoped admins with little more than a summary surface. Evidence: `apps/pwa/functions/_shared/supabase.js:6-15`, `apps/pwa/functions/_shared/supabase.js:350-351`, `apps/pwa/functions/api/admin/data.js:70-111`.

- User management does not scale and exposes more data than needed. The users route fetches the full users dataset into the browser and then filters client-side. Evidence: `apps/pwa/functions/api/admin/data.js:143-211`, `apps/pwa/assets/js/admin_views.js:216-250`. This will degrade badly at scale and unnecessarily widens the data exposed in a single admin browser session.

- Audit-log UX is too shallow for enterprise operations. The route loads a fixed page of 30 records and renders a subset of 12 without server-side filtering, export, or investigative search. Evidence: `apps/pwa/functions/api/admin/data.js:352-379`. This is acceptable for a preview, not for production incident review or compliance evidence.

- CI does not gate the most important integration path. `npm test` omits the integration suite, and both CI workflows only run contract tests, browser checks, and Lighthouse. Evidence: `apps/pwa/package.json:5-12`, `.github/workflows/cool-pwa-ci.yml:34-40`, `.github/workflows/cool-pwa-deploy.yml:36-42`. The integration suite itself is also unreliable in current form (`apps/pwa/scripts/integration-test.mjs:25-57`).

### Medium

- Logout can race the next session probe in non-reload flows because the cookie-clearing fetch is fire-and-forget. Evidence: `apps/pwa/assets/js/admin_api.js:62-68`, `apps/pwa/assets/js/app.js:349-370`.

- The queueing/offline-mutation framework is underused. The generic queueing path exists, but the active role/config/user admin forms are wired directly to live mutation functions rather than offline-safe queued forms. Evidence: `apps/pwa/assets/js/app.js:572-685`.

- The PWA shell is visually consistent, but the design system is too monocultural for a complex admin product. The dark-purple palette is the default global visual direction, and route-level information density relies heavily on repeated cards and status pills. Evidence: `apps/pwa/assets/css/app.css:25-63`, `apps/pwa/admin/index.html:55-104`. The result is polished, but not yet optimized for high-frequency operator workflows.

- Performance quality is good but not fully production-polished. Lighthouse passed with strong top-line scores, but there are still misses for compression, minification, responsive images, and back-forward cache. Verified locally via `apps/pwa/output/lighthouse/cool-pwa-admin.report.json`.

- Documentation currently overstates readiness. The checklist document describes queueing, alerts, and browser-safe admin flows more confidently than the implementation supports. Evidence: `docs/cool-pwa-world-class-checklist.md:45-77`.

## Strong Areas

- Security headers and CSP are better than average for a static admin PWA. Evidence: `apps/pwa/_headers:1-39`, `apps/pwa/functions/index.js:1-45`.

- The shell has real accessibility work, not just claims. It includes a skip link, `:focus-visible`, 48px interactive targets, and reduced-motion handling. Evidence: `apps/pwa/assets/css/app.css:184-211`, `apps/pwa/assets/css/app.css:943-955`.

- Typography and brand assets are deliberate. The product uses self-hosted `Space Grotesk` and `Manrope` rather than default stacks, and the shell is visually cohesive. Evidence: `apps/pwa/assets/css/app.css:5-23`, `apps/pwa/assets/css/app.css:151-160`.

- Responsive behavior exists and is not an afterthought. The shell changes navigation, layout, and toast placement at mobile widths. Evidence: `apps/pwa/assets/css/app.css:900-940`.

- Supabase hardening work is meaningful. There is recent migration work to align `is_admin()` with active role assignments and to harden SECURITY DEFINER functions and audit triggers. Evidence: `supabase/migrations/20260411113000_align_platform_admin_helpers_with_role_assignments.sql:9-178`, `supabase/migrations/20260323210000_production_readiness.sql:6-47`, `supabase/migrations/20260328000000_admin_readiness_security_hardening.sql:6-197`.

## World-Class Benchmark Notes

The current implementation compares reasonably well to a prototype or internal tool, but it is not yet operating at the level of mature admin products.

What world-class admin/control-plane products consistently do:

- least-privilege access and explicit role scopes
- searchable, actor-attributed audit trails with meaningful filters
- safe write flows with previews, confirmations, and reversible actions
- productivity features such as keyboard navigation, saved views, and focused work queues
- conflict awareness when multiple operators touch the same object
- central observability for browser, API, auth, and operational events
- clear distinction between “offline shell works” and “privileged live actions require network”

Reference patterns:

- Vercel’s production checklist pushes teams toward CSP, rate limiting, tracing, monitoring, and incident readiness, which is the right bar for an admin control plane: <https://vercel.com/docs/production-checklist>
- Stripe’s teams docs explicitly recommend granting the lowest permission needed and reviewing what each role can and cannot do before assignment: <https://docs.stripe.com/get-started/account/teams> and <https://docs.stripe.com/get-started/account/teams/roles>
- GitHub’s audit-log model is closer to the standard this PWA should aim for: searchable event history with actor/action context rather than a thin recent-activity strip: <https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/reviewing-the-audit-log-for-your-organization>
- Shopify’s admin docs show two important operator patterns this PWA currently lacks: richer activity review and page-level concurrency awareness to reduce conflicting edits: <https://help.shopify.com/en/manual/shopify-admin/activity-logs>
- Linear demonstrates how much productivity matters in dense admin tools: inbox-first triage and keyboard-driven navigation are not “nice to have” at scale: <https://linear.app/docs/inbox> and <https://linear.app/docs/keyboard-shortcuts>

## External Standards Relevant To This Audit

- Core Web Vitals should remain within current web.dev guidance for LCP, INP, and CLS: <https://web.dev/articles/vitals>
- bfcache eligibility is an important polish/performance lever, and `no-store` decisions should be deliberate rather than incidental: <https://web.dev/articles/bfcache>
- Offline fallback should be self-contained and clearly bounded; it should not imply live privileged work when the network is absent: <https://web.dev/articles/offline-fallback-page>
- Accessibility expectations should align with WCAG 2.2, especially focus visibility and target size: <https://www.w3.org/WAI/WCAG22/quickref/>
- Authentication responses for privileged surfaces should avoid discrepancy factors and enumeration leaks: <https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html>
- Session design, rotation, and invalidation should align with OWASP session-management guidance: <https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html>
- Logging should capture who/what/where/when, privilege changes, session failures, and high-risk administrative actions without storing raw secrets or tokens: <https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html>
- ASVS is the right baseline for defining what “production-ready” means for a privileged admin application: <https://owasp.org/www-project-application-security-verification-standard/>

## Production Checklist

### Product and UX

- Define supported operator personas: platform admin, bank admin, read-only auditor, incident responder.
- Replace free-text critical forms with validated selectors, scoped choices, confirmation steps, and post-change summaries.
- Add destructive-action friction for privilege changes, config writes, and partner-routing changes.
- Add keyboard-friendly navigation and quick actions for high-frequency workflows.
- Introduce conflict awareness for shared objects or at minimum last-editor warnings on mutable records.
- Separate “overview dashboards” from “investigation screens” so users can search/filter/export.

### Information Architecture

- Make the scoped-admin journey real, or remove the promise from the UI until it exists.
- Rework route hierarchy around operator jobs rather than around tables or route names.
- Add saved filters/views for users, config entries, incidents, and audit events.

### Frontend Quality

- Add a build step for minification, compression-friendly output, and image-size discipline.
- Revisit bfcache eligibility where safe.
- Add explicit empty, error, stale, and offline states per route.
- Treat the offline shell as a bounded mode with route-specific messaging.
- Add metadata required for central telemetry export.

### Accessibility

- Keep the current baseline and expand it into route-level audits for forms, dialogs, and tables.
- Validate color contrast across both themes, not only the happy-path cards.
- Add explicit labels and helper text for all privileged forms and confirmation states.
- Test keyboard-only completion of every primary admin journey.

### Authentication and Sessions

- Stop issuing admin cookies until admin entitlement is re-verified after OTP verification.
- Move away from storing raw access and refresh tokens together in a browser cookie payload.
- Remove the refresh-token body fallback.
- Add login throttling and anti-automation controls to the admin sign-in surface.
- Normalize auth error responses to prevent role/account enumeration.
- Add re-authentication for the highest-risk actions.

### Authorization and Governance

- Finish migration away from legacy `users.is_admin`.
- Ensure every privileged user has a revocable, auditable role assignment.
- Add read-only auditor roles and narrower operational roles where needed.
- Add policy tests for every admin RPC and every privileged table or mutation path.

### Data and Database

- Move users, audit logs, and large inventories to server-side pagination, sorting, and filtering.
- Reduce the fields returned to the browser for user-management screens.
- Add explicit retention rules for admin audit data and operational logs.
- Verify RLS/policy behavior with automated tests, not only migration intent.
- Document which functions are SECURITY DEFINER and why.

### Observability and Operations

- Send browser events to a real ingestion endpoint with environment/version tagging.
- Add structured API logs for auth, session refresh, access denial, mutation success/failure, and latency.
- Add alerting for failed admin sign-ins, repeated denied access, and high-risk config changes.
- Define SLOs and dashboards for auth endpoints, admin data routes, and mutation routes.
- Add a tested incident response and rollback flow specific to this admin PWA.

### Notifications

- Implement real push subscription management or stop positioning notifications as a live operational channel.
- Distinguish in-app alerts from system push alerts in both code and UX copy.
- Add delivery monitoring and stale-alert cleanup.

### Release Engineering

- Make the integration suite reliable and mandatory in CI.
- Add authenticated smoke tests against preview deployments.
- Gate production deploys on integration, smoke, and policy tests.
- Record release version into the app shell and telemetry.

### Documentation and Policy

- Update README and checklist docs to match actual behavior.
- Add an admin PWA runbook covering access provisioning, revocation, session failure, and rollback.
- Add explicit privacy and retention rules for admin telemetry, notifications, and audit logs.
- Define support boundaries: what can be done offline, what requires live connectivity, what is preview-only.

## Recommended Go-Live Sequence

### Before Any External Or Broad Internal Launch

- fix local/live QA so auth and Pages Functions can be exercised in browser
- complete legacy-admin migration and revocation
- harden auth/session flow and remove enumeration leaks
- add confirmation and validation rails to privilege/config mutations
- wire central telemetry and API logging
- make CI gate on reliable integration coverage

### Before Calling It A Production Admin Console

- implement real scoped-admin journeys
- add searchable/paginated audit and user-management screens
- add real notification plumbing or remove notification claims
- define operator-specific workflows, shortcuts, saved views, and investigation surfaces

## Overall Grade

- frontend shell and installability: B+
- accessibility baseline: B
- visual system and branding: B
- performance baseline: B
- backend/API design for privileged use: C
- auth/session security posture: C-
- authorization/governance completeness: C-
- observability and operational readiness: C
- data-handling scalability: C
- documentation accuracy: C

Overall: strong internal beta, not yet ready for production go-live as the main admin surface.

# Collect Security And Privacy Review

Audit date: 2026-06-01

Security/privacy status: **LOCAL CODE CHECKS, LINKED SMS-FIRST UAT, AND ADMIN
PWA LIVE GATE PASS; HUMAN RELEASE SIGNOFF PENDING**.

## Current Findings

| Area | Status | Evidence |
| --- | --- | --- |
| Client secrets | Pass by tests/scans | Focused tests and release scans cover obvious API key, token, JWT, and database URL patterns. |
| Local env files | Pass | `.env`, `.env.local`, and `.env.json` remain ignored/untracked. |
| Android SMS permissions | Partially proven | Restricted SMS permissions are isolated to the Android SMS access flavor and runtime permission is required before ingestion is enabled; real MoMo SMS UAT is still pending after the refactor. |
| Identity privacy | Pass locally | Current UX uses generated 6-digit Collect ID and does not ask for or display real names. |
| Payment privacy | Pass locally | Contributor flow creates payment intents and does not expose manual transaction reporting. |
| Raw SMS default handling | Pass by contract; human UAT pending | Raw SMS is not part of public/member UI. Compliance reveal is permission-gated and audited in linked admin/security UAT. |
| Parser/allocation boundary | Pass in linked UAT; device UAT pending | Edge Functions type-check, local contracts, and linked SMS-first allocation UAT pass. |
| Admin authorization | Pass in linked rollback UAT | `scripts/collect_admin_security_uat.sh` verifies RBAC, reveal audit, reparse permission, and denial paths. |
| Admin PWA local runtime | Pass | Local build/render smoke passes and screenshots are nonblank. |
| Admin PWA live runtime | Pass | `https://cool-admin-212.pages.dev` passed the deployed URL live gate. |

## Required Before Release

1. Run real Android SMS access UAT with sanitized MoMo SMS scenarios.
2. Run the release secret scan in the final release environment.
3. Record Android signing review and iOS release-scope evidence.
4. Record stakeholder and release-owner signoff.

Older CAPTCHA/HIBP/plan/PITR release findings are historical for the previous
packet and are not treated as current blockers unless a fresh post-refactor
readiness run reproduces them.

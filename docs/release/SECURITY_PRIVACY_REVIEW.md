# Collect Security And Privacy Review

Audit date: 2026-05-27

Security/privacy status: **LOCAL CODE CHECKS PASS; LINKED SMS-FIRST AND LIVE
UAT PENDING**.

## Current Findings

| Area | Status | Evidence |
| --- | --- | --- |
| Client secrets | Pass by tests/scans | Focused tests and release scans cover obvious API key, token, JWT, and database URL patterns. |
| Local env files | Pass | `.env`, `.env.local`, and `.env.json` remain ignored/untracked. |
| Android SMS permissions | Partially proven | Restricted SMS permissions are isolated to the Android SMS access flavor and runtime permission is required before ingestion is enabled; real MoMo SMS UAT is still pending after the refactor. |
| Identity privacy | Pass locally | Current UX uses generated 6-digit Collect ID and does not ask for or display real names. |
| Payment privacy | Pass locally | Contributor flow creates payment intents and does not expose manual transaction reporting. |
| Raw SMS default handling | Pass by contract; live UAT pending | Raw SMS is not part of public/member UI. Compliance reveal is permission-gated and audited in linked admin/security UAT. |
| Parser/allocation boundary | Partially proven | Edge Functions type-check and local contracts pass; linked SMS-first allocation UAT is blocked by remote migration drift. |
| Admin authorization | Pass in linked rollback UAT | `scripts/collect_admin_security_uat.sh` verifies RBAC, reveal audit, reparse permission, and denial paths. |
| Admin PWA local runtime | Pass | Local build/render smoke passes and screenshots are nonblank. |
| Admin PWA live runtime | Blocked | `ADMIN_PWA_LIVE_URL` is required for deployed URL proof. |

## Required Before Release

1. Apply the SMS-first migration to the linked Supabase project and rerun linked
   contribution/allocation UAT.
2. Run real Android SMS access UAT with sanitized MoMo SMS scenarios.
3. Deploy the Admin PWA and pass the live gate.
4. Run the release secret scan in the final release environment.
5. Record stakeholder and release-owner signoff.

Older CAPTCHA/HIBP/plan/PITR release findings are historical for the previous
packet and are not treated as current blockers unless a fresh post-refactor
readiness run reproduces them.

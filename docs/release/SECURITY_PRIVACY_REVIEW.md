# Collect Security And Privacy Review

Audit date: 2026-08-08

Security/privacy status: **LOCAL CODE CHECKS, LINKED BACKEND UAT, AND ADMIN
PWA LIVE GATE PASS; HUMAN RELEASE SIGNOFF PENDING**.

## Current Findings

| Area | Status | Evidence |
| --- | --- | --- |
| Client secrets | Pass by tests/scans | Focused tests and release scans cover obvious API key, token, JWT, and database URL patterns. |
| Local env files | Pass | `.env`, `.env.local`, and `.env.json` remain ignored/untracked. |
| Android SMS permissions | Implemented and emulator-validated; Play approval pending | Production and internal-receiver manifests request only `RECEIVE_SMS`, not inbox-history access. Native status, consent, runtime request, denial recovery, turn-off, optional telephony compatibility, and Android 16 emulator flows pass. Play version 12 contains only `RECEIVE_SMS`; the corrected declaration is awaiting Play review. |
| Android SMS queue | Pass by local contracts and Android 16 emulator UAT | Newly delivered provider-filtered messages use an Android Keystore AES/GCM queue. Entries remain retryable until successful ingestion acknowledgement, are bounded, and are cleared when access is disabled. Real-provider and physical-device evidence remains separate. |
| Native notifications | Implemented locally; live delivery pending | Android 13+ runtime permission, native settings recovery, four notification channels, private lock-screen visibility, FCM token lifecycle, tap/deep-link handling, and FCM HTTP v1 dispatch are implemented. Live Firebase credentials and end-to-end delivery evidence are still required. |
| Identity privacy | Pass locally | Current UX uses generated 6-digit Collect ID and does not ask for or display real names. |
| Payment privacy | Pass locally | Contributor flow creates payment intents and does not expose manual transaction reporting. |
| Raw SMS default handling | Pass by contract; human UAT pending | Raw SMS is not part of public/member UI. Compliance reveal is permission-gated and audited in linked admin/security UAT. |
| Parser/allocation boundary | Local and linked contracts pass; device UAT pending | Edge Functions type-check and local contracts pass. Linked SMS-first allocation UAT passes after applying `supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql`. |
| Admin authorization | Pass in linked rollback UAT | `scripts/collect_admin_security_uat.sh` verifies RBAC, reveal audit, reparse permission, and denial paths. |
| Admin PWA local runtime | Pass | Local build/render smoke passes and screenshots are nonblank. |
| Admin PWA live runtime | Pass | `https://cool-admin-212.pages.dev` passed the deployed URL live gate. |

## Required Before Release

1. Obtain Google Play approval for the SMS Permissions Declaration before
   publishing a production build that requests `RECEIVE_SMS`.
2. Run real Android SMS access UAT with sanitized foreground, background,
   killed-app, offline-retry, disable/clear, and denial-recovery scenarios.
3. Configure server-side `FCM_SERVICE_ACCOUNT_JSON` and record live Android
   foreground/background/tap delivery evidence without exposing device tokens.
4. Run the release secret scan in the final release environment.
5. Record Android signing review, physical-device accessibility review, iOS
   release-scope evidence, stakeholder signoff, and release-owner approval.

Older CAPTCHA/HIBP/plan/PITR release findings are historical for the previous
packet and are not treated as current blockers unless a fresh post-refactor
readiness run reproduces them.

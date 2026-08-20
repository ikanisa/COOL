# Production readiness checklist

As of 20 August 2026, the bank-transfer-only implementation passes its focused
Flutter analysis and bank/admin/member contract tests locally. Production
deployment and post-deploy verification must complete before this checklist can
be marked ready.

| Control | Current state | Required evidence |
| --- | --- | --- |
| Stripe/payment API removal | Local pass | Retired function inventory empty; Stripe tables absent after guarded cutover |
| Member bank journey | Local pass | EUR request, beneficiary display, Revolut handoff and no fabricated success |
| Bank details | Local pass | Placeholder disabled; production details independently approved |
| SMS/email evidence | Local pass | Authenticated/HMAC ingestion, idempotency and raw reveal audit |
| Daily statement | Local pass | Import, reconciliation, exceptions and close UAT |
| Ledger | Local pass | Exact-once balanced immutable journal |
| Admin control plane | Local pass | Bank queues, maker-checker, users, groups, notifications, settings and audit |
| Push notifications | Pending production configuration | May2026 Firebase Android config and validated FCM service account secret |
| Supabase production | Pending deployment | Migration version, six-function inventory and linked readiness output |
| Real bank flow | Pending accountable UAT | Real receipt evidence plus statement match and exact delivery chain |
| Store/device/accessibility | Separate release gate | Physical-device and store evidence |

No production Go-Live claim is permitted until the production rows above and
the real bank-flow chain are evidenced.

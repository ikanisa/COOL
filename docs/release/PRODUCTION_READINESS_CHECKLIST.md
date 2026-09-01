# Production readiness checklist

As of 31 August 2026, the geographic MoMo/diaspora-bank implementation passes
its local source checks. Production deployment, provider review and physical
acceptance must complete before this checklist can be marked ready.

| Control | Current state | Required evidence |
| --- | --- | --- |
| Regional rail routing | Local pass | Rwanda sees MoMo only; diaspora sees bank/Revolut only |
| WhatsApp/profile defaults | Local pass | Country and provider-aware 07 number default, editable with consent revocation |
| Rwanda MoMo journey | Local pass | Exact RWF intent, USSD handoff, no fabricated success, no PIN capture |
| Android SMS scope | Local pass | `RECEIVE_SMS` only, no `READ_SMS`/`SEND_SMS`, consent and protected queue |
| MoMo reconciliation | Local pass | Bounded parser, unique allocation, idempotency, exceptions and balanced ledger |
| Diaspora bank journey | Local pass | EUR request, beneficiary display, Revolut handoff and no fabricated success |
| Bank details | Local pass | Placeholder disabled; production details independently approved |
| SMS/email evidence | Local pass | Authenticated/HMAC ingestion, idempotency and raw reveal audit |
| Daily statement | Local pass | Import, reconciliation, exceptions and close UAT |
| Ledger | Local pass | Exact-once balanced immutable journal |
| Groups | Local pass | Platform-sponsored public groups; member-created groups private and Android-only |
| Admin control plane | Local pass | Separate Rwanda MoMo and diaspora bank queues, reconciliation and audit |
| Push notifications | Pending production configuration | May2026 Firebase Android config and validated FCM service account secret |
| Supabase production | Pending deployment | Migration history, function inventory and linked readiness output |
| Google Play policy | Pending approval | Restricted-SMS declaration approved for core functionality |
| Physical Rwanda flow | Pending accountable UAT | MTN/Airtel USSD, real receipt, allocation, ledger and exception chain |
| Real diaspora bank flow | Pending accountable UAT | Receipt evidence plus statement match and exact delivery chain |
| Store/device/accessibility | Separate release gate | Physical-device and store evidence |

No production Go-Live claim is permitted until the production rows above and
the real bank-flow chain are evidenced.

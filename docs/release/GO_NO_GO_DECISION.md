# Collect GO/NO-GO Decision

Audit date: 2026-06-01

Decision: NO-GO for public production launch until the corrected SMS-first
Groups product contract is fully validated on mobile, Admin PWA, and linked
Supabase.

## Rationale

The previous product definition described goals, public campaigns, manual SMS
paste, contributor-reported transaction IDs, and anonymity choices. That model
has been superseded. The current source of truth is the Groups workflow:

- Profile owns MoMo number and 6-digit Collect ID.
- Android-only group creation syncs profile MoMo as receiver.
- iPhone group creation shows `group creation is available only on Android`.
- Members share groups by link/QR/deep link/chat/SMS.
- `Contribute` creates a Supabase payment intent tied to group, amount,
  receiver MoMo, user id, and Collect ID.
- MoMo payment is completed off app through the dialer.
- MoMo SMS is ingested, parsed, allocated, and posted to the ledger.

## Current Gate Summary

| Gate | Result |
| --- | --- |
| Mobile analyzer | Pass |
| Targeted route/profile/payment-intent tests | Pass |
| Supabase Edge Function type-check | Pass |
| Supabase migration validation | Pass |
| Focused Flutter and release-doc suites | Pass |
| Admin PWA build/render smoke | Pass locally |
| Admin PWA live deployment proof | Pass: `https://cool-admin-212.pages.dev` passed `scripts/admin_pwa_live_gate.sh --json` |
| Linked Supabase migration/readiness | Blocked: linked contribution UAT fails until the sender-hash migration is applied |
| Android release APK/AAB artifacts | Pass: current artifacts are fresh and artifact manifest passes |
| Android signing review | Blocked: signing / Play App Signing review evidence missing |
| iOS release scope | Blocked: iOS scope not signed off or explicitly out of scope |
| Linked admin/security rollback UAT | Pass |
| Android real SMS UAT | Pending |
| Human stakeholder signoff | Pending |

## Required Next Actions

1. Review and sign off the corrected SMS-first Groups product definition.
2. Run Android SMS ingestion/parser/allocation UAT with sanitized evidence.
3. Apply `supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql` and rerun linked contribution UAT.
4. Record Android signing review and iOS release scope evidence.
5. Record release-owner signoff for the current evidence packet.
6. Regenerate the release evidence packet from current validators only.

Older Supabase platform blockers are not repeated here as current blockers
unless a fresh readiness run after this refactor reproduces them.

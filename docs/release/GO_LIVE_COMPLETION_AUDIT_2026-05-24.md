# Collect Go-Live Completion Audit

Audit date: 2026-06-01

Decision: **NO-GO**

This audit supersedes the earlier 2026-05-24 packet for the SMS-first Groups
refactor. It maps the current objective to evidence generated after replacing
the old goals/campaign/manual-SMS/anonymity product model.

## Evidence Baseline

| Evidence | Current result |
| --- | --- |
| Flutter analyzer | Pass with `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze`. |
| Flutter tests | Pass: `101` tests in the full Flutter/release-doc suite. |
| Admin PWA local build/render | Pass: release build and render smoke evidence under `.cache/repo_wide_qa_uat/20260601T205424Z/admin_pwa_render_smoke`. |
| Mobile route render evidence | Pass: retained 390x844 screenshots and JSON nonblank checks for 21 representative routes under `.cache/mobile_route_render_smoke/20260602T040433Z`. |
| Admin PWA live gate | Pass: `https://cool-admin-212.pages.dev` passed `scripts/admin_pwa_live_gate.sh --json`. |
| Local Supabase migration validation | Pass. |
| Edge Function auth/type checks | Pass. |
| Linked admin/security UAT | Pass. |
| Linked SMS-first contribution UAT | Blocked: linked DB does not store contribution intent sender hash. |
| Supabase readiness | Blocked until `supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql` is applied and linked contribution UAT passes. |
| Real Android SMS access UAT | Pending. |
| Android release artifacts | Pass. |
| Android signing / iOS scope | Pending. |
| Stakeholder/release-owner signoff | Pending. |

## Requirement Audit

| Requirement | Evidence status | Gap or next action |
| --- | --- | --- |
| Correct product definition | Partial | Stakeholder approval is required for `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md`. |
| Remove old invented flows | Proven locally | Current app/docs remove public directory, goals, categories, target amounts, cover URL, manual SMS paste, manual payment reports, and anonymity picker from current journeys. |
| Verify Home/Groups/Settings mobile shell | Proven locally | Focused app shell and widget tests pass. |
| Verify Android-only group creation | Proven locally | iPhone warning copy is tested; physical iOS scope still needs release decision if iOS is included. |
| Verify contribution/payment intent/USSD launch | Backend migration pending | Repository/widget tests pass; linked rollback UAT is blocked until the sender-hash migration is applied. |
| Verify MoMo SMS ingestion/parser/allocation | Device UAT pending | Edge contracts pass; linked allocation UAT is blocked until the sender-hash migration is applied; physical Android SMS UAT remains pending. |
| Verify admin monitoring and RBAC | Partial | Local Admin PWA, live Admin PWA gate, and linked admin/security UAT pass; human admin walkthrough/signoff remains. |
| Verify release evidence quality | Partial | Current release docs, approval packet, repo-wide QA index, and mobile render evidence are refreshed; final release packet must still be regenerated after device UAT and signoffs pass. |

## Current Blocking Keys

- `product_signoff`
- `android_sms_access_uat`
- `android_release_signing_review`
- `ios_release_scope`
- `linked_supabase_sms_first_migration`
- `release_owner_signoff`

## Completion Decision

The objective is not complete. Local code checks, Admin PWA live proof, and
Android device smoke are green, but linked Supabase sender-hash migration and
production approval must wait for real Android MoMo SMS evidence approval,
Android
signing/iOS scope evidence, and release signoff.

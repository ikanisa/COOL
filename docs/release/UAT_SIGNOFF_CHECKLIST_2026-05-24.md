# Collect Human UAT Signoff Checklist

Prepared: 2026-05-24

Purpose: capture the human release-owner and persona acceptance evidence that
automated rollback UAT cannot prove. Do not record raw SMS, phone/MOMO numbers,
tokens, provider secrets, service-role keys, or unrestricted production data in
this checklist.

Status: **PENDING SIGNOFF**

## Preconditions

- [ ] CAPTCHA/bot protection is configured or the test is explicitly marked as
      pre-CAPTCHA staging UAT.
- [ ] If any row is marked pre-CAPTCHA staging UAT, the release-owner decision
      remains **NO-GO** until CAPTCHA is configured and the affected persona
      evidence is rerun or formally accepted as non-production rehearsal only.
- [ ] HIBP leaked-password protection is enabled after any required Supabase
      plan upgrade, or this checklist is staging-only and not usable for
      production GO.
- [ ] Free-plan project-pause risk and PITR/RPO risk are resolved or validly
      exceptioned after non-exceptionable blockers are fixed.
- [ ] Latest `make release-status-json` no longer reports
      `database_connectivity`, or this checklist is explicitly marked as
      staging-only and not usable for production GO.
- [ ] Test users are synthetic or approved release-test accounts.
- [ ] Test collection, payment, receiver, and SMS data are synthetic.
- [ ] Screenshots/logs are sanitized before attaching to the release packet.
- [ ] Current automated evidence is attached:
  - `.cache/supabase_go_live_evidence/20260524T085150Z`
  - `build/app/outputs/flutter-apk/app-production-release.apk`
  - `build/app/outputs/bundle/productionRelease/app-production-release.aab`
  - `build/web/main.dart.js`
  - `docs/release/UAT_EXECUTION_REPORT.md`
  - `docs/release/GO_LIVE_COMPLETION_AUDIT_2026-05-24.md`

## Persona Signoff Matrix

| ID | Persona | Required acceptance evidence | Status | Signoff |
| --- | --- | --- | --- | --- |
| UAT-01 | Contributor | Signed-in tester opens approved public collection, creates payment intent, sees MOMO/USSD instructions, marks paid with sanitized reference, and verifies identity choice. | Pending |  |
| UAT-02 | Creator | Tester creates private collection, adds receiver MOMO, requests public listing, and verifies share/QR link does not expose private receiver data. | Pending |  |
| UAT-03 | Recurring group admin | Tester creates or reviews recurring collection period behavior and confirms member/admin visibility. | Pending |  |
| UAT-04 | Public supporter | Tester uses public directory and contribution flow without membership; only approved collections are visible and receiver details appear only at contribution step. | Pending |  |
| UAT-05 | Receiver/SMS operator | Tester enters sanitized receiver MOMO SMS, verifies parse/review path, and confirms raw SMS is not public. | Pending |  |
| UAT-06 | Moderator | Tester reviews public-listing request through permitted admin lane and confirms audit trail. | Pending |  |
| UAT-07 | Payments admin | Tester manually allocates ambiguous/unallocated event with reason and confirms single ledger post and audit log. | Pending |  |
| UAT-08 | Compliance admin | Tester reveals raw SMS through reason-required permissioned flow and confirms sensitive-access/audit records. | Pending |  |
| UAT-09 | Non-admin | Tester attempts admin UI/API access and confirms denial without sensitive data leakage. | Pending |  |
| UAT-10 | Edge-case user | Tester verifies duplicate transaction, invalid amount, non-Rwanda phone, expired intent, ambiguous amount, missing receiver authorization, failed Edge Function auth, and retry/idempotency behavior. | Pending |  |

## Release Owner Decision

Release owner:

Decision:

- [ ] GO
- [ ] NO-GO

Decision rationale:

Evidence location:

Date/time:

## Minimum GO Conditions

- [ ] All ten persona rows are signed or formally waived by the release owner.
- [ ] No persona evidence is staging-only, pre-CAPTCHA-only, or dependent on a
      runner that still reports `database_connectivity`.
- [ ] `make supabase-ready-strict` passes.
- [ ] `make supabase-platform-exception-gate` passes or has no remaining
      exceptionable blockers to validate.
- [ ] `make supabase-go-live-gate-json` reports `go_live_approved=true`.
- [ ] `make supabase-go-live-evidence` is rerun after all platform and UAT
      changes.
- [ ] Worktree/release branch is intentionally reviewed before shipping.

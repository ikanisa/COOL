# Collect Human UAT Signoff Checklist

Prepared: 2026-06-01

Purpose: capture release-owner and persona acceptance evidence for the corrected
SMS-first Groups platform. Do not record raw SMS, phone/MoMo numbers, tokens,
provider secrets, service-role keys, OpenAI keys, or production customer data.

Status: **PENDING SIGNOFF**

## Preconditions

- [ ] Corrected product definition is approved.
- [ ] Linked Supabase SMS-first migration is applied and linked contribution
      UAT passes.
- [ ] Android SMS access UAT is complete with sanitized evidence.
- [ ] Admin PWA deployed URL passes live gate.
- [ ] Test users, groups, payment intents, receiver values, and SMS data are
      synthetic or approved release-test data.
- [ ] Screenshots/logs are sanitized before attaching to the release packet.
- [ ] `docs/release/UAT_EVIDENCE_MANIFEST.json` exists and
      `make uat-evidence-gate-json` passes for all ten persona evidence rows.
- [ ] Current automated evidence is attached:
  - `.cache/repo_wide_qa_uat/20260601T205424Z/summary.json`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/evidence_index.json`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/admin_pwa_live_gate.json`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/android_device_uat.txt`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/supabase/summary.json`
  - `docs/release/UAT_EXECUTION_REPORT.md`
  - `docs/release/GO_LIVE_COMPLETION_AUDIT_2026-05-24.md`
  - `docs/release/RELEASE_APPROVAL_PACKET.md`

## Persona Signoff Matrix

| ID | Persona | Required acceptance evidence | Status | Signoff |
| --- | --- | --- | --- | --- |
| UAT-01 | Contributor | Tester opens group, creates payment intent, launches MoMo USSD, and waits for MoMo SMS allocation. | Pending |  |
| UAT-02 | Android creator | Tester creates group, confirms receiver MoMo sync from profile, grants SMS access, and verifies share/QR/deep link/SMS. | Pending |  |
| UAT-03 | iPhone user | Tester taps group creation and sees exactly `group creation is available only on Android`. | Pending |  |
| UAT-04 | Group member | Tester opens shared group and contributes without repeating profile identity/MoMo details. | Pending |  |
| UAT-05 | Android SMS device | Tester grants Android SMS access, verifies automated parse/allocation path, and confirms raw SMS is not public. | Pending |  |
| UAT-06 | Admin operator | Tester monitors SMS parsing, allocations, exceptions, and ledger through permitted admin lane. | Pending |  |
| UAT-07 | Payments admin | Tester requests reparse for ambiguous event with reason and confirms audit log without manual ledger posting. | Pending |  |
| UAT-08 | Compliance admin | Tester reveals raw SMS through reason-required permissioned flow and confirms sensitive-access/audit records. | Pending |  |
| UAT-09 | Non-admin | Tester attempts admin UI/API access and confirms denial without sensitive data leakage. | Pending |  |
| UAT-10 | Edge-case user | Tester verifies invalid amount, international WhatsApp phone, expired intent, ambiguous amount, missing receiver authorization, failed Edge Function auth, and retry/idempotency behavior. | Pending |  |

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
- [ ] Product signoff, linked SMS-first UAT, Android SMS UAT, Admin PWA live
      proof, and release-owner signoff are complete.
- [ ] `make release-status-json` has no blocker keys.
- [ ] `make supabase-go-live-gate-json` reports `go_live_approved=true`.
- [ ] Worktree/release branch is intentionally reviewed before shipping.

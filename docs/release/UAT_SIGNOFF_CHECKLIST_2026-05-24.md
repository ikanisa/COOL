# Collect Human UAT Signoff Checklist

Prepared: 2026-06-01

Purpose: capture release-owner and persona acceptance evidence for the corrected
SMS-first Groups platform. Do not record raw SMS, phone/MoMo numbers, tokens,
provider secrets, service-role keys, OpenAI keys, or production customer data.

Status: **PENDING SIGNOFF**

## Preconditions

- [ ] Corrected product definition is approved.
- [x] Linked Supabase SMS-first migration is applied and linked contribution
      UAT passes.
- [ ] Android SMS access UAT is complete with sanitized evidence.
- [ ] Admin PWA deployed URL passes live gate.
- [ ] Test users, groups, payment intents, receiver values, and SMS data are
      synthetic or approved release-test data.
- [ ] Screenshots/logs are sanitized before attaching to the release packet.
- [ ] `docs/release/UAT_EVIDENCE_MANIFEST.json` exists and
      `make uat-evidence-gate-json` reports no missing, empty, escaped, or
      unsanitized evidence files. It may remain blocked on human signoff fields
      until every persona and the release owner signs.
- [ ] Current automated evidence is attached:
  - `.cache/repo_wide_qa_uat/20260601T205424Z/summary.json`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/evidence_index.json`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/admin_pwa_live_gate.json`
  - `.cache/android_device_uat/20260602T042542Z/android_device_uat.txt`
  - `.cache/supabase_go_live_evidence/20260602T045205Z/summary.json`
  - `.cache/mobile_release_gate/20260602T050529Z/mobile_release_gate.json`
  - `.cache/android_install/20260602T050529Z/final_release_package.txt`
  - `docs/release/UAT_EXECUTION_REPORT.md`
  - `docs/release/GO_LIVE_COMPLETION_AUDIT_2026-05-24.md`
  - `docs/release/RELEASE_APPROVAL_PACKET.md`

## Persona Signoff Matrix

Record each persona row in `docs/release/UAT_EVIDENCE_MANIFEST.json` with the
guarded recorder rather than hand-editing JSON when possible:

```bash
make record-uat-evidence-signoff ARGS="--persona-id UAT-01 --status signed --signoff '<reviewer and evidence summary 2026-06-02T12:00:00Z>'"
```

Record real Android SMS scenario evidence before signing UAT-05. The recorder
stores sanitized metadata only, attaches the evidence to UAT-05, and does not
approve the persona or release:

```bash
make record-android-sms-uat-evidence ARGS="--tester '<name>' --tested-at '<ISO-8601 UTC timestamp>' --device-label 'Pixel 4a UAT device' --scenarios consent,foreground_sms,background_sms,killed_app_sms,offline_retry,parser_allocation,exception_review,ledger_posting,privacy --evidence-summary '<sanitized scenario summary>' --sanitized-evidence --no-production-customer-data --raw-sms-not-public --no-phone-or-momo --no-transaction-ids"
```

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

After all ten persona rows are signed or waived, record the release-owner
decision in the UAT evidence manifest:

```bash
make record-uat-evidence-signoff ARGS="--release-owner '<name>' --decision GO --signed-at '<ISO-8601 UTC timestamp>'"
```

## Minimum GO Conditions

- [ ] All ten persona rows are signed or formally waived by the release owner.
- [ ] Product signoff, Android SMS UAT, Admin PWA live
      proof, and release-owner signoff are complete.
- [ ] `make release-status-json` has no blocker keys.
- [ ] `make supabase-go-live-gate-json` reports `go_live_approved=true`.
- [ ] Worktree/release branch is intentionally reviewed before shipping.

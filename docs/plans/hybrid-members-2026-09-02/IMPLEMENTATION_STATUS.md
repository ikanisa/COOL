# Collect hybrid membership — implementation status

Date: 3 September 2026

Verdict: **BACKEND AND ADMIN DEPLOYED WITH FLAGS OFF; PHYSICAL PILOT AND RELEASE ACCEPTANCE OPEN**

**Latest continuation:** directory migration `20260903200322` is deployed;
production is at 121 migrations. Admin Worker `1b868d4f-1da5-4ecd-8d41-323616b87110`
is live at 100% with matching asset hashes and authenticated Members/approvals
readback. MCP normal OTP/Keychain authentication and actual stdio health/list
PASS; TypeScript and 17 tests PASS. The existing minute monitor is ACTIVE,
read-only/no-send. Route Buri Munsi / 41258 and the conditional fresh-payment
handover window are resolved. [Current deployment/operator evidence](../../release/HYBRID_CONTINUATION_DEPLOYED_2026-09-03.md)
supersedes the earlier pending-deployment/credential statements below.

**Earlier continuation:** second-Admin fresh login/reload and hosted read-only
navigation now PASS. Live QA found member identity/status/sorting gaps; a forward
directory correction and Flutter UI/login recovery fixes pass locally with 562
Flutter tests, 15 database assertions and 11 MCP tests. These new fixes are **not
deployed**: production remains at 120 migrations; local migration `20260903200322`
is pending. Earlier no-pending statements below describe the preceding release.
See [current authenticated UAT and remaining gates](/Volumes/PRO-G40/COOL/docs/release/HYBRID_AUTHENTICATED_ADMIN_UAT_2026-09-03.md).

## Implemented and verified

- One account-independent member registry retains Collect ID, member name, registered MoMo name and full protected MoMo number without creating fake Auth users. Admin member lists and details combine app, claimed and feature-phone members; member-facing rosters expose only safe Collect identity.
- Private Admin-assisted groups are created atomically with a share-code/QR secret and a reviewed roster. Manual paste, CSV and TXT use deterministic parsing. XLSX is decoded deterministically across sheets and formula cells fail closed.
- PDF/JPEG/PNG/WebP rosters use the existing `OPENAI_API_KEY` only inside the authenticated Edge Function. Calls use the Responses API, strict JSON schema, `store:false`, no tools, a 5 MB limit, file digest and explicit consent. Model output cannot be submitted directly: it must be moved into the editor, corrected and re-previewed deterministically.
- Exact permitted raw MoMo SMS is retained separately from normalized parsing input. Deterministic parsing rejects outgoing, reversed, pending, promotional, credential and ambiguous messages.
- Direct-USSD allocation resolves an active receiving assignment plus normalized registered MoMo name and payer last-three digits. It never selects among ambiguous groups or posts on amount/time guessing. Matching and financial finality are separate steps: a fresh device-attested provider receipt can finalize its own matched candidate automatically, while unattested or arbitrary client-supplied SMS cannot post money.
- A balanced RWF journal, immutable member/group after-balance snapshots, reversals and replay protection serialize concurrent postings and keep one payment per provider event.
- Account claiming requires the authenticated full verified phone to equal the stored full MoMo number. Name and last-three digits are never credentials. Claims preserve the offline Collect ID/history and suppress unsent SMS routing.
- The durable feature-phone receipt outbox is consent- and feature-flag-gated. It freezes destination, exact body and balances; implements fenced claims, send-start, observed sent, failed-no-send and uncertain outcomes; and never auto-retries a possibly sent attempt.
- The exact recovered acknowledgement is:

  `BuriMunsi: Twakiriye ubwizigame bwawe bwa {amount} RWF. Balance yawe: {member_balance} RWF; balance y'itsinda: {group_balance} RWF. Ref: {reference}.`

- An authenticated Edge operator and dedicated local MCP expose nine bounded commands only: health, list, claim, claimed receipt read, exact confirmation, send-start, outcome, safe release and heartbeat. There is no generic SQL, arbitrary destination/body or financial-write tool.
- The Admin PWA includes assisted-group/roster intake, unified member directory and a masked SMS receipt queue. Exact phone/body remain claim-gated, and “Observed sent” is explicitly distinguished from handset delivery.
- A native one-minute heartbeat named `Collect feature-phone receipts` was created in **PAUSED** state with quiet-idle, action-time confirmation and uncertain-no-retry rules.

## Feature and release controls

- `hybrid_member_onboarding`, `hybrid_direct_ussd_allocation`, `native_sms_attestation_enforcement`, `hybrid_sms_notifications` and `hybrid_verified_account_claim` remain OFF in production.
- No OpenAI key is embedded in Flutter, MCP arguments, Git or documentation. Production readiness now requires the server-side secret name.
- Production reads back at 120 migrations through `20260903092500`. The local directory correction `20260903200322` is now pending review/deployment. Eleven Edge Functions were active at the preceding cutover; the five hybrid functions were deployed in guarded order and their source was independently read back byte-for-byte.
- The Admin PWA production version `871850eb-a270-489a-b400-b9facf6b5532` serves 100% of traffic and passes the live custom-domain asset/header gate at `https://admin.collect.ikanisa.com`.
- All five hybrid flags remain OFF. No live OpenAI roster request, real payment, Messages send, store upload, public distribution, Git push or hybrid feature activation occurred in the final verification work.
- Every real SMS still requires the exact imminent full recipient and exact body to be shown to Jean Bosco for fresh confirmation. The created heartbeat is not send authorization.

## Current validation evidence

| Gate | Current result | Boundary |
| --- | --- | --- |
| Production migrations | 120 through `20260903092500`; local correction `20260903200322` pending | Hosted readback; flags remain OFF; candidate tested locally |
| Production-copy upgrade rehearsal | 23 reviewed migrations pass; 116 protected tables / 202,926 rows preserved; ACL/index/hybrid contracts pass | Encrypted RAM-only, network-disabled archive copy; not production GO |
| Hosted advisors | Reviewed warning inventory matches the release gate; performance has zero warning-level findings | Not a zero-findings certification |
| Financial SQL UAT | 35 direct-USSD assertions plus concurrent two-event/same-event serialization pass | Synthetic data; matching and finality boundaries simulated |
| Roster SQL UAT | 10 assertions pass | Synthetic Admin/member rows rolled back |
| SMS outbox SQL UAT | 25 assertions pass | Synthetic consent/claims/outcomes; no SMS sent |
| Verified account claim SQL UAT | 20 assertions pass | Synthetic exact-phone Auth claim; no SMS sent |
| Raw SMS finality SQL UAT | 13 assertions pass | Synthetic fresh device-attested provider receipt automatically finalizes the matched candidate; rolled back |
| Edge/Deno | Format/type checks pass; production-readiness suite records 54/54 parser, receipt, operator, attestation and roster/OpenAI contract tests passing | Functions deployed with exact source readback; no live OpenAI extraction or physical journey |
| Flutter | Analyze clean; production-readiness suite records 557/557 passing; current focused Admin suite passes 27 tests | Source/widget tests; not physical-device acceptance |
| Admin browser | Full 23-route × 3-viewport matrix passes 69/69 with zero browser/page errors | Local authenticated evidence mode; hosted/manual assistive-tech acceptance remains open |
| Edge and MCP | Five hybrid functions active with exact source readback; MCP registered read-only; TypeScript and 11 tests including real stdio startup pass | Runtime credentials absent; authenticated dry run remains open |
| Contract/security hygiene | Production-rehearsal tests pass 16 assertions; combined release contracts pass 82 assertions; tracked/untracked secret scan and diff whitespace check pass | Technical gate passes; accountable approvals and physical acceptance remain open |
| Restore report | [Production-copy V23](/Volumes/PRO-G40/COOL/docs/release/PRODUCTION_COPY_UPGRADE_REHEARSAL_V23_2026-09-03.json) | Explicit result: not production GO |

Additional replay evidence:

- [Notification and claim continuation](/Volumes/PRO-G40/COOL/docs/release/HYBRID_NOTIFICATION_CLAIM_CLEAN_REPLAY_2026-09-03.json)
- [Failed-no-send filter replay](/Volumes/PRO-G40/COOL/docs/release/HYBRID_SMS_FILTER_CLEAN_REPLAY_2026-09-03.json)
- [Admin browser QA](/Volumes/PRO-G40/COOL/docs/release/HYBRID_ADMIN_BROWSER_QA_2026-09-03.md)
- [Operator connection and active legacy-sender preflight](/Volumes/PRO-G40/COOL/docs/release/HYBRID_OPERATOR_PREFLIGHT_2026-09-03.md)

## Remaining release gates

1. Freeze/review the dirty source and complete the separately controlled Git publication chain without absorbing unrelated edits.
2. Complete a fresh approved-operator WhatsApp sign-in and authenticated hosted UAT for assisted creation, all import formats, row correction, group link/QR, unified member detail, receipt filters, masking and permission denial. Include one consented live OpenAI PDF/image roster extraction.
3. Complete governed runtime credential injection for the registered read-only MCP profile; refresh the host inventory and run authenticated health/list preflight. Never extract a browser session or save an access token in the repository/configuration.
4. Run an approved physical Android receipt-capture/payment test and one approved Mac Messages-to-feature-phone test. Verify the exact app build, sending line, recipient, complete multipart text, both balances/reference, visible outgoing state and handset receipt.
5. Resolve the confirmed active legacy Buri Munsi watcher, nearby receiver and Mac/iPhone dispatch path at an owner-approved takeover window. Reconcile sent/uncertain history before one-group activation; never run overlapping senders or replay old receipts.
6. Activate the paused heartbeat only after the MCP dry run, duplicate-worker check and action-time confirmation workflow pass. Any send-start ambiguity remains `uncertain` and is not automatically retried.
7. Obtain the exact Android signing review and release-owner signoff recorded in the production-readiness packet. Store upload, provider acceptance and public distribution remain separate state-changing gates.

The overall goal remains open until authenticated hosted journeys, physical capture/send evidence, operational acceptance, Android signing review and owner release approval are complete.

# Collect authenticated Admin UAT and directory corrections

Date: 3 September 2026, evening Kigali time.

Latest verdict: **DIRECTORY PATCH DEPLOYED AND LIVE-VERIFIED; MCP AUTHENTICATED;
READ-ONLY MINUTE MONITOR ACTIVE; SMS SENDING/PHYSICAL ACCEPTANCE OPEN.**

The [later deployment and operator continuation](HYBRID_CONTINUATION_DEPLOYED_2026-09-03.md)
supersedes the pending-deployment/runtime statements below. Production is at
121 migrations and the corrected Admin build is live. The sections below retain
the earlier discovery/local-test evidence chronologically.

## Completed hosted flow

1. The second approved Admin, Collect ID 956974 / WhatsApp ending 7816,
   completed a fresh OTP sign-in. The dashboard survived reload. No OTP or
   browser token was copied into evidence, source, or MCP configuration.
2. Members loaded two records. The production UI still used a WhatsApp-only
   identity heading and app-only subtitle, and its summary said zero Admins.
   This contradicted the effective approval/role state, not login authority.
3. Groups loaded five records. The assisted-group action opened the private
   group/reviewed-roster form. Cancel returned safely without creating a group,
   uploading a roster, requesting OpenAI extraction, or changing a route.
4. SMS receipts loaded its empty state. This proves queue access, not receipt
   generation, dispatch, or handset delivery.
5. Admin users loaded the two approved operator records. Independent read-only
   database checks also returned two active approvals and all five hybrid flags
   OFF. Production still has 120 migrations through `20260903092500`.

## Findings and local correction

| Finding | Correction | Evidence |
| --- | --- | --- |
| WhatsApp-only member identity hides feature-phone context | Members now lead with Collect ID and available member name, show explicit app/claimed/feature-phone account state and masked contact, and open a **member record**, not an invented account | Real widget tests at 390/1440 widths and 1x/2x text; browser readback |
| Admin summary trusts obsolete `profiles.is_platform_admin` | Forward SQL projection requires a current verified WhatsApp approval **and** nonrevoked platform-owner role; no Auth/role/approval records are modified | Synthetic stale-boolean, revoked-approval, missing-approval and missing-role cases |
| Oldest page gets re-sorted newest-first during JSON aggregation | Preserve deterministic window ordinal through pagination and JSON aggregation in both directory functions | Ascending, descending, tied timestamps and next-page assertions |
| Empty later page reports zero total | Count the filtered relation independently of the page | Out-of-range page returns empty rows and correct total |
| Login rejection asserts that the code was used/expired | Neutral verification error; successful resend clears the old input | Fake-provider widget recovery test, zero real OTP requests |

Product Design guided the live journey capture and same-width visual comparison;
the existing layout, colors, navigation, icons, and component system were retained.
The Flutter workflow added real widget regressions rather than source-string
checks alone. The two optional linked mobile skill files were unavailable;
repository patterns and the loaded Flutter standards were used instead.

## Current verification

- `flutter test --no-pub --reporter expanded`: **562 passed**, exit 0.
- Focused Admin suite: **62 passed**, plus **1** login recovery test.
- `flutter analyze --no-pub`: **no issues**, exit 0.
- `ruby scripts/tests/hybrid_directory_presentation_uat.rb`: **15 passed**.
  Schema-only isolated local database, synthetic users/members, transaction rollback.
  Application ACLs/RLS were retained; local scheduler extension/ACLs were omitted
  because this database is not the server's pg_cron database. Local setup used
  the existing test-container superuser to restore schema; hosted access was not
  altered. Two earlier incomplete local setup databases remain for diagnosis;
  neither contains copied customer records.
- Notification MCP: **11 passed**, including actual stdio startup/handshake.
- Release-mode **local evidence** web build: passed. It contains synthetic data,
  not live accounts, and must never be deployed as production.
- Dart formatting, Ruby syntax, and repository `git diff --check`: passed.
- Same-width browser comparison at 1055×837: identity and channel visible,
  existing spacing/navigation preserved, no observed card overflow. Desktop
  table also inspected at 1280×720. This does not certify complete WCAG,
  screen-reader, physical-device, or all-route production compliance.

Candidate migration: `20260903200322_hybrid_directory_presentation.sql`

SHA-256: `2909300e938a4f09012e025c7d22136953ff53ffd9c4713662a9bc33ffc5c4c1`

Local evidence `main.dart.js` SHA-256:
`e0a6be834db2e0af61ccc8cc15bbb3714e8460d4d33513cb940b5e44a4e47360`

The worktree already contained substantial implementation and unrelated edits.
No blanket staging, commit, push, release deployment, or history rewrite occurred.

## Accepted screenshots from this run

Each exact saved image was opened and inspected. These are local task artifacts,
not public uploads. Production images and synthetic preview images are distinct.

- [Hosted Members before correction](/Volumes/PRO-G40/COOL/.cache/hybrid-hosted-uat-20260903/screenshots/01-members.png)
- [Hosted Groups](/Volumes/PRO-G40/COOL/.cache/hybrid-hosted-uat-20260903/screenshots/02-groups.png)
- [Hosted assisted form, unsubmitted](/Volumes/PRO-G40/COOL/.cache/hybrid-hosted-uat-20260903/screenshots/03-assisted-form.png)
- [Hosted empty SMS queue](/Volumes/PRO-G40/COOL/.cache/hybrid-hosted-uat-20260903/screenshots/04-sms-queue.png)
- [Local corrected desktop table](/Volumes/PRO-G40/COOL/.cache/hybrid-hosted-uat-20260903/screenshots/05-local-members.png)
- [Hosted two-Admin roster](/Volumes/PRO-G40/COOL/.cache/hybrid-hosted-uat-20260903/screenshots/06-admin-roster.png)
- [Local corrected cards, same viewport as hosted reference](/Volumes/PRO-G40/COOL/.cache/hybrid-hosted-uat-20260903/screenshots/07-local-members-matched.png)

## Earlier execution gates — superseded by the linked continuation

1. **Release this patch:** scoped human review of the new forward migration and
   Admin build, then the controlled production migration/build deployment and
   fresh hosted Members/sort/filter/readback. Do not deploy the evidence build.
   Keep flags OFF. Capture the existing function definitions before deployment;
   rollback is a reviewed forward restoration plus previous Admin asset version,
   with no reversal of member, approval, ledger, or balance data.
2. **MCP credentials:** browser sign-in does not authenticate the separate MCP
   process. Its safe no-network preflight still reports missing
   `COLLECT_SUPABASE_ANON_KEY` and `COLLECT_OPERATOR_ACCESS_TOKEN`. Provision
   through an approved runtime-secret path; no browser-token extraction or
   service-role substitution. Refresh the host inventory and run health plus one
   bounded pending read before enabling any queue-control tool.
3. **Legacy takeover:** agree the handover window and isolate the exact legacy
   watcher/receiver and iPhone dispatch path. The earlier inspection found them
   send-capable; no service was stopped in this run. Reconcile sent/uncertain
   identifiers and prohibit historical replay before Collect owns pilot sends.
4. **Pilot selection and physical UAT:** owner must identify the group, receiving
   MoMo code, feature-phone recipient, test amount and sending line. Then complete
   consented hosted roster/import, receiving assignment, real incoming capture,
   deterministic allocation, journal/after-balances, duplicate/ambiguous cases,
   one action-time-approved exact receipt and handset readback. No real payment
   is initiated by this agent.
5. **Other live acceptance:** consented OpenAI image/PDF extraction evaluation,
   verified full-phone account claim/history continuity, manual accessibility and
   physical-device recovery. First-number OTP non-delivery is still a separate
   unresolved incident; second-number login does not prove it fixed.
6. **Activation/signoff:** both existing Codex receipt automations remain PAUSED.
   Only after the credential, single-sender and physical acceptance gates pass,
   enable the scoped feature flags and one-minute operator under the existing
   exact-recipient/body approval and uncertain-no-retry rules. Store/public
   distribution and accountable release-owner acceptance remain separate gates.

No production financial write, group/member creation, receipt send, provider
request, feature activation, service shutdown, or store submission was performed
by this QA continuation. The overall hybrid production goal is not complete.

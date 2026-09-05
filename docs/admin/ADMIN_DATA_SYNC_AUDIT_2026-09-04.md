# Admin and Supabase data audit — 2026-09-04

**Deployment update:** the two Admin corrections and migration
`20260903201326` are now live; production/local histories match at 122.
Authenticated Admin readback and asset hashes were verified. See the
[deployment and Home correction report](../release/ADMIN_SUPABASE_DEPLOYMENT_2026-09-04.md).
The audit below records the earlier read-only snapshot; its configuration
fallback and stored test-record findings remain open.

Status: **Live list counts reconcile; Admin corrections and migration deployed.
Configuration gaps remain. “No hardcoded data” is not fully established.**

Requested by Jean Bosco as an extension of the mobile design audit. Live checks
used the existing authenticated Admin session and read-only SQL transactions
against project `lhbowpbcpwoiparwnwgt`. Production data was not changed during
that initial audit; the later authorized deployment is recorded above.

## Live readback

The deployed Admin browser made successful HTTP 200 Supabase RPC requests to
the expected project. Its data agrees with direct database queries at
2026-09-04 05:09–05:15 UTC:

| Surface / assertion | Admin readback | Database readback |
| --- | --- | --- |
| Groups | 5; 2 public, 3 private | 5 collections; 2 public |
| Members | 2 active members | 2 profiles with active membership in an active group |
| Users | 7 without active groups | 7 profiles without active group membership |
| Transactions | 3 needing attention; 0 allocated | 3 parsed events requiring review |
| Public payees | 2 | 2 active public payees |
| Overview | 3 open reconciliations; 0 unallocated transactions; 0 balanced ledgers; 2 active payees | `admin_overview` returns those four live metrics |
| Raw receipt ingestion | Not separately asserted through the UI | 3 raw SMS; 3 parsed events; no raw SMS missing an event |
| Membership links | Not separately asserted through the UI | 3 membership rows; none missing the associated member record |
| Posted payment/ledger link | No completed-payment claim | 0 posted payments, 0 ledger rows; zero missing credit postings is vacuous at this volume |

Members, users, membership rows and member records have different definitions;
their counts must not be equated. In particular, 2 members plus 7 users accounts
for the 9 profiles, while a profile may have several group membership rows.
The overview's “unallocated transactions” metric filters the transaction RPC
to the exact `unallocated` status, while the reconciliation queue includes
other review statuses. A zero in that metric does not mean the three review
events have been reconciled.

## Corrections implemented locally

1. **Country-filtered lists lost full totals and rows beyond 100.** The UI
   requested the first 100 rows, re-counted them and paginated in memory even
   though `admin_list_country_scoped` already supports server pagination and
   returns the complete filtered total. `admin_list_runtime.dart` now requests
   each 25-row page and uses the returned total. A regression with 125 rows
   confirms that page five requests offset 100 and displays rows 101–125.
2. **Missing operational facts were presented as values.** The live overview
   has no “Awaiting approvals” metric. The UI supplied `0`, and absent SLA data
   supplied `< 4h`. Both now display `Not available`. The queue-age label is
   `Oldest visible item`, since it measures only the three loaded records.

The reproducing tests failed before the changes. The two new regressions and
the existing Admin suites passed 30 tests afterward. The changed Admin overview
golden was inspected before updating it; the review is recorded in
`../release/mobile-design/CONTINUATION_2026-09-04.md`.

These changes are now deployed. The production-configured Admin build completed and
both its manifest and hosting gates passed. Its `main.dart.js` SHA-256 is
`e241614f6cd25444a975e2f826aaba2ec6fed9590dbcec6ea4a3cee2723abc79`.
The build contains the corrected labels and expected Supabase project, with
the four checked Admin fixture markers absent. Independent post-deployment
readback confirms the live Admin serves this same bundle.

## Data origin and remaining gaps

- **Stored test records remain in production.** One group has a test name and
  three receipt events have test/probe references. They are real stored rows,
  not fabricated UI fixtures. They remain untouched because deleting or
  reclassifying financial evidence requires a specific reviewed action.
- **Migration gap closed by the authorized deployment.** The initial audit
  found 122 local migrations and 121 remote versions. Migration
  `20260903201326_geographic_member_profile_gates.sql` is now applied, and both
  histories match at 122. Its profile-readiness helper exists live. The isolated
  rollback UAT passed 29 checks before deployment; existing function ACLs and
  owners were preserved and no new advisor findings appeared.
- **Runtime configuration still has bundled fallbacks.** The mobile providers
  load brand/support, legal documents and collection catalogs from Supabase but
  silently return local defaults when fetching fails; JSON parsing also has
  per-field defaults. Four compared brand/URL values match production, but the
  regulatory footer differs. The live response contains two support channels.
  This is configuration/content fallback, not a discovered fake balance or
  payment account. It can still show stale information during an outage, so a
  literal “no hardcoded data anywhere” claim would be false. Replacing these
  fallbacks needs an explicit loading/offline/content-unavailable design; this
  audit does not silently change legal wording or remove offline behavior.
- **Production repositories are connected to Supabase.** The Admin evidence
  provider is behind `ADMIN_PWA_EVIDENCE_MODE`, disabled by default and not
  enabled by the production build wrapper. The mobile repository's normal
  constructor starts empty and disallows fixture writes. Its bank-destination
  fixture fallback is restricted to explicit fixture repositories.
- **Realtime wiring exists, but delivery was not mutation-tested.** Both clients
  consume `public.app_realtime_events`; live publication/trigger definitions and
  a recent stored event were verified. This establishes configured refresh
  plumbing, not end-to-end delivery of a new live write. No synthetic payment,
  member, group or realtime event was created for the audit.

The initial audit's live Admin JavaScript hash was
`7ef5afc0decf12488a0523bd806e752323c4f02bec58689151522b827c8b3be3`
(3,464,538 bytes). It references the expected project; the six checked evidence
and test markers are absent. This is a targeted fixture check, not proof that
every constant or string in the bundle is backend-controlled.

## Evidence and handoff

Private read-only evidence is retained under
`.cache/admin-data-audit-20260904/`: RPC definitions, schema/migration/trigger
inventory, aggregate data checks, configuration comparison, deployed-bundle
fingerprint, failing/passing regressions and the rolled-back migration UAT.
Raw profile/contact/SMS contents are not reproduced in this report.

The initial audit performed no production writes. The subsequent owner-authorized
Admin and Supabase deployment is complete and independently verified in the linked
report. Configuration fallbacks and stored test records remain open; the mobile
release remains blocked. No payment, record deletion, Git publication or store
upload was performed.

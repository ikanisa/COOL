# BuriMunsi staff-testing readiness

## Current checkpoint — production005, 13 November 2026

**Production005 is live and real SMS-to-ledger acceptance passed.** The existing
Collect backend is OPEN at epoch **43**, with **53 unchanged migrations**, source
`62409fdd78973d44089565f4a61e7e4c5dd01caffbab0d7304ed3b3fa052b1f8`.
The single-file fix accepts valid native posted rows; the APK, Admin frontend,
Auth profile, keys, providers and canonical writer are unchanged. No service was added.

The signed **0.22.0-collect.9 / v31** APK is installed on the Pixel 4a; its
SHA-256 is `153f48746b62bf35bb89b68b91abf27f573fda7cc8dbfbeea2d09c270dd5aa9e`.
[Download the verified APK](https://drive.google.com/file/d/1cVHIyhTj3nb3mKpukZJBepmuFQTeJKpu/view?usp=drivesdk).
Final005 physical checks passed: records refresh recovered, the real member balance
matched nine source receipts, two Sync requests completed, restart retained login,
SMS access was Granted, capture was Listening and installed bytes matched.
Earlier package absence was unexplained; the verified reinstall and current recovery
are established, rather than uninterrupted installation. Both-role/session and
permission checks on this unchanged APK remain separately scoped evidence.

Live data comprises **32 observations/transactions, 29 financial facts (18 incoming /
11 outgoing), three notices, one active member, nine payments and nine canonical
contributions**. Shared Owner Admin confirmed the member and credits; unchanged Admin
checks are reused. The nine canonical identities and complete financial row
fingerprints stayed unchanged after the final Sync requests. Automatic parsing, unique group-scoped member matching and the
existing ledger writer require no manual SMS verification, provider confirmation,
pairing or code-in-body gate. Member registration uses the full known number.

Fresh fenced backup and actual restore compared **39 business relations, 41 stored
objects and seven preserved UNKNOWN obligations**; owned restore resources were removed.
This is not a claim of complete disaster recovery or settlement of those obligations.
**Remaining live acceptance:** witness a real new SMS during an offline interval and
confirm catch-up exactly once after reconnect. Offline cold-start navigation remains
guarded; reconnect retained login without another PIN. Image/PDF/XLSX imports are
unavailable; synthetic CSV preview does not establish real batch-registration UAT.

See [staff instructions](staff-testing-pack.md), [shared Collect Admin](https://platform-admin.collect.ikanisa.com/),
[final QA/UAT](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-005/QA-UAT.md>),
[Pixel final checks](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-005/pixel-real-member-final-uat.json>),
[real financial/repeat-Sync evidence](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-005/real-member-financial-uat.json>) and
[independent live/restore readback](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-005/live-independent-readback.json>).

## Historical checkpoints — superseded

Production005 supersedes the earlier native posted-row restriction. The production004
zero-member snapshot below predates the real enrollment and nine automatic credits.
Earlier provider/manual-verification/pairing assumptions remain historical evidence.

<details>
<summary>Previous production004 checkpoint and preserved earlier history</summary>

## Current checkpoint — production004, 13 November 2026

**Deployed and installed; software/device QA passed with live financial limits.**
The existing Collect backend is OPEN at epoch **41**, source
`623d635292c34008bf85fe473c2e2e44dbade13a833e502a9ce0c4f3559c94ab`, with **53 unchanged migrations**.
Production004 contains one suggestions-scope correction on production003. The
signed APK, Auth profile, keys, providers and existing Cloudflare Admin frontend
are unchanged; no service or frontend publication was added.

BuriMunsi **0.22.0-collect.9 / v31**, package `rw.ikanisa.burimunsi.gateway`, is
installed on the physical Pixel 4a, checksum
`153f48746b62bf35bb89b68b91abf27f573fda7cc8dbfbeea2d09c270dd5aa9e`. The [Drive APK](https://drive.google.com/file/d/1cVHIyhTj3nb3mKpukZJBepmuFQTeJKpu/view?usp=drivesdk)
was downloaded and byte-verified against the installed artifact. The phone is
left on Home, administrator signed in, SMS access Granted and capture Listening.

[Final004 device QA](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-004/pixel-production004-final-qa.json>)
passed its ten changed-path checks, including **four visible masked suggestions
from 17 eligible receipts**, all three Add Member entry options, saved login,
permission/capture, final Sync and installed-byte identity. The separate
[eight role/session checks](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-002/pixel-final-role-uat.json>)
and [production003 permission/detail/offline-login checks](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-003/pixel-production003-final-qa.json>)
are reused because the APK and authentication flow are unchanged; these overlapping
cases are not summed as unique tests.

[Independent final004 readback](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-004/live-independent-readback.json>)
confirmed **32 observations, 32 transactions and 32 completed jobs**; **29 numeric
RWF facts (18 incoming / 11 outgoing)**; all 18 incoming wallet balances; three
non-financial notices; zero unknown financial sources; and zero duplicate scoped
source keys after device repeat Sync. It preserves the original source/output
hash chain for the corrected principal. **Scoped business members, payments and
ledger entries remain zero.** Recorded-source and controlled writer-test results
are distinct from a real customer credit.

The automatic flow uses Android SMS access, original source facts and a unique
collection-scoped name/last-three-digit member match to reach the existing
canonical payment/ledger writer. No manual verification, independent provider
confirmation, phone pairing or MoMo-code-in-body prerequisite is imposed. Staff
SMS access remains unavailable. Add Member includes the approved Smart Member
Onboarding screens and requires a full known member number for registration.

The [deployment/restore receipt](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-004/live-journal/deployment-result.json>)
records the existing startup/scheduler binding and fresh bounded logical
backup/restore comparison of **39 business relations, 32 stored files and seven
preserved UNKNOWN obligations**, with owned resources removed. A full disaster
recovery, recovered credentials or settled obligations is not claimed.

Remaining live acceptance consists of:

1. Enroll a real payer and demonstrate one eligible receipt matching its member
   and posting exactly once to canonical payment/ledger, with member balance
   and shared Admin confirmation.
2. Witness a real new SMS arriving while phone internet is unavailable, then
   confirm capture, recording and eligible credit catch up once after reconnect.
   No real new SMS arrived during the tested offline interval.

Known limits: cold-start offline navigation is guarded. Restoring the original
network recovered saved login without PIN and capture Listening; it does not
prove new-SMS catch-up. Image/PDF/XLSX imports are unavailable. Earlier synthetic
CSV preview is not real batch-registration UAT. All seven historical obligations
remain explicitly UNKNOWN and preserved.

See the [final QA/UAT report](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-004/QA-UAT.md>),
[current staff testing pack](staff-testing-pack.md),
[Drive byte verification](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-003/drive-apk-byte-readback.json>)
and [Collect Admin](https://platform-admin.collect.ikanisa.com/).

## Historical checkpoints — superseded

Production004 supersedes the [production003 deployment](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-003/live-journal/deployment-result.json>)
and [readback](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-003/live-independent-readback.json>)
for the suggestions predicate. The retained notes below describe their own
builds/counts. Earlier provider/receiver proof, code `41258` in-body and manual
verification/pairing assumptions are historical, not current gates. The later
Smart Member Onboarding approval includes its additional screens.

<details>
<summary>Earlier readiness checkpoints and original evidence links</summary>


## Historical production001/device check: 13 November

Version 31 is now installed on the Pixel. A later package check found it absent
for an unknown reason; the same verified APK was reinstalled. The administrator
signed in, Android SMS access was granted, capture reported listening and the
session returned after force-stop and reopening. Earlier, it was installed over version 30 and passed 45 staff
and 60 receiver isolated device tests. Its saved administrator session and SMS
permissions survived that earlier update, and a foreground reconnect after a verified
network interruption restored Home without another PIN. SMS catch-up and the
native-to-ledger path are not established by that test.
The shared backend is now `production-20261113-001`, OPEN at epoch 35, with
the same qualified member-only 033 source. The exposed SMS-hook credential has
been rotated, shared operation locking is live, and a fresh restore matched 39
relations and 32 Storage objects while preserving six unresolved obligations.
A natural processing tick passed. Native phone/PIN login and Android SMS
capture do not require an outgoing OTP provider; the unnecessary Twilio setup
was stopped. The source permits authorized
member enrollment without managed-gateway pairing, but does not enable
financial posting. After deployment, the installed app reopened the saved
session, displayed 32 SMS observations and previewed a synthetic CSV row.
No member was registered during this check. Six recovery obligations remain
unresolved and preserved.

A subsequent authenticated live Admin spot check passed Owner sign-in, BuriMunsi
group search, and the MoMo table displaying 32 records with none credited.
Closing and reopening the Admin tab retained the Owner session; a full browser
process restart and full Admin regression were not tested. See the [Admin UAT
record](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/android-v31-session-qualification-001/admin-live-uat-final.json>).

The Pixel 4a was connected and a later Android package inventory initially found
no BuriMunsi gateway or staff package. The previously installed candidate and
its pending non-SMS action are historical observations; that inventory did not
establish whether the earlier local journal still exists. The signed version
29 testing candidate was installed and checked, followed by a signed version
30 update whose installed APK hash was verified. Both candidates passed 45
staff and 60 receiver isolated tests on the Pixel. Both roles signed in on
version 29 against the live backend and their sessions survived a restart; the
staff session survived the version 30 update.
The administrator initially declined SMS access while historical replay was
unsafe. After candidate 031 was deployed, access was granted and the gateway
reported capture enabled and listening. A sync request left all 32 original
observation and transaction rows unchanged, with no duplicate source keys.
The old inbox is held for reconciliation. Suggested from MoMo now opens and
shows no eligible suggestions. Following the history-only 032 deployment, the
SMS page displayed all 32 retained observations on the new installation and
one message opened without a verification prompt. A synthetic CSV opened in
the live member import preview; no member was registered. Candidate 032 was
subsequently replaced by 033; a fresh new-message-to-ledger flow remains unproven.
On version 30, a connection interruption left the saved session pending until
the app was backgrounded and reopened; version 31 corrects the observed
foreground reconnect issue as described above. The live Help contact was
unavailable.
Native automatic parsing has completed for 32 retained observations, but none
is linked to a canonical payment. The available historical incoming messages
lack a complete payer identifier and the managed receiving evidence needed by
the existing posting path. Image, PDF and XLSX import remain unavailable.
A synthetic OpenAI request using the protected configured key and model returned
HTTP 200 and completed; this is provider availability only, not evidence that
document import or SMS-to-ledger processing works end to end.

## Smart onboarding source work: 13 November

The owner has since approved the new Smart Member Onboarding screens inside
Add Member. The earlier historical instruction below against adding onboarding
screens is superseded. The local source now includes the new choices, scoped
suggestions, manual entry, CSV review and recoverable batch registration. The
version 30 APK and deployed 032 backend contained these changes; CSV preview
passed with a synthetic row, while live member creation and complete CSV
registration have not yet been verified end to end.
Image/PDF/XLSX extraction, full native SMS-to-ledger posting and cross-source
deduplication remain incomplete. Do not use the offline test APK as a staff
release or describe every onboarding path as verified. A fresh authenticated outcome
check on the then-installed Pixel gateway still returned pending for the earlier
non-SMS action; it did not resend or clear that action.

## Historical snapshot: 13 November 2026

The shared local backend `testing-candidate-028` and compatible Cloudflare
Collect Admin are deployed. Android candidate 017 was installed on the Pixel
4a at this earlier checkpoint; see the later device check above. The deployed Admin is
[platform-admin.collect.ikanisa.com](https://platform-admin.collect.ikanisa.com/).
The exact APK and installation guidance are in the
[staff testing pack](https://drive.google.com/file/d/1r6G5Ql0EAaE3K68TxSOWmbgjfmpjd_xs/view?usp=drivesdk).

At the observed checkpoint the gateway had captured 32 historical M-Money
messages and automatically recorded all 32 as distinct transaction records,
including the previously retrying non-financial notice. The displayed BuriMunsi scope identifies
where the messages were captured. None of these messages contained code
`41258`, so that scope does not establish the receiving account. No business
memberships or canonical ledger credits existed in the checked database.
The deployed Admin API now leaves the native receiver unestablished and blocks
legacy assignment/conflict actions for native records. Cross-source provider-
reference deduplication still needs a safe schema and reconciliation change.
These counts and deployed version are snapshots, not a claim about a later
retry or release.

Administrator and staff sign-in and session restoration have been checked on
the Pixel; staff logout also required a new sign-in. Administrator SMS access
was granted in Settings, and staff SMS access was unavailable. A repeat sync
did not add duplicates. A fenced backup was restored and matched 16 business
relations, and its 32 Storage files were checked; 31 transaction records present in the
snapshot also matched live records and their sources. See the
[UAT record](https://drive.google.com/file/d/12vy0yuVJbCEfM86Z2vrzSPKnpz_bbzph/view?usp=drivesdk) for the exact evidence boundaries.

The then-installed Pixel app reported an unresolved earlier non-SMS action.
Its last authenticated outcome check reported pending. The later device
inventory does not establish the fate of that local state. It is not an SMS
verification step.

**Remaining before staff financial testing:** finish the automatic native
transaction-to-shared-ledger path with a supported receiving-account and
member mapping; verify it using an appropriate real message and the shared
Admin; verify a new-message/offline catch-up and retry without duplicates;
resolve cross-source deduplication; and perform a rendered
comparison of all prototype screens and states. No manual SMS verification
step is part of the requested flow. Keep ambiguous receiving-account facts
unattributed rather than inventing a credit.

## Earlier checkpoint, retained for history

The sections below describe 11–12 November candidates and results. Their
versions, counts, pending work and readiness statements are superseded by the
13 November snapshot above.

Checkpoint: 11 November 2026. This is a working release checklist, not a
declaration that the MVP is deployed or ready for live transactions.

**12 November update:** The owner requires M-Money messages to be parsed and
recorded automatically in Transactions, without manual SMS verification.
The 014 APK is installed on the Pixel and ten real messages reached the
shared backend, but no transactions were created. Source changes for the
automatic flow are being integrated and are not yet deployed. See the live
[UAT record](live-uat-2026-11-11.md) for the latest confirmed results.

## Product and deployment

- BuriMunsi is a native Android app for authorized staff and administrators.
  It uses the existing local Collect Supabase, Collect Admin and shared ledger.
  Group, receiving-account, provider and user details are runtime data.
- Preserve the eight screens and existing panels in the supplied
  [v1.1.0 prototype](prototype-reference/index.html), including the requested
  SMS-permission control in Settings. Do not require a separate manual pairing
  or add onboarding screens. The three newer logos supplied on 11 November
  replace the previously supplied artwork.
- Keep users signed in across app or browser closure until explicit logout,
  subject to server-side access changes and recovery from an uncertain logout.
  The Admin browser cookie is renewed when the session is checked; browser
  cookie-lifetime limits or clearing site data can still require sign-in.

## Evidence at this checkpoint

- The deployed group search returned BuriMunsi, and the supplied admin and
  staff accounts signed in on the Pixel using the previously deployed build.
  A later read-only database check found its sponsored, public-approved group
  and a scoped receiving account with the supplied MoMo code. The receiving
  profile is unverified and empty, and the scope is disabled. This does not
  establish the new SMS flow.
- The 012 Android source, including the SMS list changes, passed isolated
  physical Pixel tests for both staff and SMS-capable variants (42 staff and
  57 receiver tests). A configured private v28 APK has been signed with the
  existing app identity and its checksum verified. These are synthetic device
  checks; the candidate has not been live-qualified or distributed. The
  earlier 011 candidate and its evidence remain preserved.
- The subsequent 013 source adds a bounded, encrypted local PDU/inbox
  correlation journal. Its capture and scan checks passed on synthetic data,
  and the configured v28 APK passed 42 staff and 57 receiver tests on the
  Pixel. It is installed on the Pixel 4a with the original sign-in controls
  visible; the installed APK matches SHA-256
  `a14f10319dc8288d3b5cf8d05453e860b1cd6a7fc627ee41c92be40b08a6eadc`.
  Administrator login survived a force-stop and restart, and SMS access was
  granted. The app was subsequently removed during phone checks and the 013
  APK was reinstalled. This local witness is bounded and cannot establish a receiving account or authorize
  posting; ordinary inbox catch-up continues if it is unavailable or full.
- A separate no-network, count-only native diagnostic found the candidate
  sender on the Pixel and 10 messages matching the candidate intake markers.
  The strict local full-receipt grammar matched none. The server's provisional
  display parser has passed synthetic suffix and ambiguity checks, but its
  output for the phone's real messages is not yet established. The diagnostic
  did not retain or transmit SMS bodies. A subsequent count-only check found
  that none of those 10 candidate messages contains the supplied MoMo code as
  a standalone number; the check does not establish their receiving account.
- The observation routes, protected storage and their forward database
  migrations passed isolated synthetic PostgreSQL and Storage checks and are
  deployed in the live backend. A separate dynamic detection profile is enabled
  for the existing BuriMunsi scope without marking the receiving
  account approved. An observation is not yet a canonical receipt or a
  posted ledger entry.
- The revised Home and Payments queries passed isolated PostgreSQL checks for
  member/group scope, search, receipt-day boundaries, ledger-backed credit,
  corrections and reversals. They are included in the deployed backend.
- The configured OpenAI key and model returned a completed response for an
  invented MoMo example using the production extraction prompt and schema on
  11 November. The existing canonical validator accepted that response under
  an invented approved profile. No real SMS or payment data was sent and no
  ledger was written. This does not prove extraction of a real message; the
  running processing job remains paused.
- The self-hosted configuration now accepts and privately projects the new
  observation, staff-edit and protected-owner switches. They default off,
  older provider-settings files remain compatible, and focused configuration
  and edge-worker projection tests passed. The matching switches are deployed.
- A new local backend release candidate was prepared from the frozen source
  and all 48 registered migrations, retaining the existing private runtime
  configuration. The release is `testing-candidate-020`; its source digest is
  `81e3436bd73dcd5fd07252e63c54c9476ced9925e3e59e39d7fc94494590d6a2`.
  The compatible Owner and observation switches are enabled; financial
  processing remains paused. A fresh, fenced database and Storage backup was
  taken before the 12 pending migrations, restored and compared over 241
  relations. Retained database passwords were separately rehydrated and
  authenticated on a restored clone. All 48 migrations and public API health
  were verified after deployment.
- The matching Admin Worker was uploaded to Cloudflare as version
  `a8ab4a89-0d43-4499-b3f7-ae20ae518108` and receives all traffic. Four
  hosted assets match the qualified build; the signed-out session endpoint
  returned its expected response. At that checkpoint, authenticated browser UAT
  remained pending; see the later spot check above.
- Focused Admin saved-login tests include normal reopening and an unconfirmed
  logout across browser controller recreation. A protected-owner client and
  server test passed against synthetic authentication and an isolated
  database. An Admin artifact bound to the 48-migration lock passed local
  hosting, build-configuration and credential checks; its client matches the
  version that passed 226 focused tests. The final rebuild includes the later
  self-hosted configuration inputs and matches the prepared backend's source
  inventory. The browser restart against an authenticated live session has not
  been verified.
- Native-login checks reproduced separate short clock differences between the
  database and edge runtime and within the database. Bounded, PIN-session-only
  corrections, persisted expiry and staff phone-edit changes are registered in
  the source. The exact 48 registered migrations passed an isolated PostgreSQL
  chain, clock and authorization contracts, competing-edit and revocation
  races, and native HTTP/database tests. These changes are live. The
  qualification result's summary says 45, but its 48 individual migration
  checks and recorded intent identify the tested chain.
- A real logical database snapshot was restored and compared across 36
  migrations and 241 relation digests. It excludes database role password
  hashes and Storage objects. Its retained members passed a later integrity
  recheck. A fresh fenced backup was also restored and compared during the
  release; Storage had no object rows or files at that point.
- Source-level route and asset checks do not establish rendered visual parity
  with every prototype screen. The browser review blocked the local prototype
  preview, so a rendered comparison is still outstanding. A later Android
  source change adds local and authorized remote SMS previews and local search
  to the existing screen. It uses the existing audited disclosure APIs with an
  explicitly automatic reason, applies a bounded scan and reports incomplete
  results. It is limited to streams accessible to the current account and
  phone: observation history is installation-scoped and canonical SMS history
  currently requires the earlier receiver binding. The 012 build and isolated
  Pixel checks passed; live verification remains pending. Some activity and
  history details also remain to be matched.

## Historical remaining acceptance work (superseded)

1. Finish and qualify the source changes for automatic SMS access, reliable
   pause/resume and saved sessions, including explicit logout and permission
   changes. Verify staff and admin capabilities against the prototype. A
   locally admitted upload can still finish after pause; the exact request is
   retained for reconciliation. Immediate remote cutoff and legacy receiver
   replacement behavior need live qualification. The new local Queued view
   covers observation entries, not the separate older paired-receiver queue.
   An uncertain Storage upload remains queued for an exact retry; the original
   write cannot currently be settled. A source change can identify a verified
   unresolved request and let a bounded number of later observations proceed.
   It passed isolated PostgreSQL and real-Storage tests and matching Android
   HTTP and coordinator checks. It has not been deployed or live-qualified.
2. Complete the path from captured SMS to extraction, matching the correct
   runtime receiving account and group, canonical transaction and shared
   ledger. A phone, SIM or message that does not identify the recipient is not
   by itself proof of the receiving account; unresolved messages must not be
   posted as confirmed payments. The empty live provider profile also prevents
   financial posting; the separate detection profile does not change that.
3. Complete dynamic Owner controls and full browser-restart session testing.
   The later live spot check covered Owner sign-in, search, MoMo listing and
   tab closure. Retention and uncertain Storage outcomes remain fail-closed.
4. Complete staff-role live testing on the installed version 31 APK and issue
   a release build only after the remaining acceptance work is qualified.
5. On the Pixel, verify the real native permission and sync flow, a real MoMo
   message through extraction and the correct shared ledger/Admin record,
   duplicate prevention, offline catch-up, role boundaries and logout/reopen.
   Test uncertain outcomes without submitting a transaction twice.
6. Complete a rendered comparison with the supplied prototype, including
   both roles, all eight routes, existing panels and updated logo dimensions.
   Complete the [staff testing pack](staff-testing-pack.md) with the qualified
   APK, deployment identities, results and accurately stated limitations.

Do not treat synthetic data, an isolated APK build, a reachable endpoint or a
historical restore as proof that the complete live transaction flow works.

</details>

</details>

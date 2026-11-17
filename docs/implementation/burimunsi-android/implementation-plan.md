# BuriMunsi implementation plan

## Current checkpoint — v36 and production-20261115-001, 15 November 2026

**Ready with limits for controlled internal staff testing.** Both signed v36
APKs (`0.22.0-collect.14`) are installed on the Pixel 4a. Native source fingerprint
`60d0b3447e514e209721d7203a0f315586fb8704abc8b262c58d490113d8edb9`
binds 329 files. The local-correlation fix skips unrelated inbox rows before
protected-state reads while retaining the existing ownership and persistence
guards. Pipeline, adapter and PDU contracts passed; the same 138 offline
contracts passed on the physical Android 13 handset and Android 16 emulators
with separate 4 KB and 16 KB page configurations.

The existing shared Collect backend is **OPEN 49 / 61 migrations**, source
`8f43be86d1e99eab4453c4a2ba65851d545f708ac5b71ee18d82cd16d338fad2`.
The original deployment operation completed after actual custody/recovery and
logical backup/restore checks; its 13 UNKNOWN control-plane outcomes remain
preserved and unsettled. Do not replay the migration or recovery operation.
The existing hosted Admin passed twelve post-61 read-only compatibility checks.

Fresh v36 physical checks passed for Excel/PDF and full-ledger CSV saves,
independent file readback, real picker cancellation, actual Staff role/login,
saved access after cold process relaunch, and autonomous Sync recovery following
41.33 seconds without a validated network. Captured global controls matched
preflight afterwards; per-SIM preferences were not individually baselined.
Both installed APK hashes match the release artifacts. The phone was left on
Android Home with saved sessions and the gateway foreground service intact.
Only exact owned UAT downloads were removed after protected local preservation.

[Private staff release: APKs, guide, QA summary, manifest and checksums](https://drive.google.com/drive/folders/1Pn43Yv8ICuteFHM70oxL-Ys832r2Ifws).
Detailed operator evidence and the critical report are in
`/Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-15/remaining-implementation-001/`.
R09 sustainable capacity/acknowledged alerts and independent host/key recovery,
R10 actual Owner MFA and credential retirement, R11 authoritative retention and
custody, and R12 new-carrier/reboot/handset/independent-recipient acceptance
remain open. New carrier arrival or a fresh v36 reboot was not established by
this pass. Earlier real-SMS and reboot witnesses remain explicitly versioned.

## Historical checkpoint — production005, 13 November 2026

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

**Software and device checks passed with live financial limits.** The existing
Collect backend is deployed as **production-20261113-004**, OPEN at epoch **41**,
source `623d635292c34008bf85fe473c2e2e44dbade13a833e502a9ce0c4f3559c94ab`, with the same
**53 migrations**. Production004 changes one native-only suggestions predicate
from production003; its currency-qualified principal correction is retained.
The APK, Admin frontend, Auth profile, keys and providers are unchanged. Existing
startup and scheduler entrypoints are bound to this source; no service was added.

The final signed **0.22.0-collect.9 / v31** APK is installed on the Pixel 4a,
checksum `153f48746b62bf35bb89b68b91abf27f573fda7cc8dbfbeea2d09c270dd5aa9e`;
its frozen native source is `32e2d9b7ac88cfcdb37dd294f964b021b9c1e872d827332292c2480b4782b6e7`.
The Drive copy was downloaded and byte-verified. Final state is Home,
administrator signed in, SMS permission Granted and capture Listening.

Final004 physical checks passed: four masked MoMo suggestions from 17 eligible
receipts, all three Add Member entry options, saved administrator login,
permissions/capture, final Sync and installed-byte identity. Both-role login,
logout and saved sessions were checked separately on this unchanged APK; the
production003 permission, incoming/outgoing detail, repeated Sync and offline
credential-recovery checks are reused with that explicit one-module compatibility
scope. No new Admin frontend publication or blanket live financial UAT is claimed.

Independent final readback found **32 observations / 32 transactions / 32 completed
jobs**, **29 source-bound numeric RWF facts (18 incoming / 11 outgoing)** and
**three non-financial notices**. All 18 incoming receipts have wallet balances.
There are no unknown financial sources or duplicate scoped source keys. The
corrected outgoing principal retains its original source/output hash chain.
There are **zero scoped business members, payments and ledger entries**.

The deployed flow is permitted original SMS → automatic parsing/transaction
recording → collection-scoped normalised name/last-three-digit match → existing
canonical payment/ledger writer for an eligible unique member. Account metadata
and member numbers remain runtime records. No manual SMS verification,
independent provider confirmation, manual pairing or MoMo-code-in-body condition
is a prerequisite. Smart Member Onboarding and its approved additional screens
remain inside Add Member; registration uses the full known number.

The transition performed a fresh bounded logical backup/restore comparison of
**39 business relations**, **32 stored files** and all **seven unresolved UNKNOWN
obligations**, with owned temporary resources removed. Full disaster recovery,
credential recovery and settlement of those obligations are not inferred.

Remaining live acceptance:

1. Enroll an actual payer and demonstrate an eligible real receipt → unique
   member → canonical payment/ledger → shared Admin confirmation; repeat Sync
   and confirm exactly one credit. Zero members/credits cannot prove this.
2. Demonstrate catch-up of a **real new SMS** received while phone internet is
   unavailable. No such message arrived during the observed offline interval.

Known limits: offline cold-start navigation remains guarded; reconnect restored
saved login without PIN and capture Listening. This differs from receipt catch-up.
Image/PDF/XLSX imports are unavailable; synthetic CSV preview does not establish
real batch-registration UAT. Use the [staff testing pack](staff-testing-pack.md).

Evidence:

- [Staff APK on Drive](https://drive.google.com/file/d/1cVHIyhTj3nb3mKpukZJBepmuFQTeJKpu/view?usp=drivesdk) and [Drive byte readback](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-003/drive-apk-byte-readback.json>)
- [Shared Collect Admin](https://platform-admin.collect.ikanisa.com/)
- [Final QA/UAT report](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-004/QA-UAT.md>)
- [Final004 physical checks](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-004/pixel-production004-final-qa.json>)
- [Final004 independent backend/source-chain readback](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-004/live-independent-readback.json>)
- [Production004 deployment/restore](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-004/live-journal/deployment-result.json>) and [scope qualification](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-004/qualification.json>)
- [Final installation](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-002/pixel-final-apk-install.json>), [separate eight role/session checks](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-002/pixel-final-role-uat.json>) and [reused production003 device checks](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-003/pixel-production003-final-qa.json>)

## Historical checkpoints — superseded

Production004 supersedes the [production003 deployment](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-003/live-journal/deployment-result.json>)
and [readback](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-003/live-independent-readback.json>)
only for the suggestions predicate. Earlier evidence below is retained. Old
provider-confirmation, manual verification/pairing, code `41258` in-body and held
native-ledger assumptions do not define current acceptance.

<details>
<summary>Earlier implementation records and evidence links</summary>


**Historical Android check, 13 November:** Version 31 is installed on the Pixel.
It was found absent at a later check for an unknown reason and reinstalled from
the verified APK. The administrator signed in, SMS permissions were granted,
capture reported listening and the session returned after force-stop and reopen.
Its isolated staff and receiver suites passed 45/45 and 60/60 respectively;
its installed hash matched the same-key signed candidate. The saved session and
SMS permission survived the update, and a verified connection interruption
recovered the session automatically after reconnection without a new PIN.
This does not establish SMS offline catch-up or financial posting.

After the production switch, both supplied roles signed in on the installed
version 31 APK. The staff session survived force-stop/reopen, Settings enforced
the staff SMS-access boundary, and manual logout worked. The administrator was
restored and capture reported Listening with SMS permission Granted. One
post-cutover records reload needed Refresh and recovered without another PIN.
See the [production role UAT](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/production-activation-001/pixel-v31-production-roles-uat.json>).

**Historical backend check, 13 November:** `production-20261113-001` is live at
epoch 35, using the qualified 033 source. The exposed SMS-hook key was rotated,
the former key is absent from the live Edge environment, and startup/deployment
controls now share an operation lock. The fresh fenced restore matched 39
relations and 32 Storage files, preserved all six unresolved obligations, and
removed its owned temporary restore resources. A natural scheduled tick passed.
The [live readback](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/production-activation-001/live-final-readonly.json>)
records these results. The member-only change separates authorized enrollment from
managed-gateway pairing while keeping financial posting gated. Its transition
included a fresh fenced backup and independent restore comparison of 39
relations and 32 Storage files. Six uncertain recovery obligations are retained
without replay or settlement. The installed v31 app reopened the saved session,
showed the 32 SMS observations and previewed one synthetic CSV row; no live
member was registered during that check.
A later authenticated Admin spot check found BuriMunsi through group search,
showed 32 recorded MoMo transactions with none credited, and retained the Owner
session after its tab was closed and reopened. Full browser restart and complete
Admin regression remain untested.
Separately, the captured database root key passed a synthetic Vault
encrypt/decrypt test in an isolated restore, and the `collect_edge` login was
reconstructed and checked with SCRAM. The restored Vault contained no existing
secrets, and the backup omits role password hashes; this is not proof of
restoring every existing ciphertext or service credential.

**Native ledger source work, 13 November:** The repository now projects a
native SMS origin without fabricating a gateway binding and preserves its
historical or live source mode. It also contains staged native financial work,
owner grant, custody, retention inspection and immutable lease-history code
with six registered migrations. Synthetic PostgreSQL and custody tests passed,
including expiry, revocation, duplicate-claim races and lease-history rollback.
The production scheduler entry point is held and the live backend remains at 52
migrations. No provider-confirmation adapter, qualified native financial writer
or real ledger credit exists yet. Existing leases before the history migration
are not backfilled.
The repository also contains a tested inspection-only classification for the
two existing Storage Iceberg tables; it keeps their subject count unknown and
erasure blocked. That migration is not live, and the positive-erasure runtime
test remains blocked by unresolved subject/obligation mapping.
See the [combined qualification handoff](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-financial-combined-staging-001/HANDOFF.md>).

**HTTP admission source work, 13 November:** The repository includes a
tested, undeployed guard for confirmed cancellations and late pre-work
registration acknowledgements. A pinned Edge supervisor test did not propagate
the simulated client disconnect to the worker, so this does not establish a
general fix for stranded admissions or resolve the six retained obligations.
See the [qualification report](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/http-fence-lifecycle-qualification-001/QUALIFICATION.md>).

**Admin email configuration, 13 November:** The running Auth service currently
allows the Admin origin and uses a 30-minute email code. Repository release
generation now also preserves the exact public, Admin and Google callback
redirects and the configured code lifetime; this source change is not yet
deployed. A synthetic real-Auth test confirmed the Admin email link goes to
the Admin login and that the code works at 29 minutes but expires at 31. The
link does not itself complete the browser-bound Admin sign-in challenge.

**SMS authentication, 13 November:** The exposed hook credential is now rotated
in the live production release and retained Auth application configuration.
Lock-aware controls are installed; the source and recovery tests were independently
reviewed before the successful guarded transition. Historical releases remain as
protected rollback evidence. The separate OpenAI key was not changed. See the
[live rotation handoff](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/sms-hook-rotation-preparation-001/same-source-live-guard-007/ROTATION-LIVE-HANDOFF-007.md>).
BuriMunsi uses the original native phone/PIN sign-in and Android SMS inbox
capture; Collect Admin uses email sign-in. These flows do not require Twilio
or outgoing SMS authentication. The exploratory Twilio setup was stopped after
the owner's clarification; no provider service or application delivery was
activated. The unused Supabase SMS-OTP and custom delivery hook remain off.

**Earlier release check, 13 November:** History-only candidate 032 of the shared
backend was live after a fenced backup and independent restore check. A subsequent
Pixel package inventory found no BuriMunsi installation, so the previously
observed pending non-SMS action cannot be treated as resolved or as still
present on the device. Signed Android testing candidates 29 and 30 were then
installed in sequence, and each passed 45 staff and 60 receiver isolated tests
on the Pixel. Both live role logins and session restoration passed on version
29; the staff session survived the version 30 update. Suggested members now
opens with no eligible results against 031. The administrator granted SMS
permission and the gateway reported listening; a sync request left the old
32 observation and transaction rows unchanged. Historical inbox items are
held to avoid replay. The 032 history fix made all 32 retained observations
visible on the new installation; an original message opened without a
verification prompt. The
retained historical SMS observations have been parsed, but are not linked to
canonical payments and do not provide all evidence required by the existing
posting path.

**13 November smart onboarding direction:** The owner supplied the Smart Member
Onboarding v1.0.0 package and asked for its features in the existing Add Member
flow, including the new onboarding screens. Preserve the existing app routes,
shared Collect member records, roles and session controls. The original package
is retained unchanged in [source addenda](source-addenda/BuriMunsi_Smart_Member_Onboarding_v1.0.0/README.md);
its manifest matches and its 12 isolated Node tests pass, but it is not itself
a compiled or deployed implementation.

**Source integration checkpoint, 13 November:** The existing Add Member panel now
contains the supplied onboarding choices and screens, scoped MoMo suggestions,
manual entry, CSV preview, row correction and a single idempotent batch command.
The query keeps full payer numbers inside PostgreSQL, distinguishes payers with
the same suffix and binds a chosen suggestion to the full submitted number.
Formatted variants of an existing member number are detected. Kinyarwanda UI
copy has been added and still needs fluent review. The installed v30 candidate
and the then-deployed 032 backend contained these changes; a synthetic CSV row appeared
in the live preview, but member creation and complete CSV registration remain
unverified.

The staff Android source compiled, 130 focused backend tests passed (including
read-only synthetic PostgreSQL cases), and controller/repository checks covered
file-picker resume, row correction and uncertain batch recovery. A separately
named offline test-only APK was installed on the Pixel 4a; its staff UI and
package-isolation suite passed 45/45 tests with synthetic records. The new
onboarding options were also captured on the device. These checks do not prove
live enrollment, OCR, real-message posting, or a release APK.
The [synthetic Pixel options capture](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/smart-onboarding-check-001/pixel-smart-options-002.png>)
and [45-test device log](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/smart-onboarding-check-001/pixel-staff-full-003.log>)
are retained separately from the live application.
Member identity and consent checks in onboarding are separate from the owner's
instruction that SMS transactions are automatically processed without manual
SMS verification. Image/PDF/XLSX import still needs the qualified document
decoder and OCR connection; the native SMS-to-shared-ledger path, cross-source
deduplication, complete live UAT and production release remain outstanding.


**12 November product direction:** The owner requires automatic processing of
M-Money transaction messages and their display in the existing Transactions
page. Manual SMS verification is not part of that workflow. Capture must use
runtime sender configuration, cover both incoming and outgoing transactions,
and retain the original prototype's screens. Parser, transaction schema,
direction-aware totals and both shared Admin and native read paths must change
together; the previous observation-only implementation is not the target.
Unknown or absent source fields must remain absent, and a non-transactional
security message must not become a fabricated financial transaction.

**11 November update:** This page records a historical checkpoint. The current
testing objective, evidence and remaining acceptance work are in
[MVP testing readiness](mvp-testing-readiness-2026-11-11.md). In particular,
the user's later instructions supersede this page's references to the older
icon and manual receiving-device pairing.

Checkpoint: 10 November 2026, backend006 deployed OPEN at epoch7; corrected native snapshot009/build029 PASS, with the full API36 65-test run still running. Scope is native Kotlin Android for Collect staff/admins and the authorized receiving-phone flavor, using the existing retained LOCAL Supabase, shared Collect Admin and canonical ledger. The original 65 task contracts and 36-action engineering register remain unchanged under `drive-handover/registers/`; inherited acceptance fields and older reports are historical evidence, not current completion claims.

The owner requires the completed original prototype: eight routes (Login, Home, Payments, Payment, Members, Member, SMS, Settings) and fifteen panels (raw, allocate, add-member, member-details, staff-list, staff-edit, confirm-remove, gateway, replace-device, profile, change-passcode, audit, history-payment, help, filters). The [sanitized reference](prototype-reference/index.html), [screen map](prototype-reference/screen-map.json) and [UI contract](prototype-reference/ui-contract.json) preserve product and workflow evidence; Revolut Design remains the sole visual design authority. Two actual SMS examples in the HTML were replaced with synthetic values. The preserved private original has SHA-256 `644c0ca7dfa38ee184a80be7d0e0d753503fa40dac00ae1814a9359b5e9fba4d`; the sanitized HTML has SHA-256 `3f2d159b139f1e39adb96bfafe739d044bb9ebfd836cc9c15d73d009b0744a97`.

Fresh ordinary-phone installation must reach the original phone-number/four-digit-passcode login. Native phone-setup codes, installation-details onboarding and email-code prelogin screens are superseded and removed from the corrected active UI. Receiver pairing, business-SIM confirmation, sync and replacement belong in the original signed-in Gateway panels. The supplied `Glossy BuriMunsi Purple App Icon.png` is the approved source asset for the app icon and original logo placements, SHA256 `75b9394d8b99c7895af3893af264e098ded960f5d2fba194baa70682d9443f66`. Existing web Owner email authentication remains valid and separate from native entry.

| Area | Observed evidence at this checkpoint | Remaining acceptance |
| --- | --- | --- |
| Corrected native UI and bootstrap | Snapshot `source-testing-candidate-009` contains 207 pinned inputs, native fingerprint `144ad260b162b5ab6c77f5228de5246a949be85441551c641e2d455bf194ca1e`. Build029 compiles and inspects eight APKs with PASS. All original routes/panels, phone/PIN entry, supplied logo and real repository/Gateway actions are written; the 27 UI source/resource checks, generator check and focused ViewModel checks pass. | Full Staff29/receiver36 instrumentation in `device-api36-016` is RUNNING; no 65-test PASS or completed rendered comparison is claimed. A production-configured/signed version24 candidate and corrected physical installation remain pending. |
| Native phone/PIN backend | Migration32, `20261110143000_burimunsi_native_phone_pin.sql`, SHA256 `bc2a6989b309258838966707548c588ff27bde6900c96d120b4d75e31c95d365`, is actually applied. Backend006 Edge readback, source upgrade at fenced epoch6 and release OPEN at epoch7 passed, with 32 migration-journal entries. Independent static review remains recorded at receipt SHA256 `16a8363e389d8727ae4bd54ff8c11874b1506ae3c8f2721f701209cdf9645f81`. Native authority uses actual scoped sessions and canonical commands; it creates no web email/MFA proof or alternate ledger. | Actual public `/session/login` rejects the unknown synthetic phone with HTTP401 `invalid_credentials`; native GET/PATCH negatives also return401. This proves denial and deployed route binding, not successful authorized staff login, native operational enrollment or financial posting. |
| Existing public testing services | Retained source006 is deployed OPEN at epoch7, SHA256 `d2fb289fb4812c21540753f8e9be6b9f126ba1f30802c791ab9fd40238ebe49b`. Post-transition Auth/API health and HTTP smoke passed with business/Auth/control counts unchanged and no native account, grant, session or ledger record created. The existing LOCAL database, Auth, keys, roles, shared Admin and canonical ledger are preserved. Genuine web Admin Owner mailbox OTP delivery and Owner workspace/session remain separately evidenced. | Verify a genuine authorized native phone/PIN session and server-selected collection against this deployed backend. Backend/negative-HTTP proof does not establish corrected native APK acceptance or the real-phone receipt-to-ledger pilot. |
| Historical signed Android candidate | Build025, API36 emulator013 (87/87), configured-release005 and signed-testing-candidate004 passed within their recorded scope. The v23 receiver was installed on the physical Pixel 4a with certificate/APK readback. | v23 contains the owner-rejected additional UI and is superseded for product acceptance. Preserve its APKs/receipts; qualify version24 (`0.22.0-collect.2`) as a new candidate rather than inheriting v23 acceptance. |
| Runtime/recovery | Manual recovery after the second Mac boot preserved the same volume, VM and fourteen service identities; that receipt records source005 before the subsequent006 transition. Startup-helper006 passed 40 fake-host checks and independent review; its warm LaunchAgent receipt records PID27661, parent1 and a ready event bound to source006. Prior source004 logical restore and encrypted 96-file custody remain retained evidence. | Actual automatic cold-login recovery remains UNPROVEN. Neither a fresh source006 full-VM restore nor a physical-phone receipt/recovery pilot is inferred from manual recovery, mock checks or warm readiness. |

Native snapshot/build/run records are under `/Volumes/PRO-G40/Projects/COLLECT-Build-Evidence/2026-11-10/burimunsi-native/{source-testing-candidate-009,build-029,device-api36-016}/`. Current deployment proof is in `/Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-10/retained-upgrade-006/{apply32,edge,upgrade,release}-result.json`; HTTP proof is in `post-source006-http-smoke-001/result.json`. Manual recovery is recorded under `runtime-after-host-restart-002/`; the warm startup proof is `runtime-startup-001/install-006-result.json`. Static review, prior rehearsal and genuine web Owner access remain in `prototype-native-review-001/result.json`, `prototype-native-rehearsal-001/` and `owner-email-login-proof-001/result.json` under the same production-evidence root. [production-goal.json](production-goal.json) retains receipt bindings and the historical task registers; older checkpoint fields must be read within their recorded scope.

## Historical next dependent sequence (superseded)

1. Finish the running API36 Staff29/receiver36 instrumentation and read back all 65 outcomes. Compare the actual empty phone/PIN entry capture (`prototype-sign-in.png`) and original route/panel interactions with the retained prototype. Build PASS and source checks are not installed-screen proof.
2. Produce production-configured version24 APKs from the qualified source, sign/verify the new candidate and install a data-preserving update for authorized testing. Verify the supplied logo, original eight routes/fifteen panels and staff/admin boundaries before accepting distribution.
3. Verify a genuine authorized native phone/PIN login and server-selected collection against deployed source006, preserving web Owner authentication, original payer/SMS evidence, uncertain-outcome recovery and the single canonical financial writer. No native account/session acceptance is inferred from the successful negative HTTP smoke.
4. Configure genuine receiving account/network, phone/SIM, roster and custodian as runtime data in the existing protected Admin and original signed-in flows. A newly invented business-enrollment or device-setup screen is not a prerequisite before native login. Qualify actual pairing, SMS permission/SIM behavior, receipt upload, duplicate/offline recovery and canonical receipt-to-ledger results through a bounded physical-phone pilot. Record real automatic cold-login recovery separately from the completed manual and warm-startup evidence.

Historical import milestones `c1f2b366f` and `a9e2c301a`, build014/device007, build025/device013/signed004, the original release-r4 guard evidence, [current-status.json](current-status.json) and [validation-summary.json](validation-summary.json) remain useful provenance. Their native managed-email/setup entry descriptions are superseded by the owner's original-prototype instruction. Public testing means authenticated internet-reachable testing; it does not imply public source publication or open staff enrollment. Backend006 deployment and build029 PASS are established; the running full65 result, corrected configured/signed APKs, genuine native staff session and physical financial acceptance remain separate pending proof layers.

</details>

</details>

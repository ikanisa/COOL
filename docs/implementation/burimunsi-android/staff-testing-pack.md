# BuriMunsi staff testing pack

**Production005 is live on the existing Collect backend, OPEN at epoch 43,
with 53 unchanged migrations. Real SMS-to-ledger acceptance passed:** one real
member has nine automatically posted canonical contributions. The Pixel displays
the matching member balance, recovered after the native records fix and completed
two Sync requests. A real new-SMS arrival during an offline interval remains unproven.

The final signed **0.22.0-collect.9 / v31** APK is installed on the Pixel 4a.
Its saved administrator login survived restart; SMS access is Granted and capture
Listening. The earlier unexplained package absence required a verified reinstall;
these results describe the current installation, not uninterrupted installation.

- [Download the staff APK from Drive](https://drive.google.com/file/d/1cVHIyhTj3nb3mKpukZJBepmuFQTeJKpu/view?usp=drivesdk) — Android 8 or later; version code 31; package `rw.ikanisa.burimunsi.gateway`.
- [Shared Collect Admin](https://platform-admin.collect.ikanisa.com/) — use an existing authorised Collect account.
- APK SHA-256: `153f48746b62bf35bb89b68b91abf27f573fda7cc8dbfbeea2d09c270dd5aa9e`. The Drive download and installed bytes match.

## Installation and use

1. Download the APK to the Android phone and open it. Allow installation from
   that source if Android requests it. Install over the existing app to preserve
   its saved data.
2. Sign in with the phone number and passcode issued privately by the
   administrator. Closing the app preserves the saved session. Use
   **Settings → Sign out** to sign out explicitly.
3. As administrator, grant **Settings → SMS permission**. **Settings → Gateway**
   should show **Granted** and capture **Listening**. Messages sync automatically;
   **Sync** requests an immediate cycle. Staff accounts have SMS permission
   **Unavailable** and no gateway controls.
4. Use **Add member → Suggested from MoMo**, manual member entry or the existing
   import option. Suggestions display masked candidates. Choose the correct person
   and enter their full known MoMo number. A masked number is never expanded into
   a guessed number.

Account permissions determine available actions. Installation requires no phone
pairing or additional SMS provider.

## Automatic transaction flow

Permitted M-Money messages are captured, parsed and recorded automatically.
Eligible incoming receipts match a member within the Collect group using the
normalised payer name and last three phone digits. A unique eligible member match
allows the existing canonical payment/ledger writer to post the contribution.
Unmatched receipts remain recorded and can be reconsidered after the real member
is registered. Outgoing and failed messages must not create contribution credits.
There is no manual SMS verification or independent provider-confirmation gate.

Final backend readback found **32 observations and transactions**, **29 enriched
financial facts (18 incoming / 11 outgoing)** and **three non-financial notices**.
All 29 financial amounts are numeric RWF values; all 18 incoming receipts have
wallet balances. No unknown financial source or duplicate scoped source key
remained. Actual incoming/outgoing details displayed amount and Balance after;
no manual Verify action was present.

## Staff acceptance scenarios

Record the date, version, role, phone model and result. Keep credentials, original
SMS bodies and personal payment details out of shared reports.

1. Check assigned-role sign-in, saved sessions, explicit sign-out and access
   boundaries. Both roles passed on this unchanged APK. Permission revoke/regrant,
   transaction details, Add Member options and repeated Sync were checked live.
2. Real financial acceptance passed with one owner-approved payer and nine genuine
   retained SMS receipts. Automatic matching created nine payments, nine canonical
   contributions and matching balance snapshots. The app's member balance and
   shared Admin's member, payment and Credited views agreed. Two final Sync requests
   and saved-session restart passed. The nine original canonical payment/ledger
   identities and complete financial row fingerprints remained unchanged after Sync.
3. Let a **real new SMS** arrive while phone internet is unavailable. Restore
   internet and confirm its source, transaction and eligible credit catch up at
   most once. No new SMS arrived during the observed offline interval, so this
   receipt catch-up journey remains unproven.

## Known limits

Cold-start navigation is guarded while offline. Reconnecting restored the saved
administrator session without another PIN and returned capture to Listening;
this proves saved credentials, not offline receipt catch-up. Image/PDF/XLSX member
imports are unavailable. CSV preview passed with a synthetic row; real batch
registration was not demonstrated. Seven historical recovery obligations remain
explicitly UNKNOWN and preserved.

## Evidence and release provenance

Production005 corrects only native posted-row validation, resolving Home/member
reads after a real credit. It retains the parser and suggestions corrections from
production003/004. The same database is retained; the APK, Auth profile, keys and
Cloudflare Admin frontend are unchanged. Role/session, permission and prior Admin checks are reused within
that compatibility scope; no new APK build or Admin frontend publication is claimed.

- [Final QA/UAT report](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-005/QA-UAT.md>)
- [Final physical-device checks](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-005/pixel-real-member-final-uat.json>)
- [Final independent backend/source-chain readback](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-005/live-independent-readback.json>)
- [Deployment and fresh logical backup/restore](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-005/live-journal/deployment-result.json>) — 39 business relations, 41 stored files and seven UNKNOWNs compared; owned temporary resources removed. This is not a complete disaster recovery or credential-recovery test.
- [Real member/credit and repeat-Sync comparison](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-005/real-member-financial-uat.json>)
- [Earlier installation receipt](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-002/pixel-final-apk-install.json>) and [Drive byte verification](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-003/drive-apk-byte-readback.json>)
- [Eight separate role/session checks](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-002/pixel-final-role-uat.json>) and [reused permission/detail/offline-login checks](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-003/pixel-production003-final-qa.json>)

Frozen native source: `32e2d9b7ac88cfcdb37dd294f964b021b9c1e872d827332292c2480b4782b6e7`.
Final backend source: `62409fdd78973d44089565f4a61e7e4c5dd01caffbab0d7304ed3b3fa052b1f8`.

The [production004 pre-enrollment readback](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/native-sms-production-004/live-independent-readback.json>)
recorded zero members/credits before the real member was enrolled; it is superseded.
Earlier records remain historical: [v28 Drive archive](https://drive.google.com/file/d/1qS_v83PHSJxV3j0KLOZ-YZMEMQOwX9Od/view?usp=drivesdk),
[v29 UAT](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/android-final-qualification-001/pixel-v29-live-uat.json>),
[v30 UAT](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/android-final-qualification-002/pixel-v30-live-uat.json>),
[v31 qualification](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/android-v31-session-qualification-001/pixel-v31-live-uat-retry-001.json>)
and [earlier Admin UAT](</Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-13/android-v31-session-qualification-001/admin-live-uat-final.json>).

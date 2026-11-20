# BuriMunsi Android integration

**15 November 2026 checkpoint:** signed native **v36 /
0.22.0-collect.14** Admin/Sync and Staff APKs are installed on the Pixel 4a.
The shared backend is `production-20261115-001`, **OPEN epoch 49 / 61
migrations**, with the existing hosted Collect Admin verified compatible.
Actual Excel/PDF/CSV downloads, picker cancellation, Staff role and cold-process
saved login, and automatic recovery after a bounded network outage passed.
The same 138 offline contracts passed on the Pixel and Android 16 4 KB/16 KB
emulators; these are separate from live carrier and reboot acceptance.
[Private v36 staff release and guide](https://drive.google.com/drive/folders/1Pn43Yv8ICuteFHM70oxL-Ys832r2Ifws).
See the latest checkpoint in [the implementation plan](implementation-plan.md).
Remaining Owner MFA/credential custody, independent host recovery, retention
authority, new-carrier/reboot/device coverage and independent recipient
acceptance prevent a blanket production-readiness claim. Earlier descriptions
below remain dated import and validation evidence.

**11 November update:** This document records the original import and earlier
validation. Some version, runtime and receiving-setup descriptions below are
historical. See [MVP testing readiness](mvp-testing-readiness-2026-11-11.md)
for the current checkpoint and the later user instructions.

BuriMunsi is a native Kotlin/Compose Android application for staff and admins. It shares Collect's existing local Supabase instance, Collect Admin, authorization, collections, receiving accounts, payments and canonical ledger. There is no BuriMunsi website or separate business backend in this integration.

The Android project is `native/burimunsi/`, version `0.21.0-collect.1` / versionCode 23. Work is on `codex/burimunsi-android-integration-20261109`, based on `940bbb39e`. Use the consolidated checkout, not the preserved outer T7 repository.

## Source reviewed and imported

The original Drive folder is [BuriMunsi](https://drive.google.com/drive/folders/1jm9YztANVsQfKgh3rm-aC8G9LDs12oPi). The final engineering handover, original 65 BuriMunsi contracts and 36-action register are retained under `drive-handover/`; their inherited completion fields remain historical. `implementation-plan.md` maps the relevant actions to current repository evidence and remaining shared-deployment work.

- A04.3 supplies the complete native Staff/receiver project, pinned Collect receiver sources, namespaced server adapters, shared posting code, tests and configuration/build tools. `source-import.json` records each imported path, original hash and receiving commit.
- Recovery.3, API r3 and presentation.3 are merged into that runtime. A04.2's consumed-view invalidation, owner/group identity and cumulative financial proof handling are retained. See `runtime-merge.md` and the source-owned `contracts/burimunsi-api/` schemas.
- SMS R4 and Storage R3 source/tests are retained in `integration/burimunsi/continuations/`, outside active Android source sets. Their missing production checkpoint/storage ports and writer cutover are documented in `supplemental-review.md`. The plaintext host adapter and older ownerless journal are test-only.
- Release r4's guard and producer-provenance code is adopted with the existing release-readiness checks. Real signing identities and independent release evidence are not provisioned by the import.

The downloaded archives and unchanged extracted originals are in the ignored `.cache/burimunsi-drive-20261109/` directory. `archive-verification.json`, `source-import.json`, `supplemental-import.json` and `release-merge.json` identify the source bytes and integration decisions. Cached archives are preserved inputs, not another application source authority.

## Android roles and configuration

| Variant | Application identity | Scope |
| --- | --- | --- |
| `staff` | `rw.ikanisa.burimunsi.staff` | Permissioned staff/admin operations; no packaged receiver or SMS permissions. |
| `internal_receiver` | `rw.ikanisa.burimunsi.gateway` | Authorized staff/admin receiving handset; separate retained queue and receiving custody. |
| `nativeTest` build type | role identity plus `.nativeTest` | Debug-signed, testOnly, offline instrumentation sandbox. |
| `qualification` build type | role identity plus `.qualification` | Optimized, unsigned, testOnly offline artifact. |

Both roles use `collectSupabaseOrigin` and `/functions/v1/collect-api`. The receiver derives its gateway URL from that same origin/prefix. Logical native requests remain `/v1/burimunsi/...`; the transport adds the existing Edge function prefix. A conflicting separate backend origin is rejected when the shared profile is selected.

`native/burimunsi/configuration/installation.example.properties` describes the public fields. A production profile needs the actual shared HTTPS origin, existing collection UUID, receipt profile, explicit timezone and public client key. Ingestion tokens, passwords, refresh tokens, privileged Supabase keys and release keys belong in their protected runtime stores. Qualification builds explicitly erase all endpoints, keys and collection bindings. Receiving uploads retain the existing hold.

The fixed schema, request framing, owner binding and recovery tests are executable source. Generate/check resources from the repository root:

```sh
python3 scripts/generate_ui_copy.py --check
python3 scripts/generate_burimunsi_wire.py --check
python3 native/burimunsi/scripts/native_pipeline.py plan
```

Use JDK 17, the verified Gradle 9.1.0 binary distribution, Android SDK 36/build-tools 36 and the exact dependencies documented in `dependency-compatibility.md`. The ignored local toolchain was verified against vendor checksums; its `environment.sh` configures this workstation. `native/burimunsi/local.properties` selects the existing SDK for Android Studio and remains ignored.

The delivered Gradle launcher verifies its distribution before execution. The build pipeline compiles and inspects the eight declared application/test artifacts, checks Staff package isolation and exact per-role instrumentation inventories, and binds evidence to its source fingerprint:

```sh
python3 native/burimunsi/scripts/native_pipeline.py build --output /absolute/new/evidence-directory
```

Use a new evidence directory. This command does not build/promote a production release or enable the backend. `current-status.json` records its dated checkpoint; use the readiness note above for later work. Failed attempts and their logs remain preserved.

## Historical import validation — 9 November 2026

Final clean `build-007` compiled and inspected all eight declared APKs. Actual API 36 instrumentation passed **53/53**: Staff 23 and receiving handset 30, including seven Android encrypted-queue/durability tests. All four installed sandbox packages were removed and the task-owned emulator was stopped. Its AVD and evidence remain available.

That historical native source fingerprint is `2b9e8b0ccfa5c82521264aa923d1bf658e3a5bb5ca6ab0e64dd3e3ca786e3f00`. The broader candidate records **544 files**, nine verified archives and 17 unchanged receiver source pins. `source-candidate.json` distinguishes original bytes from merged/adapted source; `validation-summary.json` records passing, blocked and failed checks with their proof scope. Historical SMS package logs are retained as supplied provenance through a scoped ignore exception.

Other local checks passed: 1,572 namespaced backend tests, 87 pipeline host tests, 22 UI source contracts, resource/wire generation, Deno route/dispatcher imports and sole-design-authority hygiene. The host tests use their declared reduced/synthetic boundaries. API 26, physical handset/SIM, live shared-ledger behavior, authenticated visual/TalkBack/fluency acceptance and signed production distribution remain open.

APK/evidence directory on this workstation: `/Volumes/PRO-G40/Projects/COLLECT-Build-Evidence/2026-11-09/burimunsi-native/build-007`. The staff and receiver debug APKs are under `apks/`; optimized qualification artifacts are unsigned and testOnly. Both settled startup screens were visually inspected after correcting inherited dark-theme text/system-icon contrast. They correctly require managed setup while the genuine shared deployment/login configuration is absent.

## Shared local backend: current facts and remaining work

The owner-selected [local Supabase source folder](https://drive.google.com/drive/folders/1PJHsgJ0ozM0LSCLGDXZBXyVPp72-FS7p) contains a generic hosting/client framework. Its newer 1.7 source is not proof that the retained instance was upgraded or contains Collect's business schema.

The existing retained `supabase-local` runtime was resumed with its original containers/volumes. Read-only PostgreSQL inspection found only generic account tables and migrations, no Collect business schema/runtime roles or BuriMunsi collection. See `local-supabase-current.md` for exact observations. No schema migration, provider activation, auth change or financial write occurred.

The new `collect-route.js` hook is mounted in the existing Collect dispatcher, before ordinary member authentication. It uses the same admitted DB/application fence, genuine Supabase token verification, existing Admin projection and canonical posting adapters. With no trusted server composition it returns the versioned `native_service_unconfigured` response without entering native financial commands.

Live integration still needs:

1. Deploy the reviewed Collect business schema/functions and applicable BuriMunsi extension proposals into the existing retained instance; preserve existing accounts and use one financial writer.
2. Bind the real collection/receiving custody and remaining source/gateway/custody bridges required by `createCollectNativeRoute` and `createPostgresNativePorts`.
3. Deploy and qualify the implemented Android managed-login broker and narrow `/api/admin/burimunsi/access` endpoint. `BuriApplication` now supplies `ManagedSessionHost`; the current native Collect email-code form establishes the existing Admin BFF session before the unchanged operator phone/passcode flow. The endpoint also requires the current installation secret and native grant. No refresh token is released and nothing in this broker persists credentials. Actual GoTrue/PG/device-grant commissioning remains required.
4. Commission the common phone-accessible HTTPS deployment profile. The currently exported loopback HTTP URL is a desktop-local address and is not the configured Android service origin.
5. Qualify actual device/SIM, encrypted storage, receipt-to-ledger recovery, provider handling and signed distribution against the final shared candidate.

These are unresolved integration/release items, not results inferred from source imports or host tests. Current source does not claim a working live receiving/posting deployment. The original full r4 release suite now passes all 307 tests in the existing case-sensitive managed Linux VM with its system OpenSSL; the four adopted guard libraries are byte-identical to that original delivery. Earlier Mac failures remain historical evidence in `validation-summary.json`. This Linux regression is neither independent production review nor signing/distribution approval.

## Design and evidence

The sole UI/UX authority is `revolut-design@jean-bosco-skills`, loaded from its maintained entrypoint when installed discovery was unavailable. The imported native theme is a provisional BuriMunsi adaptation of Dark/Glow families. Product identity, staff/admin capabilities and access controls are preserved. Source hygiene and host/controller checks do not establish installed visual fidelity, TalkBack or physical-phone acceptance.

## Shared login continuation — 10 November 2026

The proposed public profile selects `https://supabase.collect.ikanisa.com`, `https://api.collect.ikanisa.com` and the existing `https://platform-admin.collect.ikanisa.com`; the owner was confirmed against the configured Admin account. Cloudflare still serves its existing Workers, and the Supabase hostname/tunnel is not commissioned. SELECT-only legacy checks found one user and one Admin matching that email, with no records in the checked group/payment/ledger/MoMo/SMS tables. Other stores and provider state were not covered. No production route or financial state was changed.

The actual Admin proxy forwards the device secret only to the exact native access endpoint. Source integration covers the proxy, Edge logical URL projection, encrypted BFF custody and existing managed principal. At the shared-login checkpoint, 1,597 Buri backend tests and 115 Admin proxy tests passed locally with their declared synthetic boundaries. Core 121 and managed HTTP transport 20 checks pass, including identity mismatch, revoked access, late-response fencing and unconfirmed sign-out. The native host aggregate passes, with physical temporary paths for receiver checks on macOS. Current `build-012` compiles/inspects all eight APKs; API36 `device-api36-005` passes 59/59 (Staff 26, receiver 33), including the native credential form, disposal, denial and seven receiver durability cases. All four sandbox apps were removed and only the task-owned emulator was stopped. Captured empty credential forms were visually inspected; the two role captures are byte-identical. Production claims remain open.

The new sign-in form is a BuriMunsi adaptation of the selected Dark/Glow family using the existing form primitives. It is a shared Collect authentication precondition, followed by the existing four-digit operator passcode. No consumer registration, separate web product, alternate ledger or PIN-to-Supabase token conversion is introduced. Password/cookie/access credentials are confined to process memory and cleared locally on sign-out; a failed remote logout is shown as unconfirmed. Fluent Kinyarwanda and live authentication acceptance remain unverified.

A fresh native snapshot-v3/restore rehearsal004 also completed on 10 November. Native database owner/settings, ACL names/grantors/privileges, role flags/memberships and checked counts match the retained source. The isolated clone was stopped after verification; the separate clone003 now carries all26 reviewed migrations (see the operator continuation below). Private native configuration contains credentials even though the role dump omits password hashes. This is not an encrypted complete production backup or authorization to migrate the source.

## Existing Collect Admin operator approvals — 10 November 2026

The existing owner-only Team page now links to `/admin/burimunsi`. It approves phone, native role and maximum capabilities for existing confirmed Collect identities, in the server-selected collection. It uses the existing managed cookie/CSRF session, fresh email proof and `admin_users.manage` permission. Approval is not signup or initial native PIN/device provisioning. The versioned request includes an expected collection assertion; a changed server collection cannot retarget a retained request. Unknown commit results retain the exact original intent and support lookup before explicit same-key retry.

The canonical native composition resolves operators from that closed approval directory. Approval narrowing/revocation invalidates native sessions while preserving the independently authorized device grant and genuine shared Auth session. Read-only managed-session checks use a lock-free database snapshot; writes restore the real shared BFF context and retain existing financial permission and fresh-email checks.

All26 maintained migrations, including the additive BuriMunsi private schema, pass in the isolated retained native PG17 clone. A disposable native-schema QA copy passes owner/idempotency/capability/read-only/revocation SQL fixtures. Those Auth users/sessions/OTP rows are explicitly inserted fixtures; GoTrue/provider/TLS and normal-owner CI execution are not proved by this rehearsal. The source instance remains unmigrated.

Current checks pass: 1,631 Buri domain/route tests plus13 schema consumers,34 affected Flutter account/Team/invitation/widget tests, scoped Dart analysis and `make revolut-design-authority`. Final wide and enlarged-text captures were inspected as a utility/settings adaptation of the selected Revolut reference. An isolated870-input release-mode Admin web compilation passes on PRO-G40 using an `.example` profile and synthetic public/CAPTCHA keys. It is not a hosted deployment or full PWA acceptance. Exact hashes, paths and scope are in `validation-summary.json` under `current_operator_approval`.

The earlier native shared password broker has now been replaced with the current Collect email-code flow; real GoTrue/SMTP onboarding remains to be qualified. Canonical member/membership, source, gateway and custody runtime ports still need wiring; `serve.js` does not install the native composition, so unconfigured native operations remain closed. Real collection/wallet/SIM/custodian, initial native Admin credentials, device enrollment, public TLS, hosted/physical acceptance, independent review and signing/distribution remain open.

## Native shared email-code continuation — 10 November 2026

Android now uses Collect Admin's existing `/api/admin/auth/otp` and `/auth/verify` contracts instead of the earlier password endpoint. A current email challenge precedes the existing operator phone/four-digit PIN and installation-specific grant. The receiving queue never receives an email code or shared BFF credential. Codes and BFF/access credentials remain in process memory; submitted codes are cleared, and backgrounding disposes input while retaining only current challenge metadata so staff can read their email. Unknown send/verification results never cause automatic resends or code replays. A definite invalid-code response permits an explicit manual attempt on the same challenge.

Current `build-014` compiles and inspects eight APKs from195 verified inputs on PRO-G40. Native source SHA-256 is `7ae29ea796fb6fd23a870ab5c0127221a4a73cc372fc662af6c305e3c6db63e3`. API36 `device-api36-007` passes **61/61**: Staff27 and receiver34. Final email/code captures were inspected; matching role captures are byte-identical. All four sandbox packages were removed and only the owned emulator5558 was stopped. Current core129, transport29 and pipeline88 checks also pass within their declared fixture boundaries. Build012/password and build013/intermediate UI records remain historical evidence. See `validation-summary.json` under `current_managed_email_code`.

Read-only Cloudflare inspection shows an active managed certificate for `*.collect.ikanisa.com`, `collect.ikanisa.com` and `ikanisa.com` (dashboard expiry5 January2027). That wildcard includes the proposed Supabase hostname, so it is retained. This proves certificate availability only; DNS/tunnel/live HTTPS/Auth are still uncommissioned. Exact observation and source URL are in `cloudflare-tls-readback.json`; no Cloudflare settings, paid service or route was changed.

## Canonical member commands — 10 November 2026

Canonical composition now installs the member adapter directly and rejects replacement member writers. It shares the existing Collect Admin person/public-ID and membership statements. Direct enrollment creates a scoped beneficiary and membership, with no Auth/operator identity or credit; membership changes preserve group role and expected revision. Current native approval remains additional to shared permissions and fresh email. A global read-only staff role does not gain write access from a native capability alone.

Current checks pass1675 (Buri1655, schema13, existing Admin7). The retained native PG17 SQL qualification009 also passes all four fixtures, including common statements compiled from the current JS and executed as normal `collect_runtime` with a genuine registered work lease. It preserves the native owner's flags; it is not normal-owner CI, Edge HTTP, native login or GoTrue acceptance. The initially over-restrictive group guard in qualification007 was corrected to the existing generic Admin global operating guard scope; native collection approval/checks remain. Failed evidence and verified rollback/work reconciliation are retained. Exact scope and source hashes are in `validation-summary.json` under `current_canonical_members`.

The real gateway, audited original-source reader, custody/encryption/media ports and trusted installation in `serve.js` remain open. The retained source database and public routes remain unchanged; the native namespace stays closed without that composition. Native build014/device007 are still current because this continuation changed no native inputs.

## Canonical read projection continuation — 10 November 2026

Collect stores member MoMo routes as `07…`; native DTOs require `+250…`. The member, allocated-payment and ledger projections now normalize that authoritative reference. Original masked payer numbers, names and source timestamps remain exact, ledger deltas retain their sign, and unallocated payments keep a null member reference. Missing or masked member identity cannot borrow an Auth/login phone. A canonical Direct enrollment followed by the existing reader is covered alongside these projection cases.

All1681 affected checks pass (Buri1661/schema13/existingAdmin7), within the fixture boundaries in `validation-summary.json`. Native SQL009 consumed inputs and native build014/device007 inputs are unchanged. The audited source reader remains a separate unfinished integration: existing Collect raw reveal requires `sms.read` plus `sms.reveal`, fresh email, an explicit review reason and a final audit before plaintext returns.

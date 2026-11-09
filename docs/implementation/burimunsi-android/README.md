# BuriMunsi Android integration

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

Use a new evidence directory. This command does not build/promote a production release or enable the backend. `current-status.json` records the actual latest outcome; failed attempts and their logs remain preserved.

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
2. Bind the real collection/receiving custody and canonical command/source/gateway bridges required by `createCollectNativeRoute` and `createPostgresNativePorts`.
3. Deploy and qualify the implemented Android managed-login broker and narrow `/api/admin/burimunsi/access` endpoint. `BuriApplication` now supplies `ManagedSessionHost`; the new native Collect password form establishes the existing Admin BFF session before the unchanged operator phone/passcode flow. The endpoint also requires the current installation secret and native grant. No refresh token is released and nothing in this broker persists credentials. Actual GoTrue/PG/device-grant commissioning remains required.
4. Commission the common phone-accessible HTTPS deployment profile. The currently exported loopback HTTP URL is a desktop-local address and is not the configured Android service origin.
5. Qualify actual device/SIM, encrypted storage, receipt-to-ledger recovery, provider handling and signed distribution against the final shared candidate.

These are unresolved integration/release items, not results inferred from source imports or host tests. Current source does not claim a working live receiving/posting deployment. The original full r4 release suite now passes all 307 tests in the existing case-sensitive managed Linux VM with its system OpenSSL; the four adopted guard libraries are byte-identical to that original delivery. Earlier Mac failures remain historical evidence in `validation-summary.json`. This Linux regression is neither independent production review nor signing/distribution approval.

## Design and evidence

The sole UI/UX authority is `revolut-design@jean-bosco-skills`, loaded from its maintained entrypoint when installed discovery was unavailable. The imported native theme is a provisional BuriMunsi adaptation of Dark/Glow families. Product identity, staff/admin capabilities and access controls are preserved. Source hygiene and host/controller checks do not establish installed visual fidelity, TalkBack or physical-phone acceptance.

## Shared login continuation — 10 November 2026

The public profile selects `https://supabase.collect.ikanisa.com`, `https://api.collect.ikanisa.com` and the existing `https://platform-admin.collect.ikanisa.com`; the confirmed owner is `info@ikanisa.com`. Cloudflare still serves its existing Workers, and the Supabase hostname/tunnel is not commissioned. SELECT-only legacy checks found one user and one Admin matching that email, with no records in the checked group/payment/ledger/MoMo/SMS tables. Other stores and provider state were not covered. No production route or financial state was changed.

The actual Admin proxy forwards the device secret only to the exact native access endpoint. Source integration covers the proxy, Edge logical URL projection, encrypted BFF custody and existing managed principal. All 1,597 Buri backend tests and 115 Admin proxy tests pass locally with their declared synthetic boundaries. Core 121 and managed HTTP transport 20 checks pass, including identity mismatch, revoked access, late-response fencing and unconfirmed sign-out. The native host aggregate passes, with physical temporary paths for receiver checks on macOS. Current `build-012` compiles/inspects all eight APKs; API36 `device-api36-005` passes 59/59 (Staff 26, receiver 33), including the native credential form, disposal, denial and seven receiver durability cases. All four sandbox apps were removed and only the task-owned emulator was stopped. Captured empty credential forms were visually inspected; the two role captures are byte-identical. Production claims remain open.

The new sign-in form is a BuriMunsi adaptation of the selected Dark/Glow family using the existing form primitives. It is a shared Collect authentication precondition, followed by the existing four-digit operator passcode. No consumer registration, separate web product, alternate ledger or PIN-to-Supabase token conversion is introduced. Password/cookie/access credentials are confined to process memory and cleared locally on sign-out; a failed remote logout is shown as unconfirmed. Fluent Kinyarwanda and live authentication acceptance remain unverified.

A fresh native snapshot-v3/restore rehearsal004 also completed on 10 November. Native database owner/settings, ACL names/grantors/privileges, role flags/memberships and checked counts match the retained source. The isolated clone was stopped after verification; the separate clone003 still carries the nine foundation migrations for the pending platform review. Private native configuration contains credentials even though the role dump omits password hashes. This is not an encrypted complete production backup or authorization to migrate the source.

# Production cutover — 3 September 2026

Status: **backend and Admin deployed; full production GO remains open**.

## Approved and completed

The owner approved requiring every member/Admin client to update. Legacy clients
are not supported by this privacy cutover. This is not proof of a store rollout
or minimum-version enforcement in already-installed binaries.

- Applied the exact 14 previously reviewed/rehearsed migration files to COOL
  `lhbowpbcpwoiparwnwgt` in **one transaction**, including their history records.
  Production moved from 97 to **111 migrations**. An advisory lock and exact
  baseline/hash guards protect against concurrent or changed-source deployment.
- Read back the privilege allowlist, column grants, payment-route grants,
  indexes and all eight member-record backfills. Hybrid assisted onboarding
  remains OFF; its phase-one foundation is not presented as a completed ledger.
- Before/after fingerprints match for the five existing checked tables:
  profiles, payments, ledger_entries, raw_payment_sms and bank_transactions.
  Profile count is eight and raw receipt count is three. There are no rows in
  these payment/ledger/bank transaction tables. No real transaction was generated.
  The earlier actual archive rehearsal independently covered 116 tables.
- Storage metadata remains **182 objects / nine buckets**. No Storage object
  bytes were deleted, exported or claimed to be recoverable by the SQL archive.
- Activated only the owner-selected existing operator, **Collect ID 965511**.
  Exactly one active WhatsApp approval and the combined platform role read back.
  This account still needs a **new WhatsApp sign-in**. No Auth user/session was
  fabricated, verification overridden, OTP sent, or group role changed.
- Deployed only `ingest-payment-sms` **v4** and `parse-payment-sms` **v5**.
  Downloaded production TypeScript files match the local candidate byte-for-byte.
  Both are ACTIVE. Ingestion retains JWT verification; parsing retains its
  internal-secret gate. No other function or provider secret was changed.
- Deployed Admin Worker **78ad4076-9918-4e11-b749-17452213ce52**, independently
  verified at 100% traffic. The live custom-domain gate passes with no blockers.
  The existing unapproved browser session now shows “Admin access required”,
  with zero browser console errors/warnings. Fresh approved-session UI UAT is open.

The previous live Admin version was **195fd0dd-321d-4d5b-83ee-4aa51dc77fbc**,
not the older version in the stale August deployment log. Retain it as evidence;
do not assume client-only rollback reverses this database/privacy cutover.
No Git commit/push, store upload/publication, real payment, OTP, SMS or push send
was performed by this cutover. The public landing Worker was untouched.

## Verification

- Flutter analysis clean; **552 tests passed**.
- Receipt/parser tests: **39 passed**; both handler type checks passed.
- Deployment guards: **5 tests / 51 assertions passed**.
- Admin release manifest, hosting, dry-run and live custom-domain gates passed.
- Public runtime API returns HTTP 200. Anonymous legacy-profile, member-profile,
  profile-name, receipt-ingestion and parser requests correctly return HTTP 401.
- SQL READ ONLY member-contract readbacks pass for every existing profile:
  exact nine-field name-free payload; six-digit identity; bounded history,
  intents and balances; no Admin access without a real qualifying session.
  These SQL identity simulations do not substitute for signed-in HTTP UAT.

## Matching native release candidate

Android APK/AAB and the signed App Store IPA have now built as **1.2.4 (23)**,
using the reviewed production endpoint and public anonymous key only. No device
was overwritten and no store upload occurred. Android upload signing verifies,
with RECEIVE_SMS present and READ_SMS absent. The exported iOS app passes strict
signature verification, has `get-task-allow=false`, production APNs entitlement,
the expected bundle/team identity and 25 packaged privacy manifests. Both native
wrappers verify the embedded production backend. Packaging emitted existing
Kotlin/CocoaPods migration warnings, not build failures; do not treat them as
future-toolchain compatibility acceptance.

Native artifact hashes and the source manifest are in
[native artifact verification](NATIVE_CUTOVER_ARTIFACTS_V2_2026-09-03.json).
The repository package version is synchronized with the candidate, and the
release wrapper now derives the Android and iOS versions from that single
source. No new release commit or store version was created.

## Audit-tool corrections (no repeated production mutation)

The initial attempt stopped **before any migration write** because the API's
Postgres array representation was a string. Column metadata now uses JSONB and
a regression test rejects array text. The second attempt committed successfully.

The first post-commit ACL check falsely reported missing grants because
`read_only:true` runs as `supabase_read_only_user`; PostgreSQL's information-schema
views hide other roles' grants from that role. The independent check now uses
the authorized `postgres` context inside **BEGIN READ ONLY / ROLLBACK**. All
permission checks pass. No grants were weakened to satisfy the audit. The same
visibility issue affected the first operator readback; its independent read-only
check confirmed activation without replaying either bootstrap operation.

## Evidence

- [Fresh preflight](SUPABASE_CUTOVER_PREFLIGHT_2026-09-03.json)
- [Reviewed cutover plan](PRODUCTION_CUTOVER_PLAN_2026-09-03.json)
- [Atomic deployment / protected-data comparison](PRODUCTION_CUTOVER_APPLY_V2_2026-09-03.json)
- [Independent permission readback](PRODUCTION_CUTOVER_READBACK_V2_2026-09-03.json)
- [Final readback including all 14 deployed source hashes](PRODUCTION_CUTOVER_READBACK_FINAL_2026-09-03.json)
- [Selected operator readback](FIRST_OPERATOR_CUTOVER_READBACK_2026-09-03.json)
- [Downloaded receipt-function source verification](SMS_EDGE_CUTOVER_2026-09-03.json)
- [Live Admin hosting gate](ADMIN_PWA_CUTOVER_LIVE_GATE_2026-09-03.json)
- [Public HTTP / member contract readback](CUTOVER_API_MEMBER_READBACK_2026-09-03.json)
- [Final hosted preflight: healthy, no pending migrations](SUPABASE_POST_CUTOVER_PREFLIGHT_2026-09-03.json)

The four live Admin payloads (main JavaScript, bootstrap, service worker and
manifest) were independently downloaded from the custom domain and match local
build hashes. The other seven Edge Functions, required secret-name inventory
and Auth configuration match the pre-cutover snapshot. Advisors report 179 WARN
and 27 INFO security findings, no ERROR; this is not a zero-findings certification.

## Still required before GO

1. Fresh approved-operator WhatsApp sign-in, authenticated member/Admin journeys,
   and a separately approved second operator for maker/checker acceptance.
2. Matching native build distribution and exact-artifact physical Android/iPhone
   UAT: WhatsApp delivery, MoMo/USSD handoff, consented receipt capture, balanced
   ledger, push, accessibility, lifecycle/offline behavior and crash evidence.
3. Store/provider policy approval and public availability. Local binaries or a
   browser viewport do not establish native/store acceptance.
4. Resolve obsolete Auth site/redirect configuration still pointing to the retired
   Vercel site, and confirm the intended canonical callback URLs before changing it.
5. Storage/off-site/key-escrow recovery and agreed RPO/RTO. The encrypted database
   archive and restore drill do not cover these additional recovery boundaries.
6. Review remaining advisor warnings and freeze/review the current dirty source
   before the independently authorized Git/store publication chain.

No new database IP rule was needed: deployment used authenticated HTTPS. The
earlier temporary `.205/32` exception was already removed and was not reinstated.

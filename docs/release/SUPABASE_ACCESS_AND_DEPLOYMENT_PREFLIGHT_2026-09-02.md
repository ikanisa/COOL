# Collect Supabase access and deployment preflight

Update: [latest continuation](CONTINUATION_2026-09-02.md) and
[21:31 UTC hosted capture](SUPABASE_PREFLIGHT_CURRENT_2026-09-02.json).
There are now 111 local / 97 hosted migrations, with 14 pending. Complete local
replay, combined tests and a version-matched synthetic restore have passed.
The earlier capture below remains historical evidence; no production DDL has
been applied. The three historical-name differences also differ in stored SQL,
as recorded in the detailed history review; their retired helpers are absent live.

## Outcome

The owner's Google Drive credential instruction restored working, authorized
Supabase Management API access. The native **Supabase** spreadsheet, **Sheet1**,
**COLLECT column G** was read through Google Drive/Sheets. Its project URL matched
the linked repository project and the authenticated API returned **COOL**,
`lhbowpbcpwoiparwnwgt`, `ACTIVE_HEALTHY`.

The owner has authorized Supabase deployment/push work. Credential access is no
longer the blocker. No production migration, function deployment, role approval,
network change, paid service activation, customer export or Git push occurred.
Production **GO remains unconfirmed** for the concrete gates below.

Environment clarification: the owner confirms the live app has always used the
single production backend; no hosted staging environment exists. Local fixture
and database tests are not staging deployment. Release execution targets the
existing production project; the plan does not require creating staging.

Credentials were passed through non-echoing stdin and retained only in temporary
process/tool memory. They were not printed, committed, written to dotenv, or
saved in this report. Re-read the same native source when another authorized
operation needs credentials; do not use cached values from release documents.

## Hosted readback

The [machine-readable capture](SUPABASE_PREFLIGHT_2026-09-02.json) was started at
2026-09-02T16:16:47Z. All nine inventory requests succeeded. Request success is
not a deployment or a release acceptance result.

| Check | Observed result |
| --- | --- |
| Migration history | 97 remote versions; 110 local files; 13 pending; no remote-only versions or chronological holes |
| Historical names | Versions `202605230012`, `202605230013`, `202605230014` have different remote names and local filenames. No history repair/reapplication was performed. Version identity alone does not establish SQL-body equivalence. |
| Edge Functions | All nine expected functions are active. Current local receipt changes have not been deployed. |
| Required secrets | All 12 expected secret names are present, including `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`. Values, scope, expiry and provider acceptance were not validated. Earlier evidence calling that secret absent is stale. |
| Auth | Phone enabled; WhatsApp hook enabled and target matches; refresh rotation enabled; anonymous sign-in/manual linking disabled; OTP expiry 600 seconds; no fixed SMS test OTP or validity override configured |
| Auth callback | Site URL and redirect allowlist still point to `https://easymo.vercel.app`; canonical Collect callback ownership remains to be confirmed before changing it |
| Backups | API lists zero backups, no physical-backup metadata, PITR false, WAL-G true. WAL-G enabled alone is not proof of an available recoverable snapshot. |
| Network | Four IPv4 allowlist entries are applied. Restrictions were preserved; the documented HTTPS Management API was used. |
| Access baseline | One active platform role grant; no platform WhatsApp approval table exists yet |
| Advisors | 183 security warnings and 22 security informational findings; 89 performance informational findings; no returned ERROR or performance WARN findings |

The warning categories/counts remain within the existing repository allowance in
`scripts/supabase_advisors_warning_inventory.sh`: GraphQL anonymous 19/20,
authenticated 32/36, anonymous definer functions 6/6, authenticated definer
functions 125/125, leaked-password protection 1/1. This is a baseline comparison,
not evidence that warnings vanished or an independent security clearance. The
pending candidate needs its own post-deployment advisor comparison.

## Deployment plan and actual gates

The capture records each pending filename and SHA-256. The ten reviewed member
and overview migrations, two separate hybrid receipt/registry migrations and
one platform approval migration must not be mistaken for one already accepted
release. Do not use a generic all-functions deploy or repair historical versions
to hide differences.

1. **Recovery:** no available hosted backup was returned. Establish a verified
   encrypted recovery snapshot and approved private destination before applying
   production DDL. Do not enable paid PITR or export customer records silently.
2. **Platform operator:** the owner has now selected the first identity. A
   separate read-only lookup at 2026-09-02T16:20:26Z matches confirmed Collect ID
   965511 (phone ending 8248), currently without the combined Admin role. Execute
   the separately controlled approval/bootstrap and coordinate a new sign-in
   before enabling the new platform gate. The migration
   intentionally approves nobody and would deny the existing unapproved
   operator. Group creation/group-admin access remains unrelated to this gate.
3. **Client compatibility:** coordinate current-client activation with the new
   profile/history APIs. The profile migrations revoke old full-row/name-writing
   member RPCs. An older installed client transition is still unresolved.
4. **Combined release:** complete integrated acceptance of the hybrid foundation
   with the member/platform candidate, review historical migration-name drift,
   then apply the exact selected manifest with transaction and history readback.
   The hybrid onboarding flag defaults off; it is not authority to enable a pilot.

## Local checks rerun in this continuation

- Hybrid SQL: 33 synthetic assertions, transaction rolled back.
- SMS/receipt parser: 29 synthetic unit tests passed, no network/provider send.
- Hosted preflight helper: seven tests, 29 assertions, no failures.
- Migration-chain static validation and `git diff --check` passed.

The preflight helper's first run encountered the macOS Ruby 2.6 lack of
`filter_map`. That local compatibility defect was fixed and tested; the final
capture has no request/processing errors. No previously reported Flutter,
native-device, financial, provider or store acceptance has been promoted to a
fresh result by these checks.

The workflow follows the current [Supabase Management API authentication
documentation](https://supabase.com/docs/reference/api/introduction). The read-only
probe additionally wraps database queries in a read-only transaction and rolls
them back. Backup status uses the official [backup inventory
endpoint](https://supabase.com/docs/reference/api/v1-list-all-backups).

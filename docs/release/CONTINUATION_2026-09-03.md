# Production recovery continuation — 3 September 2026

Status: **production GO not yet established**. This document supplements,
not replaces, the [2 September evidence](CONTINUATION_2026-09-02.md).

Latest update: the subsequent [production cutover](PRODUCTION_CUTOVER_2026-09-03.md)
has now deployed all 14 reviewed migrations (111 total), both receipt functions
and the matching Admin PWA. The selected operator is approved and activated.
Earlier statements below saying no production deployment or activation occurred
describe the recovery/rehearsal phase only; they are superseded by that report.

## Authority and source

The user approved an encrypted production recovery copy on this Mac, outside
the repository. The user then explicitly approved temporarily adding
`129.222.149.205/32` to COOL's database allowlist, retaining all existing rules
and removing the temporary entry after the backup/rollout attempt. This does
not approve other IPs, broader CIDRs, paid services, disabling TLS, or changing
ordinary group-admin eligibility.

The native Google Sheet **Supabase**, `Sheet1!G2:G7`, was re-read through the
Google Drive connector. The source URL and authenticated project identity
matched COOL / `lhbowpbcpwoiparwnwgt`. Credentials were passed through
non-echoing stdin, not command-line arguments, source files or evidence reports.

## Current findings and fixes

- [Hosted preflight](BACKUP_NETWORK_PREFLIGHT_2026-09-03.json): healthy project,
  97 migrations, approximately 112 MB database size, 182 Storage objects in
  nine buckets; no listed backups and no PITR. The client IP was not allowed.
- FileVault is off. No OS encryption setting was changed. The backup
  destination uses an AES-256 encrypted APFS disk image with a random key held
  in the local Keychain. It is outside Git and is detached after use.
- The [synthetic storage rehearsal](ENCRYPTED_VAULT_REHEARSAL_2026-09-03.json)
  passed all 16 checks: private permissions, overwrite/path rejection,
  Keychain retrieval, wrong-password rejection, hash preservation across
  detach/remount, read-only protection, and final detachment.
- The first rehearsal exposed a locked-image inspection issue. The helper now
  uses mounted-image metadata while attached, and inspects the backing image
  only while detached. Swift builds with warnings treated as errors.
- The [first production attempt](ENCRYPTED_PRODUCTION_DATABASE_BACKUP_2026-09-03.json)
  stopped at TLS verification, before a database dump. The temporary rule was
  removed and the original four IPv4 entries and empty IPv6 list read back.
  Docker's macOS file-sharing service retained the otherwise-unused mount;
  after checking the exact target and removing its credential file, that image
  alone was force-detached. No other disk or Docker service was stopped.
- The revised client avoids host bind mounts entirely. Its temporary password
  file and public CA exist in container tmpfs; dump output travels through an
  in-memory pipe into the encrypted destination. TLS remains `verify-full`,
  with the official Supabase CA fingerprint pinned. No global trust-store or
  Supabase SSL-enforcement setting is changed.

The [second production attempt](ENCRYPTED_PRODUCTION_DATABASE_BACKUP_V2_2026-09-03.json)
succeeded using the authenticated primary shared pooler host on documented
session-mode port 5432. The 97-migration database archive is 5,643,165 bytes,
with 2,662 table-of-contents entries. SHA-256:
`20cfe8cb1a099867332a2e65c41104d6879d0858ae2405faf7854e438336e7dd`.
The hash matched after an encrypted read-only remount. The temporary rule was
removed, all original network rules read back, and the vault detached. A
separate disk-image inventory confirmed zero remaining CollectRecovery mounts.
This closes archive capture/readback. The subsequent restore and upgrade
rehearsal below now pass; full recovery acceptance is still separate.

[Global role definitions](ENCRYPTED_PRODUCTION_ROLES_BACKUP_2026-09-03.json)
were captured separately with `pg_dumpall --roles-only --no-role-passwords`:
22 roles, 7,008 bytes, SHA-256
`0acaef8c2682c67331351704f6b1646e9a5cadda385d53665b04bfc8c9afc18a`.
This encrypted artifact also passed remount/hash verification; its temporary
network rule was removed and its vault detached. It intentionally contains no
global role passwords. Role and database captures have separate timestamps.

## Production archive restore and migration rehearsal

The [production-copy rehearsal](PRODUCTION_COPY_UPGRADE_REHEARSAL_V4_2026-09-03.json)
restores those actual encrypted archives into a fresh, isolated PostgreSQL 17.6
container, not a hosted staging project. Its root filesystem is read-only,
database files are RAM-only, container swap is disabled, no ports or host
directories are mounted, networking is disabled, Cron execution is off, and the
HTTP worker is bound to an empty database with a zero batch size. The container
is removed and its encrypted diagnostic vault detached after each run.

Recovery fidelity checks pass for:

- All 120 exported table-data sections / 195,529 captured rows and four sequence
  values, compared before any candidate migration.
- Database owner, UTF-8/ICU locale and database-level settings/grants.
- Schema, functions, policies, constraints, ACLs and global role attributes/grants.
  The comparator ignores only generated tool metadata, equivalent grant/role
  ordering, and one exact redundant AND grouping introduced by SQL reparsing;
  unit tests prove changed privileges and constraint bounds remain detectable.
- Exact extension versions and owners. Restoring into a bare cluster required
  matching Supabase's bootstrap role, installing extensions as their original
  owners, and restoring an extension-owned GraphQL wrapper omitted by pg_dump.
  Its definition and owner were captured by a narrow read-only Management API
  query, not invented. No source archive was rewritten and no ACL was dropped.

All **14 reviewed pending migration hashes** then applied successfully as the
`postgres` role in the isolated copy, taking its migration history from 97 to
111. Production itself remains at the captured 97-migration state; none of these
14 were applied to production in this continuation.

The upgrade retained every checked pre-existing value in 116 tables (202,926
rows, including extension-seeded reference rows). Configuration tables changed
by the migrations are checked separately; only `collections.updated_at` is
excluded from the original-column comparison because its backfill invokes the
existing timestamp trigger. All 834 historical Realtime invalidations remain
intact, with exactly 12 expected new refresh events (three member, two collection,
one feature flag and six settings). All four pre-existing sequences also remain
unchanged. No payment, ledger, raw receipt, profile name or Auth data was rewritten.

The current permission/index checks and numeric-ID/member-record backfills pass.
Rollback-only readbacks check the nine-field name-free profile, bounded history,
intents and balances for every existing profile. The exact owner-selected
operator, Collect ID **965511**, can be preapproved/activated and access the Admin
overview with a fresh synthetic session in this isolated copy. Ordinary group
owners can promote group members without platform WhatsApp approval and gain
no platform access. All fixture accounts, approvals, sessions and group writes
roll back; post-test fingerprints confirm cleanup. No real OTP, payment, SMS or
push was sent, and no production operator was activated.

The [final read-only hosted check](PRODUCTION_POST_REHEARSAL_READBACK_2026-09-03.json)
at **07:19:32 UTC** confirms a healthy production project with **97 migrations**,
182 Storage objects and nine buckets. Its original four IPv4 rules and empty
IPv6 list are intact; the temporary `.205/32` rule is absent. The Mac's observed
egress has since changed to `.79`, which is not authorized by the earlier
single-IP approval and was not added. An independent disk/container inventory
also found zero remaining recovery mounts or owned drill containers.

## Local checks in this continuation

- Encrypted-volume rehearsal: 16 passing checks (synthetic data only).
- Network/endpoint guards: 9 tests, 29 assertions passed.
- Backup credential escaping / narrow-access guards: 4 tests, 23 assertions passed.
- Restore parsing/ownership/permission-comparison guards: 7 tests, 25 assertions passed.
- Upgrade manifest/projection/append-only guards: 3 tests, 13 assertions passed.
- Container tmpfs credential bootstrap: passed with synthetic input and no network.
- Ruby syntax, Swift warnings-as-errors build and diff whitespace checks passed.

These checks do not replace the prior Flutter, API, database or native-device
evidence and do not certify production payment/provider behavior.

## Remaining acceptance boundaries

A database dump does not contain Storage object bytes, provider configuration,
or all required global-role credentials. This actual database restore closes the
database rehearsal gap, not full-platform/off-site recovery or agreed RPO/RTO.
Key escrow, Storage recovery, matching client/backend cutover, live permission
readback, physical-device/provider journeys and owner acceptance remain separate
gates. No production migration or platform-role activation has occurred here.

The owner has now approved requiring every member/Admin client to update for
this release (reply: “please do that as well”). The reviewed privacy migrations
deny the old name-bearing profile APIs; the matching client uses replacement
allowlisted APIs. Legacy-client compatibility is not a cutover blocker. This
approval is an update policy, not evidence of installed-app distribution or a
minimum-version enforcement facility. Those must not be claimed without proof.

The fresh cutover preflight again found the same 14 reviewed migrations pending,
a healthy production project, and no new preflight errors. Deployment will use
the authenticated HTTPS Management API without adding another database IP rule.

Sources checked:
[Supabase connection modes](https://supabase.com/docs/guides/database/connecting-to-postgres),
[Supabase TLS certificate guidance](https://supabase.com/docs/guides/database/psql),
[official dashboard certificate URL](https://github.com/supabase/supabase/blob/master/apps/studio/hooks/custom-content/custom-content.json),
[network restriction API](https://supabase.com/docs/reference/api/v1-update-network-restrictions),
and [Apple encrypted disk images](https://support.apple.com/guide/disk-utility/create-a-disk-image-dskutl11888/mac).

# Production-readiness continuation — 2 September 2026

Status: **local candidate verified further; production GO not established**.
The existing production target remains COOL / `lhbowpbcpwoiparwnwgt`. No hosted
staging was created. No production migration, role change, provider send,
payment, customer export, Git push or store release occurred in this continuation.

## Fixes made

- Corrected contradictory release checks that required retired name-writing
  profile APIs, legacy platform role-grant APIs and direct financial-table reads.
  Checks now require the current member/Admin/payment contracts, forbid retired
  access and detect column-only financial, profile-name and private identity grants.
- Fixed explicit-index checking for `collect_hybrid` and `collect_admin_access`.
  An unqualified index belongs to its table's schema, not necessarily `public`.
- Added migration `20260902212721_revoke_official_payee_trigger_execute.sql` to
  remove the unnecessary public grant on the official-payee trigger function.
  The route-lock trigger is unchanged and its rejection of a MoMo route change
  was verified. A public trigger-function grant was unnecessary; this is not a
  claim that a caller could directly execute a trigger as an ordinary RPC.
- Adapted combined test fixtures to consume generated Collect IDs without
  changing immutable IDs or disabling guards. Synthetic platform operators use
  approved phone identities, roles and fresh sessions; ordinary group owners do not.

## Fresh evidence

| Check | Result |
| --- | --- |
| Flutter suite | 552 tests passed |
| Flutter analysis | No issues |
| Clean local migration replay | All 111 files applied in order; exact file hashes recorded |
| Combined migration-order check | Application function bodies, ACLs and owners match between the combined upgrade and clean replay |
| Platform Admin SQL | 54 assertions passed |
| Ordinary group creation / group-admin contract | Passed, without platform WhatsApp pre-approval |
| Hybrid registry / receipt SQL | 33 assertions passed |
| Readiness/index/negative-access integration | 11 tests, 72 assertions passed |
| Index inventory unit tests | 3 tests, 4 assertions passed |
| History review helper unit tests | 3 tests, 10 assertions passed |
| Hosted preflight helper unit tests | 7 tests, 29 assertions passed |
| Static migration validation / shell syntax / diff whitespace | Passed |

The [clean replay](COMBINED_CLEAN_REPLAY_2026-09-02.json) starts from a new local
Supabase platform with only the synthetic owner needed by the public reference
group seed. The [combined SQL results](COMBINED_UAT_2026-09-02.json) use rolled-back
synthetic fixtures. No signed-in user simulator or production customer data was used.

The [current logical restore](COMBINED_RECOVERY_2026-09-02.json) covers the
111-migration candidate. All 113 fingerprinted application/Auth/Storage/private
tables, sequence values and the checked schema/ACL/ownership definitions matched.
A synthetic RWF 1,234 contribution was verified through the restored ledger,
balances, roster and bounded-history APIs. Archive SHA-256:
`b0a32839d26b2e1df6ca9ed9ffdfcf7e7a6555dc1adc4d23555fa685ebaead02`.
The archive is private, outside Git, and contains synthetic data only.

The first restore exposed pg_cron's database-name restriction; the second
fingerprint attempt exposed an overly restrictive identifier check for Storage
table names containing digits. Both test-harness issues were fixed. The dedicated
local scheduler stayed disabled, no extension was omitted, and its database-name
setting was restored to `postgres`. This remains a same-cluster drill: it does
not cover production backup availability, off-site recovery, Storage object
bytes, external provider configuration, or real-world recovery-time guarantees.

## Current production readback

The [fresh hosted capture](SUPABASE_PREFLIGHT_CURRENT_2026-09-02.json), started at
21:31:31 UTC, confirms **97 deployed / 111 local / 14 pending migrations**, a
healthy project and no preflight request errors. The new hardening migration
accounts for the increase from the earlier 13 pending files. No listed backup
was returned; PITR remains disabled and WAL-G enabled. Network restrictions
were unchanged. Google Drive credentials stayed out of reports and Git.

[Detailed historical review](HISTORICAL_MIGRATION_REVIEW_DETAIL_2026-09-02.json)
confirms that versions `202605230012`, `202605230013`, `202605230014` differ in
stored SQL content as well as name. The obsolete helper functions created by
that older remote history are absent from production, consistent with their
explicit retirement in `202605230016`. This does not prove full semantic/schema
equivalence. Keep the old history intact; do not reapply those versions or
silently mark replacement SQL as already executed.

## Next production step

Supabase migration/deployment work is already authorized. The immediate pending
owner question is permission to create an encrypted production recovery copy
outside the repository. A local synthetic restore is not that copy. Do not
enable paid PITR, relax network restrictions or export customer data silently.

After recovery is available, finish the production schema/manifest comparison,
coordinate the matching name-free client/backend cutover, apply the exact pending
set and read back the changed contracts. Activate only the already selected first
platform Admin identity (Collect ID 965511, verified phone ending 8248) using the
controlled bootstrap and a new sign-in. Do not approve other existing operators
automatically. Ordinary group creation and group-admin rights remain independent.

Current signed-client, physical-device, OTP, SMS/USSD, push, two-client realtime,
provider, recovery-operation and store/owner acceptance gates still require
their own evidence; this continuation does not convert local passes into GO.

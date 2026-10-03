# Candidate source contract — affected local acceptance

The existing encrypted database/role backup and isolated restore callers now
accept explicit candidate-bound source and catalog identity. The current restore
path accepts all three archive/extension inputs instead of fixed historical
reports. The unchanged historical invocation retains its historical scope.

Separate actual unit executions passed 13 contract cases, 4 existing backup cases
and 7 existing restore cases, with terminal exit 0 and no failures/skips. The fresh
network-none PostgreSQL17.6 synthetic round trip passed 27 distinct checks and
56 recorded commands, including permission/owner/RLS/body/default-ACL/member/FK
drift, dynamic namespace coverage, exact restored catalog, and separately matched
data values. These are affected scopes, not a whole-candidate test aggregate.

The eight technical inputs remained unchanged throughout the successful database
proof; the nine affected inputs were then checked before/after the final unit
commands. Subsequent usage-document wording changes are retained separately and
do not change the eight technical test inputs. Original caller/test bytes and modes were preserved. Five failed
attempts remain, covering NULL/default ACL representation, unsupported Ruby
filter_map, omitted implicit-public declarations and rebuilt internal OID names.
All 12 task-owned containers were removed. Runtime metadata records the actual
Ruby 2.6.10 and pinned PostgreSQL image. The unchanged network helper is captured
as a transitive input; its hash was observed after the checks.

Source/query hashes and exact migration versions are checked before credential
or vault actions, and checked again after capture/restore. Catalog ACL defaults
are expanded without removing permissions. Logical foreign keys remain compared
and mutation-tested while rebuilt TOAST/internal FK-trigger names are excluded.
The dump remains whole-database with owners/ACLs; role passwords remain omitted.
Before/after catalog reads and roles/database captures are separate snapshots.

This packet observes 203 migration source identities and does not replay them.
It opens no hosted connection, production encrypted vault or credential store.
The current receipt/worker financial dataset, native/scheduler joined archives,
durable inactive stop overlay, incident drills, Storage/provider recovery,
RPO/RTO and actual release acceptance remain open.

- [Command receipts](unit-command-receipts.json).
- [Source and scope verification](validation.json).
- [Successful database command/case receipt](catalog-uat-attempt6/result.json).
- [Caller usage and recovery limits](../../../platform/CURRENT_CANDIDATE_RECOVERY.md).

# Database QA checkpoint

Latest continuation: [EDGE_CHECKPOINT.md](EDGE_CHECKPOINT.md) records schema
126, 94 PostgREST checks, 66 Edge HTTP checks and the OTP repair. The schema125
evidence below is retained as its historical checkpoint.

Subsequent evidence: [API_CHECKPOINT.md](API_CHECKPOINT.md) records 82 passing
HTTP authorization checks on a copy of this same schema 125, persisted effects,
cleanup and another verified PostgreSQL shutdown. The SQL/concurrency results
below retain their original scope and source bindings.

14 September 2026. Execution remains active. The latest current-schema run
passes **all 21 selected SQL suites**. These are isolated SQL results; complete
backend/API coverage, hosted deployment, provider outcomes and mobile acceptance
remain open.

## Current evidence and repaired fixtures

The task-owned PostgreSQL 17.6 fixture retains the same container, image,
internal network and exclusive writable database volume. Its 125-migration
state remains the recorded **124 clean migrations plus one bounded upgrade**.
This is not an uninterrupted 125-migration replay.

The complete `backend-continuation/sql-all-current/report.json` batch records
21 passes, source/SQL/log hashes, explicit rollback and unchanged before/after
counts. Each suite ran in a newly created copy and all copies were removed.
Final caller review removed extra database-name assertions from two shared SQL
files because their existing launchers select their targets; the full-stack
runner retains its strict ownership/replay/copy guards. Those two suites were
rerun after the change. `sql-current-coverage.json` binds the 19 unchanged batch
cases and two focused follow-up cases to all 21 current source hashes on the
same 125-migration schema. It does not claim a second full 21-suite invocation.
Historical batch source snapshots match their recorded hashes.

FQA-026 is now fixed locally. The four previously incomplete fixtures pass:

| Suite | Repair and retained checks |
| --- | --- |
| `hybrid_backend_uat` | Preserves the required bootstrap account, measures fixture deltas, uses a WhatsApp-approved operator with a session created after role grants, and checks the current private-function access boundary. Onboarding gating, idempotency, atomic roster errors, identity reservation and raw-receipt immutability remain tested. |
| `hybrid_directory_presentation_uat` | Changes only its four synthetic accounts, scopes directory searches/counts/order to named fixture records, and preserves approval/revocation, phone masking, pagination and anonymous denial checks. |
| `group_creation_journey_uat` | Uses consumed synthetic SMS capabilities and the service ingestion/finality functions, plus a current approved reviewer session. Ordinary creation/join, receiver restrictions, payer identity, private publication rejection, share rotation and removed-member denial pass. |
| `local_backend_privacy_lifecycle_uat` | Completes attested payment finality, current observed-receipt deduplication, exact credits, receiver privacy, deletion/support request isolation and audit access checks. |

Both financial journeys now explicitly prove that matching first creates a
**review candidate with no ledger credits**. Finality is a separate service
operation. Retrying matching and finality preserves one posted payment and one
group/member credit pair. The fixture mints synthetic verification evidence;
it does not establish a real Play Integrity, device or provider result.

The initial four failures, intermediate failures and passing reruns remain in
separate evidence directories. No production control was relaxed to make a
legacy fixture pass.

## Confirmed roster repair retained

FQA-025 reproduced 14 failures across 48 checks on the 124-migration state:
general group-read permission exposed member rosters to public-group outsiders
and unrelated platform operators. The local migration
`20260914165641_restore_member_roster_membership_boundary.sql` restores
owner-or-active-member access, including valid linked/claimed member records.

All 48 access checks pass, and all direct consumers are included in the new
21-suite regression. Roster contents, API signatures, contribution visibility
and grants are preserved. No hosted migration was applied.

## Committed concurrency and recovery

Two callers were observed waiting on the same database barrier before release.
Both transactions then committed; this verifies overlap instead of inferring
it from client launch times.

- Concurrent join: exactly one active membership, one join audit and one
  queued owner notification; zero payments or ledger entries.
- Concurrent attested finality: exactly one posted payment, one provider
  confirmation, two legacy credit rows, one journal receipt and two balanced
  journal lines. The tested amount was RWF 1,234: both the journal debit and
  credit total RWF 1,234. Both callers received the same posted payment.

The finality adapter's first attempt had a psql escaping error. That failed
attempt, its source snapshot and SQL/logs are retained; the corrected attempt
passes. Every concurrency copy was removed, and the original bootstrap
baseline remained unchanged. No notification left the internal fixture.
These are two SQL races, not complete crash/retry/out-of-order/provider coverage.

A later Docker stop returned exit 137. It was not classified as a clean
PostgreSQL shutdown. The fixture restarted successfully with the same baseline,
completed primary recovery, and retained disabled scheduled/network workers.
The focused attested-finality SQL suite passed again after recovery. PostgreSQL's
own `pg_ctl` shutdown then completed its checkpoint and logged that the database
was shut down; the container exited 0. The exec client ended 137 as the container
closed, so the server outcome is established by state/log readback rather than
that client code. The stopped fixture volume is retained. No database volume
was removed.

## Advisor observations

The repository's pinned [Supabase CLI v2.101.0 advisor query](https://github.com/supabase/cli/blob/v2.101.0/apps/cli-go/internal/db/advisors/templates/lints.sql)
ran read-only with the actual configured API schema, `public`. Its downloaded
bytes match the existing pinned SHA-256. No claim of latest-version or hosted
advisor parity is made; the attempted v2.115.0 raw paths returned 404.

The query returned **zero ERROR, zero WARN and 230 INFO entries**:

- 46 tables with RLS and no policies. All 92 table/role combinations deny
  direct table privileges to `anon` and `authenticated`; both roles lack
  superuser/RLS-bypass rights. This is consistent with their server-only
  access boundary, not a reason to add browser policies.
- 93 foreign keys without covering indexes. These remain candidates for
  representative workload and query-plan review.
- 91 unused-index observations on the bootstrap database. Its lack of
  application traffic cannot justify deleting indexes.

No indexes, grants or policies were changed from these observations.

## QA transport and evidence repair

FQA-034 is fixed locally. Task-target inspection and SQL execution now have
bounded Docker client deadlines, including blocked input and inherited output
streams. A timeout stops only that local client process group and records the
daemon-side outcome as unverified. The default target still must be running;
explicit stopped-target inspection preserves every ownership, local socket,
image, internal network and writable-volume check.

SQL failures preserve partial output, the original error and cleanup results.
An uncertain creation never authorizes a database drop, and failed cleanup
cannot leave a passing report. **64 QA tooling tests / 307 assertions pass**,
including 17 target/command tests and four SQL reporting tests. Other legacy
helpers remain subject to separate discovery and target review.

## Scope limits and provenance

The 21-suite selection is not the complete backend denominator. Uninterrupted
current replay, representative supported upgrades/restore, runtime HTTP/Edge
authorization, broader financial races, workload performance, actual provider
transport and native evidence remain open. Shared free capacity fell from
about 6.4 GiB at restart preflight to about 2.7 GiB later in the batch; stable
native build capacity is still unresolved.

The prior application checkpoint remains **867 Flutter tests passed**. Of its
615 recorded inputs, 614 remain identical; the only subsequent change is the
Makefile line registering the new Ruby SQL-runner test. No Dart, Flutter test,
asset or platform input changed during this backend work. The Flutter suite
was not represented as newly rerun. The user's settings hash is unchanged.

Raw evidence is under `.cache/fullstack-qa/20260914T151002Z/`:

- Original bootstrap/replay: `database-full-bootstrap-readback.json`,
  `database-clean-replay-with-auth.json`, `database-roster-upgrade.json`,
  `database-current-replay-chain.json` and the original SQL attempt directories.
- Current continuation: `backend-continuation/`, including all SQL attempt
  reports, concurrency adapters/source snapshots, advisor query/readbacks,
  source checkpoint, command tests, target lifecycle and recovery records.
- `results.json` in this plan directory indexes checks. The continuation's
  manifest records retained file hashes; historical failures stay distinguishable
  from current passes.

The goal remains active. No production deployment, migration, external message,
store action or release approval occurred.

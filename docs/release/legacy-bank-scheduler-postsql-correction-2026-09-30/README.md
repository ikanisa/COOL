# Scheduler snapshot correction after first SQL attempt

Status: **helper corrected and source checks passed; SQL retry remains root-owned**.
This packet records a correction to the isolated acceptance helper. It does not
claim that the corrected helper, migration143 or its UAT passed PostgreSQL.

## Observed failure and exact correction

The root agent reported that the first pre143 snapshot failed at exact142, before
migration143 was applied; its transaction rolled back. In
`pg_temp.scheduler_upgrade_snapshot()`, the static cron-history aggregate used
unqualified `h`, which conflicted with the function's local `h text` variable.
The SQL statement now uses `hashes.h` for both the aggregate value and ORDER BY.
The correction is exactly one source line; no snapshot output field or digest
algorithm changed.

Corrected helper SHA256:
`076a3618bbedd628ba464118a25cc9a7686bd24021698585b1e6b09d20554e07`.

The variable/column review also checked:

- The business-table digest query is dynamic SQL in a quoted string; its `h`
  column is parsed separately and is not substituted as the PL/pgSQL variable.
- Namespace references `n.nspname` are qualified table aliases, while the local
  scalar `n` is used as the dynamic query's INTO target and JSON row count.
- The receipt query is also dynamic SQL. The remaining static cron-job fields
  have no matching local variable names.
- The rollback UAT's business snapshot uses the dynamic query form; the reported
  static-history ambiguity is not present there. Migration143's query references
  use record aliases rather than an unqualified local `h` identifier.

## Preservation

The original source packet remains unchanged at
`docs/release/legacy-bank-scheduler-retirement-2026-09-30/`.
Its artifact manifest SHA256 remains
`442406af246108ac06926e290b513e7fb9572167c273cefc59cec2bd83b857de`;
all18 recorded artifacts still match. This new packet retains the failed helper
source under `prior-source/` and corrected source under `source-snapshot/`.

Unchanged migration143 SHA256:
`a3e29f1314a4a94d1ef2bd19709aa745dca5f0e456bb70dab769d6b42c92ba85`.
Unchanged rollback UAT SHA256:
`a190bffc1212c410a200e6b99d4db6910bf0cea5d948f535e7bb1640c4d25952`.

## Focused checks and their limits

The new five-test source regression binds the exact one-line correction, checks
that the static aggregate qualifies both references, verifies the original packet
and frozen migration/UAT hashes, and preserves exact142/143 isolated guards and
rollback behavior. The nine existing retirement source tests and nine comparator
tests were rerun. Runtime versions, exact commands and outputs are retained in
`verification.json` and `logs/`. Source copies and packet artifacts are hashed.

These checks establish source consistency and comparator behavior. They cannot
establish PostgreSQL parsing, name resolution, cron permissions or upgrade
acceptance. The original source suite passed before the actual SQL attempt exposed
this ambiguity, so its earlier success must not be presented as SQL validation.

Root retains the original failed stdout/stderr/execution evidence and backup. The
worker did not run a database command or alter that evidence. Root must rerun the
corrected pre143 snapshot, then perform the separately authorized143 apply,
post143 preservation comparison, rollback UAT and full migration replay checks.

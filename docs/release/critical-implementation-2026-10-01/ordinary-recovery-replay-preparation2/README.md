# Candidate2: exact source-role prerequisite for local logical recovery

Prepared and focused-tested only. No Docker, dump, restore, migration, network or
provider operation has run from this candidate. Execution remains with root after
review of `rehearsal.py`, its exact hash, `inputs.json` and the updated command/SQL
scope. This proposal does not create an admission decision or change shipping
PostgreSQL admission.

The retained candidate1 execution passed 11 cases in 92.515 seconds and then
failed at the archive's `GRANT USAGE ON SCHEMA net TO supabase_functions_admin`.
Its dump seal remained intact and both owned containers were removed. The complete
137-file failure cohort, retained root readback, and every preparation1 byte and
seal are checked before and after this preparation. No historical file is rewritten.

The source predecessor contains 30 roles, 23 membership rows and 8 settings rows.
The missing role has this exact admitted source row, in the existing collector's
order: name, superuser, inherit, create-role, create-db, login, replication,
bypass-RLS, connection limit, valid-until, role-config hash.

```json
["supabase_functions_admin",false,false,true,false,true,false,false,-1,null,"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"]
```

The single-database dump excludes cluster globals. The actual failure demonstrates
that the admitted image fixture alone does not supply every source role. The role's
creation provenance is not inferred from its name or ACL: the observed committed
source and frozen predecessor are the admission evidence. The local prerequisite
uses only this fixed statement, with no password or customer credentials:

```sql
create role supabase_functions_admin with nosuperuser noinherit createrole nocreatedb login noreplication nobypassrls connection limit -1;
```

The candidate extracts the exact `roles`, `memberships` and `settings` expressions
from the hash-bound, unmodified catalog query and wraps them in a read-only repeatable
read transaction. It records actual source and restore role names and complete rows.
The committed source projection must equal the frozen source. After extension and
database prerequisites, `postgres` is demoted before the restore projection is read.
Only the observed role may be missing; unknown missing or extra roles, any differing
attribute, membership or setting refuse before archive restore. If that role already
matches, no role SQL is issued. After optional creation, all 30 roles and every
membership and settings row must exactly match the source before `pg_restore`.
An existing mismatched role is refused rather than altered. No other global is repaired.

The 216 source inputs plus four reference files are copied byte-for-byte into the
fresh private cache `/Users/jeanbosco/Library/Caches/COOL-ORDINARY-RECOVERY/20261002-candidate2`.
All 209 original migrations, the 124+85 split, 18 fresh committed fingerprint
projections, complete predecessor/final catalog comparisons and the current209 final
whole-file SHA `4516b26ba34a426a2d97af40e7f2675d9a8f55de274f159b6da40fded1c0084c`
remain bound. The final comparator retains every category and effective ACL.

The fixed 600-second whole-program limit retains its 540-second execution budget
and 60-second cleanup reserve. Tool input/stdout remain bounded to 64 MiB, stderr
to 1 MiB, and each command is limited by the remaining budget. Ownership labels,
cached immutable image, network-none, no ports/host mounts, 1 GiB tmpfs, disabled
cron/net dispatch and owner-checked cleanup are unchanged. Dump/restore runs use
the recorded actual absolute in-image 17.6 tool paths and freshly checked bytes.
Application migrations remain `postgres NOSUPERUSER`; restore remains the explicit
local synthetic `supabase_admin` fixture operation.

The original ten test-method ASTs are unchanged. Eight added tests cover the exact
observed prerequisite, no mutation when already exact, unknown missing/extra roles,
all role attribute mismatches, unadmitted source attributes, membership/settings
drift, malformed/duplicate rows and exact read-only expression extraction. The
focused suite passes all 18 tests under the absolute Python interpreter with `-I -B`
and a clean environment. This is parser and bound evidence; it does not establish
that the proposed restore completes.

The fresh proposed runtime output is `candidate2/docs/release/committed-recovery2`.
`command-scope-matrix.json` contains the exact reviewed command shape and new role
SQL/read-only scope. A separately retained review decision must bind the new code
and manifest hashes before execution. The candidate cannot authenticate a reviewer.

Full BE-08, hosted/system recovery, ARC-08 restore adapter, ARC-11, business authority
and release/production acceptance remain open. No maintained source, SQL, migration,
canonical register or prior generator packet was changed.

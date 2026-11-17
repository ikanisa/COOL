# Retention migration convergence candidate

`user-id-forward-candidate.sql` is a forward-only candidate for a retention
helper that was already recorded on the local source. It preserves that
migration's historical bytes and accepts the bounded user-ID format used by
Collect's application validator. The SQL requires the original exact function
body and authority, one fenced controller, the expected postimage and unchanged
owner, ACL and search path. It rejects reapplication. It has not been installed
in `supabase/migrations`, applied to either active database, or qualified for
production. It does not repair the separate migration-order divergence.

The focused test uses an owned, socket-only PostgreSQL 17 fixture with synthetic
rows. It checks the previous failure, fence and function-authority refusal,
positive-only blocked retention result, invalid inputs, runtime-role guard,
postimage and replay refusal. Run it with:

```sh
node --test --test-concurrency=1 scripts/supabase/retention-convergence/user-id-forward.test.mjs
```

A separate synthetic full-schema experiment exercised this forward candidate
on both observed retention lanes; it did not include the WIP Admin migrations,
connect to Supabase, or establish a complete migration or recovery. The bounded
ID syntax covers current application IDs, not every string allowed by the
underlying text column. Before promotion, classify historical IDs, freeze and
reconcile the shared source, solve the six-file migration-history fork, pin the
final sources and actual managed preimages, and test the complete ordered chain.

`managed-branch-1100-candidate.sql` and
`managed-branch-1102-candidate.sql` are the exact experimental variants tested
on the synthetic branch that includes migrations 303–308. The first changes
preimage pins for that branch; the second also verifies that the Iceberg schema
extension already exists before adding the separate inspection descriptors.
The synthetic result retained the existing combined Iceberg class, both new
classes and four blocked native-work classes. Its tests rejected a changed
predecessor and changed Storage schema. These files are not interchangeable
with the original 1100/1102 sources already recorded locally; copying either
into the migration chain or registering an unexecuted source as executed would
misrepresent history. The variants, actual managed catalogue, retention
semantics, local forward convergence, operator and the complete ordered chain
need independent qualification before any live use. The synthetic run skipped
the WIP Admin migrations and does not prove hosted compatibility or release.

## Complete synthetic ordering probe

`ordered-chain-fixture.mjs` constructs a fresh, owned, Unix-socket-only
PostgreSQL 17 fixture from the original 16 synthetic source positions and then
executes all 49 later source positions in order. It pins the 58-file reviewed
lock, the seven later unreviewed source files, the two managed-branch variants,
the forward-ID candidate and the synthetic Storage fixture. The historical
realtime migration uses its existing reviewed metadata-only synthetic binding.
For each of the two divergent retention positions, the probe first requires
the original source to refuse its actual predecessor and roll back before it
executes the corresponding candidate. Both unfinished Admin migrations run only
inside the fixture, and the MFA policy remains disabled. The postconditions
check the four blocked native-work classes, all three Iceberg classes, a normal
non-superuser owner, and fence release. It does not create or write a Supabase
migration-history table. The fixture and its synthetic credentials are removed
only after confirmed shutdown.

```sh
node --test --test-concurrency=1 scripts/supabase/retention-convergence/ordered-chain-fixture.test.mjs
```

The seven newer source files and branch candidates remain unapproved, despite
their exact byte pins. The fixture's Auth, realtime, Storage and deployment
identity differ from the hosted provider, and it tests neither the current
managed catalogue nor the migration operator, full retention behavior, live
admissions, customer data or Android. In particular, a passing run is not an
authorization to deploy or to record either unexecuted original migration as
applied. The source-installation and managed histories still diverge and need an
explicit, honest history strategy and an independently reviewed operator.

## Non-executable history candidate

`history-plan.mjs` computes a read-only candidate for a **separate managed
migration set**. It expects canonical JSON and a supplied SHA-256 for exactly
14 observed history rows, each containing `version`, `name`,
`statement_count` and `source_sha256`. All 14 must exactly match the pinned
repository prefix. The candidate keeps the original source versions
`20261114110000` and `20261114110200` absent from the managed history and
proposes distinct, ordered versions `20261114110001` and `20261114110201` for
the respective variant bytes. It proposes `20261114110400` for the forward-ID
candidate. It reports 52 pending actions, including those three candidates,
and flags both Admin migrations as work in progress. Versions are proposals,
not allocated or recorded history.

The supplied observation and digest are assertions, not proof that they came
from the project, that the target is fenced, or that an executor is safe. The
function creates no SQL files, database connections, or history records and
returns `execution_supported: false`, `source_directory_push_safe: false` and
`production_authorized: false`. A real execution still requires independent
review of the version choices, actual managed preimages, authoritative source
and target histories, complete backup/recovery, an atomic qualified operator,
and the WIP features. A standard push from the source migration directory
would see the divergent originals and is not qualified for this branch.
Supabase documents timestamp-ordered migration files and remote history in its
[local development workflow](https://supabase.com/docs/guides/local-development/cli-workflows).

```sh
node --test --test-concurrency=1 scripts/supabase/retention-convergence/history-plan.test.mjs
```

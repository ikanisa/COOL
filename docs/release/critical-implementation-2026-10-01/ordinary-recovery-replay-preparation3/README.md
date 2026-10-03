# Candidate3: source GraphQL extension-member restore prerequisite

Prepared only. No Docker, database query, dump, restore or migration has run from
this candidate. Root retains review/admission and actual execution responsibility.
The prior candidates, their seals, and both actual failure cohorts remain immutable.

Candidate2 passed 13 cases in 74.769 seconds, including exact equality of all 30
source/restore roles, 23 memberships and 8 settings. Its next archive ACL failed
because `graphql_public.graphql(text,text,jsonb,jsonb)` did not exist. Both containers
were removed with no cleanup errors. This is a retained failure, not a recovery pass.

The frozen schema-only source's `extensions.grant_pg_graphql_access` hook contains
the exact missing SQL wrapper. Its body SHA matches the declared source function
row. The effective catalog independently records the wrapper as a `pg_graphql`
extension member: `deptype=e`, not an inferred relationship from an ACL or name.
The source hook, event trigger, wrapper identity/owner/attributes/ACL/body/definition,
schema ownership/ACL and both wrapper dependency rows are admitted explicitly.

- Wrapper identity: `graphql_public.graphql("operationName" text, query text, variables jsonb, extensions jsonb)`.
- Owner: `supabase_admin`.
- Wrapper body SHA: `03b36c9655c8688b452fba90346ce43dafa2ded68bffb9250da6c236133d467e`.
- Function definition SHA: `22e0e26950cfdf51038425ad17051de3fb19bc7afa72edefda05c2da3e0d8bb2`.
- Hook body SHA: `ad8bfb866513170056bbc1f817103be550cd62efcb589fa2a3807718efb3eb6a`.

The latter definition hash comes from `pg_get_functiondef`; it is not merely a
role-config hash. Unknown wrapper overloads, altered source body/definition/owner,
unproved extension membership, altered hook/event-trigger provenance or substituted
SQL refuse before any container is created. The hook extractor selects only the
admitted grant hook, retaining its nested wrapper's body bytes. It does not select
the separate placeholder wrapper from the source file.

The retained TOC places the wrapper ACL at line 255, before table data. Rather than
assuming section filtering defers that ACL, the candidate uses the permitted narrow
prerequisite: create the exact source-owned `graphql_public` schema, create the exact
wrapper as `supabase_admin`, then add its proven `pg_graphql` extension membership.
The wrapper statement uses CREATE rather than CREATE OR REPLACE to refuse an
unexpected concurrent definition. Its body and canonical function definition remain
the admitted source values. Only the already satisfied schema CREATE is newly
commented in the TOC. The wrapper ACL, schema ACL, all data, all original migration
history, all other DDL and every other ACL remain intact.

The read-only wrapper projection reuses the frozen collector's exact schema,
function and dependency expressions and CTEs. It can run before the archive creates
the migration table. Actual source/target wrapper rows and dependencies are retained.
An existing wrapper must have the exact admitted identity, owner, body, definition,
attributes and dependency cohort; otherwise restoration refuses. Preliminary ACL
admission permits only the exact default new-function ACL or final source ACL, since
the complete archive applies final grants. This preliminary condition does not
normalize or omit ACLs from any catalog comparison. An unexpected ACL is refused.
The exact wrapper/extension membership must be read back before `pg_restore`.

The fixed source-role prerequisite from candidate2 remains. All 30 role attributes,
memberships and settings are still checked before archive restore. The final and
restored-predecessor comparators remain unchanged and require the complete catalog
and every effective ACL. All 18 fresh committed projections must survive restore
and each of the 85 pending original migrations. All 209 original SQL hashes and
the 124+85 split remain bound to the existing current209 proof. The final whole-file
catalog SHA remains `4516b26ba34a426a2d97af40e7f2675d9a8f55de274f159b6da40fded1c0084c`.

The private candidate is
`/Users/jeanbosco/Library/Caches/COOL-ORDINARY-RECOVERY/20261002-candidate3`, with 216
source and four reference files copied byte-for-byte. Both earlier preparations
and both actual failed executions are checked before and after: 313 files, including
all 137 actual1 and 141 actual2 files. The proposed fresh runtime output is
`candidate3/docs/release/committed-recovery3`. No historical output is reused as
fresh execution or overwritten.

All 18 existing test-method ASTs remain unchanged. Their prior receipt is retained;
the two affected archive tests and seven new GraphQL tests pass in the focused
nine-test run. Unchanged parser and Runner ASTs are also recorded. No broader suite
or Docker rehearsal runs here. The focused tests cover exact hook/body/source
provenance, unknown/mismatched wrappers, substituted SQL, dependency admission,
read-only projection and preservation of every wrapper ACL in the TOC. An additional
readback parses the retained actual TOC and proves precisely one new schema CREATE
comment with all other lines unchanged. These are preparation/parser results, not
evidence that the proposed restore completes.

The whole-program deadline remains 600 seconds (540 execution, 60 cleanup). Tool
input/stdout remain bounded to 64 MiB and stderr to 1 MiB, with command deadlines
clamped to the remaining budget. Exact-image/tool hashes and PostgreSQL 17.6,
owner labels, network-none, no ports/host mounts, 1 GiB tmpfs, disabled cron/net
dispatch, sealed durable dump and verified cleanup are unchanged. Dump/restore
uses the explicit local synthetic `supabase_admin` fixture; application migrations
remain `postgres NOSUPERUSER`.

`command-scope-matrix.json` binds the new code and input hashes, exact source
role/function scopes and proposed command. Root must supply a newly bound retained
review record before execution; this candidate cannot authenticate or create that
review. No shipping restore admission, maintained source/SQL/register change,
business authority, hosted/provider action or production readiness is claimed.
BE-08, ARC-08 and ARC-11 remain open.

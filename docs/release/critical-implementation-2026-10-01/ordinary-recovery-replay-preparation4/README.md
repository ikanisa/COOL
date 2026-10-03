# Candidate4: exact captured source compatibility repairs

Prepared only. This proposal has executed no Docker command, database query, dump,
restore or migration. Root owns code/scope review, admission and actual execution.
All previous preparations and failed executions remain immutable. BE-08, ARC-08
and ARC-11 remain open.

Recovery3 completed pg_restore and passed 15 cases in 78.539 seconds, including
exact role globals and the source GraphQL wrapper's metadata and extension
membership. Its complete restored predecessor catalog comparison failed. Both
owned containers were removed, with no cleanup errors. Forward85 replay was not
reached. See complete-captured-delta.json and DELTA.md for every changed category
and row, including all 13 equal categories.

The new prerequisite is scoped to the exact captured whole source and restored
catalogs. The source whole-file SHA is
6219ca6b2169115eb663e6497f190e9116535b01071ddb5728df5596d432ec2d;
the failed restored whole-file SHA is
b4ae2ac11f2c6c55b0f9510a2e76ac0ba8e1d7b5f3f0a1e9741e14ef0c219846.
Canonical hashes admit the complete metadata content. They are admission checks;
the original complete catalog equality and final whole-file SHA comparisons are
unchanged. An additional ACL, altered owner/body/dependency, unknown index, CHECK
hash or validation flag, changed original SQL, missing object or unrelated delta
refuses. An already exact source catalog needs no repair.

The first explicit transaction runs as the local synthetic supabase_admin. It
adds only source USAGE grants on graphql and graphql_public for postgres, anon,
authenticated and service_role, retaining postgres's source USAGE grant option.
It adds source EXECUTE grants on the six named graphql functions and source
SELECT/UPDATE/USAGE grants on graphql.seq_schema_version to those four roles.
It uses no generic GRANT ALL or function/schema rewrite. The frozen grant hook
proves graphql's grants and postgres's grant option on both schemas. The other
three roles' graphql_public USAGE grants are independently proved by the captured
schema ACL; they are not falsely attributed to that hook. Default ACLs and the
wrapper's ACL already compare equal and remain untouched.

The six graphql functions and sequence have explicit pg_graphql extension member
dependencies in the captured source. Their definition/ACL TOC entries are absent
from the actual3 archive. The frozen source transport prerequisite created
net.collect_receipt_http_response_id on net._http_response(id). Its underlying
table is a pg_net extension member, but the index is not an extension member.
The exact index name occurs zero times in the uncompressed custom dump and TOC.
The proposal reruns only the exact frozen CREATE INDEX statement, after full
metadata admission confirms the known missing index. Its source owner, unlogged
relation/column metadata, valid/ready/live flags, index definition hash and sole
index dependency remain bound. A runtime read-only archive proof also refuses
unexpected entries; it removes or rewrites no archive line.

The second transaction runs as postgres NOSUPERUSER. It drops and readds only
notification_events_copy_length_check and
provider_finality_requests_provider_network_check from the exact BETWEEN
expressions in their original frozen migrations. Their identities and all
validation/deferral flags are admitted. The notification CHECK remains NOT VALID;
the provider CHECK remains validated. The only admitted failed restored hashes
are 74e42a847ff75a14e384b3eaaca4ce27961584e94628a4dadeb2b76bd0a7275e
and 04d7111057711ab49ddb4d03ef63af3f3fe4fae5b66822a288bfad9ab74aa678.
The recreated source hashes must be d39f28d2b96e15bb3abe3c66ef153a22ec19a6381e78c24db1965407925a9e87
and 05c313d4a8d16cf1745983feb6df49956260bf6fa1dc8eaf65ccc10630086d51,
respectively, before proceeding. The comparator does not normalize the deparsed
CHECK text or accept semantic equivalence as parity. Actual re-creation remains
unverified until root executes this proposal.

All 18 fresh restored projection row/hash values must equal the freshly committed
source immediately before and after both compatibility transactions. The complete
restored predecessor catalog must then equal the source, including every effective
ACL. The existing negative wrong-ACL transaction/rollback remains. All 85 pending
original migrations still execute as postgres NOSUPERUSER, with fresh18 checks
after each. All 209 original migration hashes, the 124+85 split and final current209
whole-file SHA 4516b26ba34a426a2d97af40e7f2675d9a8f55de274f159b6da40fded1c0084c
remain mandatory.

The private candidate is
/Users/jeanbosco/Library/Caches/COOL-ORDINARY-RECOVERY/20261002-candidate4.
It contains the original216 source and four reference files unchanged, plus the
two captured source/restored catalogs:222 admitted files. The proposed unique
runtime output is candidate4/docs/release/committed-recovery4. All484 earlier
preparation and actual failed files are verified before and after. No historical
output is overwritten or presented as a fresh result.

All original25 test-method ASTs remain unchanged, including the original18.
Their successful prior18 and prior9 receipts jointly cover those25 methods. Their
fixtures, original source/reference hashes and parser/Runner ASTs remain unchanged.
Only main changes among previous top-level nodes. Nine new affected tests cover
exact repair scope, no-op exact source, unknown metadata/ACL/body/index/CHECK,
frozen SQL substitutions, forged plan SQL/hashes, BETWEEN/validation preservation,
all18 projection enforcement and unexpected archive entries. The clean-environment
absolute Python -I -B child has a20-second process-group bound. No broader test or
Docker rehearsal runs here. Preparation tests cannot prove recovery completion.

The exact cached image, actual17.6 executable hashes/paths, ownership labels,
network-none, no ports/host mounts, 1 GiB tmpfs, disabled cron/net dispatch, durable
sealed full custom dump and verified cleanup remain unchanged. The whole600-second
budget retains540 execution plus60 cleanup,64MiB input/stdout and1MiB stderr;
commands remain clamped to remaining time. All archive ACL/data/history entries
remain byte-for-byte intact under the unchanged restore-list parser. No new TOC
entry is commented. The role and wrapper prerequisites from candidates2/3 remain.

command-scope-matrix.json binds the new code and input hashes and both exact SQL
transactions. Root must supply a new retained review record bound to these hashes.
This proposal neither creates nor authenticates that decision. It changes no
maintained source/SQL/register and makes no shipping restore admission, business
authority, hosted/provider or production-readiness claim.

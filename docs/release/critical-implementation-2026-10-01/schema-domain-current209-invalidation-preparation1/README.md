# Minimal current209 static-lineage invalidation proposal

Private proposal. Only two maintained files are proposed: replace the existing
generator and add the small self-contained focused test. There is no helper,
transform engine,34-case fixture, external dependency or SQL evaluator. Maintained
files, canonical records, APP/SDK, provider state and SQL/Docker were not mutated.

The mapper previously retained static move/rename candidates across unproved
anonymous SQL and unsupported active ALTER signatures. The proposal clears prior
static candidates at every active top-level DO, EXECUTE or CALL. DO bodies remain
opaque, including SELECT/PERFORM routine calls, format fragments and indirect
effects. Unknown or unterminated DO syntax refuses rather than spilling tokens.
Unknown or unqualified ALTER signatures invalidate the literal source and
rename/schema destination names. Names are never resolved through guessed
search_path. A later explicit declaration can start a fresh exact-signature
chain; final body equality does not revive an earlier interrupted chain.

Literal declaration body-hash evidence remains unchanged. Current209 yields
775/902 literal body source matches and zero static matches. The two withdrawn
chains are collect_hybrid.roster_revision_receipt_v149_frozen and
public.collect_operations_legacy_configure_policy_v1; their prior exact source
candidates are retained in the corresponding reasoned review records. There are
127 gaps:36 application/public and91 platform. All84 uncertainty records carry
source path/line/position and the exact migration hash. They appear in the map
and gap output. Runtime/business-owner acceptance and BE-08 completion remain
open. The original34 reconstruction research is sealed separately and unused.

Actual11 focused tests passed in0.088/30 seconds. They cover qualified unknown
ALTER source/destination, schema move, unqualified names, DO at first token and
between declarations/moves, routine invocation, top-level EXECUTE/CALL, safe
unaffected literal/static evidence, a fresh declaration after a barrier, malformed
DO and exact preservation of the original49 test bytes/assertion ASTs. The prior
49-suite proof was reused. Fresh generation passed5.171/30 seconds; independent
recomputation of all five outputs passed5.178/30 seconds. Exact pinned Python
-I -B, clean environment, before/after code hashes and absent process groups are
recorded. No migration/runtime/provider gate was rerun.

The fresh cohort has1,092 input roles and665 caller-source files. Root-side archive
admission was integrated concurrently: pg_archive_admission.py was added;
supabase_cli_helpers.sh and supabase_logical_backup.sh changed. Makefile and the
Postgres architecture document also changed relative to the prior12 snapshot.
These exact deltas and current hashes are disclosed in current-input-readback.json;
the older1,091-role research proof remains historical. Every fresh1,092 hash was
read back after verification. Catalog20/raw2,543/grants4,157, the209 original and
replayed migration pairs, all caller sites and18 seams remain exact. The catalogs
are SHA2564516b26ba34a426a2d97af40e7f2675d9a8f55de274f159b6da40fded1c0084c.

source-integration-proposal.json supplies the exact before/proposed hashes and
bytes. mapper-maintained.diff has only the necessary invalidation/diagnostic
change: existing sql_static_lineage and build change; sql_lineage_uncertainty is
new. All other existing generator function ASTs remain unchanged. Original49
tests and18 seam bytes are unchanged. Root owns two-file promotion, QA registration
and a fresh maintained-source reader. The test derives the sibling generator
from __file__ and reads no historical release fixture.

Generator before:9d9f2aa6ec76cc17d72c3ad2d69cf6e0415aaadb87fb4bac1b64f1cf584a396a.
Generator proposed:28e74753b5d501d66e7b7b37af39fe6f048f1e0c57ff196fc5a4341df1221dd4.
Focused test:7d4ffacb9b66dedaf12b07bf867b2bdc77de6134ce0867990c2f857a56c2c58a.
The unchanged original49 test:ed9698015a6b290bf4af3f877fa6ca5ce37da9555ce175f76e3ecfa06f990ce4.

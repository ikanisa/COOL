# Current style and seam mapper refresh

Fresh generation and full independent verification passed, in 3.5338 and 4.0422
seconds respectively, with an actual whole execution of 7.7357 seconds. Each
command retained its original 30-second limit inside a finite 80-second whole
budget. The original generation and verification argv from
`root-schema-current-refactor-refresh1` were reused exactly, changing only the
output directory to this packet's `generated-current209`. Both process groups
are absent; neither command timed out or was retried.

Verification independently recomputed all five semantic outputs and checked
1,093 input bindings, 2,543 catalog objects across 20 preserved categories and
4,157 grant records. The map includes 666 maintained source files, 718 caller
sites, 18 reviewed caller seams and 4,754 SQL reference sites. Both ordinary209
catalogs match the current 209 migration names, and all 209 captured migration
bytes match their current source files. Every bound input's bytes and mode remain
unchanged before/after this held execution.

The unchanged mapper is SHA-256
`28e74753b5d501d66e7b7b37af39fe6f048f1e0c57ff196fc5a4341df1221dd4`.
The reviewed `admin-rpc-map` binding now correctly records current source hash
`1a2829bf8e2a2b6734ed1a65dd7248a31584f3f5bdd4c70425c9eaccae6edc9b`
and anchor line 978; its registry SHA-256 is
`538066a32db342b049fa61e55b0adc77df64a3f2e1d4593442d7629584a4d077`.
The prior genuine failed attempt remains intact in
`root-schema-final-format-refresh1`; this fresh packet does not revise that record.

Relative to the previous successful current-refactor refresh, input hash changes
are confined to the two owner-reported formatted Dart files, the updated browser
QA script and this exact reviewed-seam registry binding. Catalog objects, grants,
SQL references, summary counts and gap counts remain unchanged. The lexical
caller inventory contains 48 line/offset shifts across the two Dart files and two
changed display-expression excerpts caused by their new formatting. All caller
symbols, candidate targets, resolutions, groups and authorization fields remain
unchanged. `caller-record-deltas.json` preserves every actual record difference;
it does not infer runtime equivalence or authorization from display excerpts.

Pending SQL CI dependency scope was checked before execution. The CI workflow is
outside mapper scan roots and is not an explicit input. SQL fixture metadata and
its bootstrap SQL under `scripts/tests/fixtures/ordinary_installer_v1` are excluded
by the unchanged mapper's tests/fixtures pruning and source-extension rules. Both
strict-analysis style files are outside admitted mapper inputs: `test/support`
is outside scan roots, and `scripts/tests` is pruned. However,
`scripts/qa/run_sql_ci.py` would be admitted as a maintained Python script if
promoted. It was not maintained before or after this run, so the held mapper source
set remained unchanged. Its later promotion would change that set and would be
detected by the mapper's existing strict verification. The exact scope readback
is recorded in `dependency-scope-before.json` and `dependency-scope-after.json`.

The map remains **draft-with-open-mappings**. There are 775 exact function-body
matches among 902 functions. The 127 functions without an exact body match include
36 application/public functions and 91 platform functions. Existing gap counts
are 74 unclassified objects, 58 unresolved callers, 84 lineage uncertainty records,
318 SQL resolution review records and zero unrepresented migration sources.
Business maintenance ownership and a complete runtime call graph remain
unverified, as recorded by the mapper.

The valid previous 49 mapper tests plus 11 focused lineage-invalidation tests were
reused with their recorded source hashes and successful receipts. No mapper tests,
current209 SQL, unchanged39 Linux-admission suite, APP or SDK operation was rerun.
This refresh wrote only this new private evidence packet and the verifier's owned
temporary recomputation directory. Maintained source, prior evidence and databases
were unchanged. `result.json`, command receipts, before/after input bindings and
the five generated outputs contain the actual current readback; this packet makes
no release or provider acceptance claim.

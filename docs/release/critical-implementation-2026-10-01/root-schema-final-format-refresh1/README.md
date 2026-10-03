# Failed final-format mapper refresh and private binding proposal

The actual generation command exited 2 after 3.3678 seconds with
`reviewed source seam drift: admin-rpc-map`. Its original generation argv was
reused exactly, changing only the output directory to this packet's
`generated-current209`. The 30-second command limit and finite 80-second whole
execution budget were retained. It did not time out, and its owned process group
is absent. No retry was performed.

Generation refused before producing the five required output files. Independent
verification was not invoked because its generation prerequisite failed. This
packet does not claim that the current mapper passed. Current caller counts,
body matches and gaps were not admitted or independently verified by this attempt;
the prior verified summary remains historical context in the previous packet.

The maintained mapper code is unchanged at SHA-256
`28e74753b5d501d66e7b7b37af39fe6f048f1e0c57ff196fc5a4341df1221dd4`.
All 1,093 existing input bindings were checked before and after the attempt and
remain stable. Relative to the prior current-refactor refresh, only the mapped
input hashes of `lib/admin/core/admin_runtime.dart`,
`lib/admin/core/admin_receipt_repository.dart` and
`scripts/admin_pwa_browser_qa.mjs` changed. Root identified the Dart changes as
formatting and the browser changes as route/selector updates. The two original
observed ordinary209 catalogs are equal and unchanged; all 209 captured migration
files remain byte-identical to the current 209 migration sources. No SQL was
executed.

The failure is a stale audit binding in
`scripts/audits/collect_schema_domain_caller_seams.json`. Its `admin-rpc-map` case
still binds the archived pre-format source hash
`ca7d9e8652ec4a69fae11fac3f7540647f128bfda4ff2db1f3ff099f3fb7e28a`
and anchor line 979. Current source hash is
`1a2829bf8e2a2b6734ed1a65dd7248a31584f3f5bdd4c70425c9eaccae6edc9b`;
the exact existing anchor occurs once at line 978. The entire 21-line `rpcMap`
method is byte-identical between current source and the archived pre-format
source, with method SHA-256
`eb5d7644e3c57f40182784e80baf753ad6b0292d83c78398baaf5be0cac9bc44`.

The private `proposed/` file changes only this case's `source_sha256` and `line`.
All 18 cases, their semantic observations and reviewed targets remain intact;
the other 17 cases are exactly unchanged and currently bind their source hashes
and anchor lines. `authorization: not-inferred` is retained. Original registry
SHA-256 is
`7288cf27614bfff4a19b3e364141c5de181362cf6a5562b990859cdf5e6ee2bc`;
proposed SHA-256 is
`538066a32db342b049fa61e55b0adc77df64a3f2e1d4593442d7629584a4d077`.
`reviewed-seam-proposal.json` contains the exact before/current records, method
readback, all 18 case checks and root integration boundary. Root owns integration
of this audit-only binding after the held consumer proof and any fresh mapper
attempt.

Previous 49 ordinary mapper tests and 11 focused lineage-invalidation tests remain
applicable: mapper and both test sources match their successful recorded hashes.
`reused60-test-evidence.json` binds those genuine prior receipts; none were rerun.
This attempt changed no maintained source, APP, SDK, database, original catalog,
original migration capture or prior evidence. It did not rerun current209 SQL or
the unchanged39 Linux-admission suite. `result.json` preserves the genuine
failure; `generation.json` and its stdout/stderr preserve the actual invocation.

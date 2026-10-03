# Static function lineage and reasoned source gaps — private preparation 3

This packet is a private code proposal and read-only parse/generate proof against the current 209 captured migrations and effective catalogs. It recovers two exact static renames and keeps 125 unresolved functions explicit. It does not promote maintained source, execute SQL, assign business owners, complete the runtime call graph, or admit a release.

`generator-only.patch` is the proposed maintained generator delta. Its base is the current maintained generator SHA-256 `96a218f211f3ca95e98c87aa934365adbc8e2ebd5c1f944d0400569a105051c9`; the private candidate is `fc734112fe564479d42042717efbd2a915efbf372915fe4eae0119bb8f7d4cef`. The patch SHA-256 is `1faedd9dc217b6ba342e3cb056010c3420057f8848c28a2b13de067f4f2225bc`. Root owns review, test integration and any later maintained promotion.

## Proposed behavior

Only the existing `sql_definitions` and `build` function ASTs change. Five helpers parse identifiers, conservative input signatures, literal alterations, static lineage, and source gap evidence. All other existing function ASTs, catalog admission, normalized grants, caller parsing, source selection, and five-output semantic recomputation remain unchanged. `exact-diff-audit.json` records those boundaries.

The new fallback tracks qualified literal `ALTER FUNCTION ... RENAME TO` and `ALTER FUNCTION ... SET SCHEMA` statements in represented migration order. It requires an exact supported input signature and an exact final catalog `prosrc` SHA-256. Evidence retains the original declaration path, line, declaration hash and body hash, plus every accepted alteration path, line and statement hash. A declaration recreated under the original name does not replace the previously moved declaration. Overloads are distinguished by supported input types. Unknown signatures, conflicting destinations, procedures and literal drops cannot create a lineage match. Unqualified alterations do not imply a search path. Identical bodies under unrelated names are evidence candidates only.

The two newly resolved identities are:

- `collect_hybrid.roster_revision_receipt_v149_frozen(p_revision uuid)`: original declaration in `20260930100000_roster_import_provenance.sql`, line 190; rename in `20260930170000_roster_fresh_auth_recovery.sql`, line 147; final body SHA-256 `5eb422cb484051bed5d446b823e1ffa8c7dd3b127d1446ecfdfdb97eea50c520`.
- `public.collect_operations_legacy_configure_policy_v1(p_request_id uuid, p_expected_revision bigint, p_mode text, p_emergency_stop boolean, p_reason_code text)`: original declaration in `20261001003338_unattended_operating_policy.sql`, line 126; rename in `20261001110000_receipt_operational_authority.sql`, line 228; final body SHA-256 `b6acf58021e71472261025fa46b8015932f7fa88a782f9c98e7e4ba26bcacf11`.

Every prior unmatched function has a `source_match_review` and a corresponding `gaps.json/function_body_match_review` record. These record the required final body hash, literal effective-name candidates, exact static lineage candidates, and same-body other-name candidates. The last set never authorizes a match. The scope labels distinguish platform schemas from application/public schemas; they do not establish an external package owner.

| Reason | Records | Resolved |
|---|---:|---:|
| exact-static-lineage-body-match | 2 | 2 |
| literal-effective-name-body-hash-mismatch | 18 | 0 |
| no-literal-effective-name-definition | 106 | 0 |
| static-lineage-body-hash-mismatch | 1 | 0 |

The original 127 gaps therefore remain covered by 127 review records. Only the two proven renames leave the open list: 125 functions remain unresolved, comprising 91 platform functions and 34 application/public functions. The 27 dynamic roster aliases/wrappers, two dynamically copied application functions, and five dynamically patched application bodies remain unresolved. Dollar bodies and execution strings stay opaque; no SQL is evaluated or normalized to erase a body mismatch.

Signature support deliberately covers only explicit builtin input types used by the proven moves. Arrays, quoted/user-defined types, unsupported aliases, OUT/INOUT/VARIADIC modes and other unrepresented syntax remain unresolved. Literal drops invalidate tracked names conservatively. The original literal name/body match behavior is preserved; this proposal does not broaden that inherited behavior into an overload ownership claim.

## Observed validation

`tests-attempt1.json` and `tests-result.json` record 44 passing tests: all 32 original cases and 12 new lineage/gap cases. The original test class/function ASTs are unchanged; `original-test-relocation.patch` changes only the private module import location. `focused_tests.py` provides the new cases for review and later additive test integration. Tests cover rename then recreation, declaration/alteration hash and line provenance, quoted identifier SET SCHEMA, unqualified alteration refusal, overload signatures, unsupported types, unrelated identical-body refusal, required final body hash, dynamic wrappers, dynamic patch mismatches, drop invalidation, procedure refusal, and tampered gap rejection during full semantic readback. Synthetic fixtures use `/private/tmp`. The child completed in 0.232 seconds within its 120-second bound, exited zero, and left no process group.

`run_current209_proof.py` performed one fresh private generation and independent full semantic readback. Generation completed in 3.011 seconds and readback in 3.458 seconds, each within a separate 120-second bound, with exit zero and no residual process group. Exact commands and bounded process receipts are in `current209-result.json` and the individual command records. The runner uses Python `-I -B`, a system-only PATH and internal `/private/tmp`.

The private generated bundle in `generated-current209-lineage1` contains the same five output types. Observed results are 777 exact body matches of 902 functions, including the two static lineage matches; 125 open source gaps; 2,543 catalog objects; all 20 catalog categories and raw rows; all 4,157 grants; all 18 reviewed caller seams; and the complete 664 maintained-source scope including both QA consumers. Independent verification recomputed all five semantic outputs from 1,091 admitted input files. Acceptance remains `draft-with-open-mappings`; business ownership and runtime completeness remain false.

## Input preservation and seal

`input-guards-before.json` is a dated initial snapshot. Root subsequently corrected the leading comment wrapper in `scripts/supabase_cli_helpers.sh` as authorized by the actual replay failure. That is the sole sanctioned difference from the earlier generated baseline. The live proof instead binds `root-tooling-source-integration1/current-source-after-comment-correction.json` at SHA-256 `ef2f69cf0d51b5f08ec8c475cc3fe53ed7534314e6f8609f1a493762af3f4c1e`. `current-authorized-inputs-before.json`, both transitive snapshots and `input-guards-after.json` establish unchanged current input bytes and identities across this proof, including all 12 maintained leases. The dated helper hash was not reverted or asserted current.

The sealed preparation 1 and 2 manifests and every leaf retain their captured full identities. `initial-preparation-refusal.json` preserves the initial setup refusal caused by treating a list-shaped prior manifest as a dictionary; that refusal occurred before copying candidates or running tests. The corrected guard accepts the actual manifest shape and preserves the failed setup evidence.

The final seal binds every regular private leaf recursively except the seal files themselves. Unsafe symlinks, hard links, changed input identities and changed prior sealed leaves are refused. `packet-files.json` records leaf paths, sizes and SHA-256 values; `SHA256SUMS` binds those leaves and the packet manifest. The review packet and private generated outputs are the only write boundary for this task.

No maintained source, migrations, native SDK/app candidate, control state, database, provider, installer, approval or release state was changed. No later-stage admission is supplied by this packet.

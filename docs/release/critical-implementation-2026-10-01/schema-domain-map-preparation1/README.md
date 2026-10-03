# BE-08 schema domain map preparation

This private proposal inventories the actual 209-migration effective catalog and maintained callers without changing, consolidating or squashing any applied migration. It is a reviewable domain/caller/database-owner inventory. Its acceptance is `draft-with-open-mappings`; it does not close all of BE-08.

The two catalog inputs are the root owner's freshly replayed and sealed `ordinary-schema-catalog209-execution1/observed-output/{ordinary_clean,ordinary_populated}/final-effective-catalog.json`. Their complete file bytes must agree. Each of the 209 maintained original SQL files is also compared byte-for-byte with that rehearsal's captured original migration. The 208-chain catalogs remain earlier evidence and are not the current input. The generator makes no database, Docker, network, credential or provider call.

The maintained caller scope includes member/shared and Admin Dart, Edge TypeScript, Android's main **and internal_gateway** source sets, iOS Runner, operator/worker tooling and operational scripts. The manifest declares these roots and exclusions. Release archives, generated captures, tests, fixtures, caches and the synthetic Admin evidence adapter supply no product caller evidence. This is a lexical scan of admitted source files; eighteen key client/dispatch/identity/transport seams were also read and recorded in `reviewed-caller-seams.json` with exact file hash and line anchor.

`generated-current209/schema-domain-map.json` preserves every schema, relation, function and type row, database owner, object ACL, security-definer and RLS flag. It retains every other category from the full catalog, including columns and their ACLs, role flags, role memberships, default ACLs, policies, indexes, constraints, triggers, extensions and all dependency records. Its grant records attach object, column, database and future-object default ACL entries to a target, database owner and domain. Explicit empty ACLs stay empty; default privileges are not retroactively attributed to existing objects.

Database owner is a catalog fact. Domains are the generator's transparent schema/name taxonomy. Domain stewardship and business ownership remain review assignments. ACL entries plus role memberships do not establish business authorization, actual JWT role, current user/session, request scope, row access, or approval authority. The read-only review distinguishes member/Admin user-client calls from Edge service-client calls and native/worker Edge transport.

The generated Markdown table joins each domain to its object counts, actual database owners and candidate caller groups. The JSON domain summaries list exact candidate caller files and hash-matched function-body source files. A function literal in a specification or command registry is recorded as a **reference candidate**, not promoted to an executed call. `rpcMap` is recognized only inside maintained Admin code after reviewing its implementation. Edge route names and MCP action names are kept distinct from database routine identities. Dynamic names, interpolation, SDK schema overrides and overloads remain explicit.

Only a top-level SQL CREATE FUNCTION/PROCEDURE body with the same schema/name and exact catalog `prosrc` SHA-256 supplies a current body-source match. Commented CREATE text and CREATE text inside a DO/EXECUTE string are excluded. Calls in those matched bodies are lexical candidates. A unique qualified name is still not argument-type or runtime proof. Unqualified names need search-path review. PostgreSQL dependencies are preserved separately: PL/pgSQL procedural calls, dynamic SQL and cron job command rows are not a complete `pg_depend` graph. The generator does not simulate dynamic patches, renamed routines, dynamic SQL, runtime branches or scheduled jobs.

## Reviewable results and gaps

Use these generated outputs together:

- `DOMAIN_MAP.md`: domain/owner/caller overview.
- `schema-domain-map.json`: full object, owner, grant, candidate caller, SQL-reference and catalog-record inventory.
- `input-manifest.json`: exact input hashes, scanned roots, exclusions, original and replayed migration binding.
- `coverage.json`: counts and explicit acceptance flags.
- `gaps.json`: unclassified objects, unresolved caller sites, unmatched effective function bodies, SQL name-resolution work and any unrepresented migrations.

The current draft contains 38 schemas, 997 relations, 902 functions, 606 types and 4,157 normalized grant entries. It scans 613 maintained source files. It matches 775 effective function bodies to exact original CREATE-body bytes, retains 127 unmatched functions, and records 4,754 SQL-reference candidates. Of those 127 unmatched functions, 91 are in platform schemas and 36 are in application schemas; renamed historical roster routines and deliberate dynamic function patches account for much of the application review queue. The full unmatched identities are in `gaps.json`. There are 74 unclassified objects, 58 dynamic/ambiguous/unresolved caller sites and 309 function identities without a maintained literal caller or matched-body SQL reference candidate. These counts mean **mapping work remains**, not that those routines are unused or unsafe.

The generator's admission checks reject catalog shape/identity defects, unequal peer catalogs, replay/source migration byte drift and incomplete captured migration sets. Readback rejects any input byte drift, newly added/removed admitted source or migration, omitted raw catalog categories/rows, omitted ACL entries and invented target identities. `--require-current` requires matching current migration names **and** replayed source bytes. Source/catalog equality alone never changes `runtime_call_graph_complete` or `business_owner_assignments_verified` to true.

## Reproduction

Run from the COOL repository root using Python 3.11+ and the standard library:

```sh
python3 docs/release/critical-implementation-2026-10-01/schema-domain-map-preparation1/test_schema_domain_map.py
python3 docs/release/critical-implementation-2026-10-01/schema-domain-map-preparation1/generate_schema_domain_map.py \
  --catalog docs/release/critical-implementation-2026-10-01/ordinary-schema-catalog209-execution1/observed-output/ordinary_clean/final-effective-catalog.json \
  --catalog docs/release/critical-implementation-2026-10-01/ordinary-schema-catalog209-execution1/observed-output/ordinary_populated/final-effective-catalog.json \
  --replay-migrations docs/release/critical-implementation-2026-10-01/ordinary-schema-catalog209-execution1/observed-output/captured-migrations \
  --output docs/release/critical-implementation-2026-10-01/schema-domain-map-preparation1/generated-current209 \
  --require-current
python3 docs/release/critical-implementation-2026-10-01/schema-domain-map-preparation1/generate_schema_domain_map.py \
  --output docs/release/critical-implementation-2026-10-01/schema-domain-map-preparation1/generated-current209 \
  --verify --require-current
```

## Proposed source maintenance integration

The smallest maintained integration is this single generator under `scripts/audits/collect_schema_domain_map.py`, its focused standard-library parser/admission/coverage tests under `scripts/tests/`, and the eighteen reviewed seam observations as a sibling data file. No SQL migration rewrite or new schema snapshot should be generated. Keep domain rules and caller evidence in that source-owned generator and data file; the generated output remains catalog-bound evidence.

The existing ordinary rehearsal should supply the fresh clean/populated catalog pair and captured original migration directory. Generate and verify the map only after the replay source freezes. A migration, caller-source, seam-anchor or catalog change invalidates the affected inventory; refresh it from the new observed chain. CI can run parser/admission/coverage tests without a database and compare a newly generated map to its admitted input manifest after ordinary rehearsal. Do not add a passing check that treats zero unclassified objects, lexical candidates or ACLs as proof of runtime/business authority.

Resolve the exposed application body-source transformations, dynamic/overloaded call paths and unclassified object domains through focused reviewed rules or an authoritative read-only catalog source export. Assign domain maintenance/business owners through owner review. Only the root owner should integrate this proposal into maintained scripts or change BE-08/register acceptance. This preparation changes no maintained SQL, Dart, Edge, native, Admin, shared UI, Makefile, CI, task register or external application.

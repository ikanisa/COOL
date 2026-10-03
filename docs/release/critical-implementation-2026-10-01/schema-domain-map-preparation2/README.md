# BE-08 schema domain map candidate2

Candidate2 fixes the preparation1 verifier's material gap: retained raw catalog rows and valid target names were insufficient to prove that callers, SQL references, classifications, resolutions, summaries and gaps were faithfully generated. Preparation1 is preserved with its original seal; this candidate changes only the new private preparation2 folder.

The original 19 parser/admission/coverage tests remain, with two-file catalog fixtures updated for stricter peer admission. Thirteen new tests exercise omitted caller and SQL categories/rows, forged object and grant domains, forged resolutions and suppressed valid targets, forged summary and standalone coverage, omitted gaps/categories/files, forged domain summaries/body-source/index fields, forged scan boundaries/Markdown, removed or aliased peers, duplicate type identities, non-object catalogs and missing inputs. Several tests include multiple independent tamper cases.

`verify_bundle` first reads and validates every admitted file's bytes and current source/migration membership. It requires exactly two distinct effective catalog paths and independently admits both catalogs. Type identities now receive the same duplicate-identity protection as schemas, functions and relations. Missing/unreadable inputs, symlink inputs and malformed generated inputs produce bounded refusal errors.

It then reruns the complete generator into its own temporary directory using the current root, the two admitted catalogs and the bound replayed-migration directory. None of the stored classifications, counters, resolutions, caller/SQL sites, object source indexes or gaps supplies the expected result. It compares complete semantic JSON contents for `schema-domain-map.json`, `input-manifest.json`, `coverage.json` and `gaps.json`, and exact Markdown bytes for `DOMAIN_MAP.md`. Additional, removed, reordered or changed mapping/category/summary/gap content is rejected. JSON object key order and insignificant JSON whitespace are tolerated; list ordering remains deterministic and verified. The temporary recomputation writes no maintained file and makes no database, Docker, network, credential or provider call.

The current candidate remains bound to root's sealed current209 clean/populated catalogs and all 209 captured original migration files. Complete catalog content, original migration bytes and maintained source membership remain the admission boundary. Verification is an integrity check of this declared lexical inventory. It does not prove runtime execution or business authorization, and it keeps `runtime_call_graph_complete` and `business_owner_assignments_verified` false.

## Current output

The generated inventory retains 2,543 catalog objects (38 schemas, 997 relations, 902 functions, 606 types), all 20 catalog categories and 4,157 grant entries. It scans 613 maintained sources, records 690 caller sites and 4,754 SQL-reference candidates, and retains eighteen reviewed source seams. Its unresolved counts remain 74 unclassified objects, 58 dynamic/ambiguous/unresolved callers, 127 functions without an exact body-source match and 309 functions without a literal or matched-body SQL candidate. The acceptance remains `draft-with-open-mappings`.

`receipts/verification.json` records the actual final test, generation and full recomputation readback commands and output hashes. `preserved-preparation1.json` records fresh verification that every original preparation1 sealed leaf remains unchanged. `packet-files.json` and `SHA256SUMS` seal this candidate's leaves. No maintained code or task register is edited by this preparation.

## Reproduction

From the COOL repository root with Python 3.11+:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 docs/release/critical-implementation-2026-10-01/schema-domain-map-preparation2/test_schema_domain_map.py
PYTHONDONTWRITEBYTECODE=1 python3 docs/release/critical-implementation-2026-10-01/schema-domain-map-preparation2/generate_schema_domain_map.py \
  --catalog docs/release/critical-implementation-2026-10-01/ordinary-schema-catalog209-execution1/observed-output/ordinary_clean/final-effective-catalog.json \
  --catalog docs/release/critical-implementation-2026-10-01/ordinary-schema-catalog209-execution1/observed-output/ordinary_populated/final-effective-catalog.json \
  --replay-migrations docs/release/critical-implementation-2026-10-01/ordinary-schema-catalog209-execution1/observed-output/captured-migrations \
  --output docs/release/critical-implementation-2026-10-01/schema-domain-map-preparation2/generated-current209 \
  --require-current
PYTHONDONTWRITEBYTECODE=1 python3 docs/release/critical-implementation-2026-10-01/schema-domain-map-preparation2/generate_schema_domain_map.py \
  --output docs/release/critical-implementation-2026-10-01/schema-domain-map-preparation2/generated-current209 \
  --verify --require-current
```

## Direct source integration path changes

The minimum proposed maintained boundary is one generator, one test module and the reviewed seam data:

| Private file | Proposed maintained path | Required code adjustment |
|---|---|---|
| `generate_schema_domain_map.py` | `scripts/audits/collect_schema_domain_map.py` | Keep `Path(__file__).resolve()`; it automatically binds the maintained file's path and SHA. No hard-coded preparation path occurs in the generator. |
| `reviewed-caller-seams.json` | `scripts/audits/collect_schema_domain_caller_seams.json` | Change the generator's `this_script.with_name("reviewed-caller-seams.json")` to `this_script.with_name("collect_schema_domain_caller_seams.json")`. The sibling file is required when the generator is inside the admitted repository root. |
| `test_schema_domain_map.py` | `scripts/tests/collect_schema_domain_map_test.py` | Change only the import spec path from `Path(__file__).with_name("generate_schema_domain_map.py")` to `Path(__file__).resolve().parents[1] / "audits" / "collect_schema_domain_map.py"`. Preserve registration in `sys.modules` before executing the import spec because the generator uses dataclasses. |

The tests' synthetic repository fixtures deliberately use the real imported generator outside their temporary root, so they do not accidentally import the production seam data. The actual production/root execution requires that data file and validates all source hashes/anchors and catalog candidates before using it. Keeping the seam filename unchanged as `scripts/audits/reviewed-caller-seams.json` would avoid that one filename edit, if preferred.

After these maintained path changes, regenerate and fully verify the evidence from the current frozen source and sealed replay inputs. The generator's own path/hash changes and it becomes an admitted operational-script source, so the private candidate's input manifest must not be reused as the maintained result. Keep the original applied migration history intact. The root owner owns source integration and acceptance/register changes; this integrity fix does not close the remaining BE-08 domain/caller/business-owner mapping work.

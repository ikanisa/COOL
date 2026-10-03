# Source-size QA checkpoint

14 September 2026. FQA-020 is fixed locally. Full-system QA and mobile
acceptance remain incomplete.

The exact large-file check from `.github/workflows/ci.yml` now passes. Its
1,200-line hard limit and existing generated-file exceptions are unchanged.
No source was newly exempted from that check.

| Previously oversized source | Before | After |
| --- | ---: | ---: |
| `contribution_flow_screen.dart` | 1,479 | 821 |
| `admin_operation_tables.dart` | 1,583 | 763 |
| `admin_overview_runtime.dart` | 1,267 | 894 |
| `collect_models.dart` | 1,433 | 1,173 |
| `collect_repository.dart` | 1,771 | 1,147 |
| `collect_group_cover_catalog.dart` | 1,264 | 49 |

Bank contribution widgets, shared Admin table/overview components and payment
models moved into parts of their existing Dart libraries. Group/payment setup
and receipt-queue methods moved to a repository mixin with explicit dependencies.
They remain instance methods, so existing subclass overrides continue to work.
The shared UUID instance and per-repository SMS queue state are retained.

Five moved declaration groups were compared with saved pre-edit source. Their
bodies remain byte-identical after removing outer whitespace and matching the
model annotation boundaries. Method logic, UI text, payment guards and queue
processing were not rewritten. Initial incomplete annotation placement and
missing override annotations were caught by analysis and repaired; that failed
attempt is retained in the evidence.

The generated catalog now stores definitions in eight family parts and keeps
the original ordered list of references in the catalog entrypoint. This matters
because later named covers are interleaved across families. The new metadata-only
generator is shared with the existing asset-packaging script. Only metadata
generation was executed; no image bytes or catalog input records changed.

## Verification

- **769 Flutter tests passed**, zero failures and zero skips, with four workers
  and random seed `20260914`. The recorded source manifest includes tracked and
  new application/test/assets/native/scripts/workflow inputs and is unchanged
  between start and finish.
- The complete run includes the existing golden and interaction tests. A new
  test compares every runtime field and original order against all **44** source
  catalog records. This verifies metadata preservation, not native acceptance.
- The earlier focused run passed 111 tests covering backend contracts, security
  hygiene, Admin semantics, contribution journeys, repository overrides and
  device-permission contracts. These overlap the full suite and are not additive.
- Final Flutter analysis and formatting pass. The product-boundary, Revolut source
  hygiene and mobile contract checks pass. The secret scanner used its existing
  tracked-file fallback because gitleaks is unavailable; no full gitleaks result
  is claimed.
- Coverage is **11,876 / 17,006 lines (69.83%)**, above the unchanged 40% floor.
  The prior checkpoint was 11,876 / 17,005; the new repository getter adds one
  instrumented source line. Coverage is separate from design or performance.
- Three Node generator tests pass, covering interleaved ordering/escaping,
  invalid input rejection and repeatable metadata-only writes. The new
  `make cover-catalog-test` target passes. A pinned Node 24.19.0 CI job was added;
  hosted execution remains unverified.
- The exact extracted CI size step passes for applicable Dart and Edge
  TypeScript sources. Both full historical mobile reviews still return **blocked**;
  no acceptance file, review, golden baseline or score was changed.

## Evidence and remaining work

Raw evidence is under
`.cache/fullstack-qa/20260914T151002Z/source-size-refactor/`:

- `before.json`, saved pre-edit files, `after.json`, `moves-verified.json` and
  reproducible `verify_moves.py` preserve the source comparison.
- `full-run-start.json`, `full-run-result.json`, `flutter-full.jsonl` and
  `lcov.info` bind the full test run and coverage to its inputs.
- `ci-size-check.sh`, `ci-size-check.log`, `analyze-final.log`,
  `source-hygiene.log` and generator test logs retain command outcomes.
- `mobile-gates.json` and `database-inspection.json` retain current incomplete
  gate and environment observations.

The exact task database inspection still timed out; this is an observation
failure, not proof that the database stopped. Cleanup remains unconfirmed.
Disk/native capacity, four legacy SQL fixtures, complete route/state coverage,
runtime integration, provider/device checks and real mobile reviews remain
open. The source refactor changes source fingerprints; old native/media evidence
cannot be relabelled current based on these tests. No deployment was performed.

# Collect member and native coverage checkpoint

15 September 2026, Africa/Kigali. Execution timestamps are UTC on 14 September.
**FQA-036 is fixed locally. The full P0–P8 goal remains active; native and
full-system acceptance remain incomplete.**

The gate now requires **966 cases per platform**, retaining all 135 previous
requirements. All 38 member route templates have a source dependency review
view, backed by 228 actual page-factory and guard-callback observations.
These are coverage and discovery results, not accepted screens or completed
member journeys.

## Coverage defect and repair

The previous gate read `_RouteSpec` declarations and a manual list of additional
states. It did not read the existing `_StateSpec` inventory. Consequently,
47 of the 56 material-state IDs did not appear in required cases. Declared
variants applied to only eight selected IDs, leaving the other base cases
outside those variant requirements.

Two meaningful regressions reproduced these omissions before repair: the
51-test run failed two assertions. The updated gate reads both declared native
inventories, rejects empty, duplicate or unparseable literal case declarations,
excludes comments, and binds the declared harness paths into the source hash.
Every base case receives every existing declared variant. Explicit older
variant and keyboard requirements are preserved.

The contract has only two added fields: `material_state_inventory` and
`variant_scope: all_base_cases`. All prior arrays, criteria, annotation IDs,
reference inputs and authority binding are unchanged. Both native harness
files and the actual acceptance file are byte-identical to their snapshots.
No approval or baseline was written.

| Derived inventory | Count |
| --- | ---: |
| Native route declarations | 43 |
| Native material-state declarations | 56 |
| Distinct base IDs, including preserved legacy states | 120 |
| Default cases | 120 |
| Seven declared variants for all base IDs | 840 |
| Preserved keyboard cases | 6 |
| Required cases per platform | 966 |
| Previous cases retained / removed | 135 / 0 |
| Additional requirements | 831 |
| Accepted case records | 0 |

The seven declared variants cover compact, large, tablet, landscape, light,
large-text and reduced-motion configurations. This fixes the confirmed
inventory/variant omission. It does not establish that all possible material
states, role/geography branches, system/high-contrast themes, keyboard
combinations or lifecycle cases have been discovered.

Twenty-one manual base IDs have no exact ID in either native harness. They
remain required; possible aliases were not silently merged or removed. The
IDs and source locations appear in [member-native-cases.csv](member-native-cases.csv)
and [member-coverage-summary.json](member-coverage-summary.json). Comparator
mapping and independent/owner decisions remain unverified for every case.

## Member route and dependency discovery

The route-inventory regression now invokes actual `GoRoute` page factories
and redirect callbacks for each of 38 templates on Android and iOS, with
signed-out, Rwanda-member and diaspora-member fixtures: 228 observations.
It records the screen widget class, loading/auth redirects, route-specific
redirects and the effective first redirect. Assertions cover internal targets,
nonempty alias redirects, iOS group-creation restrictions and geography-specific
bank-transfer settings access.

Only the provider/context fixture is mounted. Destination screens are not
mounted, and the test does not execute a complete router navigation or a
payment/authentication task. Product route guards and app behavior were not
changed. The initial attempt produced all 228 observations but failed Flutter's
platform-override cleanup invariant. Its report remains failed. Resetting the
override in `finally` inside the test produced the separate passing run.

[member-route-dependencies.csv](member-route-dependencies.csv) combines those
observations with screen class locations, file-level provider references and
lexical repository/API declaration candidates. The exporter found 70 method
candidates and 37 direct API declarations representing 34 distinct kind/name
pairs. It records unresolved invocation names explicitly. File-level matches
can include neighboring screens and miss delegated calls; these counts do not
establish a complete call graph or server authorization coverage.

The exporter uses the existing gate as its case authority. It verifies the
route report's passing status, source continuity and output hash before
writing planning views. Running it again on the same source produced identical
CSV and JSON hashes. To reproduce after a source change, first run the existing
route-inventory test with `COLLECT_QA_EXPORT_ROUTES=true`, retaining its JSON
test events and before/after source hashes, then invoke:

```sh
python3 scripts/qa/export_member_coverage.py \
  .cache/fullstack-qa/20260914T151002Z/coverage-continuation/route-map-current/report.json
```

The dated report path is suitable only while its bound source remains current.
The exporter rejects stale recorded inputs. This review view adds no competing
hand-maintained native case count or acceptance record.

## Current verification and retained attempts

Raw evidence lives in `.cache/fullstack-qa/20260914T151002Z/coverage-continuation/`.

| Evidence | Result and limit |
| --- | --- |
| `gate-regression-before.json` and `before-source/` | 51 tests / 269 assertions; two reproduced failures; exact input snapshots retained |
| `route-map-initial/report.json` | Failed Flutter cleanup invariant; 228 partial observations are not a pass |
| `route-map-current/report.json` | Three tests pass; 228 factory/guard observations; recorded source unchanged |
| `final-checks/tooling.json` | 75 QA Ruby tests / 365 assertions, 57 mobile-gate tests / 298 assertions and nine Python tests pass; no Ruby failures/errors/skips |
| `final-checks/flutter-focused.json` | 60 tests pass, zero failures/skips; includes the route test, app-shell and security-hygiene contracts |
| `final-checks/analysis.json`, `format.json`, `source-hygiene.json` | Analysis, changed-Dart formatting and repository source hygiene pass |
| `final-checks/mobile-contract.json`, `evidence-consistency.json` | Valid contract and consistent blocked evidence; no release approval |
| `final-checks/android-design.json`, `ios-design.json` | Retired repository checks recorded blocked results in this dated run; their scores and criteria supply no current design authority |
| `final-checks/report.json` | All 505 recorded inputs unchanged during execution; native blocked results stay separate |
| `source-checkpoint.json` | Previous requirements, contract fields, acceptance, harnesses, settings and generated output hashes verified |

The Ruby total is 132 tests and 663 assertions. The separate three-test route
run overlaps the 60-test focused regression; these numbers must not be added
as independent product coverage. Passing execution-integrity reports do not
establish current mobile acceptance under the owner-selected `revolut-design` skill.

Both gates stop during artifact/acceptance validation: current signed release
artifacts and build provenance are missing, acceptance bindings are absent
or stale, and findings remain open. The ten Android and nine iOS diagnostics
are evidence-validation failures, not complete counts of visual defects.

The earlier full Flutter run remains 867 passes with 74.65% measured line
coverage. Of its 615 source inputs, 612 are unchanged. Only CI wiring,
`Makefile` and the expanded route-inventory test differ. No product Dart,
asset or platform source changed here; no new full-suite run or coverage
measurement is claimed. The user's settings hash remains preserved.

Shared free space fluctuated during this continuation and was 0.805 GiB at
22:37 UTC. No native build was attempted under that constraint. The prior
database shutdown and retained volume remain recorded in the
[Edge checkpoint](EDGE_CHECKPOINT.md); no database or hosted source changed.

## Remaining work

Complete task/overlay/role/geography/API/comparator mapping, reconcile the
21 legacy native IDs with actual harness actions, and establish supported
member browser behavior. Then execute current native candidates and full
member journeys with the required device, accessibility, performance and
visual evidence. All Android/iOS approvals remain outstanding. Other P0–P8
work continues in [STATUS.md](STATUS.md) and [work-items.csv](work-items.csv).
No deployment, production migration, external message, device reset, store
submission or release approval occurred.

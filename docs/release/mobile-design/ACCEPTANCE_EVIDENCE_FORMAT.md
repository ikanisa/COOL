# Mobile acceptance evidence

This is the product adapter for the `revolut-design` skill's MOBILE-DESIGN-100
rule, especially passing conditions 7 and 9. It describes evidence consumed by
`scripts/qa/mobile_design_gate.rb`; it neither changes the design authority nor
grants acceptance. The current acceptance record remains blocked.

In addition to the existing artifact, case, annotation and build-provenance
fields, an approved record requires the following separate evidence.

## Quality results

Each case has a `quality_results` object with exactly four keys:
`task_usability`, `accessibility`, `performance` and `runtime_resilience`.
Each value references an ID in the top-level `quality_evidence` array.

A quality record contains `id`, `dimension`, `platform`, `status`,
`open_findings`, `environment`, `cases`, `evidence` and `review`. Its current
`source_sha256`, `contract_sha256`, `references_sha256`, `authority_sha256`,
`version` and platform `artifacts` map bind the result to the reviewed build.
`evidence` contains the repository-local report `path` and `sha256`.
`review` contains `reviewer`, ISO-8601 `at` and substantive `notes`.

All four results must pass, with no open findings. The report must exist,
match its hash and identify the tested environment. Its explicit `cases`
scope may cover several cases on one platform. Every referring case must be
in that scope. A performance result cannot stand in for accessibility or
another dimension. A combined score does not close these checks.

## Separate reviews

`platform_reviews` is keyed by `android` and `ios`. Each reviewed platform
has exactly three records: `implementer`, `independent_visual` and `owner`.
Each record contains its own `reviewer`, ISO-8601 `at`, substantive `notes`,
`decision`, `evidence`, `platform`, complete `cases` scope, all five current
fingerprint fields and the exact platform `artifacts` map.

Every decision must be `approved`, supported by its own existing report and
hash. The independent reviewer must be distinct from the implementer and
owner. Owner acceptance must follow the completed implementation and visual
reviews. Case, quality and platform reviews must be dated after the recorded
build and cannot be in the future. Changed source, contract, references,
artifacts, reports or case coverage invalidate the affected evidence.

The validator checks consistency and file integrity. Reviewer names alone
cannot establish identity or that a review occurred: the linked records must
contain the actual attributable review or owner communication. The agent
must never manufacture these records or treat unit-test fixtures as reviews.
Private review material belongs in ignored, access-controlled local evidence,
with only appropriate hashes and non-sensitive references in shared reports.

The existing per-case visual criteria, native artifact, original reference,
comparison, interaction, accessibility and owner-annotation requirements all
remain mandatory. These additional records do not replace installation and
package-readback proof. Fixture tests validate this adapter only.

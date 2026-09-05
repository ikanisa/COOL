# Fixture data removal — 4 September 2026

Status: **Requested group removed from the working codebase. Mobile distribution
remains blocked; the earlier Android candidate is stale.**

## Changes

- Deleted the bundled mobile repository fixture file. Runtime construction starts
  empty and loads group records from Supabase; test state now requires explicit
  injection. Synthetic records live in `test/fixtures/collect_repository_fixture.dart`,
  which no `lib` source imports.
- Removed the retired group name, slug, internal ID and payee label from source,
  tests, integration harnesses, scripts and documentation. Historical document
  identifiers are marked removed, without rewriting their recorded evidence hashes.
- Updated the isolated tests to a clearly labelled QA private group. Its test
  records are not a production fallback and cannot be imported into runtime code
  under the strengthened fixture-isolation check.
- Removed 23 obsolete store screenshots showing the group or its linked sample
  totals, receipts and share links, plus 16 generated staging copies. The store
  screenshot sets are incomplete and require new capture and review before upload.
- Visually reviewed six before/after golden pairs, then refreshed only those six
  baselines and their manifest hashes. Amounts, targets and navigation retain their
  behavior; the changed test ID changes its deterministic card tint.

## Validation

- Source scan: zero retired-name or internal-ID matches in tracked and untracked
  working text files. Git history and ignored diagnostic evidence are outside this
  scan; neither is a runtime data source.
- Image text scan: zero matches across the 29 remaining golden, store, staging and
  relevant evidence images. Linked group-specific store images were also removed
  even where their titles were not visible.
- Full test run: 614 non-golden tests passed; six of 14 golden tests initially
  failed on the removed fixture labels. After visual review, all 14 golden tests
  passed. Combined coverage: **628 tests verified**, including four new live-data
  regressions for missing configuration, empty/denied backend reads, and exact
  backend-driven additions, renames and removal.
- Flutter analysis: no issues found. Source hygiene, fixture isolation, secret
  scan and syntax checks for 13 changed shell scripts passed.
- `make mobile-design-gate`: blocked (exit 2), as required. The previous APK/AAB
  provenance predates these source changes; a fresh build and acceptance are needed.

No Supabase rows, production sessions, physical-device data or payments were
modified by this cleanup. No binary or store assets were uploaded.

Evidence: `.cache/fixture-removal-20260904/` (`source-scan.json`,
`image-scan.json`, `removed-store-assets.json`, `golden-review.json`,
`tests-first.txt`, `goldens-final.txt`, `analyze-final.txt`, `source-hygiene.txt`,
`shell-syntax.txt`, `current-fingerprint.json`, `mobile-design-gate.txt`).

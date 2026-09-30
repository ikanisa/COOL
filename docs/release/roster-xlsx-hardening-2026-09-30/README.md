# Roster XLSX local validation retained on 30 September 2026

The copied verification and logs identify 57 passing parser/preflight tests,
clean focused analysis and offline locked resolution under exact Flutter 3.44.4
/ Dart 3.12.2, plus five CSV/TSV regressions under Deno 2.5.6.
`copy-verification.json` verifies each copied file against the ignored source
packet. Test-time source and log fingerprints remain unchanged in
`verification.json`; the later MFA dependency declaration change does not
retroactively change this test-time manifest. This packet is scoped local
evidence, not a frozen release-candidate or deployed/vendor acceptance.

The source verification JSON also records hashes for `focused-tests.txt` and
`focused-analysis.txt`. Those exploratory Flutter 3.44.3 logs are deliberately
not copied into this scoped packet; they remain in the original ignored cache.
All four exact-pinned command logs and the CSV regression log are included.

A03 and A09 remain open for complete decoding/budgets, representative workbook
and browser/device resource tests, permission/consent and durable server-audit
acceptance. A01 original-file provenance and A02 ground-truth evaluation are
separate open requirements.

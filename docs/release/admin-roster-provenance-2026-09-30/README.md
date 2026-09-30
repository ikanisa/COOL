# A01 Admin roster provenance — local implementation evidence

## Verified scope

The contract-1 Admin roster flow now uses the coordinated migration142 API:

- Every upload transmits the original bytes. XLSX keeps the existing safety preflight and identifies its browser-derived TSV separately. Pasted UTF8 has its own source kind.
- Typed initial, human-review and commit receipts validate exact fields, source/request hashes and IDs, row counts, mode and real booleans. Server reviewed-row hashes remain opaque; no competing JSON canonicalizer is invented.
- Source, consent, extraction ID/model and original AI confidence stay attached through editable 25-row pages and parent-linked saved reviews. Human review does not overwrite the original AI evidence.
- Create and existing eligible assisted-group additions both commit by reference. No raw-row writer or fallback success count is used by these flows.
- Unknown responses retain the draft, exact serialized request and stable ID. Only validated acknowledgement or explicit discard resolves it. Explicitly discarding a definitively rejected review retains its original source for correction.
- Actor, Auth session and operation generation are fixed for the draft. Each dispatch captures a token after verifying that ownership; safe same-session refresh is supported. Account/new-session changes clear/hide all private draft content and suppress late success.
- Terminal extraction failures require a deliberate new upload; rate-limit and in-progress errors retain safe retry guidance. The old provider request is never silently rerun.

## Validation

`validation.json` records exact commands, stdout/stderr hashes, runtime and before/after hashes for 23 source/lock/contract/font inputs. All 23 were unchanged during the checks.

- Flutter **3.44.4**, framework `ad70ec4617166f1c38e5d2bfd388af71fda14f06`, Dart **3.12.2**.
- **130 tests passed** across the new model/controller/HTTP and widget suites, existing Admin source checks and existing XLSX parser/preflight tests.
- Focused analyzer over **13 files**: **no issues**.
- The source-bound UI contract is in `UI_CONTRACT.md`. Current PNGs use the actual bundled fonts and were visually inspected. Validation errors wrap at 320px/2× text; a regression assertion checks they are not elided. Keyboard traversal, Escape preservation and a simulated keyboard inset are tested.

Earlier failed/partial local packets remain in `attempts/01` and `attempts/02`. They are superseded and do not count as current acceptance.

## Actual SQL receipt decoder

`test/admin_roster_sql_receipts_test.dart` accepts preserved stdout from the root-owned rollback-only `scripts/tests/roster_import_provenance_receipts_uat.sql` fixture. It validates the actual PostgreSQL initial/review/commit/replay/read JSON against these same typed decoders and original synthetic browser bytes. This is a separate supplemental check; it has **not** been included in the 130-test count. Execution requires the actual root-generated stdout and is documented separately when available.

## Limits and remaining acceptance

No hosted service, provider or database was called by this worker. These results do not certify SQL migration deployment, live provider behavior, physical-device/store readiness, operator acceptance, spoken screen-reader behavior or complete Revolut visual parity.

Draft state is private and memory-only. Browser reload/window closure abandons it; server receipts are retained according to the API, but cross-reload client recovery is not implemented or claimed. Provider/retention approvals, deployment pairing, broader browser/device checks and recovery policy remain explicit acceptance work. A01 as a whole remains open until its full acceptance gates are evidenced.

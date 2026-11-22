# BuriMunsi runtime integration — 9 November 2026

The imported A04.3 source retained safe command recovery and the A04.2 correction
that removes consumed financial forms before optional record refresh. It did not
contain the later recovery, API or presentation continuations. This integration
composes those changes with the imported runtime instead of replacing it with an
older continuation's full application tree.

## Inputs and decisions

The original downloaded archives and extracted trees remain unchanged under
`.cache/burimunsi-drive-20261109/`. These source archives are engineering inputs;
their historical execution logs are not verification of the combined code.

| Input | Adopted behavior | Preserved boundary |
| --- | --- | --- |
| A04.3 / A04.2 | Owner/group-bound commands, v1 ownership proof followed by v2 economic status, financial warnings, invalidation of consumed forms/selections/drafts and independent outcome notices | No SENT/UNKNOWN retransmission or stale selection after a consumed command |
| Recovery `0.19.0-recovery.3` | Immutable-command dispatch witnesses, durable readback checks, retained terminal cleanup debt, process-local shared read lease and bounded GET-only retry controller | Original owner/group fields remain persisted and are included in journal/retry identity checks; the isolated branch's ownerless model is not substituted |
| API contracts r3 | Separate `burimunsi.native.v1` envelopes; request/query/DTO/cache validation; exact response identity; strict UTF-8, header, body-size and acceptance-time profiles | Managed authentication headers remain distinct; A04's operation-status v2 replaces the branch's obsolete two-field status shape |
| Presentation `0.19.0-presentation.3` | Exact numeric formatting, explicit provenance/freshness states, permission-aware restoration and bounded paged positional restoration | A04.2 command invalidation and independent financial outcome notices remain; restoring navigation never restores authority, a financial draft or permission to POST |

The main shared-file resolutions are `OperationJournal.kt`, `NativeRepository.kt`,
`AndroidOperationStore.kt`, `BuriViewModel.kt`, `ApiClient.kt`, the native wire
schemas and the backend native handler. The receiving manifests, SIM policy,
financial records readers/writers and native-build safeguards remain based on
the imported A04 candidate; unrelated older bytes from continuation archives are
not treated as improvements.

The journal now retains a verified terminal record until financial-cache
invalidation and journal deletion both succeed and their absence is verified.
The retained owner/group and original command bytes cannot change through token
rotation, another repository wrapper or status retry. A transport-level 4xx is
not an origin-bound durable no-effect receipt, so a dispatched command remains
unresolved until authenticated recovery. This intentionally supersedes the old
test expectation that any first 4xx could clear the command and preserve an
actionable draft.

## API schema integration

`contracts/burimunsi-api/{profile,schema}.json` is the product contract source.
The corresponding generated JavaScript and Kotlin definitions both require
operation-status contract version 2, matching group/actor/request identities,
and supported economic effects. Pending means `unresolved` without an invented
operation. Committed allocation means posted/reversed/corrected; committed
nonfinancial commands mean `not_applicable`. Legacy or inconsistent status
shapes fail closed. This strict envelope supplements the mandatory preceding
owner-recovery proof; it does not replace that proof or create a second writer.

The Android client can mount these logical routes beneath the existing local
Collect Edge function at `/functions/v1/collect-api`. The public build profile
supplies that fixed transport prefix separately from the HTTPS origin. Empty
prefix remains the compatibility default for earlier callers. Other prefixes,
encoded path separators, dot-segment traversal and origin changes are refused.
Logical request/query/response validation and the two distinct authentication
proofs remain unchanged. This uses the existing Collect backend rather than
creating another BuriMunsi service. The genuine managed-session broker remains
an integration requirement; no provider credential or fake broker is supplied.

## Presentation scope

The maintained `revolut-design@jean-bosco-skills` source and its native/mobile,
brand, typography and component-state references were read directly. Existing
BuriMunsi screens, identity, workflows and selected theme are retained. The
adopted changes concern truthful loading/offline/error/unknown states, exact
values, accessible outcome notices and navigation restoration. There is no
claim of a new visual comparison or installed-screen fidelity. Added bilingual
recovery copy still needs fluent operator review.

## Verification

- `node --test native/burimunsi/api-tests/contract-integration.test.mjs`:
  **23 passed** against the merged strict handler and decoder. This covers v2
  posted/reversed/corrected/pending and nonfinancial outcomes; rejects legacy
  status, foreign owner/group/request, inconsistent effect/state and malformed
  media; and preserves the separate M-Money contract boundary.
- `prepared-entrypoints.test.mjs`: **17 passed** after adding the strict request
  headers to its existing preparation fixture. No backend permission or
  preparation assertion was relaxed.
- Kotlin core checks: **111 passed**. Command recovery, repository, ViewModel,
  presentation, HTTP and cross-layer scripts all passed. Their separate suite
  results and log hashes are recorded in
  `.cache/burimunsi-drive-20261109/checks/runtime-merged-local-summary.json`.
  The HTTP suite now includes **130** actual-client checks and the cross-layer
  controller/repository suite includes **64** checks. Enumerated traces and
  repeated projections are not combined into a business-scenario total.
- After the shared Collect Edge prefix was added, HTTP, all seven ViewModel
  suites and the 64 cross-layer checks passed again. Their logs and the changed
  source hashes are recorded in
  `.cache/burimunsi-drive-20261109/checks/runtime-shared-prefix-summary.json`.
- `scripts/generate_ui_copy.py --check` verifies the merged catalog and generated
  resources. Final Android compilation remains coordinated by the build owner.
  Host execution and historical continuation logs are not installed-device,
  PostgreSQL, carrier or hosted-service acceptance.

## Remaining implementation and acceptance boundaries

Storage R3 and SMS R4 are preserved for review rather than selected as
production storage ports. They do not supply the actual legacy decoder, durable
writer cutover, independent trusted checkpoint service, Android ciphertext blob
transactions or offline intake/quarantine integration. No local checkpoint is
represented as independent rollback protection.

The recovery retry controller is opt-in and process-local. It installs no
automatic background polling service or durable global rate limit. The
presentation checkpoint restores a bounded position through at most 16 pages
and 2,000 rows, not necessarily the same record after data changes. Real native
storage/process death, provider/SIM, managed session broker, PostgreSQL
concurrency, hosted routing and operational acceptance remain separate evidence.
The source import does not activate receiving uploads or live financial work.

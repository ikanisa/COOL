# Managed Auth recovery archive

This separate module captures and restores managed Auth **data** without widening the existing `../current-archive/` app/private archive. It uses repository-relative imports and Node built-ins; no machine-specific credential loader, deployment CLI or PostgreSQL bootstrap is included.

The qualified private predecessor has actual accepted evidence for 27 Auth tables, 271 table columns, nine enums and a separate sequence: an encrypted 115-row capture with authenticated readback, an exact local PG17 inert data roundtrip, and a matching ciphertext-only offsite download. Those receipts remain bound to the original private implementation. This repository normalization has not yet been executed or qualified. Seventeen focused predecessor tests and eight synthetic native cases previously passed; this copy retains them and adds one checkout-output refusal test for Root's focused 18-test verification.

Operational GoTrue/session recovery, independent key custody, complete Storage/config recovery, cross-service consistency and measured whole-system RPO/RTO remain open. Stored sequence endpoints are not an MVCC or Auth-quiescence guarantee. The observed 115 rows describe that archive; future captures measure their own counts and bytes in their own read-only transaction.

## API

Use Node 24.19.0 or the separately qualified supported runtime. The APIs perform no dispatch when their modules are imported. `REFERENCE.json` contains the reviewed catalogue descriptors and source provenance, not Auth rows. Source02271 is provenance, not permission to query GoTrue or evidence that Auth is quiescent.

```js
import reference from './REFERENCE.json' with {type:'json'};
import {compileCountsRequest, parseCountsResponse} from './counts.mjs';
import {compileCaptureRequest, assembleCaptureResponse} from './auth.mjs';
```

- `compileCountsRequest(reference, requestId)` and `parseCountsResponse(response, {reference, request, project})` prepare and parse a count-only preflight. They request no Auth cells or sequence values. An existing accepted count operation does not need repeating solely for this source integration.
- `compileCaptureRequest(reference, counts, requestId)` and `assembleCaptureResponse(response, {reference, counts, request, project})` prepare and parse a separately reviewed capture. They check the catalogue, native output settings, enums, inet/array text, same-transaction row/cell/byte budgets and separate sequence endpoints.
- `captureAuth({transport, reference, counts, expectedCountsSha256, requestId, archiveDirectory, keyDirectory, executeReviewedReadOnly:true})` uses an explicitly supplied `createManagementTransport` instance from `../current-archive/transport.mjs`. The caller independently verifies the actual saved count evidence, then supplies `sha(canonical(parsedCounts))` for `expectedCountsSha256`; this differs from the digest of a pretty-printed count file. There is no credential discovery, retry, cap increase or omitted-table fallback.
- `encryptAuthSnapshot` / `decryptAuthSnapshot` use the separate managed-Auth AES-256-GCM format, scope and AAD. `writeAuthBundle` / `readAuthBundle` use the shared private-file guards and authenticate readback. Library receipts include private custody locations and must remain private; do not log them or copy them into public evidence.
- `restoreAuthInert(snapshot, {adminUrl, makeClient})` creates a new literal-loopback PG17 database with `archive_data` and `archive_types`. It verifies all native cells/columns and explicit enum mappings. Generated values are materialized; live Auth schemas, defaults, triggers, sessions, providers and sequence authority are not activated. Actual Auth cells are present in the resulting private PG data directory, so its access and retention remain controlled until disposition.

## Private custody and fixed bounds

**Recovery data, archive files, keys, count evidence and actual-data PostgreSQL files must live outside the checkout.** Archive and key children must be fresh, mutually separated, and in physical private 0700 parents. Capture rejects an output child inside the module-derived whole repository root (or an ancestor containing it) before directory creation or transport dispatch. Keep key material separate from ciphertext; copying ciphertext does not establish independent key custody.

The fixed caps remain 10,000 rows/table, 50,000 total rows, 65,536 bytes/cell, 2 MiB native text, 4 MiB minus 4,096 serialized snapshot bytes, and 8 MiB wire data. Statement/transaction/transport bounds and all format/scope validation are unchanged. Sensitive responses and snapshots remain in memory or encrypted storage; safe failures do not persist cell values. Buffer zeroing does not establish guaranteed erasure of process memory or strings.

## Focused verification

Root runs the focused suite once under its reviewed network-denied process custody with a private TMPDIR outside the checkout:

```sh
node --test scripts/supabase/managed-auth-archive/auth.test.mjs
```

The original 17 tests use synthetic values and fake transport. One deliberately failed synthetic capture leaves safe intent evidence in that controlled temporary area. The added 18th test verifies `AUTH_OUTPUT_PATH_INVALID`, zero transport calls, and absence of both output children when archive output is inside the checkout.

`native-definition.mjs` exports `runNativeDefinition({adminUrl, makeClient, onMetadata})`; it has no CLI or bootstrap. The optional callback receives synthetic catalogue metadata only. A caller supplies the independently owned loopback PG17 factory and process/cluster custody. The eight existing cases cover catalogue parity, capture output settings overriding hostile session settings, same-transaction capture, authenticated fixture/refusal behavior, native enum/materialized-value roundtrip, cell budget refusal, enum drift EXPLAIN with all 28 Auth relation/sequence scans at zero loops, and extra-relation refusal. There is no need to repeat the unchanged native qualification merely to make this import/path-binding delta reviewable.

`NORMALIZED-DELTA.json` records exact predecessor/output pins, helper byte parity, import replacements, the one portable source-root binding change and its one added test. Existing app/private119-table, private Auth sources, captures, failed attempts and Root runtime wrappers remain unchanged. Sole UI authority remains `revolut-design@jean-bosco-skills`; this module changes no UI.

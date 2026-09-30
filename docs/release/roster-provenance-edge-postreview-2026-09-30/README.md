# Roster source and preview provenance: post-review Edge evidence

Status: locally verified with injected Auth, SQL RPC and provider doubles. This packet does not establish migration 142 database acceptance, deployed compatibility, live extraction quality, or production readiness.

## Corrections after the initial 117-test snapshot

The earlier `roster-provenance-edge-2026-09-30` packet is preserved unchanged as a historical snapshot. This packet binds the corrected current Edge sources.

1. The candidate resource bound includes PostgreSQL JSONB separator spaces and expansion of exponent-form confidence values. Tests cover both sides of the 512,000-byte boundary, multibyte UTF8 names, and `5e-324`. This resource calculation does not compute or replace the server-issued reviewed-row hash.
2. Deterministic NUL fields fail before JSONB completion and receive a durable `roster_preview_invalid` terminal record. AI fields already rejected NUL through the existing strict response policy.
3. A received SQL `22023` completion rejection proves that transaction failed; the handler can record a terminal invalid-preview failure. A transport failure or lost completion acknowledgement remains uncertain and does not trigger an overwrite or automatic provider rerun.
4. The daily source limit maps to HTTP 429 `roster_import_limit`. A structurally valid expired source/cached preview maps to HTTP 409 `roster_import_expired` and requires a deliberate fresh upload.

The source-only review compared migration 142 SHA-256 `46cc675c117a3fa6d438db8501a3e9643496a13a80305ae2a61071c27060d01e` with the Edge contract. No SQL or Dart file was edited or executed by this worker. Source/preview receipt fields, methods, immutable model/extraction links and bounds agree at that snapshot. SQL acceptance remains separate.

An initial new test miscounted the text length of `1e-7`, expecting a three-byte rather than five-byte expansion to `0.0000001`. `initial-test-expectation-error.log` retains the failed assertion; the expected value was corrected and all final checks passed.

## Implemented and verified

- The real Edge entrypoint validates the bearer with `Auth.getUser`; the handler derives actor/session claims only after that succeeds. SQL is responsible for independently checking the actual live session, current Admin permissions, feature flag and receipt ownership at each RPC.
- Contract 1 rejects caller-supplied actors, digests, sizes, model names and unrecognized request fields. CSV/TXT/XLSX/PDF/image all supply original bytes. Pasted text has its own UTF8 source. SHA-256 covers the actual received original bytes, including whitespace and byte-order markers.
- The source and consent receipt must be acknowledged before a provider call. Actor/session, request ID, source hash/size/type, AI extraction ID and XLSX derived assurance are checked on the acknowledgement. A completed exact retry returns its cached initial preview; in-flight and immutable failed attempts do not invoke a second provider request.
- XLSX stores separate server-computed hashes of original bytes and received client-derived TSV. The Edge check validates only bounded outer ZIP framing. It does not decode a workbook or compare the TSV with workbook cells.
- Extraction is tool-free and requests `store:false`. Only bounded candidate rows, sanitized model/response ID, response-text fingerprint, version constants and receipt metadata are submitted to SQL. Original files, raw provider responses, bearer tokens and provider keys are not included in persistence calls.
- Initial previews, including deterministic CSV/TXT/text/XLSX, require explicit human review. Edge validates the SQL-issued import/revision/hash/source receipt, row counts, ordered normalized rows, model and mandatory `can_submit:false` / `requires_human_review:true`. It cannot finalize member or financial records.
- Provider failures have fixed public codes and a terminal failure receipt. A lost completion acknowledgement is not overwritten as a failed extraction because the SQL completion may already have committed.
- Existing TypeScript phone normalization now admits the same `07[2389]` prefixes as the current SQL canonicalizer. Provider source-row limits match PostgreSQL's positive signed integer bound.

## Local limits

| Boundary | Implemented bound |
| --- | --- |
| JSON request | 8 MiB, streamed read |
| Original binary upload | 5 MiB, canonical base64 |
| Text/CSV/TXT and received XLSX TSV | 512,000 UTF8 bytes |
| Candidate rows | 1–500 |
| Candidate envelope in PostgreSQL JSONB text form | 512,000 UTF8 bytes, conservatively including separator spaces and numeric exponent expansion |
| Deterministic raw name | 480 Unicode code points; SQL valid normalized names remain 2–120 |
| Provider raw name | 120 Unicode code points |
| Raw phone | 32 Unicode code points |
| Source row | Integer 1–2,147,483,647 |
| Provider response | 1,048,576 UTF8 bytes; structured output 512,000 bytes |
| Provider deadline | 60 seconds, including response-body reads through native fetch's abort signal |
| Filename/model/response ID | Filename 160 safe ASCII characters; model 128 and response ID 256 sanitized ASCII characters |

These are implementation bounds, not provider-budget or lawful-retention approval. PDF/image checks retain the existing framing and image dimension limits; they are not complete decoders or scanners.

## Exact test evidence

- **125 Deno tests passed on Deno 2.5.6**: 74 source/provenance/handler tests, plus all 51 existing roster tests (19 file-policy, 24 provider-response, 3 request-policy, 5 CSV/parser). The five CSV tests are included in 51, not additional to it.
- **10 actual-entry roster HTTP tests passed**, plus **45 existing HTTP regressions**, on **Bun 1.4.0** with the harness's local dependencies. This environment did not expose `tsc`; the HTTP harness did not provide TypeScript checking. The separate pinned Deno entrypoint check passed.
- **One focused static roster wiring check passed**. This verifies source wiring only.
- The new tests cover forged metadata, verified-user/session mismatch, delayed source-ACK barriers, consent before provider, unavailable/malformed acknowledgements, completed/failed replays, wrong-model/source lineage, lost completion ACK, bounded streams/rows/envelopes, original PDF-byte handoff, UTF8 errors, and explicit human review for every format.

Exact commands, exit codes, runtime version, counts and hashes are in `verification.json`. `source-sha256.json` was captured before and after the final checks and matched. `context-sha256.json` records the package manifests and shared contract at capture time; it is not Flutter dependency-resolution or SQL runtime evidence. `artifact-sha256.json` protects the retained logs and metadata. Earlier dated evidence packets were left untouched.

## Runtime provenance

The previously verified official Deno release is retained in the ignored task runtime directory; no binary is copied here. `runtime-verification.json` preserves the official archive URL/checksum evidence and the binary was rehashed for this run.

- Release: `https://github.com/denoland/deno/releases/tag/v2.5.6`
- Archive: `https://github.com/denoland/deno/releases/download/v2.5.6/deno-aarch64-apple-darwin.zip`
- Checksum: the same archive URL with `.sha256sum` appended.
- Archive SHA-256: `32a5b2bcf49432715719c7c769529269fbd08cafdc059b7cecd42f9d771059ab`
- Binary SHA-256: `a371e0605be5039a91a079a802d66b22c124a42e31573e43136c93c2b362f1c0`

## Remaining acceptance

1. Actual migration 142 UAT must establish live-session/permission revocation fencing, private immutable lineage, human revision limits, idempotency, authorization and atomic member commit behavior. This packet mocks those RPCs.
2. Complete and test Dart/Admin source upload, immutable preview/review presentation, account/session races and typed review/commit acknowledgement handling against the coordinated contract. Retain a combined frozen integration packet.
3. Validate deployed Auth/Edge/SQL compatibility and representative provider extraction quality and consent interaction. No live service, model or database was called here.
4. Add full PDF/image codec and expansion protections, server verification of XLSX derivation if required, representative workbook/browser memory testing, durable provider spend/rate controls and retention/access/deletion approval. Do not close all of A03/A09 based on this packet.

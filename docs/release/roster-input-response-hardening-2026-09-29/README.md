# Roster input and response hardening — 29 September 2026

Status: **local verification passed; A03 remains partial and production remains NO-GO.**
This packet records bounded roster-upload and AI-response behavior, including the
exact repository-pinned Deno 2.5.6 run. It does not establish whole-repository Q01
acceptance, provider accuracy, deployment state, or production release approval.

## Implemented scope

- Upload decoding enforces canonical base64 and a 5 MiB decoded-byte limit before
  allocating the decoded copy. MIME signatures must match the declared file type.
- PNG checks cover chunk boundaries, CRCs, header dimensions and final framing.
  JPEG checks cover dimensions and marker/scan boundaries, including progressive
  images. WebP checks cover RIFF/chunk bounds and declared image dimensions. PDF
  checks cover the version, trailer and an in-range cross-reference pointer.
  These are framing checks; they do not fully decode image codecs or PDF objects.
- The provider response has a 1 MiB streamed body limit and a 60-second timeout.
  Oversized streams are cancelled. Provider decoding and size failures produce
  fixed upstream error codes without provider-body disclosure.
- The response policy accepts one completed assistant JSON message, optionally
  preceded by bounded reasoning metadata. It rejects incomplete status, tools,
  refusals, alternate answers, unsupported content, conflicting SDK text aliases,
  excessive depth/node/byte counts and duplicate JSON keys. Reasoning metadata
  is discarded and never copied into the roster preview.
- Extracted JSON text is limited to 512,000 UTF-8 bytes. The document must contain
  exactly `rows`, with 1–500 records and exactly five fields per record. Row
  numbers are positive safe integers; confidence is a finite number from 0 to 1;
  names are at most 120 Unicode characters; phone text is at most 32 characters.
  Invalid types, unknown fields, control characters and lone surrogates fail
  closed. Legitimate multilingual names are retained. Unreadable fields and low
  confidence remain visible for correction rather than being invented.
- The shared AI preview helper and HTTP response keep `can_submit: false`.
  The UI requires moving extraction into its editor and preparing a deterministic
  preview before the separate group-creation action. This packet does not prove
  the complete source/approver audit or the authorization of that commit action.

## Evidence retained

| Artifact | What it proves |
| --- | --- |
| [roster-validation.json](roster-validation.json) | Exact commands, zero exit codes, runtime digest, log digests and unchanged source fingerprints for the pinned run. |
| [roster-tests.log](roster-tests.log) | **51 passed, 0 failed:** 24 strict-response tests, 19 file-policy tests, 3 AI request/preview tests and 5 deterministic roster tests. |
| [entrypoint-check.log](entrypoint-check.log) | `prepare-roster-import/index.ts` passes type checking under Deno 2.5.6 / TypeScript 5.9.2. |
| [source-sha256.json](source-sha256.json) | SHA-256 identities of 14 source/configuration files; all matched again when this packet was prepared. |
| [verification.json](verification.json) | Download provenance, archive and binary digests, runtime version and official-checksum matches. |
| [official-release-assets.json](official-release-assets.json) | Selected official GitHub release asset metadata, with the source response digest. |
| [deno-aarch64-apple-darwin.zip.sha256sum](deno-aarch64-apple-darwin.zip.sha256sum) | Original official checksum file copied unchanged. |
| [copy-verification.json](copy-verification.json) | Source-to-packet hash comparisons for the seven copied evidence files and hashes for generated packet material. |

The initial type-check command used `--cached-only`, which Deno 2.5.6 does not
accept for `check`. Its diagnostic is preserved in
[entrypoint-check-initial-flag-error.log](entrypoint-check-initial-flag-error.log).
The corrected `check --no-lock` command passed. The final report retains the
initial attempt. No compatibility source changes were required. No root-level
Deno lockfile was used for this run; runtime matching is not proof of complete
third-party dependency pinning or supply-chain review.

The worker separately reported **10 actual-handler HTTP tests plus 45 existing
handler tests passing** under Bun 1.4.0, using isolated host, database and HTTP
doubles. Roster cases covered valid hashed previews, incomplete or ambiguous
model output, tools, invalid row types, cancelled oversized response streams,
malformed provider JSON, spoofed uploads and unchanged deterministic previews.
The mock database permits only the permission RPC and feature-flag read, so an
unexpected mutation fails those tests. Those command outputs were observed in
the task but were not saved as independent log files; their counts are therefore
worker-reported supplementary evidence in this packet. They are not part of the
51-test pinned Deno result. They made no real provider requests or production
mutations. The HTTP runner is
[run_edge_http_tests.py](../../../scripts/hardening/run_edge_http_tests.py) and
the separate roster suite is
[roster_http.test.cjs](../../../scripts/hardening/roster_http.test.cjs).

## Runtime provenance and reproduction

The bounded common-location search found Deno 2.9.6 only. The pinned runtime was
then downloaded into the ignored task cache, without modifying global tools.
The archive matched both the
[official checksum file](https://github.com/denoland/deno/releases/download/v2.5.6/deno-aarch64-apple-darwin.zip.sha256sum)
and the asset digest in the
[official Deno 2.5.6 release](https://github.com/denoland/deno/releases/tag/v2.5.6).
The binary and archive are deliberately not copied into this packet.

| Item | SHA-256 |
| --- | --- |
| Official archive | `32a5b2bcf49432715719c7c769529269fbd08cafdc059b7cecd42f9d771059ab` |
| Extracted runtime binary | `a371e0605be5039a91a079a802d66b22c124a42e31573e43136c93c2b362f1c0` |
| Source fingerprint file | `795acce63c6ce1664b120eb59c69e4ea1ef20f79c50a8a57390d3fbbe1735181` |
| Pinned validation report | `3c4589d0a0991757cba19d18081a19b6ce4a56382828bc29c70c6bd9adc70466` |

Run from the repository root; the report contains the absolute runtime path used:

```sh
.cache/roster-deno-2.5.6-20260929/deno test --cached-only --no-prompt --no-lock \
  supabase/functions/_shared/roster_response_policy_test.ts \
  supabase/functions/_shared/openai_roster_test.ts \
  supabase/functions/_shared/roster_import_test.ts \
  supabase/functions/_shared/roster_file_policy_test.ts
.cache/roster-deno-2.5.6-20260929/deno check --no-lock \
  supabase/functions/prepare-roster-import/index.ts
```

## Remaining acceptance work

1. Implement and test full bounded image/PDF decoding, aggregate animation limits,
   PDF page/object-stream expansion limits, and corrupt/decompression-heavy
   fixtures. Current header dimensions and file-byte caps do not prove these.
2. Implement and concurrently test durable per-account extraction quotas and
   production cost controls; approve operational values with the accountable owner.
3. Verify the deployed function, configuration and limits, then exercise the
   actual vendor integration with approved fixtures. Mock responses do not prove
   model accuracy, retention, processing geography or vendor configuration.
4. Complete A02 labeled multilingual/scanned/prompt-injection evaluation and
   A01 immutable source/approver audit and commit-path authorization testing.
5. Run whole-repository release checks against a reviewed, frozen candidate.
   This evidence is bound to file hashes in a modified checkout.

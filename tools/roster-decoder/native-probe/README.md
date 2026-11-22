# Native roster dependency investigation

These standalone probes preserve the engineering evidence for the open native
roster decoder task. They execute real WASM engines in the exact Supabase Edge
Runtime `v1.77.4` binary, whose SHA-256 the runner verifies. **They do not
implement or qualify the production signed roster decoder contract.** The
application's optional AI decoder remains disabled.

The original request/response contract pins Python/Pillow/pypdf/PDFium/openpyxl
and Linux isolation. A replacement needs a distinct truthful versioned contract,
Supabase-owned replay/outcome custody, complete format rules and resource tests.
Passing a format's existing examples alone does not establish that replacement.

## Preserved inputs

- `dependencies.lock.json` pins six public npm archives by URL, exact version,
  byte length, SHA-256 and SHA-512 integrity. Three are executed: Magick WASM
  0.0.45, PDFium wrapper 3.0.0 and qpdf wrapper 0.3.0 (the actual qpdf engine
  reports 12.2.0). `fast-png` 8.0.0, `iobuffer` 6.0.1 and `fflate` 0.8.3 are
  preserved for source-review reproducibility; they are not executed here.
- `corpus/` preserves the exact 35 public synthetic fixtures used during the
  investigation. Its original manifest and `corpus-provenance.json` record
  expected labels, actual hashes and generation versions. Timestamps and
  generator versions can change newly generated PDF/workbook bytes, so a new
  generation is not silently substituted for this packet.
- The corpus was generated using Python 3.12.14, Pillow 12.3.0, pypdf **6.10.0**
  and openpyxl 3.1.5. That is a generator description, not a claim that the
  existing decoder's pinned pypdf 6.19.0 was executed.
- `upstream-source-review.lock.json` identifies exact files inspected from
  Supabase Edge Runtime tag `v1.77.4`, including the actual inner snake_case
  permission fields. A future implementation must re-review a changed runtime.
- Source adapters, the preparer and the runner remain in this directory. The
  native result pins all of their bytes, every preserved corpus file, the actual
  prepared JS/WASM/archive bytes, and the native executable.

The preparer verifies archive checksums and exact package metadata before
reading only named regular members. It never runs npm install hooks. The npm
signature/attestation flags in the lock remain false: checksum reproducibility
is not independent provenance verification or release dependency approval.

## Reproduce

Use a new physical preparation directory and a new private attempt directory.
Preparation downloads only pinned public npm archive URLs. An optional archive
directory can supply exact files named `<sha256>.tgz`; their checks are identical
to the downloaded path.

```sh
python tools/roster-decoder/native-probe/prepare.py \
  --directory /absolute/path/to/new-prepared-roster-probe

COLLECT_CI_SYNTHETIC=true node tools/roster-decoder/native-probe/run.mjs \
  /absolute/path/to/exact-edge-runtime-1.77.4 \
  /absolute/path/to/new-prepared-roster-probe \
  /absolute/path/to/new-private-native-attempt \
  /absolute/path/to/new-safe-observation-receipt.json
```

The native binary must have SHA-256
`7883510fe308b4b5c49ec0a8e2020ec81c5fa41133239f3969a372b1cbf107ba`.
Node 24 is the qualified runner environment. Port `127.0.0.1:9178` must be
unused; the runner refuses an occupied port. It starts and stops only its own
Edge child process and never opens a database connection.

The main service creates a fresh user worker per request with no environment
entries, no remote/npm module resolution, explicit network/environment/write/
subprocess/FFI/system denials and a static WASM path. It configures 384 MiB,
4/5 second CPU thresholds and a 10 second wall timeout. `oneshot` runs with
parallelism 1. Observing those settings is not an exhaustion test of the caps
and does not establish production concurrency or supervision behavior.

Every observation includes the worker's network, environment, filesystem and
subprocess probes. A `NotFound` result for `/etc/hostname` is explicitly not
claimed as a permission denial. Network/environment/write `NotCapable` results
and subprocess failure are recorded separately. Only synthetic corpus files
are supplied; no customer upload, credential, provider request or live record
is involved. Native diagnostics stay in the private attempt directory.

The runner deliberately reports `parser_contract_qualified: false` and
`production_acceptance: false`, even when all observations complete. Its
`findings` fields indicate whether known gaps were reproduced; a completed
investigation is not a passing parser qualification.

## What the probe compares

| Lane | Work actually executed | Interpretation |
|---|---|---|
| Image, default | Decode all collection images and materialize RGBA | Reproduces truncated JPEG acceptance and default PNG animation loss. |
| Image, warning strict | Attach JPEG warning rejection before read; explicitly select APNG for the known animation fixtures | Demonstrates the JPEG fix and the APNG codec's external-delegate limitation. The fixture-selected format is not an application file classifier. |
| PDFium | Load and fully rasterize all bounded pages | Demonstrates rendering; rendering alone accepts several documents forbidden by the existing structure policy. |
| qpdf | Parse object/xref streams to JSON, inspect all emitted objects, bound generalized decoded streams and reject warnings/active keys | Tests the ten current PDF structural fixtures. It is a prototype, with semantic equivalence and combined rendering/isolation still unqualified. |

The qpdf Emscripten wrapper's original CommonJS bytes are embedded unchanged
between the small reviewed prefix/suffix. The prefix selects its existing
browser branch and captures diagnostics with a 64 KiB bound. A Blob URL supplies
the pinned static WASM bytes without network access. JSON and decoded streams
remain in the worker's in-memory filesystem. This is an explicit adapter under
review, not an upstream Deno support claim.

Workbook fixtures are preserved but **no native workbook parser is executed**.
The optional source-reviewed APNG alternative has not been natively qualified.
The prototype does not persist nonces, create signed responses, dispatch an AI
request, enforce approval, or replace any application route.

## Primary implementation references

- [Supabase image manipulation/WASM example](https://supabase.com/docs/guides/functions/examples/image-manipulation).
- [Pinned Supabase user worker source](https://github.com/supabase/edge-runtime/blob/v1.77.4/ext/workers/user_workers.js).
- [Pinned worker permission definitions](https://github.com/supabase/edge-runtime/blob/v1.77.4/ext/workers/lib.rs).
- [Magick WASM upstream](https://github.com/dlemstra/magick-wasm).
- [PDFium WASM wrapper upstream](https://github.com/hyzyla/pdfium).
- [qpdf 12.2 JSON interface and complete object representation](https://qpdf.readthedocs.io/en/12.2/json.html).
- [qpdf WASM package upstream](https://github.com/neslinesli93/qpdf-wasm).
- [fast-png source](https://github.com/image-js/fast-png).

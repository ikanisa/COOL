# Native roster decoder: concrete feasibility and remaining work

## Decision

The owner has since selected a static-image-only roster policy: animated
images must be rejected with an actionable message. Full APNG decoding and a
dedicated APNG supervisor are no longer release requirements. The observations
below are retained as historical evidence; they do not authorize animation
delivery or prove the static-only policy is deployed.

**Original task 29 remains open.** The pinned Supabase Edge Runtime can execute
the reviewed candidate WASM engines in a restricted disposable worker, so a
Supabase-owned replacement is technically plausible. The current investigation
does not establish a complete replacement for the signed Python decoder. The
production template continues to keep the optional roster AI decoder inactive.

The remaining gaps include static-image validation and animation refusal, equivalent PDF
structure semantics combined with rendering, the bounded workbook parser, a
truthful version 2 signed contract, PostgreSQL replay/outcome custody, and
resource/isolation acceptance. No existing Python toolchain identity has been
forged, no file-header shortcut has replaced decoding, and no SQLite authority
has been introduced into the Supabase backend.

`tools/roster-decoder/native-probe/README.md` contains exact reproduction steps.
That directory preserves the 35 synthetic fixtures, actual generator provenance,
dependency/source locks, small adapters, archive verifier and native runner.
The final receipt, `roster-native-observations.json`, binds actual source,
corpus, prepared dependency and native executable bytes before/after execution.
Its flags explicitly deny parser-contract and production acceptance. The
earlier exploratory attempts are separate historical evidence, without a
retroactive claim of complete per-attempt source binding.

## Why the original contract cannot be relabeled

The application bridge in
`supabase/functions/_shared/roster_decoder_bridge.mjs` validates an exact
versioned toolchain map. The current decoder uses Python 3.12, Pillow 12.3.0,
pypdfium2 5.2.0, pypdf 6.19.0, openpyxl 3.1.5 and defusedxml 0.7.1. Its supervisor
verifies signed source/reservation/request identities and persists replay
nonces. Its child combines Linux process isolation, denied socket/process
capabilities, memory/CPU/wall limits and full format validation.

The candidate engines have different truthful identities: Magick WASM 0.0.45,
PDFium wrapper 3.0.0, and qpdf WASM wrapper 0.3.0 with actual qpdf 12.2.0. They can
support a distinct native contract after review. Returning the old Python map
from those engines would defeat the existing provenance check.

The exact synthetic corpus was generated with Python 3.12.14, Pillow 12.3.0,
pypdf 6.10.0 and openpyxl 3.1.5. The older generator pypdf version is disclosed in
the preserved provenance. It is not described as execution of the decoder's
pinned pypdf 6.19.0. Preserving the exact fixture bytes avoids silently changing
PDF/workbook timestamps or library-generated structures between comparisons.

## Executed findings and their limits

| Area | Native evidence | Remaining acceptance |
|---|---|---|
| Runtime compatibility | Actual Edge 1.77.4 / Deno 2.1.4 loads the pinned image, PDFium and qpdf WASM engines without npm/network resolution in the child. | Independent dependency provenance, license/security review and a reproducible release build remain separate from tarball checksum identity. |
| Static PNG/JPEG/WebP and animated WebP | Historical candidate code materializes full RGBA pixels. The existing corpus covers malformed/truncated files, CRC, dimensions and frame count. | Qualify static formats and fail-closed animation detection and refusal, including resource bounds. |
| JPEG strictness | Default Magick accepted the truncated JPEG. Installing the warning callback before reading rejects it. | All relevant warning classes must fail closed in the production adapter; this probe only establishes the concrete supplied sample. |
| PNG animation | Default PNG decoding returned one frame for three-frame APNG and accepted a 21-frame file. Explicit APNG selected the codec that requires an unavailable external ffmpeg delegate, rejecting even the valid three-frame fixture. | Detect and refuse animated PNGs; a decoder that silently drops frames does not establish static-only enforcement. |
| PDF rendering | PDFium renders bounded pages, including compressed-object PDFs. Rendering alone also accepted JavaScript/attachment and oversized stream examples forbidden by current policy. | Rendering must follow full structural checks; renderer success is insufficient validation. |
| PDF structure | qpdf JSON exposes complete object and decoded-stream data; the prototype correctly handles the ten existing PDF structural labels, including compressed objects, encryption, active content, malformed xref and 33 MiB expansions. | Complete semantic equivalence, normalized name/string action values, indirect references, filter combinations, all unreferenced objects, allocation order, and integration with rendering remain unqualified. |
| Child isolation | Workers receive no environment entries. Recorded network/environment/write denials and subprocess failure occur in the real pinned runtime. | A missing `/etc/hostname` is only `NotFound`, not a proved permission denial. Existing-secret canaries, FFI/system probes, worker teardown, CPU/memory exhaustion and concurrent supervision require explicit tests. |
| Resource configuration | Fresh workers are configured for 384 MiB, 4/5 second CPU thresholds, 10 second wall time and parallelism 1. | These settings are not exhaustion evidence or acceptance of the old 8 second wall contract. A native version 2 budget must be explicit and tested. |
| Workbooks | Exact current XLSX corpus bytes are preserved. No native workbook decoder was run. | The entire bounded ZIP/XML/workbook semantic implementation remains required. |

The source-reviewed `fast-png` alternative includes APNG support, but its
reviewed APNG frame path calls its noninterlaced decoder. That source fact is a
reason to qualify interlaced and other variants before selection; it is not an
executed claim that every APNG fails. The package and its exact dependencies
are pinned for reproducible review, with `source_review_only` scope. They were
not substituted into the application or presented as a solved APNG dependency.

The qpdf probe preserves the original package JavaScript between an explicit
browser-branch wrapper and a bounded diagnostic adapter. Static WASM is loaded
through an in-memory Blob URL; emitted JSON and streams remain in the worker's
memory filesystem. The actual engine reports 12.2.0. The prototype's acceptance
of the current ten labels is useful feasibility evidence, not proof that its
new representation preserves every pypdf rejection rule. The original Python
decoder's validation remains unchanged.

## Concrete implementation plan and acceptance gates

### 1. Complete native file validation

Select or build a reviewed image validator that fully decodes supported static
JPEG/PNG/WebP, including interlaced/color/alpha variants, CRC errors and
truncated payloads. Detect and reject animated images without silently treating
them as static. Preserve the applicable input, dimension and pixel limits;
decode limits must bound allocation, not only check dimensions after unbounded
work. Full animation-frame decoding and compositing are no longer required.

For PDF, integrate the qpdf structural stage and PDFium raster stage inside one
disposable worker. Normalize the JSON representation without losing current
active-key/action semantics. Review all objects, including unreferenced and
compressed objects; retain encryption refusal, 5,000 objects, 20 pages, depth 40,
100,000 graph events, 2,000 streams, 32 MiB expanded-stream total and 16 million raster
pixels. Test alternate filters, nested references, malformed xrefs, warning
recovery and compressed-object expansion before a response can be accepted.
The structured representation and upstream parser may allocate before a
post-parse limit; exhaustion tests must prove the containing worker budget.

Implement the native XLSX path with the original central/local ZIP integrity,
safe names/types/flags, complete read/CRC checks, 64 entries, 2 MiB per entry, 8 MiB
total and bounded expansion ratio. XML parsing must reject DTD/entities and
external references and preserve the 100,000-event limit. Workbook semantics
must preserve row/column/cell/text limits, exact supported types, formula,
macro/binary and link refusal, deterministic header mapping and original
workbook provenance. Client-derived rows cannot be relabeled as decoding the
original workbook bytes.

### 2. Introduce a truthful native version 2 contract

Define a separate signed request/response version and truthful native
toolchain/build identities. Preserve source hash and byte length, MIME/kind,
reservation/request/operation/nonce identity, bounded timestamps, response
hash, deterministic rejection and row/text provenance. The existing version 1
contract stays explicit; a native response cannot pretend to be its pinned
Python implementation. The current human review and revision-bound commit
remain the final application authority.

### 3. Move replay and outcome custody into private Supabase PostgreSQL

Use an additive, reviewed migration for unique operation/nonce reservations
and retained outcome evidence under the application's source/epoch fence.
Keep database transactions short while parsing runs in a separate disposable
worker. Exact same-operation readback must resolve a lost response; an unknown
outcome cannot be silently replayed, expired or erased. Capacity/cleanup must
exclude only proved settled history and retain unresolved obligations. The
database must remain the sole replay authority; a Python SQLite cache cannot
serve as a second backend.

Prove request races, replay across processes, source/profile/epoch changes,
timeout with uncertain worker teardown, exact response recovery and bounded
maintenance on actual PostgreSQL. Add the new retained class to privacy,
backup and recovery inventories with explicit personal/shared selectors.

### 4. Qualify the real Supabase service boundary

Use the pinned Edge runtime's actual permission fields and a fresh child for
each parse. Keep signing/provider/database credentials in the parent. Prove
that the child cannot read a known existing secret outside its public input
mount, access parent environment, perform network or filesystem writes, spawn
processes or use FFI. Exhaust CPU/memory/wall limits with adversarial corpus
and prove child exit before releasing its capacity slot. Qualify concurrency,
shutdown, abandoned requests and the native response-size limit. The current
parallelism 1 dependency probes do not establish production scheduling.

Add the new closed router entry and worker-specific environment projection
only after the native contract and custody are implemented. Test unauthenticated
and incorrectly signed requests, crossed profile/source, over-limit inputs and
all representative formats against the actual current migration chain and
exact release binary. Run the signed integration corpus with source-bound
receipts and exact expected outputs, without a replacement mock parser.

### 5. Enable only after platform and provider acceptance

The completed native implementation still needs the actual self-hosted image,
deployment identity, storage/key custody, backup/restore and resource-envelope
acceptance. Processor approval, configured model/project and external provider
retention remain explicit requirements for AI dispatch. Optional settings can
remain empty until those gates close. Configuration presence alone is neither
parser qualification nor authorization to send roster data.

## Sources and durable evidence

The original implementation and exact bridge are the requirements used for
this comparison. The independent runtime and library references are:

- [Supabase WASM image example](https://supabase.com/docs/guides/functions/examples/image-manipulation).
- [Exact worker construction](https://github.com/supabase/edge-runtime/blob/v1.77.4/ext/workers/user_workers.js) and [permission definitions](https://github.com/supabase/edge-runtime/blob/v1.77.4/ext/workers/lib.rs).
- [Magick WASM upstream](https://github.com/dlemstra/magick-wasm) and [PDFium WASM wrapper](https://github.com/hyzyla/pdfium).
- [qpdf 12.2 JSON documentation](https://qpdf.readthedocs.io/en/12.2/json.html), including complete object representation and external stream-data output.
- [qpdf WASM wrapper source](https://github.com/neslinesli93/qpdf-wasm).
- [fast-png source](https://github.com/image-js/fast-png).

The final observation receipt and preserved corpus should accompany the
implementation plan. The remaining task is substantive parser/authority work;
it is not resolved by replacing a URL or adding an unchecked dependency.

## Preserved harness corrections

The first final preflight refused an ordering mismatch between Python path-component sorting and JavaScript relative-path sorting before any child started. `roster-native-preflight-note.json` preserves its source identity and explanation. The canonical relative-path order was corrected in the standalone preparer.

A subsequent exact-source run completed all 45 engine observations and reproduced every stated finding, but its last version assertion expected the program display name `qpdf`. The unchanged Emscripten wrapper reports `this.program version 12.2.0`. That incomplete receipt remains in `roster-native-observations-version-check-failure.json`. The corrected standalone runner accepts the two exact display prefixes while still requiring engine version 12.2.0, and uses a new prepared directory and result. The native decoder, corpus, dependencies and application code were not changed for that correction.

## Final source-bound observation result

The final runner completed all **45** observations, reproduced all eight concrete finding indicators, verified unchanged source/prepared/binary bytes, and stopped its own native child. `parser_contract_qualified`, `provider_accuracy_verified` and `production_acceptance` remain false. The final observation receipt SHA-256 is `821259266b388fc272115057f4ac51a86b9b4c26a3cd3afcecd8b86bb961d79a`. Its probe source graph SHA-256 is `92d187d3503341ccead7c52ef13d35e0e4c3c2eb73ff244f1ccba886cf70a550`.

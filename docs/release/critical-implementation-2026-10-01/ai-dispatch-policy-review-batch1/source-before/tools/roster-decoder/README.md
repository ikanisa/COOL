# Collect roster decoder

Repository-owned codec/workbook validation boundary for `prepare-roster-import`.
It performs complete Pillow PNG/JPEG/WebP decoding of every animation frame,
strict PDF object/stream inspection and PDFium rendering of every page, and
independent bounded ZIP/XML/openpyxl workbook-to-TSV derivation.

## Isolation and limits

- Linux child per job: networking/socket/exec/fork/ptrace syscalls denied by
  seccomp; no provider/database/signing credentials in the child environment.
- Read-only container, no Linux capabilities, no new privileges, bounded PIDs,
  memory/CPU, connection count and temporary filesystem.
- Child: 384MiB virtual memory, 4s CPU soft / 5s hard, 8s supervisor wall timeout,
  32 descriptors, zero file-output allowance and no core dumps.
- Input: 5MiB; images: 16 million total decoded pixels, 16,000px maximum side,
  20 frames; PDF: 20 pages, 5,000 objects, 2,000 streams, bounded traversal,
  32MiB decoded streams, 16 million total raster pixels; XLSX: 64 ZIP entries,
  2MiB per entry / 8MiB expanded, 10 sheets, 501 rows, 32 columns / 16,320 cells,
  500 member rows / 512KB UTF-8 TSV.
- Reject PDF JavaScript/launch/attachments/encryption and workbook formulas,
  external references, macros, hidden binary attachments, DTD/entities, invalid
  original formats, truncation, malformed CRC/content and expansion limits.

The networked supervisor accepts only HMAC-authenticated, short-lived requests.
Nonces are claimed atomically in SQLite before decoding and reject replay.
Responses sign the exact UTF-8 payload and bind request/reservation/nonce, original
source hash/size, toolchain/policy/build hash, decoded bounds and derived TSV/hash.
The Edge adapter requires the configured build hash and compares workbook TSV
byte-for-byte before any source registration or provider transmission.

The legacy142 client receipt remains compatible and conservatively labels its
TSV `client_derived_tsv`. New146 private verification records retain independently
verified derivation and the signed decoder receipt hash; no label is silently
upgraded on historical imports.

## Local verification

Install the pinned generation dependencies into a task-local virtualenv. Provide
the six exact Linux ARM64 wheels selected by `requirements.lock`, their retained
official PyPI release metadata, and the whole SHA256 of the separately reviewed
publisher-input receipt. The source pool may also contain Mac fixture wheels;
only the six receipt-selected Linux wheels enter the private build context.
Then run:

```sh
python scripts/tests/verify_roster_decoder.py \
  --python /absolute/path/to/task/venv/bin/python \
  --wheel-source /absolute/path/to/authenticated/wheels \
  --publisher-receipt /absolute/path/to/publisher-inputs.json \
  --publisher-sha256 REVIEWED_WHOLE_RECEIPT_SHA256 \
  --metadata-directory /absolute/path/to/retained/pypi-metadata \
  --output /absolute/path/to/new/evidence-directory
```

The runner verifies source, metadata, package/version, ABI, size and lock hashes,
copies a fresh private build context and rechecks its complete contents before
building. Dependency installation uses a read-only wheelhouse, no package index,
no build cache and no network. Missing, substituted or changed selected inputs
fail; there is no network fallback or reuse of an old decoder image.

The runner builds from current sources, generates synthetic files, starts an
isolated loopback supervisor, runs real format/malformed/resource/HMAC/replay
checks, runs all six dependency security tests on that networkless Linux image,
probes actual Linux network/memory/CPU enforcement, runs the actual Deno
adapter integration tests and removes its own supervisor. It makes no DB,
provider, hosted Auth or customer-data calls. Preserve failed attempts.

## Deployment configuration

Build using the pinned base image and hash-locked Python3.12/Linux aarch64 wheels.
A different architecture requires its own reviewed wheel hashes and verification.
Use `scripts/qa/roster_wheelhouse.py` with the same explicit wheel/receipt/metadata
inputs, `--decoder-directory tools/roster-decoder` and a fresh `--destination` to
prepare the build context. Build that prepared directory with
`docker build --no-cache --network=none`; a raw source-directory build lacks the
required wheelhouse. The local verification runner also rechecks copied bytes
immediately before invoking Docker.
Run with the same flags used by the runner and a durable nonce state volume. Bind
the service behind an authenticated TLS route; requests must reach this fixed
operator-configured endpoint only. Provision the same strong random signing
secret separately to the supervisor and Edge function.

Required Edge settings: `ROSTER_DECODER_URL`, `ROSTER_DECODER_SECRET` (at least32
UTF-8 bytes), `ROSTER_DECODER_BUILD_SHA256`. The build hash is SHA256 of compact,
sorted JSON mapping `decoder.py`, `server.py`, `requirements.lock` and `Dockerfile`
to their SHA256 hashes. Use the actual runner receipt for the exact built sources;
a source edit changes the required value. A local source digest does not prove
which image or configuration a hosted service runs.

Migration146 must precede the new Edge handler. Its policy ceilings are internal
engineering count/byte/concurrency/cost units; cost units are conservative
attempt charges and are **not provider currency invoices or live pricing**.
An unknown or failed attempt retains its full daily charge; an ambiguous attempt
also retains its active lease for180s. A request cannot be redispatched after
crash/timeout; a new explicit upload receives a new request and quota charge.

Hosted activation, TLS/service-secret provisioning and provider accuracy remain
deployment/evaluation gates. Local verification does not claim those occurred.

Primary references: [Supabase runtime limits](https://supabase.com/docs/guides/functions/limits),
[Pillow image safety](https://pillow.readthedocs.io/en/stable/reference/Image.html),
[PDFium wrapper](https://github.com/pypdfium2-team/pypdfium2),
[openpyxl security](https://openpyxl.readthedocs.io/en/stable/),
[OpenAI Responses instruction roles](https://developers.openai.com/api/reference/cli/resources/responses/methods/create).

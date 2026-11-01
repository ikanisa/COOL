# Collect roster decoder

Standalone codec/workbook validation source retained for Collect roster imports.
The current application routes live in
`supabase/functions/_shared/domain/roster.js`. This Python helper is not a
Supabase Edge Function and does not satisfy the native Supabase parser gate by
itself; see `docs/architecture/roster-ai-dispatch-policy.md`.

## Decoder controls

The decoder performs Pillow PNG/JPEG/WebP decoding of every animation frame,
PDF object/stream inspection and PDFium rendering of every page, and bounded
ZIP/XML/openpyxl workbook-to-TSV derivation. It rejects active PDF content,
workbook formulas and external references, malformed source files and expansion
limits. Input and output bytes, image dimensions, frame/page counts and workbook
rows/columns are bounded in `decoder.py`.

On Linux, each job runs in a separate process with networking, socket, execution,
fork and tracing syscalls denied by seccomp. The child receives no provider,
database or signing credentials. `server.py` applies connection, replay, timeout
and resource limits. Run the container read-only, without Linux capabilities or
new privileges, with bounded memory, CPU, PIDs and temporary storage.

The HTTP supervisor accepts HMAC-authenticated requests with request, reservation,
nonce and policy identities. It stores nonce claims in SQLite and signs the exact
response payload, including source and build hashes. Provision a strong
`ROSTER_DECODER_SECRET` separately from source and persist the nonce state volume.

## Locked build inputs

Build with the pinned base image and the hash-locked Python 3.12/Linux ARM64
wheels in `requirements.lock`. A different architecture requires its own reviewed
wheel hashes and verification. The acquisition helper captures official package
metadata and exact lock-selected wheel bytes into a fresh directory:

```sh
python3 -B scripts/qa/roster_wheelhouse.py --acquire \
  --lock-file tools/roster-decoder/requirements.lock \
  --lock-sha256 REVIEWED_WHOLE_LOCK_SHA256 \
  --destination /absolute/path/to/fresh/publisher-inputs
```

Use the helper's explicit wheel, receipt and metadata arguments with
`--decoder-directory tools/roster-decoder` and a fresh `--destination` to prepare
a private build context. Build that prepared directory with
`docker build --no-cache --network=none`. The source directory alone has no
wheelhouse and is not a complete image build context. Preserve the acquired
metadata, source hashes and publisher receipt outside this repository.

## Supabase integration status

The current Supabase application requires a `ROSTER_DECODER` adapter and an
approved processing policy. The signed protocol adapter is implemented in
`supabase/functions/_shared/roster_decoder_bridge.mjs`, with application and
protocol tests in `deploy/platform-api/test/supabase_roster_decoder_*`. The
adapter verifies exact source/build/request/reservation/nonce lineage and signed
outcomes. Those tests use transport doubles; they do not establish a deployed
Linux parser or exact runtime/container qualification.

The supervisor's persistent SQLite replay state is a separate backend. It must
not be silently enabled in the Supabase-only production deployment. A faithful
native parser and private Supabase replay journal remain a release gate; an
Edge Function proxy or file-header-only parser does not close it. Roster AI stays
disabled in that deployment until those capabilities and the processor policy
are qualified.

Run the existing canonical roster tests from `deploy/platform-api` with
`node --test test/ingestion.test.mjs`. Those tests do not establish a deployed
Linux decoder, production credentials, provider accuracy or device acceptance.

Primary references: [Pillow image safety](https://pillow.readthedocs.io/en/stable/reference/Image.html),
[PDFium wrapper](https://github.com/pypdfium2-team/pypdfium2),
[openpyxl security](https://openpyxl.readthedocs.io/en/stable/).

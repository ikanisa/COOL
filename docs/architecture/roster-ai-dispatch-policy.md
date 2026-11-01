# Roster extraction policy and Supabase deployment

The current application implementation is `supabase/functions/_shared/domain/roster.js`. It runs through the authenticated Collect Admin API, private Supabase Storage adapter, SQL import/commit guards and application admission fence. The old Cloudflare source and earlier release documents remain provenance; they do not establish the current deployed behavior.

Text, UTF-8 CSV and the existing client-derived XLSX path are deterministic. The XLSX receipt explicitly records `derived_assurance: client_derived_tsv`; the server checks the retained source and derivative hashes, parses the submitted derivative, and requires human review before commit. That receipt does not claim server-side workbook-to-TSV validation. PDF/image extraction additionally needs the exact independently approved AI and decoder policy below. Human review and an acknowledged source/revision remain required for either path.

## Required inactive configuration

| Value | Current binding |
|---|---|
| `ROSTER_AI_APPROVAL_JSON` | Exact compact approval JSON, no more than 16,384 JavaScript characters. |
| `ROSTER_AI_APPROVAL_SHA256` | Lowercase SHA-256 of the complete raw approval bytes. |
| `ROSTER_AI_MODEL` | Exact approved model. No model is selected by this document. |
| `OPENAI_API_KEY` | Server-side provider credential; never supplied to the decoder child. |
| `OPENAI_PROJECT_ID`, `OPENAI_ORGANIZATION_ID` | Exact approved project and organization; sent as request headers. |
| `ROSTER_DECODER_PROTOCOL` | `roster-hmac-v1`. |
| `ROSTER_DECODER_URL` | Signed-supervisor transport URL: HTTPS, `/decode`, no credentials, query or fragment, port 443/default. |
| `ROSTER_DECODER_SECRET` | Dedicated supervisor HMAC key, 32–4,096 UTF-8 bytes. |
| `ROSTER_DECODER_BUILD_SHA256` | Exact approved decoder source/build identity. |

The policy binds schema version 1, enabled/approved status, purpose `collect_roster_pdf_image_extraction`, provider `openai`, approval UUID and evidence hash, a current approval window, the exact organization/project/model/build, and bounded processor, residency and retention evidence references for both the AI provider and decoder. `responses_endpoint` is fixed to `https://api.openai.com/v1/responses`. `decoder_url` is the logical binding `https://roster-decoder.internal/decode`; the signed bridge separately fixes the physical HTTPS transport destination above.

The application validates the policy before extraction and rechecks its raw bytes, digest, effective settings and expiry at dispatch boundaries. It records the approved policy, source/object hashes, processor/project/model, decoder lineage and dispatch phase in SQL. An environment template containing empty fields is not an approval. Changing settings or allowing the policy to expire does not authorize replay of a previously ambiguous provider dispatch.

## Existing signed decoder integration

`supabase/functions/_shared/roster_decoder_bridge.mjs` translates the logical request into the existing Python supervisor's authenticated protocol. It binds the processing/request UUID, reservation/import UUID, source hash, nonce, freshness window and approved build. The exact response payload is verified before content can reach the model. It enforces source, request, response and decoded-content bounds, rejects redirects/mismatched lineage, and retains uncertain work through the application fence. Its protocol and application tests are `deploy/platform-api/test/supabase_roster_decoder_protocol.test.mjs` and `supabase_roster_decoder_bridge.test.mjs`; they exercise the current Supabase modules but do not run native codecs or prove a deployed decoder.

The real parser remains in `tools/roster-decoder/decoder.py`. It fully decodes supported image frames, inspects PDF objects/streams and active content, renders every supported PDF page, and bounds workbook ZIP/XML expansion and cell semantics. Its Python 3.12, Pillow, PDFium/pypdfium2 and pypdf implementation runs inside a disposable Linux process with memory/CPU/file/socket/process controls. `server.py` authenticates requests and retains nonce replay authority in SQLite. The child receives no database, HMAC or provider credentials.

## Unclosed native Supabase parser gate

This helper is not a Supabase Edge Function. Its Python/native libraries, subprocess isolation and SQLite replay authority cannot be treated as equivalent to the user's Supabase-only backend requirement. Supabase documents Edge Functions as TypeScript/JavaScript/WASM execution and explicitly states that native image dependencies require a WASM alternative: [WASM modules](https://supabase.com/docs/guides/functions/wasm), [image manipulation](https://supabase.com/docs/guides/functions/examples/image-manipulation).

No equivalent qualified WASM parser, complete corpus comparison, per-job native isolation replacement or Supabase-backed durable decoder replay journal is present in this candidate. File headers and image dimensions do not replace the existing complete decoding and PDF inspection. A proxy to the Python helper would retain its separate runtime and SQLite backend; it would not close this gate.

The production self-host configuration must keep roster AI disabled until the following evidence exists:

1. A reviewed native Supabase function with pinned parser assets implements the existing image/PDF/container/expansion/active-content limits and proves them with the full valid and adversarial corpus on the exact Edge Runtime image.
2. Replay claims and original outcomes live in a private, admission-fenced Supabase schema, with bounded capacity and retained unknown obligations. Existing logical request/reservation/source/build bindings remain exact.
3. Parser isolation, memory, CPU, cancellation and concurrent-load behavior are qualified without giving untrusted parsing code database/provider secrets or broader filesystem/network access.
4. The processor, organization/project, region, retention, transfer, spend and model-quality decisions have actual approved evidence and the exact policy is bound to that deployed build. Provider/device/restore acceptance is recorded independently from synthetic protocol tests.

## AI provider copies

The current model request contains original PDF/image bytes after verified decoding; PDF uses a generic filename, which does not remove document content. The request sets `store: false`, uses structured output with no tools, and is still an external processor dispatch. Supabase hosts the application and its retained state; it does not host this OpenAI model. The fixed endpoint and evidence-reference strings do not prove regional processing or zero retention. OpenAI's official [data controls](https://developers.openai.com/api/docs/guides/your-data) describe the separate account and retention conditions.

Any transport failure after dispatch may leave an unknown external outcome. The import remains ambiguous and cannot be relabeled as a stopped, refunded, erased or successful request without original-outcome evidence. Retained sources, derivatives, processor records, holds and backup copies remain part of the governed retention inventory.

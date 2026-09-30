# Upload and extraction integrity — local implementation

Implements local goal items9–11 and13: complete supported codecs/pages, isolated
resource limits, durable concurrent quotas, original workbook verification and a
labeled evaluation harness. This packet contains synthetic data only.

## Changes

1. `tools/roster-decoder` supplies full PNG/JPEG/WebP frame decoding, strict PDF
   structure/stream checks plus complete PDFium page rendering, and bounded
   ZIP/XML/openpyxl derivation of canonical roster TSV. It runs each job in a
   networkless Linux process with memory, CPU, wall-time, file and output limits.
2. The Edge adapter validates a signed, nonce/request/reservation/source-bound
   receipt including exact decoder build, pinned toolchain, policy, decoded
   bounds and TSV/hash. A workbook-to-client-TSV mismatch rejects the upload
   before source registration, parsing or any provider request.
3. Migration146 adds immutable private reservations, completions and source
   verification receipts. Actor/global daily count, bytes and worst-case attempt
   cost units are charged atomically; concurrent active work is bounded. The
   policy row receives a same-value UPDATE as a REPEATABLE READ serialization
   fence. No crash/replay grants another attempt, and ambiguity retains its full
   charge and active lease until expiry. A missing finish ACK can be repaired
   using an already durable142 preview/failure.
4. New source creation requires matching budget and source verification. Existing
   provenance and client receipt shapes remain compatible. Original142/144
   historical evidence is preserved; a separate final146 compatibility test
   exercises the new prerequisites before review, commit and reload.
5. English/French/Kinyarwanda/Swahili CSV header aliases are recognized; duplicate
   semantic headers are rejected. Trusted OpenAI extraction instructions now use
   the Responses `instructions` field. Uploaded content stays user data;
   structured output, tool absence, nonpersistent requests, exact validation and
   human review remain enforced.
6. Evaluation fixtures cover multilingual text/scans, every supported binary
   format, malformed inputs, expansion/animation/page limits, ambiguity and
   prompt injection. The harness scores exact row fields/order, omissions,
   invented ready numbers and blocked rows. Recorded provider files can be
   scored separately; neither their existence nor synthetic probes prove live
   provider accuracy.

## Evidence and current limits

- `decoder-attempt3/validation.json`:30 actual HTTP/corpus/auth/replay/substitution
  checks, five supported formats, actual Linux network/memory/CPU enforcement,
  eight actual Deno signed-decoder integration tests; all passed with source
  hashes unchanged at capture. Its adapter budget helper predates the subsequent
  strict timezone/503 acknowledgement correction; use the final integrated
  packet for current-source coverage.
- `decoder-attempt4-final/validation.json`: passed30 actual codec/corpus/HTTP cases,
  credential isolation, eight actual Deno adapter tests,155 deterministic,
  response/receipt/evaluation regressions, five labeled deterministic corpus
  measurements, three evaluation contract probes, types and concurrency-harness
  syntax. All32 bound source inputs were unchanged. Manifest SHA256:
  `3ac742db80400c8cc42596dfd182c1380726cb009c7d099926fd1fa3e0fe56eb`.
- `decoder-attempt5-object-streams/validation.json` adds real PDF1.5 compressed
  Catalog/Pages/Page and xref-stream fixtures. The valid file renders; a33MiB
  compressed object stream rejects with `roster_pdf_expansion_limit`.
- `decoder-attempt6-all-format-handlers/validation.json` is the current decoder
  packet:32 actual codec/corpus/HTTP cases,14 actual signed-decoder integrations
  and155 regressions. Its six new cases connect actual Linux decoding to the
  unmodified upload handler across PNG/JPEG/WebP/PDF/XLSX and stop substituted
  workbook TSV before source/provider work. SQL/Auth/provider responses in these
  handler cases are explicitly recording fixtures. All32 source inputs remained
  unchanged; manifest SHA256:
  `7f033702fec174233bc52d9c85e1e6809524e83f0093b949490da3b2b292b9b8`.
  The integration source also type-checks with pinned Deno2.5.6.
- `edge-http-runtime-final/report.json`:71 passing real loopback HTTP checks on
  all9 current executable/configured Edge entrypoints, exact source hashes before
  and after, pinned Deno2.5.6 compilation, signed decoder/146/142 recording
  acknowledgements, preview replay, quota/error guards, OTP145 signed requests,
  deadline and no-resend checks. Provider network permissions are denied; three
  OTP transport attempts are recorded as denied and remain unresolved. No
  provider connection or acceptance occurred. Three retired bank ingestion
  routes are explicitly checked for source/config/listener absence. Failed and
  superseded HTTP attempts are preserved in `prior-http-attempts`.
- `edge-http-contract-final/validation.json` and its adjacent log:45 retained
  OTP/receipt/operator/integrity cases plus24 roster handler cases using a real
  signed loopback recording decoder and synthetic SQL/provider dependencies.
  The runner used its existing Bun fallback, so this run alone does not claim
  TypeScript compilation. Pinned Deno compilation is supplied by the preceding
  actual HTTP gate. These counts overlap other test scopes and are not additive.
- Root reports actual146 apply, rollback UAT, final142→144 compatibility and all
  seven real concurrency races passed on the exact guarded offline task database.
  This worker made no database, hosted Auth, provider or customer-data calls;
  root owns the separate database execution and restoration evidence.
- The earlier ff14 SQL candidate is retained in `prior-candidates/ff14ee019697`.
  It lacked the stale REPEATABLE READ row-version fence; it is superseded.
- Provider monetary prices are not represented by internal engineering cost
  units. Hosted activation, operator TLS/secret configuration, live model accuracy
  and release approval are not claimed by these local implementation tests.

## Root database execution

Frozen migration146: `d68f8fc45eb92b7ca34ac710548f105b926bfe9026e3214f0e8b030075026f4b`.
Rollback UAT: `badb9cdf37e14e090a4bb9ea4ec2d6a06dc3621b15b721cd8cd6f2e28cdfc6f6`.
Concurrency harness: `157b532a972b2280d16b2bb0a968dfad73d4fe6b3419c1f4f04c8090e4f9a9da`.
Compatibility UAT: `cf01acb18db68afd85d26cf11a241f796fa4649d2dbc4140237756bbe99cd777`.

Both SQL UATs require `collect.roster_provenance_qa=isolated_clone`, registry146,
cron launches off and pg_net batch0, and roll back all writes. The Ruby harness
requires `COLLECT_ROSTER_PROVENANCE_QA=isolated_clone`, frozen
`COLLECT_ROSTER_RESOURCE_MIGRATION_SHA`, and a new absolute
`COLLECT_ROSTER_CHECKPOINT` path. It verifies the exact project/port/container,
captures baseline/control hashes and owned XIDs, observes real two-session lock
waits, and refuses to commit cleanup unless all table/control fingerprints match.
Sequence counters are explicitly not restored.

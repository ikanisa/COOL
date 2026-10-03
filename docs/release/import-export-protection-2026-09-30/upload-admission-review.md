# Roster upload admission and bounded reading

## Finding and correction

The previous `AdminRosterUpload.file` called `PlatformFile.readAsBytes()` before validating the extension, extraction consent or byte limit. A selected source could therefore be allocated in full before rejection. `length()` also cannot serve as an admission check: the locked platform interface permits that fallback to read the source.

The correction checks the allowed extension, explicit PDF/image consent and already available metadata before byte I/O. It uses `readAsByteStream`, checks the cumulative cap before retaining each chunk, copies accepted chunks, and rejects a known length which changes during reading. A thrown size/length error cancels the stream; a stream error closes it. Unknown lengths remain supported within the same actual-byte cap.

Only `AdminRosterUpload` and the explicit `dart:typed_data` import changed. The complete gateway, draft, session, checkpoint and canonical expiry suffix is byte-preserved. The allowed MIME declarations, original byte digest/base64, filename sanitation, strict UTF-8, XLSX derivation and existing consent version are retained.

## Required controls and observed evidence

| Control | Why it is needed | Current evidence |
| --- | --- | --- |
| Metadata admission | Prevent full reads of a known oversized, empty, unsupported or unconsented source. | All eight allowed extensions, unsupported/dotfile/double-extension names, negative/zero known lengths, five AI types without consent; zero whole read, stream read and asynchronous length calls. |
| Actual byte cap | Metadata can be unknown or inaccurate. | Exact 512000-byte text and 5242880-byte binary boundaries, multi-chunk/single-chunk overrun and changed known lengths. Rejected streams stop before a later chunk. |
| Byte integrity | Reused platform buffers must not change retained source or provenance. | Eight MIME/type paths preserve original base64 and SHA; a deliberately reused/mutated buffer preserves the bytes as read. |
| Parsing after admission | A rejected resource must not reach source preparation or workbook decoding. | Invalid oversized XLSX and CSV sources are rejected before upload creation; draft preparation has no gateway call. Existing strict UTF-8 and workbook parser/preflight cases pass. |
| Error minimization | Native exceptions and paths may contain private file context. | Stream-error draft case presents the existing fixed safe message; private markers, payload and preparation/review/commit calls are absent. |
| Formula protection | Whitespace and control prefixes must not hide a spreadsheet formula marker in reviewed names. | 48 cases cover both name fields, four formula markers and six prefix variants; zero review dispatch. A legitimate `+250` phone/name control remains reviewable. This is input protection, not CSV output escaping. |

## Immutable acceptance

- `upload-admission-prior-attempt1` retains the initial fixture generic-inference compilation failure.
- `upload-admission-prior-attempt2` retains **49 passing controls and 43 reproduced failures**, clean analysis and unchanged copied inputs/dependency sources. These failures demonstrate the old whole-read/admission behavior.
- `upload-admission-current-attempt3` retains the missing `BytesBuilder` import failure; it is not accepted.
- `upload-admission-current-attempt4` passed **209 tests**, with one optional historical SQL receipt test skipped, and clean analysis. Its **93 upload/formula cases all passed**. All 824 copied inputs and locked SDK/FilePicker dependency sources remained unchanged. The live upload file matches this accepted export.

`upload-admission-acceptance.json` binds the exact current/prior validation hashes, current runtime hash, dependency manifest, preserved source scope and original checkout drift. Current co-resident Gateway/router/repository changes are listed separately; this packet is not an application-wide source freeze.

## Limits

The instrumented files implement the actual locked `PlatformFile` interface and exercise real Dart stream cancellation. They do not establish a physical picker outcome or the maximum allocation inside a plugin before a chunk is emitted. The application caps retained source bytes; it cannot undo allocation performed by a selected-file provider. The recorded native/web plugin sources and versions are included in the dependency manifest.

The packet executes no SQL, hosted/provider operation or native build. Actual Edge extraction, budget races, persisted audit and physical/browser delivery require their separate evidence. No active normal Admin CSV export was found in the earlier reviewed scope; source `export` statements do not provide that capability. New co-resident surfaces require the final current inventory before making an application-wide conclusion. Full L12 remains subject to the parent register.

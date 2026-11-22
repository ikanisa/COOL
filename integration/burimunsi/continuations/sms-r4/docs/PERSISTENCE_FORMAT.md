# Persisted format v1

`SnapshotCodec.kt` and `JournalFormat.kt` are the normative executable definitions. All numeric primitives are signed big-endian; a boolean is exactly byte 0 or 1. An optional numeric field has a boolean presence tag followed by its fixed-width value when present. A text field has a signed 32-bit UTF-16 code-unit count and exact big-endian code units; -1 means null. Zero means empty. No normalization or Unicode replacement occurs.

## Snapshot

`SMSS` (4 bytes), version 1 (4), payload byte length (4), exact payload, SHA-256 of all preceding frame bytes (32). Maximum total 8 MiB. The decoder requires the exact length and consumes the entire payload. Unsupported versions are rejected before interpreting the payload.

The payload contains the frozen upload batch and originals (scope, binding, capture/source identities, input mode/format, original parts in observation order, classification and redundant derived hashes), then revision, phase, diagnostic reason, attempt counter, first attempt time, last observed time, not-before time, optional active attempt, uncertainty flag, receipt list and conflicting receipt list. Enum names are strings, not ordinals.

Input parts preserve sequence/total/reference/reference width, sender/body, service-centre timestamp, subscription, coding scheme, application port, validated-envelope flag and exact PDU hexadecimal spelling. Multipart assembly and all evidence/body/batch hashes are recomputed on decode. Stored assembly completeness, assembly reason and hashes must match recomputation. Classification policy version is preserved; current classification eligibility is rechecked by the machine/gate at dispatch, not silently rewritten on decode.

## Journal

Header: `SMSJ` (4 bytes), version 1 (4), SHA-256-compatible framed scope digest (32). Scope framing is the existing R2 `EvidenceHash.framed(scope.fields())` algorithm. Header length is 40 bytes.

Each record is: length (4), previous tail digest (32), full snapshot frame, SHA-256(previous digest + snapshot frame) (32). Length excludes its own four bytes. The first previous digest is SHA-256(header); later previous digests equal the preceding record checksum. Atomic append compares SHA-256 of the complete prior journal, not just the last snapshot revision.

Replay rejects incorrect framing/digests/scopes, stale or skipped revisions, illegal phase history, changing immutable batches/classifications, attempt resets, backward observation times, receipt removal/replacement and duplicate original ownership. M-Money additionally rejects the same scope/source/body in another original/batch. Terminal snapshots remain indexed.

There is deliberately no recovery rule that skips or truncates a record. A partial tail blocks the complete journal even though earlier bytes may be intact. Recovery/export/replacement needs a separately authorized evidence-preserving workflow.

## Integrity and privacy limitations

Checksums and the chain are not a MAC, digital signature or encryption. An attacker able to rewrite all bytes can recompute checksums. An earlier complete valid prefix also passes without an external trusted high-water mark. These limits are retained as external production requirements.

The binary representation can contain full SMS PII. `HostFileJournal` writes plaintext solely for synthetic host verification; never use it for real SMS data. This format does not automatically migrate or replace any existing Android file/database format. R2 had no persisted format to convert.

## Platform reference

Host implementation uses `FileChannel.tryLock`, `force(true)`, exclusive new-file creation and no-follow path checks. Review the Java 21 specifications for their platform boundaries:

- https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/nio/channels/FileChannel.html
- https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/nio/file/Files.html

The host process tests do not establish storage survival after physical power loss, handset reboot, OEM behavior or key invalidation. Local checks neither authenticate carrier origin nor independently certify security.

# Gateway operator journal recovery — staged contract

The existing internal Gateway app now opens Journal recovery even when ordinary
initialization fails. A separate `collect/gateway.recovery.v1` MethodChannel owns
only status, export, restore and cancellation. It does not initialize a signing
key, provision enrollment, clear pause, activate a target, call the network or
invoke SMS. The actual `GatewayActivity` forwards file-picker results and closes
the maintenance controller alongside the original sender Bridge.

Export requires an existing encrypted, established journal with a durable pause.
The read-only pause verifier reads the committed `.bak` when present without an
AtomicFile reader, deletion, rename, migration or repair. It reads the existing
nonexportable AES alias and refuses unavailable keys, unpaused/missing/corrupt
control and symlinks. The same check runs once after picker return while core
export owns CycleGate and PROCESS_LOCK. Core snapshots retain exact `.bin`,
`.bak` and `.new` bytes. Dispatch is never automatically resumed.

The Android Storage Access Framework chooses one `.collect-gateway` file using
`application/octet-stream`. Its unpublished framed format contains a fixed
version magic; signed-long ciphertext file count; exact 64-character manifest
SHA256; bounded UTF8 entry names (<=200 bytes), signed-long sizes, exact bytes
and per-entry SHA256; and an exact terminal count/hash with EOF. Only the core
manifest, seal and flat named objects are representable. File-only frames carry
no symlink, permission, activation or key metadata. Unknown paths, traversal,
duplicates, extra/trailing bytes, size/digest/count mismatch and incomplete
frames refuse. Copying uses one 4KiB buffer, directory inventory pages <=8 names,
and no lifetime in-memory entry catalogue. No lifetime archive count eviction is
introduced. Manifest records remain bounded by the core reader to 1024 bytes;
individual ciphertext parts remain bounded to 512KiB+29. Total disk/time scales
with retained evidence. Prior ZIP implementations are retained, superseded;
ZipOutputStream's per-entry catalogue was unsuitable for the bounded-memory goal.

Export success requires provider output close plus an exact streaming SHA256
readback. This establishes current returned bytes, not physical power-loss or
provider durability. An unreadable/changed output remains an unknown result.

Restore first retains raw provider bytes in private quarantine, then interprets
frames into another private directory. The separately supplied trusted manifest
fingerprint reaches the unchanged core restore API. That API validates the seal,
complete object hashes and semantic closure into a fresh inactive original/view
pair. Wrong keys, changed evidence and unknown objects fail closed. An unavailable
original Android storage alias preserves opaque ciphertext with
`key_validated=false`. Flutter states that explicitly; a validated result also
remains inactive and requires re-enrollment. No original private key extraction,
replacement-key generation, new-device decryption, active-installation merge,
backend acknowledgement, receipt/delivery manufacture or blind replay exists.

Each admitted operation has an immutable ticket, operation/hash/result identity
and its own cancellation flag. Picker delivery transitions synchronously to
transfer before worker enqueue. Cancel after picker delivery keeps the original
reservation through terminal; a new operation cannot reset its cancellation or
change its destination/hash. Late foreign picker callbacks and worker settlement
cannot affect another operation. Picker cancel and Flutter page close cancel
maintenance; every partial snapshot, raw import, failed validation and inactive
original remains retained for investigation. No governed deletion UI is added.

The closed DTO carries only operation/state/phase, file counts, manifest fingerprint,
key-validation/inactive/re-enrollment flags and a redacted reason code. The UI
uses existing Collect shared theme, cards, headings and controls under the
selected Revolut skill. Narrow 320px/2x-text, keyboard focus entry, duplicate
submission, initialization failure, cancellation/close and opaque/validated
results have scoped local proof. Full TalkBack, physical picker/provider behavior,
rotation/process-kill recovery, power-loss/fsync, API26 devices, Gradle/R8/signing,
quarantine custody/disk budget/cleanup and measured RPO/RTO remain unverified.

# Receiver source closure and extraction — v0.4.0

## Original-source boundary

`upstream/collect/` contains only the 17 exact files listed in `native/burimunsi/integration/receiver-sources.json`. They were retrieved at commit `497de00bb16c86c797ebaad0f938dfd5efb42541`; their Git blob hashes were verified before use. They are not a reconstruction, not the complete repository and not evidence that the actual working tree or deployed application has those bytes. They are outside all Gradle source sets.

The original sixteen files used `MemberSmsUploadPolicy` but did not include its definition. `MemberSmsJobs.kt` supplies that definition along with unrelated member scheduling/session/upload code. The extractor verifies the entire original and extracts only exact `park`, `retry` and `permanentSourceError` fragments into a small object. It refuses changed fragments. It also checks that no member scheduler, uploader, session store or access-token implementation appears in any generated file. A baseline source-dependency regression is in `evidence/v0.4.0/receiver-dependency-regression.json`.

## Generated source

Seventeen Kotlin files are emitted: the original sixteen, with the documented three receiver/privacy/HTTP adaptations, and `MemberSmsUploadPolicy.kt`. `SmsQueueStore.kt`, acknowledgement, encryption, source identity, multipart logic and upload-hold policy are unchanged. The generated media-type check compares the exact media type after stripping parameters; redirects remain disabled as in the original HTTP client. No missing runtime capability is replaced by a new ledger, credential or demo binding.

## Build-input handling

Default input root: `upstream/collect/`. Explicit `--collect-root`/Gradle `collectRoot` overrides it for the whole extraction. Missing, changed or linked input files fail without borrowing from the bundle. Gradle declares source inputs and runs the check on each receiving build; the generated directory is attached only to the `internal_receiver` flavor.

## Output and interrupted-generation handling

Use a dedicated directory whose path includes `build`, outside the original receiver-source subtree. Sources are fully validated before output preparation. A nonempty prior output must contain only files accounted for by its provenance, with matching output hashes. Unexpected or altered entries are preserved and the command fails; do not erase them without inspecting their origin.

A lock excludes another cooperating extractor. New files are fsynced in a sibling staging directory. Promotion moves the old generation to a sibling backup and installs the staged generation. An ordinary promotion error attempts to restore the old generation. No code uses a partially written file as the completed new generation.

This is **not a filesystem-wide/crash-atomic transaction**. A process kill can leave a lock, staging directory, backup, or absent output. Stop builds/writers, inspect those siblings and their provenance, retain needed evidence, and regenerate into a fresh build directory. Do not remove a live process's lock. The script assumes an exclusively controlled source/build tree; it does not defend against an adversary concurrently rewriting paths or a forged manifest.

## Executed tests and limits

27 extractor tests exercise exact pin validation, reproducibility, unchanged sources, absent helper regression, forbidden member code, altered inputs/outputs, no per-file fallback, symlinks, foreign files, lock contention and injected write/promotion errors. Eight bundle/install/build-source tests cover default input selection and exact-baseline updates. Thirty-four JVM tests compile and execute seven real pure policy classes with no Android API stubs.

The helper methods are exact extracted source and their presence/absence is tested. The entire Android queue, JSON implementation, Keystore, telephony integration, receiver lifecycle, OEM behavior, disk retention and actual APK/DEX boundaries have **not** been compiled or executed here. Full native and real carrier testing remain required.

# Local AAB archive readback

This is a private utility for root to run after its actual native compilation and unsigned production AAB build. No SDK executable, APP test, native build, actual AAB readback or provider command was executed during preparation. Pinned Flutter source was read to identify its notice encoding. The focused proofs use tiny synthetic archives only.

Existing tooling was checked first. The IPA inspector extracts files and invokes Apple signing tools, the Flutter publisher ZIP helper addresses four exact SDK timestamp members, and the Gradle SBOM exporter describes selected compile/runtime graphs and external AAR/JAR bytes. None provides this complete AAB archive readback. The helper uses standard Python zipfile directly and performs no extraction or external invocation; it is not a new production acceptance system.

## Root use

Use the pinned Python runtime and an outer command deadline. Supply the expected AAB SHA-256 from the completed build record, an independently held SHA-256 for the input bindings JSON, and a fresh output filename under an existing canonical directory. The helper's default internal deadline is 120 seconds; --timeout-seconds accepts a finite positive value up to 600 seconds.

```sh
python3 -I -B aab_readback.py \
  --aab /absolute/path/app-production-release.aab \
  --aab-sha256 ACTUAL_AAB_SHA256 \
  --bindings /absolute/path/root-bindings.json \
  --bindings-sha256 HELD_BINDINGS_SHA256 \
  --output /absolute/path/fresh-aab-readback.json
```

The JSON bindings have schema_version=1, a nonempty inputs list, and an optional fonts list. Each record requires a unique label, canonical absolute path and lowercase SHA-256. Input records additionally carry a role label. Root should supply its actual source/export, SDK snapshot, lock, resolved package, graph and build records; the helper hashes every supplied record before and after archive reading. It reports the roles supplied, and does not invent mandatory role counts or certify the underlying receipts. Role labels and captured records confer no approval or authority. See bindings.example.json for placeholders to replace; it is not a valid acceptance record.

Fonts records also carry family and an asset path relative to Flutter's asset bundle, such as assets/typefaces/Inter-Variable.ttf. The helper compares each supplied font source hash to its actual AAB payload and reports missing or different bytes plainly. A missing font comparison or missing compiled notice remains visible in the receipt; its status=pass describes completed archive integrity and byte binding, not product completeness. Root must evaluate those content facts. The current source declares Inter-Variable.ttf plus AeonikPro-Regular.ttf and AeonikPro-Medium.ttf. Rights and approved typography remain unresolved outside this utility.

## Evidence produced

The input AAB must be a canonical, exclusive regular file. A single open file descriptor supplies the complete archive hash before and after inspection, and both its identity and the named leaf must stay unchanged. Supplied evidence and font input files receive before/after hash and identity checks. No input is modified.

Every ZIP member is read to EOF and receives a SHA-256, byte count, CRC32, compression and mode record. Duplicate normalized file/directory names, unsafe or noncanonical paths, NUL/control names, unsupported encodings, symlinks and special members, file/directory collisions, CRC corruption and size overruns are refused. Standard ZIP local header and overlap checks remain provided by zipfile.

The local evaluation profile requires the exact existing Gradle marker at base/assets/collect-local-unsigned-qa.json, including its newline. Its payload is local_unsigned_native_qa with store_acceptance, provider_configuration and signing all false. The marker reports the build's declared profile; it does not cryptographically establish unsignedness. Signature metadata names are inventoried, while signature_verified and unsignedness_verified remain false.

Actual native library and Flutter libapp.so/libflutter.so member hashes are listed. Font payloads and the packaged FontManifest.json are reported. Native Flutter 3.44.4 creates NOTICES.Z through ZLibEncoder(gzip: true); the helper boundedly decodes the gzip, validates its UTF-8 and hashes the decoded notices without exposing their text. Plain NOTICES is also understood. This does not prove complete licensing notices or font rights.

## Supported bounds and limits

This utility supports a single-disk ordinary ZIP, with no ZIP64 or trailing archive bytes. It bounds the AAB and each member at 1 GiB, the central directory at 32 MiB before parser allocation, total ZIP expansion at 4 GiB, and members at 50,000. Input records are at most 1 GiB each; the binding JSON is at most 1 MiB and has at most 128 input plus 128 font records. Retained marker, font manifest and notice payloads have separate 16 KiB, 1 MiB and 32 MiB limits. Decoded notices are capped at 64 MiB. These are this reader's resource limits, not additional shipping criteria; an unsupported artifact needs a reviewed reader adjustment rather than a false production failure claim.

The output is an exclusively created mode-0600 JSON receipt. It preserves a failed readback status when decoding or binding fails; an existing output is refused. The root owns the actual run and output sealing.

This is an actual archive byte inventory, not a complete package-level CycloneDX SBOM. It does not map opaque Dart AOT or native objects to all source/dependency components. The existing Gradle observer and gradle_observed_sbom.py can separately bind selected external dependency inputs/edges to root's build evidence. Source/SDK provenance, complete artifact SBOM, advisory triage, licensing/font permission, signing, device/store acceptance and ARC-09 closure are all separate and are not established here. No all-flavor or fixed graph-count requirement is introduced.

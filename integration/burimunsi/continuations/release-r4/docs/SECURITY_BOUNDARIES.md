# Security boundaries and limits — r4

## What is checked

The guard recomputes in-scope source bytes and executable-mode classifications; validates manifest/result/log/dependency/artifact hashes, strict structures, time ordering and required qualifications; and verifies exact source-package membership. Application build/promotion additionally requires scoped Ed25519 signatures under a separately pinned external policy. Negative tests show rejection of the specific fault cases delivered. This is engineering verification, not a security certification or proof that all possible inputs are safe.

## What remains external

Signatures authenticate possession of configured keys and bind the signed statements. They do not establish the real-world identity or independence of those key holders, prove a producer told the truth, establish database commit behavior, operate a carrier SIM, install Android software, verify APK publisher signatures, establish hosted routes, satisfy legal requirements or authorize release. Synthetic positive fixtures are temporary tests, not genuine qualification records.

The trust administrator must onboard identities and maintain protected policies/pins. CI must protect the executable guard, runtime, clock, workspace and output parents. This code does not create signing services, protected GitHub environments, hardware key custody, online revocation, transparency logging or trusted timestamping. No SLSA conformance or level is claimed. Full application production gates remain blocked for missing real qualification/authorization.

The internal consistency diagnostic is not a release API. Use public validation plus the combined product CLI. Source-only packages and their offline verifier remain non-authenticating. Even an application gate that verifies all configured signatures returns `production_authorized=false`: only the separately authorized release process may act.

## Filesystem and resource assumptions

Use an unprivileged protected executor with immutable inputs and no concurrent writers. The code rejects symbolic/hard links and special files, checks metadata around reads and repeats relevant validation, but is not an OS sandbox or formal defense against every filesystem race. There is no atomic transaction binding a local verdict to a later external deployment.

The fixed excluded directory names are `.git`, `.gradle`, `.kotlin`, `__pycache__`, `node_modules`, `build`, `.release-evidence` at any depth. All other regular source files, including ordinary historical logs, are inventoried. Exclusions cannot be supplied by evidence. Excluded contents are not claimed scanned or certified; referenced artifact/dependency bytes are checked separately.

Limits: 64 MiB per file/member, 8 MiB per JSON document, 512 MiB aggregate source/expanded nested-archive budget, 20,000 entries, archive nesting depth four and maximum compression ratio 2,000. Evidence references are individually bounded; hostile-input process isolation is still necessary. Provenance has at most 256 signatures, per-OpenSSL timeout of 10 seconds and overall crypto budget of 30 seconds. Legitimate oversized or slow inputs may be blocked. A resource-limit change requires a reviewed source change and fresh tests.

OpenSSL is resolved only from fixed system directories, with a reduced subprocess environment and no shell. The OS, binary and its dynamic libraries must still be protected and qualified. `runtime_inventory.py` records executable hashes/versions, not a full transitive system dependency closure or authenticity proof.

## Credential and archive inspection

The scanner is heuristic, with possible false positives and false negatives. It rejects common credential filenames/markers, credential-like assignments, authenticated connection URIs, token-shaped/JWT-shaped content and recursively inspected ZIP-family payloads. It checks UTF-8 and UTF-16/32 views and ZIP comments but does not decode arbitrary obfuscation or all encodings. No matched values are printed in errors. Test templates are not exempted. The 33 full-app findings remain unresolved; a heuristic match does not prove an active credential.

Supported archives are ZIP/JAR/APK/AAB and ZIP-based Office containers. Opaque unsupported compressed formats are rejected instead of labeled scanned. Checks cover traversal/absolute/Windows paths, reserved names, controls, normalization, duplicate/case-colliding paths, file/directory collisions, encryption, links, special files and privileged modes. This is neither exhaustive malware detection nor Android install/signature qualification.

## Time, retention and reproducibility

Source/evidence freshness is 24 hours with no future timestamps. Signature time is the authenticated producer assertion, not an independent timestamp authority. Trust policy validity is at most 30 days and keys must still be valid at verification. Revocation is evaluated only against the currently supplied pinned policy; no online refresh is performed. A new pin requires new statements.

Same source bytes, modes and evidence bytes yield the same ZIP with the same Python/zlib implementation. A fresh test run produces new evidence and a different ZIP. Cross-runtime compression equivalence has not been qualified. Historical archives may be retained indefinitely for byte audit, but cannot satisfy current qualification after expiry. New evidence/output paths are exclusive and never overwritten.

`verify-package` checks an independently supplied expected hash, safety, closure and freshness before reporting a source-only result; it never executes contained source. It uses a temporary filesystem snapshot, not a sandbox. `audit-package` checks integrity without renewing old qualifications.

## Reference and implementation scope

OpenSSL's official command reference specifies Ed25519 raw-input verification: https://docs.openssl.org/3.0/man1/openssl-pkeyutl/ . This delivery uses OpenSSL rather than implementing cryptography in Python. No independent review or certification of this new protocol and integration is claimed. External security review, protected deployment and real acceptance remain explicitly open in the action register.

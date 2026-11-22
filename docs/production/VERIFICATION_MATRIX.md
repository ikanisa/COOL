# Required behavioral verification matrix

| Boundary | Required cases | Delivered verification |
|---|---|---|
| Signed OTP hook | Correct signature, body tamper, expired/future timestamp, key rotation, static header rejection, quota/replay states, uncertain provider response | Actual helper and handler logic executed with isolated dependencies; live Auth/provider/SQL not exercised |
| Receipt acceptance | Missing auth/version, wrong body/owner/envelope, durable commit then parse failure, replay, invalid input bounds | Actual helper and handler logic executed with isolated dependencies; SQL durability/locking not executed |
| Play Integrity | Licensed app, package/hash, minimum version, certificate allowlist, age, correct OAuth grant type, fixed token URI | Helper and real handler logic executed with synthetic verdicts and temporary test keys; Google verdict authenticity not exercised |
| Native ACK | Correct owner/body, account change, body mutation, mixed queue, duplicate IDs, new concurrent envelope | Pure Kotlin policy executed on JVM; Android bridge and account lifecycle not executed |
| Receipt encryption | Unicode roundtrip, random nonce, wrong key, tamper, malformed ciphertext, locked key | Real JVM AES-GCM executed; Android Keystore lifecycle not executed |
| Human reconciliation | AAL2 permission, different users, stale approval, evidence match, duplicates, reversal, service-only finalization | Staged SQL and source checks only; full backend and reviewer UI required |
| Mobile receipt bridge | Typed ACK, malformed/null/error response, owner/hash fields | Dart cases authored; no Dart/Flutter execution in delivery environment |
| Release evidence | Missing/duplicate gates, source mismatch, stale evidence, self-approval, bad hashes, path traversal, symlinks | Python validator tests executed; no release approved |
| Recovery and rollout | Cold start, process death, boot, delayed receipt, queue overflow, revoked consent, restore | Not executed; mandatory external release evidence |

The complete original and new test suites must be run on the canonical full checkout. This matrix must not be interpreted as a list of completed application journeys.

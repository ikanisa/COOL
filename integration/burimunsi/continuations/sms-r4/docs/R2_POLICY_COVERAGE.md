# Policy-to-evidence traceability

The machine-readable per-case evidence is `evidence/policies_r2.json`. Case names below identify executable tests, not manual checklists.

| Requirement | Implementation | Test evidence |
|---|---|---|
| Supported-message classification | Separate adapters and immutable `Classification` | `fixture/*`, `classification/*`; exact inherited originals checked by Python |
| Original evidence retention and encoding | `Evidence.kt`, `Identity.kt` | `evidence/*`, `multipart/*`, every `fault/*` invariant |
| Multipart order, metadata and ambiguity | `MultipartPolicy.inspect` | Valid shuffled ordering plus missing/duplicate/mixed/unsupported/Unicode mutations in `multipart/*` |
| Duplicate and collision handling | `DuplicatePolicy`, `BatchAdmissionPolicy` | `duplicates/*`, `batch/*`, operation-rebinding tests |
| Queue transitions and immutable operation | `QueueMachine`, `UploadBatch` | `lifecycle/*`, `model/2000-deterministic-events-retain-evidence-and-budget` |
| Strict application-specific acknowledgements | `AckPolicy` | `ack/*`; typed/missing/foreign/duplicate/batch coverage and conflicting-result tests |
| Retry budget and clock boundaries | `RetryPolicy`, `QueueMachine` | `retry/*`, lifecycle timeout/restart/clock cases |
| Binding, owner and SIM state | `SimPolicy`, scope/session/attempt checks | `sim/*`, lifecycle authority changes, dispatch recheck |
| Failed and indeterminate persistence | `CommitDriver`, `QueueStorePort` | 48 `fault/*` cases: six faults × four commit boundaries × two contracts; storage no-recreation tests |
| Concurrent reservation safety | CAS revision boundary and `DispatchPolicy` | `storage/concurrent-reservation-emits-once`: twenty threads, one committed reservation effect |
| Full M-Money batch | Immutable batch with whole-set validation | `lifecycle/mmoney-full-batch-mixed-outcomes-atomic`: twenty originals, mixed outcomes, replay |
| Source delivery and installation | `install_overlay.py`, provenance | Fourteen Python tests with temporary checkouts; dry-run, repeat, collision, drift, symlink and traversal cases |

A test can contain multiple assertions; assertion counts are not presented as independent test cases. The 2,000 seeded model transitions form one bounded invariant test, not exhaustive formal verification. The new fault store simulates durable outcomes in memory. The separately rerun inherited Buri reliability suite also exercises real host AES-GCM, file operations and terminated child JVMs; it still does not prove Android hardware power-loss behavior.

# Android complete native recovery — root handoff

Status: staged, source-bound local acceptance. Root is the sole canonical promoter.

- 40 fresh current method observations passed: Recovery 11, History 4, Lookup
  Fairness 7, Archive Storage 12, Dispatch Backend Integration 6.
- All 25 current Kotlin native files compiled against Android36 on the verified
  pinned ARM64 JDK21. Nine owned commands have real terminal exit0 receipts;
  every command child is reaped and the final process readback is empty.
- Final source inventory: 45 files. Eleven proposed canonical changes have exact
  old/new SHA256 and retained/new mode decisions in promotion-manifest.json.
- The post-command consumer-only Build.kt shim insertion is byte-identical to
  the actually compiled private shim. Its exact AST delta, all six shim bytes,
  and unchanged native/test inputs are recorded in final-source-association.json.
- No composed preceding method passes are needed for this current acceptance.
  Setup-only failures 1–3 and real terminal failed native attempts 4–5 are
  preserved. Earlier successful 36/39-case runs remain superseded, retained
  evidence, not additional fresh cases. No preceding expensive late/attempt/
  heartbeat cohorts were repeated or counted.

The new store maintenance APIs stream a complete raw ciphertext inventory and
archive, retain AtomicFile base/backup/new bytes, and restore into a fresh inactive
original/view pair. Strict full hashes and current source-bound readers validate
pending hot/late/cold publication, UUID reservations, receipts, trie closure,
legacy references and durable cursor state. Dedicated tests prove unrecognized
future work, malformed terminal data, original substitution, missing nodes/files,
wrong keys, damaged/extra/symlink files, source change, busy/cancelled operations
and incomplete restore remain denied. Restored historical enrollment cannot
configure, provision, resume, reserve an invocation or reach SignedBackend
transport. V1 observational attempt and callback originals remain hot. Exact V2
late receipts remain scoped to their own transport and never clear stop.

Review RECOVERY_CONTRACT.md for actual API ordering, closure and limits. Current
native APIs are maintenance entrypoints; an operator file-picker/Bridge recovery
workflow is not included. Production Keystore decryption is same-key-realm only;
no signing/storage private key export/import, portable/new-device decryption,
activation, credential transfer, acknowledgement/delivery manufacture or blind
replay exists. An unavailable AES alias preserves opaque evidence with
key_validated=false; wrong key/corrupt evidence refuses validation.

Remaining external/native recovery gates: a real-device same-key rehearsal,
physical power-loss/fsync/AtomicFile behavior, API26/device compatibility,
Gradle/R8/package/signing acceptance, approved operational snapshot window and
disk/callback-delay budget, operator invocation and archive custody, new-device
re-enrollment/revocation/read-only backend reconciliation, any approved portable
key architecture, and measured full configuration/Auth/sender recovery RPO/RTO.
Scheduler extras/SIM/permissions/preferences are outside this journal snapshot.
No hosted, provider, device, store or production-release readiness is claimed.

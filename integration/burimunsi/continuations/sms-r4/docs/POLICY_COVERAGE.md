# R3 coverage map

| Requirement | Executable evidence |
|---|---|
| Both application contracts preserved | R2 policy suite plus `codec/BURI_COLLECT_V2/*`, `codec/MMONEY_LEDGER_V1/*`, inherited app suites. |
| Complete state serialization | Every phase represented, including rejected and conflicting receipts; deterministic byte round-trip and derived hash comparisons. |
| Original evidence preservation | Multipart observation order/PDU case, provider no-PDU boundary, null/empty/raw-code-unit metadata, frozen batch preservation across history. |
| Unsupported/malformed storage rejection | All snapshot truncation offsets and single-byte corruptions; unsupported versions; resealed enum/hash/string mutations; 1,000 seeded arbitrary byte arrays. |
| Atomic duplicate ownership | Replayed original index; M-Money source/body duplication across captures and within batches; retained acknowledgement tombstones. |
| Safe queue persistence | CAS/time/attempt/receipt rollback checks; immutable classifications; missing/unavailable/corrupt storage blocks. |
| Fault injection | Four state-changing stages × seven memory-port faults; all four host append interruption hooks. No send effect on failed/unknown writes. |
| Torn log behavior | Every partial tail offset tested: no prefix fallback, truncation or write repair. |
| Recovery across process boundaries | Separate JVM capture/reserve/inspect/restore/stage/finalize; two-process reservation race; `Runtime.halt` during partial append and after force-before-return. |
| Last-moment dispatch constraints | Reservation lease edge, changed session/permission/SIM/admission and acknowledged-state rejection. |
| Safe additive upgrade | Temporary native checkouts for both apps; R2 source byte preservation; new shared files only; plaintext host adapter excluded. |

Counts and named cases are in `evidence/persistence_r3.json`. Loop iterations, assertion counts and child-process counts are supplementary measures, not additional test cases. The new suite does not claim exhaustive exploration of every byte sequence or all possible JVM scheduling histories.

# R3 integration contract and remaining acceptance

## Current dependency chain

Application classifier → `QueueMachine` → `CommitDriver` → `JournalQueueStore` → `AppendJournalPort`.

The port beneath `JournalQueueStore` is the native integration boundary. The delivered `HostFileJournal` is a functioning POSIX/JVM reference for synthetic tests, not a mobile adapter.

The existing R2 classifiers and machine are unchanged. Do not replace M-Money's contract with Collect v2 or infer financial posting from either ingestion acknowledgement.

## Native transaction obligations

1. Preserve an inbound message's original bytes/metadata before classification or queue admission. Keep unsupported, ambiguous and conflicting incoming observations in the native evidence/quarantine store; do not drop them because `capture` refuses a batch. Intake checkpoints advance only after the evidence and admission decision are durable.
2. Provision a new installation store explicitly. Opening existing storage must never create an empty store after deletion, key invalidation, unreadable data, unknown version or failed decryption.
3. Implement `AppendJournalPort.read` with bounded complete reads and immutable returned bytes. Implement `append` by locking the complete storage unit, checking the SHA-256 of ALL current bytes against `expectedContentHash`, and appending exactly one record under the same lock. Never split state and uniqueness indexes into independent commits.
4. Return `COMMITTED` only after the qualified native durability barrier. Return `UNKNOWN` when a write may have happened. A caller receiving `UNKNOWN` must not send a retained upload effect. Do not truncate partial records or recreate corruption as an error-recovery shortcut.
5. Protect real evidence with authenticated encryption, restricted storage and the established Keystore lifecycle policy. Raw snapshot/journal bytes include PII; do not log them, attach them to ordinary telemetry, or send them to Drive.
6. Bind the store to contract, owner, installation and generation. Include a trusted lifecycle/high-water strategy where anti-rollback is required. A complete old valid journal prefix is not detectable from the journal alone.
7. Call `ReservationGate.permitted` immediately before request submission while holding the application's lifecycle/binding fence. Re-read the committed reservation under that fence. An expired reservation must be recovered by a queue action, never reused merely because its payload still matches. The pure gate is neither a mutex nor duplicate-send suppression.
8. Keep the original request/operation identity across retries. Verify the response against the frozen attempt and current session. Persist a validated acknowledgement first; finalize it separately. Do not delete terminal originals or acknowledgement tombstones here.

## Crash/reopen behavior

| Observed durable state | Required behavior |
|---|---|
| READY | Reevaluate current authority/SIM/classifier before reserving a send. |
| IN_FLIGHT after process interruption | Do not reconstruct a send effect. Use `Restore`; retain outcome uncertainty and schedule only the original operation. |
| RETRY_WAIT | Preserve attempt count and not-before time; no early retry. |
| HELD | Retain evidence. Authorization holds require a strictly newer session; limits do not reset. |
| ACK_PENDING | Finalize the already validated receipts; do not resend or drop the pending acknowledgement. |
| ACKNOWLEDGED / REJECTED / CONFLICT | Retain originals, receipts and identity indexes. No ordinary redispatch. |
| Missing/unavailable/corrupt/foreign-scope/unknown-version journal | Block; preserve bytes. No empty replacement or prefix salvage. |

The machine's clock and session fencing still apply. An old attempt acknowledgement cannot bypass a changed session. Server idempotency remains essential when the result of a prior request is uncertain.

## Limits and operational behavior

Snapshot cap: 8 MiB including framing. Journal cap: 64 MiB; 10,000 records; 1,000 retained batch entries. Original batch and multipart bounds remain R2's 20 originals and 255 parts per input. These are engineering safeguards, not workload qualification. Exceeding a cap refuses further admission/append and retains existing evidence. There is no eviction or silent compaction.

The reference rebuilds indexes by replaying the complete bounded journal; throughput, large-volume behavior and mobile memory usage require qualification. Do not assume this reference is the final production database architecture.

## Remaining work in order

- Reconcile these three additive shared sources against the selected consolidated A03/A04 candidates; the provided installer intentionally refuses unknown pinned core baselines.
- Implement encrypted native storage, intake/quarantine/checkpoint atomicity, legacy-queue migration, trusted lifecycle/anti-rollback handling and worker/lifecycle-fence wiring.
- Compile Staff/receiver variants with the pinned Android toolchain; run serialization/JSON bridges, WorkManager, Room/file/Keystore, lock contention, permission, SIM, reboot/unlock and replacement instrumentation.
- Qualify hosted ingestion and real database idempotency/acknowledgements separately from financial reconciliation.
- Run consented physical-carrier scenarios. No synthetic pass closes the real-carrier gate.

No production enablement, secrets, remote database operations or actual Collect checkout modifications are part of this delivery.

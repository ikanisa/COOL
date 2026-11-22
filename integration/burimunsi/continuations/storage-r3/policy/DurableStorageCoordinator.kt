package rw.ikanisa.storagepolicy

/** Implementations serialize ALL writers and effects for this namespace, across instances
 * and processes, for the entire block. A production port also authenticates/encrypts bytes,
 * enforces durable compare-and-set, and refuses pending, unreadable or damaged records.
 * A missing record is NOT permission to initialize. No port may repair by deleting evidence. */
interface LifecycleJournalPort {
    fun <T> exclusive(block: () -> T): T
    fun read(): ByteArray?
    fun compareAndSet(expected: ByteArray?, replacement: ByteArray)
    /** Called only during explicit first provisioning, inside exclusive. Must check all
     * ledger/key/sidecar/retirement artifacts in the application's real storage scope. */
    fun verifyVirginScope(binding: Binding)
}

data class StoredLifecycle(val state: StorageState, val snapshotSha256: String)
sealed class LifecycleCommand {
    data class BeginWrite(val operationId: String, val digest: String): LifecycleCommand()
    data class ConfirmWrite(val operationId: String, val digest: String, val artifactId: String): LifecycleCommand()
    data class Failure(val fault: StorageFault): LifecycleCommand()
    object ConfirmHealthWrite: LifecycleCommand()
    data class BeginDeletion(val operationId: String, val explicit: Boolean): LifecycleCommand()
    /** The caller has already validated server authenticity, product/owner/generation and
     * operation identity. A string receipt alone is NOT a server authorization check. */
    data class AcceptDeletionReceipt(val operationId: String, val receiptId: String): LifecycleCommand()
    data class BeginReplacement(val operationId: String, val target: Binding, val explicit: Boolean,
        val archive: VerifiedEvidenceArchive? = null): LifecycleCommand()
}

enum class ArtifactObservation { PRESENT, ABSENT, UNREADABLE, UNSAFE }
interface CleanupArtifactPort {
    /** IDs are opaque manifest IDs, never directly trusted filesystem paths. Adapters must
     * enforce scope and non-following access and prevent reuse while cleanup is pending. */
    fun observe(binding: Binding, artifactId: String): ArtifactObservation
    fun remove(binding: Binding, artifactId: String)
}
data class ReplacementObservation(val operationId: String, val target: Binding, val artifactIds: Set<String>)
interface ReplacementArtifactPort {
    /** Re-observe an existing attempt before returning null. null means VERIFIED absence,
     * never an I/O failure, partial creation or unknown outcome. */
    fun observe(intent: ReplacementIntent): ReplacementObservation?
    /** Idempotently create/adopt ONLY this target and operation. Must never remove old
     * evidence, regenerate over partial artifacts, or authorize a financial operation. */
    fun createOrResume(intent: ReplacementIntent): ReplacementObservation
}

/** Storage workflow coordinator, not a financial command executor. Has no generic reset,
 * clear-error, arbitrary state-save, delete-snapshot or fallback-to-empty operation. */
class DurableStorageCoordinator(private val journal: LifecycleJournalPort) {
    private fun need(ok: Boolean, code: String) { if (!ok) throw StoragePolicyFailure(code) }
    private fun stored(bytes: ByteArray) = StoredLifecycle(LifecycleSnapshotCodec.decode(bytes), LifecycleSnapshotCodec.sha256(bytes))
    private fun requireCurrent(expected: StoredLifecycle): Pair<ByteArray, StorageState> {
        val bytes = journal.read() ?: throw StoragePolicyFailure("lifecycle_missing")
        val actual = stored(bytes)
        need(actual == expected, "lifecycle_stale_checkpoint")
        return bytes to actual.state
    }
    private fun save(before: ByteArray?, next: StorageState): StoredLifecycle {
        val bytes = LifecycleSnapshotCodec.encode(next)
        if (before == null || !before.contentEquals(bytes)) journal.compareAndSet(before?.copyOf(), bytes.copyOf())
        val readback = journal.read() ?: throw StoragePolicyFailure("lifecycle_commit_unverified")
        need(readback.contentEquals(bytes), "lifecycle_commit_unverified")
        return stored(readback)
    }
    /** Explicit, evidence-free first provisioning only. Not a recovery or migration API. */
    fun provision(binding: Binding, explicit: Boolean): StoredLifecycle = journal.exclusive {
        need(explicit, "explicit_provisioning_required")
        need(journal.read() == null, "lifecycle_already_exists")
        journal.verifyVirginScope(binding)
        save(null, StorageState(binding))
    }
    fun load(expectedBinding: Binding): StoredLifecycle = journal.exclusive {
        val v = stored(journal.read() ?: throw StoragePolicyFailure("lifecycle_missing"))
        need(v.state.binding == expectedBinding, "lifecycle_binding_mismatch"); v
    }
    fun apply(expected: StoredLifecycle, command: LifecycleCommand): StoredLifecycle = journal.exclusive {
        val (before, s) = requireCurrent(expected)
        fun token(id: String) = EffectToken(s.binding, s.revision, id)
        val next = when (command) {
            is LifecycleCommand.BeginWrite -> {
                val w = WriteIntent(command.operationId, command.digest)
                if (s.phase == Phase.ACTIVE && s.lastWrite == w) s
                else StorageLifecyclePolicy.beginWrite(s, command.operationId, command.digest)
            }
            is LifecycleCommand.ConfirmWrite -> {
                val w = WriteIntent(command.operationId, command.digest)
                if (s.phase == Phase.ACTIVE && s.lastWrite == w && command.artifactId in s.evidence) s
                else StorageLifecyclePolicy.confirmWrite(s, token(command.operationId), command.digest, command.artifactId)
            }
            is LifecycleCommand.Failure -> StorageLifecyclePolicy.recordFailure(s, command.fault)
            LifecycleCommand.ConfirmHealthWrite -> StorageLifecyclePolicy.confirmHealthWrite(s, s.revision, s.binding)
            is LifecycleCommand.BeginDeletion -> StorageLifecyclePolicy.beginDeletion(s, command.operationId, command.explicit)
            is LifecycleCommand.AcceptDeletionReceipt -> {
                if (s.phase in setOf(Phase.CLEANUP_PENDING, Phase.TOMBSTONED) && s.deletion?.operationId == command.operationId) {
                    need(s.deletion!!.receiptId == command.receiptId, "deletion_receipt_conflict"); s
                } else StorageLifecyclePolicy.acceptDeletionReceipt(s, token(command.operationId), command.receiptId)
            }
            is LifecycleCommand.BeginReplacement -> {
                val intent = ReplacementIntent(command.operationId, command.target, command.archive?.proof)
                need(command.explicit, "explicit_replacement_required")
                if (s.phase == Phase.ACTIVE && s.lastReplacement == intent) s
                else StorageLifecyclePolicy.beginReplacement(s, command.operationId, command.target, true, command.archive?.proof)
            }
        }
        save(before, next)
    }
    /** One artifact per call. Physical removal followed by lost acknowledgement is recovered
     * by observing the SAME manifest entry as absent. Failure never advances the manifest. */
    fun cleanupOne(expected: StoredLifecycle, artifacts: CleanupArtifactPort): StoredLifecycle = journal.exclusive {
        val (before, s) = requireCurrent(expected)
        if (s.phase == Phase.TOMBSTONED) return@exclusive stored(before)
        val id = StorageLifecyclePolicy.nextCleanup(s)
        val token = EffectToken(s.binding, s.revision, s.deletion!!.operationId)
        if (id == null) return@exclusive save(before, StorageLifecyclePolicy.finishCleanup(s, token))
        when (artifacts.observe(s.binding, id)) {
            ArtifactObservation.PRESENT -> artifacts.remove(s.binding, id)
            ArtifactObservation.ABSENT -> Unit
            ArtifactObservation.UNREADABLE -> throw StoragePolicyFailure("cleanup_unreadable")
            ArtifactObservation.UNSAFE -> throw StoragePolicyFailure("cleanup_unsafe")
        }
        need(artifacts.observe(s.binding, id) == ArtifactObservation.ABSENT, "cleanup_absence_unverified")
        save(before, StorageLifecyclePolicy.confirmArtifactAbsent(s, token, id))
    }
    /** The exact replacement target/operation is durable before this method can execute.
     * Unknown/partial effects must be resolved by the adapter, never given a new identity. */
    fun resumeReplacement(expected: StoredLifecycle, artifacts: ReplacementArtifactPort): StoredLifecycle = journal.exclusive {
        val (before, s) = requireCurrent(expected)
        need(s.phase == Phase.REPLACEMENT_PENDING, "replacement_not_pending")
        val intent = s.replacement!!
        val result = artifacts.observe(intent) ?: artifacts.createOrResume(intent)
        need(result.operationId == intent.operationId, "replacement_operation_mismatch")
        val verified = artifacts.observe(intent)
        need(verified == result, "replacement_creation_unverified")
        save(before, StorageLifecyclePolicy.confirmReplacement(s,
            EffectToken(s.binding, s.revision, intent.operationId), result.target, result.artifactIds))
    }
}

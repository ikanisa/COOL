package rw.ikanisa.storagepolicy

/** Host-testable policy only. The caller must persist each returned state BEFORE executing
 * its next effect, serialize writers, and supply observations from verified storage I/O.
 * This reducer never opens, deletes, renames, decrypts or creates a file. */
class StoragePolicyFailure(val code: String) : IllegalStateException(code)
private fun requirePolicy(ok: Boolean, code: String) { if (!ok) throw StoragePolicyFailure(code) }
private fun bounded(value: String) = value.isNotBlank() && value.length <= 256 && value.none { it.isISOControl() }

enum class ArtifactShape { ABSENT, FILE, EMPTY, UNSAFE, UNREADABLE }
enum class OpenDecision { FRESH, READ_EXISTING, PENDING_WRITE, BACKUP_REQUIRES_RECOVERY, CORRUPT, UNSAFE, UNREADABLE }
data class RecordInventory(val base: ArtifactShape, val backup: ArtifactShape, val pending: ArtifactShape)
object RecordOpeningPolicy {
    fun decide(i: RecordInventory): OpenDecision = when {
        listOf(i.base, i.backup, i.pending).any { it == ArtifactShape.UNREADABLE } -> OpenDecision.UNREADABLE
        listOf(i.base, i.backup, i.pending).any { it == ArtifactShape.UNSAFE } -> OpenDecision.UNSAFE
        i.pending != ArtifactShape.ABSENT -> OpenDecision.PENDING_WRITE
        i.backup != ArtifactShape.ABSENT -> OpenDecision.BACKUP_REQUIRES_RECOVERY
        i.base == ArtifactShape.EMPTY -> OpenDecision.CORRUPT
        i.base == ArtifactShape.FILE -> OpenDecision.READ_EXISTING
        else -> OpenDecision.FRESH
    }
    fun mayCreateKey(i: RecordInventory, anySiblingEvidence: Boolean): Boolean =
        decide(i) == OpenDecision.FRESH && !anySiblingEvidence
}

enum class StorageFault { IO_UNAVAILABLE, NO_SPACE, PERMISSION_DENIED, KEY_UNAVAILABLE,
    KEY_PERMANENTLY_LOST, MALFORMED, AUTHENTICATION_FAILED, UNSUPPORTED_VERSION, UNKNOWN }
/** Classification is based on adapter-provided typed evidence, never exception message text.
 * An authentication failure is NOT proof that a key was permanently lost. */
object CorruptionPolicy {
    fun replacementEligible(fault: StorageFault?): Boolean = fault in setOf(
        StorageFault.KEY_PERMANENTLY_LOST, StorageFault.MALFORMED,
        StorageFault.AUTHENTICATION_FAILED, StorageFault.UNSUPPORTED_VERSION)
    fun maySilentlyRecreate(fault: StorageFault): Boolean = false
    fun mayDeleteAsRecovery(fault: StorageFault): Boolean = false
}

data class Binding(val product: String, val owner: String, val generation: String) {
    init { requirePolicy(listOf(product, owner, generation).all(::bounded), "invalid_binding") }
}
enum class Phase { ACTIVE, WRITE_PENDING, DELETE_REQUESTED, CLEANUP_PENDING, TOMBSTONED, REPLACEMENT_PENDING }
data class WriteIntent(val operationId: String, val digest: String)
data class DeleteIntent(val operationId: String, val artifacts: Set<String>, val receiptId: String? = null)
data class Tombstone(val binding: Binding, val operationId: String, val receiptId: String)
data class ArchiveProof(val binding: Binding, val artifactIds: Set<String>, val receiptId: String)
data class ReplacementIntent(val operationId: String, val target: Binding, val archive: ArchiveProof?)
data class EffectToken(val binding: Binding, val revision: Long, val operationId: String)

/** Tokens bind observations to an exact owner, generation and durable revision. Snapshots
 * are data, not authorization: only a trusted decoder/adapter may restore them. */
data class StorageState(
    val binding: Binding,
    val revision: Long = 0,
    val phase: Phase = Phase.ACTIVE,
    val evidence: Set<String> = emptySet(),
    val write: WriteIntent? = null,
    val deletion: DeleteIntent? = null,
    val removed: Set<String> = emptySet(),
    val tombstones: List<Tombstone> = emptyList(),
    val archives: List<ArchiveProof> = emptyList(),
    val replacement: ReplacementIntent? = null,
    val fault: StorageFault? = null,
    val lastWrite: WriteIntent? = null,
    val lastReplacement: ReplacementIntent? = null,
    val usedOperations: Set<String> = emptySet(),
) {
    fun validated(): StorageState {
        requirePolicy(revision >= 0, "invalid_revision")
        requirePolicy(usedOperations.all(::bounded), "invalid_operation_inventory")
        requirePolicy(evidence.all(::bounded) && removed.all(::bounded), "invalid_evidence")
        requirePolicy((phase == Phase.WRITE_PENDING) == (write != null), "invalid_write_state")
        requirePolicy((phase in setOf(Phase.DELETE_REQUESTED, Phase.CLEANUP_PENDING, Phase.TOMBSTONED)) == (deletion != null), "invalid_deletion_state")
        requirePolicy((phase == Phase.REPLACEMENT_PENDING) == (replacement != null), "invalid_replacement_state")
        requirePolicy(deletion != null || removed.isEmpty(), "invalid_cleanup_state")
        deletion?.let {
            requirePolicy(bounded(it.operationId) && it.operationId in usedOperations && it.artifacts.all(::bounded), "invalid_deletion")
            requirePolicy(it.receiptId == null || bounded(it.receiptId), "invalid_receipt")
            requirePolicy(removed.all { id -> id in it.artifacts }, "invalid_cleanup_evidence")
            requirePolicy(evidence == it.artifacts - removed, "cleanup_evidence_changed")
            requirePolicy((phase == Phase.DELETE_REQUESTED) == (it.receiptId == null), "invalid_receipt_state")
        }
        write?.let { requirePolicy(bounded(it.operationId) && it.operationId in usedOperations && it.digest.matches(Regex("[0-9a-f]{64}")), "invalid_write") }
        if (phase == Phase.TOMBSTONED) {
            requirePolicy(evidence.isEmpty() && removed == deletion!!.artifacts, "cleanup_not_complete")
            requirePolicy(tombstones.any { it.binding == binding && it.operationId == deletion!!.operationId && it.receiptId == deletion.receiptId }, "tombstone_missing")
        }
        requirePolicy(tombstones.all { bounded(it.operationId) && bounded(it.receiptId) }, "invalid_tombstone")
        requirePolicy(archives.all { bounded(it.receiptId) && it.artifactIds.all(::bounded) }, "invalid_archive")
        requirePolicy(tombstones.map { it.binding to it.operationId }.distinct().size == tombstones.size, "duplicate_tombstone")
        replacement?.let {
            requirePolicy(bounded(it.operationId) && it.operationId in usedOperations, "invalid_replacement_operation")
            requirePolicy(it.target.product == binding.product && it.target.owner == binding.owner && it.target.generation != binding.generation,
                "replacement_binding_invalid")
            requirePolicy(tombstones.none { old -> old.binding == it.target } && archives.none { old -> old.binding == it.target }, "retired_generation")
            if (it.archive == null) requirePolicy(evidence.isEmpty() && tombstones.any { old -> old.binding == binding }, "replacement_proof_missing")
            else requirePolicy(it.archive.binding == binding && it.archive.artifactIds == evidence && bounded(it.archive.receiptId), "verified_archive_required")
        }
        fun sameScope(b: Binding) = b.product == binding.product && b.owner == binding.owner
        requirePolicy(tombstones.all { sameScope(it.binding) && it.operationId in usedOperations }, "invalid_tombstone_scope")
        requirePolicy(archives.all { sameScope(it.binding) }, "invalid_archive_scope")
        requirePolicy(archives.map { it.binding }.distinct().size == archives.size, "duplicate_archive_generation")
        requirePolicy(archives.none { it.binding == binding }, "active_generation_archived")
        requirePolicy(tombstones.none { it.binding == binding } || phase in setOf(Phase.TOMBSTONED, Phase.REPLACEMENT_PENDING), "active_generation_tombstoned")
        lastWrite?.let { requirePolicy(bounded(it.operationId) && it.operationId in usedOperations && it.digest.matches(Regex("[0-9a-f]{64}")), "invalid_last_write") }
        lastReplacement?.let {
            requirePolicy(bounded(it.operationId) && it.operationId in usedOperations && it.target == binding, "invalid_last_replacement")
            if (it.archive != null) requirePolicy(it.archive in archives, "last_replacement_archive_missing")
            else requirePolicy(tombstones.any { old -> old.binding != binding }, "last_replacement_tombstone_missing")
        }
        return this
    }
}

object StorageLifecyclePolicy {
    private fun bump(s: StorageState): Long {
        s.validated(); requirePolicy(s.revision < Long.MAX_VALUE, "revision_exhausted"); return s.revision + 1
    }
    private fun token(s: StorageState, id: String, t: EffectToken) {
        requirePolicy(t.binding == s.binding && t.revision == s.revision && t.operationId == id, "stale_effect")
    }
    private fun newId(s: StorageState, id: String) {
        requirePolicy(bounded(id) && id !in s.usedOperations, "operation_id_reused_or_invalid")
    }
    fun beginWrite(s: StorageState, operationId: String, digest: String): StorageState {
        s.validated(); val intent = WriteIntent(operationId, digest)
        if (s.phase == Phase.WRITE_PENDING && s.write == intent) return s
        requirePolicy(s.phase == Phase.ACTIVE && s.fault == null, "write_blocked")
        newId(s, operationId)
        return s.copy(revision = bump(s), phase = Phase.WRITE_PENDING, write = intent,
            usedOperations = s.usedOperations + operationId).validated()
    }
    fun confirmWrite(s: StorageState, t: EffectToken, digest: String, artifactId: String): StorageState {
        s.validated(); requirePolicy(s.phase == Phase.WRITE_PENDING, "no_pending_write")
        token(s, s.write!!.operationId, t)
        requirePolicy(digest == s.write.digest && bounded(artifactId), "write_receipt_mismatch")
        return s.copy(revision = bump(s), phase = Phase.ACTIVE, evidence = s.evidence + artifactId,
            lastWrite = s.write, write = null, fault = null).validated()
    }
    fun recordFailure(s: StorageState, fault: StorageFault): StorageState {
        s.validated()
        // Each failure advances the fence. A previous successful health-write cannot clear it.
        return s.copy(revision = bump(s), fault = fault).validated()
    }
    fun confirmHealthWrite(s: StorageState, observedRevision: Long, binding: Binding): StorageState {
        s.validated(); requirePolicy(binding == s.binding && observedRevision == s.revision, "stale_health_write")
        requirePolicy(s.phase == Phase.ACTIVE, "outcome_unresolved")
        requirePolicy(s.fault in setOf(null, StorageFault.IO_UNAVAILABLE, StorageFault.NO_SPACE, StorageFault.PERMISSION_DENIED), "explicit_recovery_required")
        return if (s.fault == null) s else s.copy(revision = bump(s), fault = null).validated()
    }
    fun beginDeletion(s: StorageState, operationId: String, explicit: Boolean): StorageState {
        s.validated(); requirePolicy(explicit, "explicit_deletion_required")
        if (s.deletion?.operationId == operationId) return s
        requirePolicy(s.phase == Phase.ACTIVE, "unresolved_operation_blocks_deletion")
        newId(s, operationId)
        return s.copy(revision = bump(s), phase = Phase.DELETE_REQUESTED,
            deletion = DeleteIntent(operationId, s.evidence.toSet()), removed = emptySet(),
            usedOperations = s.usedOperations + operationId).validated()
    }
    /** Caller has authenticated/validated the remote receipt or a product-specific local-only
     * authorization. This API does NOT turn an arbitrary server response into proof. */
    fun acceptDeletionReceipt(s: StorageState, t: EffectToken, receiptId: String): StorageState {
        s.validated(); requirePolicy(s.phase == Phase.DELETE_REQUESTED, "deletion_receipt_not_expected")
        token(s, s.deletion!!.operationId, t); requirePolicy(bounded(receiptId), "invalid_receipt")
        return s.copy(revision = bump(s), phase = Phase.CLEANUP_PENDING,
            deletion = s.deletion.copy(receiptId = receiptId)).validated()
    }
    fun nextCleanup(s: StorageState): String? {
        s.validated(); requirePolicy(s.phase == Phase.CLEANUP_PENDING, "cleanup_not_authorized")
        return (s.deletion!!.artifacts - s.removed).sorted().firstOrNull()
    }
    /** A failed/unreadable unlink must NOT call this method. Only verified absence may do so. */
    fun confirmArtifactAbsent(s: StorageState, t: EffectToken, artifactId: String): StorageState {
        s.validated(); requirePolicy(s.phase == Phase.CLEANUP_PENDING, "cleanup_not_authorized")
        token(s, s.deletion!!.operationId, t)
        requirePolicy(artifactId in s.deletion.artifacts, "cleanup_outside_manifest")
        if (artifactId in s.removed) return s
        return s.copy(revision = bump(s), removed = s.removed + artifactId,
            evidence = s.evidence - artifactId).validated()
    }
    fun finishCleanup(s: StorageState, t: EffectToken): StorageState {
        s.validated(); requirePolicy(s.phase == Phase.CLEANUP_PENDING, "cleanup_not_pending")
        token(s, s.deletion!!.operationId, t)
        requirePolicy(s.removed == s.deletion.artifacts, "cleanup_not_complete")
        val tombstone = Tombstone(s.binding, s.deletion.operationId, s.deletion.receiptId!!)
        return s.copy(revision = bump(s), phase = Phase.TOMBSTONED,
            tombstones = s.tombstones + tombstone, fault = null).validated()
    }
    fun beginReplacement(s: StorageState, operationId: String, target: Binding,
        explicit: Boolean, archive: ArchiveProof? = null): StorageState {
        s.validated(); requirePolicy(explicit, "explicit_replacement_required")
        val intent = ReplacementIntent(operationId, target, archive)
        if (s.phase == Phase.REPLACEMENT_PENDING && s.replacement == intent) return s
        requirePolicy(s.phase == Phase.TOMBSTONED ||
            (s.phase == Phase.ACTIVE && CorruptionPolicy.replacementEligible(s.fault)), "replacement_blocked")
        requirePolicy(target.product == s.binding.product && target.owner == s.binding.owner && target.generation != s.binding.generation,
            "replacement_binding_invalid")
        requirePolicy(s.tombstones.none { it.binding == target } && s.archives.none { it.binding == target }, "retired_generation")
        if (s.phase != Phase.TOMBSTONED) {
            requirePolicy(archive != null && archive.binding == s.binding && archive.artifactIds == s.evidence && bounded(archive.receiptId),
                "verified_archive_required")
        } else requirePolicy(archive == null, "unexpected_archive")
        newId(s, operationId)
        return s.copy(revision = bump(s), phase = Phase.REPLACEMENT_PENDING, replacement = intent,
            deletion = null, removed = emptySet(), usedOperations = s.usedOperations + operationId).validated()
    }
    fun confirmReplacement(s: StorageState, t: EffectToken, created: Binding, newArtifacts: Set<String>): StorageState {
        s.validated(); requirePolicy(s.phase == Phase.REPLACEMENT_PENDING, "replacement_not_pending")
        token(s, s.replacement!!.operationId, t)
        requirePolicy(created == s.replacement.target && newArtifacts.isNotEmpty() && newArtifacts.all(::bounded), "replacement_receipt_mismatch")
        requirePolicy(newArtifacts.intersect(s.evidence).isEmpty(), "replacement_overwrites_evidence")
        return s.copy(binding = created, revision = bump(s), phase = Phase.ACTIVE,
            evidence = newArtifacts.toSet(), archives = s.archives + listOfNotNull(s.replacement.archive),
            lastReplacement = s.replacement, replacement = null, fault = null).validated()
    }
}

/** Product-specific compatibility guard for the existing M-Money replacement entry point.
 * The choice remains explicit in its caller; COMPLETE alone is not a deletion receipt. */
object LedgerReplacementPolicy {
    fun mayReplace(deleteState: String, hasReceipt: Boolean, sessionLost: Boolean, deletionAccessLost: Boolean): Boolean = when (deleteState) {
        "COMPLETE" -> hasReceipt
        "NONE" -> sessionLost
        "PENDING" -> sessionLost && deletionAccessLost && !hasReceipt
        else -> false
    }
}

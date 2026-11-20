package storagechecks

import rw.ikanisa.storagepolicy.*
import rw.ikanisa.burimunsi.core.*
import java.io.IOException
import java.nio.file.Files
import java.io.File

private val names = mutableListOf<String>()
private fun test(name: String, body: () -> Unit) { body(); names += name }
private fun rejected(code: String? = null, body: () -> Unit) {
    val error = runCatching(body).exceptionOrNull() ?: error("expected refusal: $code")
    if (code != null) check(when (error) { is StoragePolicyFailure -> error.code; is ContractFailure -> error.code; else -> error.message } == code) { "wrong refusal: $error expected $code" }
}
private val binding = Binding("burimunsi", "owner-1", "generation-1")
private val digest = "a".repeat(64)
private fun initial() = StorageState(binding, evidence = setOf("ledger", "originals", "key-wrap"))
private fun effect(s: StorageState, id: String) = EffectToken(s.binding, s.revision, id)
private fun deletion(): StorageState {
    val s = StorageLifecyclePolicy.beginDeletion(initial(), "delete-1", true)
    return StorageLifecyclePolicy.acceptDeletionReceipt(s, effect(s, "delete-1"), "verified-receipt-1")
}
private fun deleted(): StorageState {
    var s = deletion()
    while (StorageLifecyclePolicy.nextCleanup(s) != null) s = StorageLifecyclePolicy.confirmArtifactAbsent(s, effect(s, "delete-1"), StorageLifecyclePolicy.nextCleanup(s)!!)
    return StorageLifecyclePolicy.finishCleanup(s, effect(s, "delete-1"))
}
private fun operation(id: String = "00000000-0000-4000-8000-000000000001") = PendingOperation(id, "owner-scope", "POST /payment", "{\"exact\":\"é \\n\"}", Values.sha256("{\"exact\":\"é \\n\"}"), OperationState.PREPARED)
private class Port : OperationRecordPort {
    var active: PendingOperation? = null; var tombstone: OperationTombstone? = null
    var fail: String? = null; var retainRemoval = false; var lieOnWrite = false
    val events = mutableListOf<String>()
    private fun hit(point: String) { events += point; if (fail == point) { fail = null; throw IOException("synthetic_failure") } }
    override fun readActive(): PendingOperation? { hit("read-active"); return active }
    override fun readTombstone(): OperationTombstone? { hit("read-tombstone"); return tombstone }
    override fun writeActive(value: PendingOperation) {
        hit("write-active-before"); if (!lieOnWrite) active = value; hit("write-active-after")
    }
    override fun writeTombstone(value: OperationTombstone) {
        val p = if (value.cleanupComplete) "complete" else "tombstone"
        hit("$p-before"); if (!lieOnWrite) tombstone = value; hit("$p-after")
    }
    override fun removeActive() {
        hit("remove-before"); check(tombstone != null && !tombstone!!.cleanupComplete)
        if (!retainRemoval) active = null
        hit("remove-after")
    }
}
fun main() {
    for (base in ArtifactShape.values()) for (backup in ArtifactShape.values()) for (pending in ArtifactShape.values()) {
        test("opening-matrix-$base-$backup-$pending") {
            val i = RecordInventory(base, backup, pending); val result = RecordOpeningPolicy.decide(i)
            check((result == OpenDecision.FRESH) == (listOf(base, backup, pending).all { it == ArtifactShape.ABSENT }))
            if (pending != ArtifactShape.ABSENT) check(result != OpenDecision.FRESH && result != OpenDecision.READ_EXISTING)
            check(!RecordOpeningPolicy.mayCreateKey(i, true))
            check(RecordOpeningPolicy.mayCreateKey(i, false) == (result == OpenDecision.FRESH))
        }
    }
    for (fault in StorageFault.values()) test("no-silent-recovery-$fault") {
        check(!CorruptionPolicy.maySilentlyRecreate(fault) && !CorruptionPolicy.mayDeleteAsRecovery(fault))
        val s = StorageLifecyclePolicy.recordFailure(initial(), fault)
        check(s.evidence == initial().evidence)
        rejected("write_blocked") { StorageLifecyclePolicy.beginWrite(s, "write-1", digest) }
    }
    test("pending-write-retains-originals-and-id") {
        val s = StorageLifecyclePolicy.beginWrite(initial(), "write-1", digest)
        val failed = StorageLifecyclePolicy.recordFailure(s, StorageFault.NO_SPACE)
        check(failed.write == s.write && failed.evidence == s.evidence)
        check(StorageLifecyclePolicy.beginWrite(failed, "write-1", digest) == failed)
        rejected("write_blocked") { StorageLifecyclePolicy.beginWrite(failed, "write-2", digest) }
        rejected("unresolved_operation_blocks_deletion") { StorageLifecyclePolicy.beginDeletion(failed, "delete-1", true) }
        rejected("replacement_blocked") { StorageLifecyclePolicy.beginReplacement(failed, "replace-1", binding.copy(generation = "g2"), true) }
        rejected("outcome_unresolved") { StorageLifecyclePolicy.confirmHealthWrite(failed, failed.revision, binding) }
    }
    test("pending-write-only-exact-current-observation-resolves") {
        val s = StorageLifecyclePolicy.beginWrite(initial(), "write-1", digest)
        val failed = StorageLifecyclePolicy.recordFailure(s, StorageFault.IO_UNAVAILABLE)
        rejected("stale_effect") { StorageLifecyclePolicy.confirmWrite(failed, effect(s, "write-1"), digest, "write-record") }
        rejected("write_receipt_mismatch") { StorageLifecyclePolicy.confirmWrite(failed, effect(failed, "write-1"), "b".repeat(64), "write-record") }
        val done = StorageLifecyclePolicy.confirmWrite(failed, effect(failed, "write-1"), digest, "write-record")
        check(done.phase == Phase.ACTIVE && done.fault == null && done.evidence.containsAll(initial().evidence))
        rejected("operation_id_reused_or_invalid") { StorageLifecyclePolicy.beginWrite(done, "write-1", digest) }
    }
    test("health-write-cannot-clear-newer-failure-or-changed-owner") {
        val first = StorageLifecyclePolicy.recordFailure(initial(), StorageFault.NO_SPACE)
        val next = StorageLifecyclePolicy.recordFailure(first, StorageFault.IO_UNAVAILABLE)
        rejected("stale_health_write") { StorageLifecyclePolicy.confirmHealthWrite(next, first.revision, binding) }
        rejected("stale_health_write") { StorageLifecyclePolicy.confirmHealthWrite(next, next.revision, binding.copy(owner = "other")) }
        check(StorageLifecyclePolicy.confirmHealthWrite(next, next.revision, binding).fault == null)
    }
    test("corruption-is-not-cleared-by-free-space-or-health-write") {
        val s = StorageLifecyclePolicy.recordFailure(initial(), StorageFault.AUTHENTICATION_FAILED)
        rejected("explicit_recovery_required") { StorageLifecyclePolicy.confirmHealthWrite(s, s.revision, binding) }
    }
    test("deletion-intent-is-explicit-repeatable-and-nondestructive") {
        rejected("explicit_deletion_required") { StorageLifecyclePolicy.beginDeletion(initial(), "d", false) }
        val s = StorageLifecyclePolicy.beginDeletion(initial(), "d", true)
        check(s.evidence == initial().evidence && s.deletion!!.receiptId == null)
        check(StorageLifecyclePolicy.beginDeletion(s, "d", true) == s)
        rejected("cleanup_not_authorized") { StorageLifecyclePolicy.nextCleanup(s) }
        rejected("unresolved_operation_blocks_deletion") { StorageLifecyclePolicy.beginDeletion(s, "d2", true) }
    }
    test("deletion-receipt-exact-binding-and-revision") {
        val s = StorageLifecyclePolicy.beginDeletion(initial(), "d", true)
        for (t in listOf(effect(s, "other"), effect(s, "d").copy(binding = binding.copy(owner = "other")), effect(s, "d").copy(revision = 0))) {
            rejected("stale_effect") { StorageLifecyclePolicy.acceptDeletionReceipt(s, t, "receipt") }
        }
        rejected("invalid_receipt") { StorageLifecyclePolicy.acceptDeletionReceipt(s, effect(s, "d"), "") }
    }
    test("failed-cleanup-never-becomes-complete") {
        val s = deletion(); val failed = StorageLifecyclePolicy.recordFailure(s, StorageFault.IO_UNAVAILABLE)
        check(failed.phase == Phase.CLEANUP_PENDING && failed.evidence == s.evidence && failed.deletion == s.deletion)
        rejected("cleanup_not_complete") { StorageLifecyclePolicy.finishCleanup(failed, effect(failed, "delete-1")) }
        rejected("replacement_blocked") { StorageLifecyclePolicy.beginReplacement(failed, "replace", binding.copy(generation = "g2"), true) }
    }
    test("cleanup-only-manifest-targets-and-current-generation") {
        val s = deletion()
        rejected("cleanup_outside_manifest") { StorageLifecyclePolicy.confirmArtifactAbsent(s, effect(s, "delete-1"), "other") }
        rejected("stale_effect") { StorageLifecyclePolicy.confirmArtifactAbsent(s, effect(s, "delete-1").copy(binding = binding.copy(generation = "g2")), "ledger") }
    }
    for (id in initial().evidence.sorted()) test("cleanup-interrupted-after-unlink-$id") {
        // Storage effect succeeded, acknowledgment/state write did not. Re-observe the SAME id.
        val s = deletion(); val physical = s.evidence.toMutableSet(); physical.remove(id)
        val recovered = StorageLifecyclePolicy.confirmArtifactAbsent(s, effect(s, "delete-1"), id)
        check(recovered.evidence == physical && recovered.deletion == s.deletion)
        check(StorageLifecyclePolicy.confirmArtifactAbsent(recovered, effect(recovered, "delete-1"), id) == recovered)
    }
    test("completed-deletion-retains-tombstone-and-never-auto-recreates") {
        val s = deleted(); check(s.evidence.isEmpty() && s.tombstones.size == 1 && s.deletion!!.receiptId == "verified-receipt-1")
        rejected("write_blocked") { StorageLifecyclePolicy.beginWrite(s, "write", digest) }
        rejected("explicit_replacement_required") { StorageLifecyclePolicy.beginReplacement(s, "replace", binding.copy(generation = "g2"), false) }
    }
    test("explicit-replacement-retains-tombstone-and-target-on-failure") {
        val s = StorageLifecyclePolicy.beginReplacement(deleted(), "replace", binding.copy(generation = "g2"), true)
        val failed = StorageLifecyclePolicy.recordFailure(s, StorageFault.NO_SPACE)
        check(failed.replacement == s.replacement && failed.tombstones == s.tombstones)
        check(StorageLifecyclePolicy.beginReplacement(failed, "replace", s.replacement!!.target, true) == failed)
        rejected("replacement_blocked") { StorageLifecyclePolicy.beginReplacement(failed, "other", binding.copy(generation = "g3"), true) }
        rejected("replacement_receipt_mismatch") { StorageLifecyclePolicy.confirmReplacement(failed, effect(failed, "replace"), binding, setOf("new")) }
        val done = StorageLifecyclePolicy.confirmReplacement(failed, effect(failed, "replace"), s.replacement.target, setOf("new-ledger"))
        check(done.binding.generation == "g2" && done.tombstones == s.tombstones)
    }
    for (target in listOf(binding, binding.copy(owner = "other"), binding.copy(product = "mmoney"))) test("replacement-rejects-$target") {
        rejected("replacement_binding_invalid") { StorageLifecyclePolicy.beginReplacement(deleted(), "replace", target, true) }
    }
    test("corrupt-replacement-requires-verified-exact-archive") {
        val s = StorageLifecyclePolicy.recordFailure(initial(), StorageFault.MALFORMED)
        val target = binding.copy(generation = "g2")
        rejected("verified_archive_required") { StorageLifecyclePolicy.beginReplacement(s, "replace", target, true) }
        val archive = ArchiveProof(binding, s.evidence, "archive-receipt")
        rejected("verified_archive_required") { StorageLifecyclePolicy.beginReplacement(s, "replace", target, true, archive.copy(artifactIds = setOf("ledger"))) }
        val prepared = StorageLifecyclePolicy.beginReplacement(s, "replace", target, true, archive)
        rejected("replacement_overwrites_evidence") { StorageLifecyclePolicy.confirmReplacement(prepared, effect(prepared, "replace"), target, setOf("ledger")) }
        val done = StorageLifecyclePolicy.confirmReplacement(prepared, effect(prepared, "replace"), target, setOf("new-ledger"))
        check(done.archives.single() == archive && archive.artifactIds == initial().evidence)
    }
    test("corrupt-or-inconsistent-state-refuses-restoration") {
        rejected("invalid_write_state") { initial().copy(phase = Phase.WRITE_PENDING).validated() }
        rejected("invalid_deletion_state") { initial().copy(phase = Phase.TOMBSTONED).validated() }
        rejected("cleanup_evidence_changed") { deletion().copy(evidence = emptySet()).validated() }
        rejected("invalid_revision") { initial().copy(revision = -1).validated() }
        rejected("revision_exhausted") { StorageLifecyclePolicy.recordFailure(initial().copy(revision = Long.MAX_VALUE), StorageFault.NO_SPACE) }
    }
    // Simulated interruption on both sides of EVERY successful state-persistence transition.
    val transitions = mutableListOf<Pair<StorageState, StorageState>>()
    fun step(s: StorageState, f: (StorageState) -> StorageState): StorageState = f(s).also { transitions += s to it }
    var state = initial()
    state = step(state) { StorageLifecyclePolicy.beginWrite(it, "w", digest) }
    state = step(state) { StorageLifecyclePolicy.recordFailure(it, StorageFault.NO_SPACE) }
    state = step(state) { StorageLifecyclePolicy.confirmWrite(it, effect(it, "w"), digest, "w-artifact") }
    state = step(state) { StorageLifecyclePolicy.recordFailure(it, StorageFault.NO_SPACE) }
    state = step(state) { StorageLifecyclePolicy.confirmHealthWrite(it, it.revision, binding) }
    state = step(state) { StorageLifecyclePolicy.beginDeletion(it, "d", true) }
    state = step(state) { StorageLifecyclePolicy.acceptDeletionReceipt(it, effect(it, "d"), "receipt") }
    while (StorageLifecyclePolicy.nextCleanup(state) != null) state = step(state) { StorageLifecyclePolicy.confirmArtifactAbsent(it, effect(it, "d"), StorageLifecyclePolicy.nextCleanup(it)!!) }
    state = step(state) { StorageLifecyclePolicy.finishCleanup(it, effect(it, "d")) }
    state = step(state) { StorageLifecyclePolicy.beginReplacement(it, "r", binding.copy(generation = "g2"), true) }
    state = step(state) { StorageLifecyclePolicy.confirmReplacement(it, effect(it, "r"), binding.copy(generation = "g2"), setOf("new")) }
    transitions.forEachIndexed { index, pair ->
        for (afterCommit in listOf(false, true)) test("interruption-transition-$index-${if (afterCommit) "after" else "before"}-state-commit") {
            val reopened = (if (afterCommit) pair.second else pair.first).copy().validated()
            check(reopened == if (afterCommit) pair.second else pair.first)
            check(reopened.tombstones.containsAll(pair.first.tombstones))
            check(reopened.archives.containsAll(pair.first.archives))
            if (reopened.phase != Phase.ACTIVE) rejected { StorageLifecyclePolicy.beginWrite(reopened, "unsafe-new", digest) }
        }
    }
    test("mmoney-complete-without-receipt-never-authorizes-replacement") {
        check(!LedgerReplacementPolicy.mayReplace("COMPLETE", false, true, true))
        check(LedgerReplacementPolicy.mayReplace("COMPLETE", true, false, false))
        check(!LedgerReplacementPolicy.mayReplace("PENDING", true, true, true))
        check(!LedgerReplacementPolicy.mayReplace("invented", true, true, true))
        check(LedgerReplacementPolicy.mayReplace("PENDING", false, true, true))
    }
    test("classification-never-confuses-authentication-failure-with-permanent-key-loss") {
        check(StorageFailureClassifier.classify(IOException("wrapper", javax.crypto.AEADBadTagException("not logged"))) == StorageFault.AUTHENTICATION_FAILED)
        check(StorageFailureClassifier.classify(java.security.UnrecoverableKeyException("not logged")) == StorageFault.KEY_UNAVAILABLE)
        check(StorageFailureClassifier.classify(java.nio.file.AccessDeniedException("not logged")) == StorageFault.PERMISSION_DENIED)
        check(StorageFailureClassifier.classify(IllegalStateException("SQLiteFullException KEY_LOST")) == StorageFault.UNKNOWN)
        check(StorageFailureClassifier.classify(StoragePolicyFailure("storage_unsupported_version")) == StorageFault.UNSUPPORTED_VERSION)
        check(StorageFailureClassifier.classify(StoragePolicyFailure("storage_malformed")) == StorageFault.MALFORMED)
    }
    test("cyclic-and-deep-error-chains-terminate-without-destructive-recovery") {
        val a = Exception(); val b = Exception(a); a.initCause(b)
        check(StorageFailureClassifier.classify(a) == StorageFault.UNKNOWN)
        var deep: Throwable = IOException()
        repeat(40) { deep = Exception(deep) }
        check(StorageFailureClassifier.classify(deep) == StorageFault.UNKNOWN)
    }
    // Faults in real DurableOperationStore with a deterministic storage port (not Android I/O).
    for (point in listOf("read-active", "read-tombstone", "write-active-before", "write-active-after")) test("prepare-interruption-$point") {
        val p = Port(); val store = DurableOperationStore(p); val op = operation(); p.fail = point
        rejected { store.save(op) }
        check(p.tombstone == null && "remove-before" !in p.events)
        val restored = DurableOperationStore(p)
        if (p.active != null) {
            check(restored.load() == op)
            rejected("pending_operation_requires_resolution") { OperationJournal(restored).prepare("new-owner", "POST /payment", "{}") }
        }
        restored.save(op); check(restored.load() == op)
    }
    for (transition in listOf(OperationState.SENT, OperationState.UNKNOWN)) for (point in listOf("write-active-before", "write-active-after")) test("write-$transition-interruption-$point") {
        val p = Port(); val store = DurableOperationStore(p); val original = operation()
        store.save(original)
        val sent = original.copy(state = OperationState.SENT, attemptCount = 1); store.save(sent)
        val next = sent.copy(state = transition); p.fail = point; rejected { store.save(next) }
        val reopened = DurableOperationStore(p); check(reopened.load()!!.requestId == original.requestId)
        reopened.save(next); check(reopened.load() == next)
    }
    for (point in listOf("read-active", "read-tombstone", "tombstone-before", "tombstone-after", "remove-before", "remove-after", "complete-before", "complete-after")) test("terminal-interruption-$point") {
        val p = Port(); val store = DurableOperationStore(p); val op = operation(); store.save(op)
        val sent = op.copy(state = OperationState.SENT, attemptCount = 1); store.save(sent)
        val terminal = sent.copy(state = OperationState.COMMITTED); p.fail = point
        rejected { store.save(terminal) }
        check(p.active != null || p.tombstone != null) // evidence never disappears
        if ("remove-before" in p.events) check(p.events.indexOf("tombstone-after") < p.events.indexOf("remove-before"))
        val restored = DurableOperationStore(p)
        if (p.tombstone?.cleanupComplete == false) {
            check(OperationJournal(restored).unresolved()!!.requestId == op.requestId)
            rejected("pending_operation_requires_resolution") { OperationJournal(restored).prepare("s", "k", "{}") }
        }
        restored.save(terminal); check(!restored.cleanupPending() && restored.load() == terminal)
        restored.save(terminal); restored.clear(); restored.clear()
        check(p.active == null && p.tombstone!!.operation == terminal)
    }
    test("silent-unlink-failure-retains-tombstone-and-blocks-new-operation") {
        val p = Port(); val store = DurableOperationStore(p); val journal = OperationJournal(store)
        val op = journal.prepare("s", "k", "{}"); val attempt = journal.beginAttempt(op.requestId)
        p.retainRemoval = true; rejected("operation_delete_pending") { journal.completeAttempt(attempt) }
        check(journal.unresolved()!!.requestId == op.requestId && p.active != null && p.tombstone != null)
        rejected("pending_operation_requires_resolution") { journal.prepare("s", "k", "{}") }
        p.retainRemoval = false; journal.reconcile(op.requestId, OperationState.COMMITTED)
        check(journal.unresolved() == null && p.tombstone!!.cleanupComplete)
        val next = journal.prepare("s", "k", "{}"); check(next.requestId != op.requestId && p.tombstone!!.operation.requestId == op.requestId)
        rejected { store.save(op.copy(state = OperationState.REJECTED)) }
        check(store.load() == next)
    }
    test("unresolved-clear-and-owner-or-body-replacement-denied") {
        val p = Port(); val store = DurableOperationStore(p); val op = operation(); store.save(op)
        rejected("unresolved_operation_cannot_be_cleared") { store.clear() }
        rejected("pending_operation_requires_resolution") { store.save(op.copy(sessionScope = "other")) }
        rejected("invalid_stored_operation") { store.save(op.copy(body = "changed")) }
        check(p.active == op && p.tombstone == null)
    }
    test("unverified-active-write-does-not-report-success") {
        val p = Port(); p.lieOnWrite = true
        rejected("operation_commit_unverified") { DurableOperationStore(p).save(operation()) }
        check(p.active == null && p.tombstone == null)
    }
    test("unverified-tombstone-does-not-authorize-deletion") {
        val p = Port(); val store = DurableOperationStore(p); val op = operation(); store.save(op)
        p.lieOnWrite = true
        rejected("operation_tombstone_commit_unverified") { store.save(op.copy(state = OperationState.REJECTED)) }
        check(p.active == op && "remove-before" !in p.events)
    }
    test("corrupt-tombstone-retains-active-record") {
        val p = Port(); val store = DurableOperationStore(p); val op = operation(); store.save(op)
        p.tombstone = OperationTombstone(op, false)
        rejected("invalid_operation_tombstone") { store.load() }
        rejected("invalid_operation_tombstone") { store.resumeCleanup() }
        check(p.active == op)
    }
    test("conflicting-tombstone-does-not-delete-changed-owner") {
        val p = Port(); val op = operation(); p.active = op
        p.tombstone = OperationTombstone(op.copy(sessionScope = "other", state = OperationState.REJECTED), false)
        rejected("operation_tombstone_conflict") { DurableOperationStore(p).resumeCleanup() }
        check(p.active == op)
    }
    test("retired-command-resurrection-is-refused") {
        val p = Port(); val op = operation(); p.active = op
        p.tombstone = OperationTombstone(op.copy(state = OperationState.REJECTED), true)
        rejected("operation_tombstone_resurrection") { DurableOperationStore(p).load() }
        check(p.active == op)
    }
    test("physical-files-absent-pending-backup-corrupt-and-symlinks") {
        val dir = Files.createTempDirectory("storage-policy-").toFile()
        try {
            val base = File(dir, "store.v1"); check(ProtectedFileAccess.readable(base) == null)
            for (suffix in listOf(".new", ".bak")) {
                val retained = File(base.path + suffix); retained.writeText("evidence")
                rejected { ProtectedFileAccess.readable(base) }; rejected { ProtectedFileAccess.requireWritable(base) }
                check(retained.readText() == "evidence"); Files.delete(retained.toPath())
            }
            base.writeBytes(byteArrayOf()); rejected("storage_malformed") { ProtectedFileAccess.readable(base) }
            check(base.exists()); base.writeText("exact-original")
            check(ProtectedFileAccess.readable(base) == base)
            val link = File(base.path + ".new"); Files.createSymbolicLink(link.toPath(), File(dir, "missing").toPath())
            rejected("storage_unsafe_path") { ProtectedFileAccess.readable(base) }
            rejected("storage_delete_unsafe_or_unreadable") { ProtectedFileAccess.deleteVerified(base) }
            check(base.readText() == "exact-original"); Files.delete(link.toPath())
            ProtectedFileAccess.deleteVerified(base); ProtectedFileAccess.deleteVerified(base)
            check(ProtectedFileAccess.members(base).all { ProtectedFileAccess.shape(it) == ArtifactShape.ABSENT })
        } finally { dir.deleteRecursively() }
    }
    println("{\"status\":\"passed\",\"checks\":${names.size},\"names\":[" + names.joinToString(",") { "\"$it\"" } + "]}")
}

package rw.ikanisa.burimunsi.core

import java.util.UUID

/** Terminal proof survives removal of the active command. Never a server receipt by itself:
 * only OperationJournal's verified-outcome path is permitted to supply a terminal state. */
data class OperationTombstone(val operation: PendingOperation, val cleanupComplete: Boolean)

/** Each write must commit durably or throw. Reads must distinguish absence from failed/corrupt
 * reads. removeActive must verify absence, not just call an unchecked platform delete().
 * Serialize access across ALL instances/processes at the adapter boundary. */
interface OperationRecordPort {
    fun readActive(): PendingOperation?
    fun writeActive(value: PendingOperation)
    fun removeActive()
    fun readTombstone(): OperationTombstone?
    fun writeTombstone(value: OperationTombstone)
}

/** No I/O error is converted to null, and no unresolved command can be cleared or replaced.
 * A failed unlink leaves the terminal tombstone pending; a later explicit prepare/cleanup can
 * retry that SAME cleanup. load() is read-only and never deletes evidence. */
class DurableOperationStore(private val port: OperationRecordPort) : OperationStore {
    private fun terminal(v: PendingOperation) = v.state in setOf(OperationState.COMMITTED, OperationState.REJECTED)
    private fun validate(v: PendingOperation): PendingOperation {
        checkContract(runCatching { UUID.fromString(v.requestId).toString() == v.requestId }.getOrDefault(false), "invalid_stored_operation")
        checkContract(v.sessionScope.isNotBlank() && v.sessionScope.length <= 512 && v.kind.isNotBlank() && v.kind.length <= 512 &&
            v.body.toByteArray(Charsets.UTF_8).size <= 2_000_000 && v.bodySha256 == Values.sha256(v.body) && v.attemptCount >= 0,
            "invalid_stored_operation")
        checkContract(v.state != OperationState.PREPARED || v.attemptCount == 0, "invalid_stored_operation")
        return v
    }
    private fun proof(): OperationTombstone? = port.readTombstone()?.also {
        validate(it.operation); checkContract(terminal(it.operation), "invalid_operation_tombstone")
    }
    private fun active() = port.readActive()?.let(::validate)
    private fun sameCommand(a: PendingOperation, b: PendingOperation): Boolean = a.requestId == b.requestId &&
        a.sessionScope == b.sessionScope && a.kind == b.kind && a.body == b.body && a.bodySha256 == b.bodySha256
    private fun compatible(a: PendingOperation, t: OperationTombstone) {
        checkContract(sameCommand(a, t.operation) && a.attemptCount == t.operation.attemptCount &&
            (!terminal(a) || a.state == t.operation.state), "operation_tombstone_conflict")
    }
    private fun persistProof(t: OperationTombstone) {
        port.writeTombstone(t)
        checkContract(proof() == t, "operation_tombstone_commit_unverified")
    }
    @Synchronized override fun load(): PendingOperation? {
        val a = active(); val t = proof() ?: return a
        if (!t.cleanupComplete) {
            if (a != null) compatible(a, t)
            return t.operation // terminal outcome is durable; cleanup is not yet complete
        }
        checkContract(a == null || a.requestId != t.operation.requestId, "operation_tombstone_resurrection")
        return a ?: t.operation
    }
    @Synchronized override fun cleanupPending(): Boolean = proof()?.cleanupComplete == false
    /** Only a durable terminal tombstone authorizes cleanup. This can be called repeatedly. */
    @Synchronized fun resumeCleanup() {
        val t = proof() ?: return
        if (t.cleanupComplete) {
            val a = active()
            checkContract(a == null || a.requestId != t.operation.requestId, "operation_tombstone_resurrection")
            return
        }
        active()?.let { compatible(it, t) }
        port.removeActive()
        checkContract(active() == null, "operation_delete_pending")
        persistProof(t.copy(cleanupComplete = true))
    }
    @Synchronized override fun save(value: PendingOperation) {
        validate(value)
        var a = active(); var t = proof()
        if (t != null && !t.cleanupComplete) {
            // Never delete a changed record on behalf of a stale tombstone.
            if (a != null) compatible(a, t)
            if (terminal(value)) checkContract(t.operation == value, "conflicting_terminal_outcome")
            resumeCleanup(); a = active(); t = proof()
        }
        if (a != null && terminal(a)) {
            checkContract(t == null || t.operation.requestId != a.requestId, "operation_tombstone_resurrection")
            // Migration of a legacy terminal active record, not deletion of an unresolved record.
            persistProof(OperationTombstone(a, false)); resumeCleanup(); a = null; t = proof()
        }
        if (terminal(value)) {
            if (a == null) {
                checkContract(t?.operation == value, "missing_operation_for_terminal_outcome")
                return
            }
            checkContract(sameCommand(a, value) && a.attemptCount == value.attemptCount, "operation_changed")
            checkContract(a.state != OperationState.PREPARED || value.state == OperationState.REJECTED, "invalid_operation_transition")
            persistProof(OperationTombstone(value, false))
            resumeCleanup()
            return
        }
        if (a == null) {
            checkContract(value.state == OperationState.PREPARED && value.attemptCount == 0, "invalid_initial_operation")
            checkContract(t?.operation?.requestId != value.requestId, "retired_operation_id")
        } else {
            checkContract(sameCommand(a, value), "pending_operation_requires_resolution")
            val allowed = value == a || when (a.state) {
                OperationState.PREPARED -> value.state == OperationState.SENT && value.attemptCount in setOf(0, 1)
                OperationState.SENT, OperationState.UNKNOWN ->
                    (value.state == OperationState.UNKNOWN && value.attemptCount == a.attemptCount) ||
                    (value.state == OperationState.SENT && (value.attemptCount == a.attemptCount ||
                        (a.attemptCount < Int.MAX_VALUE && value.attemptCount == a.attemptCount + 1)))
                else -> false
            }
            checkContract(allowed, "invalid_operation_transition")
        }
        port.writeActive(value)
        checkContract(active() == value, "operation_commit_unverified")
    }
    @Synchronized override fun clear() {
        val a = active()
        checkContract(a == null || terminal(a) || proof()?.let { it.operation.let(::terminal) && sameCommand(a, it.operation) } == true,
            "unresolved_operation_cannot_be_cleared")
        if (a != null && terminal(a)) save(a) else resumeCleanup()
    }
}

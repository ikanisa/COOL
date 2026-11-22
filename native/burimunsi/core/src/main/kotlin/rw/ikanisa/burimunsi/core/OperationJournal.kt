package rw.ikanisa.burimunsi.core

import java.util.UUID
import java.util.IdentityHashMap

/** SENT is a durable *dispatch fence*, not proof of network delivery. */
enum class OperationState { PREPARED, SENT, UNKNOWN, COMMITTED, REJECTED }
data class PendingOperation(val requestId: String, val sessionScope: String, val kind: String,
    val body: String, val bodySha256: String, val state: OperationState, val attemptCount: Int = 0,
    val ownerAccountId: String? = null, val groupId: String? = null) {
    override fun toString() = "PendingOperation(state=$state, attemptCount=$attemptCount)"
}
/** A process-local witness bound to the exact immutable command, not its UUID alone.
 * It is not server authority and is never a credential. */
@ConsistentCopyVisibility
data class OperationAttempt internal constructor(val operation: PendingOperation, val sequence: Int,
    val uncertainPredecessor: Boolean) {
    val requestId: String get() = operation.requestId
}
interface OperationStore {
    /** All wrappers for the same storage namespace must share this process-local lock.
     * Cross-process exclusion and physical durability are adapter qualification gates. */
    val coordinationLock: Any get() = this
    fun load(): PendingOperation?
    /** Save MUST retain terminal records. Deletion belongs to finishCleanup only. */
    fun save(value: PendingOperation)
    fun clear()
}

/** Entries exist only while a read is executing. Identity-keyed namespaces avoid
 * accidental coalescing of adapters with equal-but-distinct lock objects. */
private object RecoveryReads {
    private val active = IdentityHashMap<Any, Any>()
    @Synchronized fun begin(namespace: Any): Any {
        checkContract(!active.containsKey(namespace), "recovery_check_in_progress")
        return Any().also { active[namespace] = it }
    }
    @Synchronized fun finish(namespace: Any, lease: Any) {
        if (active[namespace] === lease) active.remove(namespace)
    }
}

/** Platform-independent journal. It emits no network requests, renews no authority,
 * and never replaces an unresolved command. Callers validate authenticated outcome
 * evidence under their still-current session witness before reconcile/completeAttempt.
 * Read-back checks detect adapter failures; they are not an fsync/power-loss proof. */
class OperationJournal(private val store: OperationStore,
    private val newRequestId: () -> String = { UUID.randomUUID().toString() }) {
    private val terminal = setOf(OperationState.COMMITTED, OperationState.REJECTED)
    private fun loaded(): PendingOperation? = store.load()?.also {
        Values.requestId(it.requestId)
        checkContract(it.sessionScope.isNotBlank() && it.kind.isNotBlank() &&
            it.bodySha256 == Values.sha256(it.body) && it.attemptCount >= 0 &&
            ((it.ownerAccountId == null && it.groupId == null) ||
                (!it.ownerAccountId.isNullOrBlank() && !it.groupId.isNullOrBlank())), "corrupt_operation")
    }
    private fun persist(value: PendingOperation) {
        store.save(value)
        checkContract(loaded() == value, "operation_store_unavailable")
    }
    fun prepare(sessionScope: String, kind: String, body: String, ownerAccountId: String? = null, groupId: String? = null): PendingOperation = synchronized(store.coordinationLock) {
        checkContract((ownerAccountId == null && groupId == null) ||
            (!ownerAccountId.isNullOrBlank() && !groupId.isNullOrBlank()), "invalid_operation_owner")
        // Even a verified terminal outcome keeps the gate closed until cleanup finishes.
        checkContract(loaded() == null, "pending_operation_requires_resolution")
        checkContract(sessionScope.isNotBlank() && kind.isNotBlank(), "invalid_operation")
        val next = PendingOperation(Values.requestId(newRequestId()), sessionScope, kind,
            body, Values.sha256(body), OperationState.PREPARED, ownerAccountId = ownerAccountId, groupId = groupId)
        persist(next)
        next
    }
    /** One dispatch fence per command. No SENT/UNKNOWN -> SENT transition exists.
     * A crash after the fence but before I/O sacrifices availability, never safety. */
    fun beginAttempt(expected: PendingOperation, sessionScope: String): OperationAttempt = synchronized(store.coordinationLock) {
        val current = owned(expected)
        checkContract(current.state == OperationState.PREPARED && current.attemptCount == 0 &&
            current.sessionScope == sessionScope, "pending_operation_requires_resolution")
        val attempt = OperationAttempt(current, 1, false)
        persist(current.copy(state = OperationState.SENT, attemptCount = attempt.sequence))
        attempt
    }
    /** Only after the matching authenticated retained outcome, never a POST ACK alone. */
    fun completeAttempt(attempt: OperationAttempt) = synchronized(store.coordinationLock) {
        val current = attemptOwned(attempt)
        persist(current.copy(state = OperationState.COMMITTED))
    }
    @Suppress("UNUSED_PARAMETER")
    fun failAttempt(attempt: OperationAttempt, httpStatus: Int, uncertain: Boolean) = synchronized(store.coordinationLock) {
        val current = attemptOwned(attempt)
        // HTTP errors (including 4xx) are not durable, origin-bound no-effect receipts.
        // The v1 recovery protocol has no authoritative rejected result. Never infer one.
        persist(current.copy(state = OperationState.UNKNOWN))
    }
    /** State and attempt count may advance, but immutable command bytes may not.
     * A valid checksum does not make a replacement record the original operation.
     * The retained snapshot must come from prepare/unresolved before asynchronous I/O. */
    private fun owned(expected: PendingOperation): PendingOperation {
        val current = loaded() ?: throw ContractFailure("missing_operation")
        checkContract(current.requestId == expected.requestId, "operation_changed")
        checkContract(current.sessionScope == expected.sessionScope && current.kind == expected.kind &&
            current.body == expected.body && current.bodySha256 == expected.bodySha256 &&
            current.ownerAccountId == expected.ownerAccountId && current.groupId == expected.groupId,
            "operation_identity_changed")
        return current
    }
    private fun attemptOwned(attempt: OperationAttempt): PendingOperation {
        val current = owned(attempt.operation)
        checkContract(current.state == OperationState.SENT && current.attemptCount == attempt.sequence &&
            attempt.sequence == 1 && !attempt.uncertainPredecessor, "operation_attempt_changed")
        return current
    }
    /** Compatibility only for marking uncertainty. Dispatch and completion must use
     * their witnessed APIs; this method cannot bypass either gate. */
    fun mark(expected: PendingOperation, next: OperationState) = synchronized(store.coordinationLock) {
        val current = owned(expected)
        checkContract(next == OperationState.UNKNOWN && current.state in
            setOf(OperationState.SENT, OperationState.UNKNOWN), "invalid_operation_transition")
        persist(current.copy(state = next))
    }
    /** Caller must have authenticated, decoded and owner-bound this exact request.
     * REJECTED remains a legacy/future proof state; the current v1 decoder refuses it. */
    fun reconcile(expected: PendingOperation, outcome: OperationState) = synchronized(store.coordinationLock) {
        checkContract(outcome in terminal, "invalid_reconciliation")
        val current = owned(expected)
        checkContract(current.state !in terminal || current.state == outcome, "conflicting_reconciliation")
        if (current.state != outcome) persist(current.copy(state = outcome))
    }
    /** Missing receipt / pending is not rejection. Nor may it downgrade a retained
     * terminal proof during interrupted cleanup. There is no journal rewrite here. */
    fun observePending(expected: PendingOperation) = synchronized(store.coordinationLock) {
        checkContract(owned(expected).state !in terminal, "conflicting_reconciliation")
    }
    /** Runs with the same operation lock as prepare/beginAttempt. Cache cleanup MUST
     * verify absence itself and throw on failure. If any step fails, no compensating
     * deletion/recreation is attempted. Re-entry after interruption is safe. */
    fun finishCleanup(expected: PendingOperation, invalidateRecords: () -> Unit) = synchronized(store.coordinationLock) {
        val before = owned(expected)
        checkContract(before.state in terminal, "operation_not_resolved")
        invalidateRecords()
        // Reentrant/misbehaving adapters may substitute evidence while this callback
        // runs. Never delete a same-ID replacement, changed outcome or changed count.
        val after = owned(expected)
        checkContract(after.state == before.state, "conflicting_reconciliation")
        checkContract(after == before, "operation_attempt_changed")
        store.clear()
        checkContract(loaded() == null, "operation_store_unavailable")
    }
    /** At most one status read/apply/cleanup for this storage namespace in-process.
     * Never hold the journal lock across I/O. No timeout steals a live lease; transport
     * cancellation must unwind this scope. A re-login cannot bypass an active read.
     * This is not cross-process exclusion or server financial idempotency. */
    fun <T> withRecoveryRead(expected: PendingOperation, action: () -> T): T {
        val namespace = store.coordinationLock
        val lease = synchronized(namespace) { owned(expected); RecoveryReads.begin(namespace) }
        return try { action() } finally { RecoveryReads.finish(namespace, lease) }
    }
    /** Any retained record blocks replacement, including terminal cleanup debt. */
    fun unresolved(): PendingOperation? = synchronized(store.coordinationLock) { loaded() }
}

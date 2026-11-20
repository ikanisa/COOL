package rw.ikanisa.burimunsi.core

import java.util.UUID

/** Persisted BEFORE dispatch. A failed retry is not evidence that the original
 * command failed. Only an authenticated durable outcome can resolve that case. */
enum class OperationState { PREPARED, SENT, UNKNOWN, COMMITTED, REJECTED }
data class PendingOperation(val requestId: String, val sessionScope: String, val kind: String,
    val body: String, val bodySha256: String, val state: OperationState, val attemptCount: Int = 0)
data class OperationAttempt internal constructor(val requestId: String, val sequence: Int,
    val uncertainPredecessor: Boolean)
interface OperationStore {
    fun load(): PendingOperation?
    fun save(value: PendingOperation)
    fun clear()
}
class OperationJournal(private val store: OperationStore) {
    private val terminal = setOf(OperationState.COMMITTED, OperationState.REJECTED)
    @Synchronized fun prepare(sessionScope: String, kind: String, body: String): PendingOperation {
        val previous = store.load()
        val hash = Values.sha256(body)
        // Repeated UI taps, process restoration and a matching payload are NOT
        // proof that an earlier transmission was never accepted. Never resubmit it.
        // Only an authenticated result lookup may close an unresolved operation.
        checkContract(previous == null || previous.state in terminal,
            "pending_operation_requires_resolution")
        val next = PendingOperation(UUID.randomUUID().toString(), sessionScope, kind, body, hash, OperationState.PREPARED)
        store.save(next)
        return next
    }
    /** The durable sequence prevents a delayed failure from overwriting a newer
     * attempt or an authenticated reconciliation. No network I/O belongs here. */
    @Synchronized fun beginAttempt(requestId: String): OperationAttempt {
        val current = owned(requestId)
        checkContract(current.state !in terminal && current.attemptCount in 0 until Int.MAX_VALUE, "invalid_operation_transition")
        val attempt = OperationAttempt(requestId, current.attemptCount + 1,
            current.state != OperationState.PREPARED || current.attemptCount > 0)
        store.save(current.copy(state = OperationState.SENT, attemptCount = attempt.sequence))
        return attempt
    }
    @Synchronized fun completeAttempt(attempt: OperationAttempt) {
        val current = attemptOwned(attempt)
        store.save(current.copy(state = OperationState.COMMITTED))
    }
    @Synchronized fun failAttempt(attempt: OperationAttempt, httpStatus: Int, uncertain: Boolean) {
        val current = attemptOwned(attempt)
        // These responses have a rollback/no-effect contract on the FIRST attempt.
        // 408, 425, malformed replies, network errors and server errors are uncertain.
        val definiteInitialRejection = !attempt.uncertainPredecessor && !uncertain &&
            httpStatus in setOf(400, 401, 403, 404, 405, 409, 413, 415, 422)
        store.save(current.copy(state = if (definiteInitialRejection) OperationState.REJECTED else OperationState.UNKNOWN))
    }
    private fun owned(requestId: String): PendingOperation {
        val current = store.load() ?: throw ContractFailure("missing_operation")
        checkContract(current.requestId == requestId, "operation_changed")
        return current
    }
    private fun attemptOwned(attempt: OperationAttempt): PendingOperation {
        val current = owned(attempt.requestId)
        checkContract(current.state == OperationState.SENT && current.attemptCount == attempt.sequence,
            "operation_attempt_changed")
        return current
    }
    /** Compatibility for callers that only mark uncertainty or a verified success.
     * REJECTED cannot be inferred from SENT/UNKNOWN through this low-level method. */
    @Synchronized fun mark(requestId: String, next: OperationState) {
        val current = owned(requestId)
        val allowed = when(current.state) {
            OperationState.PREPARED -> setOf(OperationState.SENT, OperationState.REJECTED)
            OperationState.SENT, OperationState.UNKNOWN -> setOf(OperationState.UNKNOWN, OperationState.COMMITTED, OperationState.SENT)
            else -> emptySet()
        }
        checkContract(next in allowed, "invalid_operation_transition")
        store.save(current.copy(state = next))
    }
    /** Only an authenticated outcome lookup for this exact account/request may call this. */
    @Synchronized fun reconcile(requestId: String, outcome: OperationState) {
        checkContract(outcome in terminal, "invalid_reconciliation")
        val current = owned(requestId)
        checkContract(current.state !in terminal || current.state == outcome, "conflicting_reconciliation")
        store.save(current.copy(state = outcome))
    }
    @Synchronized fun unresolved(): PendingOperation? = store.load()?.takeIf { it.state !in terminal }
}

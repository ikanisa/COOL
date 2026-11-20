package rw.ikanisa.burimunsi.core

/** Local admission policy, not a timer, credential, durable rate limiter or financial
 * operation retry. A caller must still authenticate and validate every GET response. */
data class RecoveryRetryPolicy(val maxChecks: Int = 5, val baseDelayMs: Long = 1_000,
    val maxDelayMs: Long = 30_000) {
    init {
        require(maxChecks in 1..100) { "maxChecks must be in 1..100" }
        require(baseDelayMs > 0 && maxDelayMs >= baseDelayMs) { "Invalid recovery backoff" }
    }
}

data class RecoveryReadScope(val generation: Long, val sessionDigest: String) {
    init { require(generation >= 0 && Regex("[a-f0-9]{64}").matches(sessionDigest)) }
}
enum class RecoveryReadResult {
    PENDING, TRANSIENT_FAILURE, AUTH_REQUIRED, DENIED, INVALID_RESPONSE, CONFLICT,
    CLEANUP_FAILED, CANCELLED, RESOLVED
}
enum class RecoveryRetryPhase { READY, IN_FLIGHT, BACKOFF, AUTH_REQUIRED, STOPPED, EXHAUSTED, COMPLETE }
data class RecoveryRetrySnapshot(val phase: RecoveryRetryPhase, val checksStarted: Int,
    val nextCheckAtMs: Long?, val reason: String?)
/** Object identity, not user supplied sequence numbers, identifies a completion. */
class RecoveryReadTicket internal constructor(val checkNumber: Int, internal val scope: RecoveryReadScope)

/** One bounded status-check cycle for one immutable command. Time is a caller-supplied
 * nonnegative monotonic tick. No timers, threads, journal writes, credentials, UUIDs,
 * POSTs or resets are created here. State advancement does not change command identity.
 * Reconstructing this object starts a new LOCAL cycle, not a new financial operation.
 * Authentication, ownership and response proofs remain the repository's responsibility. */
class ReadOnlyRecoveryRetry(private val original: PendingOperation,
    private val policy: RecoveryRetryPolicy = RecoveryRetryPolicy()) {
    private var phase = RecoveryRetryPhase.READY
    private var checks = 0
    private var nextAt: Long? = 0
    private var lastTime = 0L
    private var reason: String? = null
    private var active: RecoveryReadTicket? = null
    private var deniedScope: RecoveryReadScope? = null
    init { validate(original) }
    private fun validate(op: PendingOperation) {
        Values.requestId(op.requestId)
        checkContract(op.sessionScope.isNotBlank() && op.kind.isNotBlank() &&
            op.bodySha256 == Values.sha256(op.body) && op.attemptCount >= 0, "corrupt_operation")
    }
    private fun match(op: PendingOperation) {
        validate(op)
        checkContract(op.requestId == original.requestId, "operation_changed")
        checkContract(op.sessionScope == original.sessionScope && op.kind == original.kind &&
            op.body == original.body && op.bodySha256 == original.bodySha256 &&
            op.ownerAccountId == original.ownerAccountId && op.groupId == original.groupId, "operation_identity_changed")
    }
    private fun observe(nowMs: Long) {
        checkContract(nowMs >= 0 && nowMs >= lastTime, "recovery_clock_invalid")
        lastTime = nowMs
    }
    @Synchronized fun snapshot() = RecoveryRetrySnapshot(phase, checks, nextAt, reason)
    @Synchronized fun begin(current: PendingOperation, scope: RecoveryReadScope, nowMs: Long): RecoveryReadTicket {
        match(current)
        checkContract(nowMs >= 0 && nowMs >= lastTime, "recovery_clock_invalid")
        checkContract(active == null, "recovery_check_in_progress")
        checkContract(phase != RecoveryRetryPhase.COMPLETE, "recovery_already_resolved")
        checkContract(phase != RecoveryRetryPhase.STOPPED, "recovery_retry_stopped")
        checkContract(checks < policy.maxChecks && phase != RecoveryRetryPhase.EXHAUSTED, "recovery_retry_exhausted")
        checkContract(phase != RecoveryRetryPhase.AUTH_REQUIRED || scope != deniedScope, "recovery_authentication_required")
        checkContract(nowMs >= (nextAt ?: Long.MAX_VALUE), "recovery_retry_backoff")
        lastTime = nowMs
        checks += 1
        phase = RecoveryRetryPhase.IN_FLIGHT
        reason = null
        return RecoveryReadTicket(checks, scope).also { active = it }
    }
    @Synchronized fun finish(ticket: RecoveryReadTicket, result: RecoveryReadResult,
        nowMs: Long, minimumDelayMs: Long = 0): RecoveryRetrySnapshot {
        checkContract(active === ticket, "recovery_attempt_changed")
        checkContract(minimumDelayMs >= 0, "invalid_recovery_delay")
        observe(nowMs)
        active = null
        reason = result.name.lowercase()
        when (result) {
            RecoveryReadResult.RESOLVED -> { phase = RecoveryRetryPhase.COMPLETE; nextAt = null }
            RecoveryReadResult.DENIED, RecoveryReadResult.INVALID_RESPONSE, RecoveryReadResult.CONFLICT -> {
                phase = RecoveryRetryPhase.STOPPED; nextAt = null
            }
            else -> {
                if (checks >= policy.maxChecks) {
                    phase = RecoveryRetryPhase.EXHAUSTED; nextAt = null
                } else {
                    var delay = policy.baseDelayMs
                    repeat(checks - 1) {
                        delay = if (delay > policy.maxDelayMs / 2) policy.maxDelayMs
                            else minOf(policy.maxDelayMs, delay * 2)
                    }
                    delay = maxOf(delay, minimumDelayMs) // Never shorten a supplied Retry-After floor.
                    if (nowMs > Long.MAX_VALUE - delay) {
                        phase = RecoveryRetryPhase.STOPPED; nextAt = null; reason = "recovery_clock_exhausted"
                    } else {
                        nextAt = nowMs + delay
                        phase = if (result == RecoveryReadResult.AUTH_REQUIRED) RecoveryRetryPhase.AUTH_REQUIRED
                            else RecoveryRetryPhase.BACKOFF
                        if (result == RecoveryReadResult.AUTH_REQUIRED) deniedScope = ticket.scope
                    }
                }
            }
        }
        return snapshot()
    }
}

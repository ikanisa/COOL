package rw.ikanisa.sms.policy

enum class Phase { READY, IN_FLIGHT, RETRY_WAIT, HELD, ACK_PENDING, ACKNOWLEDGED, REJECTED, CONFLICT }
data class Attempt(val key: String,val operationId: String,val payloadHash: String,
                   val ordinal: Int,val sessionEpoch: Long,val startedAt: Long)
/** Evidence remains attached even in terminal states. Retention/deletion is a separate policy. */
class QueueSnapshot internal constructor(
    val batch: UploadBatch,val revision: Long,val phase: Phase,val reason: String,
    val attempts: Int,val firstAttemptAt: Long?,val lastObservedAt: Long,val notBefore: Long?,
    val activeAttempt: Attempt?,val outcomeUncertain: Boolean,
    receipts: List<VerifiedReceipt> = emptyList(),conflictingReceipts: List<VerifiedReceipt> = emptyList(),
) {
    val receipts = frozen(receipts)
    val conflictingReceipts = frozen(conflictingReceipts)
    internal fun evolve(phase: Phase = this.phase,reason: String = this.reason,attempts: Int = this.attempts,
        firstAttemptAt: Long? = this.firstAttemptAt,lastObservedAt: Long = this.lastObservedAt,
        notBefore: Long? = this.notBefore,activeAttempt: Attempt? = this.activeAttempt,
        outcomeUncertain: Boolean = this.outcomeUncertain,receipts: List<VerifiedReceipt> = this.receipts,
        conflictingReceipts: List<VerifiedReceipt> = this.conflictingReceipts) =
        QueueSnapshot(batch,revision+1,phase,reason,attempts,firstAttemptAt,lastObservedAt,notBefore,
            activeAttempt,outcomeUncertain,receipts,conflictingReceipts)
    fun valid(): Boolean {
        if (!batch.valid() || revision < 0 || attempts !in 0..100 || lastObservedAt < 0) return false
        if (attempts == 0) {
            if (activeAttempt != null || firstAttemptAt != null || outcomeUncertain) return false
        } else {
            val a = activeAttempt ?: return false
            if (a.ordinal != attempts || a.key != batch.key || a.operationId != batch.operationId ||
                a.payloadHash != batch.payloadHash || a.sessionEpoch <= 0 || a.startedAt < 0 ||
                firstAttemptAt == null || firstAttemptAt < 0 || firstAttemptAt > a.startedAt || a.startedAt > lastObservedAt) return false
        }
        if (phase == Phase.IN_FLIGHT && activeAttempt == null) return false
        if (phase == Phase.RETRY_WAIT && (notBefore == null || notBefore < lastObservedAt || activeAttempt == null || !outcomeUncertain)) return false
        if (phase != Phase.RETRY_WAIT && notBefore != null) return false
        if (phase in setOf(Phase.ACK_PENDING,Phase.ACKNOWLEDGED,Phase.REJECTED) && (activeAttempt == null || receipts.isEmpty() || outcomeUncertain)) return false
        if (receipts.isNotEmpty()) {
            if (phase !in setOf(Phase.ACK_PENDING,Phase.ACKNOWLEDGED,Phase.REJECTED,Phase.CONFLICT)) return false
            if (receipts.size != batch.originals.size || receipts.map { it.captureId }.toSet() != batch.originals.map { it.captureId }.toSet()) return false
            if (receipts.any { r -> when (r.outcome) {
                ReceiptOutcome.RETAINED -> r.canonicalId?.let(EvidenceHash::identity) != true || r.rejectionCode != null ||
                    (batch.scope.contract == Contract.MMONEY_LEDGER_V1 && (r.canonicalId?.let(AckPolicy::uuid) != true || r.bodySha256 != null)) ||
                    (batch.scope.contract == Contract.BURI_COLLECT_V2 && r.bodySha256 != batch.originals.single().bodySha256)
                ReceiptOutcome.REJECTED -> r.canonicalId != null || r.bodySha256 != null || r.rejectionCode?.matches(Regex("[A-Z0-9_]{1,64}")) != true || batch.scope.contract == Contract.BURI_COLLECT_V2
            } }) return false
        }
        if (phase == Phase.ACKNOWLEDGED && receipts.any { it.outcome != ReceiptOutcome.RETAINED }) return false
        if (phase == Phase.REJECTED && receipts.none { it.outcome == ReceiptOutcome.REJECTED }) return false
        if (conflictingReceipts.isNotEmpty() && phase != Phase.CONFLICT) return false
        return true
    }
    override fun toString() = "QueueSnapshot(phase=$phase,reason=$reason,revision=$revision,attempts=$attempts)"
    companion object {
        internal fun capture(batch: UploadBatch,now: Long): QueueSnapshot {
            require(now >= 0 && batch.valid())
            return QueueSnapshot(batch,0,Phase.READY,"CAPTURED",0,null,now,null,null,false)
        }
    }
}
sealed class QueueAction {
    data object SendOriginal: QueueAction()
    data class Response(val attempt: Attempt,val body: Map<String,Any?>): QueueAction()
    data class Failure(val attempt: Attempt,val httpStatus: Int?,val retryAfterMs: Long? = null): QueueAction()
    data object Timeout: QueueAction()
    data object Restore: QueueAction()
    data object FinalizeAcknowledgement: QueueAction()
    data object ResumeAfterAuthorization: QueueAction()
}
sealed class QueueEffect {
    data object None: QueueEffect()
    /** May be emitted only following COMMITTED reservation; transport must recheck the authority fence. */
    data class UploadOriginal internal constructor(val attempt: Attempt,val batch: UploadBatch): QueueEffect()
}
data class QueuePlan internal constructor(val next: QueueSnapshot,val effect: QueueEffect,val decision: String)
class QueueMachine(private val classifier: MessageClassifier,val limits: RetryLimits = RetryLimits()) {
    fun admits(batch: UploadBatch): Boolean = batch.valid() && batch.originals.all {
        it.eligible() && classifier.classify(it.assembly) == it.classification
    }
    fun transition(s: QueueSnapshot,action: QueueAction,current: Authority,now: Long): QueuePlan {
        fun same(reason: String) = QueuePlan(s,QueueEffect.None,reason)
        fun next(value: QueueSnapshot,reason: String,effect: QueueEffect = QueueEffect.None): QueuePlan {
            if (s.revision == Long.MAX_VALUE) return same("REVISION_EXHAUSTED")
            check(value.valid()) { "Invalid policy transition" }
            return QueuePlan(value,effect,reason)
        }
        if (!s.valid()) return same("CORRUPT_SNAPSHOT")
        if (now < s.lastObservedAt || now < 0) return same("CLOCK_ROLLBACK")
        if (!current.scope.valid() || current.scope != s.batch.scope) return same("OWNER_SCOPE_CHANGED")
        if (current.binding != s.batch.binding || !current.binding.valid()) return same("BINDING_CHANGED")
        if (current.sessionEpoch <= 0) return same("SESSION_REQUIRED")
        fun fenced(a: Attempt) = s.activeAttempt == a && a.sessionEpoch == current.sessionEpoch
        fun retry(reason: String,serverDelay: Long? = null): QueuePlan {
            val first = s.firstAttemptAt ?: return same("ATTEMPT_REQUIRED")
            return when (val d = RetryPolicy.schedule(s.attempts,now,first,limits,serverDelay)) {
                is RetryDecision.Hold -> next(s.evolve(phase=Phase.HELD,reason=d.reason,notBefore=null,
                    lastObservedAt=now,outcomeUncertain=true),d.reason)
                is RetryDecision.Wait -> next(s.evolve(phase=Phase.RETRY_WAIT,reason=reason,notBefore=d.at,
                    lastObservedAt=now,outcomeUncertain=true),reason)
            }
        }
        return when (action) {
            QueueAction.SendOriginal -> {
                if (s.phase !in setOf(Phase.READY,Phase.RETRY_WAIT)) return same("NOT_DISPATCHABLE")
                if (!current.enabled) return same("PAUSED")
                if (!current.online) return same("OFFLINE")
                for (o in s.batch.originals) {
                    val route = SimPolicy.route(current.binding,o.assembly.input.parts.firstOrNull()?.subscriptionId,current.sim)
                    if (route != Route.ACCEPT) return same(route.name)
                }
                if (!admits(s.batch)) return same("CLASSIFICATION_CHANGED_OR_UNSUPPORTED")
                if (s.notBefore != null && now < s.notBefore) return same("BACKOFF")
                if (s.attempts >= limits.maxAttempts) return next(s.evolve(phase=Phase.HELD,reason="RETRY_LIMIT",notBefore=null,lastObservedAt=now),"RETRY_LIMIT")
                if (s.firstAttemptAt != null && now-s.firstAttemptAt >= limits.maxElapsedMs)
                    return next(s.evolve(phase=Phase.HELD,reason="RETRY_AGE_LIMIT",notBefore=null,lastObservedAt=now),"RETRY_AGE_LIMIT")
                if (now > Long.MAX_VALUE-limits.leaseMs) return same("CLOCK_OVERFLOW")
                val a = Attempt(s.batch.key,s.batch.operationId,s.batch.payloadHash,s.attempts+1,current.sessionEpoch,now)
                next(s.evolve(phase=Phase.IN_FLIGHT,reason="ORIGINAL_RESERVED",attempts=s.attempts+1,
                    firstAttemptAt=s.firstAttemptAt ?: now,lastObservedAt=now,notBefore=null,activeAttempt=a),
                    "ORIGINAL_RESERVED",QueueEffect.UploadOriginal(a,s.batch))
            }
            is QueueAction.Response -> {
                if (!fenced(action.attempt)) return same("STALE_RESPONSE")
                if (s.phase == Phase.CONFLICT) return same("CONFLICT_RETAINED")
                val parsed = AckPolicy.validate(action.body,s.batch)
                if (parsed is AckDecision.Invalid) {
                    if (s.receipts.isNotEmpty() || s.phase != Phase.IN_FLIGHT) return same("INVALID_ACK_RETAINED")
                    return retry("ACK_UNCERTAIN_${parsed.reason}")
                }
                val receipts = (parsed as AckDecision.Valid).receipts
                if (s.receipts.isNotEmpty()) {
                    if (s.receipts == receipts) return same("ACK_REPLAY")
                    return next(s.evolve(phase=Phase.CONFLICT,reason="CONFLICTING_ACK",notBefore=null,
                        lastObservedAt=now,conflictingReceipts=receipts),"CONFLICTING_ACK")
                }
                // A matching late final-attempt receipt can settle exhaustion; obsolete attempts cannot.
                next(s.evolve(phase=Phase.ACK_PENDING,reason="ACK_VALIDATED",receipts=receipts,notBefore=null,
                    lastObservedAt=now,outcomeUncertain=false),"ACK_VALIDATED")
            }
            is QueueAction.Failure -> {
                if (!fenced(action.attempt) || s.phase != Phase.IN_FLIGHT) return same("STALE_FAILURE")
                when (action.httpStatus) {
                    401,403 -> next(s.evolve(phase=Phase.HELD,reason="AUTHORIZATION_REQUIRED",notBefore=null,
                        lastObservedAt=now,outcomeUncertain=true),"AUTHORIZATION_REQUIRED")
                    409 -> next(s.evolve(phase=Phase.CONFLICT,reason="SERVER_CONFLICT",notBefore=null,
                        lastObservedAt=now,outcomeUncertain=true),"SERVER_CONFLICT")
                    null,408,429,in 500..599 -> retry("DELIVERY_UNCERTAIN",action.retryAfterMs)
                    else -> next(s.evolve(phase=Phase.HELD,reason="SERVER_RESPONSE_REQUIRES_REVIEW",notBefore=null,
                        lastObservedAt=now,outcomeUncertain=true),"SERVER_RESPONSE_REQUIRES_REVIEW")
                }
            }
            QueueAction.Timeout -> {
                if (s.phase != Phase.IN_FLIGHT) return same("NO_ACTIVE_ATTEMPT")
                if (now-s.activeAttempt!!.startedAt < limits.leaseMs) return same("LEASE_ACTIVE")
                retry("TIMEOUT_UNCERTAIN")
            }
            QueueAction.Restore -> when (s.phase) {
                Phase.IN_FLIGHT -> retry("INTERRUPTED_UNCERTAIN")
                Phase.ACK_PENDING -> same("FINALIZE_ACK_REQUIRED")
                else -> same("RESTORED_WITHOUT_RESET")
            }
            QueueAction.FinalizeAcknowledgement -> {
                if (s.phase != Phase.ACK_PENDING || s.receipts.isEmpty()) return same("NO_STAGED_ACK")
                next(s.evolve(phase=if (s.receipts.all { it.outcome == ReceiptOutcome.RETAINED }) Phase.ACKNOWLEDGED else Phase.REJECTED,
                    reason="ACK_COMMITTED",notBefore=null,lastObservedAt=now),"ACK_COMMITTED")
            }
            QueueAction.ResumeAfterAuthorization -> {
                if (s.phase != Phase.HELD || s.reason != "AUTHORIZATION_REQUIRED") return same("NOT_AUTH_HOLD")
                if (current.sessionEpoch <= (s.activeAttempt?.sessionEpoch ?: 0)) return same("NEW_SESSION_REQUIRED")
                retry("REAUTHORIZED_ORIGINAL_ONLY")
            }
        }
    }
}

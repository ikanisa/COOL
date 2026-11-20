package rw.ikanisa.sms.policy

sealed class StoreRead {
    data class Present(val snapshot: QueueSnapshot): StoreRead()
    data object Missing: StoreRead()
    data object Corrupt: StoreRead()
    data object Unavailable: StoreRead()
}
enum class StoreWrite { COMMITTED, NOT_COMMITTED, UNKNOWN, REVISION_CONFLICT, ORIGINAL_ALREADY_BOUND }
enum class BatchAdmission { NEW, REPLAY, OPERATION_CONFLICT, ORIGINAL_ALREADY_BOUND, CORRUPT_INDEX, INVALID_BATCH }
object BatchAdmissionPolicy {
    fun decide(batch: UploadBatch,retained: List<QueueSnapshot>): BatchAdmission {
        if (!batch.valid()) return BatchAdmission.INVALID_BATCH
        if (retained.any { !it.valid() } || retained.map { it.batch.key }.distinct().size != retained.size) return BatchAdmission.CORRUPT_INDEX
        val allOriginals = retained.flatMap { it.batch.originals }.map { it.key }
        if (allOriginals.toSet().size != allOriginals.size) return BatchAdmission.CORRUPT_INDEX
        retained.find { it.batch.key == batch.key }?.let {
            return if (it.batch.payloadHash == batch.payloadHash) BatchAdmission.REPLAY else BatchAdmission.OPERATION_CONFLICT
        }
        if (batch.originals.any { it.key in allOriginals }) return BatchAdmission.ORIGINAL_ALREADY_BOUND
        return BatchAdmission.NEW
    }
}
/**
 * A native implementation must atomically persist evidence/state/revision and an original->batch
 * uniqueness index. createIfUnbound uses BatchAdmissionPolicy within that transaction, including
 * terminal tombstones. CAS must not mutate the immutable batch. UNKNOWN never means committed.
 * There is intentionally no delete, reset, clear or recreate-corruption operation.
 */
interface QueueStorePort {
    fun read(key: String): StoreRead
    fun createIfUnbound(initial: QueueSnapshot): StoreWrite
    fun compareAndSet(key: String,expectedRevision: Long,next: QueueSnapshot): StoreWrite
}
data class DriverResult(val status: String,val effect: QueueEffect = QueueEffect.None,val snapshot: QueueSnapshot? = null)
object DispatchPolicy {
    /** Recheck immediately before send, under the native adapter's lifecycle/binding fence. */
    fun permitted(effect: QueueEffect.UploadOriginal,snapshot: QueueSnapshot,current: Authority,now: Long): Boolean =
        snapshot.valid() && snapshot.phase == Phase.IN_FLIGHT && snapshot.activeAttempt == effect.attempt &&
        snapshot.batch.payloadHash == effect.batch.payloadHash && snapshot.batch.key == effect.batch.key &&
        current.scope == effect.batch.scope && current.binding == effect.batch.binding &&
        current.sessionEpoch == effect.attempt.sessionEpoch && current.enabled && current.online &&
        now >= snapshot.lastObservedAt && effect.batch.originals.all {
            SimPolicy.route(current.binding,it.assembly.input.parts.firstOrNull()?.subscriptionId,current.sim) == Route.ACCEPT
        }
}
class CommitDriver(private val store: QueueStorePort,private val machine: QueueMachine) {
    private fun read(key: String): StoreRead = try { store.read(key) } catch (_: Exception) { StoreRead.Unavailable }
    private fun write(block: () -> StoreWrite): StoreWrite = try { block() } catch (_: Exception) { StoreWrite.UNKNOWN }
    fun capture(batch: UploadBatch,now: Long): DriverResult {
        if (now < 0 || !machine.admits(batch)) return DriverResult("INPUT_NOT_ELIGIBLE")
        val existing = read(batch.key)
        if (existing is StoreRead.Present) {
            if (!existing.snapshot.valid() || existing.snapshot.batch.key != batch.key) return DriverResult("CORRUPT_STORAGE")
            return DriverResult(if (existing.snapshot.batch.payloadHash == batch.payloadHash) "CAPTURE_ALREADY_RETAINED" else "OPERATION_CONFLICT",snapshot=existing.snapshot)
        }
        if (existing != StoreRead.Missing) return DriverResult("STORAGE_BLOCKED")
        val initial = QueueSnapshot.capture(batch,now)
        return when (write { store.createIfUnbound(initial) }) {
            StoreWrite.COMMITTED -> DriverResult("CAPTURE_COMMITTED",snapshot=initial)
            StoreWrite.NOT_COMMITTED -> DriverResult("CAPTURE_NOT_COMMITTED")
            StoreWrite.UNKNOWN -> DriverResult("CAPTURE_OUTCOME_UNKNOWN")
            StoreWrite.REVISION_CONFLICT -> DriverResult("REVISION_CONFLICT")
            StoreWrite.ORIGINAL_ALREADY_BOUND -> DriverResult("ORIGINAL_ALREADY_BOUND")
        }
    }
    fun advance(key: String,action: QueueAction,authority: Authority,now: Long): DriverResult {
        val read = read(key)
        if (read !is StoreRead.Present) return DriverResult(when (read) {
            StoreRead.Missing -> "MISSING_EVIDENCE"
            StoreRead.Corrupt -> "CORRUPT_STORAGE"
            else -> "STORAGE_BLOCKED"
        })
        val before = read.snapshot
        if (!before.valid() || before.batch.key != key) return DriverResult("CORRUPT_STORAGE")
        val plan = machine.transition(before,action,authority,now)
        if (plan.next === before) return DriverResult(plan.decision,snapshot=before)
        return when (write { store.compareAndSet(key,before.revision,plan.next) }) {
            StoreWrite.COMMITTED -> DriverResult(plan.decision,plan.effect,plan.next)
            StoreWrite.NOT_COMMITTED -> DriverResult("WRITE_NOT_COMMITTED",snapshot=before)
            StoreWrite.UNKNOWN -> DriverResult("WRITE_OUTCOME_UNKNOWN")
            StoreWrite.REVISION_CONFLICT -> DriverResult("REVISION_CONFLICT")
            StoreWrite.ORIGINAL_ALREADY_BOUND -> DriverResult("ORIGINAL_ALREADY_BOUND")
        }
    }
}

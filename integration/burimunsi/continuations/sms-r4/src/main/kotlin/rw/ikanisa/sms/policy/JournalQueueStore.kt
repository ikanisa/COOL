package rw.ikanisa.sms.policy

sealed class JournalRead {
    class Bytes(bytes: ByteArray): JournalRead() {
        private val retained=bytes.copyOf()
        fun copy(): ByteArray=retained.copyOf()
        override fun toString()="JournalBytes(length=${retained.size})"
    }
    data object Missing: JournalRead()
    data object Unavailable: JournalRead()
}
/**
 * Integration contract: atomically compare the SHA-256 of ALL existing bytes and append the record
 * under one exclusive interprocess lock. COMMITTED requires the platform's durable write barrier.
 * Missing/uninitialized storage must NOT be created. Partial/unknown writes are retained; never
 * truncate a torn tail, skip a corrupt record, reset an index, or report UNKNOWN as COMMITTED.
 * The production port must protect confidentiality and bind storage to the installation lifecycle.
 */
interface AppendJournalPort {
    fun read(): JournalRead
    fun append(expectedContentHash: String, record: ByteArray): StoreWrite
}
sealed class JournalInspection {
    data class Ready(val state: JournalState): JournalInspection()
    data class Blocked(val reason: String): JournalInspection()
}

/** QueueStorePort implementation: indexes are derived from the same committed log as the evidence. */
class JournalQueueStore(private val port: AppendJournalPort, private val scope: OwnerScope): QueueStorePort {
    fun inspect(): JournalInspection = try {
        when(val result=port.read()) {
            is JournalRead.Bytes -> JournalInspection.Ready(JournalFormat.replay(result.copy(),scope))
            JournalRead.Missing -> JournalInspection.Blocked("JOURNAL_MISSING")
            JournalRead.Unavailable -> JournalInspection.Blocked("JOURNAL_UNAVAILABLE")
        }
    } catch(e: SnapshotFormatException) { JournalInspection.Blocked("JOURNAL_${e.code.name}") }
      catch(_: Exception) { JournalInspection.Blocked("JOURNAL_UNAVAILABLE") }

    override fun read(key: String): StoreRead = when(val inspection=inspect()) {
        is JournalInspection.Ready -> inspection.state.snapshots[key]?.let(StoreRead::Present) ?: StoreRead.Missing
        is JournalInspection.Blocked -> if(inspection.reason in setOf("JOURNAL_MISSING","JOURNAL_UNAVAILABLE")) StoreRead.Unavailable else StoreRead.Corrupt
    }
    override fun createIfUnbound(initial: QueueSnapshot): StoreWrite {
        if(!JournalHistory.initial(initial) || initial.batch.scope!=scope) return StoreWrite.NOT_COMMITTED
        val state=(inspect() as? JournalInspection.Ready)?.state ?: return StoreWrite.NOT_COMMITTED
        when(JournalHistory.admission(initial.batch,state.snapshots.values)) {
            BatchAdmission.NEW -> Unit
            BatchAdmission.ORIGINAL_ALREADY_BOUND -> return StoreWrite.ORIGINAL_ALREADY_BOUND
            else -> return StoreWrite.REVISION_CONFLICT
        }
        return append(state,initial)
    }
    override fun compareAndSet(key: String, expectedRevision: Long, next: QueueSnapshot): StoreWrite {
        val state=(inspect() as? JournalInspection.Ready)?.state ?: return StoreWrite.NOT_COMMITTED
        val before=state.snapshots[key] ?: return StoreWrite.REVISION_CONFLICT
        if(next.batch.key!=key || before.revision!=expectedRevision || !JournalHistory.follows(before,next)) return StoreWrite.REVISION_CONFLICT
        return append(state,next)
    }
    private fun append(state: JournalState, next: QueueSnapshot): StoreWrite {
        val frame=try { JournalFormat.record(state,next) } catch(_: SnapshotFormatException) { return StoreWrite.NOT_COMMITTED }
        return try { port.append(state.contentHash,frame) } catch(_: Exception) { StoreWrite.UNKNOWN }
    }
}

/**
 * Additional last-moment gate for R3 callers. The native lifecycle fence MUST cover this check
 * and request submission together; this pure function is neither a mutex nor a single-use token.
 */
object ReservationGate {
    fun permitted(effect: QueueEffect.UploadOriginal, committed: QueueSnapshot, authority: Authority,
                  now: Long, machine: QueueMachine): Boolean {
        val a=effect.attempt
        return SnapshotIntegrity.valid(committed) && machine.admits(committed.batch) &&
            DispatchPolicy.permitted(effect,committed,authority,now) &&
            SnapshotCodec.batchBytes(effect.batch).contentEquals(SnapshotCodec.batchBytes(committed.batch)) &&
            now>=a.startedAt && now-a.startedAt<machine.limits.leaseMs
    }
}

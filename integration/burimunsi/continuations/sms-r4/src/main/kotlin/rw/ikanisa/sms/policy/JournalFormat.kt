package rw.ikanisa.sms.policy

import java.security.MessageDigest
import java.util.Collections

/** Monotone storage history, in addition to each snapshot's structural checks. */
object JournalHistory {
    fun initial(s: QueueSnapshot): Boolean = SnapshotIntegrity.valid(s) && s.revision==0L &&
        s.phase==Phase.READY && s.reason=="CAPTURED" && s.attempts==0 && s.receipts.isEmpty() && s.conflictingReceipts.isEmpty()

    fun follows(old: QueueSnapshot, next: QueueSnapshot): Boolean {
        if (!SnapshotIntegrity.valid(old) || !SnapshotIntegrity.valid(next) || old.revision==Long.MAX_VALUE ||
            next.revision != old.revision+1 || next.lastObservedAt < old.lastObservedAt ||
            !SnapshotCodec.batchBytes(old.batch).contentEquals(SnapshotCodec.batchBytes(next.batch))) return false
        val allowed=when(old.phase) {
            Phase.READY -> setOf(Phase.IN_FLIGHT)
            Phase.IN_FLIGHT -> setOf(Phase.RETRY_WAIT,Phase.HELD,Phase.CONFLICT,Phase.ACK_PENDING)
            Phase.RETRY_WAIT -> setOf(Phase.IN_FLIGHT,Phase.HELD,Phase.ACK_PENDING)
            Phase.HELD -> setOf(Phase.RETRY_WAIT,Phase.HELD,Phase.ACK_PENDING)
            Phase.ACK_PENDING -> setOf(Phase.ACKNOWLEDGED,Phase.REJECTED,Phase.CONFLICT)
            Phase.ACKNOWLEDGED,Phase.REJECTED -> setOf(Phase.CONFLICT)
            Phase.CONFLICT -> emptySet()
        }
        if(next.phase !in allowed) return false
        if(next.phase==Phase.IN_FLIGHT) {
            val a=next.activeAttempt ?: return false
            if(next.attempts!=old.attempts+1 || a.startedAt!=next.lastObservedAt ||
                next.firstAttemptAt != (old.firstAttemptAt ?: a.startedAt)) return false
        } else if(next.attempts!=old.attempts || next.activeAttempt!=old.activeAttempt || next.firstAttemptAt!=old.firstAttemptAt) return false
        if(old.receipts.isNotEmpty() && next.receipts!=old.receipts) return false
        if(old.conflictingReceipts.isNotEmpty() && next.conflictingReceipts!=old.conflictingReceipts) return false
        if(old.outcomeUncertain && next.receipts.isEmpty() && !next.outcomeUncertain) return false
        return true
    }
    /** Atomic admission includes terminal originals and M-Money's separate source/body identity. */
    fun admission(batch: UploadBatch, retained: Collection<QueueSnapshot>): BatchAdmission {
        val base=BatchAdmissionPolicy.decide(batch,retained.toList())
        if(base!=BatchAdmission.NEW) return base
        val seen=retained.flatMap { it.batch.originals }.toMutableList()
        for(o in batch.originals) {
            if(seen.any { it.key==o.key || (o.scope.contract==Contract.MMONEY_LEDGER_V1 &&
                o.scope==it.scope && o.sourceId==it.sourceId && o.body==it.body) }) return BatchAdmission.ORIGINAL_ALREADY_BOUND
            seen+=o
        }
        return BatchAdmission.NEW
    }
}

class JournalState internal constructor(val scope: OwnerScope, val recordCount: Int,
    val tailHash: String, val contentHash: String, snapshots: Map<String,QueueSnapshot>) {
    val snapshots: Map<String,QueueSnapshot> = Collections.unmodifiableMap(LinkedHashMap(snapshots))
    override fun toString() = "JournalState(records=$recordCount,entries=${snapshots.size})"
}

/** Append-only versioned hash chain. Digests detect corruption; they are NOT authentication. */
object JournalFormat {
    const val VERSION=1
    const val HEADER_BYTES=40
    const val MAX_BYTES=64*1024*1024
    const val MAX_RECORDS=10000
    const val MAX_ENTRIES=1000
    private const val MAGIC=0x534d534a // SMSJ
    private fun digest(b: ByteArray)=MessageDigest.getInstance("SHA-256").digest(b)
    private fun hex(b: ByteArray)=b.joinToString("") { "%02x".format(it.toInt() and 255) }
    private fun unhex(s: String): ByteArray {
        requireFormat(s.matches(Regex("[a-f0-9]{64}")))
        return ByteArray(32) { s.substring(it*2,it*2+2).toInt(16).toByte() }
    }
    fun empty(scope: OwnerScope): ByteArray {
        requireFormat(scope.valid(),DecodeCode.SCOPE)
        return BinaryWriter(HEADER_BYTES).also { w -> w.int(MAGIC); w.int(VERSION); w.raw(unhex(EvidenceHash.framed(scope.fields()))) }.result()
    }
    fun replay(bytes: ByteArray, expectedScope: OwnerScope): JournalState {
        requireFormat(bytes.size in HEADER_BYTES..MAX_BYTES,DecodeCode.SIZE)
        val r=BinaryReader(bytes)
        requireFormat(r.int()==MAGIC,DecodeCode.MAGIC); requireFormat(r.int()==VERSION,DecodeCode.VERSION)
        requireFormat(expectedScope.valid() && MessageDigest.isEqual(r.raw(32),unhex(EvidenceHash.framed(expectedScope.fields()))),DecodeCode.SCOPE)
        var tail=digest(bytes.copyOfRange(0,HEADER_BYTES)); var count=0
        val states=LinkedHashMap<String,QueueSnapshot>()
        while(r.remaining>0) {
            requireFormat(++count<=MAX_RECORDS,DecodeCode.SIZE)
            val length=r.count(32+44+32,32+SnapshotCodec.MAX_BYTES+32)
            requireFormat(length<=r.remaining,DecodeCode.TRUNCATED)
            val payload=r.raw(length-32); val check=r.raw(32)
            requireFormat(MessageDigest.isEqual(check,digest(payload)),DecodeCode.CHECKSUM)
            requireFormat(MessageDigest.isEqual(payload.copyOfRange(0,32),tail),DecodeCode.HISTORY)
            val s=SnapshotCodec.decode(payload.copyOfRange(32,payload.size))
            requireFormat(s.batch.scope==expectedScope,DecodeCode.SCOPE)
            val old=states[s.batch.key]
            if(old==null) {
                requireFormat(states.size<MAX_ENTRIES,DecodeCode.SIZE)
                requireFormat(JournalHistory.initial(s) && JournalHistory.admission(s.batch,states.values)==BatchAdmission.NEW,DecodeCode.HISTORY)
            } else requireFormat(JournalHistory.follows(old,s),DecodeCode.HISTORY)
            states[s.batch.key]=s; tail=check
        }
        return JournalState(expectedScope,count,hex(tail),EvidenceHash.sha256(bytes),states)
    }
    fun record(previous: JournalState, next: QueueSnapshot): ByteArray {
        requireFormat(previous.recordCount<MAX_RECORDS,DecodeCode.SIZE)
        requireFormat(next.batch.scope==previous.scope,DecodeCode.SCOPE)
        val old=previous.snapshots[next.batch.key]
        requireFormat(if(old==null) previous.snapshots.size<MAX_ENTRIES && JournalHistory.initial(next) &&
            JournalHistory.admission(next.batch,previous.snapshots.values)==BatchAdmission.NEW else JournalHistory.follows(old,next),DecodeCode.HISTORY)
        val snapshot=SnapshotCodec.encode(next)
        val payload=unhex(previous.tailHash)+snapshot
        return BinaryWriter(payload.size+36).also { it.int(payload.size+32); it.raw(payload); it.raw(digest(payload)) }.result()
    }
}

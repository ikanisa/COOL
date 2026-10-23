package app.cool.mobile.security

import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets

/** Recovery metadata only; this journal never supplies server authority. */
data class ReceiptSmsPendingRecord(val userId: String, val sessionId: String,
    val collectionId: String, val requestId: String, val expectedRevision: Int,
    val expectedDecisionRevision: Long, val optIn: Boolean) {
    init {
        listOf(userId, sessionId, collectionId, requestId).forEach(::validateReceiptSmsUuid)
        require(expectedRevision in 0..999999998)
        require(expectedDecisionRevision in 0..9007199254740990L)
    }
    fun wire(): Map<String, Any> = mapOf("schema_version" to 2, "user_id" to userId,
        "session_id" to sessionId, "collection_id" to collectionId, "request_id" to requestId,
        "expected_revision" to expectedRevision, "expected_decision_revision" to expectedDecisionRevision,
        "opt_in" to optIn)
    companion object {
        fun fromWire(value: Any?): ReceiptSmsPendingRecord {
            val row = value as? Map<*, *> ?: error("Invalid receipt SMS recovery metadata")
            require(row.keys == setOf("schema_version", "user_id", "session_id", "collection_id", "request_id", "expected_revision", "expected_decision_revision", "opt_in"))
            require(row["schema_version"] == 2 || row["schema_version"] == 2L)
            val revision = receiptSmsDecisionHead(row["expected_revision"])
            require(revision <= 999999998L)
            return ReceiptSmsPendingRecord(row["user_id"] as? String ?: error("Invalid recovery owner"),
                row["session_id"] as? String ?: error("Invalid recovery session"),
                row["collection_id"] as? String ?: error("Invalid recovery group"),
                row["request_id"] as? String ?: error("Invalid recovery request"), revision.toInt(),
                receiptSmsDecisionHead(row["expected_decision_revision"], true),
                row["opt_in"] as? Boolean ?: error("Explicit recovery choice required"))
        }
    }
}
fun validateReceiptSmsUuid(value: String) {
    require(Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$").matches(value))
}
fun receiptSmsDecisionHead(value: Any?, expected: Boolean = false): Long {
    require(value is Int || value is Long)
    val number = (value as Number).toLong()
    require(number in 0..(if (expected) 9007199254740990L else 9007199254740991L))
    return number
}
data class ReceiptSmsSuperseded(val request: ReceiptSmsPendingRecord, val observedDecisionRevision: Long) {
    init { require(observedDecisionRevision in 1..9007199254740991L && observedDecisionRevision > request.expectedDecisionRevision) }
    fun wire(): Map<String, Any> = request.wire() + ("superseded_by_decision_revision" to observedDecisionRevision)
}
data class ReceiptSmsRecoveryState(val pending: List<ReceiptSmsPendingRecord> = emptyList(),
    val superseded: List<ReceiptSmsSuperseded> = emptyList()) {
    fun group(collection: String) = ReceiptSmsRecoveryState(pending.filter { it.collectionId == collection }, superseded.filter { it.request.collectionId == collection })
    fun wire(): Map<String, Any> = mapOf("schema_version" to 2,
        "pending" to pending.map { it.wire() }, "superseded" to superseded.map { it.wire() })
}
interface ReceiptSmsPendingCustody {
    fun read(owner: String): ByteArray?
    fun write(owner: String, bytes: ByteArray)
}
object ReceiptSmsPendingCodec {
    const val MAX_RECORDS = 32
    const val ROW_BYTES = 166
    const val MAX_BYTES = 8 + MAX_RECORDS * 2 * ROW_BYTES
    fun validate(owner: String, state: ReceiptSmsRecoveryState) {
        validateReceiptSmsUuid(owner)
        require(state.pending.size <= MAX_RECORDS && state.superseded.size <= MAX_RECORDS)
        val all = state.pending + state.superseded.map { it.request }
        require(all.all { it.userId == owner } && all.map { it.requestId }.distinct().size == all.size)
        require(state.pending.groupBy { it.collectionId to it.sessionId }.values.all { it.size == 1 })
        // Every multi-request group is an explicitly claimed withdrawal cohort.
        // Reserve history space before dispatch, including its newest request.
        val groups = state.pending.groupBy { it.collectionId }.values
        require(groups.all { rows -> rows.count { it.optIn } <= 1 })
        val reserved = groups.filter { it.size > 1 }.sumOf { it.size }
        require(state.superseded.size + reserved <= MAX_RECORDS) { "Receipt SMS recovery history capacity unavailable" }
    }
    fun encode(owner: String, state: ReceiptSmsRecoveryState): ByteArray {
        validate(owner, state)
        val rows = (state.pending.map { Triple(0,it,0L) } + state.superseded.map { Triple(1,it.request,it.observedDecisionRevision) })
            .sortedWith(compareBy({ it.second.collectionId }, { it.first }, { it.second.requestId }))
        val output = ByteBuffer.allocate(8 + rows.size * ROW_BYTES).putInt(0x52534332).putInt(rows.size)
        rows.forEach { (kind, record, head) ->
            output.put(kind.toByte())
            listOf(record.userId,record.sessionId,record.collectionId,record.requestId).forEach { output.put(it.toByteArray(StandardCharsets.US_ASCII)) }
            output.putInt(record.expectedRevision).putLong(record.expectedDecisionRevision)
                .put(if(record.optIn) 1.toByte() else 0.toByte()).putLong(head)
        }
        return output.array()
    }
    fun decode(owner: String, bytes: ByteArray): ReceiptSmsRecoveryState {
        require(bytes.size in 8..MAX_BYTES)
        val input = ByteBuffer.wrap(bytes); require(input.int == 0x52534332)
        val count = input.int; require(count in 0..MAX_RECORDS * 2 && bytes.size == 8 + count * ROW_BYTES)
        fun uuid(): String { val value=ByteArray(36);input.get(value);require(value.all { it.toInt() in 0..127 });return String(value,StandardCharsets.US_ASCII) }
        val pending=mutableListOf<ReceiptSmsPendingRecord>();val history=mutableListOf<ReceiptSmsSuperseded>()
        repeat(count) {
            val kind=input.get().toInt();require(kind==0 || kind==1)
            val user=uuid();val session=uuid();val group=uuid();val request=uuid();val revision=input.int;val decision=input.long
            val choice=input.get().toInt();require(choice==0 || choice==1);val head=input.long
            val row=ReceiptSmsPendingRecord(user,session,group,request,revision,decision,choice==1)
            if(kind==0) { require(head==0L);pending.add(row) } else history.add(ReceiptSmsSuperseded(row,head))
        }
        val state=ReceiptSmsRecoveryState(pending,history)
        require(encode(owner,state).contentEquals(bytes)) { "Noncanonical receipt SMS recovery journal" }
        return state
    }
}
class ReceiptSmsPendingJournal(private val custody: ReceiptSmsPendingCustody) {
    private fun load(owner: String) = custody.read(owner)?.let { ReceiptSmsPendingCodec.decode(owner,it) } ?: ReceiptSmsRecoveryState()
    private fun save(owner: String,state: ReceiptSmsRecoveryState) { custody.write(owner,ReceiptSmsPendingCodec.encode(owner,state)) }
    fun read(owner: String,group: String): ReceiptSmsRecoveryState = synchronized(lock) {
        validateReceiptSmsUuid(owner);validateReceiptSmsUuid(group);load(owner).group(group)
    }
    fun claim(record: ReceiptSmsPendingRecord, withdrawalFence: Boolean = false): ReceiptSmsRecoveryState = synchronized(lock) {
        if(withdrawalFence) require(!record.optIn)
        val state=load(record.userId);val group=state.pending.filter { it.collectionId==record.collectionId }
        if(group.any { it.sessionId==record.sessionId } || !withdrawalFence && group.isNotEmpty()) return@synchronized state.group(record.collectionId)
        if(withdrawalFence) {
            require(!record.optIn && group.isNotEmpty() && group.none { it.sessionId==record.sessionId })
            require(group.all { record.expectedDecisionRevision>=it.expectedDecisionRevision && record.expectedRevision>=it.expectedRevision })
        }
        val next=state.copy(pending=state.pending+record)
        ReceiptSmsPendingCodec.validate(record.userId,next);save(record.userId,next);next.group(record.collectionId)
    }
    fun complete(request: ReceiptSmsPendingRecord, acknowledgedHead: Long): ReceiptSmsRecoveryState = synchronized(lock) {
        require(acknowledgedHead==request.expectedDecisionRevision+1)
        val state=load(request.userId)
        val retained=state.pending.find { it.requestId==request.requestId } ?: state.superseded.find { it.request.requestId==request.requestId }?.request
        if(retained==null) return@synchronized state.group(request.collectionId)
        require(retained==request) { "Receipt SMS acknowledgement custody changed" }
        val fenced=state.pending.filter { it.collectionId==request.collectionId && it.requestId!=request.requestId && it.expectedDecisionRevision<acknowledgedHead }
        val ids=fenced.map { it.requestId }.toSet()+request.requestId
        val next=ReceiptSmsRecoveryState(state.pending.filterNot { it.requestId in ids },
            state.superseded.filterNot { it.request.requestId==request.requestId } + fenced.map { ReceiptSmsSuperseded(it,acknowledgedHead) })
        ReceiptSmsPendingCodec.validate(request.userId,next);save(request.userId,next);next.group(request.collectionId)
    }
    fun supersede(owner: String,group: String,known: List<ReceiptSmsPendingRecord>,observedHead: Long): ReceiptSmsRecoveryState = synchronized(lock) {
        validateReceiptSmsUuid(owner);validateReceiptSmsUuid(group)
        require(observedHead in 1..9007199254740991L && known.size in 1..32 && known.map { it.requestId }.distinct().size==known.size)
        require(known.all { it.userId==owner && it.collectionId==group })
        val state=load(owner);val actual=state.pending.filter { it.collectionId==group };val expected=known.associateBy { it.requestId }
        // Another instance may legitimately ACK/remove a known request. Never
        // overwrite an unobserved active request or trust changed known bodies.
        require(actual.all { expected[it.requestId]==it }) { "Receipt SMS recovery cohort changed" }
        val retained=(state.pending+state.superseded.map { it.request }).associateBy { it.requestId }
        known.forEach { row ->
            require(retained[row.requestId]==null || retained[row.requestId]==row) { "Receipt SMS recovery metadata changed" }
            require(retained[row.requestId]!=null || row.expectedDecisionRevision<observedHead) { "Missing request is not fenced" }
        }
        val fenced=known.filter { it.expectedDecisionRevision<observedHead };require(fenced.isNotEmpty())
        val ids=fenced.map { it.requestId }.toSet();val historyIds=state.superseded.map { it.request.requestId }.toSet()
        val next=ReceiptSmsRecoveryState(state.pending.filterNot { it.requestId in ids },
            state.superseded+fenced.filterNot { it.requestId in historyIds }.map { ReceiptSmsSuperseded(it,observedHead) })
        ReceiptSmsPendingCodec.validate(owner,next);save(owner,next);next.group(group)
    }
    companion object { private val lock=Any() }
}

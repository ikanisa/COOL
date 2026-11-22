package rw.ikanisa.burimunsi.core

/** Scope is retained alongside the source so another account cannot adopt it. */
data class ObservationOwner(val collectionId:String,val accountId:String) {
    fun valid()=runCatching{Values.id(collectionId);Values.id(accountId);true}.getOrDefault(false)
}
/** Process-local fence; no bearer or personal data is stored in a queued item. */
data class ObservationSessionOwner(val owner:ObservationOwner,val generation:Long)
data class ObservationEntry(val owner:ObservationOwner,val sourceKey:String,val observation:SmsObservation) {
    override fun toString()="ObservationEntry(redacted)"
}
data class ObservationSeen(val owner:ObservationOwner,val sourceKey:String,val inboxRowId:Long,val requestId:String,val bodySha256:String,
    val inboxReceivedAt:String?=null) {
    override fun toString()="ObservationSeen(redacted)"
}
data class ObservationJournalState(val pending:List<ObservationEntry>,val seen:List<ObservationSeen>) {
    override fun toString()="ObservationJournalState(redacted)"
}
/** A local preview is never a financial fact and must not enter logs or saved state. */
data class QueuedObservationRow(val id:String,val sender:String,val at:String,val preview:String="") {
    override fun toString()="QueuedObservationRow(redacted)"
}
data class QueuedObservationSnapshot(val session:ObservationSessionOwner,val revision:Long,val items:List<QueuedObservationRow>) {
    override fun toString()="QueuedObservationSnapshot(redacted)"
}
object QueuedObservationPreview {
    private const val MAX_CODE_POINTS=200
    fun from(body:String):String = if(body.codePointCount(0,body.length)<=MAX_CODE_POINTS)body
        else body.substring(0,body.offsetByCodePoints(0,MAX_CODE_POINTS))+"…"
}
data class ObservationPendingSnapshot(val revision:Long,val entries:List<ObservationEntry>) {
    override fun toString()="ObservationPendingSnapshot(redacted)"
}
data class ObservationSeenSnapshot(val revision:Long,val entries:List<ObservationSeen>) {
    override fun toString()="ObservationSeenSnapshot(redacted)"
}
interface ObservationJournalStore {
    fun read():ObservationJournalState
    fun write(value:ObservationJournalState)
    /** Persist a conservative replay hold before a seen identity is evicted. */
    fun protectSeenEviction(value:ObservationSeen):Boolean = false
}
enum class ObservationAppend { STORED, DUPLICATE, FULL }

/** A new provider profile rechecks a bounded recent inbox overlap. */
object ObservationCursor {
    fun start(exactProfileCursor:Long?,latestOwnerCursor:Long):Long {
        checkContract(latestOwnerCursor>=0&&(exactProfileCursor==null||exactProfileCursor>=0),"observation_cursor_unavailable")
        // Even an older, previously used profile cannot resume before retained identities.
        return maxOf(exactProfileCursor?:0L,(latestOwnerCursor-500L).coerceAtLeast(0L))
    }
}
object ObservationSourceIdentity {
    fun inbox(installationId:String,owner:ObservationOwner,rowId:Long,inboxReceivedAt:String?=null):String {
        checkContract(owner.valid()&&rowId>0&&runCatching{Values.requestId(installationId)==installationId}.getOrDefault(false),"invalid_observation_source")
        val received=inboxReceivedAt?.let{runCatching{java.time.Instant.parse(it).toEpochMilli()}.getOrNull()}
        checkContract(inboxReceivedAt==null||received!=null&&received>0,"invalid_observation_source")
        val parts=listOf("observation-inbox-v1",installationId,owner.collectionId,owner.accountId,rowId.toString())+
            if(received==null)emptyList() else listOf(received.toString())
        return Values.sha256(parts.joinToString(""){"${it.length}:$it"})
    }
    /** Opaque, collection-scoped identity for one Android inbox row. Android's
     * signing-key/user/device scoped ID is never sent or retained in plaintext. */
    fun reinstallStable(androidId:String,collectionId:String,rowId:Long,inboxReceivedAt:String):String {
        val id=androidId.lowercase(java.util.Locale.ROOT)
        val received=runCatching{java.time.Instant.parse(inboxReceivedAt).toEpochMilli()}.getOrNull()
        checkContract(Regex("[0-9a-f]{16}").matches(id)&&id!="0000000000000000"&&
            id!="9774d56d682e549c"&&runCatching{Values.id(collectionId)==collectionId}.getOrDefault(false)&&rowId>0&&
            received!=null&&received>0,
            "observation_device_identity_unavailable")
        val parts=listOf("burimunsi-android-inbox-v1",collectionId,id,rowId.toString(),received.toString())
        return Values.sha256(parts.joinToString(""){"${it.length}:$it"})
    }
}

/** The Android adapter provides encrypted, no-backup storage. Never log source bodies. */
class ObservationJournal(private val storage:ObservationJournalStore) {
    companion object { private val lock=Any(); private var revision=0L; private const val MAX_PENDING=256; private const val MAX_OWNER_SEEN=16_000; private const val MAX_SEEN=16_000 }
    // Even an uncertain write invalidates an earlier UI snapshot.
    private fun save(state:ObservationJournalState){try{storage.write(state);checkContract(storage.read()==state,"observation_store_unavailable")}finally{revision++}}
    fun append(owner:ObservationOwner, sourceKey:String, inboxRowId:Long, observation:SmsObservation, profile:ObservationProfile, now:Long):ObservationAppend = synchronized(lock){
        checkContract(owner.valid()&&inboxRowId>0&&Regex("[a-f0-9]{64}").matches(sourceKey)&&observation.sourceMode=="catch_up"&&observation.valid(profile,now),"invalid_observation")
        val state=storage.read()
        val prior=state.seen.firstOrNull{it.owner==owner&&it.sourceKey==sourceKey}
        if(prior!=null){
            checkContract(prior.inboxRowId==inboxRowId&&prior.bodySha256==Values.sha256(observation.rawBody),"observation_source_conflict")
            return@synchronized ObservationAppend.DUPLICATE
        }
        // A changed installation identity must not create a second identity for the same stored row.
        checkContract(state.seen.none{it.owner==owner&&it.inboxRowId==inboxRowId&&
            (it.inboxReceivedAt==null||it.inboxReceivedAt==observation.inboxReceivedAt)},"observation_source_conflict")
        checkContract(state.seen.none{it.requestId==observation.requestId},"observation_request_conflict")
        if(state.pending.size>=MAX_PENDING)return@synchronized ObservationAppend.FULL
        val entry=ObservationEntry(owner,sourceKey,observation)
        val seen=state.seen+ObservationSeen(owner,sourceKey,inboxRowId,observation.requestId,Values.sha256(observation.rawBody),observation.inboxReceivedAt)
        // Keep all pending identities and each owner's entire replay horizon.
        val pending=state.pending+entry
        val pendingIds=pending.map{it.observation.requestId}.toSet()
        val trim=seen.toMutableList()
        val latestByOwner=trim.groupBy{it.owner}.mapValues{(_,items)->items.maxOf{it.inboxRowId}}
        fun evictable(item:ObservationSeen):Boolean {
            val latest=latestByOwner[item.owner]?:return false
            return item.requestId !in pendingIds&&item.inboxRowId<(latest-500L).coerceAtLeast(0L)
        }
        while(trim.count{it.owner==owner}>MAX_OWNER_SEEN||trim.size>MAX_SEEN){
            val index=trim.indexOfFirst{evictable(it)}
            if(index<0)return@synchronized ObservationAppend.FULL
            // A durable hold must survive a crash before the journal drops the
            // identity; an absent marker must never become a new receipt.
            if(!storage.protectSeenEviction(trim[index]))return@synchronized ObservationAppend.FULL
            trim.removeAt(index)
        }
        save(ObservationJournalState(pending,trim));ObservationAppend.STORED
    }
    fun pending(owner:ObservationOwner):List<ObservationEntry> = synchronized(lock){
        checkContract(owner.valid(),"invalid_observation_owner");storage.read().pending.filter{it.owner==owner}
    }
    /** Recover the original durable request identity, including after acknowledgement. */
    fun seen(owner:ObservationOwner,sourceKey:String,rowId:Long,bodySha256:String):ObservationSeen? = synchronized(lock){
        checkContract(owner.valid()&&rowId>0&&Regex("[a-f0-9]{64}").matches(sourceKey)&&Regex("[a-f0-9]{64}").matches(bodySha256),"invalid_observation_source")
        storage.read().seen.singleOrNull{it.owner==owner&&it.sourceKey==sourceKey}?.also{
            checkContract(it.inboxRowId==rowId&&it.bodySha256==bodySha256,"observation_source_conflict")
        }
    }
    fun pendingSnapshot(owner:ObservationOwner):ObservationPendingSnapshot = synchronized(lock){
        checkContract(owner.valid(),"invalid_observation_owner")
        ObservationPendingSnapshot(revision,storage.read().pending.filter{it.owner==owner})
    }
    fun seenSnapshot(owner:ObservationOwner):ObservationSeenSnapshot = synchronized(lock){
        checkContract(owner.valid(),"invalid_observation_owner")
        ObservationSeenSnapshot(revision,storage.read().seen.filter{it.owner==owner})
    }
    /** The callback is short and must not do I/O; callers hold their owner/session fence first. */
    fun <T> ifRevision(expected:Long,action:()->T):T? = synchronized(lock){if(revision==expected)action()else null}
    fun latestSeenRow(owner:ObservationOwner):Long? = synchronized(lock){
        checkContract(owner.valid(),"invalid_observation_owner");storage.read().seen.filter{it.owner==owner}.maxOfOrNull{it.inboxRowId}
    }
    fun acknowledge(owner:ObservationOwner,requestId:String,ack:ObservationAck):Boolean = synchronized(lock){
        checkContract(owner.valid(),"invalid_observation_owner")
        val state=storage.read();val matches=state.pending.filter{it.owner==owner&&it.observation.requestId==requestId}
        if(matches.size!=1||!ObservationAcknowledgement.matches(matches.single().observation,ack))return@synchronized false
        save(state.copy(pending=state.pending.filterNot{it.owner==owner&&it.observation.requestId==requestId}));true
    }
}

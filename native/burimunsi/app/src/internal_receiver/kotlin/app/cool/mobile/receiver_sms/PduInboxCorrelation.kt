package app.cool.mobile.receiver_sms

import rw.ikanisa.burimunsi.core.*
import java.security.MessageDigest
import kotlin.math.abs

/** Separate, non-posting evidence. No correlation outcome identifies a wallet. */
internal data class PduSegmentEvidence(val sender:String,val serviceCentreMs:Long,val decodedBody:String?,val pduHex:String) {
    override fun toString()="PduSegmentEvidence(redacted)"
}
internal data class PduEvidence(val witnessId:String,val owner:ObservationOwner,val installationId:String,val profileFingerprint:String,
    val format:String,val capturedAtMs:Long,val subscriptionId:Int?,val segments:List<PduSegmentEvidence>,
    val bodySha256:String,val pduSha256:String,val structurallyComplete:Boolean) {
    override fun toString()="PduEvidence(redacted)"
}
internal data class InboxEvidence(val requestId:String,val owner:ObservationOwner,val installationId:String,val profileFingerprint:String,
    val sourceKey:String,val rowId:Long,val sender:String,val bodySha256:String,val serviceCentreMs:Long?,val receivedAtMs:Long,
    val subscriptionId:Int?) {
    override fun toString()="InboxEvidence(redacted)"
}
internal data class CorrelationState(val pdus:List<PduEvidence> = emptyList(),val inbox:List<InboxEvidence> = emptyList(),
    val conflictedSources:Set<String> = emptySet(),val conflictedWitnesses:Set<String> = emptySet(),val saturated:Boolean=false)
internal enum class CorrelationStatus { INCOMPLETE, WAITING, AMBIGUOUS, CORRELATED_UNVERIFIED }
internal enum class CorrelationWrite { STORED, DUPLICATE, CONFLICT, FULL }

internal object PduInboxCorrelation {
    private const val MAX_SEGMENTS=16
    private const val MATCH_WINDOW_MS=600_000L
    private val sha=Regex("[a-f0-9]{64}")
    private fun id(value:String)=runCatching{Values.requestId(value)==value}.getOrDefault(false)
    private fun bytes(hex:String):ByteArray? {
        if(hex.isEmpty()||hex.length>1024||hex.length%2!=0||!Regex("[a-f0-9]+").matches(hex))return null
        return ByteArray(hex.length/2){hex.substring(it*2,it*2+2).toInt(16).toByte()}
    }
    private fun digest(pdus:List<ByteArray>):String {
        val d=MessageDigest.getInstance("SHA-256")
        for(pdu in pdus){d.update(byteArrayOf((pdu.size ushr 24).toByte(),(pdu.size ushr 16).toByte(),(pdu.size ushr 8).toByte(),pdu.size.toByte()));d.update(pdu)}
        return d.digest().joinToString(""){"%02x".format(it.toInt() and 255)}
    }
    private fun hex(bytes:ByteArray)=bytes.joinToString(""){"%02x".format(it.toInt() and 255)}
    /** The pinned Collect policy decides structural completeness; it does not authenticate the decoded body. */
    fun capture(witnessId:String,owner:ObservationOwner,installationId:String,profile:ObservationProfile,now:Long,
        subscriptionId:Int?,format:String?,senders:List<String>,times:List<Long>,bodies:List<String?>,pdus:List<ByteArray>):PduEvidence? {
        if(!id(witnessId)||!owner.valid()||!id(installationId)||!profile.current(now)||subscriptionId!=null&&subscriptionId<0||
            pdus.size !in 1..MAX_SEGMENTS||pdus.any{it.isEmpty()||it.size>512}||
            senders.size!=pdus.size||times.size!=pdus.size||bodies.size!=pdus.size)return null
        val assembly=MomoMultipartPolicy.assemble(senders,times,bodies,pdus,format)
        if(!ObservationCandidate.accepts(senders.first(),assembly.body,profile.receipt))return null
        val evidence=PduEvidence(witnessId,owner,installationId,profile.fingerprint(),format?:"unknown",now,subscriptionId,
            pdus.indices.map{i->PduSegmentEvidence(senders[i],times[i],bodies[i],hex(pdus[i]))},
            Values.sha256(assembly.body),digest(pdus),assembly.complete)
        return evidence.takeIf(::valid)
    }
    /** Re-run pinned policy against the exact retained bytes after a reopen. */
    fun valid(value:PduEvidence):Boolean {
        if(!id(value.witnessId)||!id(value.installationId)||!value.owner.valid()||!sha.matches(value.profileFingerprint)||
            value.format !in setOf("3gpp","3gpp2","unknown")||value.capturedAtMs<=0||
            value.subscriptionId!=null&&value.subscriptionId<0||value.segments.size !in 1..MAX_SEGMENTS||
            !sha.matches(value.bodySha256)||!sha.matches(value.pduSha256))return false
        val pdus=value.segments.map{bytes(it.pduHex)?:return false}
        val senders=value.segments.map{it.sender};val times=value.segments.map{it.serviceCentreMs};val bodies=value.segments.map{it.decodedBody}
        if(senders.any{it.length>96}||bodies.any{it!=null&&it.toByteArray(Charsets.UTF_8).size>3000})return false
        val assembly=MomoMultipartPolicy.assemble(senders,times,bodies,pdus,value.format.takeUnless{it=="unknown"})
        return assembly.body.toByteArray(Charsets.UTF_8).size in 1..3000&&
            Values.sha256(assembly.body)==value.bodySha256&&digest(pdus)==value.pduSha256&&assembly.complete==value.structurallyComplete
    }
    fun valid(value:InboxEvidence):Boolean = id(value.requestId)&&value.owner.valid()&&id(value.installationId)&&
        sha.matches(value.profileFingerprint)&&value.rowId>0&&runCatching{
            value.sourceKey==ObservationSourceIdentity.inbox(value.installationId,value.owner,value.rowId,java.time.Instant.ofEpochMilli(value.receivedAtMs).toString())||
            value.sourceKey==ObservationSourceIdentity.inbox(value.installationId,value.owner,value.rowId)
        }.getOrDefault(false)&&
        value.sender.length in 1..96&&sha.matches(value.bodySha256)&&value.receivedAtMs>0&&
        (value.serviceCentreMs==null||value.serviceCentreMs>0)&&(value.subscriptionId==null||value.subscriptionId>=0)
    fun inbox(requestId:String,owner:ObservationOwner,installationId:String,profile:ObservationProfile,now:Long,rowId:Long,
        sender:String,body:String,serviceCentreMs:Long?,receivedAtMs:Long,subscriptionId:Int?):InboxEvidence? {
        if(!profile.current(now)||!ObservationCandidate.accepts(sender,body,profile.receipt))return null
        val value=InboxEvidence(requestId,owner,installationId,profile.fingerprint(),ObservationSourceIdentity.inbox(installationId,owner,rowId,java.time.Instant.ofEpochMilli(receivedAtMs).toString()),
            rowId,sender,Values.sha256(body),serviceCentreMs,receivedAtMs,subscriptionId)
        return value.takeIf(::valid)
    }
    private fun firstPart(value:PduEvidence)=value.segments.firstOrNull()?.let{segment->bytes(segment.pduHex)?.let{MomoMultipartPolicy.part(it,value.format)}}
    private fun samePduIdentity(a:PduEvidence,b:PduEvidence):Boolean {
        if(a.owner!=b.owner||a.installationId!=b.installationId||a.subscriptionId!=b.subscriptionId||a.format!=b.format||
            a.segments.first().sender!=b.segments.first().sender||a.segments.first().serviceCentreMs!=b.segments.first().serviceCentreMs)return false
        val pa=firstPart(a);val pb=firstPart(b)
        val sameConcat=pa?.reference!=null&&pa.reference==pb?.reference&&pa.referenceBits==pb?.referenceBits
        return sameConcat||a.bodySha256==b.bodySha256||a.pduSha256==b.pduSha256
    }
    /** Per-pass rejection only, built from the store's bounded, validated PDU snapshot.
     * Keep every exact digest key, including incomplete or conflicted witnesses.
     * Deliberately omit the capture-time window: a later PDU with this key can
     * match an earlier row that the snapshot's PDU cannot. A new key is deferred
     * in its entirety until the next pass, so it cannot gain a partial unique match.
     * Live owner/permission/config checks and the atomic exact store match remain
     * necessary for every potential row. No body or PDU bytes are cached here. */
    class InboxRelevance(pdus:List<PduEvidence>,owner:ObservationOwner,profileFingerprint:String) {
        private data class Key(val sender:String,val serviceCentreMs:Long,val subscriptionId:Int)
        private val hashes=pdus.asSequence().filter{it.owner==owner&&it.profileFingerprint==profileFingerprint}
            .mapNotNull{pdu->val first=pdu.segments.firstOrNull();val sub=pdu.subscriptionId
                if(first==null||first.serviceCentreMs<=0||sub==null)null else
                    Key(first.sender,first.serviceCentreMs,sub) to pdu.bodySha256}
            .groupBy({it.first},{it.second}).mapValues{(_,values)->values.toSet()}
        val empty:Boolean get()=hashes.isEmpty()
        fun mayMatch(sender:String,body:String,serviceCentreMs:Long?,subscriptionId:Int?):Boolean {
            if(serviceCentreMs==null||subscriptionId==null)return false
            val candidates=hashes[Key(sender,serviceCentreMs,subscriptionId)]?:return false
            return Values.sha256(body) in candidates
        }
    }
    fun matches(pdu:PduEvidence,row:InboxEvidence):Boolean {
        val first=pdu.segments.first()
        return pdu.owner==row.owner&&pdu.installationId==row.installationId&&pdu.profileFingerprint==row.profileFingerprint&&
            first.sender==row.sender&&pdu.bodySha256==row.bodySha256&&first.serviceCentreMs>0&&
            row.serviceCentreMs==first.serviceCentreMs&&pdu.subscriptionId!=null&&pdu.subscriptionId==row.subscriptionId&&
            abs(pdu.capturedAtMs-row.receivedAtMs)<=MATCH_WINDOW_MS
    }
    /** A later collision may change a correlation to ambiguous; it never becomes financial proof. */
    fun status(state:CorrelationState,witnessId:String):CorrelationStatus {
        val pdu=state.pdus.singleOrNull{it.witnessId==witnessId}?:return CorrelationStatus.INCOMPLETE
        if(state.saturated)return CorrelationStatus.AMBIGUOUS
        if(!valid(pdu)||!pdu.structurallyComplete||pdu.subscriptionId==null||pdu.segments.first().serviceCentreMs<=0)return CorrelationStatus.INCOMPLETE
        if(witnessId in state.conflictedWitnesses)return CorrelationStatus.AMBIGUOUS
        val rows=state.inbox.filter{matches(pdu,it)}
        val collision=state.pdus.any{it.witnessId!=pdu.witnessId&&samePduIdentity(pdu,it)}
        if(collision||rows.size>1||rows.any{it.sourceKey in state.conflictedSources})return CorrelationStatus.AMBIGUOUS
        return if(rows.isEmpty())CorrelationStatus.WAITING else CorrelationStatus.CORRELATED_UNVERIFIED
    }
}

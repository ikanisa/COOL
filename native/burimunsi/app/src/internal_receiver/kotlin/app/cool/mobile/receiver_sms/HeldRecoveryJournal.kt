package app.cool.mobile.receiver_sms

import android.content.Context
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.core.HeldObservationAck
import rw.ikanisa.burimunsi.core.ObservationAcknowledgement
import rw.ikanisa.burimunsi.core.SmsObservation
import rw.ikanisa.burimunsi.core.Values
import rw.ikanisa.burimunsi.core.checkContract
import rw.ikanisa.burimunsi.storage.SecureStore
import java.time.Instant
import java.util.UUID

/** One encrypted, durable request per held inbox identity. This journal does
 * not grant capture authority: its caller must recheck the current owner,
 * permission, consent, inbox row and Cloud reconciliation before dispatch. */
internal class HeldRecoveryJournal(context:Context,private val owner:ObservationOwner,
    private val installation:String,private val deviceScope:String) {
    companion object { private val lock=Any() }
    internal enum class Phase { PREPARED, ATTEMPTING, CONFIRMED, MATCHED_EXISTING }
    internal data class Entry(val rowId:Long,val observation:SmsObservation,val phase:Phase,val sourceId:String?=null) {
        override fun toString()="HeldRecoveryJournal.Entry(redacted)"
    }
    private val app=context.applicationContext
    private fun exact(value:JSONObject,keys:Set<String>)=checkContract(value.keys().asSequence().toSet()==keys,"observation_store_unavailable")
    private fun store(key:String):SecureStore {
        checkContract(owner.valid()&&runCatching{Values.requestId(installation)==installation}.getOrDefault(false)&&
            Regex("[a-f0-9]{64}").matches(deviceScope)&&Regex("[a-f0-9]{64}").matches(key),"observation_store_unavailable")
        val name=Values.sha256(listOf("held-recovery-v1",owner.collectionId,owner.accountId,installation,deviceScope,key)
            .joinToString(""){"${it.length}:$it"})
        return SecureStore(app,"observation-held-recovery-$name")
    }
    private fun encode(entry:Entry):String {
        val o=entry.observation
        return JSONObject().put("version",1).put("collectionId",owner.collectionId).put("accountId",owner.accountId)
            .put("installationId",installation).put("deviceScope",deviceScope).put("rowId",entry.rowId)
            .put("phase",entry.phase.name).put("requestId",o.requestId).put("rawSender",o.rawSender).put("rawBody",o.rawBody)
            .put("sourceMode",o.sourceMode).put("complete",o.complete).put("capturedAt",o.capturedAt)
            .put("serviceCentreAt",o.serviceCentreAt?:JSONObject.NULL).put("inboxReceivedAt",o.inboxReceivedAt?:JSONObject.NULL)
            .put("subscriptionId",o.subscriptionId?:JSONObject.NULL).put("sourceKey",o.sourceKey?:JSONObject.NULL)
            .also{if(entry.sourceId!=null)it.put("terminalSourceId",entry.sourceId)}.toString()
    }
    private fun decode(text:String,key:String):Entry {
        val v=JSONObject(text)
        val base=setOf("version","collectionId","accountId","installationId","deviceScope","rowId","phase","requestId",
            "rawSender","rawBody","sourceMode","complete","capturedAt","serviceCentreAt","inboxReceivedAt","subscriptionId","sourceKey")
        checkContract(v.keys().asSequence().toSet() in setOf(base,base+"terminalSourceId"),"observation_store_unavailable")
        checkContract(v.getInt("version")==1&&v.getString("collectionId")==owner.collectionId&&v.getString("accountId")==owner.accountId&&
            v.getString("installationId")==installation&&v.getString("deviceScope")==deviceScope&&v.getString("sourceKey")==key,
            "observation_store_unavailable")
        val phase=runCatching{Phase.valueOf(v.getString("phase"))}.getOrNull()
        val value=SmsObservation(v.getString("requestId"),v.getString("rawSender"),v.getString("rawBody"),v.getString("sourceMode"),
            v.getBoolean("complete"),v.getString("capturedAt"),if(v.isNull("serviceCentreAt"))null else v.getString("serviceCentreAt"),
            if(v.isNull("inboxReceivedAt"))null else v.getString("inboxReceivedAt"),
            if(v.isNull("subscriptionId"))null else v.getInt("subscriptionId"),v.getString("sourceKey"))
        val source=if(v.has("terminalSourceId"))v.getString("terminalSourceId")else null
        checkContract(phase!=null&&(phase in setOf(Phase.CONFIRMED,Phase.MATCHED_EXISTING))==(source!=null)&&
            (source==null||runCatching{Values.id(source)==source}.getOrDefault(false))&&v.getLong("rowId")>0&&runCatching{Values.requestId(value.requestId)==value.requestId}.getOrDefault(false)&&
            value.sourceMode=="catch_up"&&!value.complete&&value.rawSender.length in 1..96&&value.rawSender==value.rawSender.trim()&&
            value.rawBody.toByteArray(Charsets.UTF_8).size in 1..3000&&value.inboxReceivedAt!=null&&
            (value.subscriptionId?.let{it>=0}!=false)&&listOf(value.capturedAt,value.serviceCentreAt,value.inboxReceivedAt)
                .filterNotNull().all{runCatching{Instant.parse(it);true}.getOrDefault(false)},"observation_store_unavailable")
        return Entry(v.getLong("rowId"),value,phase!!,source)
    }
    private fun read(key:String):Entry?=store(key).read()?.let{decode(it,key)}
    fun pending(key:String):Entry?=synchronized(lock){read(key)}

    /** Returns the original immutable request on every retry. A changed inbox
     * row cannot overwrite a request whose network outcome may be unknown. */
    fun prepare(rowId:Long,key:String,sender:String,body:String,receivedAt:String,sentAt:String?,subscriptionId:Int?,now:Long):Entry? = synchronized(lock){
        val existing=read(key)
        if(existing!=null){val o=existing.observation
            return@synchronized existing.takeIf{it.rowId==rowId&&o.sourceKey==key&&o.rawSender==sender&&o.rawBody==body&&
                o.inboxReceivedAt==receivedAt&&o.serviceCentreAt==sentAt&&o.subscriptionId==subscriptionId}
        }
        if(rowId<=0||now<=0)return@synchronized null
        val value=SmsObservation(UUID.randomUUID().toString(),sender,body,"catch_up",false,Instant.ofEpochMilli(now).toString(),
            sentAt,receivedAt,subscriptionId,key)
        val proposed=Entry(rowId,value,Phase.PREPARED)
        val encoded=encode(proposed)
        if(runCatching{decode(encoded,key)}.getOrNull()!=proposed)return@synchronized null
        val target=store(key);target.write(encoded)
        read(key)?.takeIf{it==proposed}
    }
    /** Persist uncertainty before starting the remote call. */
    fun begin(entry:Entry):Entry?=synchronized(lock){
        val key=entry.observation.sourceKey?:return@synchronized null
        val current=read(key)?:return@synchronized null
        if(current!=entry)return@synchronized null
        if(current.phase==Phase.ATTEMPTING)return@synchronized current
        if(current.phase!=Phase.PREPARED)return@synchronized null
        val next=current.copy(phase=Phase.ATTEMPTING);store(key).write(encode(next))
        read(key)?.takeIf{it==next}
    }
    /** Keep terminal evidence: a later stale/missing read must never mint a new request. */
    fun confirm(entry:Entry,ack:HeldObservationAck):Entry?=synchronized(lock){
        val key=entry.observation.sourceKey?:return@synchronized null
        if(entry.phase!=Phase.ATTEMPTING||read(key)!=entry||ack.autoProcessing!="held"||
            !ObservationAcknowledgement.matches(entry.observation,ack.observation))return@synchronized null
        val next=entry.copy(phase=Phase.CONFIRMED,sourceId=ack.observation.sourceId)
        store(key).write(encode(next));read(key)?.takeIf{it==next}
    }
    fun markExisting(entry:Entry,sourceId:String):Entry?=synchronized(lock){
        val key=entry.observation.sourceKey?:return@synchronized null
        if(entry.phase!=Phase.PREPARED||read(key)!=entry||!runCatching{Values.id(sourceId)==sourceId}.getOrDefault(false))return@synchronized null
        val next=entry.copy(phase=Phase.MATCHED_EXISTING,sourceId=sourceId)
        store(key).write(encode(next));read(key)?.takeIf{it==next}
    }
    /** A never-dispatched request can be cleared only by an explicitly validated caller. */
    fun clear(entry:Entry):Boolean=synchronized(lock){
        val key=entry.observation.sourceKey?:return@synchronized false
        if(entry.phase!=Phase.PREPARED||read(key)!=entry)return@synchronized false
        val target=store(key);target.clear();target.read()==null
    }
}

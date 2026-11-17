package app.cool.mobile.receiver_sms

import android.content.Context
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.HeldObservationAck
import rw.ikanisa.burimunsi.core.HeldRecoveryResolution
import rw.ikanisa.burimunsi.core.ObservationAcknowledgement
import rw.ikanisa.burimunsi.core.ObservationConsentState
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.core.SmsObservation
import rw.ikanisa.burimunsi.core.Values
import rw.ikanisa.burimunsi.core.checkContract
import rw.ikanisa.burimunsi.storage.SecureStore
import java.time.Instant
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/** The store name and its authenticated encryption bind every record to its
 * owner, installation, device and source. Only uncertain requests retain SMS
 * text; terminal records retain an opaque row digest and source identity. */
internal class HeldRecoveryJournal(context:Context,private val owner:ObservationOwner,
    private val installation:String,private val deviceScope:String) {
    companion object {
        private val lock=Any()
        private val migrationStarted=AtomicBoolean(false)
        private val fileName=Regex("^buri-(observation-held-recovery-[a-f0-9]{64})\\.v1(?:\\.bak)?$")
        private val hash=Regex("[a-f0-9]{64}")
        private const val MAX_CONSENT_GENERATION=9_007_199_254_740_991L
        private fun name(owner:ObservationOwner,installation:String,deviceScope:String,key:String):String {
            checkContract(owner.valid()&&runCatching{Values.requestId(installation)==installation}.getOrDefault(false)&&
                hash.matches(deviceScope)&&hash.matches(key),"observation_store_unavailable")
            return "observation-held-recovery-"+Values.sha256(listOf("held-recovery-v1",owner.collectionId,owner.accountId,
                installation,deviceScope,key).joinToString(""){"${it.length}:$it"})
        }
        /** Remove old terminal bodies even if the inbox row, session or SMS permission
         * has gone away. Corrupt, foreign-named and unresolved records are untouched. */
        internal fun migrateLegacyFiles(context:Context,files:Collection<String>):Boolean=synchronized(lock){
            var complete=true
            for(storeName in files.mapNotNull{fileName.matchEntire(it)?.groupValues?.get(1)}.toSet()){
                try{
                    val raw=SecureStore(context.applicationContext,storeName).read()?:continue
                    val value=JSONObject(raw)
                    if(value.optInt("version",-1)!=1||value.optString("phase") !in setOf("CONFIRMED","MATCHED_EXISTING"))continue
                    val owner=ObservationOwner(value.getString("collectionId"),value.getString("accountId"))
                    val installation=value.getString("installationId");val device=value.getString("deviceScope")
                    val key=value.getString("sourceKey")
                    if(name(owner,installation,device,key)!=storeName){complete=false;continue}
                    HeldRecoveryJournal(context,owner,installation,device).read(key)
                }catch(_:Exception){complete=false /* Preserve invalid or unavailable records. */}
            }
            complete
        }
        /** Local privacy maintenance is independent of capture authority and does
         * not read the inbox, contact the server, or clear an uncertain request. */
        internal fun migrateLegacyAsync(context:Context,
            listFiles:()->List<String>?={context.applicationContext.noBackupFilesDir.list()?.toList()},
            wait:(Long)->Unit={Thread.sleep(it)},finished:(Boolean)->Unit={}){
            if(!migrationStarted.compareAndSet(false,true))return
            val app=context.applicationContext
            try{Thread({
                var complete=false
                try{
                    for(attempt in 0..2){
                        complete=try{listFiles()?.let{migrateLegacyFiles(app,it)}==true}catch(_:Exception){false}
                        if(complete)break
                        if(attempt<2)wait(200L*(attempt+1))
                    }
                }catch(_:Exception){/* Keep incomplete files intact. */}
                finally{
                    if(!complete)migrationStarted.set(false)
                    runCatching{finished(complete)}
                }
            },"held-recovery-privacy-migration").start()}
            catch(_:Exception){migrationStarted.set(false)}
        }
    }
    internal enum class Phase { PREPARED, ATTEMPTING, CONFIRMED, MATCHED_EXISTING }
    internal data class Entry(val phase:Phase,val requestId:String,val sourceKey:String,val rowDigest:String,
        val sourceId:String?=null,val rowId:Long?=null,val observation:SmsObservation?=null,
        val consentGeneration:Long?=null) {
        override fun toString()="HeldRecoveryJournal.Entry(redacted)"
    }
    private val app=context.applicationContext
    private fun store(key:String)=SecureStore(app,name(owner,installation,deviceScope,key))
    private fun terminal(phase:Phase)=phase==Phase.CONFIRMED||phase==Phase.MATCHED_EXISTING
    private fun rowDigest(rowId:Long,key:String,sender:String,body:String,received:String,sent:String?,sub:Int?):String {
        val fields=listOf("burimunsi-held-row-v2",rowId.toString(),key,sender,Values.sha256(body),received,
            if(sent==null)"0" else "1$sent",if(sub==null)"0" else "1$sub")
        return Values.sha256(fields.joinToString(""){"${it.length}:$it"})
    }
    private fun entry(rowId:Long,o:SmsObservation,phase:Phase,sourceId:String?=null,consentGeneration:Long?=null):Entry {
        val key=o.sourceKey?:throw IllegalArgumentException("Missing source key")
        val digest=rowDigest(rowId,key,o.rawSender,o.rawBody,o.inboxReceivedAt?:throw IllegalArgumentException("Missing receipt time"),
            o.serviceCentreAt,o.subscriptionId)
        return if(terminal(phase))Entry(phase,o.requestId,key,digest,sourceId)
        else Entry(phase,o.requestId,key,digest,null,rowId,o,consentGeneration)
    }
    private fun generation(consent:ObservationConsentState?):Long? = consent?.takeIf{
        it.confirmed&&it.revision.enabled&&it.revision.generation in 1..MAX_CONSENT_GENERATION
    }?.revision?.generation
    private fun sameConsent(entry:Entry,consent:ObservationConsentState?):Boolean =
        entry.consentGeneration!=null&&generation(consent)==entry.consentGeneration
    private fun encode(value:Entry):String {
        if(terminal(value.phase))return JSONObject().put("version",2).put("phase",value.phase.name)
            .put("requestId",value.requestId).put("sourceId",value.sourceId).put("rowDigest",value.rowDigest).toString()
        val o=value.observation?:throw IllegalArgumentException("Missing uncertain request")
        val consentGeneration=value.consentGeneration?:throw IllegalArgumentException("Missing consent witness")
        checkContract(consentGeneration in 1..MAX_CONSENT_GENERATION,"observation_store_unavailable")
        return JSONObject().put("version",3).put("collectionId",owner.collectionId).put("accountId",owner.accountId)
            .put("installationId",installation).put("deviceScope",deviceScope).put("rowId",value.rowId)
            .put("phase",value.phase.name).put("requestId",o.requestId).put("rawSender",o.rawSender).put("rawBody",o.rawBody)
            .put("sourceMode",o.sourceMode).put("complete",o.complete).put("capturedAt",o.capturedAt)
            .put("serviceCentreAt",o.serviceCentreAt?:JSONObject.NULL).put("inboxReceivedAt",o.inboxReceivedAt?:JSONObject.NULL)
            .put("subscriptionId",o.subscriptionId?:JSONObject.NULL).put("sourceKey",o.sourceKey?:JSONObject.NULL)
            .put("consentGeneration",consentGeneration).toString()
    }
    /** The boolean marks a valid v1 terminal that must be atomically redacted. */
    private fun decode(text:String,key:String):Pair<Entry,Boolean> {
        val v=JSONObject(text);val fields=v.keys().asSequence().toSet();val version=v.getInt("version")
        val phase=runCatching{Phase.valueOf(v.getString("phase"))}.getOrNull()
            ?:throw IllegalArgumentException("Invalid protected journal phase")
        val request=v.getString("requestId")
        checkContract(runCatching{Values.requestId(request)==request}.getOrDefault(false),"observation_store_unavailable")
        if(version==2){
            checkContract(fields==setOf("version","phase","requestId","sourceId","rowDigest")&&terminal(phase),"observation_store_unavailable")
            val source=v.getString("sourceId");val digest=v.getString("rowDigest")
            checkContract(runCatching{Values.id(source)==source}.getOrDefault(false)&&hash.matches(digest),"observation_store_unavailable")
            return Entry(phase,request,key,digest,source) to false
        }
        val base=setOf("version","collectionId","accountId","installationId","deviceScope","rowId","phase","requestId",
            "rawSender","rawBody","sourceMode","complete","capturedAt","serviceCentreAt","inboxReceivedAt","subscriptionId","sourceKey")
        checkContract((version==1&&fields in setOf(base,base+"terminalSourceId")||
            version==3&&fields==base+"consentGeneration"&&!terminal(phase))&&v.getString("collectionId")==owner.collectionId&&
            v.getString("accountId")==owner.accountId&&v.getString("installationId")==installation&&
            v.getString("deviceScope")==deviceScope&&v.getString("sourceKey")==key,"observation_store_unavailable")
        val o=SmsObservation(request,v.getString("rawSender"),v.getString("rawBody"),v.getString("sourceMode"),
            v.getBoolean("complete"),v.getString("capturedAt"),if(v.isNull("serviceCentreAt"))null else v.getString("serviceCentreAt"),
            if(v.isNull("inboxReceivedAt"))null else v.getString("inboxReceivedAt"),
            if(v.isNull("subscriptionId"))null else v.getInt("subscriptionId"),v.getString("sourceKey"))
        val source=if(v.has("terminalSourceId"))v.getString("terminalSourceId")else null
        checkContract(terminal(phase)==(source!=null)&&(source==null||runCatching{Values.id(source)==source}.getOrDefault(false))&&
            v.getLong("rowId")>0&&o.sourceMode=="catch_up"&&!o.complete&&o.rawSender.length in 1..96&&o.rawSender==o.rawSender.trim()&&
            o.rawBody.toByteArray(Charsets.UTF_8).size in 1..3000&&o.inboxReceivedAt!=null&&
            (o.subscriptionId?.let{it>=0}!=false)&&listOf(o.capturedAt,o.serviceCentreAt,o.inboxReceivedAt).filterNotNull()
                .all{runCatching{Instant.parse(it);true}.getOrDefault(false)},"observation_store_unavailable")
        val consentGeneration=if(version==3){
            val value=v.get("consentGeneration")
            val number=when(value){is Int->value.toLong();is Long->value;else->null}
            checkContract(number!=null&&number in 1..MAX_CONSENT_GENERATION,"observation_store_unavailable")
            number
        }else null
        return entry(v.getLong("rowId"),o,phase,source,consentGeneration) to terminal(phase)
    }
    private fun read(key:String):Entry? {
        val target=store(key);val raw=target.read()?:return null;val (value,migrate)=decode(raw,key)
        if(migrate){
            val redacted=encode(value);target.write(redacted)
            checkContract(target.read()?.let{decode(it,key)}==(value to false),"observation_store_unavailable")
        }
        return value
    }
    fun pending(key:String):Entry?=synchronized(lock){read(key)}
    /** A row match is identity evidence only, never permission to dispatch. */
    fun matches(entry:Entry,rowId:Long,sender:String,body:String,receivedAt:String,sentAt:String?,subscriptionId:Int?):Boolean=synchronized(lock){
        read(entry.sourceKey)==entry&&entry.rowDigest==rowDigest(rowId,entry.sourceKey,sender,body,receivedAt,sentAt,subscriptionId)
    }
    /** A future retry protocol must still separately validate the current
     * actor, grant, installation, permission, inbox row and server guard. */
    fun consentMatches(entry:Entry,consent:ObservationConsentState?):Boolean=synchronized(lock){
        read(entry.sourceKey)==entry&&sameConsent(entry,consent)
    }

    /** A changed row cannot replace either an uncertain request or its tombstone. */
    fun prepare(rowId:Long,key:String,sender:String,body:String,receivedAt:String,sentAt:String?,subscriptionId:Int?,now:Long,
        consent:ObservationConsentState?=null):Entry? = synchronized(lock){
        val existing=read(key)
        if(existing!=null)return@synchronized existing.takeIf{
            it.rowDigest==rowDigest(rowId,key,sender,body,receivedAt,sentAt,subscriptionId)&&
                (terminal(it.phase)||sameConsent(it,consent))
        }
        val consentGeneration=generation(consent)?:return@synchronized null
        if(rowId<=0||now<=0)return@synchronized null
        val o=SmsObservation(UUID.randomUUID().toString(),sender,body,"catch_up",false,Instant.ofEpochMilli(now).toString(),
            sentAt,receivedAt,subscriptionId,key)
        val proposed=entry(rowId,o,Phase.PREPARED,consentGeneration=consentGeneration);val encoded=encode(proposed)
        if(runCatching{decode(encoded,key)}.getOrNull()!=(proposed to false))return@synchronized null
        store(key).write(encoded);read(key)?.takeIf{it==proposed}
    }
    /** This transition permits only the first dispatch. A persisted ATTEMPTING
     * record is never itself permission to resend, even with unchanged consent. */
    fun begin(entry:Entry,consent:ObservationConsentState?=null):Entry?=synchronized(lock){
        val current=read(entry.sourceKey)?:return@synchronized null
        if(current!=entry||!sameConsent(current,consent))return@synchronized null
        if(current.phase!=Phase.PREPARED)return@synchronized null
        val next=current.copy(phase=Phase.ATTEMPTING);store(entry.sourceKey).write(encode(next))
        read(entry.sourceKey)?.takeIf{it==next}
    }
    fun confirm(entry:Entry,ack:HeldObservationAck,consent:ObservationConsentState?=null):Entry?=synchronized(lock){
        val o=entry.observation?:return@synchronized null
        if(entry.phase!=Phase.ATTEMPTING||read(entry.sourceKey)!=entry||!sameConsent(entry,consent)||ack.autoProcessing!="held"||
            !ObservationAcknowledgement.matches(o,ack.observation))return@synchronized null
        val next=entry.copy(phase=Phase.CONFIRMED,sourceId=ack.observation.sourceId,rowId=null,observation=null,consentGeneration=null)
        store(entry.sourceKey).write(encode(next));read(entry.sourceKey)?.takeIf{it==next}
    }
    /** Legacy v1 attempts have no local consent witness. They may only be
     * redacted after the caller receives an authenticated exact ACK from the
     * server route that proves the original held admission and rechecks its
     * original consent generation against the current consent. This method
     * does not establish transport provenance or authorize a resend. */
    fun confirmReadOnly(entry:Entry,ack:HeldRecoveryResolution,consent:ObservationConsentState?=null):Entry?=synchronized(lock){
        val o=entry.observation?:return@synchronized null
        val consentValid=if(entry.consentGeneration==null)generation(consent)!=null else sameConsent(entry,consent)
        if(entry.phase!=Phase.ATTEMPTING||read(entry.sourceKey)!=entry||!consentValid||!ack.validFor(o)||ack.state!="acknowledged")return@synchronized null
        val next=entry.copy(phase=Phase.CONFIRMED,sourceId=ack.sourceId,rowId=null,observation=null,consentGeneration=null)
        store(entry.sourceKey).write(encode(next));read(entry.sourceKey)?.takeIf{it==next}
    }
    fun markExisting(entry:Entry,sourceId:String,consent:ObservationConsentState?=null):Entry?=synchronized(lock){
        if(entry.phase!=Phase.PREPARED||read(entry.sourceKey)!=entry||!sameConsent(entry,consent)||!runCatching{Values.id(sourceId)==sourceId}.getOrDefault(false))return@synchronized null
        val next=entry.copy(phase=Phase.MATCHED_EXISTING,sourceId=sourceId,rowId=null,observation=null,consentGeneration=null)
        store(entry.sourceKey).write(encode(next));read(entry.sourceKey)?.takeIf{it==next}
    }
    fun clear(entry:Entry):Boolean=synchronized(lock){
        if(entry.phase!=Phase.PREPARED||read(entry.sourceKey)!=entry)return@synchronized false
        val target=store(entry.sourceKey);target.clear();target.read()==null
    }
}

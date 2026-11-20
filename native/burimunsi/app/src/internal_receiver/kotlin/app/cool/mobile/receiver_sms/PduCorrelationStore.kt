package app.cool.mobile.receiver_sms

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.core.checkContract
import rw.ikanisa.burimunsi.storage.SecureStore

/** Keystore-backed, atomic and bounded. This store has no network or posting path. */
internal class PduCorrelationStore(context:Context,private val byteLimit:Int=MAX_BYTES,private val pduLimit:Int=MAX_PDUS,private val rowLimit:Int=MAX_ROWS) {
    private val store=SecureStore(context.applicationContext,"pdu-correlation")
    companion object { private val lock=Any();private const val MAX_PDUS=64;private const val MAX_ROWS=256;private const val MAX_BYTES=1_500_000 }
    init{require(byteLimit in 1..MAX_BYTES&&pduLimit in 1..MAX_PDUS&&rowLimit in 1..MAX_ROWS)}
    private fun exact(v:JSONObject,keys:Set<String>)=checkContract(v.keys().asSequence().toSet()==keys,"correlation_store_unavailable")
    private fun owner(v:JSONObject):ObservationOwner {exact(v,setOf("collectionId","accountId"));return ObservationOwner(v.getString("collectionId"),v.getString("accountId"))}
    private fun ownerJson(v:ObservationOwner)=JSONObject().put("collectionId",v.collectionId).put("accountId",v.accountId)
    private fun nullInt(v:JSONObject,key:String)=if(v.isNull(key))null else v.getInt(key)
    private fun nullLong(v:JSONObject,key:String)=if(v.isNull(key))null else v.getLong(key)
    private fun pdu(v:JSONObject):PduEvidence {
        exact(v,setOf("witnessId","owner","installationId","profileFingerprint","format","capturedAtMs","subscriptionId","segments","bodySha256","pduSha256","structurallyComplete"))
        val parts=v.getJSONArray("segments");checkContract(parts.length() in 1..16,"correlation_store_unavailable")
        val segments=(0 until parts.length()).map{i->val s=parts.getJSONObject(i);exact(s,setOf("sender","serviceCentreMs","decodedBody","pduHex"))
            PduSegmentEvidence(s.getString("sender"),s.getLong("serviceCentreMs"),if(s.isNull("decodedBody"))null else s.getString("decodedBody"),s.getString("pduHex"))}
        return PduEvidence(v.getString("witnessId"),owner(v.getJSONObject("owner")),v.getString("installationId"),v.getString("profileFingerprint"),
            v.getString("format"),v.getLong("capturedAtMs"),nullInt(v,"subscriptionId"),segments,v.getString("bodySha256"),
            v.getString("pduSha256"),v.getBoolean("structurallyComplete")).also{checkContract(PduInboxCorrelation.valid(it),"correlation_store_unavailable")}
    }
    private fun inbox(v:JSONObject):InboxEvidence {
        exact(v,setOf("requestId","owner","installationId","profileFingerprint","sourceKey","rowId","sender","bodySha256","serviceCentreMs","receivedAtMs","subscriptionId"))
        return InboxEvidence(v.getString("requestId"),owner(v.getJSONObject("owner")),v.getString("installationId"),v.getString("profileFingerprint"),
            v.getString("sourceKey"),v.getLong("rowId"),v.getString("sender"),v.getString("bodySha256"),nullLong(v,"serviceCentreMs"),
            v.getLong("receivedAtMs"),nullInt(v,"subscriptionId")).also{checkContract(PduInboxCorrelation.valid(it),"correlation_store_unavailable")}
    }
    private fun readUnlocked():CorrelationState {
        val raw=store.read()?:return CorrelationState();val root=JSONObject(raw);exact(root,setOf("version","pdus","inbox","conflictedSources","conflictedWitnesses","saturated"))
        checkContract(root.getInt("version")==1,"correlation_store_unavailable")
        val p=root.getJSONArray("pdus");val i=root.getJSONArray("inbox");val c=root.getJSONArray("conflictedSources");val w=root.getJSONArray("conflictedWitnesses")
        checkContract(p.length()<=MAX_PDUS&&i.length()<=MAX_ROWS&&c.length()<=MAX_ROWS&&w.length()<=MAX_PDUS,"correlation_store_unavailable")
        val pdus=(0 until p.length()).map{pdu(p.getJSONObject(it))};val inbox=(0 until i.length()).map{inbox(i.getJSONObject(it))}
        val conflicts=(0 until c.length()).map{c.getString(it)};val witnessConflicts=(0 until w.length()).map{w.getString(it)}
        checkContract(pdus.map{it.witnessId}.toSet().size==pdus.size&&inbox.map{it.sourceKey}.toSet().size==inbox.size&&
            inbox.map{it.requestId}.toSet().size==inbox.size&&conflicts.toSet().size==conflicts.size&&
            conflicts.all{Regex("[a-f0-9]{64}").matches(it)}&&witnessConflicts.toSet().size==witnessConflicts.size&&
            witnessConflicts.all{id->pdus.any{it.witnessId==id}},"correlation_store_unavailable")
        checkContract(root.opt("saturated") is Boolean,"correlation_store_unavailable")
        return CorrelationState(pdus,inbox,conflicts.toSet(),witnessConflicts.toSet(),root.getBoolean("saturated"))
    }
    private fun encode(state:CorrelationState):String {
        val pdus=JSONArray();for(v in state.pdus){val segments=JSONArray();for(s in v.segments)segments.put(JSONObject()
            .put("sender",s.sender).put("serviceCentreMs",s.serviceCentreMs).put("decodedBody",s.decodedBody?:JSONObject.NULL).put("pduHex",s.pduHex))
            pdus.put(JSONObject().put("witnessId",v.witnessId).put("owner",ownerJson(v.owner)).put("installationId",v.installationId)
                .put("profileFingerprint",v.profileFingerprint).put("format",v.format).put("capturedAtMs",v.capturedAtMs)
                .put("subscriptionId",v.subscriptionId?:JSONObject.NULL).put("segments",segments).put("bodySha256",v.bodySha256)
                .put("pduSha256",v.pduSha256).put("structurallyComplete",v.structurallyComplete))}
        val inbox=JSONArray();for(v in state.inbox)inbox.put(JSONObject().put("requestId",v.requestId).put("owner",ownerJson(v.owner))
            .put("installationId",v.installationId).put("profileFingerprint",v.profileFingerprint).put("sourceKey",v.sourceKey)
            .put("rowId",v.rowId).put("sender",v.sender).put("bodySha256",v.bodySha256).put("serviceCentreMs",v.serviceCentreMs?:JSONObject.NULL)
            .put("receivedAtMs",v.receivedAtMs).put("subscriptionId",v.subscriptionId?:JSONObject.NULL))
        val conflicts=JSONArray();state.conflictedSources.sorted().forEach(conflicts::put)
        val witnesses=JSONArray();state.conflictedWitnesses.sorted().forEach(witnesses::put)
        return JSONObject().put("version",1).put("pdus",pdus).put("inbox",inbox).put("conflictedSources",conflicts)
            .put("conflictedWitnesses",witnesses).put("saturated",state.saturated).toString()
    }
    private fun writeUnlocked(state:CorrelationState) {
        val encoded=encode(state)
        checkContract(encoded.toByteArray(Charsets.UTF_8).size<=MAX_BYTES,"correlation_store_unavailable")
        store.write(encoded);checkContract(store.read()==encoded,"correlation_store_unavailable")
    }
    /** Fence uncertainty before an append; a failed second write retains the hold. */
    private fun commit(state:CorrelationState,candidate:CorrelationState?):Boolean {
        writeUnlocked(state.copy(saturated=true))
        if(candidate==null||encode(candidate).toByteArray(Charsets.UTF_8).size>byteLimit)return false
        writeUnlocked(candidate.copy(saturated=false));return true
    }
    fun read():CorrelationState=synchronized(lock){readUnlocked()}
    /** Do not retain inbox metadata unless a locally retained PDU can match it. */
    fun recordIfRelevant(value:InboxEvidence):CorrelationWrite?=synchronized(lock){
        checkContract(PduInboxCorrelation.valid(value),"invalid_correlation_evidence")
        val state=readUnlocked()
        if(state.pdus.none{PduInboxCorrelation.matches(it,value)})return@synchronized null
        record(value)
    }
    /** A matching row without a verified journal identity cannot become a unique match. */
    fun holdIfUnretained(value:InboxEvidence):Boolean=synchronized(lock){
        checkContract(PduInboxCorrelation.valid(value),"invalid_correlation_evidence")
        val state=readUnlocked();val affected=state.pdus.filter{PduInboxCorrelation.matches(it,value)}.map{it.witnessId}.toSet()
        if(affected.isEmpty())return@synchronized true
        if(state.saturated)return@synchronized false
        commit(state,state.copy(conflictedWitnesses=state.conflictedWitnesses+affected))
    }
    fun record(value:PduEvidence):CorrelationWrite=synchronized(lock){
        checkContract(PduInboxCorrelation.valid(value),"invalid_correlation_evidence")
        val state=readUnlocked();val prior=state.pdus.find{it.witnessId==value.witnessId}
        if(state.saturated)return@synchronized CorrelationWrite.FULL
        if(prior!=null){
            if(prior==value)return@synchronized CorrelationWrite.DUPLICATE
            return@synchronized if(commit(state,state.copy(conflictedWitnesses=state.conflictedWitnesses+prior.witnessId)))CorrelationWrite.CONFLICT else CorrelationWrite.FULL
        }
        return@synchronized if(commit(state,if(state.pdus.size>=pduLimit)null else state.copy(pdus=state.pdus+value)))CorrelationWrite.STORED else CorrelationWrite.FULL
    }
    fun record(value:InboxEvidence):CorrelationWrite=synchronized(lock){
        checkContract(PduInboxCorrelation.valid(value),"invalid_correlation_evidence")
        val state=readUnlocked();val prior=state.inbox.find{it.sourceKey==value.sourceKey||it.requestId==value.requestId}
        if(state.saturated)return@synchronized CorrelationWrite.FULL
        if(prior!=null){
            if(prior==value)return@synchronized CorrelationWrite.DUPLICATE
            val conflicts=state.conflictedSources+prior.sourceKey+value.sourceKey
            return@synchronized if(commit(state,if(conflicts.size>rowLimit)null else state.copy(conflictedSources=conflicts)))CorrelationWrite.CONFLICT else CorrelationWrite.FULL
        }
        return@synchronized if(commit(state,if(state.inbox.size>=rowLimit)null else state.copy(inbox=state.inbox+value)))CorrelationWrite.STORED else CorrelationWrite.FULL
    }
}

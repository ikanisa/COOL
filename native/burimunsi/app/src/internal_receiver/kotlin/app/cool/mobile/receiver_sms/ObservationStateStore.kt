package app.cool.mobile.receiver_sms

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.system.Os
import android.system.OsConstants
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.*
import java.io.File
import java.security.KeyStore
import java.time.Instant
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/** Independent of the existing gateway queue. Keystore-backed and excluded from backup. */
internal class ObservationStateStore(context:Context):ObservationJournalStore {
    private val app=context.applicationContext
    override fun protectSeenEviction(value:ObservationSeen):Boolean =
        ObservationReplayGuard.protect(app,value.owner,value.inboxRowId)
    private val file=BuriQueueFile(File(app.noBackupFilesDir,"buri-observation-journal.v1"),{directory->
        val fd=Os.open(directory.absolutePath,OsConstants.O_RDONLY,0)
        try{check(OsConstants.S_ISDIR(Os.fstat(fd).st_mode));Os.fsync(fd)}finally{Os.close(fd)}
    })
    private fun key():SecretKey {
        val alias=app.packageName+".burimunsi.observation.v1"
        val keys=KeyStore.getInstance("AndroidKeyStore").apply{load(null)}
        (keys.getKey(alias,null) as? SecretKey)?.let{return it}
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").apply{
            init(KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }
    private fun cipher()=ReceiptCipher({key()},{Base64.encodeToString(it,Base64.NO_WRAP)},{Base64.decode(it,Base64.NO_WRAP)})
    private fun exact(value:JSONObject,keys:Set<String>)=checkContract(value.keys().asSequence().toSet()==keys,"observation_store_unavailable")
    private fun owner(value:JSONObject)=ObservationOwner(value.getString("collectionId"),value.getString("accountId")).also{
        checkContract(it.valid(),"observation_store_unavailable")
    }
    private fun ownerJson(owner:ObservationOwner)=JSONObject().put("collectionId",owner.collectionId).put("accountId",owner.accountId)
    private fun nullableString(value:JSONObject,key:String)=if(value.isNull(key))null else value.getString(key)
    private fun observation(value:JSONObject):SmsObservation {
        val keys=setOf("requestId","rawSender","rawBody","sourceMode","complete","capturedAt","serviceCentreAt","inboxReceivedAt","subscriptionId")
        exact(value,if(value.has("sourceKey"))keys+"sourceKey" else keys)
        val item=SmsObservation(value.getString("requestId"),value.getString("rawSender"),value.getString("rawBody"),
            value.getString("sourceMode"),value.getBoolean("complete"),value.getString("capturedAt"),
            nullableString(value,"serviceCentreAt"),nullableString(value,"inboxReceivedAt"),
            if(value.isNull("subscriptionId"))null else value.getInt("subscriptionId"),
            if(value.has("sourceKey"))value.getString("sourceKey") else null)
        checkContract(runCatching{Values.requestId(item.requestId)==item.requestId}.getOrDefault(false)&&
            item.rawSender.length in 1..96&&item.rawSender==item.rawSender.trim()&&item.rawBody.toByteArray(Charsets.UTF_8).size in 1..3000&&
            ((item.sourceMode=="live"&&item.complete)||(item.sourceMode=="catch_up"&&!item.complete&&item.inboxReceivedAt!=null))&&
            (item.subscriptionId?.let{it>=0}!=false)&&
            (item.sourceKey?.let{key->item.sourceMode=="catch_up"&&Regex("[a-f0-9]{64}").matches(key)}!=false),"observation_store_unavailable")
        for(stamp in listOf(item.capturedAt,item.serviceCentreAt,item.inboxReceivedAt).filterNotNull())
            checkContract(Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]{1,9})?Z").matches(stamp)&&
                runCatching{Instant.parse(stamp);true}.getOrDefault(false),"observation_store_unavailable")
        return item
    }
    private fun observationJson(value:SmsObservation)=JSONObject().put("requestId",value.requestId).put("rawSender",value.rawSender)
        .put("rawBody",value.rawBody).put("sourceMode",value.sourceMode).put("complete",value.complete)
        .put("capturedAt",value.capturedAt).put("serviceCentreAt",value.serviceCentreAt?:JSONObject.NULL)
        .put("inboxReceivedAt",value.inboxReceivedAt?:JSONObject.NULL).put("subscriptionId",value.subscriptionId?:JSONObject.NULL)
        .also{objectValue->value.sourceKey?.let{objectValue.put("sourceKey",it)}}
    override fun read():ObservationJournalState {
        val text=file.read()?.let{cipher().decrypt(it)}?:return ObservationJournalState(emptyList(),emptyList())
        val root=JSONObject(text);exact(root,setOf("version","pending","seen"));checkContract(root.getInt("version")==1,"observation_store_unavailable")
        val pendingJson=root.getJSONArray("pending");val seenJson=root.getJSONArray("seen")
        checkContract(pendingJson.length()<=256&&seenJson.length()<=16_000,"observation_store_unavailable")
        val pending=(0 until pendingJson.length()).map{index->
            val item=pendingJson.getJSONObject(index);exact(item,setOf("owner","sourceKey","observation"))
            val scope=item.getJSONObject("owner");exact(scope,setOf("collectionId","accountId"))
            ObservationEntry(owner(scope),item.getString("sourceKey"),observation(item.getJSONObject("observation")))
        }
        val seen=(0 until seenJson.length()).map{index->
            val item=seenJson.getJSONObject(index);val keys=setOf("owner","sourceKey","inboxRowId","requestId","bodySha256")
            exact(item,if(item.has("inboxReceivedAt"))keys+"inboxReceivedAt" else keys)
            val scope=item.getJSONObject("owner");exact(scope,setOf("collectionId","accountId"))
            ObservationSeen(owner(scope),item.getString("sourceKey"),item.getLong("inboxRowId"),item.getString("requestId"),item.getString("bodySha256"),
                if(item.has("inboxReceivedAt"))item.getString("inboxReceivedAt") else null)
        }
        checkContract(seen.all{it.inboxRowId>0&&Regex("[a-f0-9]{64}").matches(it.sourceKey)&&Regex("[a-f0-9]{64}").matches(it.bodySha256)&&
            runCatching{Values.requestId(it.requestId)==it.requestId}.getOrDefault(false)}&&
            seen.map{Triple(it.owner,it.sourceKey,it.requestId)}.toSet().size==seen.size&&
            seen.map{it.owner to it.sourceKey}.toSet().size==seen.size&&
            seen.map{Triple(it.owner,it.inboxRowId,it.inboxReceivedAt)}.toSet().size==seen.size&&
            seen.groupBy{it.owner to it.inboxRowId}.values.all{items->items.size==1||items.none{it.inboxReceivedAt==null}}&&
            seen.all{it.inboxReceivedAt==null||runCatching{Instant.parse(it.inboxReceivedAt).toEpochMilli()>0}.getOrDefault(false)}&&
            seen.map{it.requestId}.toSet().size==seen.size&&pending.map{it.observation.requestId}.toSet().size==pending.size&&
            pending.all{entry->seen.count{it.owner==entry.owner&&it.sourceKey==entry.sourceKey&&
                it.requestId==entry.observation.requestId&&it.bodySha256==Values.sha256(entry.observation.rawBody)}==1},"observation_store_unavailable")
        return ObservationJournalState(pending,seen)
    }
    override fun write(value:ObservationJournalState) {
        val pending=JSONArray();for(entry in value.pending)pending.put(JSONObject().put("owner",ownerJson(entry.owner))
            .put("sourceKey",entry.sourceKey).put("observation",observationJson(entry.observation)))
        val seen=JSONArray();for(entry in value.seen)seen.put(JSONObject().put("owner",ownerJson(entry.owner))
            .put("sourceKey",entry.sourceKey).put("inboxRowId",entry.inboxRowId).put("requestId",entry.requestId).put("bodySha256",entry.bodySha256)
            .also{objectValue->entry.inboxReceivedAt?.let{objectValue.put("inboxReceivedAt",it)}})
        val encrypted=cipher().encrypt(JSONObject().put("version",1).put("pending",pending).put("seen",seen).toString())
        checkContract(file.write(encrypted),"observation_store_unavailable")
    }
}

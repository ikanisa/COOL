package app.cool.mobile.receiver_sms

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import app.cool.mobile.BuildConfig
import org.json.JSONArray
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.ObservationConsentState
import rw.ikanisa.burimunsi.core.ObservationCursor
import rw.ikanisa.burimunsi.core.ObservationJournal
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.core.ObservationProfile
import rw.ikanisa.burimunsi.core.ObservationSessionOwner
import rw.ikanisa.burimunsi.core.ObservationSourceIdentity
import rw.ikanisa.burimunsi.core.Values
import rw.ikanisa.burimunsi.core.checkContract
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.storage.SecureStore
import java.time.Instant

internal fun observationInboxPermitted(app: Context): Boolean =
    app.checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED &&
        app.checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED

internal fun heldInboxSourceKey(device: String, collection: String, rowId: Long, received: Long): String =
    ObservationSourceIdentity.reinstallStable(device, collection, rowId, Instant.ofEpochMilli(received).toString())

/** Encrypted legacy hold and original cursor compatibility. */
internal class ObservationHeldInbox(
    private val app: Context,
    private val config: ObservationConfigStore,
) {
    private companion object {
        const val MAX_HELD = 20_000
    }

    private val cursorStore = SecureStore(app, "observation-cursors")

    data class PreviousCursor(val profileLastId: Long?, val scanStart: Long)

    private fun legacyStore(collection:String)=SecureStore(app,"observation-legacy-held-"+Values.sha256(collection))
    private fun priorCursorStore(owner:ObservationOwner)=SecureStore(app,"observation-prior-cursor-held-"+
        Values.sha256(listOf(owner.collectionId,owner.accountId).joinToString(""){"${it.length}:$it"}))
    fun legacyExists(collection:String)=legacyStore(collection).read()!=null
    fun deviceId():String?=Settings.Secure.getString(app.contentResolver,Settings.Secure.ANDROID_ID)

    fun holdsExisting(profile: ObservationProfile, collection: String): Boolean =
        BuildConfig.CLOUD_HOLD_EXISTING_INBOX || profile.legacyHold == true || legacyExists(collection)

    fun previousCursor(owner: ObservationOwner, profileFingerprint: String): PreviousCursor {
        checkContract(Regex("[a-f0-9]{64}").matches(profileFingerprint),"observation_cursor_unavailable")
        val root=cursorStore.read()?.let(::JSONObject)?:JSONObject().put("items",JSONArray())
        checkContract(root.keys().asSequence().toSet()==setOf("items"),"observation_cursor_unavailable")
        val rows=root.getJSONArray("items");checkContract(rows.length()<=50,"observation_cursor_unavailable")
        var last:Long?=null;var latest=0L;val seen=mutableSetOf<Pair<ObservationOwner,String>>()
        for(index in 0 until rows.length()){
            val row=rows.getJSONObject(index)
            checkContract(row.keys().asSequence().toSet()==setOf("collectionId","accountId","profileFingerprint","lastId"),"observation_cursor_unavailable")
            val scope=ObservationOwner(row.getString("collectionId"),row.getString("accountId"));val id=row.getLong("lastId");val fingerprint=row.getString("profileFingerprint")
            checkContract(scope.valid()&&Regex("[a-f0-9]{64}").matches(fingerprint)&&seen.add(scope to fingerprint)&&id>=0,"observation_cursor_unavailable")
            if(scope==owner){latest=maxOf(latest,id);if(fingerprint==profileFingerprint)last=id}
        }
        // Include a journal write that survived before its cursor update, even if an
        // older profile has a cursor. Unreadable protected state throws and holds.
        latest=maxOf(latest,ObservationJournal(ObservationStateStore(app)).latestSeenRow(owner)?:0L)
        // Every approved profile reconsiders at most the retained recent overlap.
        return PreviousCursor(last, ObservationCursor.start(last, latest))
    }

    /** The original inbox is held as opaque exact identities. The snapshot is
     * encrypted and never deletes, uploads, or claims a legacy message. */
    fun snapshot(session:ObservationSessionOwner,profile:ObservationProfile,consent:ObservationConsentState,
        control:ObservationConfigStore.Control,stopped:()->Boolean):Pair<String,Set<String>>? {
        val owner=session.owner;val device=deviceId()?:return null
        val deviceScope=Values.sha256(listOf("burimunsi-held-device-v1",owner.collectionId,device.lowercase()).joinToString(""){"${it.length}:$it"})
        // Validate even for an empty inbox: a broken ID must not establish a false baseline.
        heldInboxSourceKey(device,owner.collectionId,1,1)
        // The Cloud application is a separate installation, but the phone inbox
        // can still contain receipts handled by the old installation. Hold the
        // exact existing rows at the first authorized scan even if Cloud has no
        // legacy records. Later insertions remain eligible for normal capture.
        val legacy=holdsExisting(profile, owner.collectionId)
        val store=if(legacy)legacyStore(owner.collectionId)else priorCursorStore(owner)
        val existing=store.read()
        if(existing!=null){
            val value=JSONObject(existing);checkContract(value.keys().asSequence().toSet()==setOf("collectionId","deviceScope","keys")&&
                value.getString("collectionId")==owner.collectionId&&value.getString("deviceScope")==deviceScope,"observation_cursor_unavailable")
            val list=value.getJSONArray("keys");checkContract(list.length()<=MAX_HELD,"observation_cursor_unavailable")
            val keys=(0 until list.length()).map{list.getString(it)}
            checkContract(keys.toSet().size==keys.size&&keys.all{Regex("[a-f0-9]{64}").matches(it)},"observation_cursor_unavailable")
            return device to keys.toSet()
        }
        if(profile.legacyHold==null)return null
        val prior=if(legacy)null else previousCursor(owner, profile.fingerprint()).scanStart
        val ambiguous=if(legacy)emptySet() else ObservationStateStore(app).read().seen
            .filter{it.owner.collectionId==owner.collectionId&&it.inboxReceivedAt==null}.map{it.inboxRowId}.toSet()
        val cursor=try{app.contentResolver.query(Uri.parse("content://sms/inbox"),arrayOf("_id","date"),"_id > ?",arrayOf("0"),"_id ASC")}
            catch(_:Exception){null}?:return null
        val keys=linkedSetOf<String>()
        cursor.use{
            val idCol=it.getColumnIndexOrThrow("_id");val dateCol=it.getColumnIndexOrThrow("date")
            while(it.moveToNext()){
                if(stopped()||!observationInboxPermitted(app)||it.isNull(idCol))return null
                val id=it.getLong(idCol)
                if(prior!=null&&id>prior&&id !in ambiguous)continue
                if(it.isNull(dateCol))return null
                val date=it.getLong(dateCol)
                checkContract(id>0&&date>0&&keys.size<MAX_HELD,"observation_cursor_unavailable")
                checkContract(keys.add(heldInboxSourceKey(device,owner.collectionId,id,date)),"observation_cursor_unavailable")
            }
        }
        val encoded=JSONObject().put("collectionId",owner.collectionId).put("deviceScope",deviceScope)
            .put("keys",JSONArray().also{array->keys.forEach{array.put(it)}}).toString()
        val saved=ObservationLegacyOwnership.withoutControlTransition(app){
            NativeRepository.withObservationOwner(app,session){group,account->
                if(stopped()||!observationInboxPermitted(app)||owner!=ObservationOwner(group,account)||config.controlState(owner)!=control||
                    config.consent(owner)!=consent||!consent.canCapture(observationInboxPermitted(app))||config.profile(owner,System.currentTimeMillis())!=profile||
                    deviceId()!=device||store.read()!=null||(!legacy&&(
                        previousCursor(owner, profile.fingerprint()).scanStart!=prior||ObservationStateStore(app).read().seen
                            .filter{it.owner.collectionId==owner.collectionId&&it.inboxReceivedAt==null}.map{it.inboxRowId}.toSet()!=ambiguous)))false
                else{store.write(encoded);store.read()==encoded}
            }?:false
        }?:false
        return if(saved)device to keys else null
    }
}

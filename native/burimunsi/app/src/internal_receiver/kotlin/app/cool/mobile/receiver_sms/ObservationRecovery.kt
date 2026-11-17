package app.cool.mobile.receiver_sms

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import app.cool.mobile.BuildConfig
import org.json.JSONArray
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.ObservationCursor
import rw.ikanisa.burimunsi.core.ObservationCandidate
import rw.ikanisa.burimunsi.core.ObservationJournal
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.core.ObservationConsentState
import rw.ikanisa.burimunsi.core.ObservationProfile
import rw.ikanisa.burimunsi.core.ObservationReconcileRequest
import rw.ikanisa.burimunsi.core.ObservationReconcileReply
import rw.ikanisa.burimunsi.core.ObservationSessionOwner
import rw.ikanisa.burimunsi.core.ObservationSourceIdentity
import rw.ikanisa.burimunsi.core.ReceiptCandidate
import rw.ikanisa.burimunsi.core.Values
import rw.ikanisa.burimunsi.core.checkContract
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.storage.SecureStore
import java.time.Instant

/** Local inbox catch-up; raw text leaves the cursor only after candidate filtering. */
internal class ObservationRecovery(context:Context) {
    private val app=context.applicationContext
    private val cursorStore=SecureStore(app,"observation-cursors")
    private val config=ObservationConfigStore(app)
    companion object {
        private val lock=Any();private const val PAGE=100;private const val MAX_HELD=20_000;private const val MAX_LATEST_SCAN=20_000
        private var auditProgress:AuditProgress?=null
        private var completedAuditStart:Long?=null
        private var completedAuditRevision:String?=null
    }
    internal enum class Backfill { COMPLETE, MORE, BLOCKED }
    internal enum class Scan { COMPLETE, MORE, BLOCKED }
    internal enum class Audit { COMPLETE, MORE, RETRY, UNCONFIRMED, BLOCKED }
    private data class AuditScope(val session:ObservationSessionOwner,val fingerprint:String,val legacyHold:Boolean?,
        val consent:ObservationConsentState,val control:ObservationConfigStore.Control,val deviceScope:String,val heldScope:String,val revision:Long)
    private data class AuditProgress(val scope:AuditScope,val last:Long,val unconfirmed:Boolean,val startedAt:Long,
        val collectionRevision:String,val recordedCount:Int,
        val sourceIds:Set<String> = emptySet(),val phoneComplete:Boolean=false,val cloudCursor:String?=null,
        val cloudRevision:String?=null,val cloudTotal:Int?=null,val cloudIds:Set<String> = emptySet(),val cursors:Set<String> = emptySet())
    private data class AuditAuthority(val scope:AuditScope,val profile:ObservationProfile,val device:String,val held:Set<String>)
    private class AuditAuthorityChanged:Exception()
    private data class AuditRow(val id:Long,val received:Long,val sender:String,val body:String,val sent:Long?,val sub:Int?){
        override fun toString()="AuditRow(redacted)"
    }
    internal data class LatestWitness(val session:ObservationSessionOwner,val profileFingerprint:String,val legacyHold:Boolean?,
        val consent:ObservationConsentState,val control:ObservationConfigStore.Control,val rowId:Long,val localSourceKey:String,
        val request:ObservationReconcileRequest,val protected:Boolean=false) {
        override fun toString()="LatestWitness(redacted)"
    }
    internal sealed class Latest {
        data class Ready(val witness:LatestWitness):Latest()
        object Held:Latest()
        data class Empty(val session:ObservationSessionOwner,val profileFingerprint:String,val legacyHold:Boolean?,
            val consent:ObservationConsentState,val control:ObservationConfigStore.Control,val deviceScope:String):Latest() {
            override fun toString()="Latest.Empty(redacted)"
        }
        object Blocked:Latest()
    }
    private data class BackfillCursor(val last:Long,val end:Long)
    private fun permitted()=app.checkSelfPermission(Manifest.permission.READ_SMS)==PackageManager.PERMISSION_GRANTED&&
        app.checkSelfPermission(Manifest.permission.RECEIVE_SMS)==PackageManager.PERMISSION_GRANTED
    private fun legacyStore(collection:String)=SecureStore(app,"observation-legacy-held-"+Values.sha256(collection))
    private fun priorCursorStore(owner:ObservationOwner)=SecureStore(app,"observation-prior-cursor-held-"+
        Values.sha256(listOf(owner.collectionId,owner.accountId).joinToString(""){"${it.length}:$it"}))
    private fun rescanStore(owner:ObservationOwner,legacy:Boolean)=SecureStore(app,"observation-bounded-rescan-"+
        Values.sha256(listOf(owner.collectionId,owner.accountId,legacy.toString()).joinToString(""){"${it.length}:$it"}))
    private fun legacyExists(collection:String)=legacyStore(collection).read()!=null
    private fun deviceId():String?=Settings.Secure.getString(app.contentResolver,Settings.Secure.ANDROID_ID)
    private fun stableKey(device:String,collection:String,rowId:Long,received:Long)=
        ObservationSourceIdentity.reinstallStable(device,collection,rowId,Instant.ofEpochMilli(received).toString())

    /** The original inbox is held as opaque exact identities. The snapshot is
     * encrypted and never deletes, uploads, or claims a legacy message. */
    private fun held(session:ObservationSessionOwner,profile:ObservationProfile,consent:ObservationConsentState,
        control:ObservationConfigStore.Control,stopped:()->Boolean):Pair<String,Set<String>>? {
        val owner=session.owner;val device=deviceId()?:return null
        val deviceScope=Values.sha256(listOf("burimunsi-held-device-v1",owner.collectionId,device.lowercase()).joinToString(""){"${it.length}:$it"})
        // Validate even for an empty inbox: a broken ID must not establish a false baseline.
        stableKey(device,owner.collectionId,1,1)
        // The Cloud application is a separate installation, but the phone inbox
        // can still contain receipts handled by the old installation. Hold the
        // exact existing rows at the first authorized scan even if Cloud has no
        // legacy records. Later insertions remain eligible for normal capture.
        val legacy=BuildConfig.CLOUD_HOLD_EXISTING_INBOX||profile.legacyHold==true||legacyExists(owner.collectionId)
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
        val prior=if(legacy)null else read(owner,profile.fingerprint()).second
        val ambiguous=if(legacy)emptySet() else ObservationStateStore(app).read().seen
            .filter{it.owner.collectionId==owner.collectionId&&it.inboxReceivedAt==null}.map{it.inboxRowId}.toSet()
        val cursor=try{app.contentResolver.query(Uri.parse("content://sms/inbox"),arrayOf("_id","date"),"_id > ?",arrayOf("0"),"_id ASC")}
            catch(_:Exception){null}?:return null
        val keys=linkedSetOf<String>()
        cursor.use{
            val idCol=it.getColumnIndexOrThrow("_id");val dateCol=it.getColumnIndexOrThrow("date")
            while(it.moveToNext()){
                if(stopped()||!permitted()||it.isNull(idCol))return null
                val id=it.getLong(idCol)
                if(prior!=null&&id>prior&&id !in ambiguous)continue
                if(it.isNull(dateCol))return null
                val date=it.getLong(dateCol)
                checkContract(id>0&&date>0&&keys.size<MAX_HELD,"observation_cursor_unavailable")
                checkContract(keys.add(stableKey(device,owner.collectionId,id,date)),"observation_cursor_unavailable")
            }
        }
        val encoded=JSONObject().put("collectionId",owner.collectionId).put("deviceScope",deviceScope)
            .put("keys",JSONArray().also{array->keys.forEach{array.put(it)}}).toString()
        val saved=ObservationLegacyOwnership.withoutControlTransition(app){
            NativeRepository.withObservationOwner(app,session){group,account->
                if(stopped()||!permitted()||owner!=ObservationOwner(group,account)||config.controlState(owner)!=control||
                    config.consent(owner)!=consent||!consent.canCapture(permitted())||config.profile(owner,System.currentTimeMillis())!=profile||
                    deviceId()!=device||store.read()!=null||(!legacy&&(
                        read(owner,profile.fingerprint()).second!=prior||ObservationStateStore(app).read().seen
                            .filter{it.owner.collectionId==owner.collectionId&&it.inboxReceivedAt==null}.map{it.inboxRowId}.toSet()!=ambiguous)))false
                else{store.write(encoded);store.read()==encoded}
            }?:false
        }?:false
        return if(saved)device to keys else null
    }

    /** Scan the whole inbox in bounded passes. A later insertion with a reused
     * or lower row ID is considered on the next pass regardless of its date. */
    private fun scanHeld(session:ObservationSessionOwner,profile:ObservationProfile,consent:ObservationConsentState,
        control:ObservationConfigStore.Control,stopped:()->Boolean):Scan {
        val owner=session.owner;val (device,keys)=held(session,profile,consent,control,stopped)?:return Scan.BLOCKED
        val installation=MomoGatewayStore(app).existingInstallationId()?:return Scan.BLOCKED
        val journal=ObservationJournal(ObservationStateStore(app))
        val seen=NativeRepository.withObservationOwner(app,session){_,_->journal.seenSnapshot(owner)}?:return Scan.BLOCKED
        val seenByKey=seen.entries.associateBy{it.sourceKey}
        val revision=ObservationInboxRevision.snapshot();val epoch=ObservationInboxRevision.epoch()
        val scope=Values.sha256(listOf(owner.collectionId,owner.accountId,session.generation.toString(),profile.fingerprint(),
            profile.legacyHold.toString(),consent.revision.enabled.toString(),consent.revision.generation.toString(),
            consent.confirmed.toString(),control.paused.toString(),control.revision.toString(),Values.sha256(device))
            .joinToString(""){"${it.length}:$it"})
        val store=rescanStore(owner,profile.legacyHold==true||legacyExists(owner.collectionId));var stored=store.read()
        val last=stored?.let{raw->
            val v=JSONObject(raw);val fields=v.keys().asSequence().toSet()
            checkContract((fields==setOf("collectionId","accountId","lastId")||
                fields==setOf("collectionId","accountId","lastId","scope","epoch","revision"))&&
                v.getString("collectionId")==owner.collectionId&&v.getString("accountId")==owner.accountId&&v.getLong("lastId")>=0,
                "observation_cursor_unavailable")
            if(fields.size==6&&v.getString("scope")==scope&&v.getString("epoch")==epoch&&v.getLong("revision")==revision)
                v.getLong("lastId") else 0L
        }?:0L
        fun save(expected:Long,next:Long):Boolean=NativeRepository.withObservationOwner(app,session){group,account->
            if(stopped()||!permitted()||owner!=ObservationOwner(group,account)||config.controlState(owner)!=control||
                config.consent(owner)!=consent||!consent.canCapture(permitted())||config.profile(owner,System.currentTimeMillis())!=profile||
                deviceId()!=device||ObservationInboxRevision.snapshot()!=revision)false
            else{
                val current=store.read()
                if(current!=stored)false else{
                    val text=JSONObject().put("collectionId",owner.collectionId).put("accountId",owner.accountId).put("lastId",next)
                        .put("scope",scope).put("epoch",epoch).put("revision",revision).toString()
                    store.write(text);if(store.read()!=text)false else{stored=text;true}
                }
            }
        }?:false
        val base=arrayOf("_id","address","body","date");val uri=Uri.parse("content://sms/inbox")
        val senders=profile.receipt.senders.sorted()
        val filtered=senders.isNotEmpty()&&senders.size<=30&&senders.all{it.isNotEmpty()&&it.all{c->c in ' '..'~'}}
        val plans=if(filtered)listOf(
            ("_id > ? AND (address COLLATE NOCASE IN (${senders.joinToString(","){"?"}}) OR address GLOB '*[^ -~]*')") to
                (arrayOf(last.toString())+senders),
            "_id > ?" to arrayOf(last.toString())
        )else listOf("_id > ?" to arrayOf(last.toString()))
        val cursor=plans.firstNotNullOfOrNull{(selection,args)->
            listOf(base+arrayOf("date_sent","sub_id"),base+"date_sent",base+"sub_id",base)
                .firstNotNullOfOrNull{columns->try{app.contentResolver.query(uri,columns,selection,args,"_id ASC")}
                    catch(_:Exception){null}}
        }?:return Scan.BLOCKED
        var position=last;var count=0
        cursor.use{
            val idCol=it.getColumnIndexOrThrow("_id");val senderCol=it.getColumnIndexOrThrow("address")
            val bodyCol=it.getColumnIndexOrThrow("body");val dateCol=it.getColumnIndexOrThrow("date")
            val sentCol=it.getColumnIndex("date_sent");val subCol=it.getColumnIndex("sub_id")
            while(count<PAGE&&it.moveToNext()){
                if(stopped()||!permitted()||!ObservationLegacyOwnership.controlTransitionClear(app)||it.isNull(idCol)||it.isNull(dateCol))return Scan.BLOCKED
                val id=it.getLong(idCol);val received=it.getLong(dateCol);if(id<=position||received<=0)return Scan.BLOCKED
                val sender=if(it.isNull(senderCol))"" else it.getString(senderCol)
                val body=if(it.isNull(bodyCol))"" else it.getString(bodyCol)
                val sent=if(sentCol<0||it.isNull(sentCol))null else it.getLong(sentCol).takeIf{v->v>0}
                val sub=if(subCol<0||it.isNull(subCol))null else it.getInt(subCol).takeIf{v->v>=0}
                val key=stableKey(device,owner.collectionId,id,received)
                val candidate=ObservationCapture.candidate(app,session,profile.fingerprint(),sender,body)?:return Scan.BLOCKED
                val advanced=if(key in keys||!candidate)ObservationLegacyOwnership.withoutControlTransition(app){save(position,id)}?:false
                else ObservationLegacyOwnership.withDecision(app,owner,id,received,sender,body,sub){decision->
                    val retained=when(decision){
                        // Protected rows are never replayed. The independent
                        // Cloud audit carries their unresolved status forward.
                        ObservationLegacyOwnership.Decision.HOLD->true
                        ObservationLegacyOwnership.Decision.OWNED->{ObservationLegacyOwnership.retained(app,sender,body,sent,received,sub);true}
                        ObservationLegacyOwnership.Decision.UNOWNED->{
                            val receivedAt=Instant.ofEpochMilli(received).toString()
                            val localKey=ObservationSourceIdentity.inbox(installation,owner,id,receivedAt)
                            val existing=seenByKey[localKey]
                            val duplicate=journal.ifRevision(seen.revision){existing!=null&&existing.inboxRowId==id&&
                                existing.bodySha256==Values.sha256(body)}==true
                            if(duplicate)true else{
                                val result=ObservationCapture.retain(app,session,profile.fingerprint(),"inbox:$id",sender,body,"catch_up",false,
                                    sent?.let{v->Instant.ofEpochMilli(v).toString()},receivedAt,sub)
                                result!=ObservationCapture.Result.FULL&&result!=ObservationCapture.Result.UNAVAILABLE
                            }
                        }
                    }
                    retained&&save(position,id)
                }?:false
                if(!advanced)return Scan.BLOCKED
                position=id;count++
            }
        }
        if(count<PAGE){if(ObservationLegacyOwnership.withoutControlTransition(app){save(position,0)}!=true)return Scan.BLOCKED;return Scan.COMPLETE}
        return Scan.MORE
    }
    private fun backfillStore(owner:ObservationOwner,fingerprint:String):SecureStore {
        val key=Values.sha256(listOf(owner.collectionId,owner.accountId,fingerprint).joinToString(""){"${it.length}:$it"})
        return SecureStore(app,"observation-sender-backfill-$key")
    }
    private fun parseBackfill(encoded:String):BackfillCursor {
        val value=JSONObject(encoded)
        checkContract(value.keys().asSequence().toSet()==setOf("version","lastId","endId")&&value.getInt("version")==1,
            "observation_cursor_unavailable")
        val last=value.getLong("lastId");val end=value.getLong("endId")
        checkContract(last>=0&&end>=last,"observation_cursor_unavailable")
        return BackfillCursor(last,end)
    }
    private fun saveBackfill(store:SecureStore,value:BackfillCursor){
        val encoded=JSONObject().put("version",1).put("lastId",value.last).put("endId",value.end).toString()
        store.write(encoded);checkContract(store.read()==encoded,"observation_cursor_unavailable")
    }
    private fun backfillCursor(owner:ObservationOwner,fingerprint:String):BackfillCursor {
        val store=backfillStore(owner,fingerprint)
        store.read()?.let{return parseBackfill(it)}
        // Freeze the pre-upgrade cursor before the new sender-only scanner runs.
        // Rows the old classifier accepted are deliberately skipped during this
        // migration even if their old local deduplication markers were evicted.
        val rows=read(owner,fingerprint).first
        val old=(0 until rows.length()).map{rows.getJSONObject(it)}.firstOrNull{
            it.getString("collectionId")==owner.collectionId&&it.getString("accountId")==owner.accountId&&
                it.getString("profileFingerprint")==fingerprint
        }?.getLong("lastId")?:0L
        return BackfillCursor(0,old).also{saveBackfill(store,it)}
    }
    private fun advanceBackfill(session:ObservationSessionOwner,profile:ObservationProfile,
        consent:ObservationConsentState,control:ObservationConfigStore.Control,expected:BackfillCursor,next:Long):Boolean =
        NativeRepository.withObservationOwner(app,session){group,account->
            val owner=session.owner;val fingerprint=profile.fingerprint()
            if(owner!=ObservationOwner(group,account)||!permitted()||control.paused||config.controlState(owner)!=control||
                config.consent(owner)!=consent||!consent.canCapture(permitted())||
                config.profile(owner,System.currentTimeMillis())?.fingerprint()!=fingerprint)return@withObservationOwner false
            val store=backfillStore(owner,fingerprint)
            if(store.read()?.let(::parseBackfill)!=expected||next<=expected.last||next>expected.end)return@withObservationOwner false
            saveBackfill(store,expected.copy(last=next));true
        }?:false

    /** One-time bounded migration for messages the old incoming-only predicate
     * skipped. It never retries an older accepted receipt with a new request ID. */
    fun backfill(stopped:()->Boolean={false}):Backfill = synchronized(lock){
        if(stopped()||!permitted()||!ObservationLegacyOwnership.controlTransitionClear(app))return@synchronized Backfill.BLOCKED
        val session=NativeRepository.observationOwner(app)?:return@synchronized Backfill.BLOCKED
        val heldMode=try{NativeRepository.withObservationOwner(app,session){group,account->
            val owner=ObservationOwner(group,account);val profile=config.profile(owner,System.currentTimeMillis())
            if(profile?.legacyHold==null)null else BuildConfig.CLOUD_HOLD_EXISTING_INBOX||profile.legacyHold==true||legacyExists(group)
        }}catch(_:Exception){null}?:return@synchronized Backfill.BLOCKED
        if(heldMode)return@synchronized Backfill.COMPLETE
        val initial=try{NativeRepository.withObservationOwner(app,session){group,account->
            val owner=ObservationOwner(group,account);val profile=config.profile(owner,System.currentTimeMillis())
            val control=config.controlState(owner);val consent=config.consent(owner)
            if(control.paused||consent?.canCapture(permitted())!=true||profile==null||profile.legacyHold!=false)null
            else Triple(profile,backfillCursor(owner,profile.fingerprint()),consent to control)
        }}catch(_:Exception){null}?:return@synchronized Backfill.BLOCKED
        val owner=session.owner;val profile=initial.first;val fingerprint=profile.fingerprint();var position=initial.second
        val (consent,control)=initial.third
        if(position.last==position.end)return@synchronized Backfill.COMPLETE
        val base=arrayOf("_id","address","body","date");val uri=Uri.parse("content://sms/inbox")
        val senders=profile.receipt.senders.sorted()
        val filtered=senders.isNotEmpty()&&senders.size<=30&&senders.all{it.isNotEmpty()&&it.all{c->c in ' '..'~'}}
        val bounds=arrayOf(position.last.toString(),position.end.toString())
        val plans=if(filtered)listOf(
            ("_id > ? AND _id <= ? AND (address COLLATE NOCASE IN (${senders.joinToString(","){"?"}}) OR address GLOB '*[^ -~]*')") to (bounds+senders),
            "_id > ? AND _id <= ?" to bounds
        )else listOf("_id > ? AND _id <= ?" to bounds)
        val cursor=plans.firstNotNullOfOrNull{(selection,args)->
            listOf(base+arrayOf("date_sent","sub_id"),base+"date_sent",base+"sub_id",base)
                .firstNotNullOfOrNull{columns->try{app.contentResolver.query(uri,columns,selection,args,"_id ASC")}catch(_:Exception){null}}
        }?:return@synchronized Backfill.BLOCKED
        try{cursor.use{
            val idCol=it.getColumnIndexOrThrow("_id");val senderCol=it.getColumnIndexOrThrow("address")
            val bodyCol=it.getColumnIndexOrThrow("body");val dateCol=it.getColumnIndexOrThrow("date")
            val sentCol=it.getColumnIndex("date_sent");val subCol=it.getColumnIndex("sub_id");var count=0
            while(count<PAGE&&it.moveToNext()){
                if(stopped()||!ObservationLegacyOwnership.controlTransitionClear(app))return@synchronized Backfill.BLOCKED
                val id=it.getLong(idCol);if(id<=position.last||id>position.end)return@synchronized Backfill.BLOCKED
                val sender=if(it.isNull(senderCol))"" else it.getString(senderCol)
                val body=if(it.isNull(bodyCol))"" else it.getString(bodyCol)
                val received=if(it.isNull(dateCol))null else it.getLong(dateCol).takeIf{v->v>0}
                val sent=if(sentCol<0||it.isNull(sentCol))null else it.getLong(sentCol).takeIf{v->v>0}
                val sub=if(subCol<0||it.isNull(subCol))null else it.getInt(subCol).takeIf{v->v>=0}
                val candidate=ObservationCapture.candidate(app,session,fingerprint,sender,body)?:return@synchronized Backfill.BLOCKED
                val eligible=candidate&&!ReceiptCandidate.accepts(sender,body,profile.receipt)
                val advanced=if(eligible)ObservationLegacyOwnership.withDecision(app,owner,id,received,sender,body,sub){decision->
                    val retained=when(decision){
                        ObservationLegacyOwnership.Decision.HOLD->true
                        ObservationLegacyOwnership.Decision.OWNED->{ObservationLegacyOwnership.retained(app,sender,body,sent,received,sub);true}
                        ObservationLegacyOwnership.Decision.UNOWNED->{
                            val result=ObservationCapture.retain(app,session,fingerprint,"inbox:$id",sender,body,"catch_up",false,
                                sent?.let{v->Instant.ofEpochMilli(v).toString()},received?.let{v->Instant.ofEpochMilli(v).toString()},sub)
                            result!=ObservationCapture.Result.FULL&&result!=ObservationCapture.Result.UNAVAILABLE
                        }
                    }
                    retained&&!stopped()&&advanceBackfill(session,profile,consent,control,position,id)
                }?:false else ObservationLegacyOwnership.withoutControlTransition(app){
                    !stopped()&&advanceBackfill(session,profile,consent,control,position,id)
                }?:false
                if(!advanced)return@synchronized Backfill.MORE
                position=position.copy(last=id);count++
            }
            if(count<PAGE&&position.last<position.end){
                if(!advanceBackfill(session,profile,consent,control,position,position.end))return@synchronized Backfill.BLOCKED
                position=position.copy(last=position.end)
            }
            if(position.last==position.end)Backfill.COMPLETE else Backfill.MORE
        }}catch(_:Exception){Backfill.BLOCKED}
    }
    private fun read(owner:ObservationOwner,profileFingerprint:String):Pair<JSONArray,Long>{
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
        return rows to ObservationCursor.start(last,latest)
    }
    private fun advance(session:rw.ikanisa.burimunsi.core.ObservationSessionOwner,profileFingerprint:String,expected:Long,next:Long,
        consent:rw.ikanisa.burimunsi.core.ObservationConsentState,control:ObservationConfigStore.Control):Boolean =
        NativeRepository.withObservationOwner(app,session){group,account->
            val owner=session.owner
            if(owner!=ObservationOwner(group,account)||!permitted()||control.paused||
                config.controlState(owner)!=control||config.consent(owner)!=consent||!consent.canCapture(permitted()))return@withObservationOwner false
            if(config.profile(owner,System.currentTimeMillis())?.fingerprint()!=profileFingerprint)return@withObservationOwner false
            val (rows,old)=read(owner,profileFingerprint);if(old!=expected||next<=old)return@withObservationOwner false
            val updated=JSONArray();var found=false
            for(i in 0 until rows.length()){
                val row=rows.getJSONObject(i)
                if(row.getString("collectionId")==owner.collectionId&&row.getString("accountId")==owner.accountId&&row.getString("profileFingerprint")==profileFingerprint){
                    updated.put(JSONObject().put("collectionId",owner.collectionId).put("accountId",owner.accountId)
                        .put("profileFingerprint",profileFingerprint).put("lastId",next));found=true
                }else updated.put(row)
            }
            if(!found){checkContract(rows.length()<50,"observation_cursor_unavailable");updated.put(JSONObject()
                .put("collectionId",owner.collectionId).put("accountId",owner.accountId).put("profileFingerprint",profileFingerprint).put("lastId",next))}
            val encoded=JSONObject().put("items",updated).toString();cursorStore.write(encoded)
            checkContract(cursorStore.read()==encoded,"observation_cursor_unavailable");true
        }?:false
    /** Revisit only already-seen inbox identities when the PDU worker finished after the inbox scan. */
    fun correlateRecent(stopped:()->Boolean={false}) = synchronized(lock){
        if(stopped()||!permitted()||!ObservationLegacyOwnership.controlTransitionClear(app))return@synchronized
        val session=NativeRepository.observationOwner(app)?:return@synchronized
        val initial=try{NativeRepository.withObservationOwner(app,session){group,account->
            val owner=ObservationOwner(group,account);val now=System.currentTimeMillis()
            val profile=config.profile(owner,now);val consent=config.consent(owner)
            val correlation=PduCorrelationStore(app).read()
            val latest=ObservationJournal(ObservationStateStore(app)).latestSeenRow(owner)
            if(config.paused(owner)||consent?.canCapture(permitted())!=true||profile==null||latest==null||
                correlation.saturated||correlation.pdus.none{it.owner==owner})null else {
                val fingerprint=profile.fingerprint()
                Triple(fingerprint,latest,PduInboxCorrelation.InboxRelevance(correlation.pdus,owner,fingerprint))
            }
        }}catch(_:Exception){null}?:return@synchronized
        val (fingerprint,latest,relevance)=initial
        if(relevance.empty)return@synchronized
        val base=arrayOf("_id","address","body","date")
        val uri=Uri.parse("content://sms/inbox");val start=(latest-500L).coerceAtLeast(0L)
        val cursor=listOf(base+arrayOf("date_sent","sub_id"),base+"date_sent",base+"sub_id",base)
            .firstNotNullOfOrNull{columns->try{app.contentResolver.query(uri,columns,"_id > ?",arrayOf(start.toString()),"_id ASC")}
                catch(_:Exception){null}}?:return@synchronized
        try{cursor.use{
            val idColumn=it.getColumnIndexOrThrow("_id");val senderColumn=it.getColumnIndexOrThrow("address")
            val bodyColumn=it.getColumnIndexOrThrow("body");val dateColumn=it.getColumnIndexOrThrow("date")
            val sentColumn=it.getColumnIndex("date_sent");val subColumn=it.getColumnIndex("sub_id")
            var count=0
            while(count<500&&it.moveToNext()){
                if(stopped()||!permitted())return@synchronized
                val id=it.getLong(idColumn);if(id>latest)break
                count++
                val sender=if(it.isNull(senderColumn))"" else it.getString(senderColumn)
                val body=if(it.isNull(bodyColumn))"" else it.getString(bodyColumn)
                val received=if(it.isNull(dateColumn))null else it.getLong(dateColumn).takeIf{value->value>0}
                val sent=if(sentColumn<0||it.isNull(sentColumn))null else it.getLong(sentColumn).takeIf{value->value>0}
                val sub=if(subColumn<0||it.isNull(subColumn))null else it.getInt(subColumn).takeIf{value->value>=0}
                if(received==null||!relevance.mayMatch(sender,body,sent,sub))continue
                val candidate=ObservationCapture.candidate(app,session,fingerprint,sender,body)?:return@synchronized
                if(candidate)ObservationLegacyOwnership.withDecision(app,session.owner,id,received,sender,body,sub){decision->
                    if(decision==ObservationLegacyOwnership.Decision.UNOWNED&&!stopped())
                        ObservationCapture.correlateExisting(app,session,fingerprint,id,sender,body,sent,received,sub)
                }
            }
        }}catch(_:Exception){/* Keep the original incomplete observation and protected witness. */}
    }
    /** A completed sweep is distinct from denied, failed or interrupted scanning. */
    fun scanStatus(stopped:()->Boolean={false}):Scan = synchronized(lock){
        if(stopped()||!permitted()||!ObservationLegacyOwnership.controlTransitionClear(app))return@synchronized Scan.BLOCKED
        val session=NativeRepository.observationOwner(app)?:return@synchronized Scan.BLOCKED
        val initial=try{NativeRepository.withObservationOwner(app,session){group,account->
            val owner=ObservationOwner(group,account)
            val profile=config.profile(owner,System.currentTimeMillis());val control=config.controlState(owner);val consent=config.consent(owner)
            if(control.paused||consent?.canCapture(permitted())!=true||profile==null||profile.legacyHold==null)null
            else Triple(profile,consent,control)
        }}catch(_:Exception){null}?:return@synchronized Scan.BLOCKED
        val (profile,consent,control)=initial
        return@synchronized try{scanHeld(session,profile,consent,control,stopped)}catch(_:Exception){Scan.BLOCKED}

    }
    /** Compatibility for callers that only need to know whether another pass is needed. */
    fun scan(stopped:()->Boolean={false}):Boolean = scanStatus(stopped)==Scan.MORE

    private fun auditAuthority(stopped:()->Boolean):AuditAuthority? {
        if(stopped()||!ObservationInboxRevision.observerActive()||!permitted()||!ObservationLegacyOwnership.controlTransitionClear(app))return null
        val session=NativeRepository.observationOwner(app)?:return null
        val initial=NativeRepository.withObservationOwner(app,session){group,account->
            val owner=ObservationOwner(group,account);val profile=config.profile(owner,System.currentTimeMillis())
            val control=config.controlState(owner);val consent=config.consent(owner)
            if(control.paused||consent?.canCapture(permitted())!=true||profile?.legacyHold==null)null
            else Triple(profile,consent,control)
        }?:return null
        val (profile,consent,control)=initial
        val (device,keys)=held(session,profile,consent,control,stopped)?:return null
        val heldScope=Values.sha256(keys.sorted().joinToString(""){"${it.length}:$it"})
        val scope=AuditScope(session,profile.fingerprint(),profile.legacyHold,consent,control,Values.sha256(device),heldScope,
            ObservationInboxRevision.snapshot())
        if(stopped()||!ObservationInboxRevision.observerActive()||!permitted()||NativeRepository.observationOwner(app)!=session)return null
        return AuditAuthority(scope,profile,device,keys)
    }
    /** A completed local sweep is reusable only for this exact authority and inbox revision. */
    fun sweepScope(stopped:()->Boolean={false}):String? = synchronized(lock){
        try{auditAuthority(stopped)?.scope?.let{scope->
            Values.sha256(listOf(scope.session.owner.collectionId,scope.session.owner.accountId,scope.session.generation.toString(),
                scope.fingerprint,scope.legacyHold.toString(),scope.consent.revision.enabled.toString(),
                scope.consent.revision.generation.toString(),scope.consent.confirmed.toString(),scope.control.paused.toString(),
                scope.control.revision.toString(),scope.deviceScope,scope.heldScope,scope.revision.toString())
                .joinToString(""){"${it.length}:$it"})
        }}catch(_:Exception){null}
    }
    fun resetAudit()=synchronized(lock){auditProgress=null;completedAuditStart=null;completedAuditRevision=null}
    fun auditStartedAt():Long?=synchronized(lock){completedAuditStart}
    fun auditRevision():String?=synchronized(lock){completedAuditRevision}

    /** One bounded page of read-only source verification; the whole process-local
     * sweep is invalidated by a changed inbox, owner, control or process restart. */
    fun auditPage(repo:NativeRepository,stopped:()->Boolean={false}):Audit = synchronized(lock){
        val authority=try{auditAuthority(stopped)}catch(_:Exception){null}?:run{auditProgress=null;return@synchronized Audit.BLOCKED}
        val scope=authority.scope;val owner=scope.session.owner
        val clock=android.os.SystemClock.elapsedRealtime()
        val previous=auditProgress?.takeIf{it.scope==scope&&clock>=it.startedAt&&clock-it.startedAt<24*60*60_000L}
        var progress:AuditProgress=previous?:run{
            completedAuditStart=null;completedAuditRevision=null
            val status=repo.observationReconcileStatus()
            if(try{auditAuthority(stopped)?.scope!=scope}catch(_:Exception){true})return@synchronized Audit.BLOCKED
            if(status.hasPending)return@synchronized Audit.RETRY
            if(status.hasUnmatchedCanonical)return@synchronized Audit.UNCONFIRMED
            if(status.recordedCount !in 0..16_000||status.hasRecorded!=(status.recordedCount>0))return@synchronized Audit.UNCONFIRMED
            AuditProgress(scope,0,false,clock,status.revision,status.recordedCount)
        }
        if(progress.phoneComplete){
            if(stopped()||try{auditAuthority(stopped)?.scope!=scope}catch(_:Exception){true}){
                auditProgress=null;return@synchronized Audit.BLOCKED
            }
            val page=try{repo.observationPage(cursor=progress.cloudCursor,limit=100)}catch(error:ApiFailure){
                if(error.code in setOf("cursor_scope_changed","cursor_expired","invalid_cursor")){
                    auditProgress=null;return@synchronized Audit.RETRY
                }
                throw error
            }
            val after=try{auditAuthority(stopped)}catch(_:Exception){null}
            if(after?.scope!=scope||stopped()){auditProgress=null;return@synchronized Audit.BLOCKED}
            val ids=page.items.map{it.source.id};val total=page.totalCount
            if(total !in 0..16_000||ids.size>100||ids.toSet().size!=ids.size||ids.any{it in progress.cloudIds}||
                (progress.cloudRevision!=null&&page.revision!=progress.cloudRevision)||
                (progress.cloudTotal!=null&&total!=progress.cloudTotal)||
                page.items.any{it.groupId!=owner.collectionId}){
                auditProgress=null;return@synchronized Audit.UNCONFIRMED
            }
            val collected=progress.cloudIds+ids
            if(collected.size>total){auditProgress=null;return@synchronized Audit.UNCONFIRMED}
            val next=page.nextCursor
            if(next!=null){
                if(next in progress.cursors||ids.isEmpty()||collected.size>=total){auditProgress=null;return@synchronized Audit.UNCONFIRMED}
                auditProgress=progress.copy(cloudCursor=next,cloudRevision=page.revision,cloudTotal=total,cloudIds=collected,
                    cursors=progress.cursors+next)
                return@synchronized Audit.MORE
            }
            if(stopped()||try{auditAuthority(stopped)?.scope!=scope}catch(_:Exception){true}){
                auditProgress=null;return@synchronized Audit.BLOCKED
            }
            val status=repo.observationReconcileStatus()
            if(try{auditAuthority(stopped)?.scope!=scope}catch(_:Exception){true}){auditProgress=null;return@synchronized Audit.BLOCKED}
            auditProgress=null
            if(status.hasPending||status.hasUnmatchedCanonical||status.revision!=progress.collectionRevision||status.recordedCount!=progress.recordedCount)
                return@synchronized Audit.RETRY
            if(status.hasRecorded!=(status.recordedCount>0)||total!=status.recordedCount||collected.size!=total||collected!=progress.sourceIds)
                return@synchronized Audit.UNCONFIRMED
            completedAuditStart=progress.startedAt
            completedAuditRevision=progress.collectionRevision
            return@synchronized Audit.COMPLETE
        }
        val base=arrayOf("_id","address","body","date");val uri=Uri.parse("content://sms/inbox")
        val senders=authority.profile.receipt.senders.sorted()
        val filtered=senders.isNotEmpty()&&senders.size<=30&&senders.all{it.isNotEmpty()&&it.all{c->c in ' '..'~'}}
        val plans=if(filtered)listOf(
            ("_id > ? AND (address COLLATE NOCASE IN (${senders.joinToString(","){"?"}}) OR address GLOB '*[^ -~]*')") to
                (arrayOf(progress.last.toString())+senders),"_id > ?" to arrayOf(progress.last.toString())
        )else listOf("_id > ?" to arrayOf(progress.last.toString()))
        fun open()=plans.firstNotNullOfOrNull{(selection,args)->
            listOf(base+arrayOf("date_sent","sub_id"),base+"date_sent",base+"sub_id",base)
                .firstNotNullOfOrNull{columns->try{app.contentResolver.query(uri,columns,selection,args,"_id ASC")}
                    catch(_:Exception){null}}
        }
        fun takePage():List<AuditRow>? {
            val cursor=open()?:return null;val rows=mutableListOf<AuditRow>();var previous=progress.last
            cursor.use{
                val id=it.getColumnIndexOrThrow("_id");val date=it.getColumnIndexOrThrow("date")
                val sender=it.getColumnIndexOrThrow("address");val body=it.getColumnIndexOrThrow("body")
                val sent=it.getColumnIndex("date_sent");val sub=it.getColumnIndex("sub_id")
                while(rows.size<20&&it.moveToNext()){
                    if(stopped()||it.isNull(id)||it.isNull(date))return null
                    val rowId=it.getLong(id);val received=it.getLong(date)
                    if(rowId<=previous||received<=0)return null
                    rows.add(AuditRow(rowId,received,if(it.isNull(sender))"" else it.getString(sender),
                        if(it.isNull(body))"" else it.getString(body),if(sent<0||it.isNull(sent))null else it.getLong(sent).takeIf{v->v>0},
                        if(sub<0||it.isNull(sub))null else it.getInt(sub).takeIf{v->v>=0}));previous=rowId
                }
            }
            return rows
        }
        val rows=try{takePage()}catch(_:Exception){null}?:run{auditProgress=null;return@synchronized Audit.BLOCKED}
        var uncertain=progress.unconfirmed;val requests=mutableListOf<ObservationReconcileRequest>()
        val decisions=mutableMapOf<Long,ObservationLegacyOwnership.Decision>()
        for(row in rows){
            if(authority.profile.receipt.senders.none{it.equals(row.sender,ignoreCase=true)})continue
            if(!ObservationCandidate.accepts(row.sender,row.body,authority.profile.receipt)){uncertain=true;continue}
            val key=stableKey(authority.device,owner.collectionId,row.id,row.received)
            val decision=if(key in authority.held)ObservationLegacyOwnership.Decision.HOLD else
                ObservationLegacyOwnership.classify(app,owner,row.id,row.received,row.sender,row.body,row.sub)
            decisions[row.id]=decision
            // A held identity may be checked, but this never releases the hold
            // or creates a source when the read-only lookup is missing.
            requests.add(ObservationReconcileRequest(key,Values.sha256(row.body),row.sender,
                row.sent?.let{Instant.ofEpochMilli(it).toString()},Instant.ofEpochMilli(row.received).toString(),row.sub))
        }
        // Per-item conflicts/poison witnesses are isolated; authentication and
        // service-wide outages are retried with the caller's bounded backoff.
        fun verify(items:List<ObservationReconcileRequest>):List<ObservationReconcileReply?> {
            if(items.isEmpty())return emptyList()
            if(stopped())throw InterruptedException()
            if(try{auditAuthority(stopped)?.scope!=scope}catch(_:Exception){true})throw AuditAuthorityChanged()
            return try{
                val replies=repo.reconcileObservations(items)
                checkContract(replies.size==items.size&&replies.indices.all{i->replies[i].sourceKey==items[i].sourceKey&&
                    replies[i].state in setOf("matched","missing")&&(replies[i].state=="matched")==(replies[i].sourceId!=null)},
                    "invalid_observation_reconciliation")
                replies
            }
            catch(error:ApiFailure){
                val itemFailure=error.code in setOf("observation_item_conflict","observation_item_unavailable")
                if(!itemFailure)throw error
                if(items.size==1)listOf(null) else{
                    val middle=items.size/2;verify(items.subList(0,middle))+verify(items.subList(middle,items.size))
                }
            }
        }
        val states=try{requests.chunked(4).flatMap{verify(it)}}catch(error:Exception){
            if(stopped()||error is AuditAuthorityChanged){auditProgress=null;return@synchronized Audit.BLOCKED}
            throw error
        }
        var sourceIds=progress.sourceIds
        for(reply in states){
            val sourceId=reply?.sourceId
            if(reply?.state!="matched"||sourceId==null)uncertain=true
            else if(sourceId in sourceIds)uncertain=true
            else if(sourceIds.size>=16_000){auditProgress=null;return@synchronized Audit.UNCONFIRMED}
            else sourceIds=sourceIds+sourceId
        }
        // Re-read the exact page and authority after all responses; never
        // advance on a changed provider row, hold, consent, owner or revision.
        val after=try{auditAuthority(stopped)}catch(_:Exception){null}
        if(after?.scope!=scope||try{takePage()!=rows}catch(_:Exception){true}){
            auditProgress=null;return@synchronized Audit.BLOCKED
        }
        for(row in rows){
            if(authority.profile.receipt.senders.none{it.equals(row.sender,ignoreCase=true)}||
                !ObservationCandidate.accepts(row.sender,row.body,authority.profile.receipt))continue
            val key=stableKey(authority.device,owner.collectionId,row.id,row.received)
            val before=decisions[row.id]?:run{auditProgress=null;return@synchronized Audit.BLOCKED}
            val now=if(key in after.held)ObservationLegacyOwnership.Decision.HOLD else
                ObservationLegacyOwnership.classify(app,owner,row.id,row.received,row.sender,row.body,row.sub)
            if(before!=now||ObservationInboxRevision.snapshot()!=scope.revision||stopped()){
                auditProgress=null;return@synchronized Audit.BLOCKED
            }
        }
        if(try{auditAuthority(stopped)?.scope!=scope}catch(_:Exception){true}){
            auditProgress=null;return@synchronized Audit.BLOCKED
        }
        val last=rows.lastOrNull()?.id?:progress.last
        if(rows.size<20){
            if(uncertain){auditProgress=null;return@synchronized Audit.UNCONFIRMED}
            auditProgress=progress.copy(last=last,sourceIds=sourceIds,phoneComplete=true)
            return@synchronized Audit.MORE
        }
        progress=progress.copy(last=last,unconfirmed=uncertain,sourceIds=sourceIds);auditProgress=progress
        Audit.MORE
    }

    /**
     * The phone's latest provider SMS is ordered by received time, then inbox
     * row ID. A held latest source is not replaced with an older unheld one.
     * This read is time-bounded by the cycle budget, and also fails closed if
     * the provider returns too many rows or violates the requested ordering.
     */
    fun latest(stopped:()->Boolean={false}):Latest = synchronized(lock){
        if(stopped()||!permitted()||!ObservationLegacyOwnership.controlTransitionClear(app))return@synchronized Latest.Blocked
        // The gateway identity must be read before the native session fence.
        val installation=try{MomoGatewayStore(app).existingInstallationId()}catch(_:Exception){null}?:return@synchronized Latest.Blocked
        val session=NativeRepository.observationOwner(app)?:return@synchronized Latest.Blocked
        val initial=try{NativeRepository.withObservationOwner(app,session){group,account->
            val owner=ObservationOwner(group,account);val profile=config.profile(owner,System.currentTimeMillis())
            val control=config.controlState(owner);val consent=config.consent(owner)
            if(control.paused||consent?.canCapture(permitted())!=true||profile==null||profile.legacyHold==null)null
            else Triple(profile,consent,control)
        }}catch(_:Exception){null}?:return@synchronized Latest.Blocked
        val (profile,consent,control)=initial;val owner=session.owner
        try {
            val (device,heldKeys)=held(session,profile,consent,control,stopped)?:return@synchronized Latest.Blocked
            fun current():Boolean=ObservationLegacyOwnership.withoutControlTransition(app){
                NativeRepository.withObservationOwner(app,session){group,account->
                    !stopped()&&permitted()&&owner==ObservationOwner(group,account)&&config.controlState(owner)==control&&
                        config.consent(owner)==consent&&consent.canCapture(permitted())&&
                        config.profile(owner,System.currentTimeMillis())==profile&&deviceId()==device
                }?:false
            }==true
            val base=arrayOf("_id","address","body","date");val uri=Uri.parse("content://sms/inbox")
            val senders=profile.receipt.senders.sorted()
            val filtered=senders.isNotEmpty()&&senders.size<=30&&senders.all{it.isNotEmpty()&&it.all{c->c in ' '..'~'}}
            val plans=if(filtered)listOf(
                ("_id > ? AND (address COLLATE NOCASE IN (${senders.joinToString(","){"?"}}) OR address GLOB '*[^ -~]*')") to
                    (arrayOf("0")+senders), "_id > ?" to arrayOf("0")
            )else listOf("_id > ?" to arrayOf("0"))
            val cursor=plans.firstNotNullOfOrNull{(selection,args)->
                listOf(base+arrayOf("date_sent","sub_id"),base+"date_sent",base+"sub_id",base)
                    .firstNotNullOfOrNull{columns->try{app.contentResolver.query(uri,columns,selection,args,"date DESC, _id DESC")}
                        catch(_:Exception){null}}
            }?:return@synchronized Latest.Blocked
            data class PhoneRow(val id:Long,val received:Long,val sender:String,val body:String,val sent:Long?,val sub:Int?)
            var newest:PhoneRow?=null
            cursor.use{
                val idCol=it.getColumnIndexOrThrow("_id");val dateCol=it.getColumnIndexOrThrow("date")
                val senderCol=it.getColumnIndexOrThrow("address");val bodyCol=it.getColumnIndexOrThrow("body")
                val sentCol=it.getColumnIndex("date_sent");val subCol=it.getColumnIndex("sub_id")
                val identities=mutableSetOf<Long>();var count=0
                while(it.moveToNext()){
                    if(++count>MAX_LATEST_SCAN||stopped()||!permitted()||!ObservationLegacyOwnership.controlTransitionClear(app)||
                        it.isNull(idCol)||it.isNull(dateCol))return@synchronized Latest.Blocked
                    val id=it.getLong(idCol);val received=it.getLong(dateCol)
                    if(id<=0||received<=0||!identities.add(id))return@synchronized Latest.Blocked
                    val sender=if(it.isNull(senderCol))"" else it.getString(senderCol)
                    val body=if(it.isNull(bodyCol))"" else it.getString(bodyCol)
                    val sent=if(sentCol<0||it.isNull(sentCol))null else it.getLong(sentCol).takeIf{v->v>0}
                    val sub=if(subCol<0||it.isNull(subCol))null else it.getInt(subCol).takeIf{v->v>=0}
                    if(profile.receipt.senders.none{it.equals(sender,ignoreCase=true)})continue
                    val previous=newest
                    if(previous==null||received>previous.received||received==previous.received&&id>previous.id)
                        newest=PhoneRow(id,received,sender,body,sent,sub)
                }
            }
            val row=newest
            if(row!=null){
                if(!ObservationCandidate.accepts(row.sender,row.body,profile.receipt))return@synchronized Latest.Held
                val key=stableKey(device,owner.collectionId,row.id,row.received)
                val decision=if(key in heldKeys)ObservationLegacyOwnership.Decision.HOLD else
                    ObservationLegacyOwnership.classify(app,owner,row.id,row.received,row.sender,row.body,row.sub)
                if(!current())return@synchronized Latest.Blocked
                val receivedAt=Instant.ofEpochMilli(row.received).toString()
                val request=ObservationReconcileRequest(key,Values.sha256(row.body),row.sender,row.sent?.let{v->Instant.ofEpochMilli(v).toString()},receivedAt,row.sub)
                val local=ObservationSourceIdentity.inbox(installation,owner,row.id,receivedAt)
                return@synchronized Latest.Ready(LatestWitness(session,profile.fingerprint(),profile.legacyHold,consent,control,row.id,local,request,
                    decision!=ObservationLegacyOwnership.Decision.UNOWNED))
            }
            // The caller must independently confirm that the Cloud is empty.
            if(!current())Latest.Blocked else Latest.Empty(session,profile.fingerprint(),profile.legacyHold,consent,control,Values.sha256(device))
        }catch(_:Exception){Latest.Blocked}
    }
}

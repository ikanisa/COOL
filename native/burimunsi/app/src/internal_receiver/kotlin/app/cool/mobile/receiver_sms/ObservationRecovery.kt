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
import rw.ikanisa.burimunsi.core.ObservationJournal
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.core.ObservationConsentState
import rw.ikanisa.burimunsi.core.ObservationProfile
import rw.ikanisa.burimunsi.core.ObservationSessionOwner
import rw.ikanisa.burimunsi.core.ObservationSourceIdentity
import rw.ikanisa.burimunsi.core.ReceiptCandidate
import rw.ikanisa.burimunsi.core.Values
import rw.ikanisa.burimunsi.core.checkContract
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.storage.SecureStore
import java.time.Instant

/** Local inbox catch-up; raw text leaves the cursor only after candidate filtering. */
internal class ObservationRecovery(context:Context) {
    private val app=context.applicationContext
    private val cursorStore=SecureStore(app,"observation-cursors")
    private val config=ObservationConfigStore(app)
    companion object {private val lock=Any();private const val PAGE=100;private const val MAX_HELD=20_000}
    internal enum class Backfill { COMPLETE, MORE, BLOCKED }
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
        control:ObservationConfigStore.Control,stopped:()->Boolean):Boolean {
        val owner=session.owner;val (device,keys)=held(session,profile,consent,control,stopped)?:return false
        val store=rescanStore(owner,profile.legacyHold==true||legacyExists(owner.collectionId));val last=store.read()?.let{raw->
            val v=JSONObject(raw);checkContract(v.keys().asSequence().toSet()==setOf("collectionId","accountId","lastId")&&
                v.getString("collectionId")==owner.collectionId&&v.getString("accountId")==owner.accountId&&v.getLong("lastId")>=0,
                "observation_cursor_unavailable");v.getLong("lastId")
        }?:0L
        fun save(expected:Long,next:Long):Boolean=NativeRepository.withObservationOwner(app,session){group,account->
            if(stopped()||!permitted()||owner!=ObservationOwner(group,account)||config.controlState(owner)!=control||
                config.consent(owner)!=consent||!consent.canCapture(permitted())||config.profile(owner,System.currentTimeMillis())!=profile||
                deviceId()!=device)false
            else{
                val current=store.read()?.let{JSONObject(it).getLong("lastId")}?:0L
                if(current!=expected)false else{
                    val text=JSONObject().put("collectionId",owner.collectionId).put("accountId",owner.accountId).put("lastId",next).toString()
                    store.write(text);store.read()==text
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
        }?:return false
        var position=last;var count=0
        cursor.use{
            val idCol=it.getColumnIndexOrThrow("_id");val senderCol=it.getColumnIndexOrThrow("address")
            val bodyCol=it.getColumnIndexOrThrow("body");val dateCol=it.getColumnIndexOrThrow("date")
            val sentCol=it.getColumnIndex("date_sent");val subCol=it.getColumnIndex("sub_id")
            while(count<PAGE&&it.moveToNext()){
                if(stopped()||!permitted()||!ObservationLegacyOwnership.controlTransitionClear(app)||it.isNull(idCol)||it.isNull(dateCol))return false
                val id=it.getLong(idCol);val received=it.getLong(dateCol);if(id<=position||received<=0)return false
                val sender=if(it.isNull(senderCol))"" else it.getString(senderCol)
                val body=if(it.isNull(bodyCol))"" else it.getString(bodyCol)
                val sent=if(sentCol<0||it.isNull(sentCol))null else it.getLong(sentCol).takeIf{v->v>0}
                val sub=if(subCol<0||it.isNull(subCol))null else it.getInt(subCol).takeIf{v->v>=0}
                val key=stableKey(device,owner.collectionId,id,received)
                val candidate=ObservationCapture.candidate(app,session,profile.fingerprint(),sender,body)?:return false
                val advanced=if(key in keys||!candidate)ObservationLegacyOwnership.withoutControlTransition(app){save(position,id)}?:false
                else ObservationLegacyOwnership.withDecision(app,owner,id,received,sender,body,sub){decision->
                    val retained=when(decision){
                        ObservationLegacyOwnership.Decision.HOLD->false
                        ObservationLegacyOwnership.Decision.OWNED->ObservationLegacyOwnership.retained(app,sender,body,sent,received,sub)
                        ObservationLegacyOwnership.Decision.UNOWNED->{
                            val result=ObservationCapture.retain(app,session,profile.fingerprint(),"inbox:$id",sender,body,"catch_up",false,
                                sent?.let{v->Instant.ofEpochMilli(v).toString()},Instant.ofEpochMilli(received).toString(),sub)
                            result!=ObservationCapture.Result.FULL&&result!=ObservationCapture.Result.UNAVAILABLE
                        }
                    }
                    retained&&save(position,id)
                }?:false
                if(!advanced)return false
                position=id;count++
            }
        }
        if(count<PAGE){if(ObservationLegacyOwnership.withoutControlTransition(app){save(position,0)}!=true)return false;return false}
        return true
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
                        ObservationLegacyOwnership.Decision.HOLD->false
                        ObservationLegacyOwnership.Decision.OWNED->ObservationLegacyOwnership.retained(app,sender,body,sent,received,sub)
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
    /** Returns true only when another bounded pass may be needed. */
    fun scan(stopped:()->Boolean={false}):Boolean = synchronized(lock){
        if(stopped()||!permitted()||!ObservationLegacyOwnership.controlTransitionClear(app))return@synchronized false
        val session=NativeRepository.observationOwner(app)?:return@synchronized false
        val initial=try{NativeRepository.withObservationOwner(app,session){group,account->
            val owner=ObservationOwner(group,account)
            val profile=config.profile(owner,System.currentTimeMillis());val control=config.controlState(owner);val consent=config.consent(owner)
            if(control.paused||consent?.canCapture(permitted())!=true||profile==null||profile.legacyHold==null)null
            else Triple(profile,consent,control)
        }}catch(_:Exception){null}?:return@synchronized false
        val (profile,consent,control)=initial
        return@synchronized try{scanHeld(session,profile,consent,control,stopped)}catch(_:Exception){false}

    }
}

package app.cool.mobile.receiver_sms

import android.content.Context
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.ObservationCandidate
import rw.ikanisa.burimunsi.core.ObservationJournal
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.core.ObservationConsentState
import rw.ikanisa.burimunsi.core.ObservationProfile
import rw.ikanisa.burimunsi.core.ObservationReconcileRequest
import rw.ikanisa.burimunsi.core.ObservationSessionOwner
import rw.ikanisa.burimunsi.core.ObservationSourceIdentity
import rw.ikanisa.burimunsi.core.Values
import rw.ikanisa.burimunsi.core.checkContract
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.storage.SecureStore
import java.time.Instant

/** Local inbox catch-up; raw text leaves the cursor only after candidate filtering. */
internal class ObservationRecovery(context:Context) {
    private val app=context.applicationContext
    private val config=ObservationConfigStore(app)
    companion object {
        private val lock = Any()
        private const val PAGE = 100
        private const val MAX_LATEST_SCAN = 20_000
    }
    private val heldInbox = ObservationHeldInbox(app, config)
    private val audit = ObservationInboxAudit(app, config, heldInbox, lock)
    private val backfill = ObservationInboxBackfill(app, config, heldInbox, lock)

    internal enum class Backfill { COMPLETE, MORE, BLOCKED }
    internal enum class Scan { COMPLETE, MORE, BLOCKED }
    internal enum class Audit { COMPLETE, MORE, YIELD, RETRY, UNCONFIRMED, BLOCKED }
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
    private fun rescanStore(owner:ObservationOwner,legacy:Boolean)=SecureStore(app,"observation-bounded-rescan-"+
        Values.sha256(listOf(owner.collectionId,owner.accountId,legacy.toString()).joinToString(""){"${it.length}:$it"}))
    /** Scan the whole inbox in bounded passes. A later insertion with a reused
     * or lower row ID is considered on the next pass regardless of its date. */
    private fun scanHeld(session:ObservationSessionOwner,profile:ObservationProfile,consent:ObservationConsentState,
        control:ObservationConfigStore.Control,stopped:()->Boolean):Scan {
        val owner=session.owner;val (device,keys)=heldInbox.snapshot(session,profile,consent,control,stopped)?:return Scan.BLOCKED
        val installation=MomoGatewayStore(app).existingInstallationId()?:return Scan.BLOCKED
        val journal=ObservationJournal(ObservationStateStore(app))
        val seen=NativeRepository.withObservationOwner(app,session){_,_->journal.seenSnapshot(owner)}?:return Scan.BLOCKED
        val seenByKey=seen.entries.associateBy{it.sourceKey}
        val revision=ObservationInboxRevision.snapshot();val epoch=ObservationInboxRevision.epoch()
        val scope=Values.sha256(listOf(owner.collectionId,owner.accountId,session.generation.toString(),profile.fingerprint(),
            profile.legacyHold.toString(),consent.revision.enabled.toString(),consent.revision.generation.toString(),
            consent.confirmed.toString(),control.paused.toString(),control.revision.toString(),Values.sha256(device))
            .joinToString(""){"${it.length}:$it"})
        val store=rescanStore(owner,profile.legacyHold==true||heldInbox.legacyExists(owner.collectionId));var stored=store.read()
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
            if(stopped()||!observationInboxPermitted(app)||owner!=ObservationOwner(group,account)||config.controlState(owner)!=control||
                config.consent(owner)!=consent||!consent.canCapture(observationInboxPermitted(app))||config.profile(owner,System.currentTimeMillis())!=profile||
                heldInbox.deviceId()!=device||ObservationInboxRevision.snapshot()!=revision)false
            else{
                val current=store.read()
                if(current!=stored)false else{
                    val text=JSONObject().put("collectionId",owner.collectionId).put("accountId",owner.accountId).put("lastId",next)
                        .put("scope",scope).put("epoch",epoch).put("revision",revision).toString()
                    store.write(text);if(store.read()!=text)false else{stored=text;true}
                }
            }
        }?:false
        val cursor = queryObservationInbox(app, last, profile.receipt.senders) ?: return Scan.BLOCKED
        var position=last;var count=0
        cursor.use{
            val idCol=it.getColumnIndexOrThrow("_id");val senderCol=it.getColumnIndexOrThrow("address")
            val bodyCol=it.getColumnIndexOrThrow("body");val dateCol=it.getColumnIndexOrThrow("date")
            val sentCol=it.getColumnIndex("date_sent");val subCol=it.getColumnIndex("sub_id")
            while(count<PAGE&&it.moveToNext()){
                if(stopped()||!observationInboxPermitted(app)||!ObservationLegacyOwnership.controlTransitionClear(app)||it.isNull(idCol)||it.isNull(dateCol))return Scan.BLOCKED
                val id=it.getLong(idCol);val received=it.getLong(dateCol);if(id<=position||received<=0)return Scan.BLOCKED
                val sender=if(it.isNull(senderCol))"" else it.getString(senderCol)
                val body=if(it.isNull(bodyCol))"" else it.getString(bodyCol)
                val sent=if(sentCol<0||it.isNull(sentCol))null else it.getLong(sentCol).takeIf{v->v>0}
                val sub=if(subCol<0||it.isNull(subCol))null else it.getInt(subCol).takeIf{v->v>=0}
                val key=heldInboxSourceKey(device,owner.collectionId,id,received)
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
    fun backfill(stopped: () -> Boolean = { false }): Backfill = backfill.run(stopped)

    /** Revisit only already-seen inbox identities when the PDU worker finished after the inbox scan. */
    fun correlateRecent(stopped:()->Boolean={false}) = synchronized(lock){
        if(stopped()||!observationInboxPermitted(app)||!ObservationLegacyOwnership.controlTransitionClear(app))return@synchronized
        val session=NativeRepository.observationOwner(app)?:return@synchronized
        val initial=try{NativeRepository.withObservationOwner(app,session){group,account->
            val owner=ObservationOwner(group,account);val now=System.currentTimeMillis()
            val profile=config.profile(owner,now);val consent=config.consent(owner)
            val correlation=PduCorrelationStore(app).read()
            val latest=ObservationJournal(ObservationStateStore(app)).latestSeenRow(owner)
            if(config.paused(owner)||consent?.canCapture(observationInboxPermitted(app))!=true||profile==null||latest==null||
                correlation.saturated||correlation.pdus.none{it.owner==owner})null else {
                val fingerprint=profile.fingerprint()
                Triple(fingerprint,latest,PduInboxCorrelation.InboxRelevance(correlation.pdus,owner,fingerprint))
            }
        }}catch(_:Exception){null}?:return@synchronized
        val (fingerprint,latest,relevance)=initial
        if(relevance.empty)return@synchronized
        val start = (latest - 500L).coerceAtLeast(0L)
        val cursor = queryObservationInbox(app, start) ?: return@synchronized
        try{cursor.use{
            val idColumn=it.getColumnIndexOrThrow("_id");val senderColumn=it.getColumnIndexOrThrow("address")
            val bodyColumn=it.getColumnIndexOrThrow("body");val dateColumn=it.getColumnIndexOrThrow("date")
            val sentColumn=it.getColumnIndex("date_sent");val subColumn=it.getColumnIndex("sub_id")
            var count=0
            while(count<500&&it.moveToNext()){
                if(stopped()||!observationInboxPermitted(app))return@synchronized
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
        if(stopped()||!observationInboxPermitted(app)||!ObservationLegacyOwnership.controlTransitionClear(app))return@synchronized Scan.BLOCKED
        val session=NativeRepository.observationOwner(app)?:return@synchronized Scan.BLOCKED
        val initial=try{NativeRepository.withObservationOwner(app,session){group,account->
            val owner=ObservationOwner(group,account)
            val profile=config.profile(owner,System.currentTimeMillis());val control=config.controlState(owner);val consent=config.consent(owner)
            if(control.paused||consent?.canCapture(observationInboxPermitted(app))!=true||profile==null||profile.legacyHold==null)null
            else Triple(profile,consent,control)
        }}catch(_:Exception){null}?:return@synchronized Scan.BLOCKED
        val (profile,consent,control)=initial
        return@synchronized try{scanHeld(session,profile,consent,control,stopped)}catch(_:Exception){Scan.BLOCKED}

    }
    /** Compatibility for callers that only need to know whether another pass is needed. */
    fun scan(stopped:()->Boolean={false}):Boolean = scanStatus(stopped)==Scan.MORE

    fun sweepScope(stopped: () -> Boolean = { false }): String? = audit.sweepScope(stopped)
    fun resetAudit() = audit.resetAudit()
    fun auditStartedAt(): Long? = audit.auditStartedAt()
    fun auditRevision(): String? = audit.auditRevision()

    fun auditPage(
        repo: NativeRepository,
        stopped: () -> Boolean = { false },
        budgetExpired: () -> Boolean = { false },
    ): Audit = audit.auditPage(repo, stopped, budgetExpired)

    /**
     * The phone's latest provider SMS is ordered by received time, then inbox
     * row ID. A held latest source is not replaced with an older unheld one.
     * This read is time-bounded by the cycle budget, and also fails closed if
     * the provider returns too many rows or violates the requested ordering.
     */
    fun latest(stopped:()->Boolean={false}):Latest = synchronized(lock){
        if(stopped()||!observationInboxPermitted(app)||!ObservationLegacyOwnership.controlTransitionClear(app))return@synchronized Latest.Blocked
        // The gateway identity must be read before the native session fence.
        val installation=try{MomoGatewayStore(app).existingInstallationId()}catch(_:Exception){null}?:return@synchronized Latest.Blocked
        val session=NativeRepository.observationOwner(app)?:return@synchronized Latest.Blocked
        val initial=try{NativeRepository.withObservationOwner(app,session){group,account->
            val owner=ObservationOwner(group,account);val profile=config.profile(owner,System.currentTimeMillis())
            val control=config.controlState(owner);val consent=config.consent(owner)
            if(control.paused||consent?.canCapture(observationInboxPermitted(app))!=true||profile==null||profile.legacyHold==null)null
            else Triple(profile,consent,control)
        }}catch(_:Exception){null}?:return@synchronized Latest.Blocked
        val (profile,consent,control)=initial;val owner=session.owner
        try {
            val (device,heldKeys)=heldInbox.snapshot(session,profile,consent,control,stopped)?:return@synchronized Latest.Blocked
            fun current():Boolean=ObservationLegacyOwnership.withoutControlTransition(app){
                NativeRepository.withObservationOwner(app,session){group,account->
                    !stopped()&&observationInboxPermitted(app)&&owner==ObservationOwner(group,account)&&config.controlState(owner)==control&&
                        config.consent(owner)==consent&&consent.canCapture(observationInboxPermitted(app))&&
                        config.profile(owner,System.currentTimeMillis())==profile&&heldInbox.deviceId()==device
                }?:false
            }==true
            val cursor = queryObservationInbox(app, 0, profile.receipt.senders, order = ObservationInboxOrder.NEWEST)
                ?: return@synchronized Latest.Blocked
            data class PhoneRow(val id:Long,val received:Long,val sender:String,val body:String,val sent:Long?,val sub:Int?)
            var newest:PhoneRow?=null
            cursor.use{
                val idCol=it.getColumnIndexOrThrow("_id");val dateCol=it.getColumnIndexOrThrow("date")
                val senderCol=it.getColumnIndexOrThrow("address");val bodyCol=it.getColumnIndexOrThrow("body")
                val sentCol=it.getColumnIndex("date_sent");val subCol=it.getColumnIndex("sub_id")
                val identities=mutableSetOf<Long>();var count=0
                while(it.moveToNext()){
                    if(++count>MAX_LATEST_SCAN||stopped()||!observationInboxPermitted(app)||!ObservationLegacyOwnership.controlTransitionClear(app)||
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
                val key=heldInboxSourceKey(device,owner.collectionId,row.id,row.received)
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

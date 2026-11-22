package app.cool.mobile.receiver_sms

import android.content.Context
import app.cool.mobile.receiver_sms.ObservationRecovery.Audit
import rw.ikanisa.burimunsi.core.ObservationCandidate
import rw.ikanisa.burimunsi.core.ObservationConsentState
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.core.ObservationProfile
import rw.ikanisa.burimunsi.core.ObservationReconcileReply
import rw.ikanisa.burimunsi.core.ObservationReconcileRequest
import rw.ikanisa.burimunsi.core.ObservationSessionOwner
import rw.ikanisa.burimunsi.core.Values
import rw.ikanisa.burimunsi.core.checkContract
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.NativeRepository
import java.time.Instant

/** Verifies held and recorded sources against a single phone and collection revision. */
internal class ObservationInboxAudit(
    private val app: Context,
    private val config: ObservationConfigStore,
    private val heldInbox: ObservationHeldInbox,
    private val lock: Any,
) {
    companion object {
        private const val AUDIT_PAGE = 4
        private var auditProgress:AuditProgress?=null
        private var completedAuditStart:Long?=null
        private var completedAuditRevision:String?=null
    }

    private data class AuditScope(val session:ObservationSessionOwner,val fingerprint:String,val legacyHold:Boolean?,
        val consent:ObservationConsentState,val control:ObservationConfigStore.Control,val deviceScope:String,val heldScope:String,val revision:Long)
    private data class AuditProgress(val scope:AuditScope,val last:Long,val unconfirmed:Boolean,val startedAt:Long,
        val collectionRevision:String,val recordedCount:Int,
        val sourceIds:Set<String> = emptySet(),val phoneComplete:Boolean=false,val cloudCursor:String?=null,
        val cloudRevision:String?=null,val cloudTotal:Int?=null,val cloudIds:Set<String> = emptySet(),val cursors:Set<String> = emptySet(),
        val cloudComplete:Boolean=false)
    private data class AuditAuthority(val scope:AuditScope,val profile:ObservationProfile,val device:String,val held:Set<String>)
    private class AuditAuthorityChanged:Exception()
    private data class AuditRow(val id:Long,val received:Long,val sender:String,val body:String,val sent:Long?,val sub:Int?){
        override fun toString()="AuditRow(redacted)"
    }

    private fun auditAuthority(stopped:()->Boolean):AuditAuthority? {
        if(stopped()||!ObservationInboxRevision.observerActive()||!observationInboxPermitted(app)||!ObservationLegacyOwnership.controlTransitionClear(app))return null
        val session=NativeRepository.observationOwner(app)?:return null
        val initial=NativeRepository.withObservationOwner(app,session){group,account->
            val owner=ObservationOwner(group,account);val profile=config.profile(owner,System.currentTimeMillis())
            val control=config.controlState(owner);val consent=config.consent(owner)
            if(control.paused||consent?.canCapture(observationInboxPermitted(app))!=true||profile?.legacyHold==null)null
            else Triple(profile,consent,control)
        }?:return null
        val (profile,consent,control)=initial
        val (device,keys)=heldInbox.snapshot(session,profile,consent,control,stopped)?:return null
        if(HeldRecoveryJournal.hasRecords(app)){
            val installation=MomoGatewayStore(app).existingInstallationId()?:return null
            if(HeldRecoveryJournal.hasUncertain(app,session.owner,installation,Values.sha256(device)))return null
        }
        val heldScope=Values.sha256(keys.sorted().joinToString(""){"${it.length}:$it"})
        val scope=AuditScope(session,profile.fingerprint(),profile.legacyHold,consent,control,Values.sha256(device),heldScope,
            ObservationInboxRevision.snapshot())
        if(stopped()||!ObservationInboxRevision.observerActive()||!observationInboxPermitted(app)||NativeRepository.observationOwner(app)!=session)return null
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
    fun auditPage(repo:NativeRepository,stopped:()->Boolean={false},budgetExpired:()->Boolean={false}):Audit = synchronized(lock){
        // A deadline never makes an in-flight page valid. Keep only progress
        // saved before this call; the next cycle revalidates its whole scope.
        fun interrupted():Audit {
            if(stopped()&&budgetExpired())return Audit.YIELD
            auditProgress=null;return Audit.BLOCKED
        }
        // A reply received after the deadline may be checkpointed after the
        // local authority and inbox are rechecked. It cannot start another I/O.
        val localStop={stopped()&&!budgetExpired()}
        val authority=try{auditAuthority(stopped)}catch(_:Exception){null}?:return@synchronized interrupted()
        val scope=authority.scope;val owner=scope.session.owner
        val clock=android.os.SystemClock.elapsedRealtime()
        val previous=auditProgress?.takeIf{it.scope==scope&&clock>=it.startedAt&&clock-it.startedAt<24*60*60_000L}
        val progress:AuditProgress=previous?:run{
            completedAuditStart=null;completedAuditRevision=null
            if(stopped())return@synchronized interrupted()
            val status=repo.observationReconcileStatus()
            if(try{auditAuthority(localStop)?.scope!=scope}catch(_:Exception){true})return@synchronized interrupted()
            if(status.hasPending)return@synchronized Audit.RETRY
            if(status.hasUnmatchedCanonical)return@synchronized Audit.UNCONFIRMED
            if(status.recordedCount !in 0..16_000||status.hasRecorded!=(status.recordedCount>0))return@synchronized Audit.UNCONFIRMED
            auditProgress=AuditProgress(scope,0,false,clock,status.revision,status.recordedCount)
            return@synchronized Audit.MORE
        }
        if(progress.cloudComplete){
            if(stopped())return@synchronized interrupted()
            val status=repo.observationReconcileStatus()
            if(try{auditAuthority(localStop)?.scope!=scope}catch(_:Exception){true})return@synchronized interrupted()
            auditProgress=null
            if(status.hasPending||status.hasUnmatchedCanonical||status.revision!=progress.collectionRevision||status.recordedCount!=progress.recordedCount)
                return@synchronized Audit.RETRY
            if(status.hasRecorded!=(status.recordedCount>0)||progress.cloudTotal!=status.recordedCount||
                progress.cloudIds.size!=status.recordedCount||progress.cloudIds!=progress.sourceIds)
                return@synchronized Audit.UNCONFIRMED
            completedAuditStart=progress.startedAt
            completedAuditRevision=progress.collectionRevision
            return@synchronized Audit.COMPLETE
        }
        if(progress.phoneComplete){
            if(stopped()||try{auditAuthority(stopped)?.scope!=scope}catch(_:Exception){true}){
                return@synchronized interrupted()
            }
            val page=try{repo.observationPage(cursor=progress.cloudCursor,limit=100)}catch(error:ApiFailure){
                if(error.code in setOf("cursor_scope_changed","cursor_expired","invalid_cursor")){
                    auditProgress=null;return@synchronized Audit.RETRY
                }
                throw error
            }
            val after=try{auditAuthority(localStop)}catch(_:Exception){null}
            if(after?.scope!=scope)return@synchronized interrupted()
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
            auditProgress=progress.copy(cloudRevision=page.revision,cloudTotal=total,cloudIds=collected,cloudComplete=true)
            return@synchronized Audit.MORE
        }
        fun open() = queryObservationInbox(app, progress.last, authority.profile.receipt.senders)
        fun takePage(checkStop:()->Boolean=stopped):List<AuditRow>? {
            val cursor=open()?:return null;val rows=mutableListOf<AuditRow>();var previous=progress.last
            cursor.use{
                val id=it.getColumnIndexOrThrow("_id");val date=it.getColumnIndexOrThrow("date")
                val sender=it.getColumnIndexOrThrow("address");val body=it.getColumnIndexOrThrow("body")
                val sent=it.getColumnIndex("date_sent");val sub=it.getColumnIndex("sub_id")
                while(rows.size<AUDIT_PAGE&&it.moveToNext()){
                    if(checkStop()||it.isNull(id)||it.isNull(date))return null
                    val rowId=it.getLong(id);val received=it.getLong(date)
                    if(rowId<=previous||received<=0)return null
                    rows.add(AuditRow(rowId,received,if(it.isNull(sender))"" else it.getString(sender),
                        if(it.isNull(body))"" else it.getString(body),if(sent<0||it.isNull(sent))null else it.getLong(sent).takeIf{v->v>0},
                        if(sub<0||it.isNull(sub))null else it.getInt(sub).takeIf{v->v>=0}));previous=rowId
                }
            }
            return rows
        }
        val rows=try{takePage()}catch(_:Exception){null}?:return@synchronized interrupted()
        var uncertain=progress.unconfirmed;val requests=mutableListOf<ObservationReconcileRequest>()
        val decisions=mutableMapOf<Long,ObservationLegacyOwnership.Decision>()
        for(row in rows){
            if(authority.profile.receipt.senders.none{it.equals(row.sender,ignoreCase=true)})continue
            if(!ObservationCandidate.accepts(row.sender,row.body,authority.profile.receipt)){uncertain=true;continue}
            val key=heldInboxSourceKey(authority.device,owner.collectionId,row.id,row.received)
            val decision=if(key in authority.held)ObservationLegacyOwnership.Decision.HOLD else
                ObservationLegacyOwnership.classify(app,owner,row.id,row.received,row.sender,row.body,row.sub)
            decisions[row.id]=decision
            // A held identity may be checked, but this never releases the hold
            // or creates a source when the read-only lookup is missing.
            requests.add(ObservationReconcileRequest(key,Values.sha256(row.body),row.sender,
                row.sent?.let{Instant.ofEpochMilli(it).toString()},Instant.ofEpochMilli(row.received).toString(),row.sub))
        }
        // One bounded request per page. A poison item leaves the whole page
        // unconfirmed while later pages can still be checked.
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
                List(items.size){null}
            }
        }
        val states=try{requests.chunked(4).flatMap{verify(it)}}catch(error:Exception){
            if(stopped()||error is AuditAuthorityChanged)return@synchronized interrupted()
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
        val after=try{auditAuthority(localStop)}catch(_:Exception){null}
        if(after?.scope!=scope||try{takePage(localStop)!=rows}catch(_:Exception){true})return@synchronized interrupted()
        for(row in rows){
            if(authority.profile.receipt.senders.none{it.equals(row.sender,ignoreCase=true)}||
                !ObservationCandidate.accepts(row.sender,row.body,authority.profile.receipt))continue
            val key=heldInboxSourceKey(authority.device,owner.collectionId,row.id,row.received)
            val before=decisions[row.id]?:run{auditProgress=null;return@synchronized Audit.BLOCKED}
            val now=if(key in after.held)ObservationLegacyOwnership.Decision.HOLD else
                ObservationLegacyOwnership.classify(app,owner,row.id,row.received,row.sender,row.body,row.sub)
            if(before!=now||ObservationInboxRevision.snapshot()!=scope.revision||localStop()){
                return@synchronized interrupted()
            }
        }
        if(try{auditAuthority(localStop)?.scope!=scope}catch(_:Exception){true}){
            return@synchronized interrupted()
        }
        val last=rows.lastOrNull()?.id?:progress.last
        if(rows.size<AUDIT_PAGE){
            if(uncertain){auditProgress=null;return@synchronized Audit.UNCONFIRMED}
            auditProgress=progress.copy(last=last,sourceIds=sourceIds,phoneComplete=true)
            return@synchronized Audit.MORE
        }
        auditProgress=progress.copy(last=last,unconfirmed=uncertain,sourceIds=sourceIds)
        Audit.MORE
    }
}

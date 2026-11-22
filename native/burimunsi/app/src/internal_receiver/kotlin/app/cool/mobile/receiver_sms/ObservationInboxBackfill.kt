package app.cool.mobile.receiver_sms

import android.content.Context
import app.cool.mobile.receiver_sms.ObservationRecovery.Backfill
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.ObservationConsentState
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.core.ObservationProfile
import rw.ikanisa.burimunsi.core.ObservationSessionOwner
import rw.ikanisa.burimunsi.core.ReceiptCandidate
import rw.ikanisa.burimunsi.core.Values
import rw.ikanisa.burimunsi.core.checkContract
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.storage.SecureStore
import java.time.Instant

/** Bounded migration for provider messages skipped by the original receipt classifier. */
internal class ObservationInboxBackfill(
    private val app: Context,
    private val config: ObservationConfigStore,
    private val heldInbox: ObservationHeldInbox,
    private val lock: Any,
) {
    private companion object {
        const val PAGE = 100
    }

    private data class BackfillCursor(val last:Long,val end:Long)

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
        val old = heldInbox.previousCursor(owner, fingerprint).profileLastId ?: 0L
        return BackfillCursor(0,old).also{saveBackfill(store,it)}
    }
    private fun advanceBackfill(session:ObservationSessionOwner,profile:ObservationProfile,
        consent:ObservationConsentState,control:ObservationConfigStore.Control,expected:BackfillCursor,next:Long):Boolean =
        NativeRepository.withObservationOwner(app,session){group,account->
            val owner=session.owner;val fingerprint=profile.fingerprint()
            if(owner!=ObservationOwner(group,account)||!observationInboxPermitted(app)||control.paused||config.controlState(owner)!=control||
                config.consent(owner)!=consent||!consent.canCapture(observationInboxPermitted(app))||
                config.profile(owner,System.currentTimeMillis())?.fingerprint()!=fingerprint)return@withObservationOwner false
            val store=backfillStore(owner,fingerprint)
            if(store.read()?.let(::parseBackfill)!=expected||next<=expected.last||next>expected.end)return@withObservationOwner false
            saveBackfill(store,expected.copy(last=next));true
        }?:false

    /** One-time bounded migration for messages the old incoming-only predicate
     * skipped. It never retries an older accepted receipt with a new request ID. */
    fun run(stopped: () -> Boolean):Backfill = synchronized(lock){
        if(stopped()||!observationInboxPermitted(app)||!ObservationLegacyOwnership.controlTransitionClear(app))return@synchronized Backfill.BLOCKED
        val session=NativeRepository.observationOwner(app)?:return@synchronized Backfill.BLOCKED
        val heldMode=try{NativeRepository.withObservationOwner(app,session){group,account->
            val owner=ObservationOwner(group,account);val profile=config.profile(owner,System.currentTimeMillis())
            if(profile?.legacyHold==null)null else heldInbox.holdsExisting(profile, group)
        }}catch(_:Exception){null}?:return@synchronized Backfill.BLOCKED
        if(heldMode)return@synchronized Backfill.COMPLETE
        val initial=try{NativeRepository.withObservationOwner(app,session){group,account->
            val owner=ObservationOwner(group,account);val profile=config.profile(owner,System.currentTimeMillis())
            val control=config.controlState(owner);val consent=config.consent(owner)
            if(control.paused||consent?.canCapture(observationInboxPermitted(app))!=true||profile==null||profile.legacyHold!=false)null
            else Triple(profile,backfillCursor(owner,profile.fingerprint()),consent to control)
        }}catch(_:Exception){null}?:return@synchronized Backfill.BLOCKED
        val owner=session.owner;val profile=initial.first;val fingerprint=profile.fingerprint();var position=initial.second
        val (consent,control)=initial.third
        if(position.last==position.end)return@synchronized Backfill.COMPLETE
        val cursor = queryObservationInbox(app, position.last, profile.receipt.senders, through = position.end)
            ?: return@synchronized Backfill.BLOCKED
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
}

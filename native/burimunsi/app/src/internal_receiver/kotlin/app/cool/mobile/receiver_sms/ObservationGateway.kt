package app.cool.mobile.receiver_sms

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import app.cool.mobile.BuildConfig
import rw.ikanisa.burimunsi.core.GatewayStatus
import rw.ikanisa.burimunsi.core.ObservationJournal
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.core.QueuedObservationRow
import rw.ikanisa.burimunsi.core.QueuedObservationSnapshot
import rw.ikanisa.burimunsi.core.QueuedObservationPreview
import rw.ikanisa.burimunsi.core.SmsListContent
import rw.ikanisa.burimunsi.core.SmsListSearch
import rw.ikanisa.burimunsi.data.NativeRepository
import java.time.Instant

/** Local status and scheduling only; no SIM, wallet or payment is asserted. */
internal object ObservationGateway {
    private fun permitted(context:Context)=listOf(Manifest.permission.RECEIVE_SMS,Manifest.permission.READ_SMS).all{
        context.checkSelfPermission(it)==PackageManager.PERMISSION_GRANTED
    }
    /** The bounded preview is local only; raw bodies and search text never leave this adapter. */
    fun queued(context:Context,query:String):QueuedObservationSnapshot? {
        if(BuildConfig.IS_QUALIFICATION||query.length>80||query.any{it.isISOControl()})return null
        val session=NativeRepository.observationOwner(context)?:return null
        return NativeRepository.withObservationOwner(context,session){group,account->
            if(!permitted(context))return@withObservationOwner null
            val pending=ObservationJournal(ObservationStateStore(context)).pendingSnapshot(ObservationOwner(group,account))
            val rows=pending.entries.filter{entry->
                SmsListSearch.matches(entry.observation.requestId,SmsListContent(entry.observation.rawSender,entry.observation.rawBody),query)
            }.map{entry->
                val value=entry.observation
                QueuedObservationRow(value.requestId,value.rawSender,value.inboxReceivedAt?:value.capturedAt,QueuedObservationPreview.from(value.rawBody))
            }
                .sortedWith(compareByDescending<QueuedObservationRow>{Instant.parse(it.at)}.thenBy{it.id})
            if(!permitted(context))null else QueuedObservationSnapshot(session,pending.revision,rows)
        }
    }
    /** Session -> journal lock order matches capture and acknowledgement. */
    fun publishQueued(context:Context,snapshot:QueuedObservationSnapshot,publish:()->Unit):Boolean =
        NativeRepository.withObservationOwner(context,snapshot.session){_,_->
            if(!permitted(context))false else ObservationJournal(ObservationStateStore(context)).ifRevision(snapshot.revision){
                if(!permitted(context))false else{publish();true}
            }?:false
        }?:false
    fun start(context:Context) {
        if(!BuildConfig.IS_QUALIFICATION&&NativeRepository.observationOwner(context)!=null)
            ObservationBackground.ensure(context.applicationContext)
    }
    fun sync(context:Context) {
        check(!BuildConfig.IS_QUALIFICATION&&NativeRepository.observationOwner(context)!=null){"Current administrator session required"}
        ObservationBackground.ensure(context.applicationContext)
        ObservationBackground.signal(context.applicationContext)
    }
    fun setPaused(context:Context,paused:Boolean) {
        withControl(context){owner,config->config.setPaused(owner,paused)}
    }
    /** Caller may hold the legacy receiver lock; the session lock is acquired second. */
    fun <T> withControl(context:Context,action:(ObservationOwner,ObservationConfigStore)->T):T {
        check(!BuildConfig.IS_QUALIFICATION){"Offline qualification only"}
        return try{
            NativeRepository.withObservationOwner(context){group,account->
                action(ObservationOwner(group,account),ObservationConfigStore(context))
            }?:error("Current administrator session required")
        }finally{
            // A partial protected write still requires consent reconciliation.
            // Persisted periodic recovery remains the fallback after process death.
            if(NativeRepository.observationOwner(context)!=null)
                try{ObservationBackground.ensure(context.applicationContext)}catch(_:Exception){}
        }
    }
    fun status(context:Context):GatewayStatus {
        if(BuildConfig.IS_QUALIFICATION)return GatewayStatus(false,false,null,0,null,null,null,"qualification_offline",observationMode=true)
        return NativeRepository.withObservationOwner(context){group,account->
            val owner=ObservationOwner(group,account);val config=ObservationConfigStore(context)
            val paused=config.paused(owner)
            val permitted=listOf(Manifest.permission.RECEIVE_SMS,Manifest.permission.READ_SMS).all{
                context.checkSelfPermission(it)==PackageManager.PERMISSION_GRANTED
            }
            val consent=config.consent(owner)
            val profile=config.profile(owner,System.currentTimeMillis())
            val pending=ObservationJournal(ObservationStateStore(context)).pending(owner).size
            val problem=when {
                !permitted->"permission_required"
                paused->"observation_paused"
                consent?.canCapture(true)!=true||profile==null->"observation_waiting"
                else->null
            }
            GatewayStatus(true,!paused,null,pending,null,null,null,problem,
                approvedSenders=profile?.receipt?.senders?.sorted(),observationMode=true)
        }?:GatewayStatus(false,false,null,0,null,null,null,"authorization_required",observationMode=true)
    }
}

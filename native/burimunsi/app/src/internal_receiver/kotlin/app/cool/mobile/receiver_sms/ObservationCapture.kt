package app.cool.mobile.receiver_sms

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings
import app.cool.mobile.BuildConfig
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.NativeRepository
import java.time.Instant
import java.util.UUID

/** Stores locally filtered inbox candidates; no wallet or completeness is inferred. */
internal object ObservationCapture {
    enum class Result { STORED, DUPLICATE, FILTERED, FULL, UNAVAILABLE }
    private fun permitted(context:Context)=context.checkSelfPermission(Manifest.permission.READ_SMS)==PackageManager.PERMISSION_GRANTED&&
        context.checkSelfPermission(Manifest.permission.RECEIVE_SMS)==PackageManager.PERMISSION_GRANTED
    fun candidate(context:Context,session:ObservationSessionOwner,profileFingerprint:String,sender:String,body:String):Boolean? {
        if(BuildConfig.IS_QUALIFICATION||!BuildConfig.IS_GATEWAY||!permitted(context))return null
        val app=context.applicationContext
        return try{NativeRepository.withObservationOwner(app,session){group,account->
            val owner=ObservationOwner(group,account);val config=ObservationConfigStore(app)
            if(config.paused(owner)||config.consent(owner)?.canCapture(permitted(app))!=true)return@withObservationOwner null
            val profile=config.profile(owner,System.currentTimeMillis())?:return@withObservationOwner null
            if(profile.fingerprint()!=profileFingerprint)return@withObservationOwner null
            ObservationCandidate.accepts(sender,body,profile.receipt)
        }}catch(_:Exception){null}
    }
    fun retain(context:Context,session:ObservationSessionOwner,profileFingerprint:String,stableSourceId:String,sender:String,body:String,mode:String,complete:Boolean,
        serviceCentreAt:String?,inboxReceivedAt:String?,subscriptionId:Int?):Result {
        if(BuildConfig.IS_QUALIFICATION||!BuildConfig.IS_GATEWAY||!permitted(context))return Result.UNAVAILABLE
        val rowId=stableSourceId.takeIf{Regex("inbox:[1-9][0-9]{0,18}").matches(it)}
            ?.substringAfter(':')?.toLongOrNull()?:return Result.UNAVAILABLE
        val app=context.applicationContext
        // Read the gateway identity before the session lock to keep lock ordering consistent.
        val installation=try{MomoGatewayStore(app).existingInstallationId()}catch(_:Exception){null}?:return Result.UNAVAILABLE
        return try{NativeRepository.withObservationOwner(app,session){collection,account->
            val owner=ObservationOwner(collection,account);val config=ObservationConfigStore(app);val now=System.currentTimeMillis()
            val consent=config.consent(owner)?:return@withObservationOwner Result.UNAVAILABLE
            if(config.paused(owner)||!consent.canCapture(permitted(app)))return@withObservationOwner Result.UNAVAILABLE
            val profile=config.profile(owner,now)?:return@withObservationOwner Result.UNAVAILABLE
            if(profile.fingerprint()!=profileFingerprint)return@withObservationOwner Result.UNAVAILABLE
            val sourceKey=ObservationSourceIdentity.inbox(installation,owner,rowId,inboxReceivedAt)
            val androidId=Settings.Secure.getString(app.contentResolver,Settings.Secure.ANDROID_ID)?:return@withObservationOwner Result.UNAVAILABLE
            val stableKey=ObservationSourceIdentity.reinstallStable(androidId,collection,rowId,inboxReceivedAt?:return@withObservationOwner Result.UNAVAILABLE)
            val item=SmsObservation(UUID.randomUUID().toString(),sender,body,mode,complete,
                Instant.ofEpochMilli(now).toString(),serviceCentreAt,inboxReceivedAt,subscriptionId,stableKey)
            if(!ObservationCandidate.accepts(sender,body,profile.receipt))return@withObservationOwner Result.FILTERED
            if(!item.valid(profile,now))return@withObservationOwner Result.UNAVAILABLE
            val journal=ObservationJournal(ObservationStateStore(app))
            val stored=ObservationConsent.whilePermitted(consent,{permitted(app)&&!config.paused(owner)}){
                journal.append(owner,sourceKey,rowId,item,profile,now)
            }?:return@withObservationOwner Result.UNAVAILABLE
            // The existing inbox request remains unchanged. Optional local PDU evidence
            // attaches only to that durable identity and cannot block incomplete sync.
            if(stored!=ObservationAppend.FULL&&permitted(app)&&!config.paused(owner))try{
                val seen=journal.seen(owner,sourceKey,rowId,Values.sha256(body))
                val received=inboxReceivedAt?.let{Instant.parse(it).toEpochMilli()}
                val sent=serviceCentreAt?.let{Instant.parse(it).toEpochMilli()}
                if(seen!=null&&received!=null){
                    val inbox=PduInboxCorrelation.inbox(seen.requestId,owner,installation,profile,now,rowId,sender,body,sent,received,subscriptionId)
                    if(inbox!=null&&permitted(app)&&!config.paused(owner))PduCorrelationStore(app).recordIfRelevant(inbox)
                }
            }catch(_:Exception){/* The original unverified observation remains queued. */}
            when(stored){
                ObservationAppend.STORED->Result.STORED;ObservationAppend.DUPLICATE->Result.DUPLICATE;ObservationAppend.FULL->Result.FULL
            }
        }?:Result.UNAVAILABLE}catch(_:Exception){Result.UNAVAILABLE}
    }
    /** Repair the inbox-first race without changing or resending the original observation. */
    fun correlateExisting(context:Context,session:ObservationSessionOwner,profileFingerprint:String,rowId:Long,sender:String,body:String,
        serviceCentreMs:Long?,receivedMs:Long,subscriptionId:Int?):Boolean {
        if(BuildConfig.IS_QUALIFICATION||!BuildConfig.IS_GATEWAY||!permitted(context)||rowId<=0)return false
        val app=context.applicationContext
        val installation=try{MomoGatewayStore(app).existingInstallationId()}catch(_:Exception){null}?:return false
        return try{NativeRepository.withObservationOwner(app,session){group,account->
            val owner=ObservationOwner(group,account);val config=ObservationConfigStore(app);val now=System.currentTimeMillis()
            val control=config.controlState(owner);val consent=config.consent(owner)?:return@withObservationOwner false
            val profile=config.profile(owner,now)?:return@withObservationOwner false
            if(control.paused||!consent.canCapture(permitted(app))||profile.fingerprint()!=profileFingerprint)return@withObservationOwner false
            val key=ObservationSourceIdentity.inbox(installation,owner,rowId,Instant.ofEpochMilli(receivedMs).toString())
            val seen=try{ObservationJournal(ObservationStateStore(app)).seen(owner,key,rowId,Values.sha256(body))}catch(_:Exception){null}
            val evidence=PduInboxCorrelation.inbox(seen?.requestId?:UUID.randomUUID().toString(),owner,installation,profile,now,rowId,
                sender,body,serviceCentreMs,receivedMs,subscriptionId)?:return@withObservationOwner false
            if(!permitted(app)||config.controlState(owner)!=control||config.consent(owner)!=consent||
                config.profile(owner,System.currentTimeMillis())?.fingerprint()!=profileFingerprint)return@withObservationOwner false
            val store=PduCorrelationStore(app)
            if(seen==null)store.holdIfUnretained(evidence) else store.recordIfRelevant(evidence)!=CorrelationWrite.FULL
        }?:false}catch(_:Exception){false}
    }
}

package app.cool.mobile.receiver_sms

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import app.cool.mobile.BuildConfig
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.data.ObservationUploadUnresolved
import app.cool.mobile.receiver_sms.ObservationSyncDiagnostics.Fence
import app.cool.mobile.receiver_sms.ObservationSyncDiagnostics.Phase

/** Scheduled receiver worker; each cycle requires the current authenticated owner. */
internal class ObservationCoordinator(context:Context,private val repository:NativeRepository,
    private val diagnostic:ObservationSyncDiagnostics.Cycle?=null) {
    private val app=context.applicationContext
    private val config=ObservationConfigStore(app)
    private val journal=ObservationJournal(ObservationStateStore(app))
    private fun permitted()=app.checkSelfPermission(Manifest.permission.READ_SMS)==PackageManager.PERMISSION_GRANTED&&
        app.checkSelfPermission(Manifest.permission.RECEIVE_SMS)==PackageManager.PERMISSION_GRANTED
    private fun <T> owned(session:ObservationSessionOwner,action:()->T):T? =
        NativeRepository.withObservationOwner(app,session){_,_->action()}
    private fun fail(fence:Fence):Boolean {diagnostic?.reject(fence);return false}
    private fun recordError(error:Exception){diagnostic?.error(ObservationSyncDiagnostics.errorKind(error))}
    private fun currentControls(session:ObservationSessionOwner,control:ObservationConfigStore.Control,
        consent:ObservationConsentState?,allowed:Boolean):Boolean = when {
        config.controlState(session.owner)!=control->fail(Fence.CONTROL_CHANGED)
        config.consent(session.owner)!=consent->fail(Fence.CONSENT_CHANGED)
        (permitted()&&!config.paused(session.owner))!=allowed->fail(Fence.CAPTURE_AUTHORITY_CHANGED)
        else->true
    }
    private fun uploadAllowed(session:ObservationSessionOwner,stopped:()->Boolean):Boolean {
        if(stopped())return fail(Fence.STOPPED)
        if(!permitted())return fail(Fence.PERMISSION_REQUIRED)
        if(!ObservationLegacyOwnership.controlTransitionClear(app))return fail(Fence.CONTROL_TRANSITION)
        return owned(session){
            when {
                config.paused(session.owner)->fail(Fence.PAUSED)
                config.consent(session.owner)?.canCapture(permitted())!=true->fail(Fence.CONSENT_NOT_CAPTURING)
                else->true
            }
        }?:fail(Fence.OWNER_CHANGED)
    }
    private fun authorityDenied(session:ObservationSessionOwner,error:Exception):Boolean {
        if(error !is ApiFailure||error.status !in setOf(401,403))return false
        val owner=session.owner
        runCatching{owned(session){config.consent(owner)?.let{config.saveConsent(owner,it.copy(confirmed=false))}}}
        return true
    }

    /** Persist each permission decision before dispatch; an old reply cannot confirm a newer decision. */
    private fun reconcile(session:ObservationSessionOwner,stopped:()->Boolean):Boolean {
        diagnostic?.phase(Phase.CONSENT_LOCAL)
        if(stopped())return fail(Fence.STOPPED)
        if(!ObservationLegacyOwnership.controlTransitionClear(app))return fail(Fence.CONTROL_TRANSITION)
        val owner=session.owner
        var local=try{owned(session){config.consent(owner)}}catch(error:Exception){recordError(error);return fail(Fence.CONSENT_READ_FAILED)}
        val beforeControl=owned(session){config.controlState(owner)}?:return fail(Fence.OWNER_CHANGED)
        val before=owned(session){permitted()&&!config.paused(owner)}?:return fail(Fence.OWNER_CHANGED)
        if(local!=null){
            val next=ObservationConsent.reconcile(local,null,before)?:return fail(Fence.CONSENT_RECONCILE_REJECTED)
            if(next!=local){
                if(owned(session){
                    if(!currentControls(session,beforeControl,local,before))false
                    else{config.saveConsent(owner,next);true}
                }!=true)return fail(Fence.OWNER_CHANGED)
                local=next
            }
        }
        if(!ObservationLegacyOwnership.controlTransitionClear(app))return fail(Fence.CONTROL_TRANSITION)
        diagnostic?.phase(Phase.CONSENT_READ)
        val server=try{repository.observationConsent()}catch(error:Exception){recordError(error);if(authorityDenied(session,error))return fail(Fence.AUTHORITY_DENIED);null}
        if(stopped())return fail(Fence.STOPPED)
        diagnostic?.phase(Phase.CONSENT_MERGE)
        val actualControl=owned(session){config.controlState(owner)}?:return fail(Fence.OWNER_CHANGED)
        val actual=owned(session){permitted()&&!config.paused(owner)}?:return fail(Fence.OWNER_CHANGED)
        val merged=ObservationConsent.reconcile(local,server,actual)?:return fail(Fence.CONSENT_RECONCILE_REJECTED)
        if(owned(session){
            if(!currentControls(session,actualControl,local,actual))false
            else{config.saveConsent(owner,merged);true}
        }!=true)return fail(Fence.OWNER_CHANGED)
        if(!merged.confirmed){
            if(owned(session){currentControls(session,actualControl,merged,actual)}!=true)return fail(Fence.OWNER_CHANGED)
            if(!ObservationLegacyOwnership.controlTransitionClear(app))return fail(Fence.CONTROL_TRANSITION)
            diagnostic?.phase(Phase.CONSENT_WRITE)
            val echo=try{repository.setObservationConsent(merged.revision)}catch(error:Exception){
                recordError(error);return fail(if(authorityDenied(session,error))Fence.AUTHORITY_DENIED else Fence.CONSENT_WRITE_FAILED)
            }
            if(stopped())return fail(Fence.STOPPED)
            val confirmed=owned(session){
                val current=config.consent(owner)?:run{fail(Fence.CONSENT_MISSING);return@owned null}
                if(config.controlState(owner)!=actualControl){fail(Fence.CONTROL_CHANGED);return@owned null}
                if((permitted()&&!config.paused(owner))!=actual){fail(Fence.CAPTURE_AUTHORITY_CHANGED);return@owned null}
                if(current!=merged){fail(Fence.CONSENT_CHANGED);return@owned null}
                val accepted=ObservationConsent.acknowledge(current,echo)?:run{fail(Fence.CONSENT_ACK_REJECTED);return@owned null}
                config.saveConsent(owner,accepted);accepted
            }?:return fail(Fence.OWNER_CHANGED)
            return confirmed.canCapture(actual)||fail(Fence.CONSENT_NOT_CAPTURING)
        }
        return merged.canCapture(actual)||fail(Fence.CONSENT_NOT_CAPTURING)
    }

    /** False means leave all queued evidence intact and retry after authority/network recovery. */
    fun cycle(stopped:()->Boolean={false}):Boolean {
        diagnostic?.coordinatorStarted()
        diagnostic?.phase(Phase.COORDINATOR_START)
        var completed=false
        try{completed=coordinate(stopped);return completed}
        catch(error:Exception){recordError(error);fail(Fence.EXCEPTION);throw error}
        finally{diagnostic?.coordinatorFinished(completed)}
    }
    private fun coordinate(stopped:()->Boolean):Boolean {
        if(stopped())return fail(Fence.STOPPED)
        if(BuildConfig.IS_QUALIFICATION)return fail(Fence.QUALIFICATION)
        if(!BuildConfig.IS_GATEWAY)return fail(Fence.NOT_GATEWAY)
        if(!ObservationLegacyOwnership.controlTransitionClear(app))return fail(Fence.CONTROL_TRANSITION)
        val session=NativeRepository.observationOwner(app)?:return fail(Fence.OWNER_UNAVAILABLE)
        val current=session.owner
        if(!reconcile(session,stopped))return false
        if(!ObservationLegacyOwnership.controlTransitionClear(app))return fail(Fence.CONTROL_TRANSITION)
        diagnostic?.phase(Phase.PROFILE_READ)
        val profile=try{repository.observationProfile()}catch(error:Exception){recordError(error);if(authorityDenied(session,error))return fail(Fence.AUTHORITY_DENIED);null}
        if(stopped())return fail(Fence.STOPPED)
        diagnostic?.phase(Phase.PROFILE_SAVE)
        if(profile!=null&&owned(session){config.saveProfile(current,profile,System.currentTimeMillis());true}!=true)return fail(Fence.OWNER_CHANGED)
        diagnostic?.phase(Phase.PROFILE_VALIDATE)
        val currentProfile=owned(session){config.profile(current,System.currentTimeMillis())!=null}?:return fail(Fence.OWNER_CHANGED)
        if(!currentProfile)return fail(Fence.PROFILE_UNAVAILABLE)
        diagnostic?.phase(Phase.JOURNAL_READ)
        val entries=owned(session){journal.pending(current)}?:return fail(Fence.OWNER_CHANGED)
        diagnostic?.queued(entries.size)
        var unresolved=0;var laterAttempts=0
        for(entry in entries){
            diagnostic?.phase(Phase.UPLOAD_GUARD)
            if(unresolved>0&&laterAttempts>=2)return fail(Fence.UNRESOLVED_LATER_LIMIT)
            if(!uploadAllowed(session,stopped))return false
            diagnostic?.phase(Phase.UPLOAD)
            diagnostic?.attempted()
            val ack=try{repository.submitObservation(entry.observation)}catch(error:Exception){
                if(error is ObservationUploadUnresolved&&error.requestId==entry.observation.requestId){
                    diagnostic?.phase(Phase.UPLOAD_UNRESOLVED)
                    if(!uploadAllowed(session,stopped))return false
                    if(unresolved>=16)return fail(Fence.UNRESOLVED_LIMIT)
                    unresolved++;diagnostic?.unresolved();continue
                }
                recordError(error);return fail(if(authorityDenied(session,error))Fence.AUTHORITY_DENIED else Fence.UPLOAD_FAILED)
            }
            if(unresolved>0)laterAttempts++
            diagnostic?.phase(Phase.ACKNOWLEDGE)
            if(stopped())return fail(Fence.STOPPED) // Preserve the exact request until a later durable acknowledgement.
            if(!ObservationLegacyOwnership.controlTransitionClear(app))return fail(Fence.CONTROL_TRANSITION)
            val removed=owned(session){
                when {
                    config.paused(current)->fail(Fence.PAUSED)
                    !permitted()->fail(Fence.PERMISSION_REQUIRED)
                    config.consent(current)?.canCapture(permitted())!=true->fail(Fence.CONSENT_NOT_CAPTURING)
                    else->journal.acknowledge(current,entry.observation.requestId,ack)||fail(Fence.ACK_REJECTED)
                }
            }?:return fail(Fence.OWNER_CHANGED)
            if(!removed)return false
            diagnostic?.acknowledged()
        }
        return unresolved==0||fail(Fence.UNRESOLVED_REMAIN)
    }
}

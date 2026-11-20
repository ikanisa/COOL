package app.cool.mobile.receiver_sms

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import app.cool.mobile.BuildConfig
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.core.ObservationSessionOwner
import rw.ikanisa.burimunsi.data.NativeRepository
import java.util.UUID

/** Local evidence only: a complete PDU is not a carrier or wallet attestation. */
internal object ObservationPduCapture {
    private fun permitted(context:Context)=listOf(Manifest.permission.READ_SMS,Manifest.permission.RECEIVE_SMS).all{
        context.checkSelfPermission(it)==PackageManager.PERMISSION_GRANTED
    }
    fun record(context:Context,session:ObservationSessionOwner,at:Long,subscription:Int?,format:String?,
        senders:List<String>,times:List<Long>,bodies:List<String?>,pdus:List<ByteArray>):Boolean {
        if(BuildConfig.IS_QUALIFICATION||!BuildConfig.IS_GATEWAY||!permitted(context))return false
        val app=context.applicationContext;val gateway=MomoGatewayStore(app)
        return try{gateway.withObservationState legacy@{state->
            // A retained paired receiver has its own source and queue. Never adopt it here.
            if(state?.has("binding")==true||state?.has("control_transition")==true||
                state?.opt("receiver_retired")==true||state?.opt("retirement_pending")==true)return@legacy false
            val installation=gateway.existingInstallationId()?:return@legacy false
            NativeRepository.withObservationOwner(app,session) owner@{group,account->
                val owner=ObservationOwner(group,account);val config=ObservationConfigStore(app);val now=System.currentTimeMillis()
                val control=config.controlState(owner);val consent=config.consent(owner)?:return@owner false
                val profile=config.profile(owner,now)?:return@owner false
                if(control.paused||!consent.canCapture(permitted(app))||at<=0||at>now+300_000L)return@owner false
                val evidence=PduInboxCorrelation.capture(UUID.randomUUID().toString(),owner,installation,profile,at,
                    subscription,format,senders,times,bodies,pdus)?:return@owner false
                if(!permitted(app)||config.controlState(owner)!=control||config.consent(owner)!=consent||
                    config.profile(owner,System.currentTimeMillis())?.fingerprint()!=profile.fingerprint())return@owner false
                PduCorrelationStore(app).record(evidence)==CorrelationWrite.STORED
            }?:false
        }}catch(_:Exception){false}
    }
}

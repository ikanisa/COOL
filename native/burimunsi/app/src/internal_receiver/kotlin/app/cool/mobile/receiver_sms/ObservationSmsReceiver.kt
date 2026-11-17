package app.cool.mobile.receiver_sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import app.cool.mobile.BuildConfig
import rw.ikanisa.burimunsi.data.NativeRepository
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Retain candidate multipart evidence locally; inbox recovery still owns the request. */
class ObservationSmsReceiver:BroadcastReceiver() {
    companion object {
        private val busy=AtomicBoolean(false)
        private val worker=Executors.newSingleThreadExecutor{task->Thread(task,"burimunsi-pdu-capture").apply{isDaemon=true}}
    }
    override fun onReceive(context:Context,intent:Intent){
        if(BuildConfig.IS_QUALIFICATION||!BuildConfig.IS_GATEWAY||intent.action!=Telephony.Sms.Intents.SMS_RECEIVED_ACTION)return
        // SMS itself is not assumed to grant foreground-start permission. The
        // supervisor starts only from a visible task or an OS/user exemption.
        runCatching{BuriContinuousSupervisor.start(context.applicationContext)}
        // The default SMS app may insert the row after this broadcast. A delayed
        // local scan and periodic recovery use the stable inbox row identity.
        try{ObservationBackground.signalLocal(context.applicationContext,2_000)}catch(_:Exception){/* Periodic recovery remains scheduled. */}
        val app=context.applicationContext;val at=System.currentTimeMillis()
        val session=try{NativeRepository.observationOwner(app)}catch(_:Exception){null}?:return
        if(!busy.compareAndSet(false,true))return // Inbox catch-up remains available.
        val pending=try{goAsync()}catch(_:RuntimeException){busy.set(false);return}
        try{worker.execute{
            try{
                val messages=Telephony.Sms.Intents.getMessagesFromIntent(intent)
                @Suppress("DEPRECATION") val raw=intent.extras?.get("pdus") as? Array<*>
                val pdus=raw?.mapNotNull{it as? ByteArray}
                val subscription=listOf("subscription","subscription_id","android.telephony.extra.SUBSCRIPTION_INDEX")
                    .firstNotNullOfOrNull{key->if(intent.hasExtra(key))intent.getIntExtra(key,-1).takeIf{it>=0}else null}
                if(pdus!=null&&messages.size==pdus.size&&raw.size==pdus.size&&messages.isNotEmpty())
                    ObservationPduCapture.record(app,session,at,subscription,intent.getStringExtra("format"),
                        messages.map{it.originatingAddress.orEmpty()},messages.map{it.timestampMillis},messages.map{it.messageBody},pdus)
            }catch(_:Exception){/* The inbox path preserves an unverified candidate. */}
            finally{
                busy.set(false)
                try{ObservationBackground.signalLocal(app,2_000)}catch(_:Exception){}
                pending.finish()
            }
        }}catch(_:RuntimeException){busy.set(false);pending.finish()}
    }
}

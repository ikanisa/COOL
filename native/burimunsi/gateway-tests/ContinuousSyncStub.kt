package app.cool.mobile.receiver_sms
import android.content.Context
import rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth
/** No Android service is started by host gateway/capture adapter tests. */
object BuriContinuousSupervisor {
 fun foregroundChanged(context:Context,resumed:Boolean){}
 fun health()=ContinuousReceiverHealth(supported=true)
 fun stop(context:Context){}
 fun halt(context:Context,problem:String){}
 fun recover(context:Context,bootOrReplacement:Boolean=false){}
 fun start(context:Context){}
}

package app.cool.mobile.receiver_sms

import android.content.Context
import org.json.JSONObject

object CaptureFixture {
    var result=SmsQueueStore.AppendResult.STORED
    var active=true;var retain=true;var metadataFailure=false;var scheduleFailure=false
    var finished=0;var signalCalls=0;var scheduleCalls=0
    val queue=mutableListOf<JSONObject>();val pendingJobs=mutableSetOf<Int>()
    var gate=MomoGatewayWakeupGate()
    fun reset(){result=SmsQueueStore.AppendResult.STORED;active=true;retain=true;metadataFailure=false;scheduleFailure=false;
        finished=0;signalCalls=0;scheduleCalls=0;queue.clear();pendingJobs.clear();gate=MomoGatewayWakeupGate()}
}
class MomoGatewayStore(context:Context){
    fun active()=CaptureFixture.active
    fun read()=JSONObject().put("binding",JSONObject().put("owner_user_id","synthetic-owner").put("id","synthetic-binding")
        .put("version",1).put("subscription_id",7))
    fun installationId()="synthetic-installation"
    fun update(action:(JSONObject)->Unit){if(CaptureFixture.metadataFailure)error("synthetic metadata failure");action(JSONObject())}
    fun <T> withCurrentBinding(binding:JSONObject,action:()->T):T?=if(active())action()else null
    fun park(reason:String){}
}
class SmsQueueStore(context:Context){
    enum class AppendResult { STORED,DUPLICATE,FULL,RESERVED,DISABLED,FAILED }
    fun activeCaptureOwner():String?=null
    fun appendIfCapacity(value:JSONObject,max:Int):AppendResult {
        if(CaptureFixture.result==AppendResult.STORED)CaptureFixture.queue.add(value)
        return CaptureFixture.result
    }
}
object SmsQueueWorker { fun executeCapture(action:()->Unit)=action() }
object SmsQueueEventBus { fun notifyQueueChanged(){} }
object MomoGatewayJobs {
    fun signal(context:Context){
        CaptureFixture.signalCalls++
        CaptureFixture.gate.signal {
            if(CaptureFixture.scheduleFailure)error("synthetic scheduling failure")
            CaptureFixture.scheduleCalls++
            CaptureFixture.pendingJobs.add(904_601) // Fake the real stable JobScheduler ID.
        }
    }
}
object MomoGatewayPolicy {
    const val MAX_PENDING=1000
    fun memberCaptureSupported(flavor:String)=false
    fun captureId(installation:String,binding:String,sender:String,body:String,received:Long,subscription:Int?)="synthetic-id"
    fun sourceResolved(selected:Int?,actual:Int?,multiple:Boolean)=selected==actual
}
class MomoGatewayRecovery(context:Context){fun multipleSims()=true}
fun JSONObject.optionalInt(key:String)=(opt(key) as? Int)
object MomoMultipartPolicy {
    data class Assembly(val body:String,val complete:Boolean)
    fun assemble(senders:List<String>,times:List<Long>,parts:List<String>,pdus:List<ByteArray?>,format:String?)=Assembly(parts.joinToString(""),true)
    fun memberCaptureEligible(sender:String,assembly:Assembly)=false
}
object BuriReceiverReliability { enum class Route { ACCEPT,OTHER_SIM,UNCERTAIN } }
object BuriCapturePolicy {
    fun senderAllowed(binding:JSONObject?,sender:String)=CaptureFixture.retain
    fun route(context:Context,binding:JSONObject?,subscription:Int?)=BuriReceiverReliability.Route.ACCEPT
    fun retain(context:Context,binding:JSONObject?,sender:String,body:String,subscription:Int?)=CaptureFixture.retain
}

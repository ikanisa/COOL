package app.cool.mobile.receiver_sms
import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
/** Explicit platform/queue/capture doubles. Actual GatewayFactory and pure
 * BuriReceiverReliability execute; this is not Android/SMS storage proof. */
object ReceiverFixture{
 val lock=Any();var state:JSONObject?=null;var stateUnavailable=false;var queued=0;var unreadable=false;var queueEnabled=true;var jobs=0;var subscriptions:Set<Int>?=setOf(3);var inboxLatest:Long?=null
 var retainedCaptureId:String?=null;var retainedBodyHash:String?=null
 val ownerLock=Any();var observationAccount="operator-1";var observationPaused=true
 var failMarkerWrite=false;var failMarkerClear=false;var failQueueEnable=false;var failQueueDisable=false
 var failObservationWrite=false;var failObservationAfterWrite=false
 var afterObservationControl:((Boolean)->Unit)?=null
 var afterSourceLookup:(()->Unit)?=null
 fun reset(){state=null;stateUnavailable=false;queued=0;unreadable=false;queueEnabled=true;jobs=0;subscriptions=setOf(3);inboxLatest=null;retainedCaptureId=null;retainedBodyHash=null;afterSourceLookup=null
  observationAccount="operator-1";observationPaused=true;failMarkerWrite=false;failMarkerClear=false;failQueueEnable=false;failQueueDisable=false;failObservationWrite=false;failObservationAfterWrite=false;afterObservationControl=null}
}
private fun fixtureCopy(value:Any?):Any?=when(value){
 is JSONObject->JSONObject().also{out->for(key in value.keys())out.put(key,fixtureCopy(value.opt(key)))}
 is JSONArray->JSONArray().also{out->for(i in 0 until value.length())out.put(fixtureCopy(value.get(i)))}
 else->value
}
class MomoGatewayStore(private val context:Context){
 fun installationId()="50000000-0000-4000-8000-000000000001"
 fun existingInstallationId()=installationId()
 fun <T> withReceiverState(action:(JSONObject)->T):T?=synchronized(ReceiverFixture.lock){read()?.let(action)}
 fun <T> withObservationState(action:(JSONObject?)->T):T=synchronized(ReceiverFixture.lock){action(read())}
 fun <T> withCurrentBinding(expected:JSONObject,action:()->T):T?=synchronized(ReceiverFixture.lock){
  if(!BuriCapturePolicy.uploadsAdmitted(context))return@synchronized null
  val state=read()?:return@synchronized null;val current=state.optJSONObject("binding")?:return@synchronized null
  if(!state.optBoolean("capture_enabled")||state.optString("reason") in setOf("authorization_required","permission_required")||
   !BuriReceiverReliability.bindingMatches(expected::opt,current::opt))return@synchronized null
  action()
 }
 fun read():JSONObject?=synchronized(ReceiverFixture.lock){check(!ReceiverFixture.stateUnavailable){"Synthetic unavailable gateway state"};ReceiverFixture.state}
 fun active()=BuriCapturePolicy.uploadsAdmitted(context)
 fun binding()=read()?.optJSONObject("binding")
 fun owner()=binding()?.getString("owner_user_id")?:""
 fun update(action:(JSONObject)->Unit)=synchronized(ReceiverFixture.lock){
  val current=ReceiverFixture.state?:error("Missing fixture");val before=fixtureCopy(current) as JSONObject;action(current)
  if(ReceiverFixture.failMarkerWrite&&!before.has("control_transition")&&current.has("control_transition")){
   ReceiverFixture.state=before;error("Synthetic marker write failure")
  }
  if(ReceiverFixture.failMarkerClear&&before.has("control_transition")&&!current.has("control_transition")){
   ReceiverFixture.state=before;error("Synthetic marker clear failure")
  }
 }
}
class SmsQueueStore(context:Context){
 fun queueMetadata(owner:String):Pair<Int,String?>{check(!ReceiverFixture.unreadable){"Synthetic unreadable ciphertext"};return ReceiverFixture.queued to null}
 fun disablePreservingQueue(owner:String):Boolean{if(ReceiverFixture.failQueueDisable)return false;ReceiverFixture.queueEnabled=false;return true}
 fun enableForOwner(owner:String):Boolean{if(ReceiverFixture.failQueueEnable)return false;ReceiverFixture.queueEnabled=true;return true}
 fun hasGatewaySource(owner:String,captureId:String,bindingId:String,bindingVersion:Int,bodyHash:String):Boolean{
  check(!ReceiverFixture.unreadable){"Synthetic unreadable ciphertext"}
  val matches=ReceiverFixture.retainedCaptureId==captureId&&ReceiverFixture.retainedBodyHash==bodyHash
  val callback=ReceiverFixture.afterSourceLookup;ReceiverFixture.afterSourceLookup=null;callback?.invoke()
  return matches
 }
}
object MomoGatewayJobs{fun ensure(context:Context){ReceiverFixture.jobs++};fun signal(context:Context){ReceiverFixture.jobs++}}
class MomoGatewayRecovery(context:Context){fun latestInboxId():Long?=ReceiverFixture.inboxLatest}
fun JSONObject.optionalInt(key:String):Int?=(opt(key) as? Int)?.takeIf{it>=0&&it!=Int.MAX_VALUE}

package app.cool.mobile.receiver_sms
import android.content.Context
import rw.ikanisa.burimunsi.core.GatewayStatus
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.core.QueuedObservationSnapshot

/** Scheduling/status doubles; real observation code has its own adapter tests. */
class ObservationConfigStore(context:Context){
 data class Control(val paused:Boolean)
 fun controlState(owner:ObservationOwner)=Control(ReceiverFixture.observationPaused)
 fun setPaused(owner:ObservationOwner,paused:Boolean){
  if(ReceiverFixture.failObservationWrite)error("Synthetic protected control failure")
  ReceiverFixture.observationPaused=paused
  ReceiverFixture.afterObservationControl?.invoke(paused)
  if(ReceiverFixture.failObservationAfterWrite)error("Synthetic partial protected control failure")
 }
}
object ObservationGateway{
 fun queued(context:Context,query:String):QueuedObservationSnapshot?=null
 fun publishQueued(context:Context,snapshot:QueuedObservationSnapshot,publish:()->Unit)=false
 fun start(context:Context){}
 fun sync(context:Context){if(ReceiverFixture.state?.has("binding")!=true)error("No signed-in synthetic observer")}
 fun <T> withControl(context:Context,action:(ObservationOwner,ObservationConfigStore)->T):T=
  synchronized(ReceiverFixture.ownerLock){
   if(ReceiverFixture.state?.has("binding")!=true)error("No signed-in synthetic observer")
   action(ObservationOwner("group-1",ReceiverFixture.observationAccount),ObservationConfigStore(context))
  }
 fun setPaused(context:Context,paused:Boolean){withControl(context){owner,config->config.setPaused(owner,paused)}}
 fun status(context:Context)=GatewayStatus(false,false,null,0,null,null,null,"authorization_required",observationMode=true)
}

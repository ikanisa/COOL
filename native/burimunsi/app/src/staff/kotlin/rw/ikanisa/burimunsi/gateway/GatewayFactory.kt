package rw.ikanisa.burimunsi.gateway

import android.content.Context
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.GatewayStatus
import rw.ikanisa.burimunsi.core.ReceiverRetirementAck
import rw.ikanisa.burimunsi.core.QueuedObservationSnapshot

object GatewayFactory {
    fun installationId(context:Context):String?=null
    fun create(context:Context,managedCollection:()->String?={null},pairGateway:(String,Boolean)->JSONObject={_,_->error("Sign in first")},
        retirementPending:()->Boolean={false},recoverRetirement:()->JSONObject?={null},authorizeControl:()->Boolean={false}):GatewayPort=object:GatewayPort {
        override fun bound()=false
        override fun status()=GatewayStatus(false,false,null,0,null,null,null,"not_available")
        override fun start()=Unit
        override fun setPaused(paused:Boolean):Unit=error("Gateway unavailable on Staff build")
        override fun pair(code:String):Unit=error("Gateway unavailable on Staff build")
        override fun sync():Unit=error("Gateway unavailable on Staff build")
        override fun replace(code:String):ReceiverRetirementAck=error("Gateway unavailable on Staff build")
        override fun retirementPending()=false
        override fun recoverRetirement():ReceiverRetirementAck?=null
        override fun requiredPermissions()=emptyArray<String>()
        override fun queuedObservations(query:String):QueuedObservationSnapshot?=null
        override fun publishQueued(snapshot:QueuedObservationSnapshot,publish:()->Unit)=false
    }
}

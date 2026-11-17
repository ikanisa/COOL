package rw.ikanisa.burimunsi.gateway

import rw.ikanisa.burimunsi.core.GatewayStatus
import rw.ikanisa.burimunsi.core.ReceiverRetirementAck
import rw.ikanisa.burimunsi.core.QueuedObservationSnapshot

/** Local execution health only. It is never a receipt or member-credit acknowledgement. */
data class ContinuousReceiverHealth(
    val supported:Boolean=false,
    val running:Boolean=false,
    val problem:String?=null,
    val lastCycleAt:Long?=null,
    /** Process-local monotonic start of the proof, never a wall-clock timestamp. */
    val proofStartedAtElapsed:Long?=null,
)

/** Implemented in flavor-specific code. Staff has no receiving implementation. */
interface GatewayPort {
    fun bound():Boolean
    fun status():GatewayStatus
    fun start()
    fun setPaused(paused:Boolean)
    fun pair(code:String)
    fun sync()
    fun replace(code:String):ReceiverRetirementAck
    fun retirementPending():Boolean
    fun recoverRetirement():ReceiverRetirementAck?
    fun requiredPermissions():Array<String>
    fun queuedObservations(query:String):QueuedObservationSnapshot?
    /** Publish only while the same session, permission and queue revision remain current. */
    fun publishQueued(snapshot:QueuedObservationSnapshot,publish:()->Unit):Boolean
    /** A background transition keeps authorized sync running; it grants no authority. */
    fun foregroundChanged(resumed:Boolean) {}
    fun continuousHealth():ContinuousReceiverHealth=ContinuousReceiverHealth()
    /** Stop the supervisor immediately, for example before explicit operator logout. */
    fun stopContinuous() {}
    /** Best-effort process recovery within Android's foreground-start restrictions. */
    fun recoverContinuous() {}
}

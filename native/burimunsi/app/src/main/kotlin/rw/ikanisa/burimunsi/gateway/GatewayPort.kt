package rw.ikanisa.burimunsi.gateway

import rw.ikanisa.burimunsi.core.GatewayStatus

/** Implemented in flavor-specific code. Staff has no receiving implementation. */
interface GatewayPort {
    fun bound():Boolean
    fun status():GatewayStatus
    fun start()
    fun setPaused(paused:Boolean)
    fun pair(code:String)
    fun requiredPermissions():Array<String>
}

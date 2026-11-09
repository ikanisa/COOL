package rw.ikanisa.burimunsi.gateway

import android.content.Context
import rw.ikanisa.burimunsi.core.GatewayStatus

object GatewayFactory {
    fun installationId(context:Context):String?=null
    fun create(context:Context):GatewayPort=object:GatewayPort {
        override fun bound()=false
        override fun status()=GatewayStatus(false,false,null,0,null,null,null,"not_available")
        override fun start()=Unit
        override fun setPaused(paused:Boolean):Unit=error("Gateway unavailable on Staff build")
        override fun pair(code:String):Unit=error("Gateway unavailable on Staff build")
        override fun requiredPermissions()=emptyArray<String>()
    }
}

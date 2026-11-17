package rw.ikanisa.burimunsi

import android.app.Application
import rw.ikanisa.burimunsi.gateway.GatewayFactory
class BuriApplication : Application() {
    override fun onCreate(){
        super.onCreate()
        // Flavor dispatch is a no-op on Staff. Android remains the authority on
        // whether a foreground service may start from this process entry point.
        runCatching{GatewayFactory.create(this).recoverContinuous()}
    }
}

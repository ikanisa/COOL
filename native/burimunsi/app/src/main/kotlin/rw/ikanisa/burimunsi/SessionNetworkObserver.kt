package rw.ikanisa.burimunsi

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import java.util.concurrent.atomic.AtomicBoolean

/** Observes connectivity only while the Activity is resumed; it grants no session authority. */
internal object SessionNetworkObserver {
    fun observe(manager:ConnectivityManager?,signal:()->Unit):()->Unit {
        if(manager==null)return {}
        val active=AtomicBoolean(true)
        val callback=object:ConnectivityManager.NetworkCallback(){
            private fun notifySession(){if(active.get())signal()}
            override fun onAvailable(network:Network){notifySession()}
            override fun onCapabilitiesChanged(network:Network,capabilities:NetworkCapabilities){
                if(capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)&&
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED))notifySession()
            }
        }
        try{manager.registerDefaultNetworkCallback(callback)}catch(_:Exception){active.set(false);return {}}
        return {
            if(active.getAndSet(false))try{manager.unregisterNetworkCallback(callback)}catch(_:Exception){}
        }
    }
}

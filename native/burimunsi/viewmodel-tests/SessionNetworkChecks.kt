package rw.ikanisa.burimunsi.networktests

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import rw.ikanisa.burimunsi.SessionNetworkObserver

/** Exercises the production callback with an isolated Android API double. */
fun main(){
    class Manager:ConnectivityManager(){
        var callback:NetworkCallback?=null;var unregistered=0;var reject=false
        override fun registerDefaultNetworkCallback(callback:NetworkCallback){if(reject)throw SecurityException();this.callback=callback}
        override fun unregisterNetworkCallback(callback:NetworkCallback){check(this.callback===callback);unregistered++}
    }
    var signals=0;val manager=Manager();val stop=SessionNetworkObserver.observe(manager){signals++}
    val callback=manager.callback?:error("callback not registered");val network=Network()
    callback.onAvailable(network);check(signals==1)
    callback.onCapabilitiesChanged(network,NetworkCapabilities(setOf(NetworkCapabilities.NET_CAPABILITY_INTERNET)));check(signals==1)
    callback.onCapabilitiesChanged(network,NetworkCapabilities(setOf(NetworkCapabilities.NET_CAPABILITY_INTERNET,NetworkCapabilities.NET_CAPABILITY_VALIDATED)));check(signals==2)
    stop();stop();check(manager.unregistered==1)
    callback.onAvailable(network);callback.onCapabilitiesChanged(network,NetworkCapabilities(setOf(NetworkCapabilities.NET_CAPABILITY_INTERNET,NetworkCapabilities.NET_CAPABILITY_VALIDATED)))
    check(signals==2)
    manager.reject=true;SessionNetworkObserver.observe(manager){error("failed registration signalled")}()
    SessionNetworkObserver.observe(null){error("missing manager signalled")}()
    println("PASS production network observer signals resumed connectivity, validates capability changes, and ignores callbacks after disposal")
}

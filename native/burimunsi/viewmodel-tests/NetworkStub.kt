package android.net

open class ConnectivityManager {
    open fun registerDefaultNetworkCallback(callback:NetworkCallback){}
    open fun unregisterNetworkCallback(callback:NetworkCallback){}
    open class NetworkCallback {
        open fun onAvailable(network:Network){}
        open fun onCapabilitiesChanged(network:Network,capabilities:NetworkCapabilities){}
    }
}
class Network
class NetworkCapabilities(private val values:Set<Int> = emptySet()) {
    fun hasCapability(value:Int)=value in values
    companion object {const val NET_CAPABILITY_INTERNET=12;const val NET_CAPABILITY_VALIDATED=16}
}

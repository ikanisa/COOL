package rw.ikanisa.burimunsi.core

data class ObservationConsentRevision(val enabled:Boolean,val generation:Long)
data class ObservationConsentState(val revision:ObservationConsentRevision,val confirmed:Boolean) {
    fun canCapture(androidPermissionGranted:Boolean)=androidPermissionGranted&&revision.enabled&&confirmed
}

/** A newer permission decision must survive delayed responses and process restarts. */
object ObservationConsent {
    const val MAX_GENERATION = 9_007_199_254_740_991L
    fun reconcile(local:ObservationConsentState?, server:ObservationConsentRevision?, androidPermissionGranted:Boolean):ObservationConsentState? {
        if(local==null&&server==null)return null // Lost local state requires an online read before capture.
        if(local!=null&&local.revision.generation !in 1..MAX_GENERATION)return null
        if(server!=null&&server.generation !in 0..MAX_GENERATION)return null
        val base=maxOf(local?.revision?.generation?:0,server?.generation?:0)
        val mustAdvance=local==null||local.revision.enabled!=androidPermissionGranted||
            server!=null&&(server.generation>local.revision.generation||
                server.generation==local.revision.generation&&server.enabled!=local.revision.enabled)
        if(mustAdvance){
            if(base==MAX_GENERATION)return null
            return ObservationConsentState(ObservationConsentRevision(androidPermissionGranted,base+1),false)
        }
        val confirmed=if(server==null)local.confirmed else
            server.generation==local.revision.generation&&server.enabled==local.revision.enabled
        return local.copy(confirmed=confirmed)
    }
    fun acknowledge(current:ObservationConsentState,echo:ObservationConsentRevision):ObservationConsentState? =
        if(current.revision==echo)current.copy(confirmed=true)else null
    fun <T> whilePermitted(consent:ObservationConsentState,permission:()->Boolean,write:()->T):T? =
        if(consent.canCapture(permission()))write()else null
}

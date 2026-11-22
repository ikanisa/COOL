package rw.ikanisa.burimunsi.core

/** Pair response is the collection authority. Managed UI, when present, may
 * narrow its visibility/actions; logout never invents or erases capture scope. */
object ReceiverCollectionScope {
    fun collection(value:Any?):String?=(value as? String)?.takeIf{Regex("[A-Za-z0-9][A-Za-z0-9_-]{0,127}").matches(it)}
    fun matches(value:Any?,managedCollection:String?):Boolean {
        val bound=collection(value)?:return false
        return managedCollection==null||collection(managedCollection)==bound
    }
}

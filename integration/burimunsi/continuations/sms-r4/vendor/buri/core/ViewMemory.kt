package rw.ikanisa.burimunsi.core

/** Session-only navigation memory. Never persisted, and never contains credentials. */
data class RememberedView<T>(val key:String,val value:T,val revision:Long)
class ViewMemory<T>(private val limit:Int=32) {
    init { require(limit in 1..100) }
    private val history=mutableListOf<RememberedView<T>>()
    private val contexts=linkedMapOf<String,RememberedView<T>>()
    var revision:Long=0; private set
    fun remember(key:String,value:T) {
        contexts.remove(key);contexts[key]=RememberedView(key,value,revision)
        while(contexts.size>limit)contexts.remove(contexts.keys.first())
    }
    fun push(key:String,value:T) {
        remember(key,value);history.add(RememberedView(key,value,revision))
        while(history.size>limit)history.removeAt(0)
    }
    fun remembered(key:String):RememberedView<T>?=contexts[key]
    fun previous():RememberedView<T>?=if(history.isEmpty())null else history.removeAt(history.lastIndex)
    /** Keep origins but force readback after a confirmed/uncertain mutation. */
    fun invalidateRecords(){revision++;contexts.clear()}
    fun isCurrent(entry:RememberedView<T>)=entry.revision==revision
    fun clear(){history.clear();contexts.clear();revision++}
}

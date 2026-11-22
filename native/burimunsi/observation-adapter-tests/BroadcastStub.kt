package android.content

/** Synthetic broadcasts only; never access a real SMS provider or device. */
object BroadcastFixture {
    @Volatile var finished=java.util.concurrent.CountDownLatch(1)
    fun reset(){finished=java.util.concurrent.CountDownLatch(1)}
}
open class BroadcastReceiver {
    open fun onReceive(context:Context,intent:Intent){}
    fun goAsync()=PendingResult()
    class PendingResult {fun finish(){BroadcastFixture.finished.countDown()}}
}
class Bundle(private val values:Map<String,Any?>){fun get(key:String)=values[key]}
class Intent(val action:String?,val values:Map<String,Any?> = emptyMap()) {
    val extras:Bundle get()=Bundle(values)
    fun hasExtra(key:String)=values.containsKey(key)
    fun getIntExtra(key:String,fallback:Int)=(values[key] as? Int)?:fallback
    fun getStringExtra(key:String)=values[key] as? String
}

package android.content

class Context { val applicationContext:Context get()=this }
class Bundle(private val values:Map<String,Any?>) { operator fun get(key:String)=values[key] }
class Intent(val action:String?,private val values:Map<String,Any?> = emptyMap()) {
    val extras:Bundle get()=Bundle(values)
    fun hasExtra(key:String)=values.containsKey(key)
    fun getIntExtra(key:String,default:Int)=(values[key] as? Int)?:default
    fun getStringExtra(key:String)=values[key] as? String
}
open class BroadcastReceiver {
    open fun onReceive(context:Context,intent:Intent){}
    fun goAsync()=PendingResult()
    class PendingResult { fun finish(){app.cool.mobile.receiver_sms.CaptureFixture.finished++} }
}

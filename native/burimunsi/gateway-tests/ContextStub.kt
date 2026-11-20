package android.content
class Context {
 val applicationContext:Context get()=this
 var denied=emptySet<String>()
 fun checkSelfPermission(value:String)=if(value in denied)-1 else 0
 @Suppress("UNCHECKED_CAST") fun <T> getSystemService(type:Class<T>):T?=
  if(type==android.telephony.SubscriptionManager::class.java)android.telephony.SubscriptionManager() as T else null
 fun getSharedPreferences(name:String,mode:Int)=Prefs()
 class Prefs{fun getLong(key:String,fallback:Long)=fallback;fun edit()=Editor()}
 class Editor{fun putLong(key:String,value:Long)=this;fun apply()=Unit}
 companion object{const val MODE_PRIVATE=0}
}

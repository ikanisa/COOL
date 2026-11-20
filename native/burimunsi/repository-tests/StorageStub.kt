package rw.ikanisa.burimunsi.storage
import android.content.Context
// Test-only in-memory replacement for Android Keystore-backed SecureStore.
class SecureStore(context:Context,private val name:String){
 companion object {val records=mutableMapOf<String,String>();var failClear:String?=null;var retainClear:String?=null;var failWrite:String?=null;var failWrites:Set<String> = emptySet();var dropWrite:String?=null;var afterRead:((String,String?)->Unit)?=null;var beforeClear:((String)->Unit)?=null
  fun reset(){
   afterRead=null;beforeClear=null;records.clear();failClear=null;retainClear=null;failWrite=null;failWrites=emptySet();dropWrite=null
   // This test-only reset explicitly simulates a fresh application process.
   val field=rw.ikanisa.burimunsi.data.NativeRepository::class.java.getDeclaredField("processSessionAuthority")
   field.isAccessible=true;(field.get(null) as rw.ikanisa.burimunsi.core.SessionAuthority).retire{}
  }}
 fun read():String?{val result=synchronized(records){records[name]};afterRead?.invoke(name,result);return result}
 fun write(value:String){synchronized(records){check(failWrite!=name&&name !in failWrites){"Synthetic write failure"};if(dropWrite!=name)records[name]=value}}
 fun clear(){beforeClear?.invoke(name);synchronized(records){check(failClear!=name){"Synthetic clear failure"};if(retainClear!=name)records.remove(name)}}
}

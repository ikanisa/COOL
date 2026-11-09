package rw.ikanisa.burimunsi.storage
import android.content.Context
// Test-only in-memory replacement for Android Keystore-backed SecureStore.
class SecureStore(context:Context,private val name:String){
 companion object {val records=mutableMapOf<String,String>();var failClear:String?=null;var retainClear:String?=null;var failWrite:String?=null;var dropWrite:String?=null;var afterRead:((String,String?)->Unit)?=null;var beforeClear:((String)->Unit)?=null;fun reset(){afterRead=null;beforeClear=null;records.clear();failClear=null;retainClear=null;failWrite=null;dropWrite=null}}
 fun read():String?{val result=synchronized(records){records[name]};afterRead?.invoke(name,result);return result}
 fun write(value:String){synchronized(records){check(failWrite!=name){"Synthetic write failure"};if(dropWrite!=name)records[name]=value}}
 fun clear(){beforeClear?.invoke(name);synchronized(records){check(failClear!=name){"Synthetic clear failure"};if(retainClear!=name)records.remove(name)}}
}

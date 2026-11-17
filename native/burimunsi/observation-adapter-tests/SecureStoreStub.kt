package rw.ikanisa.burimunsi.storage
import android.content.Context
/** Memory-only storage double; never claims Keystore/encryption behavior. */
class SecureStore(context:Context,private val name:String){
 companion object{val data=mutableMapOf<String,String>();val unreadable=mutableSetOf<String>();val unwritable=mutableSetOf<String>();val readCounts=mutableMapOf<String,Int>();val writeCounts=mutableMapOf<String,Int>();fun reset(){data.clear();unreadable.clear();unwritable.clear();readCounts.clear();writeCounts.clear()}}
 fun read():String?{readCounts[name]=(readCounts[name]?:0)+1;check(name !in unreadable);return data[name]}
 fun write(value:String){writeCounts[name]=(writeCounts[name]?:0)+1;check(name !in unreadable&&name !in unwritable);data[name]=value}
 fun clear(){data.remove(name)}
}

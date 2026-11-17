package rw.ikanisa.burimunsi.storage
import android.content.Context
/** Memory-only double: these host checks do not prove Android encryption. */
class SecureStore(context:Context,private val name:String) {
    companion object {val values=mutableMapOf<String,String>();var writes=0;var failAt:Int?=null;fun reset(){values.clear();writes=0;failAt=null}}
    fun read()=values[name]
    fun write(value:String){writes++;check(writes!=failAt){"synthetic write failure"};values[name]=value}
}

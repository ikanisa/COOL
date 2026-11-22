package rw.ikanisa.burimunsi.storage
import android.content.Context
/** Memory-only storage double; never claims Keystore/encryption behavior. */
class SecureStore(context:Context,private val name:String){
 companion object {
  val data=mutableMapOf<String,String>()
  val unreadable=mutableSetOf<String>()
  val readCounts=mutableMapOf<String,Int>()
  @Volatile var beforeDirectoryRead:(()->Unit)?=null
  val fixtureDirectory=object:java.io.File("synthetic-no-backup"){
   override fun listFiles(filter:java.io.FilenameFilter):Array<java.io.File> {
    beforeDirectoryRead?.invoke()
    return data.filterKeys{filter.accept(this,"buri-$it.v1")}.map{(key,value)->
     object:java.io.File(this,"buri-$key.v1"){
      override fun length()=value.length.toLong()
      override fun lastModified()=value.hashCode().toLong()+(if(key in unreadable)1 else 0)
     }
    }.toTypedArray()
   }
  }
  fun reset(){data.clear();unreadable.clear();readCounts.clear();beforeDirectoryRead=null}
 }
 fun read():String?{readCounts[name]=(readCounts[name]?:0)+1;check(name !in unreadable);return data[name]}
 fun write(value:String){check(name !in unreadable);data[name]=value}
 fun clear(){data.remove(name)}
}

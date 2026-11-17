package rw.ikanisa.burimunsi.data
import android.content.Context
import rw.ikanisa.burimunsi.core.*
/** Synthetic process-wide ownership generation, without credentials or network. */
class NativeRepository {
 companion object {
  private val lock=Any();private var current:ObservationOwner?=null;private var generation=0L
  fun switch(owner:ObservationOwner?)=synchronized(lock){generation++;current=owner}
  fun observationOwner(context:Context):ObservationSessionOwner?=synchronized(lock){current?.let{ObservationSessionOwner(it,generation)}}
  fun <T> withObservationOwner(context:Context,expected:ObservationSessionOwner?=null,action:(String,String)->T):T?=synchronized(lock){
   val owner=current?:return@synchronized null
   if(expected!=null&&expected!=ObservationSessionOwner(owner,generation))return@synchronized null
   action(owner.collectionId,owner.accountId)
  }
 }
}

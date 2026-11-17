package app.cool.mobile.receiver_sms
import android.content.Context
import rw.ikanisa.burimunsi.core.*
internal class ObservationStateStore(context:Context):ObservationJournalStore {
 companion object { var value=ObservationJournalState(emptyList(),emptyList());var fail=false }
 override fun read():ObservationJournalState {check(!fail);return value}
 override fun write(value:ObservationJournalState){check(!fail);Companion.value=value}
}
internal class ObservationConfigStore(context:Context){
 fun paused(owner:ObservationOwner)=false
 fun consent(owner:ObservationOwner):ObservationConsentState?=null
 fun profile(owner:ObservationOwner,now:Long):ObservationProfile?=null
 fun setPaused(owner:ObservationOwner,paused:Boolean){}
}
internal object ObservationBackground { fun ensure(context:Context){};fun signal(context:Context){} }

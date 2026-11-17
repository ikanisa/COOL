package app.cool.mobile.receiver_sms
import android.content.Context
object ObservationBackground {
    @Volatile var signals=0
    fun signalLocal(context:Context,delay:Long=2_000){signals++}
    fun hasPending(context:Context)=rw.ikanisa.burimunsi.data.NativeRepository.withObservationOwner(context){group,account->
        rw.ikanisa.burimunsi.core.ObservationJournal(ObservationStateStore(context)).pending(rw.ikanisa.burimunsi.core.ObservationOwner(group,account)).isNotEmpty()
    }==true
}

package app.cool.mobile.receiver_sms
import android.content.Context
import rw.ikanisa.burimunsi.core.*
/** Memory-only journal double. The actual ObservationJournal logic is compiled. */
internal class ObservationStateStore(context:Context):ObservationJournalStore {
 companion object{var value=ObservationJournalState(emptyList(),emptyList());var unreadable=false;fun reset(){value=ObservationJournalState(emptyList(),emptyList());unreadable=false}}
 override fun read():ObservationJournalState{check(!unreadable);return value}
 override fun write(value:ObservationJournalState){check(!unreadable);Companion.value=value}
}

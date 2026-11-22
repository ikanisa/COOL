package app.cool.mobile.receiver_sms
import android.content.Context
import rw.ikanisa.burimunsi.core.*
/** Memory-only journal double. The actual ObservationJournal logic is compiled. */
internal class ObservationStateStore(private val context:Context):ObservationJournalStore {
 companion object{var value=ObservationJournalState(emptyList(),emptyList());var unreadable=false;var reads=0;fun reset(){value=ObservationJournalState(emptyList(),emptyList());unreadable=false;reads=0}}
 override fun read():ObservationJournalState{reads++;check(!unreadable);return value}
 override fun write(value:ObservationJournalState){check(!unreadable);Companion.value=value}
 override fun protectSeenEviction(value:ObservationSeen)=ObservationReplayGuard.protect(context,value.owner,value.inboxRowId)
}

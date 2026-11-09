package rw.ikanisa.burimunsi

import android.app.Application
import rw.ikanisa.burimunsi.data.ManagedCollectBroker
import rw.ikanisa.burimunsi.data.ManagedSessionHost
import rw.ikanisa.burimunsi.data.ManagedSessionTokenProvider

class BuriApplication : Application(), ManagedSessionHost {
    val managedCollectBroker by lazy { ManagedCollectBroker(this) }
    override val managedSessionTokenProvider:ManagedSessionTokenProvider get()=managedCollectBroker
    override fun signOutManagedSession()=managedCollectBroker.signOut()
    override fun onCreate(){super.onCreate() /* Receiver lifecycle belongs to its independent variant. */}
}

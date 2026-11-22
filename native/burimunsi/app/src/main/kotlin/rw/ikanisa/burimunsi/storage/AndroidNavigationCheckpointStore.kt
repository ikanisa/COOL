package rw.ikanisa.burimunsi.storage

import android.content.Context
import rw.ikanisa.burimunsi.core.NavigationCheckpointStore

/** Uses the existing Keystore AES-GCM/no-backup boundary, not SharedPreferences or a Bundle. */
class AndroidNavigationCheckpointStore(context: Context): NavigationCheckpointStore {
    private companion object { val navigationFile = Any() }
    override val writeScope: Any get() = navigationFile
    private val secure = SecureStore(context, "ui-navigation")
    override fun read() = secure.read()
    override fun write(value: String) = secure.write(value)
    override fun clear() = secure.clear()
}

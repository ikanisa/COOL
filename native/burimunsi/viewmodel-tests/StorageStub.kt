package rw.ikanisa.burimunsi.storage
import android.app.Application
class DeviceProvisioning(app:Application,id:String){val installationId=id;fun token():String?=null;fun registrationToken()="fixture-registration-token"}

// Isolated store: no disk, keychain or prior-session state in controller fixtures.
class AndroidNavigationCheckpointStore(app:Application):rw.ikanisa.burimunsi.core.NavigationCheckpointStore {
 private var value:String?=null
 override fun read()=value
 override fun write(value:String){this.value=value}
 override fun clear(){value=null}
}

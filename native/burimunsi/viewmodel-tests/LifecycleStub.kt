package androidx.lifecycle
import android.app.Application
import kotlinx.coroutines.*
open class AndroidViewModel(val application:Application){internal val fixtureScope=CoroutineScope(SupervisorJob()+Dispatchers.Default)}
val AndroidViewModel.viewModelScope:CoroutineScope get()=fixtureScope

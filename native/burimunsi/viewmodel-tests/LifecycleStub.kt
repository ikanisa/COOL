package androidx.lifecycle
import android.app.Application
import kotlinx.coroutines.*
// Android's viewModelScope serializes controller state on Main. Dispatchers.Default
// allowed fake parallel UI callbacks and intermittent lost state in SMS coalescing.
// Keep the test event loop separate from runBlocking so latch-based IO tests remain real.
private val fixtureMain=java.util.concurrent.Executors.newSingleThreadExecutor { task ->
    Thread(task,"fixture-android-main").apply{isDaemon=true}
}.asCoroutineDispatcher()
open class AndroidViewModel(val application:Application){internal val fixtureScope=CoroutineScope(SupervisorJob()+fixtureMain)}
val AndroidViewModel.viewModelScope:CoroutineScope get()=fixtureScope

/** Deliver synthetic Android callbacks on the same dispatcher as viewModelScope. */
internal suspend fun <Model : AndroidViewModel, T> Model.onFixtureMain(block: Model.() -> T): T =
    withContext(fixtureMain) { block() }

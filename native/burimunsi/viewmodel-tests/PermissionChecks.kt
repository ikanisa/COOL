package rw.ikanisa.burimunsi.permissiontests
import android.app.Application
import kotlinx.coroutines.*
import rw.ikanisa.burimunsi.ui.BuriViewModel
import rw.ikanisa.burimunsi.ui.Sheet
import rw.ikanisa.burimunsi.gateway.GatewayFixture
import rw.ikanisa.burimunsi.core.*
import androidx.lifecycle.onFixtureMain
import androidx.lifecycle.viewModelScope

fun main()=runBlocking {
    val app=Application();val model=BuriViewModel(app)
    suspend fun awaitUi(acknowledged: BuriViewModel.() -> Boolean) {
        val observed = withTimeoutOrNull(5_000) {
            while (!model.onFixtureMain(acknowledged)) delay(2)
            true
        }
        check(observed == true) { model.onFixtureMain {
            "Permission callback timed out: gate=$screenGate busy=" + state.busy + " route=" + state.route +
                " panel=" + state.sheet + " status=" + (state.gateway != null) + " failure=" + state.failure +
                " reads=" + GatewayFixture.statusReads
        } }
    }
    awaitUi { !state.starting && !state.busy && state.gateway != null }
    check(model.smsAccessGranted)
    val callerThread = model.onFixtureMain { Thread.currentThread().id }
    val starts = GatewayFixture.uploadStarts
    model.onFixtureMain {
        app.permissionResults[android.Manifest.permission.READ_SMS] = -1
        permissionsChanged()
    }
    awaitUi { GatewayFixture.uploadStarts > starts }
    check(GatewayFixture.lastStartThreadId != callerThread)
    check(!model.smsAccessGranted)
    model.onFixtureMain {
        app.permissionResults[android.Manifest.permission.READ_SMS] = 0
        app.permissionResults[android.Manifest.permission.RECEIVE_SMS] = -1
        permissionsChanged()
        check(!smsAccessGranted)
        onBackground()
        app.permissionResults[android.Manifest.permission.RECEIVE_SMS] = 0
        onForeground()
    }
    // Foreground profile replacement and its separate Home receiver read must both be acknowledged.
    awaitUi { screenGate == ScreenGate.OPEN && !state.busy && state.gateway != null }
    check(model.smsAccessGranted && model.state.sheet == null)
    println("PASS SMS permission reflects both permissions and refreshes on return without opening a sheet")
    model.onFixtureMain {
        app.permissionResults[android.Manifest.permission.READ_SMS] = -1
        GatewayFixture.snapshot = GatewayStatus(true,false,1,0,null,null,null,"permission_required")
        permissionsChanged()
    }
    awaitUi { state.gateway?.problem == "permission_required" && !state.busy }
    model.onFixtureMain { openSheet(Sheet.GATEWAY) }
    awaitUi { state.sheet == Sheet.GATEWAY && !state.busy }
    check(model.state.gateway?.problem == "permission_required")
    val changes = GatewayFixture.changes
    model.onFixtureMain {
        app.permissionResults[android.Manifest.permission.READ_SMS] = 0
        GatewayFixture.snapshot = GatewayStatus(true,false,1,0,null,null,null,null)
        permissionsChanged()
    }
    awaitUi { state.gateway != null && state.gateway?.problem == null && !state.busy }
    check(model.state.sheet == Sheet.GATEWAY && GatewayHealth.describe(model.state.gateway).canResume)
    check(GatewayFixture.changes == changes)
    println("PASS permission return refreshes the current gateway diagnosis without resuming it")
    val reads = GatewayFixture.statusReads
    val startsAgain = GatewayFixture.uploadStarts
    val callback = model.onFixtureMain {
        val owner = viewModelScope.coroutineContext[Job]!!
        val existing = owner.children.toSet()
        permissionsChanged()
        owner.children.filterNot { it in existing }.toList().also { check(it.isNotEmpty()) }
    }
    withTimeout(5_000) { callback.joinAll() }
    awaitUi { !state.busy }
    check(GatewayFixture.uploadStarts > startsAgain && GatewayFixture.statusReads == reads)
    println("PASS unchanged permissions do not trigger an extra gateway status refresh")
    GatewayFixture.statusEntered = java.util.concurrent.CountDownLatch(1)
    GatewayFixture.statusRelease = java.util.concurrent.CountDownLatch(1)
    model.onFixtureMain {
        app.permissionResults[android.Manifest.permission.RECEIVE_SMS] = -1
        permissionsChanged()
    }
    withContext(Dispatchers.IO) { check(GatewayFixture.statusEntered!!.await(5,java.util.concurrent.TimeUnit.SECONDS)) }
    model.onFixtureMain { onBackground() }
    GatewayFixture.statusRelease!!.countDown()
    awaitUi { !state.busy }
    check(model.state.gateway == null)
    model.viewModelScope.coroutineContext[Job]!!.cancelAndJoin()
    GatewayFixture.statusEntered = null
    GatewayFixture.statusRelease = null
    println("PASS permission refresh cannot publish after the app leaves the foreground")
}

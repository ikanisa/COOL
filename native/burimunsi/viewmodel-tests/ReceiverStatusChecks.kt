package rw.ikanisa.burimunsi.receiverstatustests

import android.app.Application
import androidx.lifecycle.viewModelScope
import app.cool.mobile.BuildConfig
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import rw.ikanisa.burimunsi.core.Role
import rw.ikanisa.burimunsi.core.Route
import rw.ikanisa.burimunsi.data.Fixture
import rw.ikanisa.burimunsi.gateway.GatewayFixture
import rw.ikanisa.burimunsi.ui.BuriViewModel
import rw.ikanisa.burimunsi.ui.Sheet

fun main() = runBlocking {
    suspend fun idle(vm: BuriViewModel) {
        withTimeout(10_000) { while (vm.state.busy) delay(5) }
    }
    if (!BuildConfig.IS_GATEWAY) {
        Fixture.role = Role.STAFF
        val model = BuriViewModel(Application())
        try {
            idle(model)
            model.navigate(Route.SETTINGS)
            idle(model)
            model.systemPolicyChanged(true, false)
            model.permissionsChanged()
            delay(50)
            check(model.notificationAccessGranted == true && model.batteryExemptionGranted == false)
            check(GatewayFixture.statusReads == 0 && GatewayFixture.uploadStarts == 0 && model.state.gateway == null)
        } finally {
            model.viewModelScope.cancel()
        }
        println("PASS Staff notification settings remain available without receiver diagnostics or queue work")
        return@runBlocking
    }
    val failed = mutableListOf<String>()
    suspend fun exercise(label: String, route: Route, panel: Boolean, invalidate: () -> Unit, reset: () -> Unit) {
        val model = BuriViewModel(Application())
        try {
            idle(model)
            withTimeout(5_000) { while (model.state.gateway == null) delay(5) }
            if (route == Route.SETTINGS) {
                model.navigate(route)
                idle(model)
            }
            val entered = CountDownLatch(1)
            val release = CountDownLatch(1)
            GatewayFixture.statusEntered = entered
            GatewayFixture.statusRelease = release
            GatewayFixture.snapshot = GatewayFixture.snapshot.copy(problem = "older_receiver_scope")
            if (panel) model.openSheet(Sheet.GATEWAY) else model.refresh()
            withContext(Dispatchers.IO) { check(entered.await(5, TimeUnit.SECONDS)) }
            invalidate()
            release.countDown()
            idle(model)
            if (model.state.gateway?.problem == "older_receiver_scope") failed.add(label)
        } finally {
            GatewayFixture.statusRelease?.countDown()
            GatewayFixture.statusEntered = null
            GatewayFixture.statusRelease = null
            GatewayFixture.snapshot = GatewayFixture.snapshot.copy(problem = "uploads_on_hold")
            reset()
            model.viewModelScope.cancel()
        }
    }
    exercise("Receiver panel rejected a different operator", Route.HOME, true,
        { Fixture.currentOwnerOverride = "successor" }, { Fixture.currentOwnerOverride = null })
    exercise("Settings rejected a same-operator replacement session", Route.SETTINGS, false,
        { Fixture.processSessionEpoch.incrementAndGet() }, {})
    exercise("Gateway panel rejected a changed collection grant", Route.HOME, true,
        { Fixture.receiverGroupOverride = "different-collection" }, { Fixture.receiverGroupOverride = null })
    val model = BuriViewModel(Application())
    try {
        idle(model)
        withTimeout(5_000) { while(model.state.gateway == null) delay(5) }
        model.navigate(Route.SETTINGS)
        idle(model)
        val permissionEntered = CountDownLatch(1)
        val permissionRelease = CountDownLatch(1)
        GatewayFixture.permissionsEntered = permissionEntered
        GatewayFixture.permissionsRelease = permissionRelease
        val launched = java.util.concurrent.atomic.AtomicBoolean()
        model.requestReceivingPermissions { launched.set(true) }
        withContext(Dispatchers.IO) { check(permissionEntered.await(5, TimeUnit.SECONDS)) }
        model.navigate(Route.MEMBERS)
        idle(model)
        permissionRelease.countDown()
        withContext(Dispatchers.IO) { check(GatewayFixture.permissionReadFinished.await(5, TimeUnit.SECONDS)) }
        withContext(model.viewModelScope.coroutineContext.minusKey(kotlinx.coroutines.Job)) { }
        check(!launched.get())
        GatewayFixture.permissionsEntered = null
        GatewayFixture.permissionsRelease = null
        model.navigate(Route.SETTINGS)
        idle(model)
        model.openSheet(Sheet.GATEWAY)
        idle(model)
        val statusEntered = CountDownLatch(1)
        val statusRelease = CountDownLatch(1)
        GatewayFixture.statusEntered = statusEntered
        GatewayFixture.statusRelease = statusRelease
        val previousChanges = GatewayFixture.changes
        model.setPaused(false)
        withContext(Dispatchers.IO) { check(statusEntered.await(5, TimeUnit.SECONDS)) }
        Fixture.processSessionEpoch.incrementAndGet()
        statusRelease.countDown()
        idle(model)
        check(GatewayFixture.changes == previousChanges)
        GatewayFixture.statusEntered = null
        GatewayFixture.statusRelease = null
        model.closeSheet()
        idle(model)
        val opened = kotlinx.coroutines.CompletableDeferred<Array<String>>()
        model.requestReceivingPermissions { opened.complete(it) }
        check(withTimeout(5_000){ opened.await() }.contains(android.Manifest.permission.RECEIVE_SMS))
        check(!launched.get())
        val healthEntered = CountDownLatch(1)
        val healthRelease = CountDownLatch(1)
        GatewayFixture.healthEntered = healthEntered
        GatewayFixture.healthRelease = healthRelease
        model.systemPolicyChanged(true, false)
        withContext(Dispatchers.IO) { check(healthEntered.await(5, TimeUnit.SECONDS)) }
        Fixture.currentOwnerOverride = "successor"
        healthRelease.countDown()
        withContext(Dispatchers.IO) { check(GatewayFixture.healthReadFinished.await(5, TimeUnit.SECONDS)) }
        withContext(model.viewModelScope.coroutineContext.minusKey(kotlinx.coroutines.Job)) { }
        check(model.continuousSyncProblem == null)
    } finally {
        Fixture.currentOwnerOverride = null
        GatewayFixture.permissionsRelease?.countDown()
        GatewayFixture.healthRelease?.countDown()
        GatewayFixture.statusRelease?.countDown()
        model.viewModelScope.cancel()
    }
    val app = Application()
    val navigation = BuriViewModel(app)
    try {
        idle(navigation)
        withTimeout(5_000) { while (navigation.state.gateway == null) delay(5) }
        navigation.navigate(Route.SETTINGS)
        idle(navigation)
        val previousStarts = GatewayFixture.uploadStarts
        navigation.permissionsChanged()
        withTimeout(5_000) { while (GatewayFixture.uploadStarts <= previousStarts) delay(5) }
        val statusEntered = CountDownLatch(1)
        val statusRelease = CountDownLatch(1)
        GatewayFixture.statusEntered = statusEntered
        GatewayFixture.statusRelease = statusRelease
        app.permissionResults[android.Manifest.permission.READ_SMS] = -1
        navigation.permissionsChanged()
        withContext(Dispatchers.IO) { check(statusEntered.await(5, TimeUnit.SECONDS)) }
        withContext(navigation.viewModelScope.coroutineContext.minusKey(kotlinx.coroutines.Job)) {
            navigation.navigate(Route.MEMBERS)
        }
        statusRelease.countDown()
        val opened = kotlinx.coroutines.withTimeoutOrNull(2_000) {
            while (navigation.state.route != Route.MEMBERS || navigation.state.busy) delay(5)
            true
        }
        check(opened == true) { "Permission diagnostics discarded the user's navigation from Settings" }
    } finally {
        GatewayFixture.statusRelease?.countDown()
        GatewayFixture.statusEntered = null
        GatewayFixture.statusRelease = null
        navigation.viewModelScope.cancel()
    }
    check(failed.isEmpty()) { "Receiver status escaped its authority: " + failed.joinToString() }
    println("PASS Receiver panel and Settings drop diagnostics after operator, session and collection changes")
    println("PASS Permission prompt rechecks the visible route and opens only after its protected lookup")
    println("PASS Delayed background sync health stays with the originating operator")
    println("PASS A permission status refresh preserves navigation from Settings")
    println("PASS An old receiver diagnosis cannot resume capture after session replacement")
}

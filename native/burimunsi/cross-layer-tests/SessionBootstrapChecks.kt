package rw.ikanisa.burimunsi.crosslayertests

import android.app.Application
import androidx.lifecycle.onFixtureMain
import androidx.lifecycle.viewModelScope
import app.cool.mobile.BuildConfig
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.ApiClient
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.data.Transport
import rw.ikanisa.burimunsi.gateway.GatewayFixture
import rw.ikanisa.burimunsi.storage.SecureStore
import rw.ikanisa.burimunsi.ui.BuriViewModel
import rw.ikanisa.burimunsi.ui.Sheet

private val flavor = if (BuildConfig.IS_GATEWAY) "internal_receiver" else "staff"

private class HeldCheckpoint(private val bookmark: NavigationCheckpoint) : NavigationCheckpointStore {
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    override fun read(): String {
        entered.countDown()
        check(release.await(10, TimeUnit.SECONDS))
        return bookmark.encode()
    }
    override fun write(value: String) = Unit
    override fun clear() = Unit
}

internal class SessionScenario {
    val app = Application()
    var owner = "operator-a"
    var group = "group-a"
    var role = if (BuildConfig.IS_GATEWAY) "admin" else "staff"
    var capabilities = listOf(Capability.READ)
    var token = "a".repeat(64)
    var profileUnavailable = false
    var sessionDeadline: Long? = null
    private val profile get() = JSONObject().put("id", owner).put("name", "Synthetic Operator")
        .put("phone", "+250780000001").put("role", role)
        .put("capabilities", JSONArray().also { array -> capabilities.forEach { array.put(it.key) } })

    init {
        SecureStore.reset()
        Transport.calls.clear()
        Transport.handler = { request ->
            when {
                request.path.endsWith("/session/logout") -> JSONObject().put("signedOut", true).toString()
                profileUnavailable && request.path.endsWith("/session") -> throw ApiFailure("connection_unavailable", 0)
                request.path.endsWith("/session/login") || request.path.endsWith("/session") ->
                    JSONObject().put("profile", profile).put("token", token).put("groupId", group)
                        .put("expiresAt", sessionDeadline ?: (System.currentTimeMillis() + 3_600_000)).toString()
                request.path.endsWith("/home") -> JSONObject().put("groupBalanceRwf", 0).put("todayRwf", 0)
                    .put("memberCount", 0).put("unallocatedCount", 0).put("recentPayments", JSONArray())
                    .put("asOf", "2026-11-20T00:00:00Z").toString()
                request.path.contains("/staff?") -> JSONObject().put("items", JSONArray()).put("totalCount", 0)
                    .put("revision", "fixture-1").put("asOf", "2026-11-20T00:00:00Z")
                    .put("nextCursor", JSONObject.NULL).toString()
                else -> error("Unexpected synthetic session request")
            }
        }
    }

    fun repository() = NativeRepository(app, ApiClient.phonePin("https://offline.test", "fixture-device", flavor, "") { "fixture" })
    fun signIn(repository: NativeRepository) = repository.login("0780000001", "2468")
}

private fun SessionScenario.held() = HeldCheckpoint(NavigationCheckpoint(owner, group, System.currentTimeMillis(), Route.SETTINGS))

private suspend fun idle(model: BuriViewModel) {
    withTimeout(10_000) { while (model.state.starting || model.state.busy) delay(2) }
    model.viewModelScope.launch {}.join()
}

private suspend fun stop(model: BuriViewModel) = model.viewModelScope.coroutineContext[Job]!!.cancelAndJoin()

private enum class Replacement { NONE, SAME_OWNER, OTHER_GROUP }

private suspend fun interruptedRestore(replacement: Replacement) {
    val scenario = SessionScenario()
    val original = scenario.repository()
    scenario.signIn(original)
    val checkpoint = scenario.held()
    val receiverStarts = GatewayFixture.uploadStarts
    val model = BuriViewModel(scenario.app, checkpoint, System::currentTimeMillis)
    try {
        check(checkpoint.entered.await(10, TimeUnit.SECONDS))
        original.logout()
        if (replacement != Replacement.NONE) {
            scenario.role = "staff"
            if (replacement == Replacement.OTHER_GROUP) scenario.group = "group-b"
            scenario.signIn(original)
        }
        model.viewModelScope.launch {}.join()
        checkpoint.release.countDown()
        idle(model)
        check(model.state.route != Route.SETTINGS) { "A superseded restore displayed the old Settings route" }
        check(GatewayFixture.uploadStarts == receiverStarts) { "An interrupted restore started Sync" }
        check(Transport.calls.none { it.method != "GET" && !it.path.contains("/session/") })
        if (replacement == Replacement.SAME_OWNER) {
            // Identical subject, group and token still need a new server profile and records request.
            check(original.current()?.role == Role.STAFF)
            check(model.state.operator?.role == Role.STAFF && model.state.route == Route.HOME && model.state.home != null)
            check(!model.allows(Capability.GATEWAY))
            check(Transport.calls.count { it.method == "GET" && it.path.endsWith("/session") } == 2)
        } else {
            check(model.state.route == Route.LOGIN && model.state.operator == null &&
                model.state.gateway == null && !model.presentation.showRecords)
            if (replacement == Replacement.OTHER_GROUP) {
                check(original.current()?.id == scenario.owner && original.boundCollectionId == scenario.group)
                check(Transport.calls.none { it.path.endsWith("/home") })
                return
            }
            scenario.owner = "operator-b"
            scenario.group = "group-b"
            scenario.token = "b".repeat(64)
            model.login("0780000002", "1357")
            idle(model)
            check(model.state.operator?.id == scenario.owner && model.state.home != null)
            val home = Transport.calls.last { it.path.endsWith("/home") }
            check(home.context["groupId"] == scenario.group && home.context["actorId"] == scenario.owner)
        }
    } finally {
        checkpoint.release.countDown()
        stop(model)
    }
}

private suspend fun grantsNarrowed() {
    val scenario = SessionScenario()
    scenario.role = "admin"
    scenario.capabilities = listOf(Capability.READ, Capability.STAFF, Capability.GATEWAY)
    val model = BuriViewModel(scenario.app)
    try {
        idle(model)
        model.login("0780000001", "2468")
        idle(model)
        model.openSheet(Sheet.STAFF)
        idle(model)
        check(model.state.sheet == Sheet.STAFF && model.state.staff != null)
        val staffReads = Transport.calls.count { it.path.contains("/staff?") }
        scenario.role = "staff"
        scenario.capabilities = listOf(Capability.READ)
        model.refreshSession()
        idle(model)
        check(model.state.operator?.role == Role.STAFF && model.state.sheet == null && model.state.staff == null)
        check(model.state.home != null && !model.allows(Capability.STAFF) && !model.allows(Capability.GATEWAY))
        check(Transport.calls.count { it.path.contains("/staff?") } == staffReads)
    } finally { stop(model) }
}

private suspend fun peerNarrowsGrant() {
    val scenario = SessionScenario()
    scenario.role = "admin"
    val peer = scenario.repository()
    scenario.signIn(peer)
    val checkpoint = scenario.held()
    val receiverStarts = GatewayFixture.uploadStarts
    val model = BuriViewModel(scenario.app, checkpoint, System::currentTimeMillis)
    try {
        check(checkpoint.entered.await(10, TimeUnit.SECONDS))
        scenario.role = "staff"
        check(peer.refreshSession().role == Role.STAFF)
        model.viewModelScope.launch {}.join()
        checkpoint.release.countDown()
        idle(model)
        check(model.state.operator?.role == Role.STAFF && model.state.route == Route.HOME && model.state.home != null &&
            !model.allows(Capability.GATEWAY) && GatewayFixture.uploadStarts == receiverStarts) {
            "A previous role survived another activity's grant refresh"
        }
        check(peer.current()?.role == Role.STAFF)
    } finally {
        checkpoint.release.countDown()
        stop(model)
    }
}

private suspend fun retrySavedSession() {
    val scenario = SessionScenario()
    scenario.signIn(scenario.repository())
    scenario.profileUnavailable = true
    val model = BuriViewModel(scenario.app)
    try {
        idle(model)
        check(model.state.operator == null && model.state.savedSessionPending)
        val reads = Transport.calls.count { it.path.endsWith("/session") }
        scenario.profileUnavailable = false
        model.refresh() // The saved-session splash Retry action.
        idle(model)
        check(model.state.operator?.id == scenario.owner && model.state.home != null && !model.state.savedSessionPending)
        check(Transport.calls.count { it.path.endsWith("/session") } == reads + 1)
        check(Transport.calls.count { it.path.endsWith("/session/login") } == 1)
    } finally { stop(model) }
}

private suspend fun cancelBootstrap() {
    val scenario = SessionScenario()
    scenario.signIn(scenario.repository())
    val checkpoint = scenario.held()
    val receiverStarts = GatewayFixture.uploadStarts
    val model = BuriViewModel(scenario.app, checkpoint, System::currentTimeMillis)
    try {
        check(checkpoint.entered.await(10, TimeUnit.SECONDS))
        model.viewModelScope.coroutineContext[Job]!!.cancel()
        checkpoint.release.countDown()
        stop(model)
        check(model.state.operator == null && GatewayFixture.uploadStarts == receiverStarts)
        check(Transport.calls.none { it.path.endsWith("/home") || it.path.contains("/operations/") })
    } finally {
        checkpoint.release.countDown()
        stop(model)
    }
}

private suspend fun renewedDeadlineKeepsScope() {
    val scenario = SessionScenario()
    val peer = scenario.repository()
    scenario.signIn(peer)
    val revision = peer.sessionRevision
    val checkpoint = scenario.held()
    val model = BuriViewModel(scenario.app, checkpoint, System::currentTimeMillis)
    try {
        check(checkpoint.entered.await(10, TimeUnit.SECONDS))
        peer.refreshSession()
        check(peer.sessionRevision == revision)
        model.viewModelScope.launch {}.join()
        checkpoint.release.countDown()
        idle(model)
        check(model.state.operator?.id == scenario.owner && model.state.route == Route.SETTINGS)
        check(Transport.calls.count { it.path.endsWith("/session") } == 2)
    } finally {
        checkpoint.release.countDown()
        stop(model)
    }
}

private suspend fun equalProfileRefresh() {
    val scenario = SessionScenario()
    scenario.sessionDeadline = System.currentTimeMillis() + 3_600_000
    scenario.capabilities = if (BuildConfig.IS_GATEWAY) listOf(Capability.READ, Capability.GATEWAY) else listOf(Capability.READ)
    scenario.signIn(scenario.repository())
    val model = BuriViewModel(scenario.app)
    try {
        idle(model)
        val before = checkNotNull(model.state.operator)
        model.onFixtureMain { refreshSession() }
        idle(model)
        val refreshed = checkNotNull(model.state.operator)
        check(before == refreshed && before !== refreshed) { "The screen kept an obsolete profile instance" }
        check(model.state.home != null && model.allows(Capability.READ))
        if (BuildConfig.IS_GATEWAY) {
            val permissions = kotlinx.coroutines.CompletableDeferred<Array<String>>()
            model.onFixtureMain { requestReceivingPermissions { permissions.complete(it) } }
            check(withTimeout(5_000) { permissions.await() }.contains(android.Manifest.permission.READ_SMS))
        } else {
            check(!model.allows(Capability.GATEWAY))
        }
    } finally { stop(model) }
}

private suspend fun legacyProfileRestores() {
    val scenario = SessionScenario()
    scenario.signIn(scenario.repository())
    val saved = JSONObject(SecureStore.records.getValue("session"))
    saved.put("profile", JSONObject().put("id", scenario.owner))
    SecureStore.records["session"] = saved.toString()
    val model = BuriViewModel(scenario.app)
    try {
        idle(model)
        check(model.state.operator?.id == scenario.owner && model.state.home != null)
        check(JSONObject(SecureStore.records.getValue("session")).getJSONObject("profile").getString("role") == scenario.role)
    } finally { stop(model) }
}

fun main() = runBlocking {
    val results = listOf(
        "signed-out startup retires Settings and Sync before a new group signs in" to suspend { interruptedRestore(Replacement.NONE) },
        "same-identity replacement revalidates the role and loads Home under a new generation" to suspend { interruptedRestore(Replacement.SAME_OWNER) },
        "a replacement in another group never enters the old activity" to suspend { interruptedRestore(Replacement.OTHER_GROUP) },
        "a narrowed grant removes privileged panels before reading records again" to suspend { grantsNarrowed() },
        "a peer's same-credential role change closes an interrupted bootstrap" to suspend { peerNarrowsGrant() },
        "saved-session Retry rechecks the server without repeating login" to suspend { retrySavedSession() },
        "cancelled startup publishes no session, starts no Sync and replays no command" to suspend { cancelBootstrap() },
        "a renewed deadline with identical grants preserves the current route and generation" to suspend { renewedDeadlineKeepsScope() },
        "an equal-valued foreground profile replaces the authority held by the screen" to suspend { equalProfileRefresh() },
        "an older actor-only saved profile restores through a current server profile" to suspend { legacyProfileRestores() },
    ).map { (label, scenario) ->
        runCatching { scenario() }.also { result ->
            println((if (result.isSuccess) "PASS" else "FAIL") + " $flavor $label")
            result.exceptionOrNull()?.printStackTrace()
        }
    }
    check(results.all { it.isSuccess })
}

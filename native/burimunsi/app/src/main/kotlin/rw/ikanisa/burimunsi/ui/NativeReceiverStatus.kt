package rw.ikanisa.burimunsi.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import rw.ikanisa.burimunsi.core.Access
import rw.ikanisa.burimunsi.core.Capability
import rw.ikanisa.burimunsi.core.ContractFailure
import rw.ikanisa.burimunsi.core.GatewayStatus
import rw.ikanisa.burimunsi.core.Operator
import rw.ikanisa.burimunsi.core.Role
import rw.ikanisa.burimunsi.core.Route
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth
import rw.ikanisa.burimunsi.gateway.GatewayPort

/** Receiver diagnostics belong to the current native session, collection and visible screen. */
internal class NativeReceiverStatus(
    private val receiver: Boolean,
    private val gateway: GatewayPort,
    private val repository: () -> NativeRepository?,
    private val screen: () -> UiState,
    private val foreground: () -> Boolean,
    private val clock: () -> Long,
    private val scope: CoroutineScope,
) {
    class Request internal constructor(
        val operator: Operator, val group: String, val session: Long,
        val route: Route, val routeId: String?, val sheet: Sheet?, val sheetId: String?,
        val epoch: Long,
    )

    private var epoch = 0L
    private var latestRead = 0L
    private var homeJob: Job? = null
    private var healthJob: Job? = null
    private var healthRequest: Request? = null
    private var health by mutableStateOf<Pair<Request, ContinuousReceiverHealth>?>(null)
    private var permissionFingerprint: List<Pair<String, Int>>? = null
    private var pendingPermissions: Request? = null
    private var required by mutableStateOf<Pair<Request, List<String>>?>(null)

    private fun admitted(state: UiState, actor: Operator): Boolean =
        receiver && foreground() && !state.receiverRetirementPending && !state.passcodeChangePending &&
            actor.role == Role.ADMIN && clock() < actor.expiresAt && Access.routeAllowed(actor, state.route, clock(), receiverVariant = true, boundGateway = true)

    fun request(): Request? {
        val state = screen()
        val actor = state.operator ?: return null
        if (!admitted(state, actor)) return null
        return try {
            repository()?.withCurrentProfile(actor) { group, revision ->
                Request(actor, group, revision, state.route, state.routeId, state.sheet, state.sheetId, epoch)
            }
        } catch (_: ContractFailure) { null }
    }

    private fun current(ticket: Request, publish: () -> Unit = {}): Boolean {
        val state = screen()
        if (!admitted(state, ticket.operator) || state.operator !== ticket.operator || ticket.epoch != epoch ||
            ticket.route != state.route || ticket.routeId != state.routeId ||
            ticket.sheet != state.sheet || ticket.sheetId != state.sheetId) return false
        return try {
            repository()?.withCurrentProfile(ticket.operator) { group, revision ->
                if (group != ticket.group || revision != ticket.session) false else {
                    publish()
                    true
                }
            } == true
        } catch (_: ContractFailure) { false }
    }

    fun invalidate() {
        epoch++
        homeJob?.cancel()
        healthJob?.cancel()
        healthRequest = null
        health = null
        required = null
        pendingPermissions = null
    }

    /** All protected status and queue reads run on IO. A late completion never replaces a newer read. */
    suspend fun read(ticket: Request?, home: Boolean = false, publish: (GatewayStatus) -> Unit): Boolean {
        if (ticket == null || !current(ticket)) return false
        val serial = ++latestRead
        val (status, permissions) = try {
            withContext(Dispatchers.IO) { gateway.status() to gateway.requiredPermissions().toList() }
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) {
            if (serial != latestRead || !current(ticket)) return false
            if (!home) throw e
            GatewayStatus(false, false, null, -1, null, null, null, "queue_unavailable") to null
        }
        return serial == latestRead && current(ticket) {
            required = permissions?.let { ticket to it }
            publish(status)
        }
    }

    fun permissionsRequired(granted: (String) -> Boolean): Boolean {
        if (!receiver) return false
        val snapshot = required ?: return true
        return !current(snapshot.first) || snapshot.second.any { !granted(it) }
    }

    fun launchPermissions(show: (Array<String>) -> Unit) {
        val ticket = request() ?: return
        if (!Access.allows(ticket.operator, Capability.GATEWAY, clock(), receiver)) return
        scope.launch {
            val names = try { withContext(Dispatchers.IO) { gateway.requiredPermissions() } }
                catch (e: CancellationException) { throw e }
                catch (_: Exception) { return@launch }
            if (names.isNotEmpty()) current(ticket) { show(names) }
        }
    }

    suspend fun control(ticket: Request, operation: () -> Unit): Boolean = withContext(Dispatchers.IO) {
        // The receiver checks its current pairing and collection again inside each control operation.
        if (!current(ticket)) false else { operation(); true }
    }

    fun refreshHome(publish: (GatewayStatus) -> Unit) {
        homeJob?.cancel()
        val ticket = request() ?: return
        if (ticket.route == Route.HOME && ticket.sheet == null)
            homeJob = scope.launch { read(ticket, home = true, publish = publish) }
    }

    fun permissionsChanged(grants: List<Pair<String, Int>>?, drained: () -> Unit) {
        if (!receiver) return
        val changed = grants != null && permissionFingerprint != null && permissionFingerprint != grants
        if (grants != null) permissionFingerprint = grants
        if (changed) {
            epoch++
            pendingPermissions = null
        }
        val ticket = if (changed) request() else null
        // The authorized receiving queue has its own lifecycle, including when the operator is signed out.
        scope.launch {
            try { withContext(Dispatchers.IO) { gateway.start() } }
            catch (e: CancellationException) { throw e }
            catch (_: Exception) { /* The next queue wakeup can retry. */ }
            if (ticket != null && current(ticket) && permissionView(ticket)) {
                pendingPermissions = ticket
                drained()
            }
        }
    }

    private fun permissionView(ticket: Request) =
        ticket.sheet == Sheet.GATEWAY || ticket.sheet == null && ticket.route in setOf(Route.HOME, Route.SETTINGS)

    fun takePermissionRefresh(): Request? {
        val ticket = pendingPermissions ?: return null
        pendingPermissions = null
        return ticket.takeIf { current(it) && Access.allows(it.operator, Capability.GATEWAY, clock(), receiver) }
    }

    fun refreshHealth() {
        val ticket = request()
        if (ticket == null || ticket.route != Route.SETTINGS || !Access.allows(ticket.operator, Capability.GATEWAY, clock(), receiver)) {
            health = null
            return
        }
        if (healthJob?.isActive == true && healthRequest?.let { current(it) } == true) return
        healthJob?.cancel()
        healthRequest = ticket
        healthJob = scope.launch {
            val result = try { withContext(Dispatchers.IO) { gateway.continuousHealth() } }
            catch (e: CancellationException) { throw e }
            catch (_: Exception) { null }
            current(ticket) { health = result?.let { ticket to it } }
        }
    }

    val continuousHealth: ContinuousReceiverHealth?
        get() = health?.let { (ticket, result) -> result.takeIf { current(ticket) } }
}

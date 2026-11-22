package rw.ikanisa.burimunsi.ui

import kotlinx.coroutines.CancellationException
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.NativeRepository

/** Shared by Staff and Admin Sync. Callers run storage and repository operations on IO. */
internal class NativeSessionBootstrap(
    private val repository: NativeRepository,
    private val checkpoints: NavigationCheckpointStore,
    private val receiver: Boolean,
    private val clock: () -> Long,
    private val readJournal: () -> JournalKnowledge,
) {
    class Grant(val operator: Operator, val group: String, val revision: Long)
    class Restored(val grant: Grant?, val navigation: RestorationDecision)

    sealed interface Recovery {
        data object PasscodePending : Recovery
        data object Offline : Recovery
        data object SignedOut : Recovery
        class Attached(val grant: Grant) : Recovery
    }

    private enum class Startup { IDLE, RESTORING, FOREGROUND_SHARED }
    private var startup = Startup.IDLE

    fun beginInitialRestore() { startup = Startup.RESTORING }

    fun shareInitialForeground(): Boolean {
        if (startup == Startup.IDLE) return false
        startup = Startup.FOREGROUND_SHARED
        return true
    }

    fun finishInitialRestore(completed: Boolean): Boolean {
        val retryForeground = startup == Startup.FOREGROUND_SHARED && !completed
        startup = Startup.IDLE
        return retryForeground
    }

    private fun bind(profile: Operator): Grant =
        repository.withCurrentProfile(profile) { group, revision -> Grant(profile, group, revision) }

    /** The validated group, role and generation must still own the UI publication after any suspension. */
    fun <T> withCurrent(grant: Grant, publish: () -> T): T =
        repository.withCurrentProfile(grant.operator) { group, revision ->
            checkContract(grant.group == group && grant.revision == revision, "session_changed")
            checkContract(clock() < grant.operator.expiresAt, "session_unavailable")
            publish()
        }

    fun requireCurrent(grant: Grant) = withCurrent(grant) {}

    fun restore(): Restored {
        val grant = repository.restore()?.let(::bind)
        val bookmark = if (grant == null) null else try {
            NavigationCheckpoint.decode(checkpoints.read())
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            null
        }
        val navigation = ScreenRestoration.decide(bookmark, grant?.operator, grant?.group.orEmpty(),
            clock(), receiver, readJournal())
        return Restored(grant?.takeIf { navigation.route != Route.LOGIN }, navigation)
    }

    fun login(phone: String, pin: String): Grant = bind(repository.login(phone, pin))
    fun refresh(): Grant = bind(repository.refreshSession())

    fun recover(owner: String, group: String?): Recovery {
        if (repository.hasPendingPasscode()) return Recovery.PasscodePending
        if (group == null) return Recovery.SignedOut
        return try {
            val profile = repository.reattachSameOwner(owner, group) ?: return Recovery.SignedOut
            val grant = bind(profile)
            if (profile.id == owner && grant.group == group) Recovery.Attached(grant) else Recovery.SignedOut
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            if (repository.hasSavedSession()) Recovery.Offline else Recovery.SignedOut
        }
    }
}

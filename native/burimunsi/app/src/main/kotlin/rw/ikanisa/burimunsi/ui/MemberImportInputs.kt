package rw.ikanisa.burimunsi.ui

import java.util.UUID
import rw.ikanisa.burimunsi.core.MemberImportScope

internal enum class MemberInputKind { DOCUMENT, PHOTO, CAMERA }

internal class MemberInputSelection(
    val launchId: String,
    val scope: MemberImportScope,
    val uri: String,
    val kind: MemberInputKind,
) {
    override fun toString() = "MemberInputSelection(redacted)"
}

internal class MemberImportInputs {
    private class Launch(val id: String, val scope: MemberImportScope, val kind: MemberInputKind)

    class Result internal constructor(
        val launchId: String,
        val scope: MemberImportScope,
        val kind: MemberInputKind,
        val uri: String?,
        val failure: MemberImportFailure?,
        val detectMime: (() -> String?)?,
    )

    private var flow: MemberImportScope? = null
    private var launch: Launch? = null
    private var selection: MemberInputSelection? = null
    @Volatile var pending: Result? = null
        private set

    @Synchronized
    fun clear() {
        flow = null
        launch = null
        selection = null
        pending = null
    }

    @Synchronized
    fun begin(kind: MemberInputKind, operatorId: String, collectionId: String, sessionRevision: Long): String? {
        val scope = flow?.takeIf {
            it.operatorId == operatorId && it.collectionId == collectionId && it.sessionRevision == sessionRevision
        } ?: run {
            clear()
            MemberImportScope(UUID.randomUUID().toString(), operatorId, collectionId, sessionRevision).also { flow = it }
        }
        if (launch != null || pending != null) return null
        val id = UUID.randomUUID().toString()
        launch = Launch(id, scope, kind)
        return id
    }

    @Synchronized
    fun receive(
        id: String?, uri: String?, failure: MemberImportFailure?, detectMime: (() -> String?)?,
    ): Result? {
        val source = launch?.takeIf { it.id == id } ?: return null
        launch = null
        val accepted = uri?.takeIf { it.startsWith("content://") }
        val issue = failure ?: if (uri != null && accepted == null) MemberImportFailure.UNREADABLE else null
        return Result(source.id, source.scope, source.kind, accepted, issue, detectMime).also { pending = it }
    }

    @Synchronized
    fun retainedScope(id: String): MemberImportScope? =
        pending?.takeIf { it.launchId == id }?.scope ?: selection?.takeIf { it.launchId == id }?.scope

    @Synchronized
    fun discard(result: Result): Boolean {
        if (pending !== result) return false
        pending = null
        return true
    }

    @Synchronized
    fun select(result: Result): Boolean {
        val uri = result.uri ?: return false
        if (result.failure != null || !discard(result)) return false
        selection = MemberInputSelection(result.launchId, result.scope, uri, result.kind)
        return true
    }

    @Synchronized
    fun currentSelection(): MemberInputSelection? = selection?.takeIf { launch == null && pending == null }

    @Synchronized
    fun finish(input: MemberInputSelection): Boolean {
        if (currentSelection() !== input) return false
        selection = null
        return true
    }
}

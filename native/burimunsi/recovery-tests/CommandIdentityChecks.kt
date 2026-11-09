package rw.ikanisa.burimunsi.commandidentitytests

import rw.ikanisa.burimunsi.core.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

/** Valid-but-substituted journal fixtures. These are deliberately injected faults,
 * not a claim that normal Android writes or real devices were observed to do this. */
private class Memory : OperationStore {
    var value: PendingOperation? = null
    var clears = 0
    override fun load() = value
    override fun save(value: PendingOperation) { this.value = value }
    override fun clear() { clears++; value = null }
}
private class Fixture {
    val store = Memory()
    val journal = OperationJournal(store) { "00000000-0000-4000-8000-000000000321" }
    val original = journal.prepare(Values.sha256("original-origin"), "POST allocate", "original exact payload")
    fun sent() = journal.beginAttempt(original, original.sessionScope)
    fun unknown() { journal.failAttempt(sent(), 0, true) }
    fun committed() { journal.reconcile(original, OperationState.COMMITTED) }
}
private fun refused(code: String, action: () -> Unit) {
    val error = runCatching(action).exceptionOrNull()
    check(error is ContractFailure && error.code == code) { "Expected $code, got $error" }
}
private val replacements: List<Pair<String, (PendingOperation) -> PendingOperation>> = listOf(
    "origin" to { p -> p.copy(sessionScope = Values.sha256("replacement-origin")) },
    "kind" to { p -> p.copy(kind = "PATCH different command") },
    "exact payload and valid checksum" to { p -> p.copy(body = "replacement exact payload", bodySha256 = Values.sha256("replacement exact payload")) }
)
fun main() {
    var checks = 0
    fun test(label: String, action: () -> Unit) { action(); checks++; println("PASS $label") }
    for ((field, replace) in replacements) {
        test("same-ID $field replacement blocks captured first-dispatch snapshot") {
            val f = Fixture(); val replacement = replace(f.original); f.store.value = replacement
            refused("operation_identity_changed") { f.journal.beginAttempt(f.original, f.original.sessionScope) }
            check(f.store.value == replacement && f.store.clears == 0)
        }
        for (success in listOf(true, false)) test("same-ID $field replacement fences ${if(success) "success" else "failure"} attempt callback") {
            val f = Fixture(); val attempt = f.sent(); val replacement = replace(f.store.value!!); f.store.value = replacement
            refused("operation_identity_changed") {
                if (success) f.journal.completeAttempt(attempt) else f.journal.failAttempt(attempt, 503, true)
            }
            check(f.store.value == replacement && f.store.clears == 0)
        }
        test("same-ID $field replacement fences explicit uncertainty transition") {
            val f = Fixture(); f.unknown(); val replacement = replace(f.store.value!!); f.store.value = replacement
            refused("operation_identity_changed") { f.journal.mark(f.original, OperationState.UNKNOWN) }
            check(f.store.value == replacement)
        }
        test("same-ID $field replacement fences pending observation") {
            val f = Fixture(); f.unknown(); val replacement = replace(f.store.value!!); f.store.value = replacement
            refused("operation_identity_changed") { f.journal.observePending(f.original) }
            check(f.store.value == replacement)
        }
        for (outcome in listOf(OperationState.COMMITTED, OperationState.REJECTED)) test("same-ID $field replacement fences $outcome reconciliation") {
            val f = Fixture(); f.unknown(); val replacement = replace(f.store.value!!); f.store.value = replacement
            refused("operation_identity_changed") { f.journal.reconcile(f.original, outcome) }
            check(f.store.value == replacement)
        }
        test("same-ID $field replacement before cleanup cannot touch cache") {
            val f = Fixture(); f.committed(); val replacement = replace(f.store.value!!); f.store.value = replacement
            var cacheTouched = false
            refused("operation_identity_changed") { f.journal.finishCleanup(f.original) { cacheTouched = true } }
            check(!cacheTouched && f.store.value == replacement && f.store.clears == 0)
        }
        test("same-ID $field replacement during cache invalidation cannot be deleted") {
            val f = Fixture(); f.committed(); val replacement = replace(f.store.value!!)
            refused("operation_identity_changed") { f.journal.finishCleanup(f.original) { f.store.value = replacement } }
            check(f.store.value == replacement && f.store.clears == 0)
        }
        test("latched stale response for same-ID $field replacement is refused") {
            val f = Fixture(); f.unknown(); val entered = CountDownLatch(1); val release = CountDownLatch(1)
            val failure = AtomicReference<Throwable?>()
            val worker = thread {
                try { entered.countDown(); check(release.await(5, TimeUnit.SECONDS)); f.journal.reconcile(f.original, OperationState.COMMITTED) }
                catch (e: Throwable) { failure.set(e) }
            }
            check(entered.await(5, TimeUnit.SECONDS))
            val replacement = synchronized(f.store.coordinationLock) { replace(f.store.value!!).also { f.store.value = it } }
            release.countDown(); worker.join(6000)
            check(!worker.isAlive && (failure.get() as? ContractFailure)?.code == "operation_identity_changed")
            check(f.store.value == replacement && f.store.clears == 0)
        }
    }
    for (state in listOf(OperationState.REJECTED, OperationState.UNKNOWN, OperationState.SENT, OperationState.PREPARED)) {
        test("cleanup cannot erase a changed terminal proof: COMMITTED to $state") {
            val f = Fixture(); f.committed(); val replacement = f.store.value!!.copy(state = state)
            refused("conflicting_reconciliation") { f.journal.finishCleanup(f.original) { f.store.value = replacement } }
            check(f.store.value == replacement && f.store.clears == 0)
        }
    }
    test("cleanup cannot erase a changed attempt counter with unchanged terminal state") {
        val f = Fixture(); f.committed(); val replacement = f.store.value!!.copy(attemptCount = 7)
        refused("operation_attempt_changed") { f.journal.finishCleanup(f.original) { f.store.value = replacement } }
        check(f.store.value == replacement && f.store.clears == 0)
    }
    test("cleanup successor with a different UUID stays untouched") {
        val f = Fixture(); f.committed(); val replacement = f.store.value!!.copy(requestId = "00000000-0000-4000-8000-000000000322")
        refused("operation_changed") { f.journal.finishCleanup(f.original) { f.store.value = replacement } }
        check(f.store.value == replacement && f.store.clears == 0)
    }
    test("snapshot survives legitimate PREPARED SENT UNKNOWN COMMITTED progression") {
        val f = Fixture(); f.unknown(); repeat(3) { f.journal.observePending(f.original) }
        f.committed(); f.committed(); f.journal.finishCleanup(f.original) {}
        check(f.store.value == null && f.store.clears == 1)
    }
    test("a reconstructed snapshot with equal immutable fields is accepted after restart") {
        val f = Fixture(); f.unknown(); val restored = f.store.value!!.copy()
        val restarted = OperationJournal(f.store)
        restarted.reconcile(restored, OperationState.COMMITTED); restarted.finishCleanup(restored) {}
        check(f.store.value == null)
    }
    test("checksum corruption is distinguished from self-consistent identity substitution") {
        val f = Fixture(); f.store.value = f.original.copy(body = "invalid checksum")
        refused("corrupt_operation") { f.journal.beginAttempt(f.original, f.original.sessionScope) }
        check(f.store.value!!.body == "invalid checksum" && f.store.clears == 0)
    }
    println("RESULT: $checks operation-identity fence checks passed; fault-injected snapshots and cleanup only; no physical storage or server claims.")
}

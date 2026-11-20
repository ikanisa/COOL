package rw.ikanisa.burimunsi.commandrecoverytests

import rw.ikanisa.burimunsi.core.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

/** Deterministic fault injection and finite transition exploration. No network,
 * SQL, Android, sleeps, random IDs or wall-clock-dependent decisions. */
private class Death : Error("simulated process interruption")
private class Memory : OperationStore {
    var value: PendingOperation? = null
    var saveMode = "ok"
    var clearMode = "ok"
    override fun load() = value
    override fun save(value: PendingOperation) {
        when (saveMode) {
            "before" -> throw Death()
            "drop" -> return
        }
        this.value = value
        if (saveMode == "after") throw Death()
    }
    override fun clear() {
        when (clearMode) {
            "before" -> throw Death()
            "retain" -> return
        }
        value = null
        if (clearMode == "after") throw Death()
    }
}
private fun id(n: Int) = "00000000-0000-4000-8000-" + n.toString().padStart(12, '0')
private fun journal(store: Memory): OperationJournal {
    var sequence = 0
    return OperationJournal(store) { id(++sequence) }
}
private fun refused(code: String? = null, action: () -> Unit) {
    val failure = runCatching(action).exceptionOrNull()
    check(failure is ContractFailure && (code == null || failure.message == code)) { "Expected $code, got $failure" }
}

fun main() {
    var checks = 0
    fun test(label: String, action: () -> Unit) { action(); checks++; println("PASS $label") }
    val origin = Values.sha256("synthetic-origin")
    val replacement = Values.sha256("synthetic-new-session")
    fun Memory.prepared(): PendingOperation = journal(this).prepare(origin, "POST /payments/example/allocate", "original-payload")

    test("original ID digest kind and exact payload survive timeout restart and status retry") {
        val m = Memory();val p = m.prepared();val j = journal(m)
        j.failAttempt(j.beginAttempt(p,origin),408,true)
        repeat(5) { journal(m).observePending(p) }
        check(m.value == p.copy(state=OperationState.UNKNOWN,attemptCount=1))
        refused { journal(m).beginAttempt(p,origin) }
        refused { journal(m).prepare(origin,p.kind,p.body) }
        refused { journal(m).prepare(replacement,"POST /different","new-body") }
    }
    test("PREPARED first send uses original ID without allocating replacement") {
        val m=Memory();val p=m.prepared();val j=journal(m)
        val a=j.beginAttempt(p,origin)
        check(a.requestId==p.requestId&&m.value!!.attemptCount==1)
        refused { j.beginAttempt(p,origin) }
    }
    test("re-login cannot rebind even a never-dispatched operation") {
        val m=Memory();val p=m.prepared();val j=journal(m)
        refused("pending_operation_requires_resolution") { j.beginAttempt(p,replacement) }
        check(m.value==p)
        j.observePending(p);check(m.value==p)
    }
    test("legacy ambiguous PREPARED with prior count is not dispatchable") {
        val m=Memory();val p=m.prepared();m.value=p.copy(attemptCount=1)
        refused { journal(m).beginAttempt(p,origin) };check(m.value!!.attemptCount==1)
    }
    for (state in listOf(OperationState.SENT,OperationState.UNKNOWN)) {
        test("legacy $state zero attempts cannot be rewritten as unsent") {
            val m=Memory();val p=m.prepared();m.value=p.copy(state=state)
            refused { journal(m).beginAttempt(p,origin) }
            refused { journal(m).mark(p,OperationState.SENT) }
            check(m.value==p.copy(state=state))
        }
    }
    for (status in listOf(0,200,201,202,301,307,400,401,403,404,405,408,409,413,415,422,425,429,500,502,503,504)) {
        test("status $status cannot authorize a new financial command without retained proof") {
            val m=Memory();val p=m.prepared();val j=journal(m)
            j.failAttempt(j.beginAttempt(p,origin),status,false)
            check(m.value!!.state==OperationState.UNKNOWN)
            refused { j.finishCleanup(p) { error("unknown cache must not be cleared") } }
            refused { j.prepare(origin,p.kind,p.body) }
        }
    }
    for (mode in listOf("before","after","drop")) {
        test("prepare interrupted $mode never returns a dispatchable witness") {
            val m=Memory();m.saveMode=mode
            check(runCatching { journal(m).prepare(origin,"kind","body") }.isFailure)
            m.saveMode="ok"
            if(m.value!=null)refused { journal(m).prepare(origin,"kind","replacement") }
        }
        test("dispatch-fence interrupted $mode never permits duplicate dispatch") {
            val m=Memory();val p=m.prepared();m.saveMode=mode
            check(runCatching { journal(m).beginAttempt(p,origin) }.isFailure)
            m.saveMode="ok"
            if(m.value!!.state==OperationState.SENT) refused { journal(m).beginAttempt(p,origin) }
            else check(journal(m).beginAttempt(p,origin).sequence==1) // No prior witness escaped.
        }
        test("uncertainty write interrupted $mode keeps replacement blocked") {
            val m=Memory();val p=m.prepared();val j=journal(m);val a=j.beginAttempt(p,origin)
            m.saveMode=mode;check(runCatching { j.failAttempt(a,0,true) }.isFailure);m.saveMode="ok"
            check(m.value!!.state in setOf(OperationState.SENT,OperationState.UNKNOWN))
            refused { journal(m).prepare(origin,"kind","replacement") }
            refused { journal(m).beginAttempt(p,origin) }
        }
        test("terminal-proof write interrupted $mode does not clear or replace evidence") {
            val m=Memory();val p=m.prepared();val j=journal(m);j.beginAttempt(p,origin)
            m.saveMode=mode;check(runCatching { j.reconcile(p,OperationState.COMMITTED) }.isFailure)
            m.saveMode="ok";refused { journal(m).prepare(origin,"kind","replacement") }
            journal(m).reconcile(p,OperationState.COMMITTED)
            check(m.value!!.state==OperationState.COMMITTED)
        }
    }
    for (stage in listOf("cache-before","cache-after","delete-before","delete-retain","delete-after")) {
        test("cleanup interruption at $stage resumes without command dispatch") {
            val m=Memory();val p=m.prepared();val j=journal(m)
            j.beginAttempt(p,origin);j.reconcile(p,OperationState.COMMITTED)
            var cached=true
            m.clearMode=when(stage){"delete-before"->"before";"delete-retain"->"retain";"delete-after"->"after";else->"ok"}
            check(runCatching { j.finishCleanup(p) {
                if(stage=="cache-before")throw Death()
                cached=false
                if(stage=="cache-after")throw Death()
            } }.isFailure)
            if(m.value!=null) {
                check(m.value!!.state==OperationState.COMMITTED)
                refused { journal(m).prepare(origin,"kind","replacement") }
                refused { journal(m).beginAttempt(p,origin) }
                m.clearMode="ok";journal(m).finishCleanup(p){cached=false}
            }
            // Deletion that completed before interruption is safe ONLY because the
            // terminal proof and cache invalidation occurred first.
            check(!cached && m.value==null)
        }
    }
    test("conflicting result cannot erase retained terminal proof") {
        val m=Memory();val p=m.prepared();val j=journal(m)
        j.reconcile(p,OperationState.COMMITTED);val retained=m.value
        refused("conflicting_reconciliation") { j.reconcile(p,OperationState.REJECTED) }
        refused("conflicting_reconciliation") { j.observePending(p) }
        check(m.value==retained)
        j.reconcile(p,OperationState.COMMITTED);check(m.value==retained)
    }
    test("late callbacks cannot touch successor command or its cache") {
        val m=Memory();val j=journal(m);val p=j.prepare(origin,"kind","body")
        val a=j.beginAttempt(p,origin);j.completeAttempt(a);j.finishCleanup(p){}
        val next=j.prepare(origin,"kind","next");check(next.requestId!=p.requestId)
        refused("operation_changed") { j.reconcile(p,OperationState.COMMITTED) }
        refused("operation_changed") { j.observePending(p) }
        refused("operation_changed") { j.finishCleanup(p){error("must not clear newer cache")} }
        refused("operation_changed") { j.failAttempt(a,409,false) }
        check(m.value==next)
    }
    test("corruption never becomes an empty journal") {
        val m=Memory();val p=m.prepared();m.value=p.copy(body="modified")
        refused("corrupt_operation") { journal(m).unresolved() }
        refused("corrupt_operation") { journal(m).prepare(origin,"kind","new") }
        check(m.value!!.body=="modified")
    }
    test("two journal instances sharing one store can issue only one dispatch witness") {
        val m=Memory();val p=m.prepared();val go=CountDownLatch(1);val ready=CountDownLatch(2)
        val accepted=AtomicInteger();val blocked=AtomicInteger()
        val threads=(1..2).map { thread {
            ready.countDown();check(go.await(5,TimeUnit.SECONDS))
            try { journal(m).beginAttempt(p,origin);accepted.incrementAndGet() }
            catch(_:ContractFailure){blocked.incrementAndGet()}
        } }
        check(ready.await(5,TimeUnit.SECONDS));go.countDown();threads.forEach{it.join(6000);check(!it.isAlive)}
        check(accepted.get()==1&&blocked.get()==1&&m.value!!.attemptCount==1)
    }
    test("all 100000 five-event traces preserve uncertainty and immutable request evidence") {
        // Ten actions, five steps; only this original operation is modeled.
        // A refused transition must not change any durable bytes.
        var traces=0
        fun explore(prefix:List<Int>) {
            if(prefix.size<5){for(a in 0..9)explore(prefix+a);return}
            traces++
            val m=Memory();val p=m.prepared();val j=journal(m);var witness:OperationAttempt?=null
            var dispatches=0;var confirmed=false
            for(action in prefix){
                val before=m.value
                val result=runCatching { when(action) {
                    0->{witness=j.beginAttempt(p,origin);dispatches++}
                    1->{val a=witness?:throw ContractFailure("no_witness");j.failAttempt(a,408,true)}
                    2->j.observePending(p)
                    3->{j.reconcile(p,OperationState.COMMITTED);confirmed=true}
                    4->j.finishCleanup(p) { check(confirmed) }
                    5->j.beginAttempt(p,replacement)
                    6->j.mark(p,OperationState.SENT)
                    7->j.mark(p,OperationState.UNKNOWN)
                    8->journal(m).observePending(p)
                    9->j.mark(p,OperationState.REJECTED)
                    else->error("unreachable event")
                } }
                if(result.isFailure)check(m.value==before)
                check(dispatches<=1)
                if(m.value==null)check(confirmed)
                else {
                    val value=m.value!!
                    check(value.requestId==p.requestId&&value.sessionScope==p.sessionScope&&value.body==p.body&&
                        value.bodySha256==p.bodySha256&&value.kind==p.kind&&value.attemptCount in 0..1)
                    refused { j.prepare(origin,"different","replacement") }
                }
            }
        }
        explore(emptyList());check(traces==100000)
    }
    println("RESULT: $checks deterministic command-recovery checks passed; includes 100000 enumerated traces; not PostgreSQL or Android qualification.")
}

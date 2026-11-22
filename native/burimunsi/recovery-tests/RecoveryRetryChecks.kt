package rw.ikanisa.burimunsi.recoveryretrytests

import rw.ikanisa.burimunsi.core.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

private fun original()=PendingOperation("00000000-0000-4000-8000-000000000301","a".repeat(64),
    "POST /payments/one/allocate","exact-body",Values.sha256("exact-body"),OperationState.UNKNOWN,1)
private val scope=RecoveryReadScope(1,"b".repeat(64))
private fun refused(code:String, action:()->Unit){
    val e=runCatching(action).exceptionOrNull()
    check(e is ContractFailure && e.code==code){"Expected $code, got $e"}
}
private class Store(val lock:Any=Any()):OperationStore {
    override val coordinationLock get()=lock
    var value:PendingOperation?=original()
    override fun load()=value
    override fun save(value:PendingOperation){this.value=value}
    override fun clear(){value=null}
}
fun main(){
    var checks=0
    fun test(name:String, body:()->Unit){body();checks++;println("PASS $name")}
    test("five-check default cycle uses exact exponential admission deadlines"){
        val op=original();val retry=ReadOnlyRecoveryRetry(op)
        val times=listOf(0L,1000L,3000L,7000L,15000L)
        for((i,t)in times.withIndex()){
            val ticket=retry.begin(op,scope,t)
            check(ticket.checkNumber==i+1)
            val s=retry.finish(ticket,RecoveryReadResult.PENDING,t)
            if(i<4){check(s.nextCheckAtMs==times[i+1]);refused("recovery_retry_backoff"){retry.begin(op,scope,times[i+1]-1)}}
            else check(s.phase==RecoveryRetryPhase.EXHAUSTED&&s.nextCheckAtMs==null)
        }
        refused("recovery_retry_exhausted"){retry.begin(op,scope,Long.MAX_VALUE)}
        check(retry.snapshot().checksStarted==5&&op==original())
    }
    for(result in listOf(RecoveryReadResult.PENDING,RecoveryReadResult.TRANSIENT_FAILURE,
        RecoveryReadResult.CLEANUP_FAILED,RecoveryReadResult.CANCELLED)){
        test("$result backs off without replacing the command"){
            val retry=ReadOnlyRecoveryRetry(original());val ticket=retry.begin(original(),scope,10)
            check(retry.finish(ticket,result,10).nextCheckAtMs==1010L)
            refused("recovery_retry_backoff"){retry.begin(original(),scope,1009)}
            check(retry.begin(original().copy(state=OperationState.COMMITTED),scope,1010).checkNumber==2)
        }
    }
    for(result in listOf(RecoveryReadResult.DENIED,RecoveryReadResult.INVALID_RESPONSE,RecoveryReadResult.CONFLICT)){
        test("$result stops and a different login cannot reset it"){
            val r=ReadOnlyRecoveryRetry(original());val t=r.begin(original(),scope,0)
            check(r.finish(t,result,0).phase==RecoveryRetryPhase.STOPPED)
            refused("recovery_retry_stopped"){r.begin(original(),RecoveryReadScope(2,"c".repeat(64)),99999)}
            check(r.snapshot().checksStarted==1)
        }
    }
    test("resolution stops checks without creating a replacement operation"){
        val r=ReadOnlyRecoveryRetry(original());val t=r.begin(original(),scope,0)
        check(r.finish(t,RecoveryReadResult.RESOLVED,0).phase==RecoveryRetryPhase.COMPLETE)
        refused("recovery_already_resolved"){r.begin(original(),scope,99999)}
    }
    test("re-login changes authority witness but not budget or original identity"){
        val r=ReadOnlyRecoveryRetry(original());val t=r.begin(original(),scope,0)
        r.finish(t,RecoveryReadResult.AUTH_REQUIRED,0)
        refused("recovery_authentication_required"){r.begin(original(),scope,1000)}
        val next=RecoveryReadScope(2,scope.sessionDigest) // Even A -> B -> A is a new generation.
        refused("recovery_retry_backoff"){r.begin(original(),next,999)}
        check(r.begin(original(),next,1000).checkNumber==2)
    }
    test("authentication failure on final slot exhausts rather than resets"){
        val r=ReadOnlyRecoveryRetry(original(),RecoveryRetryPolicy(maxChecks=1))
        val t=r.begin(original(),scope,0);r.finish(t,RecoveryReadResult.AUTH_REQUIRED,0)
        refused("recovery_retry_exhausted"){r.begin(original(),RecoveryReadScope(2,"c".repeat(64)),1000)}
    }
    test("busy refusal does not change time budget or release the active check"){
        val r=ReadOnlyRecoveryRetry(original());val t=r.begin(original(),scope,0);val before=r.snapshot()
        refused("recovery_check_in_progress"){r.begin(original(),scope,99999)}
        check(r.snapshot()==before);r.finish(t,RecoveryReadResult.PENDING,0)
    }
    test("duplicate completion cannot change the next deadline"){
        val r=ReadOnlyRecoveryRetry(original());val t=r.begin(original(),scope,0)
        val before=r.finish(t,RecoveryReadResult.PENDING,0)
        refused("recovery_attempt_changed"){r.finish(t,RecoveryReadResult.RESOLVED,1000)}
        check(r.snapshot()==before)
    }
    test("foreign controller ticket cannot complete a check"){
        val a=ReadOnlyRecoveryRetry(original());val b=ReadOnlyRecoveryRetry(original())
        val ta=a.begin(original(),scope,0);val tb=b.begin(original(),scope,0)
        refused("recovery_attempt_changed"){a.finish(tb,RecoveryReadResult.RESOLVED,0)}
        a.finish(ta,RecoveryReadResult.PENDING,0)
    }
    val changes=listOf<Pair<String,(PendingOperation)->PendingOperation>>(
        "request" to {it.copy(requestId="00000000-0000-4000-8000-000000000302")},
        "origin" to {it.copy(sessionScope="c".repeat(64))},"kind" to {it.copy(kind="POST /members")},
        "body" to {it.copy(body="changed",bodySha256=Values.sha256("changed"))})
    for((field,change)in changes){
        test("same retry cycle refuses changed $field without consuming a slot"){
            val r=ReadOnlyRecoveryRetry(original())
            refused(if(field=="request")"operation_changed" else "operation_identity_changed"){r.begin(change(original()),scope,0)}
            check(r.snapshot().checksStarted==0)
        }
    }
    test("corrupt record is not an ordinary pending response"){
        val r=ReadOnlyRecoveryRetry(original())
        refused("corrupt_operation"){r.begin(original().copy(body="tampered"),scope,0)}
    }
    test("negative clock cannot admit or finish a check"){
        val r=ReadOnlyRecoveryRetry(original());refused("recovery_clock_invalid"){r.begin(original(),scope,-1)}
        val t=r.begin(original(),scope,0);refused("recovery_clock_invalid"){r.finish(t,RecoveryReadResult.PENDING,-1)}
        r.finish(t,RecoveryReadResult.PENDING,0)
    }
    test("backward completion clock keeps original ticket recoverable"){
        val r=ReadOnlyRecoveryRetry(original());val t=r.begin(original(),scope,500)
        refused("recovery_clock_invalid"){r.finish(t,RecoveryReadResult.PENDING,499)}
        r.finish(t,RecoveryReadResult.PENDING,500)
    }
    test("backoff delay saturates at configured cap without overflow"){
        val r=ReadOnlyRecoveryRetry(original(),RecoveryRetryPolicy(10,2,5));var now=0L
        val expected=listOf(2L,4L,5L,5L,5L,5L,5L,5L,5L)
        expected.forEach {delay->val t=r.begin(original(),scope,now);val s=r.finish(t,RecoveryReadResult.PENDING,now)
            check(s.nextCheckAtMs==now+delay);now=s.nextCheckAtMs!!}
    }
    test("server delay floor is not shortened to local maximum"){
        val r=ReadOnlyRecoveryRetry(original());val t=r.begin(original(),scope,0)
        check(r.finish(t,RecoveryReadResult.TRANSIENT_FAILURE,0,100_000).nextCheckAtMs==100_000L)
    }
    test("negative delay refused without releasing ticket"){
        val r=ReadOnlyRecoveryRetry(original());val t=r.begin(original(),scope,0)
        refused("invalid_recovery_delay"){r.finish(t,RecoveryReadResult.PENDING,0,-1)}
        r.finish(t,RecoveryReadResult.PENDING,0)
    }
    test("unrepresentable deadline stops rather than wrapping to immediate retry"){
        val r=ReadOnlyRecoveryRetry(original());val t=r.begin(original(),scope,Long.MAX_VALUE-1)
        val s=r.finish(t,RecoveryReadResult.PENDING,Long.MAX_VALUE-1)
        check(s.phase==RecoveryRetryPhase.STOPPED&&s.reason=="recovery_clock_exhausted")
    }
    for(config in listOf(Triple(0,1L,1L),Triple(101,1L,1L),Triple(1,0L,1L),Triple(1,2L,1L))){
        test("invalid policy $config is rejected"){check(runCatching{RecoveryRetryPolicy(config.first,config.second,config.third)}.isFailure)}
    }
    test("shared namespace rejects reentrant and cross-wrapper status reads"){
        val store=Store();val a=OperationJournal(store);val b=OperationJournal(store)
        a.withRecoveryRead(original()){
            refused("recovery_check_in_progress"){a.withRecoveryRead(original()){error("must not execute")}}
            refused("recovery_check_in_progress"){b.withRecoveryRead(original()){error("must not execute")}}
        }
        check(b.withRecoveryRead(original()){7}==7)
    }
    for(fault in listOf<Throwable>(IllegalStateException("synthetic"),InterruptedException("synthetic"),AssertionError("synthetic"))){
        test("read lease unwinds for ${fault.javaClass.simpleName}"){
            val j=OperationJournal(Store());check(runCatching{j.withRecoveryRead(original()){throw fault}}.isFailure)
            check(j.withRecoveryRead(original()){true})
        }
    }
    test("different namespace status reads remain independent"){
        val a=OperationJournal(Store());val b=OperationJournal(Store())
        a.withRecoveryRead(original()){check(b.withRecoveryRead(original()){true})}
    }
    test("equal but distinct lock objects do not coalesce namespaces"){
        data class EqualLock(val n:Int)
        val a=OperationJournal(Store(EqualLock(1)));val b=OperationJournal(Store(EqualLock(1)))
        a.withRecoveryRead(original()){check(b.withRecoveryRead(original()){true})}
    }
    test("held lease does not hold journal lock across I/O"){
        val store=Store();val a=OperationJournal(store);val b=OperationJournal(store)
        val entered=CountDownLatch(1);val release=CountDownLatch(1);val error=AtomicReference<Throwable?>()
        val t=thread{try{a.withRecoveryRead(original()){entered.countDown();check(release.await(5,TimeUnit.SECONDS))}}catch(e:Throwable){error.set(e)}}
        try{check(entered.await(5,TimeUnit.SECONDS));check(b.unresolved()==original())
            refused("recovery_check_in_progress"){b.withRecoveryRead(original()){error("not reached")}}
            refused("pending_operation_requires_resolution"){b.prepare("scope","POST /new","{}")}
        }finally{release.countDown();t.join(5000)}
        check(!t.isAlive&&error.get()==null)
        check(b.withRecoveryRead(original()){true})
    }
    test("invalid snapshot fails before acquiring a lease"){
        val j=OperationJournal(Store());refused("operation_identity_changed"){j.withRecoveryRead(original().copy(kind="changed")){}}
        check(j.withRecoveryRead(original()){true})
    }
    test("exhaustion cannot unblock journal or authorize a financial retry"){
        val store=Store();val j=OperationJournal(store);val r=ReadOnlyRecoveryRetry(original(),RecoveryRetryPolicy(1))
        val t=r.begin(original(),scope,0);r.finish(t,RecoveryReadResult.TRANSIENT_FAILURE,0)
        refused("pending_operation_requires_resolution"){j.beginAttempt(original(),original().sessionScope)}
        refused("pending_operation_requires_resolution"){j.prepare("scope","POST /new","{}")}
        check(j.unresolved()==original())
    }
    test("retry controller binds immutable A04 owner and group as well as command bytes") {
        val owned=original().copy(ownerAccountId="operator",groupId="group")
        val retry=ReadOnlyRecoveryRetry(owned)
        refused("operation_identity_changed"){retry.begin(owned.copy(ownerAccountId="other"),scope,0)}
        refused("operation_identity_changed"){retry.begin(owned.copy(groupId="other"),scope,0)}
        check(retry.snapshot().checksStarted==0)
    }
    println("RESULT: $checks read-only recovery retry and lease checks passed; no network, storage durability or PostgreSQL qualification.")
}

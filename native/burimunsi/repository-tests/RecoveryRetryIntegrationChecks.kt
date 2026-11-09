package rw.ikanisa.burimunsi.commandrecoveryintegrationtests

import android.content.Context
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.burimunsi.storage.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

private fun refusal(code:String,action:()->Unit){
    val e=runCatching(action).exceptionOrNull()
    check(e is ContractFailure&&e.code==code){"Expected $code, got $e"}
}
fun main(){
    var checks=0
    fun test(name:String,body:()->Unit){SecureStore.reset();body();checks++;println("PASS $name")}
    test("bounded repository status retries exhaust with unchanged journal and one original POST"){
        val f=Fixture();val op=f.unknown();val bytes=SecureStore.records.getValue("pending-command")
        val r=ReadOnlyRecoveryRetry(op)
        for(now in listOf(0L,1000L,3000L,7000L,15000L))f.repo.reconcilePending(r,now)
        refusal("recovery_retry_exhausted"){f.repo.reconcilePending(r,99999)}
        check(r.snapshot().checksStarted==5&&f.posts.get()==1&&f.reads.get()==5)
        check(f.repo.pending()==op&&SecureStore.records["pending-command"]==bytes)
        refusal("pending_operation_requires_resolution"){f.repo.retryPending()}
    }
    test("backoff refusal neither emits GET nor consumes budget"){
        val f=Fixture();val r=ReadOnlyRecoveryRetry(f.unknown());f.repo.reconcilePending(r,0)
        refusal("recovery_retry_backoff"){f.repo.reconcilePending(r,999)}
        check(f.reads.get()==1&&r.snapshot().checksStarted==1)
        f.repo.reconcilePending(r,1000);check(f.reads.get()==2)
    }
    for(status in listOf(0,429,500,503)){
        test("status $status transient failure retries only GET with original identity"){
            val f=Fixture();val op=f.unknown();val r=ReadOnlyRecoveryRetry(op)
            f.recoveryFailure=ApiFailure(if(status==0)"connection_unavailable" else "synthetic_error",status,true)
            check(runCatching{f.repo.reconcilePending(r,0)}.exceptionOrNull() is ApiFailure)
            check(r.snapshot().phase==RecoveryRetryPhase.BACKOFF&&f.repo.pending()==op)
            f.recoveryFailure=null;f.repo.reconcilePending(r,1000)
            check(f.posts.get()==1&&f.reads.get()==2)
            check(f.api.calls.filter{it.path.endsWith("/recovery")}.all{
                it.method=="GET"&&it.body==null&&it.recoveryOrigin==op.sessionScope&&it.path.contains(op.requestId)})
        }
    }
    for(status in listOf(403,404,409,422)){
        test("status $status stops bounded polling without resolving the financial action"){
            val f=Fixture();val op=f.unknown();val r=ReadOnlyRecoveryRetry(op)
            f.recoveryFailure=ApiFailure("synthetic_error",status,false)
            check(runCatching{f.repo.reconcilePending(r,0)}.isFailure)
            check(r.snapshot().phase==RecoveryRetryPhase.STOPPED)
            f.login();f.recoveryFailure=null
            refusal("recovery_retry_stopped"){f.repo.reconcilePending(r,99999)}
            check(f.reads.get()==1&&f.posts.get()==1&&f.repo.pending()==op)
        }
    }
    test("invalid response marked 503 stops rather than becoming an ordinary transport retry"){
        val f=Fixture();val op=f.unknown();val r=ReadOnlyRecoveryRetry(op)
        f.recoveryFailure=ApiFailure("invalid_api_response",503,true)
        check(runCatching{f.repo.reconcilePending(r,0)}.isFailure)
        check(r.snapshot().phase==RecoveryRetryPhase.STOPPED&&f.repo.pending()==op)
    }
    test("401 requires sign-in but new authority does not reset original command or budget"){
        val f=Fixture();val op=f.unknown();val r=ReadOnlyRecoveryRetry(op)
        f.recoveryFailure=ApiFailure("session_unavailable",401,false)
        check(runCatching{f.repo.reconcilePending(r,0)}.isFailure)
        check(r.snapshot().phase==RecoveryRetryPhase.AUTH_REQUIRED)
        check(runCatching{f.repo.reconcilePending(r,1000)}.isFailure&&r.snapshot().checksStarted==1)
        f.token="b".repeat(64);f.login();f.recoveryFailure=null
        f.repo.reconcilePending(r,1000)
        check(f.api.calls.last().token==f.token&&f.api.calls.last().recoveryOrigin==op.sessionScope)
        check(f.repo.pending()==op&&r.snapshot().checksStarted==2&&f.posts.get()==1)
    }
    test("valid committed outcome completes cycle only after journal cleanup"){
        val f=Fixture();val op=f.unknown();val r=ReadOnlyRecoveryRetry(op);f.state="committed"
        val status=f.repo.reconcilePending(r,0)
        check(status.getString("state")=="committed"&&f.repo.pending()==null)
        check(r.snapshot().phase==RecoveryRetryPhase.COMPLETE&&f.posts.get()==1)
    }
    for(failedStore in listOf("records","pending-command")){
        test("ineffective $failedStore cleanup retains evidence and read-only retry completes it"){
            val f=Fixture();val op=f.unknown();val r=ReadOnlyRecoveryRetry(op);f.state="committed"
            SecureStore.records["records"]="synthetic stale cache";SecureStore.retainClear=failedStore
            check(runCatching{f.repo.reconcilePending(r,0)}.isFailure)
            check(r.snapshot().phase==RecoveryRetryPhase.BACKOFF&&r.snapshot().reason=="cleanup_failed")
            check(f.repo.pending()?.state==OperationState.COMMITTED)
            SecureStore.retainClear=null;f.repo.reconcilePending(r,1000)
            check(f.repo.pending()==null&&r.snapshot().phase==RecoveryRetryPhase.COMPLETE&&f.posts.get()==1)
        }
    }
    test("pending after retained commitment stops rather than discarding known outcome"){
        val f=Fixture();val op=f.unknown();AndroidOperationStore(Context()).save(op.copy(state=OperationState.COMMITTED))
        val r=ReadOnlyRecoveryRetry(op)
        refusal("conflicting_reconciliation"){f.repo.reconcilePending(r,0)}
        check(r.snapshot().phase==RecoveryRetryPhase.STOPPED&&f.repo.pending()?.state==OperationState.COMMITTED)
    }
    test("same-ID changed payload is rejected before a bounded GET"){
        val f=Fixture();val op=f.unknown();val r=ReadOnlyRecoveryRetry(op)
        val changed=op.copy(body="replacement",bodySha256=Values.sha256("replacement"));AndroidOperationStore(Context()).save(changed)
        refusal("operation_identity_changed"){f.repo.reconcilePending(r,0)}
        check(f.reads.get()==0&&r.snapshot().checksStarted==0&&f.repo.pending()==changed)
    }
    test("changed response ownership stops polling and retains original evidence"){
        val f=Fixture();val op=f.unknown();val r=ReadOnlyRecoveryRetry(op);val old=f.api.handler
        f.api.handler={request->if(request.path.endsWith("/recovery"))old(request).replace("operator-1","operator-2")else old(request)}
        check(runCatching{f.repo.reconcilePending(r,0)}.isFailure)
        check(r.snapshot().phase==RecoveryRetryPhase.STOPPED&&f.repo.pending()==op&&f.posts.get()==1)
    }
    test("malformed JSON is not silently retried"){
        val f=Fixture();val op=f.unknown();val r=ReadOnlyRecoveryRetry(op);val old=f.api.handler
        f.api.handler={request->if(request.path.endsWith("/recovery"))"not-json" else old(request)}
        check(runCatching{f.repo.reconcilePending(r,0)}.isFailure)
        check(r.snapshot().phase==RecoveryRetryPhase.STOPPED&&f.repo.pending()==op)
    }
    test("interrupted status check releases lease but never releases financial gate"){
        val f=Fixture();val op=f.unknown();val r=ReadOnlyRecoveryRetry(op)
        f.beforeResponse={throw InterruptedException("synthetic interruption")}
        check(runCatching{f.repo.reconcilePending(r,0)}.exceptionOrNull() is InterruptedException)
        check(r.snapshot().reason=="cancelled"&&f.repo.pending()==op)
        f.beforeResponse=null;f.repo.reconcilePending(r,1000)
        check(f.posts.get()==1&&f.reads.get()==2)
    }
    test("shared status lease spans repository wrappers and busy denial costs no retry slot"){
        val f=Fixture();val op=f.unknown();val other=NativeRepository(Context(),f.api,"group-1");other.login("0780000001","2468")
        val retry=ReadOnlyRecoveryRetry(op);val entered=CountDownLatch(1);val release=CountDownLatch(1)
        val failure=AtomicReference<Throwable?>()
        f.beforeResponse={entered.countDown();check(release.await(5,TimeUnit.SECONDS))}
        val worker=thread{try{f.repo.reconcilePending()}catch(e:Throwable){failure.set(e)}}
        try{
            check(entered.await(5,TimeUnit.SECONDS))
            refusal("recovery_check_in_progress"){other.reconcilePending(retry,0)}
            check(retry.snapshot().checksStarted==0&&f.reads.get()==1&&other.pending()==op)
            // Re-login does not steal an outstanding lease.
            other.login("0780000001","2468")
            refusal("recovery_check_in_progress"){other.reconcilePending()}
        }finally{f.beforeResponse=null;release.countDown();worker.join(6000)}
        check(!worker.isAlive&&failure.get()==null)
        other.reconcilePending(retry,0);check(f.reads.get()==2&&f.posts.get()==1)
    }
    test("status lease remains held throughout terminal cleanup"){
        val f=Fixture();val op=f.unknown();f.state="committed";var calls=0
        SecureStore.beforeClear={name->if(name=="records"){
            calls++;refusal("recovery_check_in_progress"){f.repo.reconcilePending()}
            check(f.repo.pending()?.state==OperationState.COMMITTED)
        }}
        f.repo.reconcilePending();SecureStore.beforeClear=null
        check(calls==1&&f.reads.get()==1&&f.posts.get()==1&&f.repo.pending()==null&&op.requestId.isNotBlank())
    }
    test("late response after re-login retains original record and consumes only its status slot"){
        val f=Fixture();val op=f.unknown();val r=ReadOnlyRecoveryRetry(op);f.state="committed"
        f.beforeResponse={f.beforeResponse=null;f.token="b".repeat(64);f.login()}
        refusal("session_changed"){f.repo.reconcilePending(r,0)}
        check(f.repo.pending()==op&&r.snapshot().checksStarted==1&&r.snapshot().phase==RecoveryRetryPhase.AUTH_REQUIRED)
        f.state="pending";f.repo.reconcilePending(r,1000);check(f.posts.get()==1)
    }
    test("manual status check after local cycle exhaustion is still GET-only"){
        val f=Fixture();val op=f.unknown();val r=ReadOnlyRecoveryRetry(op,RecoveryRetryPolicy(1))
        f.repo.reconcilePending(r,0);check(r.snapshot().phase==RecoveryRetryPhase.EXHAUSTED)
        f.state="committed";f.repo.reconcilePending()
        check(f.reads.get()==2&&f.posts.get()==1&&f.repo.pending()==null)
        check(r.snapshot().phase==RecoveryRetryPhase.EXHAUSTED) // No implicit controller reset.
    }
    println("RESULT: $checks bounded recovery repository checks passed; actual repository and synthetic dependencies; no live service or database qualification.")
}

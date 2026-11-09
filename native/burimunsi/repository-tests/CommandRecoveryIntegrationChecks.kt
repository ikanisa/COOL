package rw.ikanisa.burimunsi.commandrecoveryintegrationtests

import android.content.Context
import org.json.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.burimunsi.storage.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

internal class Fixture {
    val api=ApiClient("installation-1")
    val repo=NativeRepository(Context(),api,"group-1")
    val posts=AtomicInteger();val reads=AtomicInteger()
    var token="a".repeat(64)
    var state="pending"
    var postFailure:ApiFailure?=ApiFailure("connection_unavailable",0,true)
    var recoveryFailure:ApiFailure?=null
    var beforePost:(()->Unit)?=null
    var beforeResponse:(()->Unit)?=null
    val payment=Payment("payment-1","Payer","+250780000001",10000,"at","ft-1","unallocated",1)
    val member=Member("member-1","Member","+250780000001",10000,true,1)
    init {
        api.handler={req->when {
            req.path.endsWith("/session/login")||req.path.endsWith("/session")->JSONObject()
                .put("token",token).put("expiresAt",4102444800000L)
                .put("profile",JSONObject().put("id","operator-1").put("name","Synthetic Operator")
                    .put("phone","+250780000001").put("role","admin")
                    .put("capabilities",JSONArray().put("records.read").put("payments.allocate"))).toString()
            req.path.endsWith("/allocate")->{posts.incrementAndGet();beforePost?.invoke();postFailure?.let{throw it};"{}"}
            req.path.endsWith("/recovery")->{
                reads.incrementAndGet();recoveryFailure?.let{throw it}
                check(req.method=="GET"&&req.body==null)
                val response=JSONObject().put("protocol","burimunsi.operation-recovery.v1")
                    .put("requestId",req.path.substringBeforeLast('/').substringAfterLast('/'))
                    .put("state",state).put("originDigest",req.recoveryOrigin).put("groupId","group-1")
                    .put("actorId","operator-1").put("installationId","installation-1").toString()
                beforeResponse?.invoke();response
            }
            req.path.contains("/operations/")->JSONObject().put("contractVersion",2)
                .put("requestId",req.path.substringAfterLast('/')).put("groupId","group-1").put("actorId","operator-1")
                .put("state",state).put("operation","burimunsi.allocate").put("financialState","posted").toString()
            else->error("Unexpected path: ${req.path}")
        }}
        login()
    }
    fun login(){repo.login("0780000001","2468")}
    fun unknown():PendingOperation {
        runCatching { repo.allocate(payment,member,"Synthetic verified identity") }
        return repo.pending()!!.also{check(it.state==OperationState.UNKNOWN)}
    }
    fun prepared():PendingOperation {
        val payload=JSONObject().put("method","POST").put("path","/payments/payment-1/allocate")
            .put("body",JSONObject().put("memberId","member-1").put("expectedVersion",1)
                .put("note","Synthetic original operation")).toString()
        return PendingOperation("00000000-0000-4000-8000-000000000123",Values.sha256(token),
            "POST /payments/payment-1/allocate",payload,Values.sha256(payload),OperationState.PREPARED).also {
            AndroidOperationStore(Context()).save(it)
        }
    }
}
private fun errorCode(expected:String,action:()->Unit) {
    val error=runCatching(action).exceptionOrNull()
    check(error is ContractFailure && error.code==expected) { "Expected $expected, got $error" }
}
fun main(){
    var checks=0
    fun test(label:String,run:()->Unit){SecureStore.reset();run();checks++;println("PASS $label")}
    test("restored PREPARED sends its original operation ID once") {
        val f=Fixture();val original=f.prepared();f.postFailure=null;f.state="committed"
        f.repo.retryPending()
        val post=f.api.calls.single{it.path.endsWith("/allocate")}
        check(post.body!!.getString("requestId")==original.requestId&&f.posts.get()==1&&f.repo.pending()==null)
    }
    test("re-login before first send cannot change original request owner") {
        val f=Fixture();val original=f.prepared();f.repo.clearOperator();f.token="b".repeat(64);f.login()
        errorCode("pending_operation_requires_resolution"){f.repo.retryPending()}
        f.repo.reconcilePending()
        check(f.posts.get()==0&&f.repo.pending()==original)
        val req=f.api.calls.last();check(req.token==f.token&&req.recoveryOrigin==original.sessionScope)
    }
    for(status in listOf(400,401,403,404,409,422,429,500,503)) {
        test("first POST HTTP $status retains operation and cannot authorize replacement") {
            val f=Fixture();f.postFailure=ApiFailure("synthetic_http_error",status,false)
            val original=f.unknown();f.login()
            check(runCatching { f.repo.allocate(f.payment,f.member,"Another action") }.isFailure)
            check(runCatching { f.repo.retryPending() }.isFailure)
            check(f.posts.get()==1&&f.repo.pending()==original)
        }
    }
    test("status timeout retries remain GET-only with unchanged request evidence") {
        val f=Fixture();val original=f.unknown();val bytes=SecureStore.records.getValue("pending-command")
        f.recoveryFailure=ApiFailure("connection_unavailable",0,true)
        repeat(3){check(runCatching{f.repo.reconcilePending()}.isFailure)}
        f.recoveryFailure=null;f.repo.reconcilePending()
        check(f.posts.get()==1&&f.reads.get()==4&&f.repo.pending()==original)
        check(SecureStore.records.getValue("pending-command")==bytes)
    }
    for(mode in listOf("throw","drop")) {
        test("$mode during prepare prevents all financial dispatch") {
            val f=Fixture()
            if(mode=="throw")SecureStore.failWrite="pending-command" else SecureStore.dropWrite="pending-command"
            check(runCatching{f.repo.allocate(f.payment,f.member,"Original action")}.isFailure)
            check(f.posts.get()==0)
        }
        test("$mode during SENT fence prevents all financial dispatch") {
            val f=Fixture();val p=f.prepared()
            if(mode=="throw")SecureStore.failWrite="pending-command" else SecureStore.dropWrite="pending-command"
            check(runCatching{f.repo.retryPending()}.isFailure)
            check(f.posts.get()==0&&f.repo.pending()==p)
        }
    }
    test("persisted committed proof survives repository recreation after cleanup failure") {
        val f=Fixture();val p=f.unknown();f.state="committed";SecureStore.retainClear="records"
        SecureStore.records["records"]="stale"
        check(runCatching{f.repo.reconcilePending()}.isFailure)
        check(f.repo.pending()?.state==OperationState.COMMITTED)
        val restarted=NativeRepository(Context(),f.api,"group-1")
        SecureStore.retainClear=null;restarted.login("0780000001","2468")
        f.state="pending"
        errorCode("conflicting_reconciliation"){restarted.reconcilePending()}
        check(restarted.pending()?.requestId==p.requestId&&restarted.pending()?.state==OperationState.COMMITTED)
        f.state="committed";restarted.reconcilePending()
        check(restarted.pending()==null&&f.posts.get()==1)
    }
    test("throwing journal deletion retains terminal proof until read-only cleanup succeeds") {
        val f=Fixture();val p=f.unknown();f.state="committed";SecureStore.failClear="pending-command"
        check(runCatching{f.repo.reconcilePending()}.isFailure)
        check(f.repo.pending()?.state==OperationState.COMMITTED&&f.repo.pending()?.requestId==p.requestId)
        SecureStore.failClear=null;f.repo.reconcilePending();check(f.repo.pending()==null&&f.posts.get()==1)
    }
    for(value in listOf<Any>("0",false,-1L,1.5,2147483648L)) {
        test("corrupt attemptCount ${value.javaClass.simpleName}:$value fails closed without deletion") {
            val f=Fixture();f.prepared()
            val bytes=JSONObject(SecureStore.records.getValue("pending-command")).put("attemptCount",value).toString()
            SecureStore.records["pending-command"]=bytes
            errorCode("corrupt_operation"){f.repo.pending()}
            check(runCatching{f.repo.retryPending()}.isFailure&&f.posts.get()==0)
            check(SecureStore.records["pending-command"]==bytes)
        }
    }
    test("legacy SENT journal without attemptCount stays unsendable") {
        val f=Fixture();f.prepared()
        val j=JSONObject(SecureStore.records.getValue("pending-command"));j.put("state","SENT");j.remove("attemptCount")
        SecureStore.records["pending-command"]=j.toString()
        check(f.repo.pending()?.state==OperationState.SENT)
        errorCode("pending_operation_requires_resolution"){f.repo.retryPending()};check(f.posts.get()==0)
    }
    test("two repository instances cannot both dispatch one PREPARED operation") {
        val f=Fixture();val p=f.prepared();val other=NativeRepository(Context(),f.api,"group-1")
        other.login("0780000001","2468")
        val entered=CountDownLatch(1);val release=CountDownLatch(1)
        f.beforePost={entered.countDown();check(release.await(5,TimeUnit.SECONDS))}
        val failure=AtomicReference<Throwable?>()
        val worker=thread{try{f.repo.retryPending()}catch(e:Throwable){failure.set(e)}}
        check(entered.await(5,TimeUnit.SECONDS))
        try { errorCode("pending_operation_requires_resolution"){other.retryPending()} }
        finally { release.countDown();worker.join(6000) }
        check(!worker.isAlive&&failure.get() is ApiFailure&&f.posts.get()==1&&f.repo.pending()?.requestId==p.requestId)
    }
    test("old pending response cannot touch successor command after cleanup") {
        val f=Fixture();val old=f.unknown();val entered=CountDownLatch(1);val release=CountDownLatch(1)
        val failure=AtomicReference<Throwable?>()
        f.beforeResponse={entered.countDown();check(release.await(5,TimeUnit.SECONDS))}
        val worker=thread{try{f.repo.reconcilePending()}catch(e:Throwable){failure.set(e)}}
        check(entered.await(5,TimeUnit.SECONDS))
        f.beforeResponse=null;f.state="committed"
        // A concurrent repository GET is now refused. Preserve the original stale-
        // callback invariant with deliberate out-of-band journal fixture cleanup.
        // This simulates substituted storage; it is not a cross-process proof.
        errorCode("recovery_check_in_progress"){f.repo.reconcilePending()}
        val outOfBand=OperationJournal(AndroidOperationStore(Context()))
        outOfBand.reconcile(old,OperationState.COMMITTED)
        outOfBand.finishCleanup(old){SecureStore.records.remove("records")}
        val next=f.unknown();check(next.requestId!=old.requestId)
        release.countDown();worker.join(6000)
        check(!worker.isAlive&&(failure.get() as? ContractFailure)?.code=="operation_changed")
        check(f.repo.pending()==next&&f.posts.get()==2)
    }
    test("A to B to A re-login fences a delayed committed response") {
        val f=Fixture();val p=f.unknown();f.state="committed"
        val entered=CountDownLatch(1);val release=CountDownLatch(1);val failure=AtomicReference<Throwable?>()
        f.beforeResponse={entered.countDown();check(release.await(5,TimeUnit.SECONDS))}
        val worker=thread{try{f.repo.reconcilePending()}catch(e:Throwable){failure.set(e)}}
        check(entered.await(5,TimeUnit.SECONDS))
        f.token="b".repeat(64);f.login();f.token="a".repeat(64);f.login()
        release.countDown();worker.join(6000)
        check(!worker.isAlive&&(failure.get() as? ContractFailure)?.code=="session_changed")
        check(f.repo.pending()==p&&f.posts.get()==1)
    }
    val replacements:List<Pair<String,(PendingOperation)->PendingOperation>> = listOf(
        "origin" to { p -> p.copy(sessionScope=Values.sha256("synthetic-replacement-origin")) },
        "kind" to { p -> p.copy(kind="POST /members") },
        "body" to { p ->
            val body=JSONObject(p.body);body.getJSONObject("body").put("note","Different exact command payload")
            val bytes=body.toString();p.copy(body=bytes,bodySha256=Values.sha256(bytes))
        }
    )
    for((field,replace) in replacements){
        test("prepared snapshot cannot dispatch after same-ID $field substitution") {
            val f=Fixture();val p=f.prepared();val replacement=replace(p)
            SecureStore.afterRead={name,_->if(name=="pending-command"){
                SecureStore.afterRead=null;AndroidOperationStore(Context()).save(replacement)
            }}
            errorCode("operation_identity_changed"){f.repo.retryPending()}
            check(f.posts.get()==0&&f.reads.get()==0&&f.repo.pending()==replacement)
        }
        for(status in listOf("pending","committed")){
            test("delayed $status GET cannot alter same-ID $field replacement") {
                val f=Fixture();f.unknown();f.state=status
                val replacement=replace(f.repo.pending()!!)
                f.beforeResponse={AndroidOperationStore(Context()).save(replacement)}
                errorCode("operation_identity_changed"){f.repo.reconcilePending()}
                check(f.repo.pending()==replacement&&f.posts.get()==1&&f.reads.get()==1)
            }
        }
        for(success in listOf(true,false)){
            test("${if(success) "successful" else "failed"} POST callback cannot alter same-ID $field replacement") {
                val f=Fixture();val p=f.prepared()
                if(success){f.postFailure=null;f.state="committed"}
                var replacement:PendingOperation?=null
                f.beforePost={replacement=replace(f.repo.pending()!!);AndroidOperationStore(Context()).save(replacement!!)}
                val failure=runCatching{f.repo.retryPending()}.exceptionOrNull()
                if(success)check((failure as? ContractFailure)?.code=="operation_identity_changed")
                else check(failure is ApiFailure)
                check(f.repo.pending()==replacement&&f.posts.get()==1&&f.repo.pending()?.requestId==p.requestId)
                // A failed transport must not rewrite the substituted SENT record to UNKNOWN.
                check(f.repo.pending()?.state==OperationState.SENT)
            }
        }
        test("cache cleanup hook cannot delete same-ID $field replacement") {
            val f=Fixture();f.unknown();f.state="committed"
            var replacement:PendingOperation?=null
            SecureStore.beforeClear={name->if(name=="records"){
                replacement=replace(f.repo.pending()!!);AndroidOperationStore(Context()).save(replacement!!)
            }}
            errorCode("operation_identity_changed"){f.repo.reconcilePending()}
            check(f.repo.pending()==replacement&&f.repo.pending()?.state==OperationState.COMMITTED&&f.posts.get()==1)
            SecureStore.beforeClear=null
            check(runCatching{f.repo.allocate(f.payment,f.member,"Blocked replacement")}.isFailure)
        }
    }
    for(replacementState in listOf(OperationState.REJECTED,OperationState.UNKNOWN)){
        test("cleanup hook preserves conflicting $replacementState evidence") {
            val f=Fixture();f.unknown();f.state="committed"
            var replacement:PendingOperation?=null
            SecureStore.beforeClear={name->if(name=="records"){
                replacement=f.repo.pending()!!.copy(state=replacementState);AndroidOperationStore(Context()).save(replacement!!)
            }}
            errorCode("conflicting_reconciliation"){f.repo.reconcilePending()}
            check(f.repo.pending()==replacement&&f.posts.get()==1)
        }
    }
    test("cleanup hook preserves a substituted attempt counter") {
        val f=Fixture();f.unknown();f.state="committed"
        var replacement:PendingOperation?=null
        SecureStore.beforeClear={name->if(name=="records"){
            replacement=f.repo.pending()!!.copy(attemptCount=7);AndroidOperationStore(Context()).save(replacement!!)
        }}
        errorCode("operation_attempt_changed"){f.repo.reconcilePending()}
        check(f.repo.pending()==replacement&&f.posts.get()==1)
    }
    println("RESULT: $checks command-recovery integration checks passed; actual repository/journal/adapter with synthetic storage, JSON and transport; no Android or PostgreSQL claims.")
}

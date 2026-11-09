package rw.ikanisa.burimunsi.recoverytests
import android.content.Context
import org.json.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.burimunsi.storage.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/** Actual repository/DTO/journal; synthetic storage and transport, not Android/SQL. */
fun main(){
 var checks=0
 fun ck(label:String,value:Boolean){check(value){label};println("PASS $label");checks++}
 val tokenA="a".repeat(64);val tokenB="b".repeat(64)
 var bearer=tokenA;var operatorId="operator-1";var posts=0;var lookups=0
 var outcome="pending";var mutateFailure=true;var deny=false;var unsupported=false
 var edit:((JSONObject)->Unit)?=null;var latch:CountDownLatch?=null;var started:CountDownLatch?=null
 var lastOrigin:String?=null;var lastBearer:String?=null;var lastPath=""
 val api=ApiClient("phone-1")
 fun profile()=JSONObject().put("id",operatorId).put("name","Example Operator").put("phone","+250780000001").put("role","admin").put("capabilities",JSONArray().put("records.read").put("payments.allocate"))
 api.handler={req->when{
  req.path.endsWith("/session/login")||req.path.endsWith("/session")->JSONObject().put("token",bearer).put("expiresAt",System.currentTimeMillis()+3600000).put("profile",profile()).toString()
  req.path.endsWith("/allocate")->{posts++;if(mutateFailure)throw ApiFailure("connection_unavailable",0,true);"{}"}
  req.path.endsWith("/recovery")->{lookups++;lastOrigin=req.recoveryOrigin;lastBearer=req.token;lastPath=req.path
   check(req.method=="GET"&&req.body==null)
   if(unsupported)throw ApiFailure("not_found",404)
   if(deny)throw ApiFailure("operation_recovery_denied",403)
   val response=JSONObject().put("protocol","burimunsi.operation-recovery.v1").put("requestId",req.path.substringBeforeLast('/').substringAfterLast('/'))
    .put("state",outcome).put("originDigest",req.recoveryOrigin).put("groupId","group-1").put("actorId",operatorId).put("installationId","phone-1")
   edit?.invoke(response);started?.countDown();check(latch?.await(5,TimeUnit.SECONDS)!=false);response.toString()
  }
  req.path.contains("/operations/")->JSONObject().put("contractVersion",2).put("requestId",req.path.substringAfterLast('/'))
   .put("groupId","group-1").put("actorId",operatorId).put("state",outcome).put("operation","burimunsi.allocate").put("financialState","posted").toString()
  else->error("Unexpected endpoint "+req.path)
 }}
 SecureStore.reset();val repo=NativeRepository(Context(),api,"group-1")
 val payment=Payment("payment-1","Payer","+250780000816",10000,"at","ft-1","unallocated",1)
 val member=Member("member-1","Member","+250780000816",10000,true,1)
 fun login(){repo.login("0780000001","2468")}
 fun createUnknown(){outcome="pending";mutateFailure=true;edit=null;deny=false;unsupported=false;login();runCatching{repo.allocate(payment,member,"Verified identity note")};check(repo.pending()?.state==OperationState.UNKNOWN)}
 createUnknown();val original=repo.pending()!!;val originalBytes=SecureStore.records["pending-command"]
 repo.clearOperator();bearer=tokenB;login();val before=posts
 ck("pending preserves original session digest after new sign-in",repo.pending()?.requestId==original.requestId&&repo.pending()?.sessionScope==Values.sha256(tokenA))
 ck("renewed session pending lookup stays nonterminal",repo.reconcilePending().getString("state")=="pending"&&repo.pending()?.requestId==original.requestId)
 ck("only old digest, never old bearer, accompanies new authentication",lastOrigin==Values.sha256(tokenA)&&lastBearer==tokenB&&lastOrigin!=tokenA)
 ck("origin selector stays out of URL",!lastPath.contains(Values.sha256(tokenA))&&!lastPath.contains(tokenA))
 ck("status lookup never reposts command",posts==before)
 ck("status lookup never rebinds durable journal",SecureStore.records["pending-command"]==originalBytes)
 outcome="committed";repo.reconcilePending()
 ck("verified result clears original unknown",repo.pending()==null&&posts==before)
 createUnknown();val oldId=repo.pending()!!.requestId;repo.clearOperator();bearer=tokenA;login()
 val restarted=NativeRepository(Context(),api,"group-1");restarted.restore();outcome="committed";val beforeRestart=posts
 restarted.reconcilePending();ck("restored instance resolves without POST",restarted.pending()==null&&posts==beforeRestart&&lastPath.contains(oldId))
 createUnknown();val id=repo.pending()!!.requestId;outcome="committed"
 for((label,field,value) in listOf(
  Triple("different operator","actorId","other"),Triple("different group","groupId","other"),Triple("different installation","installationId","other"),
  Triple("different request","requestId","00000000-0000-4000-8000-999999999999"),Triple("different origin","originDigest","f".repeat(64)),
  Triple("different protocol","protocol","other"),Triple("invented rejection","state","rejected"),Triple("unknown outcome","state","unknown"))){
   edit={it.put(field,value)};ck("refuse $label result",runCatching{repo.reconcilePending()}.isFailure&&repo.pending()?.requestId==id)
 }
 edit={it.put("state",true)};ck("Boolean cannot coerce into an outcome",runCatching{repo.reconcilePending()}.isFailure&&repo.pending()!=null)
 edit={it.remove("protocol")};ck("unversioned endpoint cannot clear pending",runCatching{repo.reconcilePending()}.isFailure&&repo.pending()!=null)
 edit={it.put("rawBody","sensitive")};ck("extra projection fields refused",runCatching{repo.reconcilePending()}.isFailure&&repo.pending()!=null)
 edit=null;deny=true;val beforeDeny=posts
 ck("server denial leaves original untouched",runCatching{repo.reconcilePending()}.isFailure&&repo.pending()?.requestId==id&&posts==beforeDeny)
 deny=false;unsupported=true
 ck("older backend has no unsafe fallback",runCatching{repo.reconcilePending()}.isFailure&&repo.pending()?.requestId==id&&posts==beforeDeny)
 unsupported=false
 ck("explicit retry cannot resend dispatched request",runCatching{repo.retryPending()}.isFailure&&posts==beforeDeny)
 ck("identical new submission still refused",runCatching{repo.allocate(payment,member,"Verified identity note")}.isFailure&&posts==beforeDeny)
 outcome="committed";repo.reconcilePending()
 createUnknown();outcome="committed";val raceId=repo.pending()!!.requestId
 started=CountDownLatch(1);latch=CountDownLatch(1);var failure:Throwable?=null
 val worker=thread{try{repo.reconcilePending()}catch(e:Throwable){failure=e}}
 check(started!!.await(5,TimeUnit.SECONDS));repo.clearOperator();latch!!.countDown();worker.join(6000)
 ck("late recovery cannot clear signed-out operation",failure is ContractFailure&&repo.pending()?.requestId==raceId&&repo.current()==null)
 latch=null;started=null;bearer=tokenB;login();repo.reconcilePending()
 ck("fresh explicit check can then verify original result",repo.pending()==null)
 createUnknown();val legacy=JSONObject(SecureStore.records.getValue("pending-command"));ck("legacy journal needs no guessed identity migration",legacy.has("sessionScope")&&!legacy.has("principalUserId")&&!legacy.has("recoveryToken"))
 repo.clearOperator();operatorId="different-operator";login();deny=true
 ck("different operator cannot clear a denied lookup",runCatching{repo.reconcilePending()}.isFailure&&repo.pending()!=null)
 deny=false;operatorId="operator-1";login();outcome="committed";repo.reconcilePending()
 ck("returning admitted owner can check original request",repo.pending()==null)
 mutateFailure=false;outcome="committed";val beforeSuccess=posts;val lookupsBefore=lookups
 val result=repo.allocate(payment,member,"A new explicit verified action")
 ck("new action uses one POST plus proof read",posts==beforeSuccess+1&&lookups==lookupsBefore+1&&result.getString("state")=="committed"&&repo.pending()==null)
 // Storage failures are not permission to reopen the financial mutation gate.
 createUnknown();val cacheFailureId=repo.pending()!!.requestId;val cacheFailurePosts=posts
 SecureStore.records["records"]="old cached financial state";outcome="committed";SecureStore.failClear="records"
 ck("cache removal failure keeps original operation blocked",runCatching{repo.reconcilePending()}.isFailure&&repo.pending()?.requestId==cacheFailureId&&posts==cacheFailurePosts)
 SecureStore.failClear=null;SecureStore.retainClear="records"
 ck("silent cache retention cannot close journal",runCatching{repo.reconcilePending()}.isFailure&&repo.pending()?.requestId==cacheFailureId)
 SecureStore.retainClear=null;repo.reconcilePending()
 ck("retry of cleanup is read only",repo.pending()==null&&posts==cacheFailurePosts&&"records" !in SecureStore.records)
 createUnknown();val journalFailureId=repo.pending()!!.requestId;val journalFailurePosts=posts;outcome="committed"
 SecureStore.retainClear="pending-command"
 ck("silent journal removal failure remains unresolved",runCatching{repo.reconcilePending()}.isFailure&&repo.pending()?.requestId==journalFailureId)
 ck("retained terminal journal blocks a second action",runCatching{repo.allocate(payment,member,"Another explicit action")}.isFailure&&posts==journalFailurePosts)
 SecureStore.retainClear=null;repo.reconcilePending()
 ck("journal cleanup recovery does not repeat POST",repo.pending()==null&&posts==journalFailurePosts)
 // The same invariant applies when the first POST and its outcome read succeed.
 mutateFailure=false;outcome="committed";SecureStore.records["records"]="old cached state";SecureStore.retainClear="records"
 val beforeCleanupPost=posts
 ck("POST success plus failed cleanup retains committed proof and gate",runCatching{repo.allocate(payment,member,"Confirmed command cleanup test")}.isFailure&&repo.pending()?.state==OperationState.COMMITTED&&posts==beforeCleanupPost+1)
 SecureStore.retainClear=null;repo.reconcilePending()
 ck("cleanup after POST success needs only result read",repo.pending()==null&&posts==beforeCleanupPost+1)
 println("RESULT: $checks owner-bound recovery checks passed; actual repository/DTO/journal with synthetic transport/storage, not Android or PostgreSQL.")
}

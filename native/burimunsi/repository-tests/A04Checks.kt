package rw.ikanisa.burimunsi.a04tests
import android.content.Context
import org.json.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.burimunsi.storage.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/** Cross-stream merge regressions. Real repository/journal/DTO, synthetic transport/storage. */
private class Scenario {
 val api=ApiClient("phone-1")
 var owner="operator-1";var bearer="a".repeat(64)
 var proofState="committed";var statusState="committed";var effect="posted";var operation="burimunsi.allocate"
 var enrollmentAckGroup="group-1";var enrollmentAckId="member-1"
 var postFailure=true;var proofFailure:ApiFailure?=null;var statusFailure:ApiFailure?=null
 var editProof:((JSONObject)->Unit)?=null;var editStatus:((JSONObject)->Unit)?=null
 var statusEntered:CountDownLatch?=null;var releaseStatus:CountDownLatch?=null
 val repo:NativeRepository
 val payment=Payment("payment-1","Payer","+250780000816",10000,"at","ft-1","unallocated",1)
 val member=Member("member-1","Member","+250780000816",10000,true,1)
 init{
  SecureStore.reset()
  api.handler={r->when{
   r.path.endsWith("/session/login")||r.path.endsWith("/session")->JSONObject().put("token",bearer).put("expiresAt",System.currentTimeMillis()+3600000)
    .put("profile",JSONObject().put("id",owner).put("name","Example Operator").put("phone","+250780000001").put("role","admin")
      .put("capabilities",JSONArray().put("records.read").put("payments.allocate").put("members.enroll").put("staff.manage"))).toString()
   r.method!="GET"->{if(postFailure)throw ApiFailure("connection_unavailable",0,true);if(operation=="burimunsi.enroll")JSONObject().put("id",enrollmentAckId).put("groupId",enrollmentAckGroup).toString()else "{}"}
   r.path.endsWith("/recovery")->{proofFailure?.let{throw it};val j=JSONObject().put("protocol","burimunsi.operation-recovery.v1")
    .put("requestId",r.path.substringBeforeLast('/').substringAfterLast('/')).put("state",proofState)
    .put("originDigest",r.recoveryOrigin).put("groupId","group-1").put("actorId",owner).put("installationId","phone-1")
    editProof?.invoke(j);j.toString()}
   r.path.contains("/operations/")->{statusEntered?.countDown();check(releaseStatus?.await(5,TimeUnit.SECONDS)!=false)
    statusFailure?.let{throw it};val j=JSONObject().put("contractVersion",2).put("requestId",r.path.substringAfterLast('/'))
    .put("groupId","group-1").put("actorId",owner).put("state",statusState).put("operation",operation).put("financialState",effect)
    editStatus?.invoke(j);j.toString()}
   else->error("Unexpected fixture endpoint ${r.path}")
  }}
  repo=NativeRepository(Context(),api,"group-1");login()
 }
 fun login(){if(repo.current()!=null)repo.clearOperator();repo.login("0780000001","2468")}
 fun submit()=repo.allocate(payment,member,"Explicit verified identity note")
 fun unknown(){postFailure=true;runCatching{submit()};check(repo.pending()?.state==OperationState.UNKNOWN)}
 fun posts()=api.calls.count{it.method!="GET"&&!it.path.endsWith("/session/login")}
 fun statusReads()=api.calls.count{it.path.contains("/operations/")&&!it.path.endsWith("/recovery")}
 fun stored()=SecureStore.records["pending-command"]
}
fun main(){
 var checks=0
 fun ck(label:String,ok:Boolean){check(ok){label};checks++;println("PASS A04 $label")}
 run{
  val s=Scenario();s.unknown();val original=s.repo.pending()!!;val bytes=s.stored()
  ck("new journal persists immutable owner and group",original.ownerAccountId=="operator-1"&&original.groupId=="group-1")
  s.repo.clearOperator();s.bearer="b".repeat(64);s.login();s.proofState="pending"
  ck("pending proof is nonterminal without economic read",s.repo.reconcilePending().getString("state")=="pending"&&s.statusReads()==0&&s.stored()==bytes)
  ck("rotated token never rebinds or redispatches",runCatching{s.repo.retryPending()}.isFailure&&s.posts()==1&&s.repo.pending()==original)
  s.proofState="committed";s.repo.reconcilePending()
  val reads=s.api.calls.filter{it.path.contains("/operations/")}
  ck("v1 precedes v2 under same new bearer",reads.takeLast(2).map{it.path.endsWith("/recovery")}==listOf(true,false)&&reads.takeLast(2).all{it.token==s.bearer})
  ck("original digest remains hash-only selector",reads.takeLast(2)[0].recoveryOrigin==original.sessionScope&&reads.last().recoveryOrigin==null)
  ck("verified dual-read closes original without POST",s.repo.pending()==null&&s.posts()==1)
 }
 for((label,mutation) in listOf<Pair<String,(JSONObject)->Unit>>(
  "foreign proof owner" to {it.put("actorId","other")},"unknown proof protocol" to {it.put("protocol","unsupported")},
  "unversioned proof" to {it.remove("protocol")},"invented proof rejection" to {it.put("state","rejected")}
 )){val s=Scenario();s.unknown();val bytes=s.stored();s.editProof=mutation
  ck("$label cannot fall back to v2",runCatching{s.repo.reconcilePending()}.isFailure&&s.statusReads()==0&&s.stored()==bytes&&s.posts()==1)}
 val fields=listOf("contractVersion","requestId","groupId","actorId","state","operation","financialState")
 for(field in fields){val s=Scenario();s.unknown();val bytes=s.stored();s.editStatus={it.remove(field)}
  ck("missing v2 $field retains exact journal",runCatching{s.repo.reconcilePending()}.isFailure&&s.stored()==bytes&&s.posts()==1)}
 for((field,value) in listOf<Pair<String,Any>>(
  "contractVersion" to "2","contractVersion" to 2.5,"contractVersion" to true,"contractVersion" to 1,"contractVersion" to 3,
  "requestId" to "00000000-0000-4000-8000-000000000099","actorId" to "other","groupId" to "other",
  "state" to "pending","state" to "rejected","state" to true,"operation" to "burimunsi.enroll",
  "financialState" to "not_applicable","financialState" to "unresolved","financialState" to false,
  "rawBody" to "unexpected projection"
 )){val s=Scenario();s.unknown();val bytes=s.stored();s.editStatus={it.put(field,value)}
  ck("invalid v2 $field=$value preserves original",runCatching{s.repo.reconcilePending()}.isFailure&&s.stored()==bytes&&s.posts()==1)}
 for(status in listOf(0,401,403,404,503)){val s=Scenario();s.postFailure=false;s.statusFailure=ApiFailure("fixture_status_failure",status,status==0)
  ck("POST acknowledgement plus v2 HTTP $status remains UNKNOWN",runCatching{s.submit()}.isFailure&&s.repo.pending()?.state==OperationState.UNKNOWN&&s.posts()==1)
  s.statusFailure=null;s.login();s.repo.reconcilePending();ck("v2 HTTP $status recovery never repeats POST",s.repo.pending()==null&&s.posts()==1)}
 run{val s=Scenario();s.unknown();val bytes=s.stored();s.repo.clearOperator();s.owner="different-owner";s.bearer="b".repeat(64);s.login();val count=s.api.calls.size
  ck("different owner denied locally before either read",runCatching{s.repo.reconcilePending()}.isFailure&&s.api.calls.size==count&&s.stored()==bytes)}
 run{val s=Scenario();s.unknown();val j=JSONObject(s.stored()!!);j.remove("ownerAccountId");j.remove("groupId");SecureStore.records["pending-command"]=j.toString()
  val bytes=s.stored();s.repo.clearOperator();s.bearer="b".repeat(64);s.login();s.proofFailure=ApiFailure("operation_recovery_denied",403)
  ck("legacy journal cannot use financial status instead of owner proof",runCatching{s.repo.reconcilePending()}.isFailure&&s.statusReads()==0&&s.stored()==bytes)
  s.proofFailure=null;s.statusFailure=ApiFailure("not_found",404)
  ck("legacy journal also requires v2 financial readback",runCatching{s.repo.reconcilePending()}.isFailure&&s.stored()==bytes)
  s.statusFailure=null;s.repo.reconcilePending();ck("legacy original resolves only through both proofs",s.repo.pending()==null&&s.posts()==1)
  ck("legacy allocation retains the receipt floor under the verified actor and group",runCatching{s.submit()}.exceptionOrNull() is ApiFailure&&s.repo.pending()==null&&s.posts()==1)}
 for(effect in listOf("posted","reversed","corrected")){val s=Scenario();s.unknown();s.effect=effect;SecureStore.records["records"]="old financial view"
  val out=s.repo.reconcilePending();ck("read-only $effect recovery closes history and clears cache",out.getString("financialState")==effect&&s.repo.pending()==null&&"records" !in SecureStore.records&&s.posts()==1)}
 for(effect in listOf("reversed","corrected")){val s=Scenario();s.postFailure=false;s.effect=effect
  val e=runCatching{s.submit()}.exceptionOrNull();ck("$effect after POST never reports fresh credit",e is ApiFailure&&e.code=="operation_financially_changed"&&s.repo.pending()==null&&s.posts()==1)}
 for(key in listOf("records","pending-command")){val s=Scenario();s.unknown();s.effect="reversed";val id=s.repo.pending()!!.requestId;SecureStore.records["records"]="old view";SecureStore.retainClear=key
  ck("reversed effect with retained $key blocks next mutation",runCatching{s.repo.reconcilePending()}.isFailure&&s.repo.pending()?.requestId==id&&runCatching{s.submit()}.isFailure&&s.posts()==1)
  SecureStore.retainClear=null;s.repo.reconcilePending();ck("cleanup $key retry is read-only",s.repo.pending()==null&&s.posts()==1)}
 run{val s=Scenario();s.unknown();val bytes=s.stored();s.statusEntered=CountDownLatch(1);s.releaseStatus=CountDownLatch(1);var fail:Throwable?=null
  val t=thread{try{s.repo.reconcilePending()}catch(e:Throwable){fail=e}}
  check(s.statusEntered!!.await(5,TimeUnit.SECONDS));s.repo.clearOperator();s.releaseStatus!!.countDown();t.join(6000)
  ck("sign-out between v1 and v2 cannot close original",!t.isAlive&&fail!=null&&s.stored()==bytes&&s.repo.current()==null&&s.posts()==1)}
 for(op in listOf("burimunsi.enroll","burimunsi.membership","burimunsi.staff.create","burimunsi.staff.disable")){
  val s=Scenario();s.postFailure=false;s.operation=op;s.effect="not_applicable"
  val out=when(op){"burimunsi.enroll"->s.repo.enroll("Example Member","0780000816");"burimunsi.membership"->s.repo.setMemberActive(s.member,false);else->s.repo.staffAction(JSONObject().put("action",op.substringAfterLast('.')))}
  ck("$op keeps exact nonfinancial status contract",out.getString("operation")==op&&out.getString("financialState")=="not_applicable"&&s.repo.pending()==null&&s.posts()==1)
  if(op=="burimunsi.enroll")ck("enrollment exposes same-scope acknowledged ID only after outcome readback",out.getString("createdMemberId")=="member-1"&&s.statusReads()==1)
 }
 run{val s=Scenario();s.postFailure=false;s.operation="burimunsi.enroll";s.effect="not_applicable";s.enrollmentAckGroup="other-group"
  val out=s.repo.enroll("Example Member","0780000816")
  ck("foreign-scope enrollment ACK cannot supply a member ID after verified commit",out.getString("createdMemberId")==""&&out.getString("operation")=="burimunsi.enroll"&&s.repo.pending()==null&&s.posts()==1)}
 run{val s=Scenario();s.postFailure=false;s.operation="burimunsi.enroll";s.effect="not_applicable";s.statusFailure=ApiFailure("fixture_status_failure",503)
  ck("enrollment ACK cannot escape before authoritative confirmation",runCatching{s.repo.enroll("Example Member","0780000816")}.isFailure&&s.repo.pending()!=null&&s.posts()==1)}
 println("RESULT: $checks A04 cross-workstream repository checks passed; not Android/Keystore/PostgreSQL acceptance.")
}

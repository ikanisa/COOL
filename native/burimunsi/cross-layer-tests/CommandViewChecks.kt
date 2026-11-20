package rw.ikanisa.burimunsi.crosslayertests
import android.app.Application
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import org.json.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.burimunsi.storage.SecureStore
import rw.ikanisa.burimunsi.ui.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Host integration only. No Android storage/JSON/lifecycle, TLS or server/database execution. */
private class Scenario {
 var postMode="ok";var effect="posted";var proofState="committed";var statusState="committed"
 var owner="operator-1";var token="a".repeat(64);var operation="burimunsi.allocate"
 var recordFailure=false;var failureAfterPost=false;var deniedProof=false;var badStatus=false
 var recordReads=0;var committed=false;var uiClockOffset=0L
 var memberListed=true;var memberActive=true;var memberVersion=1
 var postReadPaymentId="payment-1"
 var statusEntered:CountDownLatch?=null;var releaseStatus:CountDownLatch?=null
 lateinit var model:BuriViewModel
 private fun page(vararg values:JSONObject)=JSONObject().put("items",JSONArray().also{a->values.forEach{a.put(it)}})
  .put("totalCount",values.size).put("revision","fixture-v1").put("asOf","2026-11-09T10:00:00Z").put("nextCursor",JSONObject.NULL).toString()
 private fun member()=JSONObject().put("id","member-1").put("groupId","synthetic-group").put("name","Synthetic Member").put("phone","+250780000816")
  .put("balanceRwf",10000).put("active",memberActive).put("version",memberVersion)
 private fun payment()=JSONObject().put("id",if(committed)postReadPaymentId else "payment-1").put("groupId","synthetic-group")
  .put("memberId",JSONObject.NULL).put("memberPhone",JSONObject.NULL).put("sourceId",JSONObject.NULL)
  .put("payerNameRaw","Synthetic Payer").put("payerPhoneRaw","+250780000816")
  .put("amountRwf",10000).put("atRaw","2026-11-09 10:00:00").put("ftId","ft-1")
  .put("state",if(committed)"posted" else "unallocated").put("version",if(committed)2 else 1)
 private fun staff()=JSONObject().put("id","staff-1").put("groupId","synthetic-group").put("name","Synthetic Staff").put("phone","+250780000002")
  .put("active",true).put("version",1).put("capabilities",JSONArray().put("records.read"))
 init {
  SecureStore.reset();Transport.calls.clear()
  Transport.handler={r->when {
   r.path.endsWith("/session/login")||r.path.endsWith("/session")->JSONObject().put("token",token).put("groupId","synthetic-group").put("expiresAt",System.currentTimeMillis()+3600000)
    .put("profile",JSONObject().put("id",owner).put("name","Synthetic Operator").put("phone","+250780000001").put("role","admin")
     .put("capabilities",JSONArray().also{a->Capability.entries.forEach{a.put(it.key)}})).toString()
   r.path.endsWith("/session/logout")->"{}"
   r.method!="GET"->{
    operation=when {r.path.endsWith("/allocate")->"burimunsi.allocate";r.path.endsWith("/members")->"burimunsi.enroll";r.path.contains("/members/")->"burimunsi.membership";else->"burimunsi.staff."+r.body!!.getString("action")}
    if(operation!="burimunsi.allocate")effect="not_applicable"
    if(postMode=="reject")throw ApiFailure("access_denied",403,false)
    committed=true;if(failureAfterPost)recordFailure=true
    if(postMode=="lost")throw ApiFailure("connection_unavailable",0,true)
    "{}"
   }
   r.path.endsWith("/recovery")->{
    if(deniedProof)throw ApiFailure("operation_recovery_denied",403)
    JSONObject().put("protocol","burimunsi.operation-recovery.v1").put("requestId",r.path.substringBeforeLast('/').substringAfterLast('/'))
     .put("state",proofState).put("originDigest",r.recoveryOrigin).put("groupId","synthetic-group").put("actorId",owner)
     .put("installationId","fixture-device").toString()
   }
   r.path.contains("/operations/")->{
    statusEntered?.countDown();check(releaseStatus?.await(10,TimeUnit.SECONDS)!=false)
    JSONObject().put("contractVersion",if(badStatus)3 else 2).put("requestId",r.path.substringAfterLast('/')).put("groupId","synthetic-group")
     .put("actorId",owner).put("state",statusState).put("operation",operation).put("financialState",effect).toString()
   }
   else->{recordReads++;if(recordFailure)throw ApiFailure("connection_unavailable",0)
    when {
     r.path.endsWith("/home")->JSONObject().put("groupBalanceRwf",10000).put("todayRwf",10000).put("memberCount",1).put("unallocatedCount",1)
      .put("recentPayments",JSONArray().put(payment())).put("asOf","2026-11-09T10:00:00Z").toString()
     r.path.contains("/payments/payment-1")->payment().toString()
     r.path.contains("/members/member-1")->member().toString()
     r.path.contains("/members?")->if(memberListed)page(member())else page()
     // The synthetic payment is unallocated, so it cannot appear in a
     // member-scoped payment listing.
     r.path.contains("/payments?")&&r.path.contains("memberId=")->page()
     r.path.contains("/payments?")->page(payment())
     r.path.contains("/ledger?")->page(JSONObject().put("id","ledger-1").put("groupId","synthetic-group").put("memberPhone","+250780000816").put("transactionId","payment-1").put("amountRwf",10000).put("atRaw","2026-11-09").put("ftId","ft-1").put("payerNameRaw","Synthetic Payer"))
     r.path.contains("/staff?")->page(staff())
     else->error("Unexpected fixture endpoint ${r.path}")
    }
   }
  }}
 }
 suspend fun idle(){withTimeout(15000){while(model.state.busy)delay(2)};delay(10)}
 suspend fun start(){model=BuriViewModel(Application()){System.currentTimeMillis()+uiClockOffset};idle();model.login("0780000001","2468");idle();check(model.state.operator!=null)}
 suspend fun allocation(){model.navigate(Route.PAYMENT,"payment-1");idle();model.openSheet(Sheet.ALLOCATE);idle();model.selectMember(model.state.members!!.items.single());model.editDraft("note","Verified original identity")}
 suspend fun submit(){model.allocate("Verified original identity");idle()}
 suspend fun close(){releaseStatus?.countDown();model.viewModelScope.coroutineContext[Job]!!.cancelAndJoin()}
 fun posts()=Transport.calls.count{it.method!="GET"&&!it.path.contains("/session/")}
 fun journal()=SecureStore.records["pending-command"]
}
fun main()=runBlocking {
 var checks=0;val failures=mutableListOf<String>()
 fun ck(label:String,ok:Boolean){checks++;println((if(ok)"PASS " else "FAIL ")+label);if(!ok)failures.add(label)}
 suspend fun scenario(block:suspend (Scenario)->Unit){val s=Scenario();try{s.start();block(s)}finally{s.close()}}
 scenario{s->
  s.allocation();s.postReadPaymentId="other-payment";s.submit()
  ck("a different detail cannot replace the acknowledged payment",s.model.state.payment==null&&s.model.state.commandNotice?.startsWith("The original action committed.")==true&&s.posts()==1&&s.journal()==null)
  s.postReadPaymentId="payment-1";s.model.refresh();s.idle()
  ck("the original payment detail recovers without a second post",s.model.state.payment?.id=="payment-1"&&s.model.state.payment?.version==2L&&s.posts()==1)
 }
 for(reason in listOf("search no longer includes member","inactive member","new member version"))scenario{s->
  s.allocation()
  val original=s.model.state.selectedMember!!
  when(reason){"inactive member"->s.memberActive=false;"new member version"->s.memberVersion++;else->s.memberListed=false}
  s.model.allocationSearch("refreshed results");s.idle()
  ck("$reason removes the old allocation selection and retains the note",s.model.state.selectedMember==null&&s.model.state.draft["note"]=="Verified original identity")
  s.model.selectMember(original)
  ck("$reason ignores a delayed click from the previous member list",s.model.state.selectedMember==null)
  s.submit()
  ck("$reason cannot create a journal or dispatch a payment",s.posts()==0&&s.journal()==null)
  s.memberListed=true;s.memberActive=true;s.model.allocationSearch("fresh result");s.idle()
  s.model.selectMember(s.model.state.members!!.items.single());s.submit()
  val requests=Transport.calls.filter{it.method=="POST"&&it.path.endsWith("/allocate")}
  ck("$reason recovers after an explicit new selection with one original post",requests.size==1&&requests.single().body?.getString("memberId")=="member-1"&&requests.single().body?.getInt("expectedVersion")==1&&s.journal()==null)
 }
 scenario{s->s.allocation();s.failureAfterPost=true;s.submit()
  ck("committed command clears durable journal",s.journal()==null&&!s.model.state.pending)
  ck("failed post-commit refresh cannot display old payment",s.model.state.payment==null&&s.model.state.savedAt==null)
  ck("failed post-commit refresh closes consumed form and beneficiary",s.model.state.sheet==null&&s.model.state.selectedMember==null&&s.model.state.draft.isEmpty())
  s.submit();ck("cleared form cannot submit another financial operation",s.posts()==1)
 }
 scenario{s->s.allocation();s.postMode="lost";s.submit();val original=s.journal()
  ck("lost acknowledgement retains original operation",original!=null&&s.model.state.pending)
  ck("uncertain command removes actionable financial snapshot",s.model.state.payment==null&&s.model.state.selectedMember==null)
  s.model.retry();s.idle()
  ck("recovery is read-only and consumes original",s.posts()==1&&s.journal()==null&&!s.model.state.pending)
  ck("recovered command closes original draft",s.model.state.sheet==null&&s.model.state.draft.isEmpty()&&s.model.state.selectedMember==null)
 }
 scenario{s->s.allocation();s.effect="reversed";s.submit()
  ck("direct reversed commit clears journal without fresh-credit success",s.journal()==null&&s.model.state.error?.contains("financial effect changed")==true)
  ck("direct reversed commit clears stale record and selection",s.model.state.payment==null&&s.model.state.selectedMember==null&&s.model.state.sheet==null)
  s.submit();ck("reversed result never replays old selection",s.posts()==1)
 }
 scenario{s->s.allocation();s.postMode="lost";s.submit();val original=s.journal();s.proofState="pending";val reads=s.recordReads
  s.model.retry();s.idle()
  ck("pending proof retains exact journal and makes no record read",s.journal()==original&&s.recordReads==reads&&s.posts()==1)
 }
 scenario{s->s.allocation();s.postMode="lost";s.submit();val original=s.journal();s.badStatus=true;s.model.retry();s.idle()
  ck("unsupported economic proof preserves original command",s.journal()==original&&s.model.state.pending&&s.posts()==1)
 }
 scenario{s->s.allocation();s.postMode="reject";s.submit()
  ck("first transport rejection retains uncertainty without claiming commitment",s.journal()!=null&&s.model.state.pending&&s.model.state.commandNotice==null&&s.model.state.error=="Access unavailable."&&s.posts()==1)
 }
 for(effect in listOf("reversed","corrected"))scenario{s->
  s.allocation();s.postMode="lost";s.submit();s.effect=effect;s.recordFailure=true
  s.model.retry();s.idle()
  ck("$effect recovery consumes journal before a failed record refresh",s.journal()==null&&!s.model.state.pending&&s.posts()==1)
  ck("$effect notice survives record read failure",s.model.state.commandNotice?.contains("reversed or corrected")==true&&s.model.state.error=="Offline. Reconnect and refresh.")
  ck("$effect recovery leaves no pre-command records or draft",s.model.state.payment==null&&s.model.state.sheet==null&&s.model.state.selectedMember==null&&s.model.state.draft.isEmpty())
  s.model.refresh();s.idle();ck("$effect notice survives repeated failed refresh",s.model.state.commandNotice?.contains("do not repeat")==true&&s.posts()==1)
  s.recordFailure=false;s.model.refresh();s.idle();ck("$effect refresh reads authoritative record without mutation",s.model.state.payment?.version==2L&&s.posts()==1)
 }
 scenario{s->s.allocation();s.failureAfterPost=true;s.submit()
  ck("posted outcome remains distinguishable from failed refresh",s.model.state.commandNotice?.startsWith("The original action committed.")==true&&s.model.state.error!=null)
  s.recordFailure=false;s.model.refresh();s.idle();ck("readback preserves completed notice and never dispatches",s.model.state.commandNotice!=null&&s.model.state.payment?.version==2L&&s.posts()==1)
  s.model.logout();s.idle();ck("signout does not expose previous operator notice",s.model.state.operator==null&&s.model.state.commandNotice==null)
 }
 for(key in listOf("records","pending-command"))scenario{s->
  s.allocation();SecureStore.records["sms-queue"]="unaltered synthetic receipt evidence";SecureStore.retainClear=key;s.submit();val original=JSONObject(s.journal()!!)
  ck("retained $key cleanup keeps original pending gate",s.model.state.pending&&s.posts()==1&&original.getInt("attemptCount")==1)
  ck("retained $key cleanup invalidates form without commitment claim",s.model.state.payment==null&&s.model.state.sheet==null&&s.model.state.commandNotice==null)
  s.submit();ck("retained $key cleanup prevents another command",s.posts()==1&&JSONObject(s.journal()!!).getString("requestId")==original.getString("requestId"))
  SecureStore.retainClear=null;s.model.retry();s.idle()
  ck("$key cleanup resumes only via read-only proofs",s.journal()==null&&!s.model.state.pending&&s.posts()==1)
  ck("$key cleanup never edits receiving evidence",SecureStore.records["sms-queue"]=="unaltered synthetic receipt evidence")
 }
 for(mode in listOf("denied","conflicting","unsupported"))scenario{s->
  s.allocation();s.postMode="lost";s.submit();val original=s.journal()
  when(mode){"denied"->s.deniedProof=true;"conflicting"->s.statusState="pending";else->s.badStatus=true}
  s.model.retry();s.idle()
  ck("$mode proof retains byte-identical original journal",s.journal()==original&&s.model.state.pending&&s.model.state.commandNotice==null)
  s.submit();ck("$mode proof cannot authorize another operation",s.posts()==1)
 }
 scenario{s->s.allocation();s.postMode="lost";s.submit();val original=JSONObject(s.journal()!!)
  s.model.logout();s.idle();s.token="b".repeat(64);s.model.login("0780000001","2468");s.idle()
  ck("same-owner login retains original unresolved command",s.model.state.pending&&JSONObject(s.journal()!!).getString("requestId")==original.getString("requestId"))
  s.model.retry();s.idle();val reads=Transport.calls.filter{it.path.contains("/operations/")}.takeLast(2)
  ck("same-owner recovery uses new bearer and immutable original digest",reads.size==2&&reads.all{it.token==s.token}&&reads[0].recoveryOrigin==original.getString("sessionScope"))
  ck("same-owner recovery completes without another POST",s.posts()==1&&s.journal()==null&&!s.model.state.pending)
 }
 scenario{s->s.allocation();s.postMode="lost";s.submit();val original=s.journal()
  s.model.logout();s.idle();s.owner="other-operator";s.token="b".repeat(64);s.model.login("0780000001","2468");s.idle()
  val before=Transport.calls.size;s.model.retry();s.idle()
  ck("changed operator denied before status calls",Transport.calls.size==before&&s.journal()==original&&s.model.state.pending)
  ck("changed operator never sees old command confirmation",s.model.state.commandNotice==null&&s.posts()==1)
 }
 for(kind in listOf("enroll","staff.create","staff.disable","membership"))scenario{s->
  when(kind){
   "enroll"->{s.model.openSheet(Sheet.ENROLL);s.idle();s.model.editDraft("name","Synthetic New Member")}
   "staff.create"->{s.model.openSheet(Sheet.STAFF);s.idle();s.model.openSheet(Sheet.STAFF_EDIT);s.idle();s.model.editDraft("name","Synthetic New Staff")}
   "staff.disable"->{s.model.openSheet(Sheet.STAFF);s.idle();s.model.openSheet(Sheet.STAFF_EDIT,"staff-1");s.idle()}
   else->{s.model.navigate(Route.MEMBER,"member-1");s.idle();check(s.model.state.member?.id=="member-1")}
  }
  s.failureAfterPost=true
  when(kind){"enroll"->s.model.enroll("Synthetic New Member","0780000816");"staff.create"->s.model.saveStaff("Synthetic New Staff","0780000002","2468",true,true);"staff.disable"->s.model.staffAction("disable");else->s.model.setMemberActive(false)}
  s.idle()
  ck("$kind uses strict nonfinancial outcome and consumes original",s.journal()==null&&!s.model.state.pending&&s.posts()==1&&s.effect=="not_applicable")
  ck("$kind clears consumed drafts before failed record read",s.model.state.sheet==null&&s.model.state.draft.isEmpty()&&s.model.state.selectedStaff==null&&s.model.state.member==null&&s.model.state.home==null)
  ck("$kind retains confirmation independently of failed readback",s.model.state.commandNotice?.startsWith("The original action committed.")==true&&s.model.state.error!=null)
 }
 scenario{s->s.allocation();s.postMode="reject";s.submit()
  ck("transport rejection retains original command without a commit claim",s.journal()!=null&&s.model.state.pending&&s.model.state.commandNotice==null)
  ck("transport rejection cannot revive actionable selection",s.model.state.sheet==null&&s.model.state.selectedMember==null&&s.posts()==1)
 }
 scenario{s->s.allocation();s.statusState="pending";s.statusEntered=CountDownLatch(1);s.releaseStatus=CountDownLatch(1)
  s.model.allocate("Verified original identity");check(withContext(Dispatchers.IO){s.statusEntered!!.await(10,TimeUnit.SECONDS)})
  val original=JSONObject(s.journal()!!);s.uiClockOffset=7200000;s.model.onForeground()
  withTimeout(10000){while(s.model.screenGate==ScreenGate.OPEN)delay(20)}
  s.releaseStatus!!.countDown();s.idle();delay(50)
  ck("expired session cannot expose command views while revalidation is pending",!s.model.presentation.showRecords&&s.model.state.commandNotice==null)
  ck("expiry during financial read retains original identity",JSONObject(s.journal()!!).getString("requestId")==original.getString("requestId")&&s.posts()==1)
 }
 println("RESULT: $checks cross-layer controller/repository checks; ${failures.size} failed. Synthetic platform/transport/storage; not Android or PostgreSQL acceptance.")
 check(failures.isEmpty()){failures.joinToString("; ")}
}

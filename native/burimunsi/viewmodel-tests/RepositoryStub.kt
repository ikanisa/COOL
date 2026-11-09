package rw.ikanisa.burimunsi.data
import android.app.Application
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.*
class ApiFailure(val code:String,val status:Int=400,val uncertain:Boolean=false):RuntimeException(code)
fun interface ManagedSessionTokenProvider { fun currentAccessToken():String? }
interface ManagedSessionHost { val managedSessionTokenProvider:ManagedSessionTokenProvider;fun signOutManagedSession(){} }
class ApiClient(origin:String,id:String,token:()->String?){
 constructor(origin:String,id:String,provider:ManagedSessionTokenProvider,token:()->String?):this(origin,id,token)
 constructor(origin:String,id:String,prefix:String,token:()->String?):this(origin,id,token)
 constructor(origin:String,id:String,provider:ManagedSessionTokenProvider,prefix:String,token:()->String?):this(origin,id,provider,token)
}
object Fixture{
 var financialState="posted"
 @Volatile var currentOwnerOverride:String?=null
 @Volatile var paged:((String,String?,String,String)->Page<String>)?=null
 @Volatile var journalFailure=false
 @Volatile var restoreSignedOut=false
 @Volatile var ownerId="operator"
 @Volatile var readFailure:ApiFailure?=null
 @Volatile var paymentsBarrier:java.util.concurrent.CountDownLatch?=null
 @Volatile var paymentsEntered:java.util.concurrent.CountDownLatch?=null
 @Volatile var missingReadTimestamp=false
 @Volatile var readEmpty=false
 @Volatile var pinUncertain=false
 @Volatile var recoveryFailure:ApiFailure?=null
 @Volatile var resolveOnCheck=false
 var pendingFlag=false;var outcomeState="committed";var exportReads=0;var lastExportMember="";var sessionReads=0;var sessionFailure:ApiFailure?=null
 var homeBarrier:java.util.concurrent.CountDownLatch?=null
 var allocateBarrier:java.util.concurrent.CountDownLatch?=null
 var enrollMutations=0;var staffMutations=0;var reconciles=0
 var historySavedAt:Long?=null

 var paymentFailure=false;var recordSavedAt:Long?=null;var refreshedRole:Role?=null;var refreshedCaps:Set<String>?=null;var paymentReads=0;
 var historyFailure=false;var historyReads=0;var historyRevision="history-v1";var historyLoop=false;var historyOverlap=false;var lastHistoryId="";var historyDelay=0L;
 var rawFailure=false;var rawReads=0;var mutations=0;var role=Role.ADMIN;var cached=false;var memberCached=false;var lifecycleCalls=0;var homeReads=0
 var lastFilter="";val saved=1794063600000L
 fun operator()=Operator(ownerId, "Example Operator", "+250780000001",role,Capability.entries.map{it.key}.toSet(),System.currentTimeMillis()+3600000)
 val member=Member("member-1","Example Member","+250780000816",10000,true,1)
 fun payment(id:String="tx-1")=Payment(id,"Example Payer","+250780000816",10000,"2026-11-07 12:00:00","90001","unallocated",1)
 fun <T> page(items:List<T>,next:String?=null)=Page(items,next,2,"v1","2026-11-07T12:00:00Z")
}
class NativeRepository(app:Application,api:ApiClient,group:String){
 var lastReadFromCache=false;var lastReadSavedAt:Long?=null;private var operator:Operator?=if(Fixture.restoreSignedOut)null else Fixture.operator()
 private fun provenance(cached:Boolean=Fixture.cached){lastReadFromCache=cached;lastReadSavedAt=if(Fixture.missingReadTimestamp)null else if(cached)Fixture.saved else Fixture.recordSavedAt?:System.currentTimeMillis()}
 fun restore()=operator
 fun current()=operator?.let{it.copy(id=Fixture.currentOwnerOverride?:it.id)}
 fun login(phone:String,pin:String):Operator{operator=Fixture.operator();return operator!!}
 fun logout(){operator=null};fun clearOperator(){operator=null};fun refreshSession():Operator{Fixture.sessionReads++;Fixture.sessionFailure?.let{if(it.status==401)operator=null;throw it};operator=operator!!.copy(role=Fixture.refreshedRole?:operator!!.role,capabilities=Fixture.refreshedCaps?:operator!!.capabilities);return operator!!}
 fun pending():Any?{if(Fixture.journalFailure)throw ContractFailure("operation_store_unavailable");return if(Fixture.pendingFlag)"original-operation" else null}
 fun reconcilePending():JSONObject{Fixture.reconciles++;Fixture.recoveryFailure?.let{throw it};if(Fixture.resolveOnCheck&&Fixture.outcomeState=="committed")Fixture.pendingFlag=false;return JSONObject().put("state",Fixture.outcomeState).put("financialState",Fixture.financialState)}
 fun home():Home{Fixture.readFailure?.let{throw it};provenance();Fixture.homeReads++;check(Fixture.homeBarrier?.await(5,java.util.concurrent.TimeUnit.SECONDS)!=false);return Home(10000,10000,1,1,listOf(Fixture.payment()),"now")}
 fun payments(q:String="",filter:String="all",cursor:String?=null):Page<Payment>{Fixture.paymentsEntered?.countDown();check(Fixture.paymentsBarrier?.await(5,java.util.concurrent.TimeUnit.SECONDS)!=false);Fixture.readFailure?.let{throw it};provenance();Fixture.lastFilter=filter;Fixture.paged?.let{handler->val p=handler("PAYMENTS",cursor,q,filter);provenance();return Page(p.items.map{Fixture.payment(it)},p.nextCursor,p.totalCount,p.revision,p.asOf)};if(Fixture.readEmpty)return Page(emptyList(),null,0,"empty","2026-11-09T00:00:00Z");return Fixture.page(listOf(Fixture.payment(if(cursor==null)"tx-1" else "tx-2")),if(cursor==null)"more" else null)}
 fun members(q:String="",cursor:String?=null):Page<Member>{provenance();Fixture.paged?.let{handler->val p=handler("MEMBERS",cursor,q,"all");provenance();return Page(p.items.map{Fixture.member.copy(id=it)},p.nextCursor,p.totalCount,p.revision,p.asOf)};return Fixture.page(listOf(Fixture.member.copy(id=if(cursor==null)"member-1" else "member-2")),if(cursor==null)"more" else null)}
 fun payment(id:String):Payment{Fixture.paymentReads++;if(Fixture.paymentFailure)throw ApiFailure("connection_unavailable",0);provenance();return Fixture.payment(id)}
 fun member(id:String):Member{provenance(Fixture.memberCached||Fixture.cached);return Fixture.member.copy(id=id)}
 fun ledger(id:String,cursor:String?=null):Page<LedgerRow>{provenance();Fixture.paged?.let{handler->val p=handler("MEMBER",cursor,id,"all");provenance();return Page(p.items.map{LedgerRow(it,"tx-1",10000,"at","90001","Payer")},p.nextCursor,p.totalCount,p.revision,p.asOf)};return Fixture.page(listOf(LedgerRow("l-1","tx-1",10000,"at","90001","Payer")))}
 fun sms(q:String="",cursor:String?=null,filter:String="all"):Page<SmsRow>{Fixture.lastFilter=filter;Fixture.paged?.let{handler->val p=handler("SMS",cursor,q,filter);return Page(p.items.map{SmsRow(it,"M-Money","at","synthetic",filter,null)},p.nextCursor,p.totalCount,p.revision,p.asOf)};return Fixture.page(listOf(SmsRow("s-1","M-Money","at","synthetic",filter,null)))}
 fun staff(cursor:String?=null):Page<StaffAccount> =Fixture.page(listOf(StaffAccount(if(cursor==null)"staff-1" else "staff-2","Staff","+250780000002",true,1,emptySet())),if(cursor==null)"more" else null)
 fun audit(cursor:String?=null):Page<AuditRow> =Fixture.page(listOf(AuditRow(if(cursor==null)"audit-1" else "audit-2","Action","at")),if(cursor==null)"more" else null)
 fun raw(id:String):RawSms{Fixture.rawReads++;if(Fixture.rawFailure)throw ApiFailure("connection_unavailable",0);return RawSms(id,"M-Money","at","unaltered", "tx-1")}
 fun allocate(p:Payment,m:Member,note:String):JSONObject{Fixture.mutations++;check(Fixture.allocateBarrier?.await(5,java.util.concurrent.TimeUnit.SECONDS)!=false);return JSONObject()}
 fun enroll(name:String,phone:String):JSONObject{Fixture.enrollMutations++;return JSONObject()}
 fun staffAction(body:JSONObject):JSONObject{Fixture.staffMutations++;return JSONObject()}
 fun setMemberActive(m:Member,active:Boolean):JSONObject{Fixture.lifecycleCalls++;return JSONObject()}
 fun changePin(current:String,next:String,confirm:String){operator=null;if(Fixture.pinUncertain){Fixture.pendingFlag=true;throw ApiFailure("connection_unavailable",0,true)}}
 fun paymentHistory(id:String,cursor:String?=null):Page<PaymentEvent>{
  Fixture.historyReads++;Fixture.lastHistoryId=id;if(Fixture.historyDelay>0)Thread.sleep(Fixture.historyDelay)
  if(Fixture.historyFailure)throw ApiFailure("connection_unavailable",0)
  provenance();Fixture.historySavedAt?.let{lastReadSavedAt=it};val first=cursor==null||Fixture.historyOverlap
  val event=if(first)PaymentEvent("transaction:$id",id,"transaction_recorded","2026-11-08T10:00:00Z",null,null)
    else PaymentEvent("ledger:l-1",id,"ledger_entry","2026-11-08T10:00:01Z",10000,"member-1")
  return Page(listOf(event),if(cursor==null||Fixture.historyLoop)"history-more" else null,2,Fixture.historyRevision,"2026-11-08T10:00:02Z")
 }
 fun exportMember(id:String):String{Fixture.exportReads++;Fixture.lastExportMember=id;return "synthetic csv"}
}

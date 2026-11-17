package rw.ikanisa.burimunsi.checkpointtests

import android.app.Application
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import java.io.ByteArrayInputStream
import java.io.DataInputStream
import java.util.Base64
import rw.ikanisa.burimunsi.ui.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.Fixture
import app.cool.mobile.BuildConfig

private class MemoryCheckpoint(initial:String?=null):NavigationCheckpointStore{
    @Volatile var value=initial
    @Volatile var writes=0
    override fun read()=value
    override fun write(value:String){this.value=value;writes++}
    override fun clear(){value=null}
}
fun main()=runBlocking{
    var checks=0
    fun ck(label:String,value:Boolean){check(value){label};println("PASS $label");checks++}
    val now=System.currentTimeMillis()
    val base=NavigationCheckpoint("operator",Fixture.managedCollection!!,now,Route.PAYMENTS,query="Example",filter="unallocated",index=2,offset=18)
    ck("checkpoint round trip preserves allowed navigation only",NavigationCheckpoint.decode(base.encode())==base)
    ck("owner and group must match",!base.validFor("other",base.groupId,now)&&!base.validFor(base.ownerId,"other",now))
    ck("checkpoint expires after fifteen minutes",base.validFor(base.ownerId,base.groupId,now+NavigationCheckpoint.TTL_MS)&&!base.validFor(base.ownerId,base.groupId,now+NavigationCheckpoint.TTL_MS+1))
    ck("clock rollback refuses checkpoint",!base.validFor(base.ownerId,base.groupId,now-1))
    ck("LOGIN cannot be persisted",runCatching{base.copy(route=Route.LOGIN,filter="all").encode()}.isFailure)
    ck("detail requires bounded opaque record ID",runCatching{base.copy(route=Route.PAYMENT,filter="all").encode()}.isFailure&&runCatching{base.copy(route=Route.MEMBER,filter="all",routeId="../private").encode()}.isFailure)
    ck("list cannot carry a detail ID",runCatching{base.copy(routeId="member-1").encode()}.isFailure)
    ck("filter cannot cross route boundaries",runCatching{base.copy(route=Route.MEMBERS).encode()}.isFailure)
    ck("query controls and overlength rejected",runCatching{base.copy(query="x\u007fy").encode()}.isFailure&&runCatching{base.copy(query="x".repeat(81)).encode()}.isFailure)
    ck("scroll offsets are bounded",runCatching{base.copy(index=-1).encode()}.isFailure&&runCatching{base.copy(offset=100001).encode()}.isFailure)
    ck("null oversized and malformed values fail closed",NavigationCheckpoint.decode(null)==null&&NavigationCheckpoint.decode("a".repeat(4097))==null&&NavigationCheckpoint.decode("broken") == null)
    val bytes=Base64.getDecoder().decode(base.encode())
    ck("trailing bytes rejected",NavigationCheckpoint.decode(Base64.getEncoder().encodeToString(bytes+1.toByte()))==null)
    val future=bytes.copyOf();future[3]=2
    ck("unknown codec version rejected",NavigationCheckpoint.decode(Base64.getEncoder().encodeToString(future))==null)
    val fields=DataInputStream(ByteArrayInputStream(bytes))
    fields.readInt();fields.readUTF();fields.readUTF();fields.readLong();fields.readUTF();fields.readUTF();fields.readUTF();fields.readUTF();fields.readInt();fields.readInt()
    ck("serialized schema ends after the navigation fields",fields.available()==0)
    suspend fun idle(m:BuriViewModel){withTimeout(10000){while(m.state.busy)delay(2)};delay(20)}
    suspend fun loaded(value:NavigationCheckpoint?,role:Role=Role.ADMIN):Pair<BuriViewModel,MemoryCheckpoint>{
        Fixture.role=role
        val store=MemoryCheckpoint(value?.encode());val vm=BuriViewModel(Application(),store){now}
        idle(vm);return vm to store
    }
    Fixture.pendingFlag=true
    val (blocked,blockedStore)=loaded(base)
    ck("A04 restoration keeps unresolved command while reloading list",blocked.state.pending&&blocked.state.route==Route.PAYMENTS&&Fixture.reconciles==0&&Fixture.mutations==0)
    blocked.viewModelScope.cancel()
    val reopened=BuriViewModel(Application(),MemoryCheckpoint(blockedStore.value)){now};idle(reopened)
    ck("A04 repeated recreation never creates a retry",reopened.state.pending&&Fixture.reconciles==0&&Fixture.mutations==0)
    reopened.viewModelScope.cancel();Fixture.pendingFlag=false
    val (m,store)=loaded(base)
    ck("process recreation restores list query filter and context",m.state.route==Route.PAYMENTS&&m.state.search=="Example"&&m.state.filter=="unallocated"&&m.state.listIndex==2&&m.state.listOffset==18)
    ck("restored records come from fresh repository read",m.state.payments?.items?.first()?.id=="tx-1"&&Fixture.lastFilter=="unallocated")
    ck("no command panel beneficiary or draft reconstructed",m.state.sheet==null&&m.state.selectedMember==null&&m.state.draft.isEmpty()&&Fixture.mutations==0&&Fixture.reconciles==0)
    m.listPosition(Route.PAYMENTS,null,7,24);m.search("A\u0000B\u007fC");delay(350)
    ck("debounced checkpoint is latest sanitized navigation",NavigationCheckpoint.decode(store.value)?.let{it.query=="ABC"&&it.index==7&&it.offset==24}==true)
    m.navigate(Route.PAYMENT,"tx-restore");idle(m);delay(50);val savedDetail=store.value
    m.viewModelScope.cancel()
    val restored=BuriViewModel(Application(),MemoryCheckpoint(savedDetail)){now};idle(restored)
    ck("detail is read back by restored ID",restored.state.payment?.id=="tx-restore"&&restored.state.routeId=="tx-restore")
    restored.back();idle(restored)
    ck("restored detail Back returns to its parent list",restored.state.route==Route.PAYMENTS)
    restored.back();idle(restored)
    ck("parent Back does not loop to restored detail",restored.state.route==Route.HOME)
    restored.viewModelScope.cancel()
    for((label,bad) in listOf("wrong owner" to base.copy(ownerId="another"),"wrong group" to base.copy(groupId="another"),"expired" to base.copy(savedAt=now-NavigationCheckpoint.TTL_MS-1),"future" to base.copy(savedAt=now+1))){
        val (vm,_)=loaded(bad);ck("$label bookmark falls back to fresh Home",vm.state.route==Route.HOME&&vm.state.search.isEmpty());vm.viewModelScope.cancel()
    }
    val (staff,_)=loaded(base.copy(route=Route.SMS,filter="all"),Role.STAFF)
    ck("restoration cannot revive privileged SMS route for Staff",staff.state.route==Route.HOME&&staff.state.messages==null);staff.viewModelScope.cancel()
    val (logout,logoutStore)=loaded(base)
    logout.listPosition(Route.PAYMENTS,null,9,1);logout.logout();idle(logout);delay(350)
    ck("logout clears checkpoint and cancels debounced writes",logoutStore.value==null&&logout.state.operator==null);logout.viewModelScope.cancel()
    val corrupt=MemoryCheckpoint("not a checkpoint");val corruptVm=BuriViewModel(Application(),corrupt){now};idle(corruptVm)
    ck("corrupt encrypted payload is optional not an authentication failure",corruptVm.state.route==Route.HOME&&corruptVm.state.operator!=null);corruptVm.viewModelScope.cancel()
    val (financial,_)=loaded(base)
    Fixture.pendingFlag=true;financial.refresh();idle(financial)
    for(effect in listOf("reversed","corrected")){
        Fixture.financialState=effect;Fixture.outcomeState="committed"
        val oldMutations=Fixture.mutations;financial.retry();idle(financial)
        ck("A04 $effect recovery displays financial warning without POST",financial.state.commandNotice?.contains("reversed or corrected")==true&&financial.state.error==null&&Fixture.mutations==oldMutations)
    }
    financial.viewModelScope.cancel();Fixture.pendingFlag=false;Fixture.financialState="posted"
    println("RESULT: $checks checkpoint and actual-controller restoration checks passed; storage encryption and Android process lifecycle not executed.")
}

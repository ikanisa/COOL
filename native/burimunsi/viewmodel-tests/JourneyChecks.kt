package rw.ikanisa.burimunsi.journeytests

import android.app.Application
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import rw.ikanisa.burimunsi.ui.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.burimunsi.gateway.GatewayFixture

/** Operational journey integration at the real controller boundary; providers/platform are doubles. */
fun main()=runBlocking{
    var assertions=0;var journeys=0
    fun ck(label:String,value:Boolean){check(value){label};println("PASS $label");assertions++}
    suspend fun idle(m:BuriViewModel){withTimeout(10000){while(m.state.busy)delay(2)};delay(15)}
    suspend fun journey(id:String,name:String,body:suspend (BuriViewModel)->Unit){
        Fixture.role=Role.ADMIN;Fixture.pendingFlag=false;Fixture.cached=false;Fixture.memberCached=false
        Fixture.sessionFailure=null;Fixture.refreshedRole=null;Fixture.refreshedCaps=null
        Fixture.rawFailure=false;Fixture.paymentFailure=false
        val m=BuriViewModel(Application());idle(m)
        try{body(m);journeys++;println("JOURNEY $id PASS $name")}finally{m.viewModelScope.cancel()}
    }
    journey("J01","sign-in and sign-out"){m->
        m.logout();idle(m);ck("J01 logout clears protected screen",m.state.operator==null&&m.state.route==Route.LOGIN)
        m.login("0780000001","2468");idle(m);ck("J01 login reaches canonical Home read boundary",m.state.route==Route.HOME&&m.state.home!=null)
    }
    journey("J02","Home and unallocated shortcut"){m->
        ck("J02 dashboard uses repository values",m.state.home?.balanceRwf==10000L)
        m.openUnallocated();idle(m);ck("J02 shortcut filters before read",m.state.route==Route.PAYMENTS&&m.state.filter=="unallocated"&&Fixture.lastFilter=="unallocated")
    }
    journey("J03","payment search pagination and return"){m->
        m.navigate(Route.PAYMENTS);idle(m);m.search("Example");m.searchSubmit();idle(m);m.setFilter("unallocated");idle(m);m.more();idle(m)
        ck("J03 second page is reachable",m.state.payments?.items?.size==2)
        m.listPosition(Route.PAYMENTS,null,3,10);m.navigate(Route.PAYMENT,"tx-2");idle(m);m.back();idle(m)
        ck("J03 Back restores query filter and position",m.state.search=="Example"&&m.state.filter=="unallocated"&&m.state.listIndex==3&&m.state.listOffset==10)
    }
    journey("J04","payment history and unaltered source evidence"){m->
        val mutations=Fixture.mutations;m.navigate(Route.PAYMENT,"tx-1");idle(m);m.openSheet(Sheet.HISTORY);idle(m);m.more();idle(m)
        ck("J04 history pagination remains transaction scoped",m.state.history?.items?.size==2&&m.state.historyPaymentId=="tx-1")
        m.closeSheet();m.openSheet(Sheet.RAW,"sms-1");idle(m);m.revealRaw("Verified support request");idle(m);ck("J04 original receipt is unchanged",m.state.raw?.body=="unaltered"&&Fixture.mutations==mutations)
    }
    journey("J05","allocation and unresolved-action block"){m->
        val before=Fixture.mutations;m.navigate(Route.PAYMENT,"tx-1");idle(m);m.openSheet(Sheet.ALLOCATE);idle(m)
        m.allocate("Verified identity");idle(m);ck("J05 no allocation without selected identity",Fixture.mutations==before)
        m.selectMember(Fixture.member);Fixture.pendingFlag=true;m.refresh();idle(m);m.allocate("Verified identity");idle(m)
        ck("J05 unresolved action blocks repeat dispatch",Fixture.mutations==before&&m.state.pending)
        Fixture.pendingFlag=false;m.refresh();idle(m);m.selectMember(Fixture.member);m.allocate("Verified identity");idle(m)
        ck("J05 explicit allocation dispatches once and clears draft",Fixture.mutations==before+1&&m.state.sheet==null&&m.state.selectedMember==null)
    }
    journey("J06","member enrollment and unsaved changes"){m->
        m.openSheet(Sheet.ENROLL);idle(m);m.editDraft("name","Example Member");m.closeSheet();ck("J06 unsaved enrollment requests confirmation",m.state.discardRequested)
        m.keepDraft();ck("J06 keep editing preserves name",m.state.draft["name"]=="Example Member")
        val before=Fixture.enrollMutations;m.enroll("A","0780000001");idle(m);ck("J06 invalid name does not dispatch",Fixture.enrollMutations==before)
        m.enroll("Example Member","0780000001");idle(m);ck("J06 explicit save clears form",Fixture.enrollMutations==before+1&&m.state.draft.isEmpty()&&m.state.sheet==null)
        ck("J06 saved member opens its freshly read transactions",m.state.route==Route.MEMBER&&m.state.routeId=="member-1"&&m.state.member?.id=="member-1"&&m.state.memberTransactions!=null)
        m.back();idle(m);ck("J06 Back returns to the original route",m.state.route==Route.HOME)
        m.openSheet(Sheet.ENROLL);idle(m);Fixture.enrollResponseGroup="other-group"
        m.enroll("Example Member","0780000001");idle(m)
        ck("J06 wrong collection cannot select a member or replay enrollment",m.state.route==Route.HOME&&m.state.member==null&&Fixture.enrollMutations==before+2&&m.state.commandNotice!=null)
        Fixture.enrollResponseGroup=null;m.refresh();idle(m)
        m.openSheet(Sheet.ENROLL);idle(m);Fixture.memberReadFailure=ApiFailure("connection_unavailable",0)
        m.enroll("Example Member","0780000001");idle(m)
        ck("J06 committed enrollment with failed ledger read stays on member without redispatch",m.state.route==Route.MEMBER&&m.state.routeId=="member-1"&&m.state.member==null&&Fixture.enrollMutations==before+3&&m.state.commandNotice!=null)
        Fixture.memberReadFailure=null;m.refresh();idle(m)
        ck("J06 retry reads the saved transactions without another enrollment",m.state.member?.id=="member-1"&&m.state.memberTransactions!=null&&Fixture.enrollMutations==before+3)
    }
    journey("J07","member ledger export and lifecycle"){m->
        m.navigate(Route.MEMBER,"member-1");idle(m);ck("J07 member and transactions load together",m.state.member?.id=="member-1"&&m.state.memberTransactions!=null)
        var csv:String?=null;m.export{csv=it};idle(m);ck("J07 export uses selected member boundary",csv=="synthetic csv"&&Fixture.lastExportMember=="member-1")
        val before=Fixture.lifecycleCalls;m.openSheet(Sheet.MEMBER_DETAILS);idle(m);m.setMemberActive(false);idle(m);ck("J07 lifecycle command remains explicit",Fixture.lifecycleCalls==before+1)
    }
    journey("J08","profile passcode and continued session"){m->
        m.openSheet(Sheet.PROFILE);idle(m);m.openSheet(Sheet.PIN);idle(m);m.back();idle(m);ck("J08 Close returns to the original route",m.state.sheet==null)
        m.openSheet(Sheet.PIN);idle(m);m.changePin("2468","8642","8642");idle(m);ck("J08 passcode change keeps the operator signed in",m.state.operator!=null&&m.state.sheet==null&&m.state.route!=Route.LOGIN)
    }
    journey("J09","staff account and removal confirmation"){m->
        m.openSheet(Sheet.STAFF);idle(m);m.more();idle(m);m.openSheet(Sheet.STAFF_EDIT,"staff-1");idle(m);m.editDraft("name","New staff name");m.requestRemoveStaff();idle(m)
        ck("J09 removal has a contextual confirmation",m.state.sheet==Sheet.REMOVE_STAFF)
        m.back();idle(m);ck("J09 cancel removal returns to route",m.state.sheet==null&&m.state.draft.isEmpty())
        m.openSheet(Sheet.STAFF);idle(m);m.openSheet(Sheet.STAFF_EDIT,"staff-1");idle(m)
        val before=Fixture.staffMutations;m.saveStaff("New staff name","0780000003","",true,false);idle(m);ck("J09 blank-PIN phone edit omits the credential and returns to the staff list",Fixture.staffMutations==before+1&&m.state.sheet==Sheet.STAFF&&Fixture.lastStaffBody?.optString("phone")=="+250780000003"&&Fixture.lastStaffBody?.has("pin")==false&&Fixture.lastStaffAutoResolve&&m.state.operator!=null)
    }
    journey("J10","receiving-phone diagnostics and capture controls"){m->
        GatewayFixture.snapshot=GatewayStatus(true,false,1,2,null,null,null,"uploads_on_hold")
        m.openSheet(Sheet.GATEWAY);idle(m);ck("J10 diagnostic separates receipt queue from member credit",GatewayHealth.describe(m.state.gateway).code=="hold"&&m.state.home?.balanceRwf==10000L)
        val before=GatewayFixture.changes;m.setPaused(false);idle(m);m.setPaused(true);idle(m)
        ck("J10 admin sync remains enabled and preserves retained receipts",GatewayFixture.changes==before+1&&m.state.gateway?.captureEnabled==true&&m.state.gateway?.pending==2&&m.state.error!=null)
    }
    journey("J11","SMS filter raw source and role revocation"){m->
        m.navigate(Route.SMS);idle(m);m.setFilter("queued");idle(m)
        ck("J11 queue filter shows the local queue",m.state.queuedObservations!=null&&!m.state.queuedUnavailable)
        m.setFilter("all");idle(m);m.openSheet(Sheet.RAW,"s-1");idle(m)
        ck("J11 canonical source view remains reachable",m.state.raw?.id=="s-1")
        Fixture.refreshedRole=Role.STAFF;Fixture.refreshedCaps=setOf(Capability.READ.key);m.refreshSession();idle(m)
        ck("J11 revocation removes raw data and SMS route",m.state.route==Route.HOME&&m.state.raw==null&&m.state.messages==null)
    }
    journey("J12","background offline recovery and no replay"){m->
        m.navigate(Route.PAYMENTS);idle(m);val before=Fixture.mutations;val reconciles=Fixture.reconciles
        m.onBackground();Fixture.sessionFailure=ApiFailure("connection_unavailable",0);m.onForeground();idle(m)
        ck("J12 failed foreground check keeps records guarded",m.screenGate==ScreenGate.REVALIDATE)
        m.navigate(Route.PAYMENT,"tx-1");idle(m);ck("J12 guarded navigation cannot bypass revalidation",m.state.route==Route.PAYMENTS)
        Fixture.sessionFailure=null;m.refresh();idle(m)
        ck("J12 explicit recovery does not replay financial commands",m.screenGate==ScreenGate.OPEN&&Fixture.mutations==before&&Fixture.reconciles==reconciles)
    }
    check(journeys==12)
    println("RESULT: $journeys controller journeys and $assertions assertions passed; not Compose interactions, real PIN providers, SMS transport or PostgreSQL acceptance.")
}

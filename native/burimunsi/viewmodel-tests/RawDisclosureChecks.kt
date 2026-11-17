package rw.ikanisa.burimunsi.rawdisclosuretests

import android.app.Application
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.burimunsi.ui.*
import java.util.concurrent.CountDownLatch

/** Real controller; repository/platform doubles. Opening the prototype raw panel
 * is the explicit audited action; no reason-entry screen or real SMS/provider. */
fun main()=runBlocking{
 var checks=0
 fun ck(label:String,value:Boolean){check(value){label};println("PASS $label");checks++}
 suspend fun idle(m:BuriViewModel){withTimeout(5000){while(m.state.busy)delay(2)};delay(10)}
 Fixture.rawReads=0;Fixture.rawFailure=false;Fixture.rawApiFailure=null;Fixture.role=Role.ADMIN;Fixture.restoreSignedOut=false;Fixture.pendingFlag=true
 val m=BuriViewModel(Application());idle(m);m.navigate(Route.PAYMENT,"tx-1");idle(m);m.openSheet(Sheet.RAW,"sms-1");idle(m)
 ck("explicit panel open audits one honest application-action purpose",Fixture.rawReads==1&&Fixture.lastRawReason=="Review original SMS from the selected contribution or receipt")
 ck("original prototype panel displays exact plaintext after authorized response",m.state.raw?.body=="unaltered"&&m.state.rawDisclosure==RawDisclosureState.REVEALED)
 for(reason in listOf("short","        ","valid reason\n","x".repeat(1001),"valid reason\u0085")){
  m.revealRaw(reason);idle(m);ck("invalid programmatic disclosure reason cannot dispatch",Fixture.rawReads==1&&m.state.raw==null&&m.state.rawDisclosure==RawDisclosureState.FAILURE)
 }
 val reason="  Gusuzuma inyemezabwishyu y’umunyamuryango 🧾  ";m.revealRaw(reason);idle(m)
 ck("audited Unicode purpose remains validated and trimmed",Fixture.rawReads==2&&Fixture.lastRawReason==reason.trim())
 ck("raw disclosure never changes pending financial outcome",m.state.pending&&Fixture.pendingFlag&&Fixture.mutations==0&&Fixture.reconciles==0)
 m.refresh();idle(m);ck("read refresh clears plaintext without repeating audited disclosure",m.state.raw==null&&Fixture.rawReads==2)
 m.closeSheet();m.openSheet(Sheet.RAW,"sms-1");idle(m);ck("a new explicit open may request the original source again",m.state.raw?.id=="sms-1"&&Fixture.rawReads==3)
 m.openSheet(Sheet.HELP);idle(m);m.back();idle(m);ck("replacing and closing a panel never restores old plaintext",m.state.sheet==null&&m.state.raw==null&&Fixture.rawReads==3)
 m.openSheet(Sheet.RAW,"sms-1");idle(m);m.navigate(Route.MEMBERS);idle(m);m.back();idle(m)
 ck("navigation memory never restores a raw disclosure sheet",m.state.sheet==null&&m.state.raw==null&&Fixture.rawReads==4)
 val entered=CountDownLatch(1);val release=CountDownLatch(1);Fixture.rawEntered=entered;Fixture.rawBarrier=release
 m.openSheet(Sheet.RAW,"sms-1");withTimeout(2000){while(entered.count!=0L)delay(2)};m.onBackground()
 ck("background immediately removes raw panel and active disclosure",m.state.sheet==null&&m.state.raw==null)
 m.onForeground();Fixture.rawBarrier=null;Fixture.rawEntered=null;release.countDown();idle(m)
 ck("late plaintext is discarded and resume never rediscloses",m.state.raw==null&&m.state.sheet==null&&Fixture.rawReads==5)
 Fixture.rawApiFailure=ApiFailure("connection_unavailable",0,true);m.openSheet(Sheet.RAW,"sms-1");idle(m)
 ck("unknown raw outcome remains separate from financial uncertainty",m.state.raw==null&&m.state.rawDisclosure==RawDisclosureState.FAILURE&&m.state.failure==DisplayFailure.NONE&&m.state.pending)
 m.refresh();idle(m);ck("unknown raw outcome has no automatic retry",Fixture.rawReads==6&&m.state.raw==null)
 m.closeSheet();Fixture.rawApiFailure=null;m.openSheet(Sheet.RAW,"sms-1");idle(m);m.onBackground();Fixture.refreshedRole=Role.STAFF;Fixture.refreshedCaps=setOf(Capability.READ.key);m.onForeground();idle(m)
 ck("permission replacement disposes all raw data",m.state.sheet==null&&m.state.raw==null&&Fixture.rawReads==7)
 m.openSheet(Sheet.RAW,"sms-1");idle(m);ck("revoked SMS capability cannot dispatch another disclosure",Fixture.rawReads==7&&m.state.sheet==null)
 ck("all disclosures remain outside financial mutation or reconciliation",Fixture.mutations==0&&Fixture.reconciles==0&&Fixture.pendingFlag)
 m.onBackground();m.viewModelScope.cancel();println("$checks original-panel raw disclosure checks passed")
}

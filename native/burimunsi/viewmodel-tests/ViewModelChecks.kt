package rw.ikanisa.burimunsi.viewmodeltests
import android.app.Application
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import rw.ikanisa.burimunsi.ui.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.Fixture
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.gateway.GatewayFixture
fun main()=runBlocking{
 var checks=0
 fun ck(label:String,v:Boolean){check(v){label};println("PASS $label");checks++}
 val m=BuriViewModel(Application())
 suspend fun idle(){withTimeout(10000){while(m.state.busy)delay(2)};delay(5)}
 idle();ck("restored Home",m.state.route==Route.HOME&&m.state.operator!=null)
 m.navigate(Route.MEMBERS);idle();m.search("Alice");m.searchSubmit();idle();m.listPosition(Route.MEMBERS,null,8,12)
 m.navigate(Route.MEMBER,"member-1");idle();m.navigate(Route.PAYMENT,"tx-1");idle();m.back();idle()
 ck("payment Back restores originating member",m.state.route==Route.MEMBER&&m.state.member?.id=="member-1")
 m.back();idle();ck("Back restores query and scroll",m.state.route==Route.MEMBERS&&m.state.search=="Alice"&&m.state.listIndex==8&&m.state.listOffset==12)
 Fixture.cached=true;m.navigate(Route.PAYMENT,"tx-2");idle();ck("cached detail carries provenance",m.state.offline&&m.state.savedAt==Fixture.saved)
 Fixture.cached=false;Fixture.memberCached=true;m.navigate(Route.MEMBER,"member-2");idle();ck("mixed member/ledger preserves oldest cached provenance",m.state.offline&&m.state.savedAt==Fixture.saved);Fixture.memberCached=false
 m.navigate(Route.HOME);idle();m.openSheet(Sheet.ENROLL);idle();m.editDraft("name","Draft name");m.editDraft("pin","2468");m.closeSheet()
 ck("dirty close asks before discarding",m.state.discardRequested&&m.state.sheet==Sheet.ENROLL)
 ck("credentials excluded from draft",!m.state.draft.containsKey("pin"))
 m.keepDraft();ck("keep editing retains value",m.state.draft["name"]=="Draft name"&&!m.state.discardRequested)
 m.discardDraft();ck("discard clears draft",m.state.sheet==null&&m.state.draft.isEmpty())
 m.openSheet(Sheet.STAFF);idle();m.more();idle();ck("staff second page reachable",m.state.staff?.items?.map{it.id}==listOf("staff-1","staff-2")&&m.state.staff?.nextCursor==null);m.closeSheet()
 m.openSheet(Sheet.AUDIT);idle();m.more();idle();ck("audit second page reachable",m.state.audit?.items?.size==2);m.closeSheet()
 m.navigate(Route.PAYMENT,"tx-1");idle();m.openSheet(Sheet.ALLOCATE);idle();m.more();idle();ck("allocation candidates second page reachable",m.state.members?.items?.size==2);m.closeSheet()
 m.navigate(Route.SMS);idle();m.setFilter("queued");idle();ck("queued SMS uses the local observation view",m.state.queuedObservations!=null&&!m.state.queuedUnavailable);m.navigate(Route.PAYMENTS);idle();ck("SMS filter does not leak into Payments",m.state.filter=="all")
 m.navigate(Route.HOME);idle();m.openUnallocated();idle();delay(80);idle();ck("Unallocated shortcut applies its filter",m.state.route==Route.PAYMENTS&&Fixture.lastFilter=="unallocated")
 m.openSheet(Sheet.PROFILE);idle();m.openSheet(Sheet.PIN);idle()
 ck("profile passcode replaces the current prototype sheet",m.state.sheet==Sheet.PIN&&m.state.panelDepth==0)
 m.back();idle();ck("passcode Close returns to underlying route",m.state.sheet==null&&m.state.panelDepth==0)
 m.openSheet(Sheet.STAFF);idle();m.more();idle();m.openSheet(Sheet.STAFF_EDIT,"staff-1");idle()
 m.editDraft("name","Unsaved staff rename");m.requestRemoveStaff();idle()
 ck("remove-access replaces the edit sheet with contextual confirmation",m.state.sheet==Sheet.REMOVE_STAFF&&m.state.panelDepth==0&&m.state.selectedStaff?.id=="staff-1")
 m.back();idle();ck("cancel removal returns to route without reviving a discarded edit",m.state.sheet==null&&m.state.draft.isEmpty()&&!m.state.draftDirty)
 m.openSheet(Sheet.STAFF);idle();m.more();idle()
 m.openSheet(Sheet.STAFF_EDIT,"missing-staff");idle();ck("missing edit target never becomes a selected account",m.state.error!=null&&m.state.selectedStaff==null&&m.state.sheetId=="missing-staff")
 m.closeSheet();m.closeSheet()
 m.navigate(Route.PAYMENT,"tx-1");idle();m.openSheet(Sheet.ALLOCATE);idle();m.selectMember(Fixture.member);m.editDraft("note","")
 ck("clearing note cannot hide selected-member dirty state",m.state.draftDirty&&m.state.selectedMember!=null)
 m.editDraft("note","Verified full identity");m.refresh();idle()
 ck("read refresh preserves allocation draft and selection",m.state.draft["note"]=="Verified full identity"&&m.state.selectedMember?.id=="member-1")
 ck("read retry never dispatches allocation",Fixture.mutations==0)
 m.discardDraft();Fixture.rawFailure=true;m.openSheet(Sheet.RAW,"sms-retry");idle();ck("opening original SMS audits the explicit panel-open purpose once",m.state.rawDisclosure==RawDisclosureState.FAILURE&&Fixture.rawReads==1&&Fixture.lastRawReason=="Review original SMS from the selected contribution or receipt")
 ck("failed original-SMS read retains retry identity",m.state.raw==null&&m.state.sheetId=="sms-retry"&&m.state.rawError!=null)
 Fixture.rawFailure=false;m.refresh();idle();ck("refresh never repeats disclosure",m.state.raw==null&&Fixture.rawReads==1);m.revealRaw("Verified support request");idle();ck("explicit reveal retains original identity",m.state.raw?.id=="sms-retry"&&Fixture.rawReads==2)
 m.closeSheet();m.openSheet(Sheet.ENROLL);idle();m.editDraft("name","Keep this name");m.navigate(Route.MEMBERS)
 ck("navigation cannot silently destroy unsaved form",m.state.discardRequested&&m.state.sheet==Sheet.ENROLL)
 m.keepDraft();ck("cancel navigation preserves active form",m.state.sheet==Sheet.ENROLL&&m.state.draft["name"]=="Keep this name")
 m.navigate(Route.MEMBERS);m.discardDraft();idle();ck("confirmed discard follows intended destination",m.state.route==Route.MEMBERS&&m.state.sheet==null)
 m.navigate(Route.PAYMENT,"tx-1");idle();m.openSheet(Sheet.HISTORY);idle()
 ck("history loads for exact current payment",m.state.historyPaymentId=="tx-1"&&Fixture.lastHistoryId=="tx-1"&&m.state.history?.items?.size==1)
 m.more();idle();ck("history continuation reaches recorded ledger change",m.state.history?.items?.size==2&&m.state.history?.nextCursor==null)
 m.closeSheet();m.openSheet(Sheet.HISTORY);idle();Fixture.historyRevision="changed";m.more();idle()
 ck("changed history snapshot quarantines copies and reports error",m.state.history==null&&m.state.readbackRequired&&m.state.error!=null&&!m.presentation.showRecords)
 Fixture.historyRevision="history-v1";Fixture.historyLoop=true;m.refresh();idle();m.more();idle()
 ck("looping history cursor is refused",m.state.history==null&&m.state.readbackRequired&&m.state.error?.contains("inconsistent")==true)
 Fixture.historyLoop=false;Fixture.historyOverlap=true;m.refresh();idle();m.more();idle()
 ck("overlapping history rows are quarantined rather than deduplicated",m.state.history==null&&m.state.readbackRequired&&m.state.error!=null)
 Fixture.historyOverlap=false;m.closeSheet();m.navigate(Route.PAYMENT,"tx-2");idle();Fixture.historyFailure=true;m.openSheet(Sheet.HISTORY);idle()
 ck("failed new history cannot display previous payment events",m.state.history==null&&m.state.sheetId=="tx-2"&&m.state.error!=null)
 Fixture.historyFailure=false;m.refresh();idle();ck("history retry uses the correct panel identity",m.state.historyPaymentId=="tx-2"&&m.state.history?.items?.first()?.transactionId=="tx-2")
 Fixture.cached=true;m.refresh();idle();ck("cached history exposes its own saved-data provenance",m.state.historyOffline&&m.state.historySavedAt==Fixture.saved)
 Fixture.cached=false;m.refresh();idle();ck("live history refresh clears its stale badge",!m.state.historyOffline)
 ck("history browsing never dispatches allocation",Fixture.mutations==0)
 m.closeSheet()
 Fixture.recordSavedAt=System.currentTimeMillis()-SnapshotFreshness.TTL_MS-60000
 m.navigate(Route.PAYMENT,"expired-tx");idle();m.navigate(Route.MEMBERS);idle();Fixture.paymentFailure=true;m.back();idle()
 ck("expired navigation snapshot cannot bypass cache policy",m.state.routeId=="expired-tx"&&m.state.payment==null&&m.state.error!=null)
 Fixture.paymentFailure=false;Fixture.recordSavedAt=null;m.refresh();idle();ck("expired route recovers through a fresh read",m.state.payment?.id=="expired-tx")
 Fixture.recordSavedAt=System.currentTimeMillis()+60000;m.navigate(Route.PAYMENT,"future-tx");idle();m.navigate(Route.MEMBERS);idle()
 val readsBefore=Fixture.paymentReads;Fixture.recordSavedAt=null;m.back();idle()
 ck("clock rollback forces navigation readback",Fixture.paymentReads==readsBefore+1)
 m.navigate(Route.HOME);idle();m.openSheet(Sheet.AUDIT);idle()
 ck("privileged activity loaded before permission change",m.state.audit?.items?.isNotEmpty()==true)
 Fixture.refreshedRole=Role.STAFF;Fixture.refreshedCaps=setOf(Capability.READ.key,Capability.ENROLL.key)
 m.refreshSession();idle()
 ck("permission downgrade clears privileged panel and data",m.state.operator?.role==Role.STAFF&&m.state.sheet==null&&m.state.audit==null&&m.state.raw==null&&m.state.staff==null)
 m.back();idle();m.openSheet(Sheet.AUDIT);idle()
 ck("revoked activity cannot return through navigation memory",m.state.sheet==null&&m.state.audit==null)
 Fixture.refreshedRole=null;Fixture.refreshedCaps=null
 m.navigate(Route.HOME);idle()
 Fixture.pendingFlag=true;m.refresh();idle()
 val mutBefore=Fixture.enrollMutations;val staffBefore=Fixture.staffMutations
 m.enroll("Example Member","0780000001");idle()
 m.changePin("2468","8642","8642");idle()
 ck("pending command prevents enrollment and passcode change",Fixture.enrollMutations==mutBefore&&m.state.operator!=null)
 m.navigate(Route.MEMBERS);idle();m.openSheet(Sheet.ENROLL);idle()
 m.enroll("Another Member","0780000001");idle()
 ck("pending command blocks another enrollment even in a form",Fixture.enrollMutations==mutBefore)
 m.navigate(Route.HOME);idle();m.openSheet(Sheet.STAFF);idle();m.staffAction("disable");idle()
 ck("pending command blocks unrelated staff mutation",Fixture.staffMutations==staffBefore)
 m.closeSheet();Fixture.pendingFlag=false;m.refresh();idle()
 m.navigate(Route.HOME);idle()
 val beforePendingCheck=Fixture.homeReads
 Fixture.outcomeState="pending";val beforeStatusChecks=Fixture.reconciles
 m.retry();idle()
 ck("pending status remains unresolved without refreshing balances",Fixture.reconciles==beforeStatusChecks+1&&Fixture.homeReads==beforePendingCheck&&m.state.error?.contains("Still awaiting")==true)
 Fixture.outcomeState="rejected";m.retry();idle()
 ck("rejection is explained after authoritative recheck",m.state.error?.contains("rejected")==true&&Fixture.homeReads==beforePendingCheck+1)
 Fixture.outcomeState="cancelled";m.retry();idle()
 ck("cancelled staff action does not claim a commit",m.state.commandNotice?.contains("cancelled before it was applied")==true)
 Fixture.outcomeState="committed"
 m.logout();idle();ck("logout clears operator and UI drafts",m.state.operator==null&&m.state.draft.isEmpty());Fixture.role=Role.STAFF;m.login("0780000001","2468");idle()
 m.navigate(Route.MEMBERS);idle();ck("new session does not inherit query",m.state.search.isEmpty())
 m.navigate(Route.MEMBER,"member-1");idle();m.setMemberActive(false);idle();ck("native Staff lifecycle denied",Fixture.lifecycleCalls==0&&m.state.error=="Access unavailable.")
 m.viewModelScope.cancel()
 // Real ViewModel, synthetic session/gateway boundaries: replacement is retirement,
 // and its independent acknowledgement can never clear or impersonate a financial outcome.
 suspend fun settle(value:BuriViewModel){withTimeout(10000){while(value.state.busy)delay(2)};delay(5)}
 Fixture.role=Role.ADMIN;Fixture.pendingFlag=false;Fixture.restoreSignedOut=false
 Fixture.sessionFailure=null;Fixture.gatewayPairFailure=null;Fixture.retirementPendingFlag=false;Fixture.retirementRecordPresent=false
 GatewayFixture.retired=false;GatewayFixture.snapshot=GatewayStatus(false,false,1,4,null,null,null,null)
 val target=BuriViewModel(Application());settle(target)
 val credentialsBefore=Fixture.gatewayCredentialsInstalled
 Fixture.gatewayPairFailure=ApiFailure("session_changed",401)
 target.pair("initial-pair-code");settle(target)
 ck("activation scope change returns to original Login rather than rebasing a session",target.state.route==Route.LOGIN&&target.state.operator==null)
 ck("stale PIN link cannot install a receiver credential",Fixture.gatewayCredentialsInstalled==credentialsBefore&&!GatewayFixture.snapshot.authorized)
 val loginBefore=Fixture.loginCalls;Fixture.gatewayPairFailure=null
 target.login("0780000001","2468");settle(target);target.pair("initial-pair-code");settle(target)
 ck("explicit fresh PIN login precedes target Pair",Fixture.loginCalls==loginBefore+1&&Fixture.gatewayCredentialsInstalled==credentialsBefore+1&&target.state.operator!=null)
 Fixture.pendingFlag=true;target.refresh();settle(target)
 val requestsBefore=Fixture.gatewayPairCalls
 target.replaceReceiver("replacement-code");settle(target)
 ck("unconfirmed financial journal refuses old-phone retirement",Fixture.gatewayPairCalls==requestsBefore&&Fixture.pendingFlag&&target.state.pending)
 Fixture.pendingFlag=false;target.refresh();settle(target)
 val statusBefore=GatewayFixture.statusReads;val clearsBefore=Fixture.clearOperatorCalls;val logoutBefore=Fixture.logoutCalls
 val credentialsAtRetire=Fixture.gatewayCredentialsInstalled;val queueBefore=GatewayFixture.queuedReceipts
 target.replaceReceiver("replacement-code");settle(target)
 ck("positive retirement ACK returns old phone to original Login",target.state.route==Route.LOGIN&&target.state.operator==null&&!target.receiverRetirementPending)
 ck("verified ACK performs local operator teardown without revoked-session logout POST",Fixture.clearOperatorCalls==clearsBefore+1&&Fixture.logoutCalls==logoutBefore)
 ck("old receiver never adopts target credential or reloads Gateway after ACK",Fixture.gatewayCredentialsInstalled==credentialsAtRetire&&GatewayFixture.statusReads==statusBefore)
 ck("retirement parks capture while retaining queued evidence",GatewayFixture.retired&&!GatewayFixture.snapshot.captureEnabled&&GatewayFixture.queuedReceipts==queueBefore)
 target.viewModelScope.cancel()
 GatewayFixture.retired=false;GatewayFixture.snapshot=GatewayStatus(true,true,1,4,null,null,null,null)
 Fixture.retirementUnknown=true;Fixture.retirementAckReady=false;Fixture.retirementPendingFlag=false;Fixture.retirementRecordPresent=false
 val old=BuriViewModel(Application());settle(old)
 val unknownPostBefore=Fixture.gatewayPairCalls;val unknownClears=Fixture.clearOperatorCalls
 old.replaceReceiver("unknown-replacement-code");settle(old)
 ck("lost retirement ACK retains independent pending state",old.receiverRetirementPending&&Fixture.retirementPendingFlag)
 ck("gateway uncertainty is not a financial pending outcome",!old.state.pending&&!Fixture.pendingFlag&&old.state.failure==DisplayFailure.NONE)
 ck("unconfirmed retirement hides financial records and plaintext",old.screenGate==ScreenGate.CHECKING&&!old.presentation.showRecords&&old.state.home==null&&old.state.raw==null)
 ck("unknown ACK does not clear the operator or resend retirement",Fixture.clearOperatorCalls==unknownClears&&Fixture.gatewayPairCalls==unknownPostBefore+1)
 Fixture.sessionFailure=ApiFailure("session_changed",401)
 val authReads=Fixture.sessionReads;val recoverReads=Fixture.retirementRecoveryReads
 old.replaceReceiver("");settle(old);old.refresh();settle(old)
 ck("same original button and Refresh check only the retirement outcome",Fixture.retirementRecoveryReads==recoverReads+2&&Fixture.gatewayPairCalls==unknownPostBefore+1)
 ck("read-only recovery precedes revoked ordinary session validation",Fixture.sessionReads==authReads&&old.receiverRetirementPending&&Fixture.clearOperatorCalls==unknownClears)
 old.viewModelScope.cancel()
 val restoresBefore=Fixture.restoreReads;val recoveryBeforeRestart=Fixture.retirementRecoveryReads
 val restarted=BuriViewModel(Application());settle(restarted)
 ck("recreated ViewModel checks encrypted original retirement before restoring session",Fixture.retirementRecoveryReads==recoveryBeforeRestart+1&&Fixture.restoreReads==restoresBefore&&restarted.receiverRetirementPending)
 val uploadStarts=GatewayFixture.uploadStarts
 restarted.onForeground();settle(restarted)
 ck("foreground pending recovery grants no upload or financial authority",GatewayFixture.uploadStarts==uploadStarts&&Fixture.sessionReads==authReads&&!restarted.presentation.showRecords)
 Fixture.pendingFlag=true;Fixture.retirementAckReady=true
 restarted.refresh();settle(restarted)
 ck("recovered ACK clears operator only after positive readback",restarted.state.route==Route.LOGIN&&restarted.state.operator==null&&Fixture.clearOperatorCalls==unknownClears+1)
 ck("recovered retirement preserves another unresolved financial journal and queue",Fixture.pendingFlag&&restarted.state.pending&&GatewayFixture.queuedReceipts==queueBefore)
 ck("ACK recovery never issues a second retirement POST or installs target credential",Fixture.gatewayPairCalls==unknownPostBefore+1&&Fixture.gatewayCredentialsInstalled==credentialsAtRetire)
 restarted.viewModelScope.cancel()
 Fixture.pendingFlag=false;Fixture.retirementPendingFlag=false;Fixture.retirementRecordPresent=true
 GatewayFixture.retired=false;GatewayFixture.snapshot=GatewayFixture.snapshot.copy(captureEnabled=true)
 val terminalPosts=Fixture.gatewayPairCalls;val terminalRestores=Fixture.restoreReads
 val interrupted=BuriViewModel(Application());settle(interrupted)
 ck("terminal ACK journal repairs interrupted local retirement before restoring authority",GatewayFixture.retired&&!GatewayFixture.snapshot.captureEnabled&&Fixture.restoreReads==terminalRestores&&interrupted.state.route==Route.LOGIN)
 ck("terminal ACK recovery grants no replacement credential or second POST",Fixture.gatewayPairCalls==terminalPosts&&Fixture.gatewayCredentialsInstalled==credentialsAtRetire)
 interrupted.viewModelScope.cancel()
 println("RESULT: $checks actual ViewModel checks passed with synthetic platform/repository boundaries; not an APK or Android execution.")
}

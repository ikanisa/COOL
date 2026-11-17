package rw.ikanisa.burimunsi

import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.test.platform.app.InstrumentationRegistry
import android.graphics.Bitmap
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.cool.mobile.BuildConfig
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.core.export.ExportFormat
import rw.ikanisa.burimunsi.ui.*

/** Original handoff routes/panels exercised with synthetic records only.
 * These tests prove UI action wiring; server/device authorization is separately tested. */
@RunWith(AndroidJUnit4::class)
class NativeUiContractTest {
    @get:Rule val ui=createComposeRule()
    private fun show(c:FakeController,onPermissions:()->Unit={},onSupport:()->Unit={},onPhoneSettings:()->Unit={},onExport:(ExportFormat)->Unit={},onNotifications:()->Unit={},onBattery:()->Unit={}){ui.setContent{BuriContent(languageTag="en",reduceMotion=true){BuriApp(model=c,onSupport=onSupport,onPermissions=onPermissions,onExport=onExport,onPhoneSettings=onPhoneSettings,onNotifications=onNotifications,onBatteryOptimization=onBattery)}}}
    private fun button(label:String)=ui.onNode(hasText(label) and hasClickAction())
    private fun headerAction(label:String)=ui.onNode(hasContentDescription(label) and hasClickAction() and !hasAnyAncestor(hasScrollAction()))
    private fun panelButton(title:String,label:String)=ui.onNode(hasText(label) and hasClickAction() and hasAnyAncestor(
        SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.PaneTitle,title)))
    private fun panelList(title:String)=ui.onNode(hasScrollToIndexAction() and hasAnyAncestor(
        SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.PaneTitle,title)))
    private fun field(label:String)=ui.onNodeWithContentDescription(label)
    private fun assertReceiverControlsAbsent(c:FakeController){
        ui.onNodeWithContentDescription("Gateway status",substring=true).assertDoesNotExist()
        ui.onNodeWithContentDescription("Original SMS").assertDoesNotExist()
        for(label in listOf("Gateway","Pair receiver","Pair phone","Sync","Phone replacement","Replace phone","Replace receiver"))ui.onAllNodesWithText(label).assertCountEquals(0)
        ui.runOnIdle{check(!c.allows(Capability.SMS)&&!c.allows(Capability.GATEWAY));check(c.rawCalls==0&&c.pairCalls==0&&c.syncCalls==0&&c.replaceCalls==0)}
    }
    private fun captureOriginalEmptySignIn(){
        val image=ui.onRoot().captureToImage().asAndroidBitmap()
        InstrumentationRegistry.getInstrumentation().targetContext.cacheDir.resolve("prototype-sign-in.png").outputStream().use{
            check(image.compress(Bitmap.CompressFormat.PNG,100,it))
        }
    }

    @Test fun freshEntryIsOriginalPhoneAndFourDigitPasscode(){
        val c=FakeController(Route.LOGIN);show(c)
        ui.onNodeWithText("Welcome\nback.").assertExists()
        captureOriginalEmptySignIn()
        field("Phone number").performScrollTo().assertExists()
        field("Passcode").performScrollTo().assertExists()
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Sign in") and hasClickAction())
        button("Sign in").assertIsNotEnabled()
        for(extra in listOf("Setup code","Phone setup details","Email","Email code","Use another Collect account","Language"))ui.onNodeWithText(extra).assertDoesNotExist()
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasContentDescription("Phone number"))
        field("Phone number").performTextInput("0780000001")
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasContentDescription("Passcode"))
        field("Passcode").performTextInput("246")
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Sign in") and hasClickAction())
        button("Sign in").assertIsNotEnabled()
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasContentDescription("Passcode"))
        field("Passcode").performTextInput("8")
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Sign in") and hasClickAction())
        button("Sign in").performClick()
        ui.runOnIdle{check(c.loginCalls==1&&c.lastPhone=="0780000001"&&c.lastPin=="2468")}
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasContentDescription("Passcode"))
        field("Passcode").assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.EditableText,androidx.compose.ui.text.AnnotatedString("")))
    }
    @Test fun startupShowsBlackBrandedSplashBeforeOriginalLogin(){
        val c=FakeController(Route.LOGIN);c.state=c.state.copy(starting=true,busy=true);show(c)
        ui.onNodeWithTag("burimunsi-splash").assertIsDisplayed()
        ui.onNodeWithContentDescription("BuriMunsi").assertIsDisplayed()
        ui.onNodeWithText("Welcome\nback.").assertDoesNotExist()
        ui.onNodeWithContentDescription("Phone number").assertDoesNotExist()
        val bitmap=ui.onRoot().captureToImage().asAndroidBitmap()
        check(bitmap.getPixel(2,2)==android.graphics.Color.BLACK)
        ui.runOnIdle{c.state=c.state.copy(starting=false,busy=false)}
        ui.onNodeWithTag("burimunsi-splash").assertDoesNotExist()
        ui.onNodeWithText("Welcome\nback.").assertExists()
    }
    @Test fun syncPolicySettingsStayInTheReceiverAdminRole(){
        val c=FakeController(Route.SETTINGS);var notificationRequests=0;var batteryRequests=0
        show(c,onNotifications={notificationRequests++},onBattery={batteryRequests++})
        if(BuildConfig.IS_GATEWAY){
            button("Sync notifications").performScrollTo().assertIsEnabled().performClick()
            button("Battery optimization").performScrollTo().assertIsEnabled().performClick()
            ui.runOnIdle{check(notificationRequests==1&&batteryRequests==1)
                c.state=c.state.copy(operator=c.operator.copy(role=Role.STAFF,capabilities=setOf(Capability.READ.key)))}
        }
        ui.onNodeWithText("Sync notifications").assertDoesNotExist()
        ui.onNodeWithText("Battery optimization").assertDoesNotExist()
        ui.onNodeWithText("Background sync").assertDoesNotExist()
    }
    @Test fun phoneNextAndPasscodeDoneSubmitOnce(){
        val c=FakeController(Route.LOGIN);show(c)
        field("Phone number").performScrollTo().performTextInput("0780000001");field("Phone number").performImeAction()
        field("Passcode").assertIsFocused().performTextInput("2468");field("Passcode").performImeAction()
        ui.runOnIdle{check(c.loginCalls==1)}
    }
    @Test fun invalidPhoneNeverEnablesSignIn(){
        val c=FakeController(Route.LOGIN);show(c);field("Phone number").performScrollTo().performTextInput("abc");field("Passcode").performTextInput("2468")
        field("Passcode").performImeAction()
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Sign in") and hasClickAction())
        button("Sign in").assertIsNotEnabled();ui.runOnIdle{check(c.loginCalls==0)}
    }
    @Test fun smartOnboardingUsesTheExistingAddMemberSheet(){
        val c=FakeController(Route.MEMBERS);c.state=c.state.copy(sheet=Sheet.ENROLL);var picks=0;var captures=0;var photos=0
        ui.setContent{BuriContent(languageTag="en",reduceMotion=true){BuriApp(c,{},{},{},{},onPickMemberFile={picks++},onTakeMemberPhoto={captures++},onPickMemberPhoto={photos++})}}
        ui.onNodeWithText("How would you like to add members?").assertExists()
        val screenshot=ui.onNode(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.PaneTitle,"Add member")).captureToImage().asAndroidBitmap()
        InstrumentationRegistry.getInstrumentation().targetContext.cacheDir.resolve("smart-onboarding-options.png").outputStream().use{
            check(screenshot.compress(Bitmap.CompressFormat.PNG,100,it))
        }
        panelButton("Add member","Add manually").performClick()
        field("MoMo name").assertExists();field("MoMo number").assertExists()
        panelList("Add member").performScrollToNode(hasText("Eligible earlier MoMo payments may be matched and credited automatically after you add this member."))
        ui.onNodeWithText("Eligible earlier MoMo payments may be matched and credited automatically after you add this member.").assertIsDisplayed()
        ui.onNodeWithText("Adding a member does not allocate previous payments.").assertDoesNotExist()
        panelButton("Add member","Save member").assertIsNotEnabled()
        ui.runOnIdle{c.onboardingOptions()}
        panelList("Add member").performScrollToNode(hasText("Take a photo of the list"))
        ui.onNodeWithText("Taking a photo sends it to OpenAI for extraction. Review members before saving.").assertIsDisplayed()
        panelButton("Add member","Take a photo of the list").performClick()
        ui.runOnIdle{check(captures==1&&c.state.onboarding.step==SmartOnboardingStep.IMPORT&&c.state.onboarding.photoCaptureFlow)}
        ui.onNodeWithText("Import member list").assertDoesNotExist()
        ui.onNodeWithText("Choose a file").assertDoesNotExist()
        ui.runOnIdle{c.state=c.state.copy(onboarding=c.state.onboarding.copy(
            documentUri="content://synthetic/member-photo",documentSelected=true,ocrConsent=true,photoPreviewPending=false),error=null,busy=false)}
        panelButton("Add member","Retry").assertIsEnabled()
        ui.runOnIdle{c.state=c.state.copy(onboarding=c.state.onboarding.copy(sourceKind="image",documentUri=null,
            documentSelected=false,rows=listOf(SmartImportRow(1,"Example Member","+250780000001","ready"))))}
        ui.onNodeWithText("Example Member").assertExists()
        ui.onNodeWithText("Choose a photo").assertDoesNotExist()
        ui.onNodeWithText("Choose a file").assertDoesNotExist()
        ui.runOnIdle{c.onboardingOptions()}
        panelList("Add member").performScrollToNode(hasText("Choose a photo"))
        panelButton("Add member","Choose a photo").performClick()
        ui.runOnIdle{check(photos==1);c.state=c.state.copy(onboarding=c.state.onboarding.copy(
            documentUri="content://synthetic/member-photo",documentMimeType="image/jpeg",documentSelected=true))}
        panelList("Add member").performScrollToNode(hasText("Preview members"))
        panelButton("Add member","Preview members").assertIsNotEnabled()
        ui.onNodeWithText("I agree to send this document to OpenAI for text extraction").performScrollTo().performClick()
        panelButton("Add member","Preview members").performScrollTo().assertIsEnabled()
        ui.runOnIdle{c.onboardingOptions()}
        panelList("Add member").performScrollToNode(hasText("Import member list"))
        panelButton("Add member","Import member list").performClick()
        ui.runOnIdle{check(picks==1&&c.state.onboarding.step==SmartOnboardingStep.IMPORT)}
        panelList("Add member").performScrollToNode(hasText("Choose a file"))
        ui.onNodeWithText("Choose a file").assertExists()
        ui.onNodeWithText("Choose a file, review the extracted rows and register only verified members.").assertDoesNotExist()
        ui.onNodeWithText("CSV is available. Image, PDF and spreadsheet import require the document service.").assertDoesNotExist()
        panelList("Add member").performScrollToNode(hasText("Suggested from transaction payments"))
        panelButton("Add member","Suggested from transaction payments").performClick()
        ui.onNodeWithText("Suggested members").assertExists()
        ui.runOnIdle{c.onboardingImport()}
        panelList("Add member").performScrollToNode(hasText("Add manually"))
        panelButton("Add member","Add manually").performClick()
        field("MoMo name").assertExists()
        ui.runOnIdle{c.onboardingImport()}
        panelList("Add member").performScrollToNode(hasText("Take a photo of the list"))
        ui.onNodeWithText("Taking a photo sends it to OpenAI for extraction. Review members before saving.").assertIsDisplayed()
        panelButton("Add member","Take a photo of the list").performClick()
        ui.runOnIdle{check(captures==2&&c.state.onboarding.photoCaptureFlow)}
        ui.runOnIdle{c.state=c.state.copy(onboarding=SmartOnboardingState(step=SmartOnboardingStep.IMPORT,sourceKind="csv",
            rows=listOf(SmartImportRow(1,"Reviewed Member","+250780000001","ready",verifiedOwnership=true,acceptedTerms=true,consentRecorded=true))))}
        ui.onNodeWithText("Suggested from transaction payments").assertDoesNotExist()
        ui.onNodeWithText("Add manually").assertDoesNotExist()
        ui.onNodeWithText("Take a photo of the list").assertDoesNotExist()
    }
    @Test fun smartOnboardingHasKinyarwandaCopy(){
        val c=FakeController(Route.MEMBERS);c.state=c.state.copy(sheet=Sheet.ENROLL)
        ui.setContent{BuriContent(languageTag="rw",reduceMotion=true){BuriApp(c,{},{},{},{})}}
        ui.onNodeWithText("Ni gute wifuza kongeramo abanyamuryango?").assertExists()
        for(label in listOf("Injiza urutonde rw’abanyamuryango","Fata ifoto y’urutonde","Hitamo ifoto")){
            panelList("Andika umunyamuryango").performScrollToNode(hasText(label));ui.onNodeWithText(label).assertExists()
        }
        ui.runOnIdle{c.onboardingManual()}
        ui.onNodeWithText("Nyuma yo kongeramo uyu munyamuryango, ubwishyu bwa MoMo bwabanje bujuje ibisabwa bushobora guhuzwa na we maze imisanzu ye ikandikwa mu buryo bwikora.").performScrollTo().assertIsDisplayed()
    }
    @Test fun privacyGateDisposesCredentialsAndRecordsWithinOriginalRoute(){
        val c=FakeController(Route.LOGIN);show(c);field("Passcode").performScrollTo().performTextInput("2468")
        ui.runOnIdle{c.screenGate=ScreenGate.BACKGROUND};field("Passcode").assertDoesNotExist()
        ui.runOnIdle{c.screenGate=ScreenGate.OPEN};field("Passcode").performScrollTo().assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.EditableText,androidx.compose.ui.text.AnnotatedString("")))
        ui.runOnIdle{c.state=c.state.copy(operator=c.operator,route=Route.PAYMENTS);c.screenGate=ScreenGate.CHECKING}
        ui.onNodeWithContentDescription("10,000 RWF").assertDoesNotExist()
        ui.onNodeWithContentDescription("Payments").assertIsSelected()
    }
    @Test fun bottomNavigationCoversEverySignedInRouteAndMapsDetailSelection(){
        val c=FakeController(Route.HOME);show(c)
        val expected=mapOf(Route.HOME to "Home",Route.PAYMENTS to "Payments",Route.PAYMENT to "Payments",Route.MEMBERS to "Members",Route.MEMBER to "Members",Route.SMS to "Home",Route.SETTINGS to "Settings")
        for((route,selected)in expected){
            if(route==Route.SMS&&!BuildConfig.IS_GATEWAY)continue
            ui.runOnIdle{c.state=c.state.copy(route=route)}
            for(label in listOf("Home","Payments","Members","Settings"))ui.onNodeWithContentDescription(label).assertExists()
            ui.onNodeWithContentDescription(selected).assertIsSelected().assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.Role,androidx.compose.ui.semantics.Role.Tab))
        }
    }
    @Test fun originalHeadersExposeFiltersProfileHistoryAndExport(){
        val c=FakeController(Route.PAYMENTS);var exports=0;show(c,onExport={exports++})
        ui.onNodeWithContentDescription("Payment filters").performClick();ui.runOnIdle{check(c.state.sheet==Sheet.FILTERS)}
        ui.onNodeWithTag("panel-close").performClick();ui.onNodeWithContentDescription("Your profile").performClick();ui.runOnIdle{check(c.state.sheet==Sheet.PROFILE)}
        ui.runOnIdle{c.state=c.state.copy(sheet=null,route=Route.PAYMENT)}
        headerAction("Contribution history").assertIsDisplayed().performClick();ui.runOnIdle{check(c.state.sheet==Sheet.HISTORY)}
        ui.runOnIdle{c.state=c.state.copy(sheet=null,route=Route.MEMBER)}
        headerAction("Download transactions").performClick();ui.runOnIdle{check(exports==0)}
        ui.onNodeWithTag("export-format:XLSX").performClick();ui.runOnIdle{check(exports==1)}
    }
    @Test fun originalFiltersIncludeProcessingAndApplyOnlyTheSelectedStatus(){
        val c=FakeController(Route.PAYMENTS);show(c);ui.onNodeWithContentDescription("Payment filters").performClick()
        ui.onNodeWithText("Filters").assertExists();ui.onNodeWithText("Status").assertExists();ui.onNodeWithTag("payment-filter-select").performClick()
        ui.onNodeWithText("Processing").performClick();ui.runOnIdle{check(c.filterCalls==0)}
        val applyBounds=button("Apply").fetchSemanticsNode().boundsInRoot
        val resetBounds=button("Reset all").fetchSemanticsNode().boundsInRoot
        check(applyBounds.bottom<=resetBounds.top){"Filter Apply and Reset must have separate hit areas"}
        button("Apply").performClick();ui.runOnIdle{check(c.filterCalls==1&&c.state.filter=="processing"&&c.state.sheet==null){"Expected processing applied once; actual sheet=${c.state.sheet}, filter=${c.state.filter}, applies=${c.filterCalls}"}}
    }
    @Test fun overviewKeepsAuthoritativeUnallocatedAmountAndAllPaymentsAction(){
        val c=FakeController(Route.HOME);c.state=c.state.copy(home=c.state.home!!.copy(unallocatedCount=1,unallocatedAmountRwf=3000));show(c)
        val list=ui.onNode(hasScrollToIndexAction())
        list.performScrollToNode(hasText("1 unallocated"))
        ui.onNodeWithText("1 unallocated").assertExists();ui.onNodeWithText("RWF 3,000").assertExists()
        list.performScrollToNode(hasContentDescription("All payments"))
        val allPayments=ui.onNodeWithContentDescription("All payments").performScrollTo().assertIsDisplayed()
        val actionBounds=allPayments.fetchSemanticsNode().boundsInRoot
        val navBounds=ui.onNodeWithContentDescription("Settings").fetchSemanticsNode().boundsInRoot
        check(actionBounds.bottom<=navBounds.top){"All payments is covered by Settings: action=$actionBounds; settings=$navBounds"}
        allPayments.performClick()
        ui.runOnIdle{check(c.state.route==Route.PAYMENTS){"All payments opened ${c.state.route}"}}
    }
    @Test fun searchIsLiveAndHasNoAddedSubmitControl(){
        val c=FakeController(Route.PAYMENTS);show(c);ui.onNodeWithText("Search").performTextInput("Example")
        ui.mainClock.advanceTimeBy(350);ui.waitForIdle();ui.runOnIdle{check(c.state.search=="Example"&&c.searchCalls==1)}
        ui.onNodeWithText("Load more").assertDoesNotExist()
    }
    @Test fun profileToPasscodeReplacesSheetAndCloseReturnsToRoute(){
        val c=FakeController(Route.SETTINGS);show(c)
        ui.runOnIdle{c.openSheet(Sheet.PROFILE)};panelButton("Profile","Change passcode").assertIsDisplayed().performClick();ui.runOnIdle{check(c.state.sheet==Sheet.PIN)}
        ui.onNodeWithContentDescription("Back to previous panel").assertDoesNotExist();ui.onNodeWithTag("panel-close").performClick()
        ui.runOnIdle{check(c.state.sheet==null&&c.state.route==Route.SETTINGS)}
    }
    @Test fun passcodeConfirmationImeDoesNotChangeCredentialUntilSave(){
        val c=FakeController(Route.HOME);c.state=c.state.copy(sheet=Sheet.PIN);show(c)
        field("Current passcode").performScrollTo().performTextInput("2468");field("New passcode").performScrollTo().performTextInput("8642");field("Confirm passcode").performScrollTo().performTextInput("8642");field("Confirm passcode").performImeAction()
        ui.runOnIdle{check(c.pinChangeCalls==0)};button("Save").performClick();ui.runOnIdle{check(c.pinChangeCalls==1)}
    }
    @Test fun rawReceiptOpensDirectlyAndLinksToItsContribution(){
        val c=FakeController(Route.PAYMENT);show(c)
        if(BuildConfig.IS_GATEWAY){
            ui.onNodeWithTag("payment-details-scroll").performScrollToNode(hasContentDescription("Original SMS"))
            ui.onNodeWithContentDescription("Original SMS").performClick()
            ui.onNodeWithText(c.receiptBody).performScrollTo().assertExists();ui.onNodeWithText("Review reason").assertDoesNotExist();ui.onNodeWithText("Reveal original SMS").assertDoesNotExist()
            panelButton("M-Money","Open contribution").performClick();ui.runOnIdle{check(c.state.route==Route.PAYMENT&&c.lastNavigationId=="tx-1"&&c.rawCalls==1)}
        }else{
            assertReceiverControlsAbsent(c)
            ui.onNodeWithText(c.receiptBody).assertDoesNotExist()
            ui.onNodeWithTag("payment-details-scroll").performScrollToNode(hasContentDescription("Member ledger"))
            ui.onNodeWithContentDescription("Member ledger").assertExists()
            headerAction("Contribution history").assertIsDisplayed()
        }
    }
    @Test fun backgroundPrivacyNeverExposesRawReceipt(){
        val c=FakeController(Route.PAYMENT)
        if(BuildConfig.IS_GATEWAY)c.openSheet(Sheet.RAW,"sms-1")
        show(c)
        if(BuildConfig.IS_GATEWAY){
            ui.onNodeWithText(c.receiptBody).assertExists();ui.runOnIdle{c.screenGate=ScreenGate.BACKGROUND};ui.onNodeWithText(c.receiptBody).assertDoesNotExist()
        }else{
            assertReceiverControlsAbsent(c);ui.onNodeWithContentDescription("10,000 RWF").assertExists()
            ui.runOnIdle{c.screenGate=ScreenGate.BACKGROUND}
            ui.onNodeWithContentDescription("10,000 RWF").assertDoesNotExist();ui.onNodeWithText(c.receiptBody).assertDoesNotExist()
            ui.runOnIdle{c.screenGate=ScreenGate.OPEN}
            ui.onNodeWithContentDescription("10,000 RWF").assertExists();assertReceiverControlsAbsent(c)
        }
    }
    @Test fun allOriginalFifteenPanelTitlesRemainReachable(){
        val c=FakeController(Route.HOME);show(c)
        val titles=mapOf(Sheet.PROFILE to "Profile",Sheet.PIN to "Change passcode",Sheet.HELP to "Help",Sheet.ALLOCATE to "Allocate",Sheet.ENROLL to "Add member",Sheet.STAFF to "Staff access",Sheet.STAFF_EDIT to "Add staff",Sheet.REMOVE_STAFF to "Remove access?",Sheet.GATEWAY to "Gateway",Sheet.REPLACE_DEVICE to "Replace receiver",Sheet.RAW to "M-Money",Sheet.MEMBER_DETAILS to "Member details",Sheet.HISTORY to "Contribution history",Sheet.AUDIT to "Activity log",Sheet.FILTERS to "Filters")
        check(titles.size==15)
        val receiverPanels=setOf(Sheet.GATEWAY,Sheet.REPLACE_DEVICE,Sheet.RAW)
        val accessible=if(BuildConfig.IS_GATEWAY)titles else titles.filterKeys{it !in receiverPanels}
        check(accessible.size==if(BuildConfig.IS_GATEWAY)15 else 12)
        for((sheet,title)in accessible){ui.runOnIdle{c.openSheet(sheet,if(sheet==Sheet.RAW)"sms-1"else null)};ui.onNode(hasText(title)and SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.Heading,Unit)).assertExists();ui.onNodeWithTag("panel-close").performClick();ui.runOnIdle{check(c.state.sheet==null)}}
        if(!BuildConfig.IS_GATEWAY){ui.runOnIdle{c.state=c.state.copy(route=Route.SETTINGS)};assertReceiverControlsAbsent(c)}
    }
    @Test fun gatewayUsesSmsPermissionWithoutPairingCode(){
        val c=FakeController(Route.HOME);var requests=0
        c.state=c.state.copy(gateway=GatewayStatus(true,true,null,0,null,null,null,"permission_required",observationMode=true),sheet=if(BuildConfig.IS_GATEWAY)Sheet.GATEWAY else null);show(c,onPermissions={requests++})
        if(BuildConfig.IS_GATEWAY){
            ui.onNodeWithText("Gateway").assertExists();field("Pairing code").assertDoesNotExist()
            ui.onNodeWithTag("check:Business SIM inserted").assertDoesNotExist()
            panelButton("Gateway","SMS permission").performClick();ui.runOnIdle{check(requests==1&&c.pairCalls==0)}
        }else{
            assertReceiverControlsAbsent(c);field("Pairing code").assertDoesNotExist()
            ui.runOnIdle{c.state=c.state.copy(route=Route.SETTINGS)};assertReceiverControlsAbsent(c)
        }
    }
    @Test fun homeOmitsGatewayControlForAllRolesAndSettingsKeepsRecovery(){
        val c=FakeController(Route.HOME);val healthy=c.state.gateway!!;show(c)
        fun assertHomeHasNoGatewayControl(){
            ui.onNodeWithContentDescription("Gateway status",substring=true).assertDoesNotExist()
            for(label in listOf("Sync enabled","Sync paused","SMS access required","Notification access required","Sync unconfirmed","Status unavailable"))ui.onNodeWithText(label).assertDoesNotExist()
            ui.onNodeWithContentDescription("Open payments").assertIsDisplayed()
            ui.onNodeWithContentDescription("Open members").assertIsDisplayed()
            ui.runOnIdle{check(c.state.sheet==null)}
        }
        assertHomeHasNoGatewayControl()
        ui.runOnIdle{c.continuousSyncRunning=false};assertHomeHasNoGatewayControl()
        ui.runOnIdle{c.continuousSyncRunning=true;c.continuousSyncProblem="notification_permission_required"};assertHomeHasNoGatewayControl()
        ui.runOnIdle{c.continuousSyncProblem=null;c.state=c.state.copy(gateway=healthy.copy(captureEnabled=false,problem="observation_paused",observationMode=true))};assertHomeHasNoGatewayControl()
        ui.runOnIdle{c.state=c.state.copy(gateway=healthy.copy(problem="permission_required"))};assertHomeHasNoGatewayControl()
        ui.runOnIdle{c.state=c.state.copy(gateway=null)};assertHomeHasNoGatewayControl()
        ui.runOnIdle{c.state=c.state.copy(gateway=healthy)}
        ui.onNodeWithContentDescription("Settings").performClick()
        if(BuildConfig.IS_GATEWAY){
            button("Gateway").performScrollTo().assertIsEnabled().performClick()
            ui.runOnIdle{check(c.state.sheet==Sheet.GATEWAY)}
            ui.onNodeWithTag("panel-close").performClick()
        }else assertReceiverControlsAbsent(c)
        // A stale authorized receiver snapshot must not expose SMS controls to staff.
        ui.runOnIdle{c.state=c.state.copy(route=Route.HOME,operator=c.operator.copy(role=Role.STAFF,capabilities=setOf(Capability.READ.key)),gateway=healthy)}
        assertHomeHasNoGatewayControl();assertReceiverControlsAbsent(c)
        ui.onNodeWithContentDescription("Settings").performClick();assertReceiverControlsAbsent(c)
    }
    @Test fun gatewayObservationsCanSyncAndResumeButCannotPauseWithoutPairing(){
        val c=FakeController(Route.HOME);c.state=c.state.copy(gateway=GatewayStatus(true,true,null,0,null,null,null,null,observationMode=true),sheet=if(BuildConfig.IS_GATEWAY)Sheet.GATEWAY else null);show(c)
        if(BuildConfig.IS_GATEWAY){
            panelList("Gateway").performScrollToNode(hasText("Sync") and hasClickAction());panelButton("Gateway","Sync").performClick();ui.runOnIdle{check(c.syncCalls==1)}
            ui.onNodeWithText("Pause").assertDoesNotExist()
            ui.runOnIdle{c.state=c.state.copy(gateway=c.state.gateway!!.copy(captureEnabled=false,problem="observation_paused"))}
            panelButton("Gateway","Resume").performScrollTo().performClick();ui.runOnIdle{check(c.state.gateway?.captureEnabled==true&&c.pairCalls==0&&c.replaceCalls==0)}
            field("Pairing code").assertDoesNotExist()
        }else{
            assertReceiverControlsAbsent(c)
            ui.runOnIdle{c.state=c.state.copy(route=Route.SETTINGS)};assertReceiverControlsAbsent(c)
        }
    }
    @Test fun pairedReceiverCanRequestMissingSmsPermissionWithoutPausing(){
        val c=FakeController(Route.HOME);var requests=0;c.permissionsRequired=true
        c.state=c.state.copy(gateway=GatewayStatus(true,false,1,0,null,null,null,"permission_required"),sheet=if(BuildConfig.IS_GATEWAY)Sheet.GATEWAY else null)
        show(c,onPermissions={requests++})
        if(BuildConfig.IS_GATEWAY){
            panelList("Gateway").performScrollToNode(hasText("SMS permission") and hasClickAction())
            panelButton("Gateway","SMS permission").assertIsEnabled().performClick()
            ui.onNodeWithText("Pause").assertDoesNotExist();ui.onNodeWithText("Resume").assertDoesNotExist()
            ui.runOnIdle{check(requests==1&&c.state.gateway?.captureEnabled==false)}
        }else assertReceiverControlsAbsent(c)
    }
    @Test fun queuedSmsMetadataShowsQueuedAndIsPermissionGated(){
        if(!BuildConfig.IS_GATEWAY)return
        val c=FakeController(Route.SMS);c.smsAccessGranted=true
        c.state=c.state.copy(filter="queued",messages=null,observations=null,offline=true,
            queuedObservations=listOf(QueuedObservationRow("request-1","SyntheticSender","2026-11-09T00:00:00Z","Synthetic queued preview")))
        show(c)
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasTestTag("queued-observation:request-1"))
        ui.onNodeWithTag("queued-observation:request-1").assertExists().assert(!hasClickAction())
        ui.onNodeWithContentDescription("SyntheticSender").assertExists();ui.onNodeWithText("Synthetic queued preview").assertExists();ui.onNodeWithText("Not verified").assertDoesNotExist()
        ui.onNodeWithText(c.receiptBody).assertDoesNotExist();ui.onNodeWithText("Open contribution").assertDoesNotExist()
        ui.runOnIdle{c.state=c.state.copy(queuedObservations=listOf(QueuedObservationRow("request-2","OtherSender","2026-11-09T00:01:00Z")))}
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasTestTag("queued-observation:request-2"))
        ui.onNodeWithTag("queued-observation:request-1").assertDoesNotExist();ui.onNodeWithTag("queued-observation:request-2").assertExists()
        ui.runOnIdle{c.smsAccessGranted=false}
        ui.onNodeWithTag("queued-observation:request-2").assertDoesNotExist()
        ui.runOnIdle{c.logout()};ui.onNodeWithTag("queued-observation:request-2").assertDoesNotExist()
    }
    @Test fun originalFormPlaceholdersDescribeExpectedInputs(){
        val c=FakeController(Route.HOME);c.state=c.state.copy(sheet=Sheet.ENROLL);show(c)
        panelButton("Add member","Add manually").performClick()
        ui.onNodeWithText("Registered full name",useUnmergedTree=true).assertExists()
        ui.runOnIdle{c.state=c.state.copy(sheet=Sheet.ALLOCATE,sheetId=null)}
        panelList("Allocate").performScrollToNode(hasText("How was the member confirmed?"))
        ui.onNodeWithText("How was the member confirmed?",useUnmergedTree=true).assertExists()
        ui.runOnIdle{c.state=c.state.copy(sheet=Sheet.STAFF_EDIT,sheetId=null,selectedStaff=null,draft=emptyMap())}
        ui.onNodeWithText("Full name",useUnmergedTree=true).assertExists()
        val account=StaffAccount("staff-1","Example Staff","+250780000001",true,1,setOf("records.read"))
        ui.runOnIdle{c.state=c.state.copy(sheetId=account.id,selectedStaff=account,draft=mapOf("name" to account.name,"phone" to account.phone))}
        ui.onNodeWithText("Leave blank to keep current",useUnmergedTree=true).assertExists()
        ui.runOnIdle{c.state=c.state.copy(draft=c.state.draft+("phone" to "+250780000002"))}
        ui.onNodeWithText("Leave blank to keep current",useUnmergedTree=true).assertExists()
        panelButton("Edit staff","Save changes").assertIsEnabled().performClick()
        ui.runOnIdle{check(c.staffSaveCalls==1&&c.lastStaffPhone=="+250780000002"&&c.lastStaffPin.isEmpty())}
        ui.runOnIdle{c.state=c.state.copy(sheetId=null,selectedStaff=null,draft=mapOf("name" to "Example Staff","phone" to "+250780000002"))}
        ui.onNodeWithText("Leave blank for default passcode",useUnmergedTree=true).assertExists()
        panelButton("Add staff","Create staff").assertIsEnabled().performClick()
        ui.runOnIdle{check(c.staffSaveCalls==2&&c.lastStaffPin.isEmpty())}
        field("Passcode").performScrollTo().performTextInput("12")
        panelButton("Add staff","Create staff").assertIsNotEnabled()
        field("Passcode").performTextInput("34")
        panelButton("Add staff","Create staff").assertIsEnabled()
    }
    @Test fun staffViewsHaveNoInventedPreferencesOrAdminGatewayControls(){
        val c=FakeController(Route.SETTINGS,Role.STAFF);show(c)
        for(extra in listOf("Language","Reduce screen motion","Staff access","Gateway","Activity"))ui.onNodeWithText(extra).assertDoesNotExist()
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Change passcode"));ui.onNodeWithText("Change passcode").assertExists()
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Help"));ui.onNodeWithText("Help").assertExists()
        ui.runOnIdle{c.state=c.state.copy(route=Route.HOME)};assertReceiverControlsAbsent(c)
    }
    @Test fun settingsSmsPermissionUsesTheAvailableAndroidAction(){
        val c=FakeController(Route.SETTINGS,Role.ADMIN);var requests=0;var settings=0
        show(c,onPermissions={requests++},onPhoneSettings={settings++})
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("SMS permission") and hasClickAction())
        val row=button("SMS permission")
        if(BuildConfig.IS_GATEWAY){
            row.assertIsEnabled().assert(hasText("Required")).performClick()
            ui.runOnIdle{check(requests==1&&settings==0);c.smsAccessGranted=true}
            row.assertIsEnabled().assert(hasText("Granted")).performClick()
            ui.runOnIdle{check(requests==1&&settings==1);c.state=c.state.copy(operator=c.operator.copy(role=Role.STAFF))}
            row.assertIsNotEnabled().assert(hasText("Unavailable"))
        }else{
            row.assertIsNotEnabled().assert(hasText("Unavailable"))
            ui.runOnIdle{check(requests==0&&settings==0)}
        }
    }
    @Test fun parsedSmsUsesExistingScreensWithoutManualVerification(){
        if(!BuildConfig.IS_GATEWAY)return
        val c=FakeController(Route.SMS);c.smsAccessGranted=true;val source=SmsSourceRef.Observation("synthetic-source")
        c.state=c.state.copy(messages=null,observations=Page(listOf(ObservationListRow(source,"synthetic-group","2026-11-09T00:00:00Z")),null,1,"v1","2026-11-09T00:00:00Z"),
            observationProcessing=mapOf(source to ObservationProcessing("parsed",false)))
        show(c);ui.onNodeWithText("Parsed").assertExists();ui.onNodeWithText("Not verified").assertDoesNotExist()
        ui.onNodeWithText("SMS receipt · Unavailable").assertExists()
        ui.runOnIdle{c.state=c.state.copy(gateway=c.state.gateway!!.copy(approvedSenders=listOf("Example provider")))}
        ui.onNodeWithText("Example provider · Unavailable").assertExists()
        ui.runOnIdle{c.state=c.state.copy(gateway=c.state.gateway!!.copy(approvedSenders=listOf("First provider","Second provider")))}
        ui.onNodeWithText("SMS receipt · Unavailable").assertExists()
        ui.runOnIdle{c.openSms(source)}
        ui.onNodeWithText("This message is unverified and has not been posted to the ledger.").assertDoesNotExist()
        ui.onNodeWithText("Reference shown in SMS").assertExists()
        panelButton("M-Money","Open contribution").assertDoesNotExist()
        ui.runOnIdle{c.state=c.state.copy(raw=c.state.raw!!.copy(sender="Example provider"))}
        ui.onNode(hasText("Example provider") and SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.Heading,Unit)).assertExists()
        ui.runOnIdle{c.state=c.state.copy(raw=c.state.raw!!.copy(sender=""))}
        ui.onNode(hasText("SMS receipt") and SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.Heading,Unit)).assertExists()
    }
    @Test fun auditedSmsPreviewsSearchBothTypedStreamsAndMarkPartial(){
        if(!BuildConfig.IS_GATEWAY)return
        val c=FakeController(Route.SMS);c.smsAccessGranted=true;val canonical=SmsSourceRef.Canonical("source-1");val observed=SmsSourceRef.Observation("source-1")
        c.state=c.state.copy(messages=Page(listOf(SmsRow(canonical.id,"","2026-11-09T08:00:00Z","","synced",null)),null,1,"c-v1","2026-11-09T08:00:00Z"),
            observations=Page(listOf(ObservationListRow(observed,"synthetic-group","2026-11-09T08:00:00Z")),"next",2,"o-v1","2026-11-09T08:00:00Z"),
            queuedObservations=emptyList(),
            smsListContent=mapOf(canonical to SmsListContent("Canonical sender","ordinary body"),observed to SmsListContent("Observation sender","A".repeat(220)+"needle")))
        show(c)
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasContentDescription("Canonical sender"))
        ui.onNodeWithContentDescription("Canonical sender").assertExists()
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasContentDescription("Observation sender"))
        ui.onNodeWithContentDescription("Observation sender").assertExists()
        ui.runOnIdle{c.state=c.state.copy(smsListSearch="needle")}
        ui.onNodeWithContentDescription("Canonical sender").assertDoesNotExist()
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasContentDescription("Observation sender"))
        ui.onNodeWithContentDescription("Observation sender").assertExists()
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Search incomplete for this account and phone."))
        ui.onNodeWithText("Search incomplete for this account and phone.").assertExists()
        ui.runOnIdle{c.state=c.state.copy(smsListSearch="no-match")}
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Search incomplete for this account and phone."))
        ui.onNodeWithText("Search incomplete for this account and phone.").assertExists()
        ui.onNodeWithText("No matching messages on this account and phone.").assertDoesNotExist()
        ui.runOnIdle{c.state=c.state.copy(observations=c.state.observations!!.copy(nextCursor=null,totalCount=1))}
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("No matching messages on this account and phone."))
        ui.onNodeWithText("No matching messages on this account and phone.").assertExists()
        val capped=(0 until 98).associate{SmsSourceRef.Observation("other-$it") as SmsSourceRef to SmsListContent("Sender","body")}+
            mapOf(canonical to SmsListContent("Canonical sender","body"),observed to SmsListContent("Observation sender","body"))
        ui.runOnIdle{c.moreCalls=0;c.moreObservationCalls=0;c.state=c.state.copy(smsListSearch="",smsListContent=capped,
            observations=c.state.observations!!.copy(nextCursor="next",totalCount=2))}
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Messages incomplete for this account and phone."))
        ui.onNodeWithText("Messages incomplete for this account and phone.").assertExists()
        ui.mainClock.advanceTimeBy(350);ui.waitForIdle();ui.runOnIdle{check(c.moreCalls==0&&c.moreObservationCalls==0)}
    }
    @Test fun allSmsIncludesOwnQueuedRowsWithoutMergingUncertainSources(){
        if(!BuildConfig.IS_GATEWAY)return
        val c=FakeController(Route.SMS);c.smsAccessGranted=true
        val source=SmsSourceRef.Observation("same-id")
        c.state=c.state.copy(messages=Page(emptyList(),null,0,"c-v1","2026-11-09T08:00:00Z"),
            observations=Page(listOf(ObservationListRow(source,"synthetic-group","2026-11-09T08:00:00Z")),null,1,"o-v1","2026-11-09T08:00:00Z"),
            queuedObservations=listOf(QueuedObservationRow("same-id","Local sender","2026-11-09T08:00:00Z","Local preview")),
            smsListContent=mapOf(source to SmsListContent("Remote sender","Remote preview")))
        show(c)
        ui.onNodeWithText("Unavailable").assertExists() // Two sources may describe one SMS after a lost acknowledgement.
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasTestTag("queued-observation:same-id"))
        ui.onNodeWithTag("queued-observation:same-id").assertExists().assert(!hasClickAction())
        ui.onNodeWithContentDescription("Local sender").assertExists()
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasContentDescription("Remote sender"))
        ui.onNodeWithContentDescription("Remote sender").assertExists()
        ui.onNodeWithText("Not verified").assertDoesNotExist();ui.onNodeWithText("Status unavailable").assertExists()
        ui.onNodeWithText("Parsed").assertDoesNotExist()
        ui.runOnIdle{c.smsAccessGranted=false};ui.onNodeWithTag("queued-observation:same-id").assertDoesNotExist()
        ui.onNodeWithContentDescription("Remote sender").assertDoesNotExist();ui.onNodeWithText("Remote preview").assertDoesNotExist()
        ui.runOnIdle{c.state=c.state.copy(smsListSearch="Remote preview")}
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Search incomplete for this account and phone."))
        ui.onNodeWithText("Search incomplete for this account and phone.").assertExists()
        ui.runOnIdle{c.smsAccessGranted=true;c.state=c.state.copy(operator=c.operator.copy(role=Role.STAFF))}
        ui.onNodeWithTag("queued-observation:same-id").assertDoesNotExist()
    }
    @Test fun observationStatusAndRetryReflectAdminProcessingAuthority(){
        if(!BuildConfig.IS_GATEWAY)return
        val c=FakeController(Route.SMS);c.smsAccessGranted=true
        val source=SmsSourceRef.Observation("synthetic-source")
        c.state=c.state.copy(messages=null,queuedObservations=emptyList(),
            observations=Page(listOf(ObservationListRow(source,"synthetic-group","2026-11-09T00:00:00Z")),null,1,"v1","2026-11-09T00:00:00Z"))
        show(c)
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Status unavailable"))
        ui.onNodeWithText("Status unavailable").assertExists();ui.onNodeWithText("Parsed").assertDoesNotExist()
        for((status,label) in listOf("pending" to "Pending","parsed" to "Parsed","retrying" to "Retrying","needs_review" to "Needs review")){
            ui.runOnIdle{c.state=c.state.copy(observationProcessing=mapOf(source to ObservationProcessing(status,status=="needs_review")))}
            ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText(label));ui.onNodeWithText(label).assertExists()
        }
        ui.runOnIdle{c.openSms(source)}
        panelList("M-Money").performScrollToNode(hasText("This status does not confirm a payment."))
        ui.onNodeWithText("This status does not confirm a payment.").assertExists()
        panelButton("M-Money","Retry").assertIsEnabled().performClick()
        ui.runOnIdle{check(c.observationRetryCalls==1)}
        ui.onNodeWithText("Retry scheduled.").assertExists();panelButton("M-Money","Retry").assertDoesNotExist()
        ui.runOnIdle{c.closeSheet();c.state=c.state.copy(operator=c.operator.copy(role=Role.STAFF,capabilities=setOf(Capability.READ.key)));c.openSms(source)}
        ui.runOnIdle{check(c.state.sheet==null&&c.deniedSheetRequests==1&&c.observationRetryCalls==1)}
    }
    @Test fun allSmsDoesNotClaimEmptyWhileTheLocalQueueIsUnknown(){
        if(!BuildConfig.IS_GATEWAY)return
        val c=FakeController(Route.SMS)
        c.state=c.state.copy(messages=Page(emptyList(),null,0,"c-v1","2026-11-09T08:00:00Z"),
            observations=Page(emptyList(),null,0,"o-v1","2026-11-09T08:00:00Z"),queuedObservations=null)
        show(c)
        ui.onNodeWithText("No messages").assertDoesNotExist();ui.onNodeWithText("SMS sync unavailable.").assertExists()
        ui.onNodeWithText("Unavailable").assertExists()
        ui.runOnIdle{c.smsAccessGranted=true;c.state=c.state.copy(queuedUnavailable=true)}
        ui.onNodeWithText("No messages").assertDoesNotExist();ui.onNodeWithText("SMS sync unavailable.").assertExists()
        ui.runOnIdle{c.state=c.state.copy(queuedUnavailable=false)}
        ui.onNodeWithText("No messages").assertDoesNotExist();ui.onNodeWithText("Queue state unavailable").assertExists()
    }
    @Test fun unknownFinancialOutcomeNeverShowsAllocationAction(){
        val c=FakeController(Route.PAYMENT);c.state=c.state.copy(payment=c.state.payment!!.copy(state="unknown"));show(c)
        ui.onNodeWithText("Status unavailable").assertExists();button("Allocate").assertDoesNotExist()
        ui.runOnIdle{c.state=c.state.copy(payment=c.state.payment!!.copy(state="corrected"))}
        ui.onNodeWithText("Corrected").assertExists()
        ui.onNodeWithText("Amount on original receipt · member credit not confirmed.").assertExists()
        button("Allocate").assertDoesNotExist()
    }
    @Test fun automaticOutgoingTransactionShowsActualFieldsWithoutAllocating(){
        val c=FakeController(Route.PAYMENT)
        c.state=c.state.copy(payment=c.state.payment!!.copy(payerNameRaw="",payerPhoneRaw="",amountRwf=null,ftId=null,
            state="recorded",memberId=null,memberPhone=null,sourceKind="observation",direction="outgoing",outcome="pending",
            feeRwf=25,walletBalanceAfterRwf=1900))
        show(c)
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Direction"))
        ui.onNodeWithText("Outgoing").assertExists();ui.onAllNodesWithText("Pending").onFirst().assertExists()
        ui.onNodeWithText("RWF 25").assertExists();ui.onNodeWithText("RWF 1,900").assertExists()
        ui.onNodeWithText("null").assertDoesNotExist()
        button("Allocate").assertDoesNotExist()
        if(BuildConfig.IS_GATEWAY){
            ui.onNodeWithTag("payment-details-scroll").performScrollToNode(hasContentDescription("Original SMS"))
            ui.onNodeWithContentDescription("Original SMS").performClick()
            ui.runOnIdle{check(c.state.rawSource==SmsSourceRef.Observation("sms-1"))}
        }
    }
    @Test fun allocationActionStaysAboveNavigationAndHonorsAccessAndOfflineState(){
        val c=FakeController(Route.PAYMENT);c.state=c.state.copy(payment=c.state.payment!!.copy(state="unallocated",memberId=null,memberPhone=null));show(c)
        ui.onNodeWithTag("payment-details-scroll").performScrollToIndex(5)
        ui.onNodeWithTag("payment-allocation-fixed").assertIsDisplayed().assertIsEnabled().performClick()
        ui.runOnIdle{check(c.state.sheet==Sheet.ALLOCATE);c.state=c.state.copy(sheet=null,offline=true)}
        ui.onNodeWithTag("payment-allocation-fixed").assertIsDisplayed().assertIsNotEnabled()
        ui.runOnIdle{c.state=c.state.copy(offline=false,operator=c.operator.copy(capabilities=setOf("records.read")))}
        ui.onNodeWithTag("payment-allocation-fixed").assertDoesNotExist()
    }
    @Test fun discardPromptRemainsInTheCurrentSheetAndPreservesDraftUntilConfirmed(){
        val c=FakeController(Route.HOME);c.state=c.state.copy(sheet=Sheet.ENROLL,draft=mapOf("name" to "Example"),draftDirty=true,discardRequested=true);show(c)
        panelButton("Add member","Keep editing").assertIsDisplayed().performClick()
        ui.runOnIdle{check(c.state.sheet==Sheet.ENROLL&&!c.state.discardRequested&&c.state.draft["name"]=="Example");c.state=c.state.copy(discardRequested=true)}
        panelButton("Add member","Discard changes").assertIsDisplayed().performClick()
        ui.runOnIdle{check(c.state.sheet==null&&c.state.draft.isEmpty())}
    }
    @Test fun gatewayShowsOnlyThePairedReceivingCodeSnapshot(){
        if(!BuildConfig.IS_GATEWAY)return
        val c=FakeController(Route.HOME);c.state=c.state.copy(gateway=c.state.gateway!!.copy(pairedReceivingCode="31415"),sheet=Sheet.GATEWAY);show(c)
        ui.onNodeWithText("Paired receiving code").performScrollTo().assertExists()
        ui.onNodeWithText("31415").performScrollTo().assertExists()
    }
    @Test fun supportActionsUseOnlyAnAvailableRuntimeContact(){
        val c=FakeController(Route.SETTINGS);var calls=0;show(c,onSupport={calls++})
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Help") and hasClickAction())
        ui.onNodeWithText("Help").performClick()
        panelButton("Help","WhatsApp").assertIsNotEnabled()
        ui.onNode(hasText("Unavailable") and hasAnyAncestor(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.PaneTitle,"Help"))).assertExists()
        ui.runOnIdle{c.supportPhone="+250780000001"}
        panelButton("Help","WhatsApp").assertIsEnabled().performClick();ui.runOnIdle{check(calls==1)}
        ui.runOnIdle{c.state=UiState();c.supportPhone=null}
        ui.onNodeWithContentDescription("Contact admin on WhatsApp").assertIsNotEnabled()
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Contact admin") and hasClickAction())
        button("Contact admin").assertIsNotEnabled()
    }
    @Test fun twoHundredPercentTypePreservesCompleteMoneyAndAccessibleIdentity(){
        val c=FakeController(Route.PAYMENTS)
        ui.setContent{val d=androidx.compose.ui.platform.LocalDensity.current;androidx.compose.runtime.CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(d.density,2f)){BuriContent(languageTag="en",reduceMotion=true){BuriApp(c,{},{},{},{})}}}
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasContentDescription("10,000 RWF"))
        ui.onNodeWithContentDescription("10,000 RWF").assertExists();ui.onNodeWithContentDescription("EXAMPLE PERSON WITH A VERY LONG FULL NAME",substring=true).assertExists()
        ui.runOnIdle{c.state=c.state.copy(route=Route.MEMBERS,sheet=Sheet.ENROLL);c.onboardingManual()}
        panelList("Add member").performScrollToNode(hasText("Eligible earlier MoMo payments may be matched and credited automatically after you add this member."))
        ui.onNodeWithText("Eligible earlier MoMo payments may be matched and credited automatically after you add this member.").assertIsDisplayed()
        panelButton("Add member","Save member").assertIsDisplayed().assertIsNotEnabled()
    }
    @Test fun exportFormatsDispatchOnlyAfterAnExplicitContextualChoice(){
        val c=FakeController(Route.PAYMENTS);val chosen=mutableListOf<ExportFormat>();show(c,onExport={chosen+=it})
        ui.onNodeWithContentDescription("Export results").performScrollTo().performClick()
        ui.onNodeWithTag("export-format-sheet").assertIsDisplayed();ui.onNodeWithTag("export-format:CSV").assertDoesNotExist()
        ui.onNodeWithTag("export-format:PDF").assertExists();ui.runOnIdle{check(chosen.isEmpty())}
        ui.onNodeWithTag("export-format:XLSX").performScrollTo().performClick();ui.runOnIdle{check(chosen==listOf(ExportFormat.XLSX));c.state=c.state.copy(route=Route.MEMBER)}
        headerAction("Download transactions").performClick()
        ui.onNodeWithText("Excel and PDF use the selected transaction filters. CSV includes the full member ledger.").assertExists()
        ui.onNodeWithTag("export-format:CSV").performScrollTo().performClick()
        ui.runOnIdle{check(chosen==listOf(ExportFormat.XLSX,ExportFormat.CSV))}
    }
    @Test fun refreshAndExportFeedbackNeverReplaceValidRecordsWithFakeSuccess(){
        val c=FakeController(Route.PAYMENTS);c.state=c.state.copy(busy=true);c.operation=UiOperation.REFRESH;show(c)
        ui.onNodeWithTag("active-operation:REFRESH").assertExists()
        ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasContentDescription("10,000 RWF"))
        ui.onNodeWithContentDescription("10,000 RWF").assertExists()
        ui.onNodeWithText("File saved").assertDoesNotExist()
        ui.runOnIdle{c.operation=UiOperation.EXPORT;c.exportFeedback=UiExportFeedback(UiExportPhase.PREPARING,ExportFormat.XLSX,completedRows=5,totalRows=10)}
        ui.onNodeWithText("5 of 10 rows").assertExists();ui.mainClock.advanceTimeBy(1500);ui.onNodeWithText("File saved").assertDoesNotExist()
        ui.runOnIdle{c.exportFeedback=c.exportFeedback!!.copy(phase=UiExportPhase.WRITING)}
        ui.onNodeWithText("Saving file").assertExists();ui.onNodeWithText("File saved").assertDoesNotExist()
        ui.runOnIdle{c.state=c.state.copy(busy=false);c.operation=UiOperation.NONE;c.exportFeedback=c.exportFeedback!!.copy(phase=UiExportPhase.COMPLETE)}
        ui.onNodeWithText("File saved").assertExists()
        ui.runOnIdle{c.openSheet(Sheet.HISTORY);c.state=c.state.copy(busy=true);c.operation=UiOperation.EXPORT;c.exportFeedback=UiExportFeedback(UiExportPhase.PREPARING,ExportFormat.PDF,canCancel=true)}
        panelButton("Contribution history","Cancel export").assertIsDisplayed().performClick();ui.runOnIdle{check(c.cancelExportCalls==1)}
    }
    @Test fun initialLoadingSkeletonDoesNotClaimAnEmptyResult(){
        val c=FakeController(Route.PAYMENTS);c.state=c.state.copy(payments=null,busy=true);c.operation=UiOperation.INITIAL_READ;show(c)
        ui.onNodeWithTag("loading-skeleton").assertExists();ui.onNodeWithText("No payments").assertDoesNotExist()
        ui.runOnIdle{c.operation=UiOperation.NONE;c.state=c.state.copy(busy=false,payments=Page(emptyList(),null,0,"empty","now"))}
        ui.onNodeWithTag("loading-skeleton").assertDoesNotExist();ui.onNodeWithText("No payments").assertExists()
    }
    @Test fun reducedMotionKeepsLoadingMeaningWithStaticRendering(){
        val c=FakeController(Route.PAYMENTS);c.state=c.state.copy(payments=null,busy=true);c.operation=UiOperation.INITIAL_READ;show(c)
        ui.onAllNodes(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.ProgressBarRangeInfo,androidx.compose.ui.semantics.ProgressBarRangeInfo.Indeterminate)).onFirst().assertExists()
        val before=ui.onRoot().captureToImage().asAndroidBitmap();ui.mainClock.advanceTimeBy(2000);ui.waitForIdle()
        check(before.sameAs(ui.onRoot().captureToImage().asAndroidBitmap()))
    }
    @Test fun typedFiltersValidateAmountsAndPreserveInclusiveKigaliDates(){
        val c=FakeController(Route.PAYMENTS)
        c.seedQuery(ListingQuery(fromAt="2026-11-13T22:00:00Z",untilAt="2026-11-14T22:00:00Z",minRwf=0,maxRwf=100))
        c.openSheet(Sheet.FILTERS);show(c)
        panelList("Filters").performScrollToNode(hasContentDescription("Minimum RWF"))
        field("Minimum RWF").performTextClearance();field("Minimum RWF").performTextInput("-1")
        button("Apply").performClick();panelList("Filters").performScrollToNode(hasText("Check the date and amount range."));ui.onNodeWithText("Check the date and amount range.").assertExists();ui.runOnIdle{check(c.filterCalls==0)}
        panelList("Filters").performScrollToNode(hasContentDescription("Minimum RWF"))
        field("Minimum RWF").performTextClearance();field("Minimum RWF").performTextInput("0");button("Apply").performClick()
        ui.runOnIdle{check(c.filterCalls==1&&c.lastAppliedQuery?.fromAt=="2026-11-13T22:00:00Z"&&c.lastAppliedQuery?.untilAt=="2026-11-14T22:00:00Z"&&c.lastAppliedQuery?.minRwf==0L&&c.lastAppliedQuery?.maxRwf==100L&&c.state.sheet==null)}
    }
    @Test fun typedFilterOverlayReturnsToItsPanelAndShowsActualSort(){
        val c=FakeController(Route.PAYMENT);c.openSheet(Sheet.HISTORY);show(c)
        ui.onNodeWithTag("listing-tools:HISTORY").assertExists();ui.onNodeWithText("Sorted by Oldest first").assertExists()
        ui.onNodeWithTag("listing-sort-menu").performClick();ui.onNodeWithText("Newest first").performClick()
        ui.runOnIdle{check(c.state.sheet==Sheet.HISTORY&&c.lastAppliedQuery?.sort==ListingSort.NEWEST)}
        button("Filters").performClick();ui.onNodeWithTag("listing-filter-select").performClick();ui.onNodeWithText("Ledger entry recorded").performClick()
        ui.onNodeWithTag("listing-filter-select").assert(hasText("Ledger entry recorded"));button("Apply").performClick()
        ui.runOnIdle{check(c.state.sheet==Sheet.HISTORY&&c.lastAppliedQuery?.filter=="ledger_entry"){"Expected HISTORY ledger_entry; actual sheet=${c.state.sheet}, query=${c.lastAppliedQuery}, applies=${c.filterCalls}"}}
        for((sheet,target)in listOf(Sheet.STAFF to ListingTarget.STAFF,Sheet.AUDIT to ListingTarget.AUDIT)){
            ui.runOnIdle{c.closeSheet();c.openSheet(sheet)};ui.onNodeWithTag("listing-tools:${target.name}").assertExists()
        }
    }
    @Test fun smsDownloadsStayMetadataOnlyAndRequireClearingBodySearch(){
        val c=FakeController(if(BuildConfig.IS_GATEWAY)Route.SMS else Route.SETTINGS);c.smsAccessGranted=true;show(c)
        if(!BuildConfig.IS_GATEWAY){ui.onNodeWithContentDescription("Export results").assertDoesNotExist();return}
        ui.onNodeWithContentDescription("Export results").performScrollTo().performClick()
        ui.onNodeWithText("SMS exports contain authorized metadata only. Message content is excluded.").assertExists()
        ui.onNodeWithTag("export-format:CSV").assertDoesNotExist();ui.onNodeWithContentDescription("Close").performClick()
        ui.runOnIdle{c.state=c.state.copy(smsListSearch="private search")}
        ui.onNodeWithContentDescription("Export results").assertDoesNotExist()
        ui.onNodeWithText("Clear SMS search to download source metadata. Message text is not included.").assertExists()
        ui.runOnIdle{c.state=c.state.copy(smsListSearch="");c.openSheet(Sheet.FILTERS)}
        ui.onNodeWithContentDescription("Search source or state").assertDoesNotExist();ui.onNodeWithTag("listing-sort-select").assertExists()
    }
    @Test fun paginationFailureRequiresExplicitRetryInsteadOfAnAutomaticLoop(){
        val c=FakeController(Route.PAYMENTS);c.state=c.state.copy(payments=c.state.payments!!.copy(nextCursor="next",totalCount=2),error="Read failed")
        show(c);ui.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Retry loading") and hasClickAction())
        ui.onNodeWithText("Retry loading").assertExists();ui.mainClock.advanceTimeBy(700);ui.runOnIdle{check(c.moreCalls==0)}
        ui.onNodeWithText("Retry loading").performClick();ui.mainClock.advanceTimeBy(700);ui.runOnIdle{check(c.moreCalls==1)}
    }
}
private class FakeController(route:Route,role:Role=Role.ADMIN):BuriController{
    private val snapshotAt=System.currentTimeMillis()
    val operator=Operator("operator-1","EXAMPLE STAFF","+250780000002",role,if(role==Role.ADMIN)Capability.values().map{it.key}.toSet()else setOf("records.read","members.enroll","payments.allocate"),Long.MAX_VALUE)
    val receiptBody="Synthetic M-Money receipt · no live SMS data"
    private val person=Member("member-1","EXAMPLE PERSON WITH A VERY LONG FULL NAME","+250780000001",10000,true,1)
    private val pay=Payment("tx-1",person.name,"*********816",10000,"2026-10-08 15:15:20","90000000001","posted",1,person.id,person.phone,"sms-1")
    override var screenGate by mutableStateOf(ScreenGate.OPEN)
    override var supportPhone:String? by mutableStateOf(null)
    override var notificationAccessGranted:Boolean? by mutableStateOf(null)
    override var continuousSyncRunning:Boolean? by mutableStateOf(true)
    override var continuousSyncProblem:String? by mutableStateOf(null)
    var permissionsRequired by mutableStateOf(false)
    override val receivingPermissionsRequired get()=permissionsRequired
    override var smsAccessGranted by mutableStateOf(false)
    override var operation by mutableStateOf(UiOperation.NONE)
    override var exportFeedback:UiExportFeedback? by mutableStateOf(null)
    var cancelExportCalls=0
    override fun cancelExport(){cancelExportCalls++}
    private var filterOrigin:ListingTarget?=null
    private var filterParent:Sheet?=null
    private val queries=androidx.compose.runtime.mutableStateMapOf<ListingTarget,ListingQuery>()
    var lastAppliedQuery:ListingQuery?=null
    fun seedQuery(query:ListingQuery,target:ListingTarget=listingTarget?:ListingTarget.PAYMENTS){queries[target]=query.validated(target)}
    override val listingTarget:ListingTarget? get()=if(state.sheet==Sheet.FILTERS)filterOrigin else when(state.sheet){
        Sheet.STAFF->ListingTarget.STAFF;Sheet.AUDIT->ListingTarget.AUDIT;Sheet.HISTORY->ListingTarget.HISTORY
        null->when(state.route){Route.PAYMENTS,Route.MEMBER->ListingTarget.PAYMENTS;Route.MEMBERS->ListingTarget.MEMBERS;Route.SMS->if(state.filter=="queued")ListingTarget.OBSERVATIONS else ListingTarget.SMS;else->null}
        else->null
    }
    override val listingQuery get()=listingTarget?.let{queries[it]?:ListingQuery.defaultsFor(it)}?:ListingQuery()
    override val canExportListing get()=listingTarget!=null&&allows(Capability.READ)&&!state.offline&&when(listingTarget){
        ListingTarget.SMS,ListingTarget.OBSERVATIONS->allows(Capability.SMS)&&smsAccessGranted&&state.smsListSearch.isBlank()&&state.queuedSearch.isBlank()
        ListingTarget.STAFF,ListingTarget.AUDIT->allows(Capability.STAFF)
        else->true
    }
    override fun applyListingQuery(query:ListingQuery){
        val target=listingTarget?:return;query.validated(target);lastAppliedQuery=query;queries[target]=query;filterCalls++
        state=state.copy(sheet=if(state.sheet==Sheet.FILTERS)filterParent else state.sheet,
            filter=if(target in setOf(ListingTarget.PAYMENTS,ListingTarget.SMS))query.filter else state.filter,
            search=if(state.route!=Route.SMS)query.q else state.search)
        filterOrigin=null;filterParent=null
    }
    override fun resetListingQuery(){val target=listingTarget?:return;queries[target]=ListingQuery.defaultsFor(target);state=state.copy(search="",filter=if(target in setOf(ListingTarget.PAYMENTS,ListingTarget.SMS))"all"else state.filter)}
    override fun dismissExportFeedback(){exportFeedback=null}
    var retirementUnconfirmed=false;var retirementChecks=0
    var loginCalls=0;var lastPhone="";var lastPin="";var searchCalls=0;var filterCalls=0;var pinChangeCalls=0;var rawCalls=0;var pairCalls=0;var replaceCalls=0;var syncCalls=0;var lastPairCode="";var lastNavigationId:String?=null
    var staffSaveCalls=0;var lastStaffPhone="";var lastStaffPin="";var moreCalls=0;var moreObservationCalls=0;var observationRetryCalls=0
    var deniedSheetRequests=0;var lastSheetRequest:Sheet?=null
    override var state by mutableStateOf(UiState(operator=if(route==Route.LOGIN)null else operator,route=route,savedAt=snapshotAt,panelSavedAt=snapshotAt,historySavedAt=snapshotAt,
        home=Home(10000,10000,1,0,listOf(pay),"2026-11-06T10:00:00Z",0),payments=Page(listOf(pay),null,1,"v1","now"),members=Page(listOf(person),null,1,"v1","now"),member=person,payment=pay,memberTransactions=Page(listOf(pay),null,1,"v1","now"),
        gateway=if(role==Role.ADMIN)GatewayStatus(true,true,1,0,null,"09:42","09:42",null)else null,messages=Page(listOf(SmsRow("sms-1","M-Money",pay.atRaw,"Synthetic preview","synced","tx-1","SIM 1")),null,1,"v1","now"),staff=Page(emptyList(),null,0,"staff-v1","now"),audit=Page(emptyList(),null,0,"audit-v1","now"),history=Page(emptyList(),null,0,"history-v1","now")))
    override fun allows(capability:Capability)=screenGate==ScreenGate.OPEN&&Access.allows(state.operator,capability,System.currentTimeMillis(),BuildConfig.IS_GATEWAY,state.gateway?.authorized==true)
    override fun login(phone:String,pin:String){loginCalls++;lastPhone=phone;lastPin=pin}
    override fun logout(){state=UiState()}
    override fun navigate(route:Route,id:String?){lastNavigationId=id;state=state.copy(route=route,routeId=id,sheet=null)}
    override fun back(){state=state.copy(route=Route.HOME,sheet=null)}
    override fun openUnallocated(){state=state.copy(route=Route.PAYMENTS,filter="unallocated")}
    override fun search(value:String){state=if(state.route==Route.SMS&&state.filter=="queued")state.copy(queuedSearch=value)else if(state.route==Route.SMS)state.copy(smsListSearch=value)else state.copy(search=value)}
    override fun searchSubmit(){searchCalls++}
    override fun setFilter(value:String){filterCalls++;state=state.copy(filter=value,sheet=null);listingTarget?.let{target->if(value in ListingQuery.filters(target))queries[target]=listingQuery.copy(filter=value)}}
    override fun refresh(){}
    override fun more(){moreCalls++}
    override fun moreObservations(){moreObservationCalls++}
    override fun retryObservation(){
        val source=state.rawSource as? SmsSourceRef.Observation?:return
        if(state.sheet!=Sheet.RAW||!smsAccessGranted||!allows(Capability.SMS)||!allows(Capability.GATEWAY)||state.observationProcessing[source]?.canRetry!=true)return
        observationRetryCalls++
        state=state.copy(observationProcessing=state.observationProcessing+(source to ObservationProcessing("retrying",false)),observationRetryNotice="Retry scheduled.")
    }
    override fun openSms(source:SmsSourceRef){
        if(source is SmsSourceRef.Observation&&allows(Capability.SMS))state=state.copy(sheet=Sheet.RAW,sheetId=source.id,rawSource=source,
            raw=RawSms(source.id,"M-Money","2026-11-09T00:00:00Z",receiptBody,null),
            observationHints=ObservationHintSet(1,"partial_inbox_display_only","synthetic-profile","a".repeat(64),Values.sha256(receiptBody),
                listOf(ObservationHint("quoted_reference","Synthetic",0,9))),rawDisclosure=RawDisclosureState.REVEALED)
        else openSheet(Sheet.RAW,source.id)
    }
    override fun openSheet(sheet:Sheet,id:String?){
        lastSheetRequest=sheet
        // Model the real controller boundary; direct fixture calls must not bypass role/profile checks.
        val permitted=when(sheet){
            Sheet.GATEWAY,Sheet.REPLACE_DEVICE->BuildConfig.IS_GATEWAY&&state.operator?.role==Role.ADMIN
            Sheet.RAW->allows(Capability.SMS)
            Sheet.STAFF,Sheet.STAFF_EDIT,Sheet.REMOVE_STAFF,Sheet.AUDIT->allows(Capability.STAFF)
            Sheet.ENROLL->allows(Capability.ENROLL)
            Sheet.ALLOCATE->allows(Capability.ALLOCATE)
            else->state.operator!=null
        }
        if(!permitted){deniedSheetRequests++;return}
        if(sheet==Sheet.FILTERS){filterOrigin=listingTarget?:ListingTarget.PAYMENTS;filterParent=state.sheet}
        state=state.copy(sheet=sheet,sheetId=id,panelDepth=0,draft=emptyMap(),draftDirty=false)
        if(sheet==Sheet.RAW){rawCalls++;state=state.copy(raw=RawSms("sms-1","M-Money",pay.atRaw,receiptBody,"tx-1","SIM 1"),rawDisclosure=RawDisclosureState.REVEALED)}
    }
    override fun closeSheet(){val parent=if(state.sheet==Sheet.FILTERS)filterParent else null;state=state.copy(sheet=parent,sheetId=null,panelDepth=0,draft=emptyMap());filterOrigin=null;filterParent=null}
    override fun keepDraft(){state=state.copy(discardRequested=false)}
    override fun discardDraft(){state=state.copy(sheet=null,sheetId=null,discardRequested=false,draftDirty=false,draft=emptyMap())}
    override fun revealRaw(reason:String){rawCalls++}
    override fun editDraft(key:String,value:String){state=state.copy(draft=state.draft+(key to value),draftDirty=true)}
    override fun selectMember(member:Member){state=state.copy(selectedMember=member)}
    override fun allocationSearch(q:String){}
    override fun allocate(note:String){}
    override fun enroll(name:String,phone:String){}
    override fun onboardingOptions(){state=state.copy(onboarding=SmartOnboardingState())}
    override fun onboardingManual(){state=state.copy(onboarding=SmartOnboardingState(step=SmartOnboardingStep.MEMBER))}
    override fun onboardingSuggestions(query:String,cursor:String?){state=state.copy(onboarding=SmartOnboardingState(step=SmartOnboardingStep.SUGGESTIONS,query=query,suggestionsLoaded=true))}
    override fun onboardingImport(){state=state.copy(onboarding=state.onboarding.copy(step=SmartOnboardingStep.IMPORT))}
    override fun onboardingPhoto(){state=state.copy(onboarding=SmartOnboardingState(step=SmartOnboardingStep.IMPORT,photoCaptureFlow=true))}
    override fun onboardingConsent(field:String,value:Boolean){if(field=="ocr")state=state.copy(onboarding=state.onboarding.copy(ocrConsent=value))}
    override fun changePin(current:String,next:String,confirm:String){pinChangeCalls++}
    override fun saveStaff(name:String,phone:String,pin:String,enroll:Boolean,allocate:Boolean){staffSaveCalls++;lastStaffPhone=phone;lastStaffPin=pin}
    override fun staffAction(action:String,pin:String?){}
    override fun requestRemoveStaff(){openSheet(Sheet.REMOVE_STAFF)}
    override fun setMemberActive(active:Boolean){}
    override fun pair(code:String){pairCalls++;lastPairCode=code;state=state.copy(gateway=state.gateway!!.copy(authorized=true),sheet=Sheet.GATEWAY)}
    override fun replaceReceiver(code:String){
        if(state.receiverRetirementPending)retirementChecks++ else{replaceCalls++;lastPairCode=code}
        if(retirementUnconfirmed){screenGate=ScreenGate.CHECKING;state=state.copy(receiverRetirementPending=true)}
        else{screenGate=ScreenGate.OPEN;state=UiState()}
    }
    override fun syncReceiver(){syncCalls++}
    override fun setPaused(value:Boolean){state=state.copy(gateway=state.gateway!!.copy(captureEnabled=!value))}
    override fun retry(){}
}

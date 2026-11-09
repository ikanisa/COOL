package rw.ikanisa.burimunsi

import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.test.platform.app.InstrumentationRegistry
import android.graphics.Bitmap
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.ui.*

/** Synthetic state only in androidTest. No test account or balance enters main. */
@RunWith(AndroidJUnit4::class)
class NativeUiContractTest {
    @get:Rule val ui=createComposeRule()
    private fun show(controller:FakeController,language:String="en"){ui.setContent{BuriContent(languageTag=language,reduceMotion=true){BuriApp(controller,{},{},{},{})}}}
    @Test fun collectLoginUsesNativeCredentialsAndClearsSubmittedPassword(){
        var submitted=0
        ui.setContent{BuriContent(languageTag="en",reduceMotion=true){CollectSignIn(false,null,{email,password->
            check(email=="operator@example.invalid"&&password=="test-only-password");submitted++
        },{})}}
        ui.onNodeWithText("Email").assertExists()
        val capture=ui.onRoot().captureToImage().asAndroidBitmap()
        InstrumentationRegistry.getInstrumentation().targetContext.cacheDir.resolve("collect-sign-in.png").outputStream().use{
            check(capture.compress(Bitmap.CompressFormat.PNG,100,it))
        }
        ui.onNodeWithText("Email").performTextInput("operator@example.invalid")
        ui.onNodeWithText("Password").performTextInput("test-only-password")
        ui.onNodeWithText("Continue").performScrollTo().performClick()
        ui.runOnIdle{check(submitted==1)}
        ui.onNodeWithText("Password").assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.EditableText,androidx.compose.ui.text.AnnotatedString("")))
        ui.onNodeWithText("Continue").assertIsNotEnabled()
    }
    @Test fun collectLoginDisposalClearsRememberedCredentials(){
        var visible by mutableStateOf(true)
        ui.setContent{BuriContent(languageTag="en",reduceMotion=true){if(visible)CollectSignIn(false,null,{_,_->},{})}}
        ui.onNodeWithText("Email").performTextInput("operator@example.invalid")
        ui.onNodeWithText("Password").performTextInput("test-only-password")
        ui.runOnIdle{visible=false}
        ui.onNodeWithText("Email").assertDoesNotExist()
        ui.runOnIdle{visible=true}
        for(label in listOf("Email","Password"))ui.onNodeWithText(label).assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.EditableText,androidx.compose.ui.text.AnnotatedString("")))
    }
    @Test fun collectLoginDenialProvidesRecoveryWithoutPrivateRecords(){
        var support=0
        ui.setContent{BuriContent(languageTag="en",reduceMotion=true){CollectSignIn(false,"burimunsi_access_denied",{_,_->},{support++})}}
        ui.onNodeWithText("This account is not approved for this phone. Contact admin.").performScrollTo().assertExists()
        ui.onNodeWithText("Contact admin").performScrollTo().performClick()
        ui.runOnIdle{check(support==1)}
        ui.onNodeWithContentDescription("10,000 RWF").assertDoesNotExist()
    }
    @Test fun pausedGuardRemovesRecordSemantics(){
        val c=FakeController(Route.HOME);show(c)
        ui.runOnIdle{c.screenGate=ScreenGate.BACKGROUND}
        ui.onNodeWithText("App paused").assertExists()
        ui.onNodeWithContentDescription("EXAMPLE PERSON WITH A VERY LONG FULL NAME",substring=true).assertDoesNotExist()
        ui.onNodeWithContentDescription("10,000 RWF").assertDoesNotExist()
    }
    @Test fun expiredGuardHasRecoveryAndNoFinancialRows(){
        val c=FakeController(Route.PAYMENT);c.screenGate=ScreenGate.STALE;show(c)
        ui.onNodeWithText("Refresh required").assertExists()
        ui.onNodeWithText("Retry access check").performScrollTo().performClick()
        ui.runOnIdle{check(c.refreshCalls==1)}
        ui.onNodeWithText("90000000001").assertDoesNotExist()
    }
    @Test fun pausingDisposesRememberedCredentialInput(){
        val c=FakeController(Route.LOGIN);show(c)
        ui.onNodeWithText("Passcode").performTextInput("2468")
        ui.runOnIdle{c.screenGate=ScreenGate.BACKGROUND}
        ui.onNodeWithText("Passcode").assertDoesNotExist()
        ui.runOnIdle{c.screenGate=ScreenGate.OPEN}
        ui.onNodeWithText("Passcode").assert(SemanticsMatcher.expectValue(androidx.compose.ui.semantics.SemanticsProperties.EditableText, androidx.compose.ui.text.AnnotatedString("")))
        ui.onNodeWithText("2468").assertDoesNotExist()
    }
    @Test fun homeHasNoRemovedLabelsAndPreservesAccessibleName(){
        val c=FakeController(Route.HOME);show(c)
        ui.onNodeWithText("Automatic").assertDoesNotExist()
        ui.onNodeWithText("RWF · 09:42").assertDoesNotExist()
        ui.onNodeWithContentDescription("EXAMPLE PERSON WITH A VERY LONG FULL NAME",substring=true).assertExists()
        ui.onAllNodesWithContentDescription("Payments").onFirst().performClick()
        ui.runOnIdle{check(c.state.route==Route.PAYMENTS)}
    }
    @Test fun paymentHistoryShowsRecordedEventsWithoutInventingSuccess(){
        val c=FakeController(Route.PAYMENT)
        c.state=c.state.copy(sheet=Sheet.HISTORY,historyPaymentId="tx-1",history=Page(listOf(
            PaymentEvent("transaction:tx-1","tx-1","transaction_recorded","2026-11-08T10:00:00Z",null,null),
            PaymentEvent("ledger:l-1","tx-1","ledger_entry","2026-11-08T10:00:01Z",-10000,"member-1")
        ),null,2,"history-1","2026-11-08T10:00:02Z"))
        show(c)
        ui.onNodeWithText("Recorded events").performScrollTo().assertExists()
        ui.onNodeWithText("Transaction recorded").performScrollTo().assertExists()
        ui.onNodeWithText("Ledger entry recorded").performScrollTo().assertExists()
        ui.onNodeWithText("Refund completed").assertDoesNotExist()
    }
    @Test fun staffHasNoMessagesShortcut(){val c=FakeController(Route.HOME);show(c);ui.onNodeWithContentDescription("Messages").assertDoesNotExist()}
    @Test fun phoneAndFourDigitFieldsHaveStableAccessibleNames(){val c=FakeController(Route.LOGIN);show(c);ui.onNodeWithText("Phone number").assertExists();ui.onNodeWithText("Passcode").assertExists();ui.onNodeWithText("Email or phone").assertDoesNotExist()}
    @Test fun memberLedgerUsesFullPhoneAndSourceReference(){val c=FakeController(Route.MEMBER);show(c);ui.onAllNodesWithText("+250780000001").onFirst().assertExists();ui.onNodeWithText("FT Id: 90000000001").assertExists();ui.onNodeWithText("Brought forward").assertDoesNotExist()}
    @Test fun paymentDetailHasOriginalReferenceAndNoCreditedLabel(){val c=FakeController(Route.PAYMENT);show(c);ui.onNodeWithText("90000000001").assertExists();ui.onNodeWithText("Credited").assertDoesNotExist();ui.onNodeWithText("Allocation").assertDoesNotExist()}
    @Test fun kinyarwandaLabelsDoNotTranslateProviderEvidence(){
        val c=FakeController(Route.PAYMENTS);show(c,"rw")
        ui.onNodeWithText("Ubwishyu").assertExists()
        ui.onNodeWithContentDescription("EXAMPLE PERSON WITH A VERY LONG FULL NAME",substring=true).assertExists()
        ui.onNodeWithText("FT Id: 90000000001").assertExists()
        ui.onNodeWithText("2026-10-08 15:15:20").assertExists()
    }
    @Test fun originalSmsRemainsUnalteredInKinyarwanda(){
        val c=FakeController(Route.PAYMENT)
        val body="M-Money original: 10,000 RWF; FT Id 90000000001. Allocated is provider text."
        c.state=c.state.copy(sheet=Sheet.RAW,sheetId="sms-1",raw=RawSms("sms-1","M-Money","2026-10-08 15:15:20",body,"tx-1"))
        show(c,"rw")
        ui.onNodeWithText("Ubutumwa bwa SMS bw’umwimerere").assertExists()
        ui.onNodeWithText(body).performScrollTo().assertExists()
    }
    @Test fun phoneNextFocusesPasscodeAndDoneSubmitsOnlyOnce(){
        val c=FakeController(Route.LOGIN);show(c)
        ui.onNodeWithText("Phone number").performScrollTo().performTextInput("0780000001")
        ui.onNodeWithText("Phone number").performImeAction()
        ui.onNodeWithText("Passcode").assertIsFocused().performTextInput("2468")
        ui.onNodeWithText("Passcode").performImeAction()
        ui.runOnIdle{check(c.loginCalls==1)}
        ui.onNodeWithText("Passcode").assert(SemanticsMatcher.expectValue(
            androidx.compose.ui.semantics.SemanticsProperties.EditableText,androidx.compose.ui.text.AnnotatedString("")))
    }
    @Test fun invalidPhoneNeverEnablesSignIn(){
        val c=FakeController(Route.LOGIN);show(c)
        ui.onNodeWithText("Phone number").performScrollTo().performTextInput("abc")
        ui.onNodeWithText("Passcode").performScrollTo().performTextInput("2468")
        ui.onNodeWithText("Sign in").performScrollTo().assertIsNotEnabled()
        ui.runOnIdle{check(c.loginCalls==0)}
    }
    @Test fun searchImeSubmitsTheVisibleQuery(){
        val c=FakeController(Route.PAYMENTS);show(c)
        ui.onNodeWithText("Name or FT Id").performTextInput("Example")
        ui.onNodeWithText("Name or FT Id").performImeAction()
        ui.runOnIdle{check(c.searchCalls==1&&c.state.search=="Example")}
    }
    @Test fun confirmingPasscodeImeDoesNotCommitCredentialChange(){
        val c=FakeController(Route.HOME);c.state=c.state.copy(sheet=Sheet.PIN);show(c)
        ui.onNodeWithText("Current passcode").performScrollTo().performTextInput("2468")
        ui.onNodeWithText("New passcode").performScrollTo().performTextInput("8642")
        ui.onNodeWithText("Confirm passcode").performScrollTo().performTextInput("8642")
        ui.onNodeWithText("Confirm passcode").performImeAction()
        ui.runOnIdle{check(c.pinChangeCalls==0)}
        ui.onNodeWithText("Save passcode").performScrollTo().performClick()
        ui.runOnIdle{check(c.pinChangeCalls==1)}
    }
    @Test fun twoHundredPercentTypeKeepsTheFullAmountAccessible(){
        val c=FakeController(Route.PAYMENTS)
        ui.setContent{
            val density=androidx.compose.ui.platform.LocalDensity.current
            androidx.compose.runtime.CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides
                androidx.compose.ui.unit.Density(density.density,2f)){
                BuriContent(languageTag="en",reduceMotion=true){BuriApp(c,{},{},{},{})}
            }
        }
        ui.onNodeWithContentDescription("10,000 RWF").performScrollTo().assertExists()
        ui.onNodeWithContentDescription("EXAMPLE PERSON WITH A VERY LONG FULL NAME",substring=true).assertExists()
    }
    @Test fun bottomNavigationExposesSelectedTab(){
        val c=FakeController(Route.HOME);show(c)
        ui.onNodeWithContentDescription("Home").assertIsSelected().assert(SemanticsMatcher.expectValue(
            androidx.compose.ui.semantics.SemanticsProperties.Role,androidx.compose.ui.semantics.Role.Tab))
    }

}
private class FakeController(route:Route):BuriController{
    // Loaded synthetic snapshots need their own retrieval provenance, just as
    // repository results do. Keep the real presentation/freshness projection.
    private val snapshotAt=System.currentTimeMillis()
    override var screenGate by mutableStateOf(ScreenGate.OPEN)
    var refreshCalls=0
    var loginCalls=0;var searchCalls=0;var pinChangeCalls=0
    private val person=Member("member-1","EXAMPLE PERSON WITH A VERY LONG FULL NAME","+250780000001",10000,true,1)
    private val pay=Payment("tx-1",person.name,"*********816",10000,"2026-10-08 15:15:20","90000000001","posted",1,person.id,person.phone,"sms-1")
    override var state by mutableStateOf(UiState(operator=if(route==Route.LOGIN)null else Operator("operator-1","EXAMPLE STAFF","+250780000002",Role.STAFF,setOf("records.read","members.enroll","payments.allocate"),Long.MAX_VALUE),route=route,
        savedAt=snapshotAt,panelSavedAt=snapshotAt,historySavedAt=snapshotAt,
        home=Home(10000,10000,1,0,listOf(pay),"2026-11-06T10:00:00Z"),payments=Page(listOf(pay),null,1,"v1","now"),members=Page(listOf(person),null,1,"v1","now"),member=person,payment=pay,ledger=Page(listOf(LedgerRow("l-1","tx-1",10000,pay.atRaw,pay.ftId,pay.payerNameRaw)),null,1,"v1","now")))
    override fun allows(c:Capability)=c in setOf(Capability.READ,Capability.ENROLL,Capability.ALLOCATE)
    override fun navigate(route:Route,id:String?){if(route!=Route.SMS)state=state.copy(route=route)}
    override fun login(phone:String,pin:String){loginCalls++}
    override fun logout(){}
    override fun back(){}
    override fun openUnallocated(){}
    override fun search(value:String){state=state.copy(search=value)}
    override fun searchSubmit(){searchCalls++}
    override fun setFilter(value:String){}
    override fun refresh(){refreshCalls++}
    override fun more(){}
    override fun openSheet(sheet:Sheet,id:String?){}
    override fun closeSheet(){}
    override fun selectMember(member:Member){}
    override fun allocationSearch(q:String){}
    override fun allocate(note:String){}
    override fun enroll(name:String,phone:String){}
    override fun changePin(current:String,next:String,confirm:String){pinChangeCalls++}
    override fun saveStaff(name:String,phone:String,pin:String,enroll:Boolean,allocate:Boolean){}
    override fun staffAction(action:String,pin:String?){}
    override fun requestRemoveStaff(){}
    override fun setMemberActive(active:Boolean){}
    override fun pair(code:String){}
    override fun setPaused(value:Boolean){}
    override fun retry(){}
}

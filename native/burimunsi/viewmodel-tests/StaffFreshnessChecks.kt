package rw.ikanisa.burimunsi.stafffreshnesstests
import android.app.Application
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.Fixture
import rw.ikanisa.burimunsi.ui.BuriViewModel
import rw.ikanisa.burimunsi.ui.Sheet

fun main()=runBlocking {
    val model=BuriViewModel(Application())
    suspend fun idle(){withTimeout(10000){while(model.state.busy)delay(2)};delay(10)}
    idle()
    Fixture.staffFailure=ApiFailure("fresh_auth_required",403,false)
    val before=Fixture.staffMutations
    model.saveStaff("Synthetic Staff","0780000002","4682",true,false);idle()
    check(Fixture.staffMutations==before+1&&model.state.pending)
    check(model.state.error=="Check the previous action, then sign in again before adding staff.")
    model.saveStaff("Synthetic Staff","0780000002","4682",true,false);idle()
    check(Fixture.staffMutations==before+1&&model.state.pending)
    Fixture.staffFailure=null;Fixture.outcomeState="cancelled";Fixture.resolveOnCheck=true
    model.retry();idle()
    check(!model.state.pending&&model.state.commandNotice?.contains("cancelled before it was applied")==true)
    check(Fixture.staffMutations==before+1)
    for ((code,status,expected) in listOf(
        Triple("new_passcode_required",400,"Enter a new passcode when changing the phone number."),
        Triple("access_denied",403,"Access unavailable.")
    )) {
        model.openSheet(Sheet.STAFF);idle();model.openSheet(Sheet.STAFF_EDIT,"staff-1");idle()
        Fixture.staffFailure=ApiFailure(code,status,false);Fixture.resolveOnCheck=false
        val attempts=Fixture.staffMutations
        model.saveStaff("Synthetic Staff","0780000003","",true,false);idle()
        check(Fixture.staffMutations==attempts+1&&Fixture.lastStaffBody?.has("pin")==false)
        check(model.state.pending&&model.state.error==expected&&model.state.operator!=null)
        model.saveStaff("Synthetic Staff","0780000003","",true,false);idle()
        check(Fixture.staffMutations==attempts+1)
        Fixture.staffFailure=null;Fixture.outcomeState="cancelled";Fixture.resolveOnCheck=true
        model.retry();idle();check(!model.state.pending)
    }
    model.openSheet(Sheet.STAFF);idle();model.openSheet(Sheet.STAFF_EDIT,"staff-1");idle()
    Fixture.staffFailure=ApiFailure("access_denied",403,false);Fixture.staffAutoOutcome="cancelled"
    model.saveStaff("Synthetic Staff","0780000003","",true,false);idle()
    check(Fixture.lastStaffAutoResolve&&!model.state.pending&&model.state.sheet==Sheet.STAFF_EDIT&&model.state.error=="Access unavailable."&&model.state.operator!=null)
    Fixture.staffAutoOutcome="committed"
    model.saveStaff("Synthetic Staff","0780000003","",true,false);idle()
    check(Fixture.lastStaffAutoResolve&&!model.state.pending&&model.state.sheet==Sheet.STAFF&&model.state.operator!=null)
    Fixture.staffFailure=null;Fixture.staffAutoOutcome=null
    model.viewModelScope.cancel()
    println("PASS staff denials retain unknown outcomes; proven cancellation shows an error and proven commitment succeeds without replay")
}

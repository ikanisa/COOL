package rw.ikanisa.burimunsi.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.ui.semantics.Role as SemanticRole
import kotlinx.coroutines.flow.distinctUntilChanged
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.*
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.*
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.cool.mobile.BuildConfig
import app.cool.mobile.R
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.core.Role
import rw.ikanisa.burimunsi.core.export.ExportFormat
import java.util.Locale

// Keep the scrollable route viewport above the floating navigation bar.
private val BottomNavHeight=68.dp
private val BottomNavBottomGap=18.dp
private val BottomNavClearance=BottomNavHeight+BottomNavBottomGap

private fun money(value:Long,locale:Locale):String=ExactDisplay.amount(value,locale.toLanguageTag()).orEmpty()
private fun initials(value:String):String=value.trim().split(Regex("\\s+")).filter{it.isNotEmpty()}.take(2).joinToString(""){it.take(1).uppercase(Locale.ROOT)}
private fun historyTime(value:String,locale:Locale):String=ExactDisplay.timestamp(value,locale.toLanguageTag())?:value
private fun iconFor(route:Route)=when(route){Route.HOME->R.drawable.ic_home;Route.PAYMENTS->R.drawable.ic_activity;Route.MEMBERS->R.drawable.ic_members;else->R.drawable.ic_settings}
private fun titleFor(route:Route)=when(route){Route.LOGIN->"Sign in";Route.HOME->"Home";Route.PAYMENTS->"Payments";Route.PAYMENT->"M-Money";Route.MEMBERS->"Members";Route.MEMBER->"Member";Route.SMS->"SMS";Route.SETTINGS->"Settings"}

@Composable
fun BuriApp(model:BuriController,onSupport:()->Unit,onPermissions:()->Unit,onExport:(ExportFormat)->Unit,onPhoneSettings:()->Unit,
    onPickMemberFile:()->Unit={},onPreviewMemberFile:(String)->Unit={},onNotifications:()->Unit={},onBatteryOptimization:()->Unit={},
    onTakeMemberPhoto:()->Unit={},onPickMemberPhoto:()->Unit={}){
    val t=LocalUiText.current
    val state=model.state
    val memory=remember(state.operator?.id){UiFocusMemory()}
    val scope="${state.route}:${state.routeId.orEmpty()}:${state.sheet}:${state.sheetId.orEmpty()}"
    CompositionLocalProvider(LocalUiFocusMemory provides memory,LocalUiFocusScope provides scope,LocalBuriRouteColors provides BuriTheme.colors(state.route),LocalBuriRoute provides state.route){
        FocusReturnEffect(scope)
        BuriAppBody(model,onSupport,onPermissions,onExport,onPhoneSettings,onPickMemberFile,onPreviewMemberFile,onNotifications,onBatteryOptimization,onTakeMemberPhoto,onPickMemberPhoto)
    }
}

@Composable private fun BuriAppBody(model:BuriController,onSupport:()->Unit,onPermissions:()->Unit,onExport:(ExportFormat)->Unit,onPhoneSettings:()->Unit,
    onPickMemberFile:()->Unit,onPreviewMemberFile:(String)->Unit,onNotifications:()->Unit,onBatteryOptimization:()->Unit,
    onTakeMemberPhoto:()->Unit,onPickMemberPhoto:()->Unit){
    val t=LocalUiText.current
    val s=model.state
    if(s.starting||s.savedSessionPending){
        BuriSplash(s.error,if(s.savedSessionPending&&!s.busy)model::refresh else null,
            if(s.savedSessionPending&&!s.busy)model::logout else null,loading=s.busy||s.starting)
        return
    }
    val gate=model.screenGate
    val presentation=model.presentation
    val read=s.operator!=null
    val keyboard=LocalSoftwareKeyboardController.current
    var exportVisible by remember(s.operator?.id,s.route,s.routeId,s.sheet,s.sheetId){mutableStateOf(false)}
    val openExport:()->Unit={if(model.canExportListing&&!s.busy&&!s.offline&&gate==ScreenGate.OPEN){keyboard?.hide();exportVisible=true}}
    LaunchedEffect(read,gate,model.canExportListing){if(!read||gate!=ScreenGate.OPEN||!model.canExportListing)exportVisible=false}
    val focus=LocalFocusManager.current
    val imeVisible=WindowInsets.ime.getBottom(LocalDensity.current)>0
    val canBack=read&&(s.route!=Route.HOME||s.sheet!=null)
    val back:()->Unit={if(imeVisible){keyboard?.hide();focus.clearFocus()}else if(canBack)model.back()}
    BackHandler(enabled=imeVisible||canBack,onBack=back)
    Box(Modifier.fillMaxSize().background(BuriTheme.wash(s.route)).onPreviewKeyEvent{
        if(it.key==Key.Escape&&(imeVisible||canBack)){if(it.type==KeyEventType.KeyUp)back();true}else false
    }){
        Box(Modifier.matchParentSize().background(Color.Black.copy(alpha=BuriTheme.WashScrimAlpha)))
        Column(Modifier.fillMaxSize().safeDrawingPadding().imePadding()){
            Header(if(gate==ScreenGate.OPEN)s else s.copy(operator=null),model,openExport,onSupport)
                if(model.operation!=UiOperation.NONE&&!(model.operation==UiOperation.EXPORT&&model.exportFeedback!=null))BuriWorkingStrip(model.operation,model.operationLabel)
                else if(model.operation==UiOperation.NONE&&s.busy)BuriInlineLoading("Working",Modifier.padding(horizontal=20.dp))
                s.commandNotice?.takeIf{read}?.let{notice->
                    BuriStatusMessage(notice,warning=true)
                }
                s.error?.let{error->
                    BuriStatusMessage(error,error=true)
                }
                model.exportFeedback?.takeIf{s.sheet==null&&read&&gate==ScreenGate.OPEN&&presentation.showRecords}?.let{BuriExportFeedback(it,model::cancelExport,model::dismissExportFeedback)}
                if(s.passcodeChangePending||s.savedSessionPending){
                    Row(Modifier.fillMaxWidth().padding(horizontal=24.dp,vertical=4.dp),verticalAlignment=Alignment.CenterVertically){
                        RoundAction(R.drawable.ic_out,t("Sign out"),model::logout,enabled=!s.busy,size=48)
                    }
                }
                if(s.offline&&read){
                    Row(Modifier.fillMaxWidth().padding(horizontal=24.dp,vertical=6.dp),verticalAlignment=Alignment.CenterVertically){
                        Glyph(R.drawable.ic_alert,t("Offline"),BuriTheme.Warn,18)
                        Spacer(Modifier.width(10.dp));Text(s.savedAt?.let{t("%1\$s · saved %2\$s",t("Offline · read only"),historyTime(java.time.Instant.ofEpochMilli(it).toString(),t.locale))}?:t("Offline · read only"),fontSize=14.sp,color=BuriTheme.Warn,lineHeight=22.sp)
                    }
                }
                if(read)PagedRestoration.label(s.listRestoration)?.let{notice->
                    Text(t(notice),Modifier.fillMaxWidth().padding(horizontal=24.dp,vertical=6.dp)
                        .semantics{liveRegion=LiveRegionMode.Polite},fontSize=14.sp,color=BuriTheme.Warn,lineHeight=22.sp)
                }
                if(presentation.unresolvedWarning){
                    Row(Modifier.fillMaxWidth().padding(horizontal=24.dp,vertical=6.dp),verticalAlignment=Alignment.CenterVertically){
                        Text(t("Previous action needs confirmation"),Modifier.weight(1f),fontSize=14.sp,color=BuriTheme.Warn,lineHeight=22.sp)
                        if(read)RoundAction(R.drawable.ic_sync,t("Check previous action"),model::retry,enabled=presentation.mayCheckOutcome,size=48)
                    }
                }
                Box(Modifier.weight(1f).fillMaxWidth().padding(bottom=if(read)BottomNavClearance else 0.dp).semantics{stateDescription=t(PresentationState.label(presentation.state))}){
                    if(gate!=ScreenGate.OPEN){
                        // Preserve the existing route shell while disposing all private records/forms.
                        if(gate in setOf(ScreenGate.CHECKING,ScreenGate.STALE)&&(s.busy||model.operation!=UiOperation.NONE))BuriLoadingPanel(if(gate==ScreenGate.CHECKING)"Checking access"else "Updating records")
                        else Column(Modifier.fillMaxWidth().padding(20.dp)){
                            Text(t(when(gate){ScreenGate.BACKGROUND->"App paused";ScreenGate.CHECKING->"Checking access";ScreenGate.STALE->"Updating records";else->"Check your connection"}),fontSize=17.sp,lineHeight=25.sp)
                            if(gate!=ScreenGate.BACKGROUND&&!s.busy)Primary(t("Refresh"),model::refresh)
                        }
                    }else if(read&&!presentation.showRecords){
                        if(s.busy||model.operation in setOf(UiOperation.INITIAL_READ,UiOperation.REFRESH))BuriLoadingPanel("Loading records")
                        else Column(Modifier.fillMaxWidth().padding(24.dp)){
                            Text(t(PresentationState.label(presentation.state)),fontSize=17.sp,lineHeight=25.sp)
                            if(presentation.mayRetryRead){Spacer(Modifier.height(16.dp));Primary(t("Refresh"),model::refresh)}
                        }
                    }else key(s.route,s.routeId){RouteEntrance(t(titleFor(s.route))){when(s.route){
                        Route.LOGIN->Login(s.busy||s.configurationRequired||s.passcodeChangePending||s.savedSessionPending,model::login,onSupport,model.supportPhone!=null)
                        Route.HOME->HomeScreen(s,model)
                        Route.PAYMENTS->PaymentsScreen(s,model,openExport)
                        Route.PAYMENT->PaymentScreen(s,model)
                        Route.MEMBERS->MembersScreen(s,model,openExport)
                        Route.MEMBER->MemberScreen(s,model,openExport)
                        Route.SMS->SmsScreen(s,model,openExport)
                        Route.SETTINGS->SettingsScreen(s,model,onPermissions,onPhoneSettings,onNotifications,onBatteryOptimization)
                    }}}
                }
        }
        if(read)BottomNav(s.route,model::navigate,s.busy||gate!=ScreenGate.OPEN,
            Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom=BottomNavBottomGap))
    }
    if(s.sheet!=null&&((gate==ScreenGate.OPEN&&presentation.showRecords)||
        (s.sheet==Sheet.REPLACE_DEVICE&&s.receiverRetirementPending&&gate!=ScreenGate.BACKGROUND)))Sheets(s,model,onSupport,onPermissions,onPhoneSettings,onPickMemberFile,onPreviewMemberFile,onTakeMemberPhoto,onPickMemberPhoto,onExport=openExport)
    if(exportVisible&&read&&gate==ScreenGate.OPEN&&presentation.showRecords&&model.canExportListing){
        ListingExportSheet(model,onPick={format->exportVisible=false;onExport(format)},onDismiss={exportVisible=false})
    }
}

/** Initial restoration is an opaque branded surface, never a disabled login
 * form or private records. The real signed-out login renders after resolution. */
@Composable internal fun BuriSplash(error:String?=null,retry:(()->Unit)?=null,signOut:(()->Unit)?=null,loading:Boolean=false){
    val t=LocalUiText.current
    Box(Modifier.fillMaxSize().background(Color.Black).safeDrawingPadding().testTag("burimunsi-splash"),contentAlignment=Alignment.Center){
        Column(Modifier.fillMaxWidth().padding(32.dp),horizontalAlignment=Alignment.CenterHorizontally){
            Image(painterResource(R.drawable.burimunsi_brand_logo),"BuriMunsi",Modifier.widthIn(max=280.dp).fillMaxWidth().aspectRatio(3f))
            if(loading){Spacer(Modifier.height(24.dp));BuriInlineLoading("Getting things ready",Modifier.widthIn(max=280.dp))}
            if(error!=null){Spacer(Modifier.height(28.dp));Text(t(error),color=BuriTheme.Muted,fontSize=16.sp,textAlign=TextAlign.Center)}
            if(retry!=null){Spacer(Modifier.height(18.dp));TextButton(retry){Text(t("Retry"))}}
            if(signOut!=null)TextButton(signOut){Text(t("Sign out"))}
        }
    }
}

@Composable private fun Brand(){
    Image(painterResource(R.drawable.burimunsi_brand_logo),"BuriMunsi",Modifier.width(156.dp).height(52.dp))
}
@Composable private fun Header(s:UiState,m:BuriController,onExport:()->Unit,onSupport:()->Unit){
    val t=LocalUiText.current
    val enabled=!s.busy&&m.screenGate==ScreenGate.OPEN
    Row(Modifier.fillMaxWidth().heightIn(min=62.dp).padding(horizontal=16.dp,vertical=6.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)){
        when(s.route){
            Route.LOGIN->{Spacer(Modifier.weight(1f));RoundAction(R.drawable.ic_help,t("Contact admin on WhatsApp"),onSupport,enabled&&m.supportPhone!=null,size=48,tonal=false)}
            Route.PAYMENT,Route.MEMBER->{
                RoundAction(R.drawable.ic_back,t("Back"),m::back,enabled,size=48,tonal=false)
                Text(t(titleFor(s.route)),Modifier.weight(1f),fontSize=16.sp,color=BuriTheme.Muted,textAlign=TextAlign.Center)
                if(s.route==Route.MEMBER)RoundAction(R.drawable.ic_export,t("Download transactions"),onExport,enabled&&!s.offline&&m.canExportListing,size=48,tonal=false)
                else RoundAction(R.drawable.ic_history,t("Contribution history"),{m.openSheet(Sheet.HISTORY)},enabled,size=48,tonal=false)
            }
            else->{
                if(s.route==Route.HOME)Brand()
                else if(s.route==Route.SMS)RoundAction(R.drawable.ic_back,t("Back to Home"),{m.navigate(Route.HOME)},enabled,size=48,tonal=false)
                else Spacer(Modifier.size(48.dp))
                Spacer(Modifier.weight(1f))
                if(s.route==Route.MEMBERS&&m.allows(Capability.ENROLL))RoundAction(R.drawable.ic_plus,t("Add member"),{m.openSheet(Sheet.ENROLL)},enabled&&!s.offline,size=48)
                if(s.route==Route.PAYMENTS)RoundAction(R.drawable.ic_filter,t("Payment filters"),{m.openSheet(Sheet.FILTERS)},enabled,size=48)
                when(s.route){
                    Route.SETTINGS->RoundAction(R.drawable.ic_out,t("Sign out"),m::logout,enabled,size=48,tonal=false)
                    Route.SMS->RoundAction(R.drawable.ic_device,t("Gateway status"),{m.openSheet(Sheet.GATEWAY)},enabled,size=48)
                    else->IconButton({m.openSheet(Sheet.PROFILE)},enabled=enabled,modifier=Modifier.size(48.dp).semantics{contentDescription=t("Your profile")}){Avatar(s.operator?.name.orEmpty(),42)}
                }
            }
        }
    }
}
@Composable private fun BottomNav(current:Route,onNavigate:(Route,String?)->Unit,busy:Boolean,modifier:Modifier=Modifier){
    val active=when(current){Route.PAYMENT->Route.PAYMENTS;Route.MEMBER->Route.MEMBERS;Route.SMS->Route.HOME;else->current}
    Row(modifier.fillMaxWidth().padding(horizontal=16.dp).heightIn(min=BottomNavHeight).background(Color(0xEE1F1F23),RoundedCornerShape(34.dp)).padding(6.dp),horizontalArrangement=Arrangement.spacedBy(4.dp)){
        for(route in listOf(Route.HOME,Route.PAYMENTS,Route.MEMBERS,Route.SETTINGS)){
            val chosen=active==route
            val action=focusAction("navigation:${route.name}"){onNavigate(route,null)}
            IconButton(onClick=action.click,enabled=!busy,modifier=action.modifier.weight(1f).height(54.dp).background(if(chosen)Color(0xFF363639)else Color.Transparent,RoundedCornerShape(28.dp)).semantics{selected=chosen;role=SemanticRole.Tab}){
                Glyph(iconFor(route),titleFor(route),if(chosen)BuriTheme.Text else Color(0xFFA1A1A3),27)
            }
        }
    }
}
@Composable fun SingleLineName(name:String,modifier:Modifier=Modifier,size:Int=19,alignment:TextAlign=TextAlign.Start){
    val t=LocalUiText.current
    Text(name,modifier.clearAndSetSemantics{contentDescription=name},fontSize=size.sp,fontWeight=FontWeight.Medium,maxLines=1,overflow=TextOverflow.Ellipsis,lineHeight=(size+8).sp,textAlign=alignment)
}
@Composable internal fun Glyph(icon:Int,description:String?,tint:Color=BuriTheme.Text,size:Int=24){
    val t=LocalUiText.current
    Icon(painterResource(icon),description?.let{t(it)},Modifier.size(size.dp),tint)
}
@Composable private fun RoundAction(icon:Int,label:String,click:()->Unit,enabled:Boolean=true,size:Int=56,tonal:Boolean=true){
    val action=focusAction("action:$label",click)
    IconButton(action.click,action.modifier.size(size.dp).background(if(tonal)BuriTheme.Tone else Color.Transparent,CircleShape),enabled=enabled){Glyph(icon,label,if(enabled)BuriTheme.Text else BuriTheme.Muted,24)}
}
@Composable private fun Avatar(name:String,size:Int=46,unallocated:Boolean=false,initialsSize:Int=15){
    val t=LocalUiText.current
    Box(Modifier.size(size.dp).background(if(unallocated)BuriTheme.Warn.copy(alpha=.10f)else BuriTheme.Tone,CircleShape).clearAndSetSemantics{},contentAlignment=Alignment.Center){Text(initials(name),fontSize=initialsSize.sp,color=if(unallocated)BuriTheme.Warn else BuriTheme.Text,fontWeight=FontWeight.Medium,lineHeight=(initialsSize+8).sp)}
}
@Composable internal fun Primary(label:String,onClick:()->Unit,enabled:Boolean=true,secondary:Boolean=false,danger:Boolean=false,
    icon:Int?=null,iconTrailing:Boolean=false,modifier:Modifier=Modifier,working:Boolean=false){
    val t=LocalUiText.current
    val action=focusAction("button:$label",onClick)
    val keyboard=LocalSoftwareKeyboardController.current
    Button({keyboard?.hide();action.click()},action.modifier.then(modifier).fillMaxWidth().heightIn(min=58.dp).semantics{if(working){stateDescription=t("In progress");progressBarRangeInfo=ProgressBarRangeInfo.Indeterminate}},enabled=enabled&&!working,shape=RoundedCornerShape(30.dp),
        colors=ButtonDefaults.buttonColors(containerColor=if(danger)BuriTheme.Bad.copy(alpha=.13f) else if(secondary)BuriTheme.Raised else BuriTheme.Text,contentColor=if(danger)BuriTheme.Bad else if(secondary)BuriTheme.Text else Color(0xFF151517))){
        if(working){BuriOrbit(size=22,tint=if(danger)BuriTheme.Bad else BuriTheme.Blue);Spacer(Modifier.width(12.dp))}
        else if(icon!=null&&!iconTrailing){Icon(painterResource(icon),null,Modifier.size(23.dp));Spacer(Modifier.width(10.dp))}
        Text(t(label),fontSize=18.sp,fontWeight=FontWeight.SemiBold,textAlign=TextAlign.Center,lineHeight=26.sp)
        if(icon!=null&&iconTrailing&&!working){Spacer(Modifier.width(10.dp));Icon(painterResource(icon),null,Modifier.size(23.dp))}
    }
}
@Composable private fun Fact(label:String,value:String){
    val t=LocalUiText.current
    Row(Modifier.fillMaxWidth().padding(vertical=15.dp),horizontalArrangement=Arrangement.spacedBy(16.dp),verticalAlignment=Alignment.Top){
        Text(t(label),Modifier.weight(.44f),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=21.sp)
        Text(value,Modifier.weight(.64f),fontSize=17.sp,fontWeight=FontWeight.Medium,lineHeight=25.sp,textAlign=TextAlign.End)
    }
}
@Composable private fun FactGroup(facts:List<Pair<String,String>>,surface:Color=BuriTheme.Surface){
    Column(Modifier.fillMaxWidth().background(surface,RoundedCornerShape(24.dp)).padding(horizontal=18.dp,vertical=4.dp)){
        facts.forEachIndexed{index,(label,value)->
            Fact(label,value)
            if(index<facts.lastIndex)HorizontalDivider(color=Color.White.copy(alpha=.08f))
        }
    }
}
private fun stateIcon(name:String)=when(name){"check"->R.drawable.ic_check;"link"->R.drawable.ic_link;"history"->R.drawable.ic_history;"sync"->R.drawable.ic_sync;"clock"->R.drawable.ic_clock;else->R.drawable.ic_alert}
@Composable private fun stateTone(name:String)=when(name){"good"->BuriTheme.Good;"bad"->BuriTheme.Bad;"warn"->BuriTheme.Warn;else->BuriTheme.Blue}
@Composable private fun MoneyText(value:Long?,modifier:Modifier=Modifier,size:Int=22,positiveSign:Boolean=false,showHint:Boolean=false){
    val t=LocalUiText.current
    if(value==null){Text(t("Unavailable"),modifier,fontSize=size.sp,color=BuriTheme.Muted);return}
    val full=(if(positiveSign&&value>0)"+" else "")+money(value,LocalUiText.current.locale)
    val measurer=rememberTextMeasurer()
    val density=LocalDensity.current
    val baseStyle=LocalTextStyle.current.copy(fontWeight=FontWeight.Medium,fontFeatureSettings="tnum")
    BoxWithConstraints(modifier){
        val widthPx=with(density){maxWidth.toPx()}
        val selected=remember(full,widthPx,density.density,density.fontScale,size,baseStyle,measurer){
            var candidate=size.toFloat()
            val floor=minOf(size.toFloat(),Presentation.MONEY_MIN_SP.toFloat())
            // Measurement inherits the platform's actual font scaling. Never reduce below 16sp.
            while(candidate>floor&&measurer.measure(full,style=baseStyle.copy(fontSize=candidate.sp),softWrap=false,maxLines=1).size.width>widthPx){candidate=maxOf(floor,candidate-1f)}
            candidate
        }
        val scroll=rememberScrollState()
        Column{
            Text(full,Modifier.horizontalScroll(scroll).semantics{contentDescription="$full RWF"},
                style=baseStyle.copy(fontSize=selected.sp,lineHeight=(selected+6).sp),maxLines=1,softWrap=false)
            if(showHint&&scroll.maxValue>0)Text(t("Scroll amount to view all digits"),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)
        }
    }
}
@Composable private fun BigValue(amount:Long?,size:Int=64){
    val t=LocalUiText.current
    Column(Modifier.fillMaxWidth().padding(vertical=14.dp),horizontalAlignment=Alignment.CenterHorizontally){
        MoneyText(amount,Modifier.widthIn(max=800.dp),size,showHint=true)
        if(amount!=null){Spacer(Modifier.height(8.dp));Text(t("RWF"),fontSize=16.sp,color=BuriTheme.Muted,lineHeight=24.sp)}
    }
}
@Composable private fun routeList(s:UiState,m:BuriController):androidx.compose.foundation.lazy.LazyListState {
    val t=LocalUiText.current
    val scroll=rememberLazyListState(s.listIndex,s.listOffset)
    LaunchedEffect(scroll,s.route,s.routeId,s.busy){if(s.busy)return@LaunchedEffect;snapshotFlow{scroll.firstVisibleItemIndex to scroll.firstVisibleItemScrollOffset}.distinctUntilChanged().collect{(index,offset)->m.listPosition(s.route,s.routeId,index,offset)}}
    return scroll
}
@Composable private fun Empty(label:String="No records"){
    val t=LocalUiText.current
    Column(Modifier.fillMaxWidth().padding(vertical=36.dp),horizontalAlignment=Alignment.CenterHorizontally){Glyph(R.drawable.ic_activity,null,BuriTheme.Muted,36);Spacer(Modifier.height(14.dp));Text(t(label),Modifier.semantics{liveRegion=LiveRegionMode.Polite},color=BuriTheme.Muted,fontSize=18.sp,lineHeight=26.sp)}}
@Composable private fun OverviewTitle(label:String){Text(label,Modifier.padding(top=12.dp,bottom=24.dp).semantics{heading()},fontSize=40.sp,fontWeight=FontWeight.SemiBold,lineHeight=44.sp,letterSpacing=(-1.6).sp)}
@Composable private fun CountLine(left:String,right:String){Row(Modifier.fillMaxWidth().padding(start=3.dp,end=3.dp,bottom=10.dp),horizontalArrangement=Arrangement.SpaceBetween){Text(left,color=BuriTheme.Muted,fontSize=13.sp);Text(right,color=BuriTheme.Muted,fontSize=13.sp)}}
@Composable private fun Section(label:String){
    val t=LocalUiText.current
    Text(t(label),Modifier.padding(top=12.dp,bottom=2.dp).semantics{heading()},fontSize=24.sp,fontWeight=FontWeight.SemiBold,lineHeight=32.sp)}
@Composable private fun Search(value:String,change:(String)->Unit,submit:()->Unit,hint:String="Search",busy:Boolean=false){
    val t=LocalUiText.current
    var submitted by remember{mutableStateOf(value)}
    LaunchedEffect(value){if(value!=submitted){kotlinx.coroutines.delay(250);submitted=value;submit()}}
    OutlinedTextField(value,change,Modifier.fillMaxWidth().heightIn(min=56.dp).semantics{contentDescription=t(hint)},singleLine=true,enabled=!busy,
        textStyle=LocalTextStyle.current.copy(fontSize=18.sp),placeholder={Text(t(hint),color=BuriTheme.Muted,fontSize=18.sp)},leadingIcon={Glyph(R.drawable.ic_search,null,BuriTheme.Muted,22)},
        keyboardOptions=KeyboardOptions(autoCorrectEnabled=false,imeAction=ImeAction.Search),keyboardActions=KeyboardActions(onSearch={submitted=value;submit()}),
        shape=RoundedCornerShape(28.dp),colors=OutlinedTextFieldDefaults.colors(focusedContainerColor=BuriTheme.Tone,unfocusedContainerColor=BuriTheme.Tone,focusedBorderColor=BuriTheme.Blue,unfocusedBorderColor=Color.Transparent))
}
@Composable private fun FilterChipIcon(label:String,icon:Int,chosen:Boolean,count:Int?=null,click:()->Unit){
    val t=LocalUiText.current
    FilterChip(selected=chosen,onClick=click,label={Row(verticalAlignment=Alignment.CenterVertically){if(chosen)Text(t(label),maxLines=1);if(count!=null&&count>0){if(chosen)Spacer(Modifier.width(8.dp));Text(count.toString(),fontSize=12.sp,fontWeight=FontWeight.SemiBold)}}},leadingIcon={Glyph(icon,label,if(chosen)Color(0xFF151517)else BuriTheme.Text,20)},modifier=Modifier.heightIn(min=48.dp),shape=RoundedCornerShape(24.dp),colors=FilterChipDefaults.filterChipColors(containerColor=BuriTheme.Tone,selectedContainerColor=BuriTheme.Text,labelColor=BuriTheme.Text,selectedLabelColor=Color(0xFF151517)))
}
private fun LazyListScope.moreButton(cursor:String?,busy:Boolean,more:()->Unit,key:String="pagination",autoEnabled:Boolean=true){
    if(cursor!=null)item(key=key){
        // Preserve the prototype's continuous list while honoring actual server cursors.
        LaunchedEffect(cursor,busy,autoEnabled){if(!busy&&autoEnabled)more()}
        if(busy)BuriInlineLoading("Loading more")else if(!autoEnabled)TextButton(more,Modifier.fillMaxWidth().heightIn(min=52.dp)){Text(LocalUiText.current("Retry loading"))}else Spacer(Modifier.height(52.dp))
    }
}
private fun rowShape(first:Boolean,last:Boolean)=RoundedCornerShape(topStart=if(first)24.dp else 0.dp,topEnd=if(first)24.dp else 0.dp,bottomStart=if(last)24.dp else 0.dp,bottomEnd=if(last)24.dp else 0.dp)
@Composable private fun PaymentRow(p:Payment,first:Boolean=true,last:Boolean=true,click:()->Unit){
    val t=LocalUiText.current
    val action=focusAction("payment:${p.id}",click)
    val status=PaymentPresentation.payment(p)
    val fontScale=LocalDensity.current.fontScale
    BoxWithConstraints(action.modifier.fillMaxWidth().heightIn(min=84.dp).background(BuriTheme.Group,rowShape(first,last)).clickable(role=SemanticRole.Button,onClick=action.click)
        .semantics(mergeDescendants=true){}.padding(horizontal=16.dp,vertical=16.dp)){
        val stacked=maxWidth<280.dp||fontScale>=1.5f
        Column(Modifier.fillMaxWidth()){
            Row(verticalAlignment=Alignment.CenterVertically){
                Avatar(p.payerNameRaw,unallocated=p.state=="unallocated");Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)){
                    SingleLineName(p.payerNameRaw.ifBlank{t("Unavailable")})
                    Spacer(Modifier.height(4.dp));Text(p.atRaw,fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)
                    Spacer(Modifier.height(4.dp));Text(t("FT Id: %1\$s",p.ftId?:t("Unavailable")),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)
                    if(p.sourceKind=="observation"){Spacer(Modifier.height(4.dp));Text(t(PaymentPresentation.directionLabel(p.direction)),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)}
                }
                if(!stacked){
                    Spacer(Modifier.width(8.dp))
                    Column(Modifier.widthIn(max=140.dp),horizontalAlignment=Alignment.End){
                        MoneyText(p.amountRwf,size=22);Spacer(Modifier.height(6.dp))
                        Glyph(stateIcon(status.icon),status.label,stateTone(status.tone),20)
                    }
                }
            }
            if(stacked){
                Spacer(Modifier.height(10.dp))
                Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){
                    MoneyText(p.amountRwf,Modifier.weight(1f),22,showHint=true)
                    Spacer(Modifier.width(12.dp));Glyph(stateIcon(status.icon),status.label,stateTone(status.tone),20)
                }
            }
        }
        if(!last)HorizontalDivider(Modifier.align(Alignment.BottomCenter),color=Color.White.copy(alpha=.08f))
    }
}
@Composable private fun MemberRow(member:Member,first:Boolean=true,last:Boolean=true,click:()->Unit){
    val t=LocalUiText.current
    val action=focusAction("member:${member.id}",click)
    val fontScale=LocalDensity.current.fontScale
    BoxWithConstraints(action.modifier.fillMaxWidth().heightIn(min=84.dp).background(BuriTheme.Group,rowShape(first,last)).clickable(role=SemanticRole.Button,onClick=action.click)
        .semantics(mergeDescendants=true){}.padding(horizontal=16.dp,vertical=16.dp)){
        val stacked=maxWidth<280.dp||fontScale>=1.5f
        Column(Modifier.fillMaxWidth()){
            Row(verticalAlignment=Alignment.CenterVertically){
                Avatar(member.name);Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)){
                    SingleLineName(member.name);Spacer(Modifier.height(5.dp))
                    Text(if(member.active)member.phone else t("%1\$s · %2\$s",member.phone,t("Inactive")),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)
                }
                if(!stacked){Spacer(Modifier.width(8.dp));MoneyText(member.balanceRwf,Modifier.widthIn(max=140.dp),22)}
            }
            if(stacked){Spacer(Modifier.height(10.dp));MoneyText(member.balanceRwf,Modifier.fillMaxWidth(),22,showHint=true)}
        }
        if(!last)HorizontalDivider(Modifier.align(Alignment.BottomCenter),color=Color.White.copy(alpha=.08f))
    }
}
@Composable private fun LedgerRowView(row:LedgerRow,first:Boolean=true,last:Boolean=true,click:()->Unit){
    val t=LocalUiText.current;val action=focusAction("ledger:${row.id}",click)
    BoxWithConstraints(action.modifier.fillMaxWidth().heightIn(min=84.dp).background(BuriTheme.Group,rowShape(first,last))
        .then(if(row.transactionId!=null)Modifier.clickable(role=SemanticRole.Button,onClick=action.click)else Modifier).padding(horizontal=16.dp,vertical=16.dp)){
        val stacked=maxWidth<280.dp||LocalDensity.current.fontScale>=1.5f
        Column(Modifier.fillMaxWidth()){
            Row(verticalAlignment=Alignment.CenterVertically){
                Avatar(row.payerNameRaw);Spacer(Modifier.width(12.dp));Column(Modifier.weight(1f)){
                    SingleLineName(row.payerNameRaw);Spacer(Modifier.height(5.dp));Text(row.atRaw,fontSize=13.sp,color=BuriTheme.Muted,lineHeight=19.sp)
                    Spacer(Modifier.height(5.dp));Text(t("FT Id: %1\$s",row.ftId),fontSize=13.sp,color=BuriTheme.Muted,lineHeight=19.sp)
                }
                if(!stacked){Spacer(Modifier.width(8.dp));Column(Modifier.widthIn(max=140.dp),horizontalAlignment=Alignment.End){MoneyText(row.amountRwf,size=22);Spacer(Modifier.height(5.dp));val status=PaymentPresentation.payment(row.state?:"unknown");Glyph(stateIcon(status.icon),status.label,stateTone(status.tone),16)}}
            }
            if(stacked){Spacer(Modifier.height(10.dp));Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){MoneyText(row.amountRwf,Modifier.weight(1f),22,showHint=true);val status=PaymentPresentation.payment(row.state?:"unknown");Glyph(stateIcon(status.icon),status.label,stateTone(status.tone),16)}}
        }
        if(!last)HorizontalDivider(Modifier.align(Alignment.BottomCenter),color=Color.White.copy(alpha=.08f))
    }
}

@Composable private fun HomeScreen(s:UiState,m:BuriController){
    val t=LocalUiText.current;val home=s.home
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(20.dp,21.dp,20.dp,26.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
        if(home==null){item{if(s.busy){BuriInlineLoading("Loading records");BuriSkeletonRows()}else Empty(t("No records available"))};return@LazyColumn}
        item{BigValue(home.balanceRwf)}
        item{Row(Modifier.fillMaxWidth().padding(top=6.dp,bottom=11.dp),horizontalArrangement=Arrangement.SpaceEvenly){
            RoundAction(R.drawable.ic_activity,t("Open payments"),{m.navigate(Route.PAYMENTS)},!s.busy,58)
            RoundAction(R.drawable.ic_members,t("Open members"),{m.navigate(Route.MEMBERS)},!s.busy,58)
            if(m.allows(Capability.ENROLL))RoundAction(R.drawable.ic_plus,t("Add member"),{m.openSheet(Sheet.ENROLL)},!s.busy&&!s.offline,58)
            if(m.allows(Capability.SMS))RoundAction(R.drawable.ic_sms,t("Messages"),{m.navigate(Route.SMS)},!s.busy,58)
            else RoundAction(R.drawable.ic_history,t("Recent payments"),{m.navigate(Route.PAYMENTS)},!s.busy,58)
        }}
        item{Row(Modifier.fillMaxWidth().padding(horizontal=8.dp),horizontalArrangement=Arrangement.spacedBy(20.dp)){
            Column(Modifier.weight(1f)){MoneyText(home.todayRwf,size=32,showHint=true);Spacer(Modifier.height(4.dp));Text(t("Today · RWF"),color=BuriTheme.Muted,fontSize=13.sp)}
            Column(Modifier.weight(1f),horizontalAlignment=Alignment.End){Text(home.memberCount.toString(),fontSize=32.sp,lineHeight=38.sp);Spacer(Modifier.height(4.dp));Text(t("Members"),color=BuriTheme.Muted,fontSize=13.sp)}
        }}
        if(home.unallocatedCount>0)item{Row(Modifier.fillMaxWidth().background(BuriTheme.Warn.copy(alpha=.075f),RoundedCornerShape(22.dp)).clickable(enabled=!s.busy){m.openUnallocated()}.padding(horizontal=16.dp,vertical=13.dp),verticalAlignment=Alignment.CenterVertically){
            Glyph(R.drawable.ic_link,null,BuriTheme.Warn,24);Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)){Text(t("%1\$d unallocated",home.unallocatedCount),fontSize=18.sp,color=BuriTheme.Warn);Spacer(Modifier.height(2.dp));Text(home.unallocatedAmountRwf?.let{t("RWF %1\$s",money(it,t.locale))}?:t("Unavailable"),fontSize=13.sp,color=BuriTheme.Warn)}
            Glyph(R.drawable.ic_arrow,t("Open unallocated"),BuriTheme.Warn,18)
        }}
        item{Row(Modifier.fillMaxWidth().heightIn(min=48.dp),verticalAlignment=Alignment.CenterVertically){Text(t("Recent"),Modifier.weight(1f),fontSize=24.sp,fontWeight=FontWeight.SemiBold);RoundAction(R.drawable.ic_arrow,t("All payments"),{m.navigate(Route.PAYMENTS)},!s.busy,48)}}
        val recent=home.recent.take(3)
        itemsIndexed(recent,key={_,p->p.id}){index,p->PaymentRow(p,index==0,index==recent.lastIndex){m.navigate(Route.PAYMENT,p.id)}}
        if(home.recent.isEmpty())item{Empty()}
    }
}
@Composable private fun PaymentsScreen(s:UiState,m:BuriController,onExport:()->Unit){
    val t=LocalUiText.current
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(20.dp,4.dp,20.dp,26.dp)){
        item{OverviewTitle(t("Payments"));Search(s.search,m::search,m::searchSubmit,t("Search"),s.busy)}
        item{ListingToolbar(m,onExport,showFilter=false)}
        item{Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(vertical=12.dp),horizontalArrangement=Arrangement.spacedBy(10.dp)){
            FilterChipIcon(t("All"),R.drawable.ic_activity,s.filter=="all"){m.setFilter("all")}
            FilterChipIcon(t("Allocated"),R.drawable.ic_check,s.filter=="allocated"){m.setFilter("allocated")}
            val count=s.home?.unallocatedCount?:if(s.filter=="unallocated"&&s.search.isBlank())s.payments?.totalCount else null
            FilterChipIcon(t("Unallocated"),R.drawable.ic_link,s.filter=="unallocated",count){m.setFilter("unallocated")}
        }}
        item{CountLine(s.payments?.totalCount?.toString().orEmpty(),"RWF")}
        val payments=s.payments?.items.orEmpty()
        itemsIndexed(payments,key={_,p->p.id}){index,p->PaymentRow(p,index==0,index==payments.lastIndex){m.navigate(Route.PAYMENT,p.id)}}
        if(s.payments?.items?.isEmpty()==true)item{Empty(t("No payments"));Text(t("Try another search."),color=BuriTheme.Muted)}
        moreButton(s.payments?.nextCursor,s.busy,m::more,autoEnabled=!s.offline&&s.error==null)
    }
}
@Composable private fun PaymentScreen(s:UiState,m:BuriController){
    val t=LocalUiText.current
    val p=s.payment
    if(p==null){if(s.busy)BuriLoadingPanel("Loading payment")else Empty(t("Payment unavailable. Go back or refresh."));return}
    val status=PaymentPresentation.payment(p)
    val canAllocate=PaymentPresentation.canAllocate(p)&&m.allows(Capability.ALLOCATE)
    Box(Modifier.fillMaxSize()){
        LazyColumn(Modifier.fillMaxSize().testTag("payment-details-scroll"),state=routeList(s,m),contentPadding=PaddingValues(20.dp,20.dp,20.dp,if(canAllocate)104.dp else 26.dp),verticalArrangement=Arrangement.spacedBy(12.dp)){
            item{Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.Center){
                Box(Modifier.size(78.dp).background(stateTone(status.tone).copy(alpha=if(status.tone=="good") .07f else if(status.tone=="warn") .08f else .12f),CircleShape),contentAlignment=Alignment.Center){Glyph(stateIcon(status.icon),status.label,stateTone(status.tone),36)}
            }}
            item{SingleLineName(p.payerNameRaw.ifBlank{t("Unavailable")},Modifier.fillMaxWidth(),26,TextAlign.Center)}
            item{BigValue(p.amountRwf)}
            if(!status.confirmedCredit)item{Text(t(status.label),Modifier.fillMaxWidth(),color=stateTone(status.tone),fontSize=14.sp,lineHeight=21.sp,textAlign=TextAlign.Center)}
            if(p.state=="corrected")item{Text(t("Amount on original receipt · member credit not confirmed."),Modifier.fillMaxWidth(),color=BuriTheme.Muted,fontSize=14.sp,lineHeight=21.sp,textAlign=TextAlign.Center)}
            item{FactGroup(buildList{
                if(p.sourceKind=="observation"){
                    add(t("Direction") to t(PaymentPresentation.directionLabel(p.direction)))
                    add(t("Outcome") to t(PaymentPresentation.outcomeLabel(p.outcome)))
                }
                add(t("FT Id") to (p.ftId?:t("Unavailable")));add(t("at") to p.atRaw.ifBlank{t("Unavailable")})
                add((if(p.memberPhone!=null&&p.memberPhone!=p.payerPhoneRaw)t("Member MoMo")else t("MoMo")) to (p.memberPhone?:p.payerPhoneRaw.ifBlank{t("Unavailable")}))
                if(p.memberPhone!=null&&p.memberPhone!=p.payerPhoneRaw)add(t("from") to "${p.payerNameRaw} (${p.payerPhoneRaw})")
                p.feeRwf?.let{add(t("Fee") to t("RWF %1\$s",money(it,t.locale)))}
                p.walletBalanceAfterRwf?.let{add(t("Balance after") to t("RWF %1\$s",money(it,t.locale)))}
            })}
            item{Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(22.dp,Alignment.CenterHorizontally)){
                if(p.memberId!=null)RoundAction(R.drawable.ic_members,t("Member ledger"),{m.navigate(Route.MEMBER,p.memberId)},!s.busy,58)
                p.sourceId?.let{sourceId->if(m.allows(Capability.SMS))RoundAction(R.drawable.ic_sms,t("Original SMS"),{
                    m.openSms(if(p.sourceKind=="observation")SmsSourceRef.Observation(sourceId) else SmsSourceRef.Canonical(sourceId))
                },!s.busy,58)}
                RoundAction(R.drawable.ic_history,t("Contribution history"),{m.openSheet(Sheet.HISTORY,p.id)},!s.busy,58)
            }}
        }
        if(canAllocate)Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(horizontal=20.dp).padding(bottom=13.dp)){
            Primary(t("Allocate"),{m.openSheet(Sheet.ALLOCATE)},!s.busy&&!s.offline&&!s.pending,icon=R.drawable.ic_link,modifier=Modifier.testTag("payment-allocation-fixed"))
        }
    }
}
@Composable private fun MembersScreen(s:UiState,m:BuriController,onExport:()->Unit){
    val t=LocalUiText.current
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(20.dp,4.dp,20.dp,26.dp)){
        item{OverviewTitle(t("Members"));Search(s.search,m::search,m::searchSubmit,t("Search"),s.busy)}
        item{ListingToolbar(m,onExport)}
        item{CountLine(s.members?.totalCount?.let{t("%1\$d members",it)}?:t("Unavailable"),"RWF")}
        val members=s.members?.items.orEmpty()
        itemsIndexed(members,key={_,member->member.id}){index,member->MemberRow(member,index==0,index==members.lastIndex){m.navigate(Route.MEMBER,member.id)}}
        if(s.members?.items?.isEmpty()==true)item{Empty(t("No members"));Text(t("Try a name or MoMo number."),color=BuriTheme.Muted)}
        moreButton(s.members?.nextCursor,s.busy,m::more,autoEnabled=!s.offline&&s.error==null)
    }
}
@Composable private fun MemberScreen(s:UiState,m:BuriController,onExport:()->Unit){
    val t=LocalUiText.current
    val member=s.member
    if(member==null){if(s.busy)BuriLoadingPanel("Loading member")else Empty(t("Member unavailable. Go back or refresh."));return}
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(20.dp,20.dp,20.dp,26.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
        item{Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.Center){Avatar(member.name,66,initialsSize=24)}}
        item{SingleLineName(member.name,Modifier.fillMaxWidth(),32,TextAlign.Center);Spacer(Modifier.height(8.dp));Text(if(member.active)member.phone else t("%1\$s · %2\$s",member.phone,t("Inactive")),Modifier.fillMaxWidth(),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=21.sp,textAlign=TextAlign.Center)}
        item{BigValue(member.balanceRwf,60)}
        item{Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.Center){
            RoundAction(R.drawable.ic_info,t("Member details"),{m.openSheet(Sheet.MEMBER_DETAILS)},!s.busy,58)
            Spacer(Modifier.width(22.dp));RoundAction(R.drawable.ic_export,t("Download transactions"),onExport,!s.busy&&!s.offline&&m.canExportListing,58)
        }}
        item{ListingToolbar(m,onExport,showExport=false)}
        item{Row(Modifier.fillMaxWidth().heightIn(min=48.dp),verticalAlignment=Alignment.CenterVertically){Text(t("Transactions"),Modifier.weight(1f).semantics{heading()},fontSize=24.sp,fontWeight=FontWeight.SemiBold);Text(t("RWF"),fontSize=12.sp,color=BuriTheme.Muted)}}
        val transactions=s.memberTransactions?.items.orEmpty()
        itemsIndexed(transactions,key={_,payment->payment.id}){index,payment->PaymentRow(payment,index==0,index==transactions.lastIndex){m.navigate(Route.PAYMENT,payment.id)}}
        if(s.memberTransactions?.items?.isEmpty()==true)item{Empty(t("No transactions"))}
        moreButton(s.memberTransactions?.nextCursor,s.busy,m::more,autoEnabled=!s.offline&&s.error==null)
    }
}
@Composable private fun QueuedSmsRow(row:QueuedObservationRow,index:Int,last:Int){
    val t=LocalUiText.current
    Row(Modifier.testTag("queued-observation:"+row.id).fillMaxWidth().background(BuriTheme.Group,rowShape(index==0,index==last))
        .padding(horizontal=16.dp,vertical=16.dp),verticalAlignment=Alignment.Top){
        Box(Modifier.size(42.dp).background(BuriTheme.Tone,CircleShape),contentAlignment=Alignment.Center){Glyph(R.drawable.ic_sms,null,BuriTheme.Text,23)};Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)){
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){SingleLineName(row.sender,Modifier.weight(1f));Spacer(Modifier.width(8.dp));Text(historyTime(row.at,t.locale),fontSize=12.sp,color=BuriTheme.Muted)}
            if(row.preview.isNotEmpty()){Spacer(Modifier.height(6.dp));Text(row.preview,fontSize=16.sp,color=BuriTheme.Muted,maxLines=2,overflow=TextOverflow.Ellipsis,lineHeight=24.sp)}
            Text(t("Queued"),Modifier.padding(top=6.dp),fontSize=13.sp,color=BuriTheme.Warn)
        }
    }
}
@Composable private fun SmsScreen(s:UiState,m:BuriController,onExport:()->Unit){
    val t=LocalUiText.current;val query=s.smsListSearch
    val allMessages=s.messages?.items.orEmpty();val allObservations=s.observations?.items.orEmpty()
    val messages=allMessages.filter{SmsListSearch.matches(it.id,s.smsListContent[SmsSourceRef.Canonical(it.id)],query)}
    fun observationContent(source:SmsSourceRef)=s.smsListContent[source].takeIf{m.smsAccessGranted}
    val observations=allObservations.filter{SmsListSearch.matches(it.source.id,observationContent(it.source),query)}
    val queueVisible=s.filter in setOf("queued","all")&&m.smsAccessGranted&&m.allows(Capability.SMS)&&m.allows(Capability.GATEWAY)
    val queued=if(queueVisible&&!s.queuedUnavailable)s.queuedObservations.orEmpty()else emptyList()
    val sender=queued.firstOrNull()?.sender?.takeIf{it.isNotBlank()}?:messages.firstOrNull()?.let{s.smsListContent[SmsSourceRef.Canonical(it.id)]?.sender}?.takeIf{it.isNotBlank()}
        ?:observations.firstOrNull()?.let{observationContent(it.source)?.sender}?.takeIf{it.isNotBlank()}
        ?:s.gateway?.approvedSenders?.filter{it.isNotBlank()}?.singleOrNull()?:t("SMS receipt")
    val missing=allMessages.any{SmsSourceRef.Canonical(it.id) !in s.smsListContent}||allObservations.any{it.source !in s.smsListContent}
    val canonicalMissing=allMessages.any{SmsSourceRef.Canonical(it.id) !in s.smsListContent}
    val observationMissing=allObservations.any{it.source !in s.smsListContent}
    val queueUnknown=s.filter=="all"&&(!queueVisible||s.queuedUnavailable||s.queuedObservations==null)
    val partial=s.smsScanError||s.observationUnavailable||missing||s.messages?.nextCursor!=null||s.observations?.nextCursor!=null||queueUnknown
    val canonicalCount=if(query.isNotBlank())messages.size else s.messages?.totalCount?:0
    val observationCount=if(query.isNotBlank())observations.size else s.observations?.totalCount?:0
    // The sources have distinct IDs; an unacknowledged upload may occur in both.
    // Do not imply that their sum is a count of unique SMS messages.
    val multiSource=listOf(canonicalCount,observationCount,queued.size).count{it>0}>1
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(20.dp,4.dp,20.dp,26.dp)){
        item{OverviewTitle(t("SMS"));key(s.filter){Search(if(s.filter=="queued")s.queuedSearch else s.smsListSearch,m::search,m::searchSubmit,t("Search M-Money"),s.busy)}}
        item{ListingToolbar(m,onExport)}
        if(s.smsListSearch.isNotBlank()||s.queuedSearch.isNotBlank())item{Text(t("Clear SMS search to download source metadata. Message text is not included."),Modifier.padding(bottom=8.dp),fontSize=14.sp,lineHeight=22.sp,color=BuriTheme.Muted)}
        item{Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(vertical=12.dp),horizontalArrangement=Arrangement.spacedBy(10.dp)){
            FilterChipIcon(t("All"),R.drawable.ic_sms,s.filter=="all"){m.setFilter("all")}
            FilterChipIcon(t("Queued"),R.drawable.ic_clock,s.filter=="queued"){m.setFilter("queued")}
            FilterChipIcon(t("Duplicates"),R.drawable.ic_history,s.filter=="duplicate"){m.setFilter("duplicate")}
        }}
        item{CountLine(t("%1\$s · %2\$s",sender,(if(s.filter=="queued")null else messages.firstOrNull()?.simLabel)?:t("Unavailable")),
            if(s.filter=="queued")if(queueVisible&&!s.queuedUnavailable&&s.queuedObservations!=null)queued.size.toString()else t("Unavailable")
            else if(s.observationUnavailable||queueUnknown||multiSource||(query.isNotBlank()&&(partial||s.smsScanRunning)))t("Unavailable")else (canonicalCount+observationCount+queued.size).toString())}
        if(s.filter=="queued"){
            itemsIndexed(queued,key={_,row->"queued:"+row.id}){index,row->QueuedSmsRow(row,index,queued.lastIndex)}
            if(!queueVisible||s.queuedUnavailable)item{Text(t("SMS sync unavailable."),color=BuriTheme.Warn)}
            else if(s.queuedObservations==null)item{if(s.busy||s.smsScanRunning)BuriInlineLoading("Loading records")else Text(t("Queue state unavailable"),color=BuriTheme.Warn)}
            else if(queued.isEmpty())item{Empty(t("No messages"));if(s.queuedSearch.isNotBlank())Text(t("Try another search."),color=BuriTheme.Muted)}
        }else{
        if(s.filter=="all")itemsIndexed(queued,key={_,row->"queued:"+row.id}){index,row->QueuedSmsRow(row,index,queued.lastIndex)}
        itemsIndexed(messages,key={_,sms->"canonical:"+sms.id}){index,sms->
            val content=s.smsListContent[SmsSourceRef.Canonical(sms.id)]
            Box(Modifier.fillMaxWidth().background(BuriTheme.Group,rowShape(index==0,index==messages.lastIndex)).clickable(enabled=!s.busy,role=SemanticRole.Button){m.openSms(SmsSourceRef.Canonical(sms.id))}.padding(horizontal=16.dp,vertical=16.dp)){
                Row(Modifier.fillMaxWidth().heightIn(min=52.dp),verticalAlignment=Alignment.Top){
                    Box(Modifier.size(42.dp).background(BuriTheme.Tone,CircleShape),contentAlignment=Alignment.Center){Glyph(R.drawable.ic_sms,null,BuriTheme.Text,23)};Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)){
                        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){SingleLineName(content?.sender?.ifBlank{t("SMS receipt")}?:t("SMS receipt"),Modifier.weight(1f));Spacer(Modifier.width(8.dp));Text(sms.at,fontSize=12.sp,color=BuriTheme.Muted)}
                        content?.body?.takeIf{it.isNotEmpty()}?.let{Spacer(Modifier.height(6.dp));Text(QueuedObservationPreview.from(it),fontSize=16.sp,color=BuriTheme.Muted,maxLines=2,overflow=TextOverflow.Ellipsis,lineHeight=24.sp)}
                        val delivery=Presentation.receipt(sms.state)
                        Row(Modifier.padding(top=6.dp),verticalAlignment=Alignment.CenterVertically){Glyph(stateIcon(delivery.icon),delivery.meaning,stateTone(delivery.tone),15);Spacer(Modifier.width(6.dp));Text(t(delivery.label),fontSize=13.sp,color=stateTone(delivery.tone))}
                    }
                }
                if(index<messages.lastIndex)HorizontalDivider(Modifier.align(Alignment.BottomCenter),color=Color.White.copy(alpha=.08f))
            }
        }
        moreButton((s.messages?.nextCursor?:"preview-pending".takeIf{canonicalMissing}).takeIf{query.isBlank()&&!s.smsScanError&&s.smsListContent.size<100},s.busy||s.smsScanRunning,m::more,"sms-canonical-pagination",autoEnabled=!s.offline&&s.error==null)
        itemsIndexed(observations,key={_,row->"observation:"+row.source.id}){index,row->
            val content=observationContent(row.source)
            Box(Modifier.fillMaxWidth().background(BuriTheme.Group,rowShape(index==0,index==observations.lastIndex)).clickable(enabled=!s.busy,role=SemanticRole.Button){m.openSms(row.source)}.padding(horizontal=16.dp,vertical=16.dp)){
                Row(Modifier.fillMaxWidth().heightIn(min=52.dp),verticalAlignment=Alignment.Top){
                    Box(Modifier.size(42.dp).background(BuriTheme.Tone,CircleShape),contentAlignment=Alignment.Center){Glyph(R.drawable.ic_sms,null,BuriTheme.Text,23)};Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)){
                        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){SingleLineName(content?.sender?.ifBlank{t("SMS receipt")}?:t("SMS receipt"),Modifier.weight(1f));Spacer(Modifier.width(8.dp));Text(row.retainedAt,fontSize=12.sp,color=BuriTheme.Muted)}
                        content?.body?.takeIf{it.isNotEmpty()}?.let{Spacer(Modifier.height(6.dp));Text(QueuedObservationPreview.from(it),fontSize=16.sp,color=BuriTheme.Muted,maxLines=2,overflow=TextOverflow.Ellipsis,lineHeight=24.sp)}
                        val processing=s.observationProcessing[row.source]
                        Text(t(observationProcessingLabel(processing)),Modifier.padding(top=6.dp),fontSize=13.sp,
                            color=if(processing?.status in setOf("needs_review","conflict"))BuriTheme.Warn else BuriTheme.Muted)
                    }
                }
            }
        }
        moreButton((s.observations?.nextCursor?:"preview-pending".takeIf{observationMissing}).takeIf{query.isBlank()&&!s.smsScanError&&s.smsListContent.size<100},s.busy||s.smsScanRunning,m::moreObservations,"sms-observation-pagination",autoEnabled=!s.offline&&s.error==null)
        if(s.observationUnavailable||(s.filter=="all"&&(!queueVisible||s.queuedUnavailable)))item{Text(t("SMS sync unavailable."),color=BuriTheme.Warn)}
        else if(queueUnknown&&!(query.isNotBlank()&&s.smsScanRunning))item{if(s.busy)BuriInlineLoading("Loading records")else Text(t("Queue state unavailable"),color=BuriTheme.Warn)}
        if(s.smsScanError)item{Text(t("Original SMS unavailable."),color=BuriTheme.Warn)}
        if(query.isBlank()&&s.smsListContent.size>=100&&partial)item{Text(t("Messages incomplete for this account and phone."),color=BuriTheme.Warn)}
        if(query.isNotBlank()&&s.smsScanRunning)item{BuriInlineLoading("Searching messages")}
        else if(query.isNotBlank()&&partial)item{Text(t("Search incomplete for this account and phone."),color=BuriTheme.Warn)}
        if(messages.isEmpty()&&observations.isEmpty()&&queued.isEmpty()&&!partial&&!s.smsScanRunning)item{
            Empty(t(if(query.isNotBlank())"No matching messages on this account and phone." else "No messages"));if(query.isNotBlank())Text(t("Try another search."),color=BuriTheme.Muted)}
        }
    }
}
@Composable private fun SettingRow(icon:Int,title:String,subtitle:String?=null,enabled:Boolean=true,click:()->Unit){
    val t=LocalUiText.current
    val action=focusAction("setting:$icon",click)
    Row(action.modifier.fillMaxWidth().heightIn(min=58.dp).clickable(enabled=enabled,role=SemanticRole.Button,onClick=action.click).semantics(mergeDescendants=true){}.padding(vertical=16.dp),verticalAlignment=Alignment.CenterVertically){
        Box(Modifier.size(42.dp).background(BuriTheme.Tone,CircleShape),contentAlignment=Alignment.Center){Glyph(icon,null,if(enabled)BuriTheme.Text else BuriTheme.Muted,23)};Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)){Text(title,fontSize=19.sp,maxLines=2,overflow=TextOverflow.Ellipsis,lineHeight=27.sp);if(subtitle!=null){Spacer(Modifier.height(5.dp));Text(subtitle,fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)}}
        Glyph(R.drawable.ic_arrow,null,BuriTheme.Muted,18)
    }
}
@Composable private fun SettingsScreen(s:UiState,m:BuriController,onPermissions:()->Unit,onPhoneSettings:()->Unit,onNotifications:()->Unit,onBatteryOptimization:()->Unit){
    val t=LocalUiText.current
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(20.dp,4.dp,20.dp,26.dp)){
        item{OverviewTitle(t("Settings"))}
        item{Row(Modifier.fillMaxWidth().clickable(enabled=!s.busy){m.openSheet(Sheet.PROFILE)}.padding(vertical=20.dp),verticalAlignment=Alignment.CenterVertically){
            Avatar(s.operator?.name.orEmpty(),62,initialsSize=21);Spacer(Modifier.width(16.dp));Column(Modifier.weight(1f)){SingleLineName(s.operator?.name.orEmpty(),size=24);Text(t(if(s.operator?.role==Role.ADMIN)"Admin" else "Staff"),fontSize=14.sp,color=BuriTheme.Muted)};Glyph(R.drawable.ic_arrow,null,BuriTheme.Muted,18)
        }}
        item{Column(Modifier.fillMaxWidth().background(BuriTheme.Group,RoundedCornerShape(24.dp)).padding(horizontal=16.dp,vertical=2.dp)){
            if(m.allows(Capability.STAFF)){SettingRow(R.drawable.ic_members,t("Staff access"),s.staff?.totalCount?.let{t("%1\$d accounts",it)},enabled=!s.busy,click={m.openSheet(Sheet.STAFF)});HorizontalDivider(color=Color.White.copy(alpha=.08f))}
            if(BuildConfig.IS_GATEWAY&&s.operator?.role==Role.ADMIN){SettingRow(R.drawable.ic_device,t("Gateway"),s.gateway?.let{t(GatewayHealth.describe(it).title)},enabled=!s.busy,click={m.openSheet(Sheet.GATEWAY)});HorizontalDivider(color=Color.White.copy(alpha=.08f))}
            if(m.allows(Capability.STAFF)){SettingRow(R.drawable.ic_history,t("Activity"),enabled=!s.busy,click={m.openSheet(Sheet.AUDIT)});HorizontalDivider(color=Color.White.copy(alpha=.08f))}
            val canManageSms=BuildConfig.IS_GATEWAY&&s.operator?.role==Role.ADMIN&&m.allows(Capability.GATEWAY)
            SettingRow(R.drawable.ic_sms,t("SMS permission"),t(if(!canManageSms)"Unavailable" else if(m.smsAccessGranted)"Granted" else "Required"),enabled=canManageSms&&!s.busy,click={if(m.smsAccessGranted)onPhoneSettings()else onPermissions()});HorizontalDivider(color=Color.White.copy(alpha=.08f))
            if(canManageSms){
                SettingRow(R.drawable.ic_sms,t("Sync notifications"),t(when(m.notificationAccessGranted){true->"Allowed";false->"Required";else->"Checking access"}),enabled=!s.busy,click=onNotifications);HorizontalDivider(color=Color.White.copy(alpha=.08f))
                SettingRow(R.drawable.ic_device,t("Battery optimization"),t(when(m.batteryExemptionGranted){true->"Unrestricted";false->"Optimized";else->"Checking access"}),enabled=!s.busy,click=onBatteryOptimization);HorizontalDivider(color=Color.White.copy(alpha=.08f))
                val syncLabel=when(m.continuousSyncProblem){
                    "authorization_required"->"Authorization required";"paused"->"Sync paused"
                    "permission_required"->"SMS access required";"notification_permission_required"->"Notification access required"
                    "connection_waiting"->"Waiting for connection";"start_not_allowed"->"Open the app to resume sync"
                    "receiver_retired"->"Receiver retired";"sync_unconfirmed"->"Sync unconfirmed"
                    else->if(m.continuousSyncRunning==true)"Sync is running" else "Starting sync"
                }
                SettingRow(R.drawable.ic_sync,t("Background sync"),t(syncLabel),enabled=!s.busy,click={m.openSheet(Sheet.GATEWAY)});HorizontalDivider(color=Color.White.copy(alpha=.08f))
            }
            SettingRow(R.drawable.ic_lock,t("Change passcode"),enabled=!s.busy,click={m.openSheet(Sheet.PIN)});HorizontalDivider(color=Color.White.copy(alpha=.08f))
            SettingRow(R.drawable.ic_help,t("Help"),enabled=!s.busy,click={m.openSheet(Sheet.HELP)})
        }}
        item{Column(Modifier.fillMaxWidth().padding(top=35.dp,bottom=15.dp),horizontalAlignment=Alignment.CenterHorizontally){RoundAction(R.drawable.ic_out,t("Sign out"),m::logout,!s.busy,56);Spacer(Modifier.height(20.dp));Text("BuriMunsi · Collect",fontSize=12.sp,color=BuriTheme.Muted)}}
    }
}
@Composable internal fun Entry(label:String,value:String,change:(String)->Unit,phone:Boolean=false,pin:Boolean=false,enabled:Boolean=true,
    imeAction:ImeAction=ImeAction.Next,onDone:(()->Unit)?=null,
    fieldFocus:FocusRequester?=null,nextFocus:FocusRequester?=null,errorText:String?=null,revealPin:Boolean=false,placeholder:String?=null){
    val t=LocalUiText.current;var visible by remember{mutableStateOf(false)}
    val keyboard=LocalSoftwareKeyboardController.current;val focus=LocalFocusManager.current
    val action:()->Unit={if(enabled){if(imeAction==ImeAction.Next){if(nextFocus!=null)nextFocus.requestFocus()else focus.moveFocus(FocusDirection.Next)}else{keyboard?.hide();focus.clearFocus();onDone?.invoke()}}}
    Column(Modifier.fillMaxWidth()){
        Text(label,fontSize=15.sp,lineHeight=21.sp,color=BuriTheme.Muted);Spacer(Modifier.height(9.dp))
        OutlinedTextField(value,change,Modifier.fillMaxWidth().heightIn(min=60.dp).semantics{contentDescription=label}.then(fieldFocus?.let{Modifier.focusRequester(it)}?:Modifier).onPreviewKeyEvent{
            if(it.key==Key.Enter||it.key==Key.NumPadEnter){if(it.type==KeyEventType.KeyUp)action();true}else false
        },singleLine=true,enabled=enabled,isError=errorText!=null,
            textStyle=LocalTextStyle.current.copy(fontSize=19.sp,lineHeight=27.sp),
            placeholder={Text(placeholder?.let{t(it)}?:if(pin)t("4 digits")else if(phone)t("07… or +250…")else "",color=BuriTheme.Muted)},
            supportingText=if(errorText!=null){{Text(t(errorText))}}else null,
            shape=RoundedCornerShape(17.dp),visualTransformation=if(pin&&!visible)PasswordVisualTransformation()else VisualTransformation.None,
            keyboardOptions=KeyboardOptions(keyboardType=if(pin)KeyboardType.NumberPassword else if(phone)KeyboardType.Phone else KeyboardType.Text,autoCorrectEnabled=false,imeAction=imeAction),
            keyboardActions=KeyboardActions(onNext={action()},onDone={action()}),
            trailingIcon=if(pin&&revealPin){{IconButton({visible=!visible},enabled=enabled){Glyph(R.drawable.ic_eye,if(visible)t("Hide passcode")else t("Show passcode"))}}}else null,
            colors=OutlinedTextFieldDefaults.colors(focusedContainerColor=BuriTheme.Input,unfocusedContainerColor=BuriTheme.Input,focusedBorderColor=BuriTheme.Blue,unfocusedBorderColor=Color.Transparent))
    }
}
@Composable private fun Login(busy:Boolean,login:(String,String)->Unit,support:()->Unit,supportAvailable:Boolean){
    val t=LocalUiText.current
    var phone by remember{mutableStateOf("")};var pin by remember{mutableStateOf("")}
    val pinFocus=remember{FocusRequester()}
    val ready=runCatching{Values.phone(phone);Values.pin(pin)}.isSuccess
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(20.dp,21.dp,20.dp,30.dp)){
        item{Brand();Spacer(Modifier.height(35.dp))}
        item{Text(t("Welcome\nback."),fontSize=56.sp,fontWeight=FontWeight.SemiBold,lineHeight=58.sp,letterSpacing=(-2.4).sp);Spacer(Modifier.height(34.dp))}
        // Keep both fields composed while keyboard-driven scrolling moves focus between them.
        item{
            Entry(t("Phone number"),phone,{phone=it.take(40)},phone=true,enabled=!busy,nextFocus=pinFocus,
                errorText=if(phone.isNotEmpty()&&runCatching{Values.phone(phone)}.isFailure)"Enter a valid phone number." else null);Spacer(Modifier.height(20.dp))
            Entry(t("Passcode"),pin,{pin=it.filter{ch->ch in '0'..'9'}.take(4)},pin=true,revealPin=true,enabled=!busy,imeAction=ImeAction.Done,fieldFocus=pinFocus,onDone={if(ready&&!busy){login(phone,pin);pin=""}});Spacer(Modifier.height(29.dp))
        }
        item{Primary(t("Sign in"),{login(phone,pin);pin=""},ready&&!busy,icon=R.drawable.ic_arrow,iconTrailing=true,working=busy)}
        item{TextButton(support,Modifier.fillMaxWidth().heightIn(min=48.dp).padding(top=12.dp),enabled=supportAvailable&&!busy){Text(t("Contact admin"),color=if(supportAvailable&&!busy)BuriTheme.Blue else BuriTheme.Muted,fontSize=15.sp)}}
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun Sheets(s:UiState,m:BuriController,onSupport:()->Unit,onPermissions:()->Unit,onPhoneSettings:()->Unit,
    onPickMemberFile:()->Unit,onPreviewMemberFile:(String)->Unit,onTakeMemberPhoto:()->Unit,onPickMemberPhoto:()->Unit,onExport:()->Unit){
    val t=LocalUiText.current
    val sheet=s.sheet?:return
    val title=when(sheet){Sheet.PROFILE->t("Profile");Sheet.PIN->t("Change passcode");Sheet.HELP->t("Help");Sheet.ALLOCATE->t("Allocate");Sheet.ENROLL->t("Add member");Sheet.STAFF->t("Staff access");Sheet.STAFF_EDIT->if(s.selectedStaff==null)t("Add staff")else t("Edit staff");Sheet.REMOVE_STAFF->t("Remove access?");Sheet.GATEWAY->t("Gateway");Sheet.REPLACE_DEVICE->t("Replace receiver");Sheet.RAW->s.raw?.sender?.takeIf{it.isNotBlank()}?:t("SMS receipt");Sheet.MEMBER_DETAILS->t("Member details");Sheet.HISTORY->t("Contribution history");Sheet.AUDIT->t("Activity log");Sheet.FILTERS->t("Filters")}
    key(sheet,s.sheetId){
    val latest=rememberUpdatedState(s)
    val sheetState=rememberModalBottomSheetState(skipPartiallyExpanded=true,confirmValueChange={target->
        if(target==SheetValue.Hidden&&(latest.value.busy||latest.value.draftDirty)){
            if(!latest.value.busy)m.closeSheet()
            false
        }else true
    })
    val keyboard=LocalSoftwareKeyboardController.current
    val imeVisible=WindowInsets.ime.getBottom(LocalDensity.current)>0
    CompositionLocalProvider(LocalBuriRouteColors provides BuriRouteColors(Color(0xFFB0B0B5),Color(0xFF8CA2FF),Color(0xFF2C2C2F),Color(0xFF242426)),LocalBuriRoute provides Route.SETTINGS){
    ModalBottomSheet(onDismissRequest=m::closeSheet,sheetState=sheetState,containerColor=Color(0xFF1C1C1E),contentColor=BuriTheme.Text,shape=RoundedCornerShape(topStart=32.dp,topEnd=32.dp),scrimColor=Color.Black.copy(alpha=.62f),dragHandle={
        Box(Modifier.fillMaxWidth().padding(top=11.dp,bottom=3.dp),contentAlignment=Alignment.Center){Box(Modifier.size(width=34.dp,height=4.dp).background(Color(0xFF505054),RoundedCornerShape(4.dp)))}
    }){
        Column(Modifier.fillMaxWidth().heightIn(max=LocalConfiguration.current.screenHeightDp.dp*.94f).imePadding().semantics{paneTitle=title}.onPreviewKeyEvent{
            if(it.key==Key.Escape){if(it.type==KeyEventType.KeyUp){if(imeVisible)keyboard?.hide()else m.closeSheet()};true}else false
        }){
            Row(Modifier.fillMaxWidth().heightIn(min=65.dp).padding(start=22.dp,end=12.dp,top=7.dp,bottom=10.dp),verticalAlignment=Alignment.CenterVertically){
                Text(title,Modifier.weight(1f).semantics{heading()},fontSize=30.sp,fontWeight=FontWeight.SemiBold,maxLines=2,overflow=TextOverflow.Ellipsis,lineHeight=38.sp)
                IconButton(m::closeSheet,enabled=!s.busy,modifier=Modifier.testTag("panel-close")){Glyph(R.drawable.ic_close,t("Close"))}
            }
            if(s.discardRequested)DiscardPrompt(s,m)
            if(m.operation!=UiOperation.NONE&&!(m.operation==UiOperation.EXPORT&&m.exportFeedback!=null))BuriWorkingStrip(m.operation,m.operationLabel)else if(m.operation==UiOperation.NONE&&s.busy)BuriInlineLoading("Working")
            m.exportFeedback?.takeIf{m.screenGate==ScreenGate.OPEN&&m.presentation.showRecords}?.let{BuriExportFeedback(it,m::cancelExport,m::dismissExportFeedback)}
            s.error?.let{message->
                Text(t(message),Modifier.padding(horizontal=24.dp,vertical=8.dp).semantics{liveRegion=LiveRegionMode.Polite},color=BuriTheme.Bad)
                if(sheet in setOf(Sheet.STAFF,Sheet.AUDIT,Sheet.ALLOCATE,Sheet.GATEWAY,Sheet.HISTORY,Sheet.MEMBER_DETAILS))
                    TextButton(m::refresh,enabled=!s.busy,modifier=Modifier.padding(horizontal=16.dp)){Text(t("Retry loading"))}
            }
            // Bounded list avoids unbounded nested-scroll measurement on compact phones and IME.
            val blockedContent=if(s.discardRequested)Modifier.clearAndSetSemantics{}.pointerInput(Unit){
                awaitPointerEventScope{while(true)awaitPointerEvent(PointerEventPass.Initial).changes.forEach{it.consume()}}
            }else Modifier
            Box(Modifier.fillMaxWidth().weight(1f,fill=false).then(blockedContent)){
                key(sheet,s.sheetId){when(sheet){
                    Sheet.PROFILE->Panel(footer={Primary(t("Change passcode"),{m.openSheet(Sheet.PIN)},!s.busy)}){
                        item{FactGroup(listOf(t("Name") to s.operator?.name.orEmpty(),t("Phone number") to s.operator?.phone.orEmpty()),BuriTheme.Group)}
                    }
                    Sheet.PIN->PinPanel(s.busy,s.pending,m::changePin)
                    Sheet.HELP->Panel(footer={Primary(t("WhatsApp"),onSupport,m.supportPhone!=null&&!s.busy)}){item{Text(m.supportPhone?:t("Unavailable"),fontSize=26.sp,lineHeight=34.sp)}}
                    Sheet.ALLOCATE->AllocatePanel(s,m)
                    Sheet.ENROLL->SmartEnrollPanel(s,m,onPickMemberFile,onPreviewMemberFile,onTakeMemberPhoto,onPickMemberPhoto)
                    Sheet.STAFF->Panel{
                        item{ListingToolbar(m,onExport)}
                        item{Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){Text(s.staff?.totalCount?.let{t("%1\$d staff",it)}?:t("Unavailable"),Modifier.weight(1f),color=BuriTheme.Muted,fontSize=14.sp);RoundAction(R.drawable.ic_plus,t("Add staff"),{m.openSheet(Sheet.STAFF_EDIT)},!s.busy&&!s.offline&&!s.pending,48)}}
                        val staff=s.staff?.items.orEmpty()
                        if(staff.isNotEmpty())item{Column(Modifier.fillMaxWidth().background(BuriTheme.Group,RoundedCornerShape(24.dp)).padding(horizontal=16.dp,vertical=2.dp)){
                            staff.forEachIndexed{index,person->
                                SettingRow(R.drawable.ic_members,person.name,t("%1\$s · %2\$s",person.phone,t(if(person.active)"Active" else "Disabled")),enabled=!s.busy){m.openSheet(Sheet.STAFF_EDIT,person.id)}
                                if(index<staff.lastIndex)HorizontalDivider(color=Color.White.copy(alpha=.08f))
                            }
                        }}
                        if(s.staff?.items?.isEmpty()==true)item{Empty(t("No staff"))}
                        if(s.staff==null&&s.busy)item{BuriSkeletonRows(3)}
                        moreButton(s.staff?.nextCursor,s.busy,m::more,autoEnabled=!s.offline&&s.error==null)
                    }
                    Sheet.STAFF_EDIT->StaffPanel(s,m)
                    Sheet.REMOVE_STAFF->Panel(footer={Primary(t("Remove access"),{m.staffAction("remove")},!s.busy&&!s.offline&&!s.pending,danger=true,working=s.busy&&m.operation==UiOperation.COMMAND)}){
                        item{SingleLineName(s.selectedStaff?.name.orEmpty(),Modifier.fillMaxWidth(),20)}
                        item{Text(t("Sign-in will stop. Financial history remains."),fontSize=15.sp,color=BuriTheme.Muted,lineHeight=23.sp)}
                    }
                    Sheet.GATEWAY->GatewayPanel(s,m,onPermissions)
                    Sheet.REPLACE_DEVICE->ReplaceReceiverPanel(s,m,onPermissions)
                    Sheet.RAW->RawPanel(s,m)
                    Sheet.MEMBER_DETAILS->{
                        val member=s.member
                        Panel(footer=if(member!=null&&s.operator?.role==Role.ADMIN&&m.allows(Capability.ENROLL)){{Primary(if(member.active)t("Deactivate membership") else t("Reactivate membership"),{m.setMemberActive(!member.active)},!s.busy&&!s.offline&&!s.pending,secondary=true,working=s.busy&&m.operation==UiOperation.COMMAND)}}else null){
                            member?.let{item{FactGroup(listOf(t("Name") to it.name,t("MoMo number") to it.phone,t("Membership") to if(it.active)t("Active") else t("Inactive")),BuriTheme.Group)}}
                        }
                    }
                    Sheet.HISTORY->Panel{
                        item{ListingToolbar(m,onExport)}
                        s.payment?.let{p->item{Fact(t("FT Id"),p.ftId?:t("Unavailable"));Fact(t("from"),p.payerNameRaw);Fact(t("MoMo"),p.payerPhoneRaw);Fact(t("Provider time"),p.atRaw);Fact(t("Current status"),t(PaymentPresentation.payment(p).label))}}
                        item{Section(t("Recorded events"));Text(t("Only canonical transaction and ledger records are shown. A transaction record is not confirmation of member credit."),fontSize=15.sp,color=BuriTheme.Muted,lineHeight=23.sp)}
                        if(s.historyOffline)item{Text(t("Saved history · may be out of date")+(s.historySavedAt?.let{" · "+historyTime(java.time.Instant.ofEpochMilli(it).toString(),LocalUiText.current.locale)}?:""),color=BuriTheme.Warn,fontSize=14.sp,lineHeight=22.sp)}
                        if(s.history==null&&s.error==null)item{if(s.busy){BuriInlineLoading("Loading recorded events");BuriSkeletonRows(3)}else Empty(t("History has not loaded."));if(!s.busy)TextButton(m::refresh){Text(t("Retry loading"))}}
                        items(s.history?.items.orEmpty(),key={it.id}){event->
                            Column(Modifier.fillMaxWidth().background(BuriTheme.Raised,RoundedCornerShape(20.dp)).padding(18.dp)){
                                Text(if(event.kind=="transaction_recorded")t("Transaction recorded") else t("Ledger entry recorded"),fontSize=19.sp,fontWeight=FontWeight.Medium,lineHeight=27.sp)
                                Spacer(Modifier.height(6.dp));Text(historyTime(event.recordedAt,LocalUiText.current.locale),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)
                                event.amountRwf?.let{amount->
                                    Spacer(Modifier.height(10.dp));Text(t("Ledger change (RWF)"),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)
                                    MoneyText(amount,Modifier.fillMaxWidth(),22,positiveSign=true,showHint=true)
                                }
                            }
                        }
                        if(s.history?.items?.isEmpty()==true)item{Empty(t("No recorded events in this response"))}
                        s.history?.let{page->item{Text(t("%1\$d of %2\$d recorded events · %3\$s",page.items.size,page.totalCount,t(listingSortLabel(m.listingQuery.sort))),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)}}
                        moreButton(s.history?.nextCursor,s.busy,m::more,autoEnabled=!s.offline&&s.error==null)
                    }
                    Sheet.AUDIT->Panel{
                        item{ListingToolbar(m,onExport)}
                        items(s.audit?.items.orEmpty(),key={it.id}){a->Column(Modifier.fillMaxWidth().padding(vertical=10.dp)){SingleLineName(a.action);Spacer(Modifier.height(5.dp));Text(a.at,color=BuriTheme.Muted,fontSize=14.sp,lineHeight=22.sp)}}
                        if(s.audit?.items?.isEmpty()==true)item{Empty()}
                        if(s.audit==null&&s.busy)item{BuriSkeletonRows(3)}
                        moreButton(s.audit?.nextCursor,s.busy,m::more,autoEnabled=!s.offline&&s.error==null)
                    }
                    Sheet.FILTERS->if(m.listingTarget!=null)ListingFiltersPanel(m)else FiltersPanel(s,m)
                }}
            }
        }
    }
    }
}

}

@Composable private fun DiscardPrompt(s:UiState,m:BuriController){
    val t=LocalUiText.current;val keep=remember{FocusRequester()}
    val keyboard=LocalSoftwareKeyboardController.current;val focus=LocalFocusManager.current
    LaunchedEffect(Unit){keyboard?.hide();focus.clearFocus();keep.requestFocus()}
    Column(Modifier.fillMaxWidth().background(Color(0xFF28282B)).padding(horizontal=24.dp,vertical=16.dp).semantics{liveRegion=LiveRegionMode.Assertive},verticalArrangement=Arrangement.spacedBy(8.dp)){
        Text(t("Discard unsaved changes?"),fontSize=18.sp,fontWeight=FontWeight.SemiBold,lineHeight=25.sp)
        Text(if(s.pending)t("An earlier action may have been submitted. Discarding this draft does not cancel it. Check the previous action before retrying.") else t("Nothing has been submitted. Credentials will be cleared."),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=21.sp)
        Primary(t("Keep editing"),m::keepDraft,!s.busy,secondary=true,modifier=Modifier.focusRequester(keep))
        Primary(t("Discard changes"),m::discardDraft,!s.busy,danger=true)
    }
}

/** Server-authorized plaintext exists only while this explicitly opened panel is visible. */
private fun observationProcessingLabel(value:ObservationProcessing?):String=when(value?.status){
    "pending"->"Pending";"retrying"->"Retrying";"parsed"->"Parsed";"needs_review"->"Needs review"
    "conflict"->"Conflict";"duplicate"->"Duplicate";"security"->"Security message";"historical"->"Historical record"
    else->"Status unavailable"
}
@Composable private fun RawPanel(s:UiState,m:BuriController){
    val t=LocalUiText.current;val raw=s.raw
    val source=s.rawSource as? SmsSourceRef.Observation
    val processing=source?.let{s.observationProcessing[it]}
    Panel(footer=if(raw?.transactionId!=null&&s.rawDisclosure==RawDisclosureState.REVEALED){{Primary(t("Open contribution"),{m.navigate(Route.PAYMENT,raw.transactionId)},!s.busy)}}else null){
        if(source!=null){
            item{Column(verticalArrangement=Arrangement.spacedBy(8.dp)){
                Text(t(observationProcessingLabel(processing)),fontSize=16.sp,color=if(processing?.status in setOf("needs_review","conflict"))BuriTheme.Warn else BuriTheme.Text)
                Text(t("This status does not confirm a payment."),fontSize=13.sp,color=BuriTheme.Muted)
                s.observationRetryNotice?.let{Text(t(it),fontSize=14.sp,color=BuriTheme.Muted)}
                if(processing?.canRetry==true)Primary(t("Retry"),m::retryObservation,!s.busy)
            }}
        }
        if(raw!=null&&s.rawDisclosure==RawDisclosureState.REVEALED){
            item{CountLine(raw.at,raw.simLabel?:t("Unavailable"))}
            if(s.rawSource is SmsSourceRef.Observation&&s.observationHints?.hints?.isNotEmpty()==true){
                val rows=s.observationHints.hints.map{hint->t(if(hint.kind=="quoted_incoming_amount")"Amount shown in SMS"else "Reference shown in SMS") to hint.text}
                item{FactGroup(rows,BuriTheme.Group)}
            }
            item{SelectionContainer{Text(raw.body,Modifier.fillMaxWidth().background(Color(0xFF28282B),RoundedCornerShape(24.dp)).padding(22.dp),fontSize=19.sp,lineHeight=33.sp)}}
        }else if(s.busy||s.rawDisclosure==RawDisclosureState.LOADING)item{BuriInlineLoading("Loading original SMS")}
        else item{Text(t(s.rawError?:"Original SMS unavailable."),color=BuriTheme.Bad)}
    }
}
@Composable internal fun Panel(footer:(@Composable ()->Unit)?=null,content:LazyListScope.()->Unit){
    val memory=LocalUiFocusMemory.current;val scope=LocalUiFocusScope.current
    val position=memory.scrollPositions[scope]?:(0 to 0);val scroll=rememberLazyListState(position.first,position.second)
    LaunchedEffect(scope,scroll){snapshotFlow{scroll.firstVisibleItemIndex to scroll.firstVisibleItemScrollOffset}.distinctUntilChanged().collect{memory.scrollPositions[scope]=it}}
    Column(Modifier.fillMaxWidth()){
        LazyColumn(Modifier.fillMaxWidth().weight(1f,fill=false),state=scroll,contentPadding=PaddingValues(22.dp,0.dp,22.dp,20.dp),verticalArrangement=Arrangement.spacedBy(20.dp),content=content)
        if(footer!=null){HorizontalDivider(color=Color.White.copy(alpha=.08f));Box(Modifier.fillMaxWidth().padding(start=22.dp,end=22.dp,top=14.dp,bottom=25.dp)){footer()}}
    }
}
@Composable private fun PinPanel(busy:Boolean,pending:Boolean,save:(String,String,String)->Unit){
    val t=LocalUiText.current
    var current by remember{mutableStateOf("")};var next by remember{mutableStateOf("")};var confirm by remember{mutableStateOf("")}
    val ready=runCatching{Values.pin(current);Values.pin(next);require(next==confirm)}.isSuccess
    val nextFocus=remember{FocusRequester()};val confirmFocus=remember{FocusRequester()}
    Panel(footer={Primary(t("Save"),{save(current,next,confirm);current="";next="";confirm=""},ready&&!busy&&!pending,working=busy)}){
        item{Entry(t("Current passcode"),current,{current=it.filter{ch->ch in '0'..'9'}.take(4)},pin=true,enabled=!busy,nextFocus=nextFocus)}
        item{Entry(t("New passcode"),next,{next=it.filter{ch->ch in '0'..'9'}.take(4)},pin=true,enabled=!busy,fieldFocus=nextFocus,nextFocus=confirmFocus)}
        item{Entry(t("Confirm passcode"),confirm,{confirm=it.filter{ch->ch in '0'..'9'}.take(4)},pin=true,enabled=!busy,imeAction=ImeAction.Done,fieldFocus=confirmFocus,errorText=if(confirm.isNotEmpty()&&confirm!=next)"Passcodes do not match."else null)}
    }
}
@Composable private fun SmartConsent(label:String,checked:Boolean,enabled:Boolean,onChange:(Boolean)->Unit){
    val t=LocalUiText.current
    Row(Modifier.fillMaxWidth().heightIn(min=52.dp).toggleable(value=checked,enabled=enabled,role=SemanticRole.Checkbox,onValueChange=onChange),
        verticalAlignment=Alignment.CenterVertically){
        Checkbox(checked=checked,onCheckedChange=null,enabled=enabled)
        Text(t(label),Modifier.weight(1f),fontSize=15.sp,lineHeight=22.sp)
    }
}
@Composable private fun SmartOption(title:String,detail:String,enabled:Boolean,onClick:()->Unit){
    val t=LocalUiText.current
    Surface(onClick=onClick,enabled=enabled,shape=RoundedCornerShape(16.dp),color=BuriTheme.Group,modifier=Modifier.fillMaxWidth()){
        Row(Modifier.padding(18.dp),verticalAlignment=Alignment.CenterVertically){
            Text("+",Modifier.clearAndSetSemantics{},color=Color(0xFFFF733E),fontSize=26.sp,lineHeight=30.sp)
            Spacer(Modifier.width(14.dp))
            Column{Text(t(title),fontSize=17.sp,fontWeight=FontWeight.Bold);Text(t(detail),fontSize=14.sp,lineHeight=21.sp,color=BuriTheme.Muted)}
        }
    }
}

/** Additional onboarding screens stay inside the original Add member entry. */
@Composable private fun SmartEnrollPanel(s:UiState,m:BuriController,onPickFile:()->Unit,onPreviewFile:(String)->Unit,
    onTakePhoto:()->Unit,onPickPhoto:()->Unit){
    val t=LocalUiText.current;val o=s.onboarding;val candidate=o.candidate;val enabled=!s.busy&&!s.offline&&!s.pending
    val name=s.draft["name"].orEmpty();val phone=s.draft["phone"].orEmpty();val phoneFocus=remember{FocusRequester()}
    val normalized=runCatching{Values.phone(phone)}.getOrNull()
    val ready=Presentation.validName(name)&&normalized!=null&&
        (candidate==null||normalized.endsWith(candidate.last3))&&o.verifiedOwnership&&o.acceptedTerms&&o.consentRecorded
    val previewNeedsConsent=o.documentMimeType?.let{it.startsWith("image/")||it=="application/pdf"||it=="application/octet-stream"}?:true
    val verified=o.rows.filter{it.verified}
    when(o.step){
        SmartOnboardingStep.OPTIONS->Panel{
            item{Text(t("How would you like to add members?"),fontSize=20.sp,fontWeight=FontWeight.SemiBold,lineHeight=27.sp)}
            item{SmartOption("Suggested from MoMo","Search unmatched payer names and last 3 digits",enabled){m.onboardingSuggestions()}}
            item{SmartOption("Add manually","Enter a verified MoMo name and number",enabled,m::onboardingManual)}
            item{SmartOption("Take a photo of the list","Taking a photo sends it to OpenAI for extraction. Review members before saving.",enabled){m.onboardingPhoto();onTakePhoto()}}
            item{SmartOption("Choose a photo","Review extracted members before saving",enabled){m.onboardingImport();onPickPhoto()}}
            item{SmartOption("Import member list","Upload or scan, review, then register",enabled){m.onboardingImport();onPickFile()}}
        }
        SmartOnboardingStep.SUGGESTIONS->Panel{
            item{Text(t("Suggested members"),fontSize=23.sp,fontWeight=FontWeight.SemiBold)}
            item{Text(t("Search eligible MoMo payer names or the last three digits."),color=BuriTheme.Muted,fontSize=15.sp,lineHeight=22.sp)}
            item{Entry(t("Name or last three digits"),o.query,m::onboardingSearchQuery,enabled=!s.busy,imeAction=ImeAction.Search,onDone={m.onboardingSuggestions(o.query)})}
            item{Primary(t("Search"),{m.onboardingSuggestions(o.query)},enabled,secondary=true)}
            if(o.suggestionsLoaded&&o.suggestions.isEmpty())item{Empty(t("No eligible suggestions found."))}
            items(o.suggestions,key={it.candidateId}){candidate->
                Row(Modifier.fillMaxWidth().heightIn(min=64.dp).clickable(enabled=enabled){m.onboardingChoose(candidate.candidateId)}.padding(vertical=10.dp),verticalAlignment=Alignment.CenterVertically){
                    Column(Modifier.weight(1f)){Text(candidate.momoName,fontSize=17.sp,fontWeight=FontWeight.Medium);Text(t("MoMo number")+" ···"+candidate.last3+" · "+t("%1\$d message(s)",candidate.sourceCount),color=BuriTheme.Muted,fontSize=14.sp)}
                    Text(t("Select"),color=BuriTheme.Blue,fontSize=15.sp)
                }
            }
            if(o.nextCursor!=null)item{Primary(t("Load more"),{m.onboardingSuggestions(o.query,o.nextCursor)},enabled,secondary=true)}
            item{TextButton(m::onboardingOptions,enabled=!s.busy){Text(t("Back"),color=BuriTheme.Blue)}}
        }
        SmartOnboardingStep.MEMBER,SmartOnboardingStep.IMPORT_MEMBER->Panel(footer={
            Primary(t(if(o.step==SmartOnboardingStep.MEMBER)"Save member" else "Add verified row to batch"),
                {if(o.step==SmartOnboardingStep.MEMBER)m.onboardingSubmit(name,phone)else m.onboardingSaveRow(name,phone)},ready&&enabled,working=s.busy&&m.operation==UiOperation.COMMAND)
        }){
            if(candidate!=null)item{Text(t("Suggested from MoMo")+" ···"+candidate.last3,color=BuriTheme.Muted,fontSize=15.sp)}
            item{Entry(t("MoMo name"),name,{m.editDraft("name",it)},enabled=!s.busy,nextFocus=phoneFocus,placeholder="Registered full name")}
            item{Entry(t("MoMo number"),phone,{m.editDraft("phone",it)},phone=true,enabled=!s.busy,imeAction=ImeAction.Done,fieldFocus=phoneFocus,
                errorText=if(phone.isNotBlank()&&normalized!=null&&candidate!=null&&!normalized.endsWith(candidate.last3))"The number does not match the suggestion." else null)}
            item{SmartConsent("Full number and phone ownership verified",o.verifiedOwnership,enabled){m.onboardingConsent("ownership",it)}}
            item{SmartConsent("Member accepted the savings terms",o.acceptedTerms,enabled){m.onboardingConsent("terms",it)}}
            item{SmartConsent("Privacy notice and consent recorded",o.consentRecorded,enabled){m.onboardingConsent("consent",it)}}
            item{Text(t("Eligible earlier MoMo payments may be matched and credited automatically after you add this member."),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=21.sp)}
            item{TextButton(if(o.step==SmartOnboardingStep.IMPORT_MEMBER)m::onboardingImport else m::onboardingOptions,enabled=!s.busy){Text(t("Back"),color=BuriTheme.Blue)}}
        }
        SmartOnboardingStep.IMPORT->Panel(footer=if(verified.isNotEmpty()){{
            Primary(t("Register verified members")+" (${verified.size})",m::onboardingSubmitBatch,enabled,working=s.busy&&m.operation==UiOperation.COMMAND)
        }}else null){
            if(!o.photoCaptureFlow&&o.sourceKind==null&&o.rows.isEmpty()){
                item{Text(t("Import member list"),fontSize=23.sp,fontWeight=FontWeight.SemiBold)}
                item{SmartOption("Suggested from transaction payments","Search unmatched payer names and last 3 digits",enabled){m.onboardingSuggestions()}}
                item{SmartOption("Add manually","Enter a verified MoMo name and number",enabled,m::onboardingManual)}
                item{SmartOption("Take a photo of the list","Taking a photo sends it to OpenAI for extraction. Review members before saving.",enabled){m.onboardingPhoto();onTakePhoto()}}
                item{Primary(t("Choose a photo"),onPickPhoto,enabled,secondary=true)}
                item{Primary(t(if(o.documentSelected)"Choose another file" else "Choose a file"),onPickFile,enabled,secondary=true)}
                if(o.documentSelected){
                    item{Text(t("File selected"),color=BuriTheme.Muted,fontSize=14.sp)}
                    if(previewNeedsConsent)item{SmartConsent("I agree to send this document to OpenAI for text extraction",o.ocrConsent,enabled){m.onboardingConsent("ocr",it)}}
                    item{Primary(t("Preview members"),{o.documentUri?.let(onPreviewFile)},enabled&&(!previewNeedsConsent||o.ocrConsent),secondary=true)}
                }
            }else if(!o.photoCaptureFlow){
                if(o.rows.isEmpty())item{Empty(t("No members"))}
                else item{Text(t("Review extracted members before saving"),fontSize=18.sp,fontWeight=FontWeight.SemiBold)}
            }else if(o.sourceKind==null&&(o.photoPreviewPending||s.busy||(o.documentUri==null&&s.error==null))){
                item{BuriInlineLoading("Working")}
            }else if(o.sourceKind==null&&o.documentUri!=null){
                item{Primary(t("Retry"),{o.documentUri?.let(onPreviewFile)},enabled,secondary=true)}
            }else if(o.sourceKind!=null&&o.rows.isEmpty()){
                item{Empty(t("No members"))}
            }
            if(o.rows.isNotEmpty())item{Text(t("%1\$d rows · %2\$d verified",o.rows.size,verified.size),fontSize=16.sp,fontWeight=FontWeight.Medium)}
            items(o.rows,key={it.row}){row->
                Row(Modifier.fillMaxWidth().heightIn(min=64.dp).clickable(enabled=enabled){m.onboardingEditRow(row.row)}.padding(vertical=8.dp),verticalAlignment=Alignment.CenterVertically){
                    Column(Modifier.weight(1f)){Text(row.name.ifBlank{t("Unreadable name")},fontSize=17.sp);Text(row.phone?:t("Number missing"),color=BuriTheme.Muted,fontSize=14.sp)}
                    Text(t(if(row.verified)"Verified" else "Review"),color=if(row.verified)BuriTheme.Good else BuriTheme.Blue,fontSize=15.sp)
                }
            }
            item{TextButton(m::onboardingOptions,enabled=!s.busy){Text(t("Back"),color=BuriTheme.Blue)}}
        }
        SmartOnboardingStep.RESULTS->Panel(footer={Primary(t("Done"),m::closeSheet,!s.busy)}){
            item{Text(t("%1\$d members registered",o.created),fontSize=22.sp,fontWeight=FontWeight.SemiBold)}
            items(o.results,key={it.row}){result->Text(t("Row %1\$d: %2\$s",result.row,t(result.status.replace('_',' '))),fontSize=15.sp,lineHeight=22.sp)}
        }
    }
}
@Composable private fun AllocatePanel(s:UiState,m:BuriController){
    val t=LocalUiText.current;val query=s.draft["query"].orEmpty();val note=s.draft["note"].orEmpty();val p=s.payment?:return
    Panel(footer={Primary(t("Allocate"),{m.allocate(note)},s.selectedMember?.active==true&&Presentation.validNote(note)&&!s.busy&&!s.offline&&!s.pending,working=s.busy&&m.operation==UiOperation.COMMAND)}){
        item{CountLine(t("FT Id: %1\$s",p.ftId?:t("Unavailable")),p.amountRwf?.let{t("RWF %1\$s",money(it,t.locale))}?:t("Unavailable"))}
        item{Search(query,{m.editDraft("query",it)},{m.allocationSearch(query)},t("Find member"),s.busy)}
        items(s.members?.items.orEmpty().filter{it.active},key={it.id}){member->Row(Modifier.fillMaxWidth().selectable(selected=s.selectedMember?.id==member.id,enabled=!s.busy,role=SemanticRole.RadioButton,onClick={m.selectMember(member)}).padding(vertical=9.dp),verticalAlignment=Alignment.CenterVertically){
            RadioButton(selected=s.selectedMember?.id==member.id,onClick=null,enabled=!s.busy);Column(Modifier.weight(1f)){SingleLineName(member.name);Text(member.phone,fontSize=14.sp,color=BuriTheme.Muted)}
        }}
        if(s.members?.items?.none{it.active}==true)item{Empty(t("No eligible members. Change the search or ask an administrator."))}
        moreButton(s.members?.nextCursor,s.busy,m::more,autoEnabled=!s.offline&&s.error==null)
        item{Entry(t("Identification note"),note,{m.editDraft("note",it)},enabled=!s.busy,imeAction=ImeAction.Done,placeholder="How was the member confirmed?")}
        s.selectedMember?.let{chosen->item{Fact(t("Member"),chosen.name);Fact(t("MoMo"),chosen.phone)}}
        item{Text(t("Identification note: 8–500 characters. Credits once after confirmation."),fontSize=15.sp,color=BuriTheme.Muted)}
    }
}
@Composable private fun CheckRow(label:String,checked:Boolean,enabled:Boolean=true,change:(Boolean)->Unit){
    Row(Modifier.testTag("check:$label").fillMaxWidth().heightIn(min=48.dp).toggleable(value=checked,enabled=enabled,role=SemanticRole.Checkbox,onValueChange=change),verticalAlignment=Alignment.CenterVertically){Checkbox(checked,onCheckedChange=null,enabled=enabled);Spacer(Modifier.width(10.dp));Text(label,Modifier.weight(1f),fontSize=16.sp,lineHeight=24.sp)}
}
@Composable private fun StaffPanel(s:UiState,m:BuriController){
    val t=LocalUiText.current;val existing=s.selectedStaff
    if(s.sheetId!=null&&existing==null){Panel{item{Empty(t("Staff account unavailable. Go back and refresh the staff list."))}};return}
    val name=s.draft["name"]?:existing?.name.orEmpty();val phone=s.draft["phone"]?:existing?.phone.orEmpty();var pin by remember(existing?.id){mutableStateOf("")}
    val phoneFocus=remember{FocusRequester()};val pinFocus=remember{FocusRequester()};val enroll=s.draft["enroll"]=="true";val allocate=s.draft["allocate"]=="true"
    val normalized=runCatching{Values.phone(phone)}.getOrNull()
    // The server decides whether this account may retain its current credential.
    val ready=Presentation.validName(name)&&normalized!=null&&(pin.isEmpty()||runCatching{Values.pin(pin)}.isSuccess)
    Panel(footer={Primary(t(if(existing==null)"Create staff"else "Save changes"),{m.saveStaff(name,phone,pin,enroll,allocate);pin=""},ready&&!s.busy&&!s.offline&&!s.pending,working=s.busy&&m.operation==UiOperation.COMMAND)}){
        item{Entry(t("Name"),name,{m.editDraft("name",it)},enabled=!s.busy,nextFocus=phoneFocus,placeholder="Full name")}
        item{Entry(t("Phone number"),phone,{m.editDraft("phone",it)},phone=true,enabled=!s.busy,fieldFocus=phoneFocus,nextFocus=pinFocus)}
        item{Entry(t(if(existing==null)"Passcode"else "New passcode"),pin,{pin=it.filter{ch->ch in '0'..'9'}.take(4)},pin=true,enabled=!s.busy,imeAction=ImeAction.Done,fieldFocus=pinFocus,
            placeholder=if(existing!=null)"Leave blank to keep current"else "Leave blank for default passcode")}
        item{CheckRow(t("Allocate unmatched payments"),allocate,!s.busy){m.editDraft("allocate",it.toString())}}
        item{CheckRow(t("Enroll members"),enroll,!s.busy){m.editDraft("enroll",it.toString())}}
        if(existing!=null)item{Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp)){
            OutlinedButton({m.staffAction(if(existing.active)"disable"else "enable")},enabled=!s.busy&&!s.offline&&!s.pending){Text(t(if(existing.active)"Disable"else "Enable"))}
            OutlinedButton(m::requestRemoveStaff,enabled=!s.busy&&!s.offline){Text(t("Remove"))}
        }}
    }
}
@Composable private fun GatewayPanel(s:UiState,m:BuriController,onPermissions:()->Unit){
    val t=LocalUiText.current;val g=s.gateway;val health=GatewayHealth.describe(g)
    if(g==null){Panel{item{if(s.busy){BuriInlineLoading("Loading records");BuriSkeletonRows(2)}else Empty(t("Status unavailable"))}};return}
    if(g.observationMode){
        Panel {
            item{Text(t(health.title),fontSize=24.sp,fontWeight=FontWeight.SemiBold)}
            item{FactGroup(listOf(
                t("SMS permission") to t(if(m.smsAccessGranted)"Granted" else "Required"),
                t("Sender") to (g.approvedSenders?.joinToString(", ")?:t("Unavailable")),
                t("Sync") to t(if(health.code in setOf("permissions","waiting","reauthorize"))"Blocked" else if(g.captureEnabled)"Listening" else "Paused"),
                t("Queued") to (if(g.pending>=0)g.pending.toString()else t("Unavailable"))
            ),BuriTheme.Group)}
            item{Text(t(health.explanation),fontSize=15.sp,color=BuriTheme.Muted)}
            if(health.needsPermission||m.receivingPermissionsRequired)item{OutlinedButton(onPermissions,enabled=!s.busy){Text(t("SMS permission"))}}
            if(g.authorized)item{Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp)){
                if(!g.captureEnabled&&health.canResume&&!m.receivingPermissionsRequired)OutlinedButton({m.setPaused(false)},enabled=!s.busy){Text(t("Resume"))}
                OutlinedButton(m::syncReceiver,enabled=!s.busy&&!s.offline){Text(t("Sync"))}
            }}
        }
        return
    }
    if(!g.authorized){
        Panel{item{Text(t(health.title),fontSize=24.sp,fontWeight=FontWeight.SemiBold)}
            item{Text(t(health.explanation),fontSize=15.sp,color=BuriTheme.Muted)}}
        return
    }
    Panel{
        item{Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){Glyph(R.drawable.ic_device,null,BuriTheme.Text,32);Spacer(Modifier.width(14.dp));Column{Text(t("Receiving phone"),fontSize=24.sp,fontWeight=FontWeight.SemiBold);Text(t("One active receiver"),fontSize=14.sp,color=BuriTheme.Muted)}}}
        item{FactGroup(listOf(
            t("Paired receiving code") to (g.pairedReceivingCode?:t("Unavailable")),
            t("Sender") to (g.approvedSenders?.joinToString(", ")?:t("Unavailable")),
            t("SIM") to t(if((g.subscriptionId?:-1)>=0&&health.code !in setOf("source","attention","permissions"))"Verified"else if(health.code=="source")"Changed · sync blocked"else "Unavailable"),
            t("SMS permission") to t(if(m.receivingPermissionsRequired)"Required"else "Granted"),
            t("Sync") to t(if(health.code in setOf("source","permissions","attention","queue","reauthorize"))"Blocked"else if(g.captureEnabled)"Listening"else "Paused"),
            t("Last receipt") to (g.lastCapture?:t("Not recorded")),
            t("Queued") to (if(g.pending>=0)g.pending.toString()else t("Unavailable")),
            t("Sync") to t(if(s.offline)"Offline"else if(g.problem=="uploads_on_hold")"Paused"else "Unavailable")
        ),BuriTheme.Group)}
        if(health.needsPermission||m.receivingPermissionsRequired)item{OutlinedButton(onPermissions,enabled=!s.busy){Text(t("SMS permission"))}}
        item{Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp)){
            if(!g.captureEnabled&&health.canResume&&!m.receivingPermissionsRequired)OutlinedButton({m.setPaused(false)},enabled=!s.busy){Text(t("Resume"))}
            OutlinedButton(m::syncReceiver,enabled=!s.busy&&!s.offline){Text(t("Sync"))}
        }}
        item{Text(t("Only the registered business SIM is ingested."),fontSize=15.sp,color=BuriTheme.Muted)}
    }
}
@Composable private fun ReplaceReceiverPanel(s:UiState,m:BuriController,onPermissions:()->Unit){
    val t=LocalUiText.current;var code by remember{mutableStateOf("")};var confirmed by remember{mutableStateOf(false)}
    val checking=m.receiverRetirementPending
    Panel(footer={Primary(t(if(checking)"Check replacement"else "Replace receiver"),{
        if(checking)m.replaceReceiver("")else if(m.receivingPermissionsRequired)onPermissions()else{m.replaceReceiver(code);code=""}
    },!s.busy&&(checking||(confirmed&&code.trim().length in 4..128&&!s.offline&&!s.pending)))}){
        item{Text(t("Retire this receiver and pair its replacement to the same receiving account. There can be only one active receiver."),fontSize=15.sp,color=BuriTheme.Muted)}
        item{CheckRow(t("I have the registered business SIM"),confirmed,!s.busy&&!checking){confirmed=it}}
        item{Entry(t("Pairing code"),code,{code=it.take(128)},enabled=!s.busy&&!checking,imeAction=ImeAction.Done)}
    }
}
@Composable private fun FiltersPanel(s:UiState,m:BuriController){
    val t=LocalUiText.current;var selected by remember(s.filter){mutableStateOf(s.filter)};var expanded by remember{mutableStateOf(false)}
    val options=listOf("all" to "All","allocated" to "Allocated","unallocated" to "Unallocated","processing" to "Processing")
    Panel(footer={Primary(t("Apply"),{m.setFilter(selected)},!s.busy)}){
        item{Text(t("Status"),fontSize=15.sp,color=BuriTheme.Muted);Spacer(Modifier.height(9.dp));Box{
            OutlinedButton({expanded=true},Modifier.testTag("payment-filter-select").fillMaxWidth().heightIn(min=60.dp),enabled=!s.busy,shape=RoundedCornerShape(17.dp)){
                Text(t(options.firstOrNull{it.first==selected}?.second?:"All"),Modifier.weight(1f),textAlign=TextAlign.Start,fontSize=19.sp);Glyph(R.drawable.ic_arrow,null,BuriTheme.Muted,18)
            }
            DropdownMenu(expanded,{expanded=false}){for((value,label)in options)DropdownMenuItem(text={Text(t(label))},onClick={selected=value;expanded=false})}
        }}
        s.payments?.asOf?.let{asOf->item{Text(historyTime(asOf,t.locale),fontSize=15.sp,color=BuriTheme.Muted)}}
    }
}

package rw.ikanisa.burimunsi.ui

import androidx.activity.compose.BackHandler
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
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.*
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
import java.util.Locale

private fun money(value:Long,locale:Locale):String=ExactDisplay.amount(value,locale.toLanguageTag()).orEmpty()
private fun initials(value:String):String=value.trim().split(Regex("\\s+")).filter{it.isNotEmpty()}.take(2).joinToString(""){it.take(1).uppercase(Locale.ROOT)}
private fun historyTime(value:String,locale:Locale):String=ExactDisplay.timestamp(value,locale.toLanguageTag())?:value
private fun iconFor(route:Route)=when(route){Route.HOME->R.drawable.ic_home;Route.PAYMENTS->R.drawable.ic_activity;Route.MEMBERS->R.drawable.ic_members;else->R.drawable.ic_settings}
private fun titleFor(route:Route)=when(route){Route.LOGIN->"Sign in";Route.HOME->"Home";Route.PAYMENTS->"Payments";Route.PAYMENT->"M-Money";Route.MEMBERS->"Members";Route.MEMBER->"Member";Route.SMS->"Messages";Route.SETTINGS->"Settings"}

@Composable
fun BuriApp(model:BuriController,onSupport:()->Unit,onPermissions:()->Unit,onExport:()->Unit,onPhoneSettings:()->Unit,onCollectSignOut:()->Unit={}){
    val t=LocalUiText.current
    val state=model.state
    val memory=remember(state.operator?.id){UiFocusMemory()}
    if(model.screenGate!=ScreenGate.OPEN){ScreenGuard(model.screenGate,state,model,onSupport);return}
    val scope="${state.route}:${state.routeId.orEmpty()}:${state.sheet}:${state.sheetId.orEmpty()}"
    CompositionLocalProvider(LocalUiFocusMemory provides memory,LocalUiFocusScope provides scope){
        FocusReturnEffect(scope)
        BuriAppBody(model,onSupport,onPermissions,onExport,onPhoneSettings,onCollectSignOut)
    }
}

@Composable private fun BuriAppBody(model:BuriController,onSupport:()->Unit,onPermissions:()->Unit,onExport:()->Unit,onPhoneSettings:()->Unit,onCollectSignOut:()->Unit){
    val t=LocalUiText.current
    val s=model.state
    val gate=model.screenGate
    val presentation=model.presentation
    if(gate!=ScreenGate.OPEN){
        // Do not merely cover the UI with a transparent layer: remove records,
        // dialogs and remembered credential fields from the Compose/semantics tree.
        ScreenGuard(gate,s,model,onSupport)
        return
    }
    val read=s.operator!=null
    val keyboard=LocalSoftwareKeyboardController.current
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
            if(read) Header(s,model)
            if(s.configurationRequired){
                Column(Modifier.fillMaxWidth().weight(1f).padding(24.dp),verticalArrangement=Arrangement.Center){
                    Text("BuriMunsi",fontSize=40.sp,fontWeight=FontWeight.SemiBold,lineHeight=48.sp)
                    Spacer(Modifier.height(20.dp))
                    Text(t("Managed setup required"),fontSize=24.sp,lineHeight=32.sp)
                    Spacer(Modifier.height(12.dp))
                    Text(t("Contact your administrator to configure this phone."),color=BuriTheme.Muted,fontSize=17.sp,lineHeight=25.sp)
                    Spacer(Modifier.height(24.dp));Primary(t("Contact admin"),onSupport)
                }
            }else{
                if(s.busy)LinearProgressIndicator(Modifier.fillMaxWidth().height(2.dp).semantics{contentDescription=t("Working")},color=BuriTheme.Blue,trackColor=Color.Transparent)
                s.commandNotice?.takeIf{read}?.let{notice->
                    Text(t(notice),Modifier.fillMaxWidth().padding(horizontal=24.dp,vertical=10.dp).semantics{liveRegion=LiveRegionMode.Polite},color=BuriTheme.Warn,fontSize=15.sp,lineHeight=23.sp)
                }
                s.error?.let{error->
                    Text(t(error),Modifier.fillMaxWidth().padding(horizontal=24.dp,vertical=10.dp).semantics{liveRegion=LiveRegionMode.Polite},color=BuriTheme.Bad,fontSize=15.sp,lineHeight=23.sp)
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
                Box(Modifier.weight(1f).fillMaxWidth().semantics{stateDescription=t(PresentationState.label(presentation.state))}){
                    if(read&&!presentation.showRecords){
                        Column(Modifier.fillMaxWidth().padding(24.dp)){
                            Text(t(PresentationState.label(presentation.state)),fontSize=17.sp,lineHeight=25.sp)
                            if(presentation.mayRetryRead){Spacer(Modifier.height(16.dp));Primary(t("Refresh"),model::refresh)}
                        }
                    }else key(s.route,s.routeId){RouteEntrance(t(titleFor(s.route))){when(s.route){
                        Route.LOGIN->Login(s.busy,model::login,onSupport,onCollectSignOut)
                        Route.HOME->HomeScreen(s,model)
                        Route.PAYMENTS->PaymentsScreen(s,model)
                        Route.PAYMENT->PaymentScreen(s,model)
                        Route.MEMBERS->MembersScreen(s,model)
                        Route.MEMBER->MemberScreen(s,model,onExport)
                        Route.SMS->SmsScreen(s,model)
                        Route.SETTINGS->SettingsScreen(s,model,onSupport)
                    }}}
                }
                if(read&&s.route in setOf(Route.HOME,Route.PAYMENTS,Route.MEMBERS,Route.SETTINGS))BottomNav(s.route,model::navigate,s.busy)
            }
        }
    }
    if(s.sheet!=null&&presentation.showRecords)Sheets(s,model,onSupport,onPermissions,onPhoneSettings)
    if(s.discardRequested)AlertDialog(onDismissRequest=model::keepDraft,
        title={Text(t("Discard unsaved changes?"))},text={Text(if(s.pending)t("An earlier action may have been submitted. Discarding this draft does not cancel it. Check the previous action before retrying.") else t("Nothing has been submitted. Credentials will be cleared."))},
        confirmButton={TextButton(model::discardDraft){Text(t("Discard changes"))}},
        dismissButton={TextButton(model::keepDraft){Text(t("Keep editing"))}})
}

@Composable private fun ScreenGuard(gate:ScreenGate,s:UiState,m:BuriController,support:()->Unit){
    val t=LocalUiText.current
    Column(Modifier.fillMaxSize().background(BuriTheme.Canvas).safeDrawingPadding()
        .verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement=Arrangement.Center){
        Text("BuriMunsi",fontSize=32.sp,fontWeight=FontWeight.SemiBold,lineHeight=40.sp)
        Spacer(Modifier.height(24.dp))
        val title=when(gate){
            ScreenGate.BACKGROUND->t("App paused")
            ScreenGate.CHECKING->t("Checking access")
            ScreenGate.STALE->t("Refresh required")
            else->t("Check your connection")
        }
        Text(title,Modifier.semantics{heading();liveRegion=LiveRegionMode.Polite},fontSize=24.sp,lineHeight=32.sp)
        Spacer(Modifier.height(12.dp))
        if(gate==ScreenGate.BACKGROUND){
            Text(t("Records are hidden while the app is not active."),color=BuriTheme.Muted)
        }else{
            Text(if(gate==ScreenGate.STALE)t("The displayed records have expired. Refresh before continuing.")
                else t("Records stay hidden until your session and current records have been checked."),color=BuriTheme.Muted)
            if(s.pending){Spacer(Modifier.height(12.dp));Text(t("A previous action still needs confirmation. Refreshing or signing out does not cancel it."),color=BuriTheme.Warn)}
            s.error?.let{Spacer(Modifier.height(12.dp));Text(t(it),color=BuriTheme.Bad,modifier=Modifier.semantics{liveRegion=LiveRegionMode.Polite})}
            Spacer(Modifier.height(24.dp))
            if(s.busy)LinearProgressIndicator(Modifier.fillMaxWidth().semantics{contentDescription=t("Checking session and records")})
            else{
                Primary(t("Retry access check"),m::refresh)
                Spacer(Modifier.height(12.dp));Primary(t("Sign out"),m::logout,secondary=true)
                TextButton(support,Modifier.fillMaxWidth()){Text(t("Contact admin"))}
            }
        }
    }
}

@Composable private fun Header(s:UiState,m:BuriController){
    val t=LocalUiText.current
    Row(Modifier.fillMaxWidth().padding(horizontal=20.dp,vertical=10.dp).heightIn(min=56.dp),verticalAlignment=Alignment.CenterVertically){
        if(s.route in setOf(Route.PAYMENT,Route.MEMBER,Route.SMS)){
            RoundAction(R.drawable.ic_back,t("Back"),m::back,enabled=!s.busy,size=48)
            Spacer(Modifier.width(12.dp))
        }
        Text(if(s.route==Route.HOME)"BuriMunsi" else t(titleFor(s.route)),Modifier.weight(1f).semantics{heading()},
            fontSize=if(s.route==Route.HOME)27.sp else 40.sp,fontWeight=FontWeight.SemiBold,maxLines=2,overflow=TextOverflow.Ellipsis,lineHeight=if(s.route==Route.HOME)35.sp else 48.sp)
        when(s.route){
            Route.HOME->RoundAction(R.drawable.ic_shield,t("My profile"),{m.openSheet(Sheet.PROFILE)},enabled=!s.busy,size=48)
            Route.MEMBERS->if(m.allows(Capability.ENROLL))RoundAction(R.drawable.ic_plus,t("Add member"),{m.openSheet(Sheet.ENROLL)},enabled=!s.busy&&!s.offline,size=48)
            Route.PAYMENT->RoundAction(R.drawable.ic_info,t("Payment information"),{m.openSheet(Sheet.HISTORY)},enabled=!s.busy,size=48)
            Route.MEMBER->RoundAction(R.drawable.ic_info,t("Member details"),{m.openSheet(Sheet.MEMBER_DETAILS)},enabled=!s.busy,size=48)
            Route.LOGIN->Unit
            else->RoundAction(R.drawable.ic_sync,t("Refresh"),m::refresh,enabled=!s.busy,size=48)
        }
    }
}
@Composable private fun BottomNav(current:Route,onNavigate:(Route,String?)->Unit,busy:Boolean){
    Row(Modifier.fillMaxWidth().padding(horizontal=20.dp,vertical=12.dp).background(BuriTheme.Raised.copy(alpha=.96f),RoundedCornerShape(34.dp)).padding(6.dp),horizontalArrangement=Arrangement.SpaceBetween){
        for(route in listOf(Route.HOME,Route.PAYMENTS,Route.MEMBERS,Route.SETTINGS)){
            val chosen=current==route
            val action=focusAction("navigation:${route.name}"){onNavigate(route,null)}
            IconButton(onClick=action.click,enabled=!busy,modifier=action.modifier.size(58.dp).background(if(chosen)Color.White.copy(alpha=.12f)else Color.Transparent,CircleShape).semantics{selected=chosen;role=SemanticRole.Tab}){
                Glyph(iconFor(route),titleFor(route),if(chosen)BuriTheme.Text else BuriTheme.Muted,26)
            }
        }
    }
}
@Composable fun SingleLineName(name:String,modifier:Modifier=Modifier,size:Int=19){
    val t=LocalUiText.current
    Text(name,modifier.clearAndSetSemantics{contentDescription=name},fontSize=size.sp,fontWeight=FontWeight.Medium,maxLines=1,overflow=TextOverflow.Ellipsis,lineHeight=(size+8).sp)
}
@Composable private fun Glyph(icon:Int,description:String?,tint:Color=BuriTheme.Text,size:Int=24){
    val t=LocalUiText.current
    Icon(painterResource(icon),description?.let{t(it)},Modifier.size(size.dp),tint)
}
@Composable private fun RoundAction(icon:Int,label:String,click:()->Unit,enabled:Boolean=true,size:Int=56){
    val action=focusAction("action:$label",click)
    IconButton(action.click,action.modifier.size(size.dp).background(Color.White.copy(alpha=.09f),CircleShape),enabled=enabled){Glyph(icon,label,if(enabled)BuriTheme.Text else BuriTheme.Muted,24)}
}
@Composable private fun Avatar(name:String,size:Int=42){
    val t=LocalUiText.current
    Box(Modifier.size(size.dp).background(Color.White.copy(alpha=.11f),CircleShape).clearAndSetSemantics{},contentAlignment=Alignment.Center){Text(initials(name),fontSize=15.sp,fontWeight=FontWeight.Medium,lineHeight=23.sp)}
}
@Composable private fun Primary(label:String,onClick:()->Unit,enabled:Boolean=true,secondary:Boolean=false){
    val t=LocalUiText.current
    val action=focusAction("button:$label",onClick)
    val keyboard=LocalSoftwareKeyboardController.current
    Button({keyboard?.hide();action.click()},action.modifier.fillMaxWidth().heightIn(min=56.dp),enabled=enabled,shape=RoundedCornerShape(30.dp),
        colors=ButtonDefaults.buttonColors(containerColor=if(secondary)BuriTheme.Raised else BuriTheme.Text,contentColor=if(secondary)BuriTheme.Text else Color(0xFF161618))){
        Text(t(label),fontSize=18.sp,fontWeight=FontWeight.SemiBold,textAlign=TextAlign.Center,lineHeight=26.sp)
    }
}
@Composable private fun Fact(label:String,value:String){
    val t=LocalUiText.current
    // Long identifiers remain complete; unlike names, financial facts may reflow.
    Column(Modifier.fillMaxWidth().padding(vertical=10.dp)){
        Text(t(label),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp);Spacer(Modifier.height(5.dp));Text(value,fontSize=18.sp,lineHeight=26.sp)
    }
}
private fun stateIcon(name:String)=when(name){"check"->R.drawable.ic_check;"link"->R.drawable.ic_link;"history"->R.drawable.ic_history;"sync"->R.drawable.ic_sync;"clock"->R.drawable.ic_clock;else->R.drawable.ic_alert}
private fun stateTone(name:String)=when(name){"good"->BuriTheme.Good;"bad"->BuriTheme.Bad;"warn"->BuriTheme.Warn;else->BuriTheme.Blue}
@Composable private fun MoneyText(value:Long,modifier:Modifier=Modifier,size:Int=22,positiveSign:Boolean=false,showHint:Boolean=false){
    val t=LocalUiText.current
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
@Composable private fun BigValue(amount:Long,size:Int=64){
    val t=LocalUiText.current
    Column(Modifier.fillMaxWidth().padding(vertical=14.dp),horizontalAlignment=Alignment.CenterHorizontally){
        MoneyText(amount,Modifier.widthIn(max=800.dp),size,showHint=true)
        Spacer(Modifier.height(8.dp));Text(t("RWF"),fontSize=16.sp,color=BuriTheme.Muted,lineHeight=24.sp)
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
@Composable private fun Section(label:String){
    val t=LocalUiText.current
    Text(t(label),Modifier.padding(top=12.dp,bottom=2.dp).semantics{heading()},fontSize=24.sp,fontWeight=FontWeight.SemiBold,lineHeight=32.sp)}
@Composable private fun Search(value:String,change:(String)->Unit,submit:()->Unit,hint:String="Search",busy:Boolean=false){
    val t=LocalUiText.current
    val keyboard=LocalSoftwareKeyboardController.current
    val focus=LocalFocusManager.current
    val search:()->Unit={if(!busy){keyboard?.hide();focus.clearFocus();submit()}}
    OutlinedTextField(value,change,Modifier.fillMaxWidth().onPreviewKeyEvent{
        if(it.key==Key.Enter||it.key==Key.NumPadEnter){if(it.type==KeyEventType.KeyUp)search();true}else false
    },label={Text(t(hint))},singleLine=true,enabled=!busy,shape=RoundedCornerShape(28.dp),
        keyboardOptions=KeyboardOptions(imeAction=ImeAction.Search),keyboardActions=KeyboardActions(onSearch={search()}),
        trailingIcon={IconButton(search,enabled=!busy){Glyph(R.drawable.ic_search,t("Search"))}},
        colors=OutlinedTextFieldDefaults.colors(focusedContainerColor=BuriTheme.Input.copy(alpha=.75f),unfocusedContainerColor=BuriTheme.Input.copy(alpha=.65f),focusedBorderColor=BuriTheme.Blue,unfocusedBorderColor=Color.Transparent))
}
@Composable private fun FilterChipIcon(label:String,icon:Int,chosen:Boolean,click:()->Unit){
    val t=LocalUiText.current
    FilterChip(selected=chosen,onClick=click,label={if(chosen)Text(t(label),maxLines=1)},leadingIcon={Glyph(icon,label,if(chosen)BuriTheme.Text else BuriTheme.Muted,20)},modifier=Modifier.heightIn(min=48.dp),shape=RoundedCornerShape(24.dp))
}
private fun LazyListScope.moreButton(cursor:String?,busy:Boolean,more:()->Unit){if(cursor!=null)item(key="pagination"){Primary("Load more",more,!busy,secondary=true)}}
@Composable private fun PaymentRow(p:Payment,click:()->Unit){
    val t=LocalUiText.current
    val action=focusAction("payment:${p.id}",click)
    val status=Presentation.payment(p.state)
    val fontScale=LocalDensity.current.fontScale
    BoxWithConstraints(action.modifier.fillMaxWidth().heightIn(min=64.dp).clickable(role=SemanticRole.Button,onClick=action.click)
        .semantics(mergeDescendants=true){}.padding(vertical=13.dp)){
        val stacked=maxWidth<360.dp||fontScale>=1.5f
        Column(Modifier.fillMaxWidth()){
            Row(verticalAlignment=Alignment.CenterVertically){
                Avatar(p.payerNameRaw);Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)){
                    SingleLineName(p.payerNameRaw)
                    Spacer(Modifier.height(4.dp));Text(p.atRaw,fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)
                    Spacer(Modifier.height(4.dp));Text(t("FT Id: %1\$s",p.ftId),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)
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
    }
}
@Composable private fun MemberRow(member:Member,click:()->Unit){
    val t=LocalUiText.current
    val action=focusAction("member:${member.id}",click)
    val fontScale=LocalDensity.current.fontScale
    BoxWithConstraints(action.modifier.fillMaxWidth().heightIn(min=64.dp).clickable(role=SemanticRole.Button,onClick=action.click)
        .semantics(mergeDescendants=true){}.padding(vertical=14.dp)){
        val stacked=maxWidth<360.dp||fontScale>=1.5f
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
    }
}
@Composable private fun LedgerRowView(row:LedgerRow,click:()->Unit){
    val t=LocalUiText.current
    val action=focusAction("ledger:${row.id}",click)
    val fontScale=LocalDensity.current.fontScale
    BoxWithConstraints(action.modifier.fillMaxWidth().heightIn(min=56.dp)
        .then(if(row.transactionId!=null)Modifier.clickable(role=SemanticRole.Button,onClick=action.click)else Modifier)
        .padding(vertical=12.dp)){
        if(maxWidth<360.dp||fontScale>=1.5f){
            Column(Modifier.fillMaxWidth()){
                Text(row.atRaw,fontSize=15.sp,lineHeight=23.sp);Text(t("FT Id: %1\$s",row.ftId),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)
                Spacer(Modifier.height(8.dp));MoneyText(row.amountRwf,Modifier.fillMaxWidth(),23,positiveSign=true,showHint=true)
            }
        }else{
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.Top){
                Column(Modifier.weight(1f)){Text(row.atRaw,fontSize=15.sp,lineHeight=23.sp);Spacer(Modifier.height(5.dp));Text(t("FT Id: %1\$s",row.ftId),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)}
                Spacer(Modifier.width(8.dp));MoneyText(row.amountRwf,Modifier.widthIn(max=150.dp),23,positiveSign=true)
            }
        }
    }
}

@Composable private fun HomeScreen(s:UiState,m:BuriController){
    val t=LocalUiText.current
    val home=s.home
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(24.dp,4.dp,24.dp,24.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
        if(home==null){item{Empty(if(s.busy)t("Loading") else t("No records available"))};return@LazyColumn}
        item{BigValue(home.balanceRwf)}
        if(s.gateway!=null)item{
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.Center){
                val health=GatewayHealth.describe(s.gateway)
                Row(Modifier.background(Color.White.copy(alpha=.08f),RoundedCornerShape(20.dp)).heightIn(min=48.dp).clickable(enabled=!s.busy){m.openSheet(Sheet.GATEWAY)}.semantics{contentDescription=t("Receiving phone: %1\$s",t(health.title))}.padding(horizontal=14.dp,vertical=10.dp),verticalAlignment=Alignment.CenterVertically){
                    Glyph(R.drawable.ic_device,null,BuriTheme.Blue,16)
                    Spacer(Modifier.width(8.dp));Text(t(health.title),fontSize=14.sp,lineHeight=22.sp)
                }
            }
        }
        item{
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceEvenly){
                RoundAction(R.drawable.ic_activity,t("Payments"),{m.navigate(Route.PAYMENTS)},!s.busy)
                RoundAction(R.drawable.ic_members,t("Members"),{m.navigate(Route.MEMBERS)},!s.busy)
                if(m.allows(Capability.ENROLL))RoundAction(R.drawable.ic_plus,t("Add member"),{m.openSheet(Sheet.ENROLL)},!s.busy&&!s.offline)
                if(m.allows(Capability.SMS))RoundAction(R.drawable.ic_sms,t("Messages"),{m.navigate(Route.SMS)},!s.busy)
                else RoundAction(R.drawable.ic_history,t("Payment history"),{m.navigate(Route.PAYMENTS)},!s.busy)
            }
        }
        item{
            Row(Modifier.fillMaxWidth().padding(top=10.dp),horizontalArrangement=Arrangement.spacedBy(24.dp)){
                Column(Modifier.weight(1f)){MoneyText(home.todayRwf,size=30,showHint=true);Spacer(Modifier.height(5.dp));Text(t("Today · RWF"),color=BuriTheme.Muted,fontSize=14.sp,lineHeight=22.sp)}
                Column(Modifier.weight(1f)){Text(home.memberCount.toString(),fontSize=30.sp,lineHeight=38.sp);Spacer(Modifier.height(5.dp));Text(t("Members"),color=BuriTheme.Muted,fontSize=14.sp,lineHeight=22.sp)}
            }
        }
        if(home.unallocatedCount>0)item{
            Row(Modifier.fillMaxWidth().background(BuriTheme.Warn.copy(alpha=.08f),RoundedCornerShape(22.dp)).clickable{m.openUnallocated()}.padding(18.dp),verticalAlignment=Alignment.CenterVertically){
                Glyph(R.drawable.ic_link,null,BuriTheme.Warn,22);Spacer(Modifier.width(14.dp));Text(t("%1\$d unallocated",home.unallocatedCount),Modifier.weight(1f),fontSize=18.sp,color=BuriTheme.Warn,lineHeight=26.sp);Glyph(R.drawable.ic_arrow,t("Open unallocated"),BuriTheme.Warn,18)
            }
        }
        item{Section(t("Recent"))}
        items(home.recent,key={it.id}){p->PaymentRow(p){m.navigate(Route.PAYMENT,p.id)}}
        if(home.recent.isEmpty())item{Empty()}
    }
}
@Composable private fun PaymentsScreen(s:UiState,m:BuriController){
    val t=LocalUiText.current
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(24.dp,4.dp,24.dp,24.dp)){
        item{Search(s.search,m::search,m::searchSubmit,t("Name or FT Id"),s.busy)}
        item{Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(vertical=12.dp),horizontalArrangement=Arrangement.spacedBy(8.dp)){
            FilterChipIcon(t("All"),R.drawable.ic_activity,s.filter=="all"){m.setFilter("all")}
            FilterChipIcon(t("Allocated"),R.drawable.ic_check,s.filter=="allocated"){m.setFilter("allocated")}
            FilterChipIcon(t("Unallocated"),R.drawable.ic_link,s.filter=="unallocated"){m.setFilter("unallocated")}
        }}
        items(s.payments?.items.orEmpty(),key={it.id}){p->PaymentRow(p){m.navigate(Route.PAYMENT,p.id)}}
        if(s.payments?.items?.isEmpty()==true)item{Empty()}
        moreButton(s.payments?.nextCursor,s.busy,m::more)
    }
}
@Composable private fun PaymentScreen(s:UiState,m:BuriController){
    val t=LocalUiText.current
    val p=s.payment
    if(p==null){Empty(if(s.busy)t("Loading payment") else t("Payment unavailable. Go back or refresh."));return}
    val status=Presentation.payment(p.state)
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(24.dp,10.dp,24.dp,30.dp),verticalArrangement=Arrangement.spacedBy(12.dp)){
        item{Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.Center){Glyph(stateIcon(status.icon),status.label,stateTone(status.tone),48)}}
        item{SingleLineName(p.payerNameRaw,Modifier.fillMaxWidth(),32)}
        item{BigValue(p.amountRwf)}
        if(!status.confirmedCredit)item{Text(t(status.label),color=stateTone(status.tone),fontSize=16.sp,lineHeight=24.sp)}
        item{
            Column(Modifier.fillMaxWidth().background(BuriTheme.Surface,RoundedCornerShape(24.dp)).padding(18.dp)){
                Fact(t("FT Id"),p.ftId);Fact(t("at"),p.atRaw)
                Fact(if(p.memberPhone!=null)t("Member MoMo") else t("MoMo"),p.memberPhone?:p.payerPhoneRaw)
                if(p.memberPhone!=null&&p.memberPhone!=p.payerPhoneRaw)Fact(t("from"),p.payerPhoneRaw)
            }
        }
        item{Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.Center){
            if(p.memberId!=null)RoundAction(R.drawable.ic_members,t("Member ledger"),{m.navigate(Route.MEMBER,p.memberId)},!s.busy)
            if(p.memberId!=null)Spacer(Modifier.width(16.dp))
            if(m.allows(Capability.SMS)&&p.sourceId!=null)RoundAction(R.drawable.ic_sms,t("Original SMS"),{m.openSheet(Sheet.RAW,p.sourceId)},!s.busy)
        }}
        if(status.canAllocate&&m.allows(Capability.ALLOCATE))item{Primary(t("Assign member"),{m.openSheet(Sheet.ALLOCATE)},!s.busy&&!s.offline&&!s.pending)}
    }
}
@Composable private fun MembersScreen(s:UiState,m:BuriController){
    val t=LocalUiText.current
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(24.dp,4.dp,24.dp,24.dp)){
        item{Search(s.search,m::search,m::searchSubmit,t("Name or MoMo number"),s.busy)}
        items(s.members?.items.orEmpty(),key={it.id}){member->MemberRow(member){m.navigate(Route.MEMBER,member.id)}}
        if(s.members?.items?.isEmpty()==true)item{Empty(t("No members"))}
        moreButton(s.members?.nextCursor,s.busy,m::more)
    }
}
@Composable private fun MemberScreen(s:UiState,m:BuriController,onExport:()->Unit){
    val t=LocalUiText.current
    val member=s.member
    if(member==null){Empty(if(s.busy)t("Loading member") else t("Member unavailable. Go back or refresh."));return}
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(24.dp,6.dp,24.dp,24.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
        item{Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.Center){Avatar(member.name,64)}}
        item{SingleLineName(member.name,Modifier.fillMaxWidth(),40);Spacer(Modifier.height(8.dp));Text(member.phone,fontSize=17.sp,color=BuriTheme.Muted,lineHeight=25.sp)}
        item{BigValue(member.balanceRwf,60)}
        item{Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.Center){
            RoundAction(R.drawable.ic_info,t("Member details"),{m.openSheet(Sheet.MEMBER_DETAILS)},!s.busy)
            Spacer(Modifier.width(16.dp));RoundAction(R.drawable.ic_export,t("Export transactions"),onExport,!s.busy&&!s.offline)
        }}
        item{Section(t("Transactions"))}
        items(s.ledger?.items.orEmpty(),key={it.id}){row->
            LedgerRowView(row){row.transactionId?.let{m.navigate(Route.PAYMENT,it)}}
        }
        if(s.ledger?.items?.isEmpty()==true)item{Empty(t("No transactions"))}
        moreButton(s.ledger?.nextCursor,s.busy,m::more)
    }
}
@Composable private fun SmsScreen(s:UiState,m:BuriController){
    val t=LocalUiText.current
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(24.dp,4.dp,24.dp,24.dp)){
        item{Search(s.search,m::search,m::searchSubmit,t("Sender or FT Id"),s.busy)}
        item{Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(vertical=12.dp),horizontalArrangement=Arrangement.spacedBy(8.dp)){
            FilterChipIcon(t("All"),R.drawable.ic_sms,s.filter=="all"){m.setFilter("all")}
            FilterChipIcon(t("Queued"),R.drawable.ic_clock,s.filter=="queued"){m.setFilter("queued")}
            FilterChipIcon(t("Duplicates"),R.drawable.ic_history,s.filter=="duplicate"){m.setFilter("duplicate")}
        }}
        item{Text(t("Receipt delivery is separate from member credit."),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)}
        items(s.messages?.items.orEmpty(),key={it.id}){sms->
            Row(Modifier.fillMaxWidth().clickable{m.openSheet(Sheet.RAW,sms.id)}.padding(vertical=16.dp),verticalAlignment=Alignment.Top){
                Glyph(R.drawable.ic_sms,null,BuriTheme.Muted,24);Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)){
                    SingleLineName(sms.sender);Spacer(Modifier.height(5.dp));Text(sms.at,fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)
                    Spacer(Modifier.height(7.dp));Text(sms.preview,fontSize=15.sp,color=BuriTheme.Muted,maxLines=2,overflow=TextOverflow.Ellipsis,lineHeight=23.sp)
                }
                Spacer(Modifier.width(8.dp))
                val delivery=Presentation.receipt(sms.state)
                Column(Modifier.widthIn(max=110.dp),horizontalAlignment=Alignment.End){
                    Glyph(stateIcon(delivery.icon),delivery.meaning,stateTone(delivery.tone),18)
                    Text(t(delivery.label),fontSize=14.sp,color=stateTone(delivery.tone),lineHeight=22.sp)
                }
            }
        }
        if(s.messages?.items?.isEmpty()==true)item{Empty(t("No messages"))}
        moreButton(s.messages?.nextCursor,s.busy,m::more)
    }
}
@Composable private fun SettingRow(icon:Int,title:String,subtitle:String?=null,enabled:Boolean=true,click:()->Unit){
    val t=LocalUiText.current
    val action=focusAction("setting:$icon",click)
    Row(action.modifier.fillMaxWidth().heightIn(min=56.dp).clickable(enabled=enabled,role=SemanticRole.Button,onClick=action.click).semantics(mergeDescendants=true){}.padding(vertical=16.dp),verticalAlignment=Alignment.CenterVertically){
        Glyph(icon,null,if(enabled)BuriTheme.Text else BuriTheme.Muted,24);Spacer(Modifier.width(18.dp))
        Column(Modifier.weight(1f)){Text(title,fontSize=19.sp,maxLines=2,overflow=TextOverflow.Ellipsis,lineHeight=27.sp);if(subtitle!=null){Spacer(Modifier.height(5.dp));Text(subtitle,fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)}}
        Glyph(R.drawable.ic_arrow,null,BuriTheme.Muted,18)
    }
}
@Composable private fun SettingsScreen(s:UiState,m:BuriController,onSupport:()->Unit){
    val t=LocalUiText.current
    LazyColumn(Modifier.fillMaxSize(),state=routeList(s,m),contentPadding=PaddingValues(24.dp,4.dp,24.dp,24.dp)){
        item{SettingRow(R.drawable.ic_shield,s.operator?.name.orEmpty(),s.operator?.phone,click={m.openSheet(Sheet.PROFILE)})}
        item{SettingRow(R.drawable.ic_lock,t("Change passcode"),click={m.openSheet(Sheet.PIN)})}
        if(m.allows(Capability.STAFF)){
            item{SettingRow(R.drawable.ic_members,t("Staff"),click={m.openSheet(Sheet.STAFF)})}
            item{SettingRow(R.drawable.ic_history,t("Activity"),click={m.openSheet(Sheet.AUDIT)})}
        }
        if(BuildConfig.IS_GATEWAY&&s.operator?.role==Role.ADMIN)item{SettingRow(R.drawable.ic_device,t("Receiving phone"),click={m.openSheet(Sheet.GATEWAY)})}
        item{UiPreferencePanel()}
        item{SettingRow(R.drawable.ic_help,t("Help"),click={m.openSheet(Sheet.HELP)})}
        item{SettingRow(R.drawable.ic_out,t("Sign out"),enabled=!s.busy,click=m::logout)}
    }
}
@Composable private fun Entry(label:String,value:String,change:(String)->Unit,phone:Boolean=false,pin:Boolean=false,enabled:Boolean=true,
    imeAction:ImeAction=ImeAction.Next,onDone:(()->Unit)?=null,
    fieldFocus:FocusRequester?=null,nextFocus:FocusRequester?=null,errorText:String?=null,password:Boolean=false,email:Boolean=false){
    val t=LocalUiText.current
    var visible by remember{mutableStateOf(false)}
    val keyboard=LocalSoftwareKeyboardController.current
    val focus=LocalFocusManager.current
    val action:()->Unit={
        if(enabled){if(imeAction==ImeAction.Next){if(nextFocus!=null)nextFocus.requestFocus()else focus.moveFocus(FocusDirection.Next)}
            else{keyboard?.hide();focus.clearFocus();onDone?.invoke()}}
    }
    OutlinedTextField(value,change,Modifier.fillMaxWidth().then(fieldFocus?.let{Modifier.focusRequester(it)}?:Modifier).onPreviewKeyEvent{
        if(it.key==Key.Enter||it.key==Key.NumPadEnter){if(it.type==KeyEventType.KeyUp)action();true}else false
    },label={Text(t(label))},singleLine=true,enabled=enabled,isError=errorText!=null,
        supportingText=if(errorText!=null){{Text(t(errorText))}}else null,
        shape=RoundedCornerShape(18.dp),visualTransformation=if((pin||password)&&!visible)PasswordVisualTransformation()else VisualTransformation.None,
        keyboardOptions=KeyboardOptions(keyboardType=if(pin)KeyboardType.NumberPassword else if(password)KeyboardType.Password else if(phone)KeyboardType.Phone else if(email)KeyboardType.Email else KeyboardType.Text,
            autoCorrectEnabled=false,imeAction=imeAction),
        keyboardActions=KeyboardActions(onNext={action()},onDone={action()}),
        trailingIcon=if(pin||password){{IconButton({visible=!visible},enabled=enabled){Glyph(R.drawable.ic_eye,if(password){if(visible)t("Hide password")else t("Show password")}else if(visible)t("Hide passcode") else t("Show passcode"))}}}else null,
        colors=OutlinedTextFieldDefaults.colors(focusedContainerColor=BuriTheme.Input,unfocusedContainerColor=BuriTheme.Raised,focusedBorderColor=BuriTheme.Blue,unfocusedBorderColor=Color.Transparent))
}
@Composable private fun Login(busy:Boolean,login:(String,String)->Unit,support:()->Unit,collectSignOut:()->Unit){
    val t=LocalUiText.current
    var phone by remember{mutableStateOf("")};var pin by remember{mutableStateOf("")}
    val pinFocus=remember{FocusRequester()}
    val ready=runCatching{Values.phone(phone);Values.pin(pin)}.isSuccess
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(24.dp,56.dp,24.dp,36.dp),verticalArrangement=Arrangement.spacedBy(22.dp)){
        item{Text("BuriMunsi",fontSize=28.sp,fontWeight=FontWeight.SemiBold,lineHeight=36.sp)}
        item{Text(t("Welcome\nback."),fontSize=48.sp,fontWeight=FontWeight.Medium,lineHeight=54.sp)}
        item{Entry(t("Phone number"),phone,{phone=it.take(24)},phone=true,enabled=!busy,nextFocus=pinFocus,
            errorText=if(phone.isNotEmpty()&&runCatching{Values.phone(phone)}.isFailure)"Enter a valid phone number." else null)}
        item{Entry(t("Passcode"),pin,{pin=it.filter { ch->ch in '0'..'9' }.take(4)},pin=true,enabled=!busy,imeAction=ImeAction.Done,fieldFocus=pinFocus,onDone={if(ready&&!busy){login(phone,pin);pin=""}})}
        item{Primary(t("Sign in"),{login(phone,pin);pin=""},ready&&!busy)}
        item{TextButton(collectSignOut,Modifier.fillMaxWidth(),enabled=!busy){Text(t("Use another Collect account"),color=BuriTheme.Blue)}}
        item{TextButton(support,Modifier.fillMaxWidth()){Text(t("Contact admin"),color=BuriTheme.Blue,fontSize=16.sp,lineHeight=24.sp)}}
    }
}

/** Native staff authentication; reuses the selected Dark/Glow form components.
 * Password is deliberately absent from saved state and cleared on submission.
 */
@Composable fun CollectSignIn(busy:Boolean,issue:String?,onSignIn:(String,String)->Unit,onSupport:()->Unit){
    val t=LocalUiText.current
    var email by remember{mutableStateOf("")};var password by remember{mutableStateOf("")}
    val passwordFocus=remember{FocusRequester()}
    val ready=email.trim().isNotEmpty()&&password.isNotEmpty()&&!busy
    val submit:()->Unit={if(ready){val supplied=password;password="";onSignIn(email,supplied)}}
    val message=when(issue){
        null->null
        "invalid_credentials","invalid_login_credentials"->"Email or password could not be verified."
        "burimunsi_access_denied","managed_setup_required"->"This account is not approved for this phone. Contact admin."
        "managed_sign_out_unconfirmed"->"Server sign-out is unconfirmed. Sign in again to check access."
        "captcha_failed","captcha_required"->"Contact admin for help completing Collect sign-in."
        "configuration_required"->"Managed setup required."
        else->"Unable to sign in. Check your connection or contact admin."
    }
    LazyColumn(Modifier.fillMaxSize().background(BuriTheme.wash(Route.LOGIN)).background(Color.Black.copy(alpha=BuriTheme.WashScrimAlpha)).imePadding().testTag("collect-sign-in"),
        contentPadding=PaddingValues(24.dp,56.dp,24.dp,36.dp),verticalArrangement=Arrangement.spacedBy(22.dp)){
        item{Text("BuriMunsi",fontSize=28.sp,fontWeight=FontWeight.SemiBold,lineHeight=36.sp)}
        item{Text(t("Sign in to\nCollect."),fontSize=48.sp,fontWeight=FontWeight.Medium,lineHeight=54.sp)}
        item{Text(t("Use the Collect staff account approved for this phone."),color=BuriTheme.Muted)}
        item{Entry(t("Email"),email,{email=it.take(254)},enabled=!busy,email=true,nextFocus=passwordFocus)}
        item{Entry(t("Password"),password,{password=it.take(128)},enabled=!busy,password=true,imeAction=ImeAction.Done,fieldFocus=passwordFocus,onDone=submit)}
        if(message!=null)item{Text(t(message),color=BuriTheme.Bad,modifier=Modifier.semantics{liveRegion=LiveRegionMode.Polite})}
        item{Primary(t(if(busy)"Signing in…" else "Continue"),submit,ready)}
        item{TextButton(onSupport,Modifier.fillMaxWidth(),enabled=!busy){Text(t("Contact admin"),color=BuriTheme.Blue)}}
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun Sheets(s:UiState,m:BuriController,onSupport:()->Unit,onPermissions:()->Unit,onPhoneSettings:()->Unit){
    val t=LocalUiText.current
    val sheet=s.sheet?:return
    val title=when(sheet){Sheet.PROFILE->t("Profile");Sheet.PIN->t("Passcode");Sheet.HELP->t("Help");Sheet.ALLOCATE->t("Allocate");Sheet.ENROLL->t("Add member");Sheet.STAFF->t("Staff");Sheet.STAFF_EDIT->if(s.selectedStaff==null)t("Add staff") else t("Staff account");Sheet.REMOVE_STAFF->t("Remove access");Sheet.GATEWAY->t("Receiving phone");Sheet.RAW->t("Original SMS");Sheet.MEMBER_DETAILS->t("Member details");Sheet.HISTORY->t("Payment information");Sheet.AUDIT->t("Activity");Sheet.FILTERS->t("Filter")}
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
    ModalBottomSheet(onDismissRequest=m::closeSheet,sheetState=sheetState,containerColor=BuriTheme.Surface,contentColor=BuriTheme.Text,dragHandle=null){
        Column(Modifier.fillMaxWidth().imePadding().semantics{paneTitle=title}.onPreviewKeyEvent{
            if(it.key==Key.Escape){if(it.type==KeyEventType.KeyUp){if(imeVisible)keyboard?.hide()else m.closeSheet()};true}else false
        }){
            Row(Modifier.fillMaxWidth().padding(20.dp,12.dp),verticalAlignment=Alignment.CenterVertically){
                Text(title,Modifier.weight(1f).semantics{heading()},fontSize=30.sp,fontWeight=FontWeight.SemiBold,maxLines=2,overflow=TextOverflow.Ellipsis,lineHeight=38.sp)
                IconButton(m::closeSheet,enabled=!s.busy){Glyph(if(s.panelDepth>1)R.drawable.ic_back else R.drawable.ic_close,if(s.panelDepth>1)t("Back to previous panel") else t("Close"))}
            }
            if(s.busy)LinearProgressIndicator(Modifier.fillMaxWidth().height(2.dp).semantics{contentDescription=t("Working")})
            s.error?.let{message->
                Text(t(message),Modifier.padding(horizontal=24.dp,vertical=8.dp).semantics{liveRegion=LiveRegionMode.Polite},color=BuriTheme.Bad)
                if(sheet in setOf(Sheet.STAFF,Sheet.AUDIT,Sheet.ALLOCATE,Sheet.RAW,Sheet.GATEWAY,Sheet.HISTORY,Sheet.MEMBER_DETAILS))
                    TextButton(m::refresh,enabled=!s.busy,modifier=Modifier.padding(horizontal=16.dp)){Text(t("Retry loading"))}
            }
            // Bounded list avoids unbounded nested-scroll measurement on compact phones and IME.
            Box(Modifier.fillMaxWidth().weight(1f,fill=false)){
                key(sheet,s.sheetId){when(sheet){
                    Sheet.PROFILE->Panel{
                        item{SingleLineName(s.operator?.name.orEmpty(),Modifier.fillMaxWidth(),30)}
                        item{Fact(t("Phone"),s.operator?.phone.orEmpty())}
                        item{Primary(t("Change passcode"),{m.openSheet(Sheet.PIN)},!s.busy)}
                    }
                    Sheet.PIN->PinPanel(s.busy,s.pending,m::changePin)
                    Sheet.HELP->Panel{item{Text(BuildConfig.SUPPORT_PHONE,fontSize=26.sp,lineHeight=34.sp)};item{Primary(t("WhatsApp"),onSupport)}}
                    Sheet.ALLOCATE->AllocatePanel(s,m)
                    Sheet.ENROLL->EnrollPanel(s,m)
                    Sheet.STAFF->Panel{
                        item{Primary(t("Add staff"),{m.openSheet(Sheet.STAFF_EDIT)},!s.busy&&!s.offline&&!s.pending)}
                        items(s.staff?.items.orEmpty(),key={it.id}){staff->SettingRow(R.drawable.ic_members,staff.name,t("%1\$s · %2\$s",staff.phone,t(if(staff.active)t("Active") else t("Disabled"))),enabled=!s.busy){m.openSheet(Sheet.STAFF_EDIT,staff.id)}}
                        if(s.staff?.items?.isEmpty()==true)item{Empty(t("No staff"))}
                        moreButton(s.staff?.nextCursor,s.busy,m::more)
                    }
                    Sheet.STAFF_EDIT->StaffPanel(s,m)
                    Sheet.REMOVE_STAFF->Panel{
                        item{SingleLineName(s.selectedStaff?.name.orEmpty(),Modifier.fillMaxWidth(),26)}
                        item{Text(t("This account will no longer have access."),fontSize=17.sp,color=BuriTheme.Muted,lineHeight=25.sp)}
                        item{Primary(t("Remove access"),{m.staffAction("remove")},!s.busy&&!s.offline&&!s.pending)}
                    }
                    Sheet.GATEWAY->GatewayPanel(s,m,onPermissions,onPhoneSettings)
                    Sheet.RAW->Panel{
                        if(s.raw==null)item{Empty(if(s.busy)t("Loading original SMS") else t("Original SMS unavailable. Retry loading or go back."))}
                        s.raw?.let{raw->
                            item{SingleLineName(raw.sender,Modifier.fillMaxWidth(),24);Fact(t("at"),raw.at)}
                            item{SelectionContainer{Text(raw.body,Modifier.fillMaxWidth().background(BuriTheme.Raised,RoundedCornerShape(20.dp)).padding(18.dp),fontSize=17.sp,lineHeight=25.sp)}}
                            if(raw.transactionId!=null)item{Primary(t("View payment"),{m.navigate(Route.PAYMENT,raw.transactionId)},!s.busy)}
                        }
                    }
                    Sheet.MEMBER_DETAILS->Panel{
                        s.member?.let{member->
                            item{Fact(t("Name"),member.name);Fact(t("MoMo"),member.phone);Fact(t("Membership"),if(member.active)t("Active") else t("Inactive"))}
                            if(s.operator?.role==Role.ADMIN&&m.allows(Capability.ENROLL))item{Primary(if(member.active)t("Deactivate membership") else t("Reactivate membership"),{m.setMemberActive(!member.active)},!s.busy&&!s.offline&&!s.pending,secondary=true)}
                        }
                    }
                    Sheet.HISTORY->Panel{
                        s.payment?.let{p->item{Fact(t("FT Id"),p.ftId);Fact(t("from"),p.payerNameRaw);Fact(t("MoMo"),p.payerPhoneRaw);Fact(t("Provider time"),p.atRaw);Fact(t("Current status"),t(Presentation.payment(p.state).label))}}
                        item{Section(t("Recorded events"));Text(t("Only canonical transaction and ledger records are shown. A transaction record is not confirmation of member credit."),fontSize=15.sp,color=BuriTheme.Muted,lineHeight=23.sp)}
                        if(s.historyOffline)item{Text(t("Saved history · may be out of date")+(s.historySavedAt?.let{" · "+historyTime(java.time.Instant.ofEpochMilli(it).toString(),LocalUiText.current.locale)}?:""),color=BuriTheme.Warn,fontSize=14.sp,lineHeight=22.sp)}
                        if(s.history==null&&s.error==null)item{Empty(if(s.busy)t("Loading recorded events") else t("History has not loaded."));if(!s.busy)TextButton(m::refresh){Text(t("Retry loading"))}}
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
                        s.history?.let{page->item{Text(t("%1\$d of %2\$d recorded events · oldest first",page.items.size,page.totalCount),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)}}
                        moreButton(s.history?.nextCursor,s.busy,m::more)
                    }
                    Sheet.AUDIT->Panel{
                        items(s.audit?.items.orEmpty(),key={it.id}){a->Column(Modifier.fillMaxWidth().padding(vertical=10.dp)){SingleLineName(a.action);Spacer(Modifier.height(5.dp));Text(a.at,color=BuriTheme.Muted,fontSize=14.sp,lineHeight=22.sp)}}
                        if(s.audit?.items?.isEmpty()==true)item{Empty()}
                        moreButton(s.audit?.nextCursor,s.busy,m::more)
                    }
                    Sheet.FILTERS->Panel{for(f in listOf("all","allocated","unallocated"))item{Primary(f.replaceFirstChar{it.uppercase()}, {m.setFilter(f)},!s.busy,secondary=s.filter!=f)}}
                }}
            }
        }
    }
}
}

@Composable private fun Panel(content:LazyListScope.()->Unit){
    val memory=LocalUiFocusMemory.current
    val scope=LocalUiFocusScope.current
    val position=memory.scrollPositions[scope]?: (0 to 0)
    val scroll=rememberLazyListState(position.first,position.second)
    LaunchedEffect(scope,scroll){snapshotFlow{scroll.firstVisibleItemIndex to scroll.firstVisibleItemScrollOffset}
        .distinctUntilChanged().collect{memory.scrollPositions[scope]=it}}
    LazyColumn(Modifier.fillMaxWidth(),state=scroll,contentPadding=PaddingValues(24.dp,8.dp,24.dp,36.dp),
        verticalArrangement=Arrangement.spacedBy(16.dp),content=content)
}
@Composable private fun PinPanel(busy:Boolean,pending:Boolean,save:(String,String,String)->Unit){
    val t=LocalUiText.current
    var current by remember{mutableStateOf("")};var next by remember{mutableStateOf("")};var confirm by remember{mutableStateOf("")}
    val ready=runCatching{Values.pin(current);Values.pin(next);require(next==confirm)}.isSuccess
    val nextFocus=remember{FocusRequester()};val confirmFocus=remember{FocusRequester()}
    Panel{
        item{Entry(t("Current passcode"),current,{current=it.filter { ch->ch in '0'..'9' }.take(4)},pin=true,enabled=!busy,nextFocus=nextFocus)}
        item{Entry(t("New passcode"),next,{next=it.filter { ch->ch in '0'..'9' }.take(4)},pin=true,enabled=!busy,fieldFocus=nextFocus,nextFocus=confirmFocus)}
        item{Entry(t("Confirm passcode"),confirm,{confirm=it.filter { ch->ch in '0'..'9' }.take(4)},pin=true,enabled=!busy,imeAction=ImeAction.Done,fieldFocus=confirmFocus,
            errorText=if(confirm.isNotEmpty()&&confirm!=next)"Passcodes do not match." else null)}
        item{Primary(t("Save passcode"),{save(current,next,confirm);current="";next="";confirm=""},ready&&!busy&&!pending)}
    }
}
@Composable private fun EnrollPanel(s:UiState,m:BuriController){
    val t=LocalUiText.current
    val name=s.draft["name"].orEmpty();val phone=s.draft["phone"].orEmpty()
    val phoneFocus=remember{FocusRequester()}
    val ready=Presentation.validName(name)&&runCatching{Values.phone(phone)}.isSuccess
    Panel{
        item{Entry(t("MoMo registered name"),name,{m.editDraft("name",it)},enabled=!s.busy,nextFocus=phoneFocus)}
        item{Text(t("Registered name: 2–100 characters."),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)}
        item{Entry(t("MoMo number"),phone,{m.editDraft("phone",it)},phone=true,enabled=!s.busy,imeAction=ImeAction.Done,fieldFocus=phoneFocus)}
        item{Primary(t("Save member"),{m.enroll(name,phone)},ready&&!s.busy&&!s.offline&&!s.pending)}
    }
}
@Composable private fun AllocatePanel(s:UiState,m:BuriController){
    val t=LocalUiText.current
    val query=s.draft["query"].orEmpty();val note=s.draft["note"].orEmpty()
    val p=s.payment?:return
    Panel{
        item{BigValue(p.amountRwf,48);Text(t("FT Id: %1\$s",p.ftId),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)}
        item{Search(query,{m.editDraft("query",it)},{m.allocationSearch(query)},t("Find member"),s.busy)}
        items(s.members?.items.orEmpty().filter{it.active},key={it.id}){member->
            Row(Modifier.fillMaxWidth().selectable(selected=s.selectedMember?.id==member.id,enabled=!s.busy,role=SemanticRole.RadioButton,onClick={m.selectMember(member)}).padding(vertical=9.dp),verticalAlignment=Alignment.CenterVertically){
                RadioButton(selected=s.selectedMember?.id==member.id,onClick=null,enabled=!s.busy)
                Column(Modifier.weight(1f)){SingleLineName(member.name);Text(if(member.active)member.phone else t("%1\$s · %2\$s",member.phone,t("Inactive")),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)}
            }
        }
        if(s.members?.items?.none{it.active}==true)item{Empty(t("No eligible members. Change the search or ask an administrator."))}
        moreButton(s.members?.nextCursor,s.busy,m::more)
        item{Entry(t("Identification note"),note,{m.editDraft("note",it)},enabled=!s.busy,imeAction=ImeAction.Done)}
        item{Text(t("Identification note: 8–500 characters."),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)}
        s.selectedMember?.let{chosen->item{Fact(t("Member"),chosen.name);Fact(t("MoMo"),chosen.phone)}}
        item{Primary(t("Allocate"),{m.allocate(note)},s.selectedMember?.active==true&&Presentation.validNote(note)&&!s.busy&&!s.offline&&!s.pending)}
    }
}
@Composable private fun StaffPanel(s:UiState,m:BuriController){
    val t=LocalUiText.current
    val existing=s.selectedStaff
    if(s.sheetId!=null&&existing==null){Panel{item{Empty(t("Staff account unavailable. Go back and refresh the staff list."))}};return}
    val name=s.draft["name"]?:existing?.name.orEmpty()
    val phone=s.draft["phone"]?:existing?.phone.orEmpty()
    var pin by remember(existing?.id){mutableStateOf("")}
    val phoneFocus=remember{FocusRequester()};val pinFocus=remember{FocusRequester()}
    val enroll=s.draft["enroll"]=="true"
    val allocate=s.draft["allocate"]=="true"
    val normalized=runCatching{Values.phone(phone)}.getOrNull()
    val needsPin=existing==null||normalized!=existing.phone
    val ready=Presentation.validName(name)&&normalized!=null&&(!needsPin&&pin.isEmpty()||runCatching{Values.pin(pin)}.isSuccess)
    Panel{
        item{Entry(t("Name"),name,{m.editDraft("name",it)},enabled=!s.busy,nextFocus=phoneFocus)}
        item{Entry(t("Phone"),phone,{m.editDraft("phone",it)},phone=true,enabled=!s.busy,fieldFocus=phoneFocus,nextFocus=pinFocus)}
        item{Entry(if(existing==null)t("Passcode") else t("New passcode"),pin,{pin=it.filter { ch->ch in '0'..'9' }.take(4)},pin=true,enabled=!s.busy,imeAction=ImeAction.Done,fieldFocus=pinFocus)}
        item{Row(Modifier.fillMaxWidth().heightIn(min=48.dp).toggleable(value=enroll,enabled=!s.busy,role=SemanticRole.Switch,onValueChange={m.editDraft("enroll",it.toString())}),verticalAlignment=Alignment.CenterVertically){Text(t("Enroll members"),Modifier.weight(1f),fontSize=17.sp,lineHeight=25.sp);Switch(enroll,onCheckedChange=null,enabled=!s.busy)}}
        item{Row(Modifier.fillMaxWidth().heightIn(min=48.dp).toggleable(value=allocate,enabled=!s.busy,role=SemanticRole.Switch,onValueChange={m.editDraft("allocate",it.toString())}),verticalAlignment=Alignment.CenterVertically){Text(t("Allocate payments"),Modifier.weight(1f),fontSize=17.sp,lineHeight=25.sp);Switch(allocate,onCheckedChange=null,enabled=!s.busy)}}
        item{Primary(if(existing==null)t("Add staff") else t("Save"),{m.saveStaff(name,phone,pin,enroll,allocate);pin=""},ready&&!s.busy&&!s.offline&&!s.pending)}
        if(existing!=null){
            item{Primary(if(existing.active)t("Disable access") else t("Enable access"),{m.staffAction(if(existing.active)"disable" else "enable")},!s.busy&&!s.offline&&!s.pending,secondary=true)}
            item{Primary(t("Remove access"),m::requestRemoveStaff,!s.busy&&!s.offline,secondary=true)}
        }
    }
}
@Composable private fun GatewayPanel(s:UiState,m:BuriController,onPermissions:()->Unit,onPhoneSettings:()->Unit){
    val t=LocalUiText.current
    var code by remember{mutableStateOf("")}
    val g=s.gateway
    val health=GatewayHealth.describe(g)
    Panel{
        item{Text(t(health.title),Modifier.semantics{heading();liveRegion=LiveRegionMode.Polite},fontSize=24.sp,fontWeight=FontWeight.SemiBold,lineHeight=32.sp)}
        item{Text(t(health.explanation),fontSize=16.sp,color=BuriTheme.Muted,lineHeight=24.sp)}
        if(health.canPair){
            item{Entry(t("Pairing code"),code,{code=it.take(128)},enabled=!s.busy,imeAction=ImeAction.Done)}
            item{Primary(t("Pair phone"),{m.pair(code);code=""},code.trim().length in 4..128&&!s.busy&&!s.offline)}
        }
        if(g?.authorized==true){
            item{Fact(t("Local capture"),if(g.captureEnabled)t("Enabled") else t("Paused"))}
            item{Fact(t("Retained receipts"),if(g.pending>=0)g.pending.toString() else t("Unavailable"))}
            item{Fact(t("Bound Android subscription"),g.subscriptionId?.takeIf{it>=0}?.toString()?:t("Not verified"))}
            item{Text(t("The subscription number is Android metadata, not the MoMo phone number or proof of wallet ownership."),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)}
            item{Fact(t("Last local capture"),g.lastCapture?:t("Not recorded"));Fact(t("Last upload acknowledgement"),g.lastUpload?:t("Not recorded"));Fact(t("Oldest retained receipt"),g.oldest?:t("Not recorded"))}
            item{Text(t("Only canonical payment and ledger records confirm member credit. Never add the local queue to displayed savings."),fontSize=15.sp,color=BuriTheme.Muted,lineHeight=23.sp)}
            if(health.canPause)item{Primary(t("Pause capture"),{m.setPaused(true)},!s.busy,secondary=true)}
            if(health.canResume)item{Primary(t("Resume local capture"),{m.setPaused(false)},!s.busy,secondary=true)}
        }
        if(health.needsPermission)item{Primary(t("Review SMS access"),onPermissions,!s.busy,secondary=true)}
        item{Primary(t("Refresh phone status"),m::refresh,!s.busy,secondary=true)}
        item{Primary(t("Phone settings"),onPhoneSettings,!s.busy,secondary=true)}
        item{Primary(t("Contact admin"),{m.openSheet(Sheet.HELP)},!s.busy,secondary=true)}
        item{Text(t("Phone replacement and SIM changes require the administrator's controlled procedure. Do not move the SIM, reset app data or discard the queue as a recovery shortcut."),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)}
    }
}

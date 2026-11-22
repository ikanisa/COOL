package rw.ikanisa.burimunsi.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.ui.semantics.Role as SemanticRole
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.*
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.*
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.cool.mobile.BuildConfig
import app.cool.mobile.R
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.core.Role

@Composable internal fun SettingRow(icon:Int,title:String,subtitle:String?=null,enabled:Boolean=true,click:()->Unit){
    val action=focusAction("setting:$icon",click)
    Row(action.modifier.fillMaxWidth().heightIn(min=58.dp).clickable(enabled=enabled,role=SemanticRole.Button,onClick=action.click).semantics(mergeDescendants=true){}.padding(vertical=16.dp),verticalAlignment=Alignment.CenterVertically){
        Box(Modifier.size(42.dp).background(BuriTheme.Tone,CircleShape),contentAlignment=Alignment.Center){Glyph(icon,null,if(enabled)BuriTheme.Text else BuriTheme.Muted,23)};Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)){Text(title,fontSize=19.sp,maxLines=2,overflow=TextOverflow.Ellipsis,lineHeight=27.sp);if(subtitle!=null){Spacer(Modifier.height(5.dp));Text(subtitle,fontSize=14.sp,color=BuriTheme.Muted,lineHeight=22.sp)}}
        Glyph(R.drawable.ic_arrow,null,BuriTheme.Muted,18)
    }
}
@Composable internal fun SettingsScreen(s:UiState,m:BuriController,onPermissions:()->Unit,onPhoneSettings:()->Unit,onNotifications:()->Unit,onBatteryOptimization:()->Unit){
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
@Composable internal fun Login(busy:Boolean,signingIn:Boolean,login:(String,String)->Unit,support:()->Unit,supportAvailable:Boolean){
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
        item{Primary(t(if(signingIn)"Signing in…" else "Sign in"),{login(phone,pin);pin=""},ready&&!busy,icon=R.drawable.ic_arrow,iconTrailing=true,working=signingIn)}
        item{TextButton(support,Modifier.fillMaxWidth().heightIn(min=48.dp).padding(top=12.dp),enabled=supportAvailable&&!busy){Text(t("Contact admin"),color=if(supportAvailable&&!busy)BuriTheme.Blue else BuriTheme.Muted,fontSize=15.sp)}}
    }
}

@Composable internal fun PinPanel(busy:Boolean,pending:Boolean,save:(String,String,String)->Unit){
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

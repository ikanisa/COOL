package rw.ikanisa.burimunsi.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.*
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.cool.mobile.R
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.core.Role

@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun Sheets(s:UiState,m:BuriController,onSupport:()->Unit,onPermissions:()->Unit,
    onPickMemberFile:()->Unit,onPreviewMemberFile:(requestId:String)->Unit,onTakeMemberPhoto:()->Unit,onPickMemberPhoto:()->Unit,onExport:()->Unit){
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

package rw.ikanisa.burimunsi.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.ui.semantics.Role as SemanticRole
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.*
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import rw.ikanisa.burimunsi.core.*

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
@Composable internal fun SmartEnrollPanel(s:UiState,m:BuriController,onPickFile:()->Unit,onPreviewFile:(requestId:String)->Unit,
    onTakePhoto:()->Unit,onPickPhoto:()->Unit){
    val t=LocalUiText.current;val o=s.onboarding;val candidate=o.candidate;val enabled=!s.busy&&!s.offline&&!s.pending
    val name=s.draft["name"].orEmpty();val phone=s.draft["phone"].orEmpty();val phoneFocus=remember{FocusRequester()}
    val normalized=runCatching{Values.phone(phone)}.getOrNull()
    val ready=Presentation.validName(name)&&normalized!=null&&
        (candidate==null||normalized.endsWith(candidate.last3))&&o.verifiedOwnership&&o.acceptedTerms&&o.consentRecorded
    val previewNeedsConsent=SmartOnboardingPresentation.previewNeedsConsent(o.documentMimeType)
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
            item{SmartConsent("Full number and phone ownership verified",o.verifiedOwnership,enabled){m.onboardingConsent("ownership",it,s.draft)}}
            item{SmartConsent("Member accepted the savings terms",o.acceptedTerms,enabled){m.onboardingConsent("terms",it,s.draft)}}
            item{SmartConsent("Privacy notice and consent recorded",o.consentRecorded,enabled){m.onboardingConsent("consent",it,s.draft)}}
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
                    if(previewNeedsConsent)item{SmartConsent("I agree to send this document to OpenAI for text extraction",o.ocrConsent,enabled){value->o.documentRequestId?.let{m.onboardingDocumentConsent(it,value)}}}
                    item{Primary(t("Preview members"),{o.documentRequestId?.let(onPreviewFile)},enabled&&(!previewNeedsConsent||o.ocrConsent),secondary=true)}
                }
            }else if(!o.photoCaptureFlow){
                if(o.rows.isEmpty())item{Empty(t("No members"))}
                else item{Text(t("Review extracted members before saving"),fontSize=18.sp,fontWeight=FontWeight.SemiBold)}
            }else if(o.sourceKind==null&&(o.photoPreviewPending||s.busy||(o.documentUri==null&&s.error==null))){
                item{BuriInlineLoading("Working")}
            }else if(o.sourceKind==null&&o.documentUri!=null){
                item{Primary(t("Retry"),{o.documentRequestId?.let(onPreviewFile)},enabled,secondary=true)}
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

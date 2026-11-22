package rw.ikanisa.burimunsi.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.ui.semantics.Role as SemanticRole
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.cool.mobile.R
import rw.ikanisa.burimunsi.core.*

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
@Composable internal fun SmsScreen(s:UiState,m:BuriController,onExport:()->Unit){
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
        if(s.showSmsSearchNotice)item{Text(t("Clear SMS search to download source metadata. Message text is not included."),Modifier.padding(bottom=8.dp),fontSize=14.sp,lineHeight=22.sp,color=BuriTheme.Muted)}
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

private fun observationProcessingLabel(value:ObservationProcessing?):String=when(value?.status){
    "pending"->"Pending";"retrying"->"Retrying";"parsed"->"Parsed";"needs_review"->"Needs review"
    "conflict"->"Conflict";"duplicate"->"Duplicate";"security"->"Security message";"historical"->"Historical record"
    else->"Status unavailable"
}

/** Server-authorized plaintext exists only while this explicitly opened panel is visible. */
@Composable internal fun RawPanel(s:UiState,m:BuriController){
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

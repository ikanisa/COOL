package rw.ikanisa.burimunsi.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.cool.mobile.R
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.core.export.ExportFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

private val ListingZone=ZoneId.of("Africa/Kigali")
internal fun listingSortLabel(value:ListingSort)=when(value){
    ListingSort.NEWEST->"Newest first";ListingSort.OLDEST->"Oldest first"
    ListingSort.AMOUNT_ASC->"Amount · low to high";ListingSort.AMOUNT_DESC->"Amount · high to low"
    ListingSort.NAME_ASC->"Name · A–Z";ListingSort.NAME_DESC->"Name · Z–A"
    ListingSort.PHONE_ASC->"Phone · ascending";ListingSort.PHONE_DESC->"Phone · descending"
    ListingSort.BALANCE_ASC->"Balance · low to high";ListingSort.BALANCE_DESC->"Balance · high to low"
    ListingSort.ACTION_ASC->"Action · A–Z";ListingSort.ACTION_DESC->"Action · Z–A"
}
internal fun listingValueLabel(value:String)=when(value){
    "all"->"All";"allocated"->"Allocated";"unallocated"->"Unallocated";"processing"->"Processing"
    "recorded"->"Recorded";"posted","credited"->"Credited";"uncredited"->"Not credited"
    "reversed","reversal"->"Reversed";"corrected"->"Corrected";"conflict"->"Conflict"
    "queued"->"Queued";"duplicate"->"Duplicates";"synced"->"Synced";"rejected"->"Rejected"
    "transaction_recorded"->"Transaction recorded";"ledger_entry"->"Ledger entry recorded"
    "active"->"Active";"inactive"->"Inactive";"incoming"->"Incoming";"outgoing"->"Outgoing"
    "successful"->"Successful";"failed"->"Failed";"pending"->"Pending";"unknown"->"Unknown";else->"Other"
}
private fun dateText(value:String?,exclusive:Boolean=false):String=value?.let{runCatching{
    (if(exclusive)Instant.parse(it).minusNanos(1)else Instant.parse(it)).atZone(ListingZone).toLocalDate().toString()
}.getOrNull()}.orEmpty()
private fun selectedBound(value:String,end:Boolean):String?=value.takeIf{it.isNotBlank()}?.let{
    val day=LocalDate.parse(it);(if(end)day.plusDays(1)else day).atStartOfDay(ListingZone).toInstant().toString()
}

@Composable internal fun ListingToolbar(model:BuriController,onExport:()->Unit,showFilter:Boolean=true,showExport:Boolean=true){
    val target=model.listingTarget?:return
    val t=LocalUiText.current;val query=model.listingQuery
    val defaults=ListingQuery.defaultsFor(target);val enabled=!model.state.busy
    var sortOpen by remember(target){mutableStateOf(false)}
    val chips=buildList<Pair<String,()->Unit>>{
        if(query.q.isNotBlank())add(t("Search: %1\$s",query.q) to {model.applyListingQuery(query.copy(q=""))})
        if(query.filter!="all")add(t("Status: %1\$s",t(listingValueLabel(query.filter))) to {model.applyListingQuery(query.copy(filter="all"))})
        if(query.fromAt!=null||query.untilAt!=null)add(t("Date range") to {model.applyListingQuery(query.copy(fromAt=null,untilAt=null))})
        if(query.minRwf!=null||query.maxRwf!=null)add(t(if(target==ListingTarget.MEMBERS)"Balance range"else "Amount range") to {model.applyListingQuery(query.copy(minRwf=null,maxRwf=null))})
        if(query.active!="all")add(t(listingValueLabel(query.active)) to {model.applyListingQuery(query.copy(active="all"))})
        if(query.direction!="all")add(t(listingValueLabel(query.direction)) to {model.applyListingQuery(query.copy(direction="all"))})
        if(query.outcome!="all")add(t(listingValueLabel(query.outcome)) to {model.applyListingQuery(query.copy(outcome="all"))})
        if(query.credit!="all")add(t(listingValueLabel(query.credit)) to {model.applyListingQuery(query.copy(credit="all"))})
        if(query.sort!=defaults.sort)add(t(listingSortLabel(query.sort)) to {model.applyListingQuery(query.copy(sort=defaults.sort))})
    }
    Column(Modifier.fillMaxWidth().padding(top=10.dp,bottom=10.dp).testTag("listing-tools:${target.name}")){
        val filterControl:@Composable (Modifier)->Unit={modifier->
            OutlinedButton({model.openSheet(Sheet.FILTERS)},modifier.heightIn(min=48.dp),enabled=enabled,shape=RoundedCornerShape(24.dp),
                colors=ButtonDefaults.outlinedButtonColors(contentColor=BuriTheme.Text)){
                Icon(painterResource(R.drawable.ic_filter),null,Modifier.size(21.dp));Spacer(Modifier.width(8.dp))
                Text(t("Filters"),fontSize=15.sp,lineHeight=22.sp)
                if(chips.isNotEmpty()){Spacer(Modifier.width(6.dp));Text(chips.size.toString(),fontSize=13.sp,fontWeight=FontWeight.SemiBold)}
            }
        }
        val sortControl:@Composable (Modifier)->Unit={modifier->
            Box(modifier){
                OutlinedButton({sortOpen=true},Modifier.fillMaxWidth().heightIn(min=48.dp).testTag("listing-sort-menu"),enabled=enabled,shape=RoundedCornerShape(24.dp),colors=ButtonDefaults.outlinedButtonColors(contentColor=BuriTheme.Text)){
                    Icon(painterResource(R.drawable.ic_arrow),null,Modifier.size(19.dp).rotate(90f));Spacer(Modifier.width(8.dp));Text(t("Sort"),fontSize=15.sp,lineHeight=22.sp)
                }
                DropdownMenu(sortOpen,{sortOpen=false},containerColor=BuriTheme.Raised){
                    ListingQuery.allowedSorts(target).forEach{sort->DropdownMenuItem(
                        text={Text(t(listingSortLabel(sort)))},trailingIcon={if(sort==query.sort)Icon(painterResource(R.drawable.ic_check),null,Modifier.size(20.dp))},
                        onClick={sortOpen=false;model.applyListingQuery(query.copy(sort=sort))})}
                }
            }
        }
        val exportControl:@Composable ()->Unit={
            if(showExport&&model.canExportListing)IconButton(onExport,enabled=enabled&&!model.state.offline,modifier=Modifier.size(48.dp).background(BuriTheme.Tone,RoundedCornerShape(24.dp))){
                Icon(painterResource(R.drawable.ic_export),t("Export results"),Modifier.size(24.dp))
            }
        }
        BoxWithConstraints(Modifier.fillMaxWidth()){
            if(maxWidth<340.dp||LocalDensity.current.fontScale>=1.4f){
                Column(verticalArrangement=Arrangement.spacedBy(8.dp)){
                    if(showFilter)Row(horizontalArrangement=Arrangement.spacedBy(8.dp),verticalAlignment=Alignment.CenterVertically){filterControl(Modifier.weight(1f));exportControl()}
                    sortControl(Modifier.fillMaxWidth())
                    if(!showFilter)exportControl()
                }
            }else Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp),verticalAlignment=Alignment.CenterVertically){
                if(showFilter)filterControl(Modifier.weight(1f));sortControl(Modifier.weight(1f));exportControl()
            }
        }
        Text(t("Sorted by %1\$s",t(listingSortLabel(query.sort))),Modifier.padding(top=8.dp),fontSize=13.sp,lineHeight=21.sp,color=BuriTheme.Muted)
        if(chips.isNotEmpty()){
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp),verticalAlignment=Alignment.CenterVertically){
                chips.forEach{(label,clear)->FilterChip(selected=true,onClick=clear,enabled=enabled,label={Text(label)},trailingIcon={Icon(painterResource(R.drawable.ic_close),t("Remove filter"),Modifier.size(16.dp))},modifier=Modifier.heightIn(min=48.dp),shape=RoundedCornerShape(24.dp),colors=FilterChipDefaults.filterChipColors(selectedContainerColor=BuriTheme.Text,selectedLabelColor=Color(0xFF151517),selectedTrailingIconColor=Color(0xFF151517)))}
                TextButton(model::resetListingQuery,enabled=enabled){Text(t("Reset all"))}
            }
        }
    }
}

@Composable private fun QueryChoice(label:String,value:String,choices:List<Pair<String,String>>,enabled:Boolean,tag:String,onChange:(String)->Unit){
    val t=LocalUiText.current;var expanded by remember{mutableStateOf(false)}
    Column(Modifier.fillMaxWidth()){
        Text(t(label),fontSize=15.sp,color=BuriTheme.Muted);Spacer(Modifier.height(8.dp))
        Box{
            OutlinedButton({expanded=true},Modifier.fillMaxWidth().heightIn(min=56.dp).testTag(tag).semantics{contentDescription=t(label)},enabled=enabled,shape=RoundedCornerShape(17.dp),colors=ButtonDefaults.outlinedButtonColors(contentColor=BuriTheme.Text)){
                Text(t(choices.firstOrNull{it.first==value}?.second?:"All"),Modifier.weight(1f),fontSize=17.sp,lineHeight=25.sp)
                Icon(painterResource(R.drawable.ic_arrow),null,Modifier.size(18.dp).rotate(90f))
            }
            DropdownMenu(expanded,{expanded=false},containerColor=BuriTheme.Raised){choices.forEach{(key,text)->DropdownMenuItem(text={Text(t(text))},onClick={expanded=false;onChange(key)})}}
        }
    }
}

@Composable private fun QueryNumber(label:String,value:String,enabled:Boolean,onChange:(String)->Unit){
    val t=LocalUiText.current
    OutlinedTextField(value,onChange,Modifier.fillMaxWidth().semantics{contentDescription=t(label)},enabled=enabled,singleLine=true,
        label={Text(t(label))},keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Ascii),
        shape=RoundedCornerShape(17.dp),colors=OutlinedTextFieldDefaults.colors(focusedBorderColor=BuriTheme.Blue,unfocusedBorderColor=BuriTheme.Muted.copy(alpha=.35f)))
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun QueryDate(label:String,value:String,enabled:Boolean,onChange:(String)->Unit){
    val t=LocalUiText.current;var open by remember{mutableStateOf(false)}
    Column{
        Text(t(label),fontSize=15.sp,color=BuriTheme.Muted);Spacer(Modifier.height(8.dp))
        OutlinedButton({open=true},Modifier.fillMaxWidth().heightIn(min=56.dp).semantics{contentDescription=t(label)},enabled=enabled,shape=RoundedCornerShape(17.dp),colors=ButtonDefaults.outlinedButtonColors(contentColor=BuriTheme.Text)){
            Icon(painterResource(R.drawable.ic_clock),null,Modifier.size(20.dp));Spacer(Modifier.width(10.dp));Text(value.ifBlank{t("Any date")},Modifier.weight(1f),fontSize=16.sp)
        }
    }
    if(open){
        val initial=runCatching{LocalDate.parse(value).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()}.getOrNull()
        val picker=rememberDatePickerState(initialSelectedDateMillis=initial)
        DatePickerDialog(onDismissRequest={open=false},confirmButton={TextButton({picker.selectedDateMillis?.let{onChange(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString())};open=false}){Text(t("Apply"))}},dismissButton={TextButton({open=false}){Text(t("Cancel"))}}){DatePicker(picker)}
    }
}

@Composable internal fun ListingFiltersPanel(model:BuriController){
    val target=model.listingTarget?:return
    val t=LocalUiText.current;val current=model.listingQuery;val enabled=!model.state.busy
    var draft by remember(target,current){mutableStateOf(current)}
    var from by remember(target,current){mutableStateOf(dateText(current.fromAt))}
    var until by remember(target,current){mutableStateOf(dateText(current.untilAt,true))}
    var minimum by remember(target,current){mutableStateOf(current.minRwf?.toString().orEmpty())}
    var maximum by remember(target,current){mutableStateOf(current.maxRwf?.toString().orEmpty())}
    var error by remember(target,current){mutableStateOf<String?>(null)}
    fun apply(){
        try{
            fun number(value:String):Long?=value.takeIf{it.isNotBlank()}?.let{require(Regex("-?[0-9]+").matches(it));it.toLong()}
            val value=draft.copy(fromAt=selectedBound(from,false),untilAt=selectedBound(until,true),minRwf=number(minimum),maxRwf=number(maximum)).validated(target)
            error=null;model.applyListingQuery(value)
        }catch(_:Exception){error="Check the date and amount range."}
    }
    Panel(footer={
        Column(verticalArrangement=Arrangement.spacedBy(6.dp)){
            Primary(t("Apply"),::apply,enabled)
            TextButton({draft=ListingQuery.defaultsFor(target);from="";until="";minimum="";maximum="";error=null;model.resetListingQuery()},enabled=enabled,modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)){Text(t("Reset all"))}
        }
    }){
        if(target !in setOf(ListingTarget.SMS,ListingTarget.OBSERVATIONS))item{Entry(t("Search"),draft.q,{draft=draft.copy(q=it.take(80))},enabled=enabled)}
        if(ListingQuery.filters(target).size>1)item{QueryChoice("Status",draft.filter,ListingQuery.filters(target).map{it to listingValueLabel(it)},enabled,if(target==ListingTarget.PAYMENTS)"payment-filter-select"else "listing-filter-select"){draft=draft.copy(filter=it)}}
        item{QueryChoice("Sort by",draft.sort.wire,ListingQuery.allowedSorts(target).map{it.wire to listingSortLabel(it)},enabled,"listing-sort-select"){wire->draft=draft.copy(sort=ListingSort.entries.first{it.wire==wire})}}
        if(ListingQuery.supportsActive(target))item{QueryChoice(if(target==ListingTarget.STAFF)"Access status"else "Membership status",draft.active,listOf("all","active","inactive").map{it to listingValueLabel(it)},enabled,"listing-active-select"){draft=draft.copy(active=it)}}
        if(ListingQuery.supportsDirection(target))item{QueryChoice("Direction",draft.direction,listOf("all","incoming","outgoing","reversal","other").map{it to listingValueLabel(it)},enabled,"listing-direction-select"){draft=draft.copy(direction=it)}}
        if(ListingQuery.supportsOutcome(target))item{QueryChoice("Outcome",draft.outcome,listOf("all","successful","failed","pending","unknown").map{it to listingValueLabel(it)},enabled,"listing-outcome-select"){draft=draft.copy(outcome=it)}}
        if(ListingQuery.supportsCredit(target))item{QueryChoice("Member credit",draft.credit,listOf("all","credited","uncredited","reversed","corrected").map{it to listingValueLabel(it)},enabled,"listing-credit-select"){draft=draft.copy(credit=it)}}
        if(ListingQuery.supportsDates(target)){
            item{Text(t("Date range"),fontSize=20.sp,fontWeight=FontWeight.Medium);Text(t("Dates use Kigali time. End date is included."),fontSize=14.sp,lineHeight=22.sp,color=BuriTheme.Muted)}
            item{Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp)){
                for((days,label)in listOf(1L to "Today",7L to "Last 7 days",30L to "Last 30 days"))AssistChip(onClick={val today=LocalDate.now(ListingZone);from=today.minusDays(days-1).toString();until=today.toString()},label={Text(t(label))},enabled=enabled,modifier=Modifier.heightIn(min=48.dp))
            }}
            item{QueryDate("From date",from,enabled){from=it}}
            item{QueryDate("Through date",until,enabled){until=it}}
        }
        if(ListingQuery.supportsAmount(target)){
            item{Text(t(if(target==ListingTarget.MEMBERS)"Balance range"else "Amount range"),fontSize=20.sp,fontWeight=FontWeight.Medium);Text(t("Whole RWF values. Leave empty for no limit."),fontSize=14.sp,lineHeight=22.sp,color=BuriTheme.Muted)}
            item{QueryNumber("Minimum RWF",minimum,enabled){minimum=it.take(18)}}
            item{QueryNumber("Maximum RWF",maximum,enabled){maximum=it.take(18)}}
        }
        error?.let{message->item{Text(t(message),Modifier.semantics{liveRegion=LiveRegionMode.Polite},color=BuriTheme.Bad,fontSize=15.sp,lineHeight=23.sp)}}
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun ListingExportSheet(model:BuriController,onPick:(ExportFormat)->Unit,onDismiss:()->Unit){
    val t=LocalUiText.current
    val target=model.listingTarget?:return
    val formats=ExportFormat.entries.filter{it!=ExportFormat.CSV||(model.state.route==Route.MEMBER&&model.state.sheet==null)}
    ModalBottomSheet(onDismissRequest=onDismiss,containerColor=BuriTheme.Surface,contentColor=BuriTheme.Text,
        shape=RoundedCornerShape(topStart=32.dp,topEnd=32.dp),scrimColor=Color.Black.copy(alpha=.62f)){
        Column(Modifier.fillMaxWidth().heightIn(max=LocalConfiguration.current.screenHeightDp.dp*.9f).verticalScroll(rememberScrollState()).padding(horizontal=24.dp).navigationBarsPadding().padding(bottom=24.dp).testTag("export-format-sheet").semantics{paneTitle=t("Export results")}){
            Row(verticalAlignment=Alignment.CenterVertically){
                Text(t("Export results"),Modifier.weight(1f).semantics{heading()},fontSize=28.sp,lineHeight=36.sp,fontWeight=FontWeight.SemiBold)
                IconButton(onDismiss,Modifier.size(48.dp)){Icon(painterResource(R.drawable.ic_close),t("Close"))}
            }
            Text(t(if(model.state.route==Route.MEMBER&&model.state.sheet==null)"Excel and PDF use the selected transaction filters. CSV includes the full member ledger."else "Current filters and sort are included."),Modifier.padding(vertical=12.dp),fontSize=15.sp,lineHeight=23.sp,color=BuriTheme.Muted)
            if(target in setOf(ListingTarget.SMS,ListingTarget.OBSERVATIONS))Text(t("SMS exports contain authorized metadata only. Message content is excluded."),Modifier.padding(bottom=12.dp),fontSize=15.sp,lineHeight=23.sp,color=BuriTheme.Warn)
            formats.forEach{format->
                val label=when(format){ExportFormat.CSV->"Full member ledger (CSV)";ExportFormat.XLSX->"Excel workbook (.xlsx)";ExportFormat.PDF->"PDF document (.pdf)"}
                OutlinedButton({onPick(format)},Modifier.fillMaxWidth().padding(vertical=5.dp).heightIn(min=60.dp).testTag("export-format:${format.name}"),enabled=model.canExportListing&&!model.state.busy&&!model.state.offline,shape=RoundedCornerShape(20.dp),colors=ButtonDefaults.outlinedButtonColors(contentColor=BuriTheme.Text)){
                    Icon(painterResource(R.drawable.ic_export),null,Modifier.size(24.dp));Spacer(Modifier.width(14.dp));Text(t(label),Modifier.weight(1f),fontSize=18.sp,lineHeight=26.sp)
                }
            }
        }
    }
}

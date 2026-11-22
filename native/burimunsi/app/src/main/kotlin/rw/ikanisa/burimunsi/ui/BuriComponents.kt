package rw.ikanisa.burimunsi.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.rememberLazyListState
import kotlinx.coroutines.flow.distinctUntilChanged
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
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
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.*
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.cool.mobile.R
import rw.ikanisa.burimunsi.core.*
import java.util.Locale

internal fun money(value:Long,locale:Locale):String=ExactDisplay.amount(value,locale.toLanguageTag()).orEmpty()
private fun initials(value:String):String=value.trim().split(Regex("\\s+")).filter{it.isNotEmpty()}.take(2).joinToString(""){it.take(1).uppercase(Locale.ROOT)}
internal fun historyTime(value:String,locale:Locale):String=ExactDisplay.timestamp(value,locale.toLanguageTag())?:value

@Composable internal fun Brand(){
    Image(painterResource(R.drawable.burimunsi_brand_logo),"BuriMunsi",Modifier.width(156.dp).height(52.dp))
}

@Composable fun SingleLineName(name:String,modifier:Modifier=Modifier,size:Int=19,alignment:TextAlign=TextAlign.Start){
    Text(name,modifier.clearAndSetSemantics{contentDescription=name},fontSize=size.sp,fontWeight=FontWeight.Medium,maxLines=1,overflow=TextOverflow.Ellipsis,lineHeight=(size+8).sp,textAlign=alignment)
}
@Composable internal fun Glyph(icon:Int,description:String?,tint:Color=BuriTheme.Text,size:Int=24){
    val t=LocalUiText.current
    Icon(painterResource(icon),description?.let{t(it)},Modifier.size(size.dp),tint)
}
@Composable internal fun RoundAction(icon:Int,label:String,click:()->Unit,enabled:Boolean=true,size:Int=56,tonal:Boolean=true){
    val action=focusAction("action:$label",click)
    IconButton(action.click,action.modifier.size(size.dp).background(if(tonal)BuriTheme.Tone else Color.Transparent,CircleShape),enabled=enabled){Glyph(icon,label,if(enabled)BuriTheme.Text else BuriTheme.Muted,24)}
}
@Composable internal fun Avatar(name:String,size:Int=46,unallocated:Boolean=false,initialsSize:Int=15){
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
@Composable internal fun Fact(label:String,value:String){
    val t=LocalUiText.current
    Row(Modifier.fillMaxWidth().padding(vertical=15.dp),horizontalArrangement=Arrangement.spacedBy(16.dp),verticalAlignment=Alignment.Top){
        Text(t(label),Modifier.weight(.44f),fontSize=14.sp,color=BuriTheme.Muted,lineHeight=21.sp)
        Text(value,Modifier.weight(.64f),fontSize=17.sp,fontWeight=FontWeight.Medium,lineHeight=25.sp,textAlign=TextAlign.End)
    }
}
@Composable internal fun FactGroup(facts:List<Pair<String,String>>,surface:Color=BuriTheme.Surface){
    Column(Modifier.fillMaxWidth().background(surface,RoundedCornerShape(24.dp)).padding(horizontal=18.dp,vertical=4.dp)){
        facts.forEachIndexed{index,(label,value)->
            Fact(label,value)
            if(index<facts.lastIndex)HorizontalDivider(color=Color.White.copy(alpha=.08f))
        }
    }
}
internal fun stateIcon(name:String)=when(name){"check"->R.drawable.ic_check;"link"->R.drawable.ic_link;"history"->R.drawable.ic_history;"sync"->R.drawable.ic_sync;"clock"->R.drawable.ic_clock;else->R.drawable.ic_alert}
@Composable internal fun stateTone(name:String)=when(name){"good"->BuriTheme.Good;"bad"->BuriTheme.Bad;"warn"->BuriTheme.Warn;else->BuriTheme.Blue}
@Composable internal fun MoneyText(value:Long?,modifier:Modifier=Modifier,size:Int=22,positiveSign:Boolean=false,showHint:Boolean=false){
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
@Composable internal fun BigValue(amount:Long?,size:Int=64){
    val t=LocalUiText.current
    Column(Modifier.fillMaxWidth().padding(vertical=14.dp),horizontalAlignment=Alignment.CenterHorizontally){
        MoneyText(amount,Modifier.widthIn(max=800.dp),size,showHint=true)
        if(amount!=null){Spacer(Modifier.height(8.dp));Text(t("RWF"),fontSize=16.sp,color=BuriTheme.Muted,lineHeight=24.sp)}
    }
}
@Composable internal fun routeList(s: UiState, m: BuriController): androidx.compose.foundation.lazy.LazyListState {
    val revision = s.memberViewportRevision.takeIf { s.route == Route.MEMBERS }
    // The verified member bookmark owns this position, including after process recreation.
    val scroll = if (revision != null) remember(revision) {
        androidx.compose.foundation.lazy.LazyListState(s.listIndex, s.listOffset)
    } else rememberLazyListState(s.listIndex, s.listOffset)
    LaunchedEffect(scroll, s.route, s.routeId, revision, s.busy) {
        if (s.busy) return@LaunchedEffect
        snapshotFlow {
            val index = scroll.firstVisibleItemIndex
            val visibleKey = if (revision != null) {
                val item = scroll.layoutInfo.visibleItemsInfo.firstOrNull { it.index == index } ?: return@snapshotFlow null
                item.key as? String
            } else null
            Triple(index, scroll.firstVisibleItemScrollOffset, visibleKey)
        }.distinctUntilChanged().collect { position ->
            if (position != null) {
                val (index, offset, visibleKey) = position
                if (revision == null) m.listPosition(s.route, s.routeId, index, offset)
                else m.memberListPosition(revision, index, offset, visibleKey)
            }
        }
    }
    return scroll
}
@Composable internal fun Empty(label:String="No records"){
    val t=LocalUiText.current
    Column(Modifier.fillMaxWidth().padding(vertical=36.dp),horizontalAlignment=Alignment.CenterHorizontally){Glyph(R.drawable.ic_activity,null,BuriTheme.Muted,36);Spacer(Modifier.height(14.dp));Text(t(label),Modifier.semantics{liveRegion=LiveRegionMode.Polite},color=BuriTheme.Muted,fontSize=18.sp,lineHeight=26.sp)}}
@Composable internal fun OverviewTitle(label:String){Text(label,Modifier.padding(top=12.dp,bottom=24.dp).semantics{heading()},fontSize=40.sp,fontWeight=FontWeight.SemiBold,lineHeight=44.sp,letterSpacing=(-1.6).sp)}
@Composable internal fun CountLine(left:String,right:String){Row(Modifier.fillMaxWidth().padding(start=3.dp,end=3.dp,bottom=10.dp),horizontalArrangement=Arrangement.SpaceBetween){Text(left,color=BuriTheme.Muted,fontSize=13.sp);Text(right,color=BuriTheme.Muted,fontSize=13.sp)}}
@Composable internal fun Section(label:String){
    val t=LocalUiText.current
    Text(t(label),Modifier.padding(top=12.dp,bottom=2.dp).semantics{heading()},fontSize=24.sp,fontWeight=FontWeight.SemiBold,lineHeight=32.sp)}
@Composable internal fun Search(value:String,change:(String)->Unit,submit:()->Unit,hint:String="Search",busy:Boolean=false){
    val t=LocalUiText.current
    var submitted by remember{mutableStateOf(value)}
    LaunchedEffect(value){if(value!=submitted){kotlinx.coroutines.delay(250);submitted=value;submit()}}
    OutlinedTextField(value,change,Modifier.fillMaxWidth().heightIn(min=56.dp).semantics{contentDescription=t(hint)},singleLine=true,enabled=!busy,
        textStyle=LocalTextStyle.current.copy(fontSize=18.sp),placeholder={Text(t(hint),color=BuriTheme.Muted,fontSize=18.sp)},leadingIcon={Glyph(R.drawable.ic_search,null,BuriTheme.Muted,22)},
        keyboardOptions=KeyboardOptions(autoCorrectEnabled=false,imeAction=ImeAction.Search),keyboardActions=KeyboardActions(onSearch={submitted=value;submit()}),
        shape=RoundedCornerShape(28.dp),colors=OutlinedTextFieldDefaults.colors(focusedContainerColor=BuriTheme.Tone,unfocusedContainerColor=BuriTheme.Tone,focusedBorderColor=BuriTheme.Blue,unfocusedBorderColor=Color.Transparent))
}
@Composable internal fun FilterChipIcon(label:String,icon:Int,chosen:Boolean,count:Int?=null,click:()->Unit){
    val t=LocalUiText.current
    FilterChip(selected=chosen,onClick=click,label={Row(verticalAlignment=Alignment.CenterVertically){if(chosen)Text(t(label),maxLines=1);if(count!=null&&count>0){if(chosen)Spacer(Modifier.width(8.dp));Text(count.toString(),fontSize=12.sp,fontWeight=FontWeight.SemiBold)}}},leadingIcon={Glyph(icon,label,if(chosen)Color(0xFF151517)else BuriTheme.Text,20)},modifier=Modifier.heightIn(min=48.dp),shape=RoundedCornerShape(24.dp),colors=FilterChipDefaults.filterChipColors(containerColor=BuriTheme.Tone,selectedContainerColor=BuriTheme.Text,labelColor=BuriTheme.Text,selectedLabelColor=Color(0xFF151517)))
}
internal fun LazyListScope.moreButton(cursor:String?,busy:Boolean,more:()->Unit,key:String="pagination",autoEnabled:Boolean=true){
    if(cursor!=null)item(key=key){
        // Preserve the prototype's continuous list while honoring actual server cursors.
        LaunchedEffect(cursor,busy,autoEnabled){if(!busy&&autoEnabled)more()}
        if(busy)BuriInlineLoading("Loading more")else if(!autoEnabled)TextButton(more,Modifier.fillMaxWidth().heightIn(min=52.dp)){Text(LocalUiText.current("Retry loading"))}else Spacer(Modifier.height(52.dp))
    }
}
internal fun rowShape(first:Boolean,last:Boolean)=RoundedCornerShape(topStart=if(first)24.dp else 0.dp,topEnd=if(first)24.dp else 0.dp,bottomStart=if(last)24.dp else 0.dp,bottomEnd=if(last)24.dp else 0.dp)

@Composable internal fun Panel(footer:(@Composable ()->Unit)?=null,content:LazyListScope.()->Unit){
    val memory=LocalUiFocusMemory.current;val scope=LocalUiFocusScope.current
    val position=memory.scrollPositions[scope]?:(0 to 0);val scroll=rememberLazyListState(position.first,position.second)
    LaunchedEffect(scope,scroll){snapshotFlow{scroll.firstVisibleItemIndex to scroll.firstVisibleItemScrollOffset}.distinctUntilChanged().collect{memory.scrollPositions[scope]=it}}
    Column(Modifier.fillMaxWidth()){
        LazyColumn(Modifier.fillMaxWidth().weight(1f,fill=false),state=scroll,contentPadding=PaddingValues(22.dp,0.dp,22.dp,20.dp),verticalArrangement=Arrangement.spacedBy(20.dp),content=content)
        if(footer!=null){HorizontalDivider(color=Color.White.copy(alpha=.08f));Box(Modifier.fillMaxWidth().padding(start=22.dp,end=22.dp,top=14.dp,bottom=25.dp)){footer()}}
    }
}

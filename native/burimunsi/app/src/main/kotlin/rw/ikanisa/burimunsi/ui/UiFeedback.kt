package rw.ikanisa.burimunsi.ui

import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.cool.mobile.R
import kotlin.math.cos
import kotlin.math.sin

internal val LocalBuriMotionAllowed=staticCompositionLocalOf{false}

/** One observer for the app subtree; neither display preference needs a permission. */
@Composable internal fun BuriMotionProvider(content:@Composable ()->Unit){
    val context=LocalContext.current
    val preferredReduction=LocalUiPreferences.current.reduceMotion
    fun systemReduction()=runCatching{Settings.Global.getFloat(context.contentResolver,Settings.Global.ANIMATOR_DURATION_SCALE,1f)<=0f}.getOrDefault(false)
    var systemReduced by remember(context){mutableStateOf(systemReduction())}
    DisposableEffect(context){
        val observer=object:ContentObserver(Handler(Looper.getMainLooper())){
            override fun onChange(selfChange:Boolean){systemReduced=systemReduction()}
        }
        val registered=runCatching{context.contentResolver.registerContentObserver(Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE),false,observer)}.isSuccess
        onDispose{if(registered)runCatching{context.contentResolver.unregisterContentObserver(observer)}}
    }
    CompositionLocalProvider(LocalBuriMotionAllowed provides (!preferredReduction&&!systemReduced),content=content)
}

@Composable private fun workPhase(reverse:Boolean=false):Float {
    if(!LocalBuriMotionAllowed.current)return .35f
    val transition=rememberInfiniteTransition(label="buri-active-work")
    val phase by transition.animateFloat(0f,1f,infiniteRepeatable(tween(if(reverse)1100 else 1250,easing=LinearEasing),if(reverse)RepeatMode.Reverse else RepeatMode.Restart),label="work-phase")
    return phase
}

/** A quiet orbit is indeterminate. It never represents percentage or success. */
@Composable internal fun BuriOrbit(modifier:Modifier=Modifier,size:Int=28,tint:Color=BuriTheme.Blue){
    val phase=workPhase()
    Canvas(modifier.size(size.dp).clearAndSetSemantics{}){
        val stroke=2.4.dp.toPx();val radius=(this.size.minDimension-stroke)/2f
        drawCircle(tint.copy(alpha=.14f),radius,style=Stroke(stroke))
        drawArc(tint,startAngle=phase*360f-90f,sweepAngle=108f,useCenter=false,
            topLeft=Offset(stroke/2f,stroke/2f),size=androidx.compose.ui.geometry.Size(radius*2,radius*2),style=Stroke(stroke,cap=StrokeCap.Round))
        val angle=(phase*360f+46f)*Math.PI/180f
        drawCircle(tint.copy(alpha=.65f),stroke*.8f,Offset(center.x+cos(angle).toFloat()*radius,center.y+sin(angle).toFloat()*radius))
    }
}

@Composable internal fun BuriInlineLoading(label:String,modifier:Modifier=Modifier){
    val t=LocalUiText.current
    Row(modifier.fillMaxWidth().heightIn(min=52.dp).padding(vertical=12.dp)
        .semantics(mergeDescendants=true){progressBarRangeInfo=ProgressBarRangeInfo.Indeterminate;liveRegion=LiveRegionMode.Polite},
        horizontalArrangement=Arrangement.Center,verticalAlignment=Alignment.CenterVertically){
        BuriOrbit(size=24);Spacer(Modifier.width(12.dp));Text(t(label),color=BuriTheme.Muted,fontSize=15.sp,lineHeight=23.sp)
    }
}

@Composable internal fun BuriWorkingStrip(operation:UiOperation,label:String?=null){
    if(operation==UiOperation.NONE||operation==UiOperation.LOAD_MORE)return
    val text=label?:when(operation){
        UiOperation.INITIAL_READ->"Loading records";UiOperation.REFRESH->"Updating records"
        UiOperation.COMMAND->"Applying changes";UiOperation.EXPORT->"Preparing export";else->"Working"
    }
    val t=LocalUiText.current
    Row(Modifier.fillMaxWidth().padding(horizontal=20.dp,vertical=6.dp)
        .background(BuriTheme.Tone,RoundedCornerShape(18.dp)).padding(horizontal=14.dp,vertical=10.dp)
        .testTag("active-operation:${operation.name}").semantics(mergeDescendants=true){progressBarRangeInfo=ProgressBarRangeInfo.Indeterminate;liveRegion=LiveRegionMode.Polite},
        verticalAlignment=Alignment.CenterVertically){
        BuriOrbit(size=25);Spacer(Modifier.width(12.dp));Text(t(text),Modifier.weight(1f),fontSize=15.sp,lineHeight=23.sp,color=BuriTheme.Text)
    }
}

/** Placeholder geometry contains no amount, identity, count or empty-state claim. */
@Composable internal fun BuriSkeletonRows(rows:Int=4){
    val pulse=workPhase(reverse=true)
    val fill=BuriTheme.Text.copy(alpha=.055f+pulse*.045f)
    Column(Modifier.fillMaxWidth().clearAndSetSemantics{this[SemanticsProperties.TestTag]="loading-skeleton"},verticalArrangement=Arrangement.spacedBy(2.dp)){
        repeat(rows.coerceIn(1,6)){index->
            Row(Modifier.fillMaxWidth().height(86.dp).background(BuriTheme.Group,RoundedCornerShape(18.dp)).padding(16.dp),verticalAlignment=Alignment.CenterVertically){
                Box(Modifier.size(43.dp).background(fill,CircleShape));Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(11.dp)){
                    Box(Modifier.fillMaxWidth(if(index%2==0).69f else .55f).height(13.dp).background(fill,RoundedCornerShape(8.dp)))
                    Box(Modifier.fillMaxWidth(.84f).height(9.dp).background(fill.copy(alpha=fill.alpha*.7f),RoundedCornerShape(6.dp)))
                }
                Spacer(Modifier.width(16.dp));Box(Modifier.width(42.dp).height(12.dp).background(fill,RoundedCornerShape(8.dp)))
            }
        }
    }
}

@Composable internal fun BuriLoadingPanel(label:String,modifier:Modifier=Modifier,skeleton:Boolean=true){
    Column(modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp)){
        BuriInlineLoading(label);Spacer(Modifier.height(16.dp))
        if(skeleton)BuriSkeletonRows()
    }
}

@Composable internal fun BuriStatusMessage(label:String,error:Boolean=false,warning:Boolean=false){
    val t=LocalUiText.current;val tint=if(error)BuriTheme.Bad else if(warning)BuriTheme.Warn else BuriTheme.Blue
    Row(Modifier.fillMaxWidth().padding(horizontal=20.dp,vertical=6.dp).background(tint.copy(alpha=.08f),RoundedCornerShape(18.dp))
        .padding(horizontal=14.dp,vertical=12.dp).semantics(mergeDescendants=true){liveRegion=LiveRegionMode.Polite},verticalAlignment=Alignment.Top){
        Icon(painterResource(if(error||warning)R.drawable.ic_alert else R.drawable.ic_info),null,Modifier.size(22.dp),tint)
        Spacer(Modifier.width(12.dp));Text(t(label),Modifier.weight(1f),fontSize=15.sp,lineHeight=23.sp,color=tint)
    }
}

@Composable internal fun BuriExportFeedback(value:UiExportFeedback,cancel:()->Unit,dismiss:()->Unit){
    val t=LocalUiText.current
    val terminal=value.phase in setOf(UiExportPhase.COMPLETE,UiExportPhase.CANCELLED,UiExportPhase.FAILED)
    val title=when(value.phase){
        UiExportPhase.PREPARING->"Preparing export";UiExportPhase.CHOOSING_DESTINATION->"Choose where to save"
        UiExportPhase.WRITING->"Saving file";UiExportPhase.COMPLETE->"File saved";UiExportPhase.CANCELLED->"Export cancelled";UiExportPhase.FAILED->"Export failed"
    }
    Column(Modifier.fillMaxWidth().padding(horizontal=20.dp,vertical=6.dp).background(BuriTheme.Raised,RoundedCornerShape(20.dp)).padding(16.dp)
        .testTag("export-feedback:${value.phase.name}").semantics(mergeDescendants=true){liveRegion=LiveRegionMode.Polite}){
        Row(verticalAlignment=Alignment.CenterVertically){
            if(!terminal)BuriOrbit(size=26) else Icon(painterResource(if(value.phase==UiExportPhase.COMPLETE)R.drawable.ic_check else R.drawable.ic_alert),null,Modifier.size(26.dp),if(value.phase==UiExportPhase.FAILED)BuriTheme.Bad else BuriTheme.Muted)
            Spacer(Modifier.width(12.dp));Text(t(title),Modifier.weight(1f),fontSize=17.sp,fontWeight=FontWeight.Medium,lineHeight=25.sp)
            if(terminal)IconButton(dismiss,Modifier.size(48.dp)){Icon(painterResource(R.drawable.ic_close),t("Dismiss export status"))}
        }
        value.fileName?.let{Spacer(Modifier.height(6.dp));Text(it,fontSize=14.sp,lineHeight=22.sp,color=BuriTheme.Muted)}
        if(value.phase==UiExportPhase.PREPARING){
            val done=value.completedRows;val total=value.totalRows
            if(done!=null&&total!=null&&done>=0&&total>=done){
                Spacer(Modifier.height(10.dp));Text(t("%1\$d of %2\$d rows",done,total),fontSize=14.sp,color=BuriTheme.Muted)
                if(total>0){Spacer(Modifier.height(8.dp));LinearProgressIndicator(progress={done.toFloat()/total},modifier=Modifier.fillMaxWidth(),color=BuriTheme.Blue,trackColor=BuriTheme.Tone)}
            }
        }
        value.error?.let{Spacer(Modifier.height(8.dp));Text(t(it),fontSize=15.sp,lineHeight=23.sp,color=BuriTheme.Bad)}
        if(value.canCancel&&!terminal)TextButton(cancel){Text(t("Cancel export"))}
    }
}

package rw.ikanisa.burimunsi.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/** Focus keys are session-memory only. No names, raw receipts or credentials are persisted. */
class UiFocusMemory {
    val origins=mutableMapOf<String,String>()
    val targets=mutableMapOf<String,FocusRequester>()
    val scrollPositions=mutableMapOf<String,Pair<Int,Int>>()
}
val LocalUiFocusMemory=staticCompositionLocalOf { UiFocusMemory() }
val LocalUiFocusScope=staticCompositionLocalOf { "root" }
data class FocusAction(val modifier:Modifier,val click:()->Unit)
@Composable fun focusAction(key:String,click:()->Unit):FocusAction {
    val memory=LocalUiFocusMemory.current
    val scope=LocalUiFocusScope.current
    // The composition key distinguishes repeated controls with the same accessible label.
    val position=currentCompositeKeyHashCode
    val targetKey="$scope/$key/$position"
    val target=remember(targetKey){FocusRequester()}
    DisposableEffect(memory,targetKey,target){
        memory.targets[targetKey]=target
        onDispose{if(memory.targets[targetKey]===target)memory.targets.remove(targetKey)}
    }
    return FocusAction(Modifier.focusRequester(target)){
        memory.origins[scope]=targetKey
        click()
    }
}
@Composable fun FocusReturnEffect(scope:String){
    val memory=LocalUiFocusMemory.current
    LaunchedEffect(scope){
        // A returning lazy row may not be attached on the first frame.
        repeat(3){
            withFrameNanos{}
            val target=memory.origins[scope]?.let{memory.targets[it]}
            if(target!=null&&runCatching{target.requestFocus()}.getOrDefault(false))return@LaunchedEffect
        }
    }
}
/** Entry-only motion: outgoing financial records are disposed, never cross-faded underneath. */
@Composable fun RouteEntrance(title:String,content:@Composable ()->Unit){
    val reduced=!LocalBuriMotionAllowed.current
    val progress=remember{Animatable(if(reduced)1f else 0f)}
    val distance=with(LocalDensity.current){6.dp.toPx()}
    LaunchedEffect(reduced){
        if(reduced)progress.snapTo(1f) else progress.animateTo(1f,tween(160))
    }
    // Animatable also respects Android's system MotionDurationScale.
    Box(Modifier.fillMaxSize().semantics{paneTitle=title}.graphicsLayer{
        alpha=progress.value;translationY=(1f-progress.value)*distance
    }){content()}
}

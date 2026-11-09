package rw.ikanisa.burimunsi.ui

import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import rw.ikanisa.burimunsi.core.Route

/** BuriMunsi adaptation of revolut-design@jean-bosco-skills Dark/Glow references.
 * These local rendering values are provisional adapters, not exported native tokens.
 * Preserve the product's identity and task routes; see the integration review.
 */
object BuriTheme {
    val Canvas=Color(0xFF000000);val Surface=Color(0xFF161618);val Raised=Color(0xFF232326)
    val Input=Color(0xFF28282B);val Text=Color(0xFFF4F4F4);val Muted=Color(0xFFD2D2D5)
    val Blue=Color(0xFFB8C6FF);val Good=Color(0xFF8CE8CB);val Warn=Color(0xFFFFD190);val Bad=Color(0xFFFFB5BF)
    // 50% black scrim over the original wash keeps secondary text readable.
    const val WashScrimAlpha=.50f
    private fun type(size:Int,line:Int,weight:FontWeight=FontWeight.Normal)=TextStyle(
        fontFamily=FontFamily.SansSerif,fontWeight=weight,fontSize=size.sp,lineHeight=line.sp)
    val Typography=Typography(
        displayLarge=type(64,72,FontWeight.Medium),displayMedium=type(48,56,FontWeight.Medium),displaySmall=type(40,48,FontWeight.SemiBold),
        headlineLarge=type(32,40,FontWeight.SemiBold),headlineMedium=type(28,36,FontWeight.SemiBold),headlineSmall=type(24,32,FontWeight.SemiBold),
        titleLarge=type(22,30,FontWeight.Medium),titleMedium=type(19,27,FontWeight.Medium),titleSmall=type(17,25,FontWeight.Medium),
        bodyLarge=type(17,26),bodyMedium=type(16,24),bodySmall=type(14,21),
        labelLarge=type(18,26,FontWeight.SemiBold),labelMedium=type(14,21,FontWeight.Medium),labelSmall=type(14,21))
    fun wash(route:Route):Brush = when(route){
        Route.HOME->Brush.verticalGradient(0f to Color(0xFF1C53EC),.18f to Color(0xFF1746CA),.38f to Color(0xFF132F86),.62f to Color(0xFF0B1738),.84f to Color(0xFF05070E),1f to Canvas)
        Route.PAYMENTS->Brush.verticalGradient(0f to Color(0xFF7338BF),.23f to Color(0xFF512689),.46f to Color(0xFF321D50),.70f to Color(0xFF170F24),1f to Canvas)
        Route.MEMBERS->Brush.verticalGradient(0f to Color(0xFF078A94),.21f to Color(0xFF086574),.43f to Color(0xFF08414B),.67f to Color(0xFF072127),1f to Canvas)
        Route.SMS->Brush.verticalGradient(0f to Color(0xFF535D94),.23f to Color(0xFF353D6A),.46f to Color(0xFF202746),.70f to Color(0xFF101323),1f to Canvas)
        Route.LOGIN->Brush.verticalGradient(0f to Color(0xFF3B4E8A),.24f to Color(0xFF253A71),.53f to Color(0xFF152447),.80f to Color(0xFF080F21),1f to Canvas)
        else->Brush.verticalGradient(listOf(Canvas,Canvas))
    }
}
/** Optional overrides make instrumentation deterministic without changing installation preferences. */
@Composable fun BuriContent(languageTag:String?=null,reduceMotion:Boolean?=null,content:@Composable ()->Unit) {
    UiPreferencesProvider(languageTag,reduceMotion) {
        MaterialTheme(colorScheme=darkColorScheme(
            primary=BuriTheme.Text,onPrimary=Color(0xFF151517),secondary=BuriTheme.Blue,
            background=BuriTheme.Canvas,surface=BuriTheme.Surface,onSurface=BuriTheme.Text,
            onSurfaceVariant=BuriTheme.Muted,error=BuriTheme.Bad,onBackground=BuriTheme.Text),
            typography=BuriTheme.Typography) {
            Surface(Modifier.fillMaxSize(),color=BuriTheme.Canvas,contentColor=BuriTheme.Text,content=content)
        }
    }
}

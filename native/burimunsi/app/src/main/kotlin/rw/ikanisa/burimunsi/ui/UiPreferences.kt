package rw.ikanisa.burimunsi.ui

import android.content.Context
import android.content.res.Configuration
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import java.util.Locale

/** Presentation copy only. Never apply this to evidence, personal names or identifiers. */
internal class UiText(private val context:Context,val locale:Locale) {
    operator fun invoke(english:String,vararg arguments:Any):String {
        val id=UiStringIds[english]
        return if(id!=null) {
            if(arguments.isEmpty())context.getString(id) else context.getString(id,*arguments)
        } else {
            // Unknown service messages remain unchanged. No heuristic translation of records.
            if(arguments.isEmpty())english else String.format(locale,english,*arguments)
        }
    }
}
internal data class UiPreferences(
    val language:String,val reduceMotion:Boolean,
    val setLanguage:(String)->Unit,val setReduceMotion:(Boolean)->Unit,
)
internal val LocalUiText=staticCompositionLocalOf<UiText>{error("BuriContent is required")}
internal val LocalUiPreferences=staticCompositionLocalOf<UiPreferences>{error("BuriContent is required")}

/** Stores only display preferences. No operator, session, receipt, form or credential data. */
@Composable internal fun UiPreferencesProvider(languageTag:String?,reduceMotion:Boolean?,content:@Composable ()->Unit){
    val context=LocalContext.current
    val configuration=LocalConfiguration.current
    val settings=remember(context){context.applicationContext.getSharedPreferences("buri-display",Context.MODE_PRIVATE)}
    var language by remember{mutableStateOf(settings.getString("language","system")?.takeIf{it in setOf("system","en","rw")}?:"system")}
    var reduced by remember{mutableStateOf(settings.getBoolean("reduce-screen-motion",false))}
    val selected=languageTag?:language
    val system=configuration.locales[0]?.language?:"en"
    val effective=if(selected=="system")system else selected
    val locale=if(effective=="rw")Locale.forLanguageTag("rw-RW")else Locale.forLanguageTag("en-RW")
    val text=remember(context,locale,configuration){
        val localized=Configuration(configuration).apply{setLocale(locale)}
        UiText(context.createConfigurationContext(localized),locale)
    }
    val preferences=UiPreferences(selected,reduceMotion?:reduced,
        setLanguage={value->if(value in setOf("system","en","rw")){language=value;settings.edit().putString("language",value).apply()}},
        setReduceMotion={value->reduced=value;settings.edit().putBoolean("reduce-screen-motion",value).apply()})
    CompositionLocalProvider(LocalUiText provides text,LocalUiPreferences provides preferences,LocalLayoutDirection provides LayoutDirection.Ltr,content=content)
}

@Composable internal fun UiPreferencePanel(){
    val t=LocalUiText.current
    val preferences=LocalUiPreferences.current
    Column(Modifier.fillMaxWidth().padding(vertical=16.dp)){
        Text(t("Language"),style=MaterialTheme.typography.titleLarge,modifier=Modifier.semantics{heading()})
        Column(Modifier.selectableGroup()){
            for((code,label) in listOf("system" to "Use phone language","en" to "English","rw" to "Ikinyarwanda")){
                Row(Modifier.fillMaxWidth().heightIn(min=48.dp).selectable(
                    selected=preferences.language==code,role=Role.RadioButton,
                    onClick={preferences.setLanguage(code)}).padding(vertical=8.dp),verticalAlignment=Alignment.CenterVertically){
                    RadioButton(selected=preferences.language==code,onClick=null)
                    Spacer(Modifier.width(12.dp));Text(t(label),Modifier.weight(1f))
                }
            }
        }
        Row(Modifier.fillMaxWidth().heightIn(min=56.dp).toggleable(value=preferences.reduceMotion,
            role=Role.Switch,onValueChange=preferences.setReduceMotion),verticalAlignment=Alignment.CenterVertically){
            Text(t("Reduce screen motion"),Modifier.weight(1f));Spacer(Modifier.width(12.dp))
            Switch(preferences.reduceMotion,onCheckedChange=null)
        }
        Text(t("Screen transitions only. Android controls keyboard and dialog animations."),
            style=MaterialTheme.typography.bodySmall,color=BuriTheme.Muted)
    }
}

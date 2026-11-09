package rw.ikanisa.burimunsi

import android.os.Bundle
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.SystemBarStyle
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.compose.runtime.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.activity.viewModels
import app.cool.mobile.BuildConfig
import rw.ikanisa.burimunsi.ui.*

class MainActivity:ComponentActivity(){
    private val model:BuriViewModel by viewModels()
    private val permissions=registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()){model.openSheet(Sheet.GATEWAY)}
    private val export=registerForActivityResult(ActivityResultContracts.CreateDocument("text/csv")){uri->
        if(uri!=null)model.export{csv->contentResolver.openOutputStream(uri,"wt")?.use{it.write(csv.toByteArray(Charsets.UTF_8))}?:error("Unable to save statement")}
    }
    override fun onCreate(savedInstanceState:Bundle?){
        super.onCreate(savedInstanceState)
        // The app uses the selected dark family regardless of the phone's day mode.
        enableEdgeToEdge(
            statusBarStyle=SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle=SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        if(!BuildConfig.DEBUG)window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        setContent {
            val broker=(application as BuriApplication).managedCollectBroker
            val managed by broker.status.collectAsState()
            val scope=rememberCoroutineScope()
            var signingIn by remember{mutableStateOf(false)}
            var visible by remember{mutableStateOf(false)}
            val signOut:()->Unit={
                scope.launch{
                    try{withContext(Dispatchers.IO){broker.signOut()}}
                    catch(_:Exception){/* Broker retains unconfirmed sign-out status. */}
                }
            }
            // Keep the lifecycle hook outside BuriApp: the privacy guard deliberately
            // removes the app's record/form subtree while paused or revalidating.
            LifecycleResumeEffect(model){
                visible=true
                model.onForeground()
                onPauseOrDispose{visible=false;broker.onBackground();model.onBackground()}
            }
            BuriContent {
                if(visible&&broker.configured&&!managed.signedIn){
                    CollectSignIn(signingIn,managed.issue,onSignIn={email,password->
                        // Hold the existing record privacy gate before the IO
                        // broker can publish a different managed identity.
                        if(!signingIn){signingIn=true;model.onBackground();scope.launch{
                            try{withContext(Dispatchers.IO){broker.signIn(email,password)};model.onForeground()}
                            catch(_:Exception){/* Only sanitized broker codes reach the form. */}
                            finally{signingIn=false}
                        }}
                    },onSupport=::support)
                }else if(visible)BuriApp(model,onSupport=::support,
                    onPermissions={permissions.launch(model.gateway.requiredPermissions())},
                    onExport={export.launch("BuriMunsi-transactions.csv")},
                    onCollectSignOut=signOut,
                    onPhoneSettings={startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:$packageName")))})
            }
        }
    }
    private fun support(){
        val phone=BuildConfig.SUPPORT_PHONE.removePrefix("+")
        try{startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://wa.me/$phone")))}
        catch(_:Exception){try{startActivity(Intent(Intent.ACTION_DIAL,Uri.parse("tel:${BuildConfig.SUPPORT_PHONE}")))}catch(_:Exception){android.widget.Toast.makeText(this,BuildConfig.SUPPORT_PHONE,android.widget.Toast.LENGTH_LONG).show()}}
    }
}

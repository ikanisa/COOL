package rw.ikanisa.burimunsi

import android.os.Bundle
import android.content.Intent
import android.net.Uri
import android.net.ConnectivityManager
import android.provider.Settings
import android.Manifest
import android.app.NotificationManager
import android.os.Build
import android.os.PowerManager
import android.content.pm.PackageManager
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.SystemBarStyle
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.lifecycleScope
import androidx.compose.runtime.*
import androidx.activity.viewModels
import kotlinx.coroutines.launch
import app.cool.mobile.BuildConfig
import app.cool.mobile.R
import rw.ikanisa.burimunsi.ui.*
import rw.ikanisa.burimunsi.core.export.ExportFormat
import rw.ikanisa.burimunsi.core.Capability

class MainActivity:ComponentActivity(){
    private var notificationsRequested=false
    private val model:BuriViewModel by viewModels()
    private val permissions=registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()){
        model.permissionsChanged();refreshSystemPolicy()
    }
    private val notifications=registerForActivityResult(ActivityResultContracts.RequestPermission()){
        refreshSystemPolicy();model.permissionsChanged()
    }
    // Keep the v33 CSV slot registered solely to drain an unbound legacy result.
    // It must never read, write, delete, or change the current download binding.
    private val legacyCsvDownload=registerForActivityResult(ActivityResultContracts.CreateDocument(ExportFormat.CSV.mimeType)){ _ -> }
    // Drain any result issued by the older unbound launcher without inspecting its URI.
    private val legacyMemberImport = registerForActivityResult(ActivityResultContracts.OpenDocument()) { _ -> }
    private val memberInputs = AndroidMemberInputs(this) { model }
    private val listingDocuments = AndroidListingDocuments(this) { model }

    override fun onCreate(savedInstanceState:Bundle?){
        super.onCreate(savedInstanceState)
        memberInputs.restore(savedInstanceState)
        listingDocuments.restore(savedInstanceState)
        // The app uses the selected dark family regardless of the phone's day mode.
        enableEdgeToEdge(
            statusBarStyle=SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle=SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        if(!BuildConfig.DEBUG)window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        setContent {
            var visible by remember{mutableStateOf(false)}
            LaunchedEffect(model.state.sheet, model.state.operator?.id, model.state.onboarding.step,
                model.state.onboarding.documentUri, memberInputs.selectedCapture) {
                memberInputs.reconcileSelection()
            }
            // A successful camera capture is queued by the ViewModel until the
            // original operator's foreground session and enrollment access are fresh.
            LaunchedEffect(visible,model.screenGate,model.state.busy,model.state.offline,model.state.pending,
                model.state.onboarding.photoPreviewPending,model.state.onboarding.documentRequestId){
                if(visible&&model.state.onboarding.photoPreviewPending&&!model.state.busy&&!model.state.offline&&!model.state.pending&&model.allows(Capability.ENROLL))
                    model.state.onboarding.documentRequestId?.let(memberInputs::previewCapturedPhoto)
            }
            val download=model.downloadRequest
            LaunchedEffect(download?.id,visible,model.state.busy){
                if(visible&&download!=null&&!model.state.busy)listingDocuments.launchNext()
            }
            // The original phone/passcode route is the application entry point.
            // Repository authentication owns installation and collection bootstrap.
            LifecycleResumeEffect(model){
                visible=true
                refreshSystemPolicy()
                model.onForeground()
                val stopNetworkObservation=SessionNetworkObserver.observe(getSystemService(ConnectivityManager::class.java)){
                    lifecycleScope.launch{model.onNetworkAvailable()}
                }
                onPauseOrDispose{visible=false;model.onBackground();stopNetworkObservation()}
            }
            BuriContent {
                if(visible)BuriApp(model,onSupport=::support,
                    onPermissions={model.requestReceivingPermissions { names -> permissions.launch(names) }},
                    onExport=model::prepareDownload,
                    onPhoneSettings={startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:$packageName")))},
                    onPickMemberFile=memberInputs::pickDocument,
                    onPreviewMemberFile=memberInputs::previewDocument,
                    onNotifications=::notificationAccess,onBatteryOptimization=::batteryOptimization,
                    onTakeMemberPhoto=memberInputs::takePhoto,onPickMemberPhoto=memberInputs::pickPhoto)
                else BuriSplash()
            }
        }
    }
    override fun onSaveInstanceState(outState:Bundle){
        listingDocuments.save(outState)
        memberInputs.save(outState)
        super.onSaveInstanceState(outState)
    }
    override fun onDestroy() {
        if (isFinishing && !isChangingConfigurations) memberInputs.finish()
        super.onDestroy()
    }

    private fun refreshSystemPolicy(){
        val manager=getSystemService(NotificationManager::class.java)
        val channel=manager?.getNotificationChannel(getString(R.string.burimunsi_sync_channel_id))
        val allowed=manager?.areNotificationsEnabled()==true&&channel?.importance!=NotificationManager.IMPORTANCE_NONE&&
            (Build.VERSION.SDK_INT<33||checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED)
        val exempt=getSystemService(PowerManager::class.java)?.isIgnoringBatteryOptimizations(packageName)==true
        model.systemPolicyChanged(allowed,exempt)
    }
    private fun notificationAccess(){
        if(!BuildConfig.IS_GATEWAY||!model.allows(Capability.GATEWAY))return
        if(Build.VERSION.SDK_INT>=33&&checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED&&!notificationsRequested){
            notificationsRequested=true
            notifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }else{
            val manager=getSystemService(NotificationManager::class.java)
            val channel=manager?.getNotificationChannel(getString(R.string.burimunsi_sync_channel_id))
            val intent=if(channel?.importance==NotificationManager.IMPORTANCE_NONE)
                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,packageName).putExtra(Settings.EXTRA_CHANNEL_ID,getString(R.string.burimunsi_sync_channel_id))
                else Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,packageName)
            runCatching{startActivity(intent)}
        }
    }
    private fun batteryOptimization(){
        if(!BuildConfig.IS_GATEWAY||!model.allows(Capability.GATEWAY))return
        val exempt=getSystemService(PowerManager::class.java)?.isIgnoringBatteryOptimizations(packageName)==true
        val target=if(exempt)Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            else Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,Uri.parse("package:$packageName"))
        if(runCatching{startActivity(target)}.isFailure)
            runCatching{startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:$packageName")))}
    }
    private fun support(){
        val contact=model.supportPhone?:return
        val phone=contact.removePrefix("+")
        try{startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://wa.me/$phone")))}
        catch(_:Exception){try{startActivity(Intent(Intent.ACTION_DIAL,Uri.parse("tel:$contact")))}catch(_:Exception){android.widget.Toast.makeText(this,contact,android.widget.Toast.LENGTH_LONG).show()}}
    }
}

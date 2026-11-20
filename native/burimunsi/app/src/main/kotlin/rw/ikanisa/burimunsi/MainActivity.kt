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
import androidx.activity.result.PickVisualMediaRequest
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.lifecycleScope
import androidx.compose.runtime.*
import androidx.activity.viewModels
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.CancellationException
import app.cool.mobile.BuildConfig
import app.cool.mobile.R
import rw.ikanisa.burimunsi.ui.*
import rw.ikanisa.burimunsi.core.export.*
import rw.ikanisa.burimunsi.export.NativePdfExporter
import java.io.File
import android.provider.DocumentsContract
import rw.ikanisa.burimunsi.core.Capability
import rw.ikanisa.burimunsi.core.SmartOnboardingStep

class MainActivity:ComponentActivity(){
    private var notificationsRequested=false
    private var activeDownloadId:Long?=null
    private var activeDownloadFormat:ExportFormat?=null
    private val memberPhotos by lazy{MemberPhotoFiles(cacheDir)}
    private var pendingMemberCapture:String?=null
    private var pendingMemberCaptureOwner:String?=null
    private var pendingMemberPhotoOwner:String?=null
    private var selectedMemberCapture:String?=null
    private var selectedMemberCaptureOwner:String?=null
    private var selectedMemberCaptureBound=false
    private var memberPreviewJob:Job?=null
    private var memberPreviewEpoch=0L
    private val model:BuriViewModel by viewModels()
    private val permissions=registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()){
        model.permissionsChanged();refreshSystemPolicy()
    }
    private val notifications=registerForActivityResult(ActivityResultContracts.RequestPermission()){
        refreshSystemPolicy();model.permissionsChanged()
    }
    // Keep the v33 CSV slot registered solely to drain an unbound legacy result.
    // It must never read, write, delete, or change the current download binding.
    private val legacyCsvDownload=registerForActivityResult(ActivityResultContracts.CreateDocument(ExportFormat.CSV.mimeType)){_ -> Unit}
    private fun saveDownload(uri:Uri?,format:ExportFormat){
        val requestId=activeDownloadId.takeIf{activeDownloadFormat==format}?:return
        activeDownloadId=null;activeDownloadFormat=null
        if(uri==null){model.downloadDestination(requestId,format,null);return}
        val resolver=applicationContext.contentResolver
        model.downloadDestination(requestId,format,write={file,check->
            try{
                check()
                require(uri.scheme=="content"&&file.length() in 1..ExportLimits().maxOutputBytes)
                resolver.openOutputStream(uri,"wt")?.use{output->
                    file.inputStream().use{input->
                        val chunk=ByteArray(8192)
                        try{while(true){check();val size=input.read(chunk);if(size<0)break;require(size>0);output.write(chunk,0,size)};check();output.flush()}
                        finally{chunk.fill(0)}
                    }
                }?:error("Destination unavailable")
                check()
            }catch(error:Exception){
                // Remove this newly created partial document on failure; never touch an existing user document.
                runCatching{DocumentsContract.deleteDocument(resolver,uri)}
                throw error
            }
        },abort={runCatching{DocumentsContract.deleteDocument(resolver,uri)};Unit})
    }
    private val memberImport=registerForActivityResult(ActivityResultContracts.OpenDocument()){uri->
        if(uri!=null)try{model.onboardingFileSelected(uri.toString(),contentResolver.getType(uri)?.lowercase())}
            catch(_:Exception){model.onboardingFileError()}
    }
    // Keep legacy auto-registration positions unchanged across an in-place upgrade.
    // New download formats use stable keys, independent of property declaration order.
    private val csvDownload=activityResultRegistry.register("burimunsi.download.csv.v1",this,
        ActivityResultContracts.CreateDocument(ExportFormat.CSV.mimeType)){saveDownload(it,ExportFormat.CSV)}
    private val excelDownload=activityResultRegistry.register("burimunsi.download.xlsx.v1",this,
        ActivityResultContracts.CreateDocument(ExportFormat.XLSX.mimeType)){saveDownload(it,ExportFormat.XLSX)}
    private val pdfDownload=activityResultRegistry.register("burimunsi.download.pdf.v1",this,
        ActivityResultContracts.CreateDocument(ExportFormat.PDF.mimeType)){saveDownload(it,ExportFormat.PDF)}
    private val memberPhotoCapture=activityResultRegistry.register("burimunsi.member-photo.capture.v1",this,
        MemberPhotoCaptureContract()){success->
        val name=pendingMemberCapture;val owner=pendingMemberCaptureOwner
        pendingMemberCapture=null;pendingMemberCaptureOwner=null
        val file=memberPhotos.restore(name)
        try{
            if(success&&file!=null&&file.length()>0&&memberImportActive(owner)&&model.state.onboarding.photoCaptureFlow){
                clearSelectedMemberCapture()
                selectedMemberCapture=name;selectedMemberCaptureOwner=owner;selectedMemberCaptureBound=false
                model.onboardingPhotoSelected(memberPhotoUri(this,file).toString())
            }else{
                memberPhotos.remove(name)
                if(success&&memberImportActive(owner)&&model.state.onboarding.photoCaptureFlow)model.onboardingFileError()
                else if(!success&&memberImportActive(owner)&&model.state.onboarding.photoCaptureFlow)model.onboardingPhotoCancelled()
            }
        }catch(_:Exception){
            memberPhotos.remove(name)
            if(memberImportActive(owner)&&model.state.onboarding.photoCaptureFlow)model.onboardingFileError()
        }
        finally{file?.let{runCatching{revokeUriPermission(memberPhotoUri(this,it),Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)}}}
    }
    private val memberPhotoPicker=activityResultRegistry.register("burimunsi.member-photo.picker.v1",this,
        ActivityResultContracts.PickVisualMedia()){uri->
        val owner=pendingMemberPhotoOwner;pendingMemberPhotoOwner=null
        if(uri!=null&&memberImportActive(owner))try{
            require(uri.scheme=="content")
            clearSelectedMemberCapture()
            model.onboardingFileSelected(uri.toString(),contentResolver.getType(uri)?.lowercase()?:"image/*")
        }catch(_:Exception){model.onboardingFileError()}
    }
    override fun onCreate(savedInstanceState:Bundle?){
        super.onCreate(savedInstanceState)
        activeDownloadId=savedInstanceState?.takeIf{it.containsKey("burimunsi.download.id")}?.getLong("burimunsi.download.id")
        activeDownloadFormat=savedInstanceState?.getString("burimunsi.download.format")?.let{runCatching{ExportFormat.valueOf(it)}.getOrNull()}
        pendingMemberCapture=memberPhotos.restore(savedInstanceState?.getString("burimunsi.member-photo.pending"))?.name
        pendingMemberCaptureOwner=savedInstanceState?.getString("burimunsi.member-photo.pending-owner")
        pendingMemberPhotoOwner=savedInstanceState?.getString("burimunsi.member-photo.picker-owner")
        selectedMemberCapture=memberPhotos.restore(savedInstanceState?.getString("burimunsi.member-photo.selected"))?.name
        selectedMemberCaptureOwner=savedInstanceState?.getString("burimunsi.member-photo.selected-owner")
        selectedMemberCaptureBound=savedInstanceState?.getBoolean("burimunsi.member-photo.selected-bound")==true
        memberPhotos.removeExcept(setOfNotNull(pendingMemberCapture,selectedMemberCapture))
        if(activeDownloadId!=null&&activeDownloadFormat!=null)model.restoreDownloadPicker(activeDownloadId!!,activeDownloadFormat!!)
        val context=applicationContext
        model.configureDownloads(File(context.cacheDir,"burimunsi-exports")){format,table,file,cancelled->
            file.outputStream().use{output->
                when(format){
                    ExportFormat.CSV->CsvEncoder.write(table,output,cancelled)
                    ExportFormat.XLSX->XlsxEncoder.write(table,output,cancelled)
                    ExportFormat.PDF->NativePdfExporter(context).write(table,output,cancelled)
                }
            }
        }
        // The app uses the selected dark family regardless of the phone's day mode.
        enableEdgeToEdge(
            statusBarStyle=SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle=SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        if(!BuildConfig.DEBUG)window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        setContent {
            var visible by remember{mutableStateOf(false)}
            LaunchedEffect(model.state.sheet,model.state.operator?.id,model.state.onboarding.step,model.state.onboarding.documentUri,selectedMemberCapture){
                val owner=model.state.operator?.id
                if(model.state.sheet!=Sheet.ENROLL||owner==null){memberPreviewJob?.cancel();clearSelectedMemberCapture()}
                else selectedMemberCapture?.let{fileName->
                    val file=memberPhotos.restore(fileName)
                    val uri=file?.let{memberPhotoUri(this@MainActivity,it).toString()}
                    if(uri!=null&&model.state.onboarding.documentUri==uri)selectedMemberCaptureBound=true
                    if(owner!=selectedMemberCaptureOwner||model.state.onboarding.step !in setOf(SmartOnboardingStep.IMPORT,SmartOnboardingStep.IMPORT_MEMBER)||
                        (selectedMemberCaptureBound&&model.state.onboarding.documentUri!=uri))clearSelectedMemberCapture()
                }
            }
            // A successful camera capture is queued by the ViewModel until the
            // original operator's foreground session and enrollment access are fresh.
            LaunchedEffect(visible,model.screenGate,model.state.busy,model.state.offline,model.state.pending,
                model.state.onboarding.photoPreviewPending,model.state.onboarding.documentUri){
                if(visible&&model.state.onboarding.photoPreviewPending&&!model.state.busy&&!model.state.offline&&!model.state.pending&&model.allows(Capability.ENROLL))
                    model.state.onboarding.documentUri?.let{prepareMemberFile(it,automaticPhoto=true)}
            }
            val download=model.downloadRequest
            LaunchedEffect(download?.id,visible,model.state.busy){
                if(visible&&download!=null&&!model.state.busy){
                    model.takeDownloadRequest()?.let{request->
                        activeDownloadId=request.id;activeDownloadFormat=request.format
                        try{when(request.format){
                            ExportFormat.CSV->csvDownload.launch(request.fileName)
                            ExportFormat.XLSX->excelDownload.launch(request.fileName)
                            ExportFormat.PDF->pdfDownload.launch(request.fileName)
                        }}catch(_:Exception){activeDownloadId=null;activeDownloadFormat=null;model.downloadDestination(request.id,request.format,null)}
                    }
                }
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
                    onPermissions={permissions.launch(model.gateway.requiredPermissions())},
                    onExport=model::prepareDownload,
                    onPhoneSettings={startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:$packageName")))},
                    onPickMemberFile={memberImport.launch(arrayOf("text/csv","text/comma-separated-values","application/csv",
                        "image/jpeg","image/png","image/webp","application/pdf","application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))},
                    onPreviewMemberFile=::previewMemberFile,
                    onNotifications=::notificationAccess,onBatteryOptimization=::batteryOptimization,
                    onTakeMemberPhoto=::takeMemberPhoto,onPickMemberPhoto=::pickMemberPhoto)
                else BuriSplash()
            }
        }
    }
    override fun onSaveInstanceState(outState:Bundle){
        activeDownloadId?.let{outState.putLong("burimunsi.download.id",it)}
        activeDownloadFormat?.let{outState.putString("burimunsi.download.format",it.name)}
        pendingMemberCapture?.let{outState.putString("burimunsi.member-photo.pending",it)}
        pendingMemberCaptureOwner?.let{outState.putString("burimunsi.member-photo.pending-owner",it)}
        pendingMemberPhotoOwner?.let{outState.putString("burimunsi.member-photo.picker-owner",it)}
        selectedMemberCapture?.let{outState.putString("burimunsi.member-photo.selected",it)}
        selectedMemberCaptureOwner?.let{outState.putString("burimunsi.member-photo.selected-owner",it)}
        outState.putBoolean("burimunsi.member-photo.selected-bound",selectedMemberCaptureBound)
        super.onSaveInstanceState(outState)
    }
    private fun memberImportActive(owner:String?)=owner!=null&&model.state.operator?.id==owner&&model.state.sheet==Sheet.ENROLL&&
        model.state.onboarding.step==SmartOnboardingStep.IMPORT
    private fun clearSelectedMemberCapture(){
        memberPhotos.remove(selectedMemberCapture);selectedMemberCapture=null;selectedMemberCaptureOwner=null;selectedMemberCaptureBound=false
    }
    private fun takeMemberPhoto(){
        if(!model.allows(Capability.ENROLL)||!memberImportActive(model.state.operator?.id)||!model.state.onboarding.photoCaptureFlow)return
        try{
            memberPhotos.remove(pendingMemberCapture)
            val file=memberPhotos.create();pendingMemberCapture=file.name;pendingMemberCaptureOwner=model.state.operator?.id
            memberPhotoCapture.launch(memberPhotoUri(this,file))
        }catch(_:Exception){
            memberPhotos.remove(pendingMemberCapture);pendingMemberCapture=null;pendingMemberCaptureOwner=null
            model.onboardingFileError(MemberImportFailure.CAMERA_UNAVAILABLE)
        }
    }
    private fun pickMemberPhoto(){
        if(!model.allows(Capability.ENROLL)||!memberImportActive(model.state.operator?.id))return
        try{pendingMemberPhotoOwner=model.state.operator?.id;memberPhotoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))}
        catch(_:Exception){pendingMemberPhotoOwner=null;model.onboardingFileError()}
    }
    override fun onDestroy(){
        if(isFinishing&&!isChangingConfigurations){clearSelectedMemberCapture();memberPhotos.remove(pendingMemberCapture)}
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
        if(!BuildConfig.IS_GATEWAY||!model.allows(rw.ikanisa.burimunsi.core.Capability.GATEWAY))return
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
        if(!BuildConfig.IS_GATEWAY||!model.allows(rw.ikanisa.burimunsi.core.Capability.GATEWAY))return
        val exempt=getSystemService(PowerManager::class.java)?.isIgnoringBatteryOptimizations(packageName)==true
        val target=if(exempt)Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            else Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,Uri.parse("package:$packageName"))
        if(runCatching{startActivity(target)}.isFailure)
            runCatching{startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:$packageName")))}
    }
    /** Read only the explicitly selected document, with a strict bound and no durable copy. */
    private fun previewMemberFile(value:String){prepareMemberFile(value,automaticPhoto=false)}
    private fun prepareMemberFile(value:String,automaticPhoto:Boolean){
        val owner=model.state.operator?.id
        val photo=model.state.onboarding.documentMimeType?.startsWith("image/")==true
        if(!memberImportActive(owner)||model.state.onboarding.documentUri!=value||!model.allows(Capability.ENROLL))return
        selectedMemberCapture?.let{memberPhotos.restore(it)}?.let{if(memberPhotoUri(this,it).toString()==value)selectedMemberCaptureBound=true}
        memberPreviewJob?.cancel()
        val attempt=++memberPreviewEpoch
        memberPreviewJob=lifecycleScope.launch {
            var prepared:ByteArray?=null;var transferred=false
            fun currentSelection()=attempt==memberPreviewEpoch&&memberImportActive(owner)&&model.state.onboarding.documentUri==value
            try {
                val pair=withContext(Dispatchers.IO){
                    val uri=Uri.parse(value);require(uri.scheme=="content")
                    val mime=contentResolver.getType(uri)?.lowercase()?:"application/octet-stream"
                    val image=mime.startsWith("image/")||photo
                    val max=if(image)20*1024*1024 else if(mime in setOf("text/csv","text/comma-separated-values","application/csv"))2*1024*1024 else 5*1024*1024
                    val bytes=contentResolver.openInputStream(uri)?.use{input->
                        readMemberDocument(input,max)
                    }?:error("file unavailable")
                    val result=if(image)"image/jpeg" to prepareMemberPhoto(bytes) else mime to bytes
                    prepared=result.second;result
                }
                if(!currentSelection()||!model.allows(Capability.ENROLL))return@launch
                if(automaticPhoto&&!model.takeOnboardingPhotoPreview(value))return@launch
                model.onboardingPreview(pair.first,pair.second)
                transferred=true
            }catch(_:MemberDocumentTooLarge){if(currentSelection())model.onboardingFileError(if(photo)MemberImportFailure.TOO_LARGE else MemberImportFailure.UNREADABLE)}
            catch(_:OutOfMemoryError){if(currentSelection())model.onboardingFileError(if(photo)MemberImportFailure.TOO_LARGE else MemberImportFailure.UNREADABLE)}
            catch(error:CancellationException){throw error}
            catch(_:Exception){if(currentSelection())model.onboardingFileError()}
            finally{if(!transferred)prepared?.fill(0)}
        }
    }
    private fun support(){
        val contact=model.supportPhone?:return
        val phone=contact.removePrefix("+")
        try{startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://wa.me/$phone")))}
        catch(_:Exception){try{startActivity(Intent(Intent.ACTION_DIAL,Uri.parse("tel:$contact")))}catch(_:Exception){android.widget.Toast.makeText(this,contact,android.widget.Toast.LENGTH_LONG).show()}}
    }
}

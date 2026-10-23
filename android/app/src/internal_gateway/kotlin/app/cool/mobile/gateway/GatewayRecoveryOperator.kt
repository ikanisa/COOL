package app.cool.mobile.gateway

import android.app.Activity
import android.content.Intent
import android.net.Uri
import app.cool.mobile.BuildConfig
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption
import java.security.KeyStore
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.SecretKey

/** Independent of signing/enrollment initialization. Each queued/UI callback
 * captures its own operation, trusted hash, cancellation and result identity. */
internal class GatewayRecoveryOperator(private val activity:GatewayActivity,messenger:BinaryMessenger,private val pauseForPreparation:(() -> String)?=null) {
    private class Operation(val ticket:GatewayRecoveryAdmission.Ticket,val result:MethodChannel.Result) { var picker:Int?=null }
    private val channel=MethodChannel(messenger,"collect/gateway.recovery.v1")
    private val worker=Executors.newSingleThreadExecutor()
    private val admission=GatewayRecoveryAdmission()
    private val closed=AtomicBoolean(false)
    private val store by lazy { GatewayEncryptedStore(activity.applicationContext) }
    private var current:Operation?=null
    private var nextPicker=PICKER
    @Volatile private var status:Map<String,Any?> = reply("none","idle","idle")
    private fun reply(operation:String,state:String,phase:String,count:Long=0,sha:String?=null,files:Long?=null,key:Boolean?=null,reason:String?=null):Map<String,Any?> =
        mapOf("contract_version" to 1,"operation" to operation,"state" to state,"phase" to phase,"completed_files" to count,
            "manifest_sha256" to sha,"files" to files,"key_validated" to key,"inactive" to (operation=="restore"),
            "requires_re_enrollment" to (operation in setOf("restore","prepareReEnrollment")),"reason_code" to reason)
    init { channel.setMethodCallHandler { call,result ->
        if(closed.get() || BuildConfig.FLAVOR!="internal_gateway" || android.os.Build.VERSION.SDK_INT<26) { result.error("gateway_recovery_unavailable","Recovery unavailable",null);return@setMethodCallHandler }
        when(call.method) {
            "status" -> { if(call.arguments!=null)invalid(result) else result.success(status) }
            "cancel" -> {
                if(call.arguments!=null) { invalid(result);return@setMethodCallHandler }
                current?.let { op -> if(admission.cancel(op.ticket))finish(op,"cancelled","gateway_recovery_cancelled") }
                result.success(status)
            }
            "prepareReEnrollment" -> {
                val refs=try { GatewayRealmPreparation.references(call.arguments) } catch(e:GatewayStateException) { result.error(e.reasonCode,"Preparation arguments invalid",null);return@setMethodCallHandler }
                val pause=pauseForPreparation ?: run { result.error("gateway_preparation_unavailable","Preparation unavailable",null);return@setMethodCallHandler }
                val ticket=try { admission.admit("prepareReEnrollment",null) } catch(e:GatewayStateException) { result.error(e.reasonCode,"Recovery already in progress",null);return@setMethodCallHandler }
                val op=Operation(ticket,result);current=op;update(op,"pausing")
                worker.execute { try {
                    requireWork(op);val certificate=pause();requireWork(op);requirePause();update(op,"snapshot")
                    val value=GatewayRealmPreparation(activity.noBackupFilesDir,store).prepare(refs,certificate,{check(op)},::requirePause)
                    requireWork(op);complete(op,value)
                } catch(e:GatewayStateException) { terminal(op,e) } catch(_:Exception) { terminal(op,GatewayStateException("gateway_preparation_unknown")) } }
            }
            "export","restore" -> {
                val args=call.arguments as? Map<*,*>
                if(call.method=="export" && call.arguments!=null || call.method=="restore" && (args?.keys!=setOf("manifest_sha256") || (args["manifest_sha256"] as? String)?.matches(Regex("[0-9a-f]{64}"))!=true)) { invalid(result);return@setMethodCallHandler }
                val ticket=try { admission.admit(call.method,args?.get("manifest_sha256") as? String) } catch(e:GatewayStateException) { result.error(e.reasonCode,"Recovery already in progress",null);return@setMethodCallHandler }
                val op=Operation(ticket,result);current=op;update(op,"preparing")
                worker.execute { try {
                    requireWork(op);if(ticket.operation=="export")requirePause();requireWork(op)
                    activity.runOnUiThread {
                        if(!admission.picker(ticket) || closed.get()) { finish(op,"cancelled","gateway_recovery_cancelled");return@runOnUiThread }
                        update(op,"picker")
                        if(nextPicker>65534) { finish(op,"failed","gateway_recovery_picker_unavailable");return@runOnUiThread }
                        val request=nextPicker++;op.picker=request
                        try { activity.startActivityForResult(if(ticket.operation=="export") Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE);type="application/octet-stream";putExtra(Intent.EXTRA_TITLE,"collect-gateway-${UUID.randomUUID()}.collect-gateway")
                        } else Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE);type="application/octet-stream" },request) }
                        catch(_:Exception) { finish(op,"failed","gateway_recovery_picker_unavailable") }
                    }
                } catch(e:GatewayStateException) { terminal(op,e) } catch(_:Exception) { terminal(op,GatewayStateException("gateway_recovery_unavailable")) } }
            }
            else -> result.notImplemented()
        }
    } }
    fun activityResult(request:Int,result:Int,data:Intent?):Boolean {
        if(request !in PICKER until nextPicker)return false
        val op=current ?: return true
        if(request!=op.picker || closed.get())return true
        val uri=data?.data
        if(result!=Activity.RESULT_OK || uri==null) { admission.cancel(op.ticket);finish(op,"cancelled","gateway_recovery_cancelled");return true }
        // This transition is synchronous, before queueing: cancellation cannot
        // clear pending or admit a new operation while the transfer is queued.
        if(!admission.picked(op.ticket)) { finish(op,"cancelled","gateway_recovery_cancelled");return true }
        op.picker=null;update(op,if(op.ticket.operation=="export")"snapshot" else "reading")
        worker.execute { try { requireWork(op);transfer(op,uri) } catch(e:GatewayStateException) { terminal(op,e) } catch(_:Exception) { terminal(op,GatewayStateException("gateway_recovery_unavailable")) } };return true
    }
    private fun check(op:Operation):Boolean = closed.get() || op.ticket.cancelled.get() || !admission.owns(op.ticket) || Thread.currentThread().isInterrupted
    private fun requireWork(op:Operation) { admission.requireWork(op.ticket);if(closed.get())throw GatewayStateException("gateway_recovery_cancelled") }
    private fun update(op:Operation,phase:String,count:Long=0,sha:String?=op.ticket.trustedManifest,files:Long?=null) {
        if(admission.owns(op.ticket))status=reply(op.ticket.operation,"working",phase,count,sha,files)
    }
    private fun requirePause() { synchronized(GatewayJournal.PROCESS_LOCK) {
        val directory=File(activity.noBackupFilesDir,"collect_gateway_v1")
        if(Files.isSymbolicLink(directory.toPath()) || !Files.isDirectory(directory.toPath(),LinkOption.NOFOLLOW_LINKS))throw GatewayStateException("gateway_recovery_pause_required")
        val keys=KeyStore.getInstance("AndroidKeyStore").also { it.load(null) }
        if(!keys.containsAlias("collect.gateway.storage.v1"))throw GatewayStateException("gateway_storage_key_unavailable")
        val key=keys.getKey("collect.gateway.storage.v1",null) as? SecretKey ?: throw GatewayStateException("gateway_storage_key_unavailable")
        GatewayRecoveryPause.require(directory) { name -> GatewayCrypto(key,"CollectGateway/$name/v1") }
    } }
    private fun transfer(op:Operation,uri:Uri) {
        requireWork(op)
        val run=GatewayRecoveryStorage.workspace(activity.noBackupFilesDir)
        if(op.ticket.operation=="export") {
            requirePause();update(op,"snapshot");var pauseChecked=false
            val archive=store.exportRecovery(File(run,"snapshot")) { if(check(op))true else { if(!pauseChecked) { requirePause();pauseChecked=true };false } }
            requireWork(op);update(op,"writing",sha=archive.manifestSha256,files=archive.files)
            val output=activity.contentResolver.openOutputStream(uri,"w") ?: throw GatewayStateException("gateway_recovery_unavailable")
            val transportSha=GatewayRecoveryTransfer.write(archive,output,{check(op)}) { n -> update(op,"writing",n,archive.manifestSha256,archive.files) }
            requireWork(op);update(op,"verifying",archive.files,archive.manifestSha256,archive.files)
            val readback=activity.contentResolver.openInputStream(uri) ?: throw GatewayStateException("gateway_recovery_output_unknown")
            GatewayRecoveryTransfer.verifyOutput(readback,transportSha) { check(op) }
            requireWork(op);complete(op,reply("export","complete","complete",archive.files,archive.manifestSha256,archive.files))
        } else {
            val sha=op.ticket.trustedManifest ?: throw GatewayStateException("gateway_recovery_invalid");update(op,"reading",sha=sha)
            val input=activity.contentResolver.openInputStream(uri) ?: throw GatewayStateException("gateway_recovery_unavailable")
            val imported=File(run,"import");GatewayRecoveryTransfer.read(input,imported,{check(op)}) { n -> update(op,"reading",n,sha) }
            requireWork(op);update(op,"validating",sha=sha)
            val restored=store.restoreRecovery(imported,sha,File(run,"inactive")) { check(op) }
            requireWork(op);complete(op,reply("restore","complete","complete",restored.files,sha,restored.files,restored.keyValidated))
        }
        // Every snapshot/quarantine/inactive original remains retained.
    }
    private fun invalid(result:MethodChannel.Result) { result.error("gateway_recovery_arguments_invalid","Recovery arguments invalid",null) }
    private fun terminal(op:Operation,error:GatewayStateException) { activity.runOnUiThread { finish(op,if(error.reasonCode=="gateway_recovery_cancelled")"cancelled" else "failed",error.reasonCode) } }
    private fun finish(op:Operation,state:String,reason:String) { complete(op,reply(op.ticket.operation,state,state,sha=op.ticket.trustedManifest,reason=reason)) }
    private fun complete(op:Operation,value:Map<String,Any?>) { activity.runOnUiThread {
        if(!admission.complete(op.ticket))return@runOnUiThread
        status=value;if(current===op)current=null;op.result.success(value)
    } }
    fun close() { closed.set(true);current?.let { admission.cancel(it.ticket) };channel.setMethodCallHandler(null);worker.shutdown() }
    companion object { private const val PICKER=9053 }
}

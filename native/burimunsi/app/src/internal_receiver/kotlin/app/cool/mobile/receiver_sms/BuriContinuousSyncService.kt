package app.cool.mobile.receiver_sms

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Telephony
import app.cool.mobile.BuildConfig
import app.cool.mobile.R
import rw.ikanisa.burimunsi.MainActivity
import rw.ikanisa.burimunsi.data.ApiClient
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth
import rw.ikanisa.burimunsi.gateway.GatewayFactory
import rw.ikanisa.burimunsi.storage.DeviceProvisioning
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import java.io.FileDescriptor
import java.io.PrintWriter
import app.cool.mobile.receiver_sms.ObservationSyncDiagnostics.ServicePhase

/** Process-local control and health; none of these values asserts receipt acceptance or credit. */
internal object BuriContinuousSupervisor {
    const val NOTIFICATION=904_720
    @Volatile private var visible=false
    @Volatile private var service:BuriContinuousSyncService?=null
    @Volatile private var manuallyStopped=false
    @Volatile private var stoppedGeneration:Long?=null
    @Volatile private var lastGeneration:Long?=null
    @Volatile private var restartPending=false
    private val state=ContinuousSyncHealthState()

    private fun validatedHealth(requireScope:Boolean):ContinuousReceiverHealth {
        val current=state.get()
        if(!current.running||current.problem!=null)return current
        val active=service
        if(active==null||!active.authorityWatched()){state.invalidate();return state.get()}
        return try{
            val authority=ObservationAuthorityRevision.stable();val revision=ObservationInboxRevision.snapshot()
            val session=NativeRepository.observationOwner(active)
            val currentDeadline=session?.let{NativeRepository.observationDeadline(active,it)}
            val permitted=listOf(Manifest.permission.READ_SMS,Manifest.permission.RECEIVE_SMS).all{
                active.checkSelfPermission(it)==PackageManager.PERMISSION_GRANTED
            }
            val legacyRoute=if(current.proofLegacyIssuedAtWall!=null)ObservationLegacyOwnership.subscriptionScope(active) else null
            val scope=if(requireScope)ObservationRecovery(active).healthScope() else null
            val stable=authority!=null&&ObservationAuthorityRevision.stable()==authority&&
                ObservationInboxRevision.snapshot()==revision&&NativeRepository.observationOwner(active)==session&&
                session!=null&&currentDeadline!=null&&NativeRepository.observationDeadline(active,session)==currentDeadline&&
                listOf(Manifest.permission.READ_SMS,Manifest.permission.RECEIVE_SMS).all{
                    active.checkSelfPermission(it)==PackageManager.PERMISSION_GRANTED
                }
            val checked=state.health(SystemClock.elapsedRealtime(),ObservationInboxRevision.observerActive(),
                if(stable)revision else null,if(stable)authority else null,session?.let(ObservationAuthorityRevision::sessionDigest),
                permitted&&stable,scope,requireScope,System.currentTimeMillis(),legacyRoute)
            // An owner or inbox callback may arrive while validation is in
            // progress. Do not return the previously checked success afterward.
            if(checked.running&&checked.problem==null&&(!ObservationInboxRevision.observerActive()||
                ObservationInboxRevision.snapshot()!=revision||ObservationAuthorityRevision.stable()!=authority||
                NativeRepository.observationOwner(active)!=session||listOf(Manifest.permission.READ_SMS,Manifest.permission.RECEIVE_SMS).any{
                    active.checkSelfPermission(it)!=PackageManager.PERMISSION_GRANTED
                }||session==null||NativeRepository.observationDeadline(active,session)!=currentDeadline||
                !ContinuousSyncHealthFreshness.sessionFresh(currentDeadline,System.currentTimeMillis())||
                !ContinuousSyncHealthFreshness.observationFresh(checked.proofObservationIssuedAtWall,checked.proofObservationExpiresAtWall,System.currentTimeMillis())||
                !ContinuousSyncHealthFreshness.legacyFresh(checked.proofLegacyIssuedAtWall,checked.proofLegacyExpiresAtWall,System.currentTimeMillis())||
                (checked.proofLegacyIssuedAtWall!=null&&ObservationLegacyOwnership.subscriptionScope(active)!=legacyRoute)))state.invalidate()
            val latest=state.get()
            if(latest!=checked&&latest.running&&latest.problem==null){state.invalidate();state.get()}else latest
        }catch(_:Exception){state.invalidate();state.get()}
    }
    /** UI calls this off-main: verify the full protected authority scope. */
    fun health():ContinuousReceiverHealth=validatedHealth(true)
    /** Main-thread publication checks only bounded local tokens and permission. */
    fun healthFast():ContinuousReceiverHealth=validatedHealth(false)
    fun invalidateProof()=state.invalidate()
    fun channel(context:Context):String=context.getString(R.string.burimunsi_sync_channel_id)
    fun foregroundChanged(context:Context,resumed:Boolean){
        visible=resumed
        if(resumed){
            // Re-evaluate elapsed time even when Android suspended the process.
            service?.refreshDisplayedHealth()
            // A visible task is an Android start opportunity, not an authorization grant.
            manuallyStopped=false
            requestStart(context)
        }
    }
    fun recover(context:Context,bootOrReplacement:Boolean=false){
        if(BuildConfig.IS_QUALIFICATION||!BuildConfig.IS_GATEWAY)return
        runCatching{ObservationBackground.ensure(context.applicationContext)}
        requestStart(context,bootOrReplacement)
    }
    fun start(context:Context){
        val generation=runCatching{NativeRepository.observationOwner(context)?.generation}.getOrNull()
        if(visible&&generation!=null&&generation!=stoppedGeneration)manuallyStopped=false
        requestStart(context)
    }
    fun stop(context:Context){
        manuallyStopped=true
        stoppedGeneration=runCatching{NativeRepository.observationOwner(context)?.generation}.getOrNull()?:lastGeneration
        halt(context,"authorization_required")
    }
    fun halt(context:Context,problem:String){
        val active=service
        active?.requestStop(problem)
        runCatching{context.applicationContext.stopService(Intent(context,BuriContinuousSyncService::class.java))}
        if(active==null)state.set(state.get().copy(running=false,problem=problem,proofStartedAtElapsed=null))
    }
    fun wake(delayMs:Long=0):Boolean {
        val active=service?:return false
        return active.wake(delayMs)
    }
    fun attached(value:BuriContinuousSyncService){service=value;state.set(ContinuousReceiverHealth(true,true,"starting"))}
    fun detached(value:BuriContinuousSyncService,problem:String?){
        if(service===value){
            service=null;state.set(state.get().copy(running=false,problem=problem,proofStartedAtElapsed=null))
            if(restartPending){restartPending=false;Handler(Looper.getMainLooper()).post{requestStart(value.applicationContext)}}
        }
    }
    fun update(value:BuriContinuousSyncService,problem:String?,finishedAt:Long?=null,result:ObservationCycleResult?=null){
        if(service!==value)return
        val old=state.get();state.set(old.copy(running=true,problem=problem,lastCycleAt=finishedAt?:old.lastCycleAt,
            proofStartedAtElapsed=if(problem==null)result?.proofStartedAtElapsed else null,
            proofInboxRevision=if(problem==null)result?.proofInboxRevision else null,
            proofAuthorityRevision=if(problem==null)result?.proofAuthorityRevision else null,
            proofSessionDigest=if(problem==null)result?.proofSessionDigest else null,
            proofScope=if(problem==null)result?.proofScope else null,
            proofSessionExpiresAtWall=if(problem==null)result?.proofSessionExpiresAtWall else null,
            proofObservationIssuedAtWall=if(problem==null)result?.proofObservationIssuedAtWall else null,
            proofObservationExpiresAtWall=if(problem==null)result?.proofObservationExpiresAtWall else null,
            proofLegacyIssuedAtWall=if(problem==null)result?.proofLegacyIssuedAtWall else null,
            proofLegacyExpiresAtWall=if(problem==null)result?.proofLegacyExpiresAtWall else null,
            proofLegacySubscriptionsDigest=if(problem==null)result?.proofLegacySubscriptionsDigest else null))
        lastGeneration=runCatching{NativeRepository.observationOwner(value)?.generation}.getOrNull()?:lastGeneration
    }
    /** A rejected creation has no attached identity. CAS cannot overwrite a
     * newer service's independently published health. */
    fun creationRejected(problem:String){publishWhileUnattached(problem)}
    private fun publishWhileUnattached(problem:String){
        if(service!=null)return
        val before=state.get()
        if(service==null)state.compareAndSet(before,before.copy(running=false,problem=problem,proofStartedAtElapsed=null))
    }
    fun problem(context:Context):String? {return try{
        if(BuildConfig.IS_QUALIFICATION||!BuildConfig.IS_GATEWAY||manuallyStopped)"authorization_required"
        else if(listOf(Manifest.permission.READ_SMS,Manifest.permission.RECEIVE_SMS).any{
                context.checkSelfPermission(it)!=PackageManager.PERMISSION_GRANTED})"permission_required"
        else {
            // This expired-deadline-compatible scope is ONLY for controls/startup.
            // Capture itself continues to require observationOwner's validated witness.
            val owner=NativeRepository.restorableObservationOwner(context)?:return "authorization_required"
            val legacy=MomoGatewayStore(context).read()
            when {
                legacy?.opt("receiver_retired")==true||legacy?.opt("retirement_pending")==true->"receiver_retired"
                legacy?.has("control_transition")==true->"paused"
                legacy?.has("binding")==true&&legacy.optJSONObject("binding")?.opt("collection_id")!=owner.collectionId->"authorization_required"
                legacy?.has("binding")==true&&legacy.opt("capture_enabled")!=true->"paused"
                ObservationConfigStore(context).paused(owner)->"paused"
                !notificationsAllowed(context)->"notification_permission_required"
                else->null
            }
        }
    }catch(_:Exception){"authorization_required"}}

    fun ensureChannel(context:Context){
        val manager=context.getSystemService(NotificationManager::class.java)?:return
        manager.createNotificationChannel(NotificationChannel(channel(context),context.getString(R.string.burimunsi_sync_channel_name),NotificationManager.IMPORTANCE_LOW).apply{
            description=context.getString(R.string.burimunsi_sync_channel_description)
            setShowBadge(false)
        })
    }
    private fun notificationsAllowed(context:Context):Boolean {
        if(Build.VERSION.SDK_INT>=33&&context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)return false
        val manager=context.getSystemService(NotificationManager::class.java)?:return false
        return manager.areNotificationsEnabled()&&manager.getNotificationChannel(channel(context))?.importance!=NotificationManager.IMPORTANCE_NONE
    }
    private fun requestStart(context:Context,bootOrReplacement:Boolean=false){
        val app=context.applicationContext
        if(BuildConfig.IS_QUALIFICATION||!BuildConfig.IS_GATEWAY)return
        try{ensureChannel(app)}catch(_:Exception){state.set(state.get().copy(running=false,problem="notification_permission_required",proofStartedAtElapsed=null));return}
        val reason=problem(app)
        if(reason!=null){
            if(reason=="authorization_required"&&!manuallyStopped&&service?.hasActiveCycle()==true){wake();return}
            halt(app,reason);return
        }
        if(wake())return
        if(service!=null){restartPending=true;return}
        val exempt=runCatching{app.getSystemService(PowerManager::class.java)?.isIgnoringBatteryOptimizations(app.packageName)==true}.getOrDefault(false)
        if(!visible&&!bootOrReplacement&&!exempt){state.set(state.get().copy(running=false,problem="start_not_allowed",proofStartedAtElapsed=null));return}
        // Publish intent before dispatch; a fast onCreate failure/success must
        // never be overwritten by the caller returning from the binder call.
        publishWhileUnattached("starting")
        try{
            app.startForegroundService(Intent(app,BuriContinuousSyncService::class.java))
        }catch(_:RuntimeException){
            // The OS owns the final start decision, including boot/type restrictions.
            // Existing persisted jobs remain a fallback; never bypass user restrictions.
            creationRejected("start_not_allowed")
        }
    }
    fun online(context:Context):Boolean = try{
        val manager=context.getSystemService(ConnectivityManager::class.java)
        val active=manager?.activeNetwork
        val caps=if(active!=null)manager.getNetworkCapabilities(active)else null
        caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)==true&&caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }catch(_:Exception){false}
}

/** Visible special-use supervisor for the internal receiving phone. Local monitoring
 * is continuous; each existing observation-pipeline cycle and wake lock is finite.
 * JobScheduler is fallback, not the executor of this foreground loop.
 */
class BuriContinuousSyncService:Service(){
    private val main=Handler(Looper.getMainLooper())
    private val worker=Executors.newSingleThreadExecutor{task->Thread(task,"burimunsi-continuous-sync")}
    private val stopped=AtomicBoolean(false)
    private val inCycle=AtomicBoolean(false)
    private val wakeLock=AtomicReference<PowerManager.WakeLock?>()
    private val retry=ContinuousSyncRetry()
    private var nextAt=Long.MAX_VALUE
    private var wakeAgain=false
    private var terminalProblem:String?=null
    @Volatile private var detachSession:(()->Unit)?=null
    @Volatile private var detachAuthority:(()->Unit)?=null
    private var networkCallback:ConnectivityManager.NetworkCallback?=null
    private var observer:ContentObserver?=null
    private var observerLease:Any?=null
    private val tick=Runnable{runCycle()}
    private val proofExpiry=Runnable{publishCurrentHealth();wake(0)}
    private var notificationsReady=false

    override fun onCreate(){
        super.onCreate()
        ObservationSyncDiagnostics.service(ServicePhase.STARTING,"starting")
        if(BuildConfig.IS_QUALIFICATION||!BuildConfig.IS_GATEWAY){terminalProblem="authorization_required";stopped.set(true);stopSelf();return}
        try{
            BuriContinuousSupervisor.ensureChannel(this)
            val note=notification(R.string.burimunsi_sync_notification_starting)
            if(Build.VERSION.SDK_INT>=34)startForeground(BuriContinuousSupervisor.NOTIFICATION,note,ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            else startForeground(BuriContinuousSupervisor.NOTIFICATION,note)
            notificationsReady=true
        }catch(_:RuntimeException){
            terminalProblem="start_not_allowed";stopped.set(true)
            BuriContinuousSupervisor.creationRejected("start_not_allowed")
            stopSelf();return
        }
        BuriContinuousSupervisor.attached(this)
        try{
            detachAuthority=ObservationAuthorityRevision.observe{shouldWake->
                // This callback can run while native session or receiver locks
                // are held. Only atomic invalidation and posting are allowed.
                BuriContinuousSupervisor.invalidateProof()
                main.post{if(!stopped.get()){publishCurrentHealth();if(shouldWake)wake(0)}}
            }
            val install=DeviceProvisioning(this,GatewayFactory.installationId(this))
            val api=ApiClient.phonePin(BuildConfig.BURI_API_ORIGIN,install.installationId,"internal_receiver",BuildConfig.BURI_API_PATH_PREFIX,BuildConfig.COLLECT_PUBLISHABLE_KEY){install.registrationToken()}
            // Attachment can precede an online renewal. Only wake here; do not
            // misclassify its temporarily unconfirmed generation as a logout.
            detachSession=NativeRepository(this,api).observeProcessSession{ObservationAuthorityRevision.ownerChanged()}
            observer=object:ContentObserver(main){override fun onChange(selfChange:Boolean){
                ObservationInboxRevision.changed();BuriContinuousSupervisor.invalidateProof();publishCurrentHealth();wake(400)
            }}.also{
                contentResolver.registerContentObserver(Telephony.Sms.CONTENT_URI,true,it)
            }
            observerLease=ObservationInboxRevision.observerRegistered()
            val manager=getSystemService(ConnectivityManager::class.java)
            networkCallback=object:ConnectivityManager.NetworkCallback(){
                override fun onAvailable(network:Network){main.post{wake(0)}}
                override fun onCapabilitiesChanged(network:Network,capabilities:NetworkCapabilities){main.post{wake(0)}}
                override fun onLost(network:Network){main.post{wake(0)}}
            }.also{manager?.registerDefaultNetworkCallback(it)}
        }catch(_:Exception){/* Finite periodic checks remain; permission loss is checked before work. */}
        wake(0)
    }
    override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int {
        if(stopped.get())return START_NOT_STICKY
        // No intent can supply authority, a group, a bearer or an upload body.
        wake(0)
        return START_STICKY
    }
    override fun onBind(intent:Intent?):IBinder?=null
    override fun onTaskRemoved(rootIntent:Intent?){wake(0);super.onTaskRemoved(rootIntent)}
    /** Android's on-demand service dump reads only bounded volatile state. */
    override fun dump(fd:FileDescriptor,writer:PrintWriter,args:Array<out String>?){
        writer.println("service_stopped=${stopped.get()} cycle_active=${inCycle.get()}")
        ObservationSyncDiagnostics.dump(writer)
    }

    internal fun wake(delayMs:Long):Boolean {
        if(stopped.get())return false
        if(Looper.myLooper()!=Looper.getMainLooper()){main.post{wake(delayMs)};return true}
        if(inCycle.get()){wakeAgain=true;return true}
        val at=android.os.SystemClock.uptimeMillis()+delayMs.coerceIn(0,60_000)
        if(at<nextAt){main.removeCallbacks(tick);nextAt=at;main.postAtTime(tick,at);ObservationSyncDiagnostics.service(ServicePhase.SCHEDULED)}
        return true
    }
    internal fun requestStop(problem:String){
        terminalProblem=problem;stopped.set(true)
        observerLease?.let{ObservationInboxRevision.observerDetached(it)};observerLease=null
        ObservationSyncDiagnostics.service(ServicePhase.STOPPED,problem)
        main.removeCallbacks(tick);main.removeCallbacks(proofExpiry);nextAt=Long.MAX_VALUE
        releaseWake()
        stopSelf()
    }
    internal fun hasActiveCycle():Boolean=inCycle.get()
    internal fun authorityWatched():Boolean=detachSession!=null&&detachAuthority!=null
    private fun notification(text:Int):Notification {
        val pending=PendingIntent.getActivity(this,0,Intent(this,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder=Notification.Builder(this,BuriContinuousSupervisor.channel(this))
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle(getString(R.string.burimunsi_sync_notification_title)).setContentText(getString(text))
            .setContentIntent(pending).setOngoing(true).setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE).setVisibility(Notification.VISIBILITY_PRIVATE)
        if(Build.VERSION.SDK_INT>=31)builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        return builder.build()
    }
    private fun releaseWake(){wakeLock.getAndSet(null)?.let{lock->runCatching{if(lock.isHeld)lock.release()}}}
    private fun notificationText(problem:String?):Int=when(ObservationSyncDiagnostics.notificationState(problem)){
        ObservationSyncDiagnostics.NotificationState.STARTING->R.string.burimunsi_sync_notification_starting
        ObservationSyncDiagnostics.NotificationState.ACTIVE->R.string.burimunsi_sync_notification_active
        ObservationSyncDiagnostics.NotificationState.WAITING->R.string.burimunsi_sync_notification_waiting
        ObservationSyncDiagnostics.NotificationState.UNCONFIRMED->R.string.ui_120e1aa27fc2
    }
    /** A foreground refresh also catches time spent in Android deep sleep. */
    internal fun refreshDisplayedHealth(){main.post{if(!stopped.get())publishCurrentHealth()}}
    private fun publishCurrentHealth(){
        val health=BuriContinuousSupervisor.healthFast()
        if(notificationsReady)runCatching{getSystemService(NotificationManager::class.java)?.notify(BuriContinuousSupervisor.NOTIFICATION,
            notification(notificationText(health.problem)))}
        main.removeCallbacks(proofExpiry)
        val started=health.proofStartedAtElapsed?:return
        val now=SystemClock.elapsedRealtime()
        var delay=if(ContinuousSyncHealthFreshness.fresh(started,now))
            ContinuousSyncHealthFreshness.MAX_PROOF_AGE_MS-(now-started) else 1L
        listOfNotNull(health.proofSessionExpiresAtWall,health.proofObservationExpiresAtWall,health.proofLegacyExpiresAtWall)
            .forEach{delay=minOf(delay,(it-System.currentTimeMillis()).coerceAtLeast(1L))}
        main.postDelayed(proofExpiry,delay)
    }
    private fun runCycle(){
        nextAt=Long.MAX_VALUE
        if(stopped.get()||!inCycle.compareAndSet(false,true))return
        wakeAgain=false
        try{worker.execute{
            var result=ObservationCycleResult(false,true,"sync_unconfirmed")
            var terminal:String?=null
            var ownsGate=false
            try{
                ObservationSyncDiagnostics.service(ServicePhase.PREFLIGHT)
                terminal=BuriContinuousSupervisor.problem(applicationContext)
                if(terminal==null){
                    ownsGate=ObservationBackground.begin()
                    if(!ownsGate){
                        ObservationSyncDiagnostics.busy()
                        ObservationSyncDiagnostics.service(ServicePhase.BACKGROUND_GATE_BUSY,"starting")
                        result=ObservationCycleResult(false,true,busy=true)
                    }
                    else {
                        val lock=getSystemService(PowerManager::class.java)?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,packageName+":sms-sync")
                        lock?.setReferenceCounted(false);lock?.acquire(120_000L);wakeLock.set(lock)
                        ObservationSyncDiagnostics.service(ServicePhase.PIPELINE)
                        result=ObservationSyncCycle.run(applicationContext,BuriContinuousSupervisor.online(applicationContext)){
                            stopped.get()||listOf(Manifest.permission.READ_SMS,Manifest.permission.RECEIVE_SMS).any{checkSelfPermission(it)!=PackageManager.PERMISSION_GRANTED}
                        }
                        // Actual scope loss is evaluated after restore's proof,
                        // never from its transient attach notification.
                        terminal=BuriContinuousSupervisor.problem(applicationContext)
                    }
                }
            }catch(error:Exception){
                ObservationSyncDiagnostics.serviceError(ServicePhase.EXECUTION_FAILED,ObservationSyncDiagnostics.errorKind(error))
                result=ObservationCycleResult(false,true,"sync_unconfirmed")
            }
            finally{
                releaseWake()
                if(ownsGate)runCatching{ObservationBackground.finish(applicationContext,false){}}
                main.post{
                    inCycle.set(false)
                    if(stopped.get())return@post
                    if(terminal!=null){requestStop(terminal!!);return@post}
                    val problem=if(result.busy)"starting"else result.problem
                    ObservationSyncDiagnostics.service(ServicePhase.RETRY,problem)
                    BuriContinuousSupervisor.update(this,problem,if(!result.busy)System.currentTimeMillis()else null,
                        if(result.completed)result else null)
                    publishCurrentHealth()
                    val delay=if(wakeAgain)0L else if(result.busy)2_000L else retry.next(result.completed,result.more,result.progress)
                    wake(delay)
                }
            }
        }}catch(error:RuntimeException){
            ObservationSyncDiagnostics.serviceError(ServicePhase.DISPATCH_REJECTED,ObservationSyncDiagnostics.errorKind(error))
            inCycle.set(false);requestStop("sync_unconfirmed")
        }
    }
    override fun onDestroy(){
        stopped.set(true);main.removeCallbacksAndMessages(null);releaseWake()
        ObservationSyncDiagnostics.service(ServicePhase.DESTROYED,terminalProblem)
        runCatching{detachSession?.invoke()};detachSession=null
        runCatching{detachAuthority?.invoke()};detachAuthority=null
        observerLease?.let{ObservationInboxRevision.observerDetached(it)};observerLease=null
        observer?.let{runCatching{contentResolver.unregisterContentObserver(it)}};observer=null
        networkCallback?.let{callback->runCatching{getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(callback)}};networkCallback=null
        worker.shutdown()
        BuriContinuousSupervisor.detached(this,terminalProblem)
        if(notificationsReady)stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}

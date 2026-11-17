package app.cool.mobile.receiver_sms

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.Manifest
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import app.cool.mobile.BuildConfig
import rw.ikanisa.burimunsi.core.ObservationJournal
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.data.NativeRepository
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Observation scheduling remains independent from the retained gateway queue. */
internal object ObservationBackground {
    private const val IMMEDIATE=904_711
    private const val RECOVERY=904_712
    private const val LOCAL=904_713
    private val wakeup=ObservationWakeup()
    fun begin()=wakeup.begin()
    fun signal(context:Context,delay:Long=0){
        if(!BuriContinuousSupervisor.wake(delay))wakeup.signalNetwork{dispatchNetwork(context,delay)}
    }
    fun signalLocal(context:Context,delay:Long=2_000){
        if(!BuriContinuousSupervisor.wake(delay))wakeup.signalLocal{dispatchLocal(context,delay)}
    }
    private fun dispatchNetwork(context:Context,delay:Long){if(!BuriContinuousSupervisor.wake(delay))schedule(context,delay)}
    private fun dispatchLocal(context:Context,delay:Long){if(!BuriContinuousSupervisor.wake(delay))scheduleLocal(context,delay)}
    fun contend(context:Context,jobId:Int){
        when(jobId){
            IMMEDIATE->signal(context)
            RECOVERY->{try{signalLocal(context)}finally{signal(context)}}
            else->signalLocal(context)
        }
    }
    private fun scheduleLocal(context:Context,delay:Long){
        if(BuildConfig.IS_QUALIFICATION||!BuildConfig.IS_GATEWAY)return
        val scheduler=context.getSystemService(JobScheduler::class.java)?:return
        val job=JobInfo.Builder(LOCAL,ComponentName(context,ObservationJobService::class.java))
            .setMinimumLatency(delay).setBackoffCriteria(30_000,JobInfo.BACKOFF_POLICY_EXPONENTIAL).build()
        check(scheduler.schedule(job)==JobScheduler.RESULT_SUCCESS){"Observation recovery unavailable"}
    }
    private fun schedule(context:Context,delay:Long){
        if(BuildConfig.IS_QUALIFICATION||!BuildConfig.IS_GATEWAY)return
        val scheduler=context.getSystemService(JobScheduler::class.java)?:return
        val job=JobInfo.Builder(IMMEDIATE,ComponentName(context,ObservationJobService::class.java))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setMinimumLatency(delay)
            .setBackoffCriteria(30_000,JobInfo.BACKOFF_POLICY_EXPONENTIAL).build()
        check(scheduler.schedule(job)==JobScheduler.RESULT_SUCCESS){"Observation scheduling unavailable"}
    }
    fun ensure(context:Context){
        if(BuildConfig.IS_QUALIFICATION||!BuildConfig.IS_GATEWAY)return
        val scheduler=context.getSystemService(JobScheduler::class.java)?:return
        if(scheduler.getPendingJob(RECOVERY)==null){
            val job=JobInfo.Builder(RECOVERY,ComponentName(context,ObservationJobService::class.java))
                .setPersisted(true).setPeriodic(15*60*1000L).build()
            check(scheduler.schedule(job)==JobScheduler.RESULT_SUCCESS){"Observation recovery unavailable"}
        }
        signal(context)
    }
    fun finish(context:Context,again:Boolean,finish:()->Unit)=wakeup.finish(again,finish,
        {dispatchLocal(context,15_000)},{signalled->dispatchNetwork(context,if(signalled)0 else 60_000)})
    fun hasPending(context:Context):Boolean=try{
        NativeRepository.withObservationOwner(context){group,account->
            val owner=ObservationOwner(group,account);val config=ObservationConfigStore(context)
            val permission=context.checkSelfPermission(Manifest.permission.READ_SMS)==PackageManager.PERMISSION_GRANTED&&
                context.checkSelfPermission(Manifest.permission.RECEIVE_SMS)==PackageManager.PERMISSION_GRANTED
            !config.paused(owner)&&config.consent(owner)?.canCapture(permission)==true&&config.profile(owner,System.currentTimeMillis())!=null&&
                ObservationJournal(ObservationStateStore(context)).pending(owner).isNotEmpty()
        }==true
    }catch(_:Exception){false}
}

class ObservationJobService:JobService(){
    private val worker=Executors.newSingleThreadExecutor()
    private val main=Handler(Looper.getMainLooper())
    private var current:Pair<JobParameters,AtomicBoolean>?=null
    override fun onStartJob(params:JobParameters):Boolean {
        if(BuildConfig.IS_QUALIFICATION||!BuildConfig.IS_GATEWAY)return false
        if(!ObservationBackground.begin()){
            try{ObservationBackground.contend(applicationContext,params.jobId)}catch(_:Exception){}
            return false
        }
        val stopped=AtomicBoolean(false);current=params to stopped
        try{worker.execute{
            var again=false
            try{
                val result=ObservationSyncCycle.run(applicationContext,BuriContinuousSupervisor.online(applicationContext)){stopped.get()}
                again=result.more||result.busy
            }catch(_:Exception){/* Protected state remains for retry after network/authority recovery. */}
            finally{
                if(!stopped.get())again=ObservationBackground.hasPending(applicationContext)||again
                val retry=again
                main.post{if(current?.second===stopped){current=null
                    try{ObservationBackground.finish(applicationContext,retry){jobFinished(params,false)}}catch(_:Exception){}}
                    // Revalidated expired saved sessions may now be eligible to
                    // recover the supervisor under an existing OS exemption.
                    if(!stopped.get())runCatching{BuriContinuousSupervisor.start(applicationContext)}
                }
            }
        }}catch(_:RuntimeException){current=null;ObservationBackground.finish(applicationContext,false){};return false}
        return true
    }
    override fun onStopJob(params:JobParameters):Boolean {
        val work=current?:return false
        if(work.first.jobId!=params.jobId)return false
        work.second.set(true);current=null
        try{ObservationBackground.finish(applicationContext,false){}}catch(_:Exception){}
        return true
    }
    override fun onDestroy(){
        val unfinished=current;unfinished?.second?.set(true);current=null
        if(unfinished!=null)try{ObservationBackground.finish(applicationContext,false){}}catch(_:Exception){}
        worker.shutdown();super.onDestroy()
    }
}

class ObservationBootReceiver:BroadcastReceiver(){
    override fun onReceive(context:Context,intent:Intent){
        if(intent.action in setOf(Intent.ACTION_BOOT_COMPLETED,Intent.ACTION_USER_UNLOCKED,Intent.ACTION_MY_PACKAGE_REPLACED)){
            try{ObservationBackground.ensure(context.applicationContext)}catch(_:Exception){}
            runCatching{BuriContinuousSupervisor.recover(context.applicationContext,
                intent.action in setOf(Intent.ACTION_BOOT_COMPLETED,Intent.ACTION_MY_PACKAGE_REPLACED))}
        }
    }
}

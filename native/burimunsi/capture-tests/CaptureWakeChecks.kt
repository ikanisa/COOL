package app.cool.mobile.receiver_sms

import android.content.Context
import android.content.Intent
import android.provider.Telephony

fun main(){
    val context=Context();val receiver=CollectSmsReceiver()
    val sms=Intent(Telephony.Sms.Intents.SMS_RECEIVED_ACTION,mapOf("subscription" to 7,"format" to "3gpp"))
    var checks=0
    fun ck(name:String,condition:Boolean){check(condition){name};println("PASS $name");checks++}
    CaptureFixture.reset();receiver.onReceive(context,sms)
    ck("new retained broadcast requests one wake after queue append",CaptureFixture.queue.size==1&&CaptureFixture.signalCalls==1&&CaptureFixture.pendingJobs.size==1&&CaptureFixture.finished==1)
    CaptureFixture.result=SmsQueueStore.AppendResult.DUPLICATE;receiver.onReceive(context,sms)
    ck("duplicate broadcast does not schedule another wake",CaptureFixture.queue.size==1&&CaptureFixture.signalCalls==1&&CaptureFixture.finished==2)
    CaptureFixture.result=SmsQueueStore.AppendResult.FULL;receiver.onReceive(context,sms)
    ck("full queue does not falsely schedule a new capture",CaptureFixture.queue.size==1&&CaptureFixture.signalCalls==1)
    CaptureFixture.reset();CaptureFixture.retain=false;receiver.onReceive(context,sms)
    ck("unapproved source is neither retained nor scheduled",CaptureFixture.queue.isEmpty()&&CaptureFixture.signalCalls==0)
    CaptureFixture.reset();CaptureFixture.scheduleFailure=true;receiver.onReceive(context,sms)
    ck("scheduler failure preserves the already retained capture",CaptureFixture.queue.size==1&&CaptureFixture.signalCalls==1&&CaptureFixture.finished==1)
    CaptureFixture.reset();CaptureFixture.metadataFailure=true;receiver.onReceive(context,sms)
    ck("metadata failure does not suppress wake for retained capture",CaptureFixture.queue.size==1&&CaptureFixture.signalCalls==1)
    CaptureFixture.reset();check(CaptureFixture.gate.begin());receiver.onReceive(context,sms)
    ck("active worker coalesces the concurrent wake",CaptureFixture.queue.size==1&&CaptureFixture.scheduleCalls==0)
    CaptureFixture.gate.finish({}, {if(CaptureFixture.queue.isNotEmpty())MomoGatewayJobs.signal(context)})
    ck("worker completion rechecks and schedules retained work",CaptureFixture.scheduleCalls==1&&CaptureFixture.pendingJobs.size==1)
    CaptureFixture.reset();receiver.onReceive(context,sms);receiver.onReceive(context,sms)
    ck("repeated schedules retain the same one-shot job identity",CaptureFixture.signalCalls==2&&CaptureFixture.pendingJobs.size==1)
    val observation=ObservationWakeup();var network=0;var local=0;var urgent=false
    check(observation.begin())
    observation.signalNetwork{network++};observation.signalLocal{local++}
    ck("observation signals are held while a worker is active",network==0&&local==0)
    observation.finish(true,{}, {local++}, {requested->urgent=requested;network++})
    ck("pause/reconcile signal schedules immediately after the active worker",network==1&&local==1&&urgent)
    var fail=true
    runCatching{observation.signalNetwork{if(fail)error("synthetic scheduler failure")}}
    fail=false;check(observation.begin());observation.finish(false,{}, {}, {network++})
    ck("failed network scheduling retains a retry signal",network==2)
    println("RESULT: $checks generated receiver wake checks passed with Android, queue and scheduler doubles; not device or network proof.")
}

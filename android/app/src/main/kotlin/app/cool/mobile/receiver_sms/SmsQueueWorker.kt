package app.cool.mobile.receiver_sms

import java.util.concurrent.Executors

/** Serializes encrypted queue I/O away from Android and Flutter UI threads. */
object SmsQueueWorker {
    private val executor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "collect-secure-sms-queue").apply { isDaemon = true }
    }

    fun execute(task: () -> Unit) {
        executor.execute(task)
    }
}

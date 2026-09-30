package app.cool.mobile.receiver_sms

import java.util.concurrent.Executors

/** Keeps SMS capture independent of Flutter work while store locking serializes queue I/O. */
object SmsQueueWorker {
    private val executor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "collect-secure-sms-queue").apply { isDaemon = true }
    }
    private val captureExecutor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "collect-secure-sms-capture").apply { isDaemon = true }
    }

    fun execute(task: () -> Unit) {
        executor.execute(task)
    }

    /** A broadcast's goAsync deadline must not wait behind Flutter snapshot or queue calls. */
    fun executeCapture(task: () -> Unit) {
        captureExecutor.execute(task)
    }
}

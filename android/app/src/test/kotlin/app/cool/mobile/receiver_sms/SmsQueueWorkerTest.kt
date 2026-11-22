package app.cool.mobile.receiver_sms

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertTrue
import org.junit.Test

class SmsQueueWorkerTest {
    @Test
    fun captureCanStartWhileFlutterTaskIsBusy() {
        val flutterTaskStarted = CountDownLatch(1)
        val releaseFlutterTask = CountDownLatch(1)
        val captureCompleted = CountDownLatch(1)

        SmsQueueWorker.execute {
            flutterTaskStarted.countDown()
            releaseFlutterTask.await(5, TimeUnit.SECONDS)
        }
        try {
            assertTrue(flutterTaskStarted.await(2, TimeUnit.SECONDS))
            SmsQueueWorker.executeCapture { captureCompleted.countDown() }
            assertTrue(captureCompleted.await(2, TimeUnit.SECONDS))
        } finally {
            releaseFlutterTask.countDown()
        }
    }
}

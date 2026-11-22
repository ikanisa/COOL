package app.cool.mobile.receiver_sms

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test

class MomoGatewayLocalRecoveryTest {
    @Test fun emptyAndStoppedScansDoNotScheduleContinuation() {
        var calls = 0
        assertFalse(runLocalRecoveryPages({ false }) { calls++; false })
        assertEquals(1, calls)
        assertFalse(runLocalRecoveryPages({ true }) { fail("stopped scan ran"); true })
        assertFalse(runLocalRecoveryPages({ calls >= 2 }) { calls++; true })
        assertEquals(2, calls)
    }

    @Test fun batchesAreBoundedAndErrorsAreNotTreatedAsProgress() {
        var calls = 0
        assertTrue(runLocalRecoveryPages({ false }) { calls++; true })
        assertEquals(5, calls)
        try {
            runLocalRecoveryPages({ false }) { throw IllegalStateException("not retained") }
            fail("failure must reach the scheduler")
        } catch (_: IllegalStateException) { }
    }

    @Test fun onlineAndOfflineScansUseOneSharedOwner() {
        val firstEntered = CountDownLatch(1)
        val releaseFirst = CountDownLatch(1)
        val secondAttempt = CountDownLatch(1)
        val secondEntered = CountDownLatch(1)
        val concurrent = AtomicInteger(0)
        val max = AtomicInteger(0)
        val first = Thread {
            MomoGatewayInboxScanLock.run {
                max.updateAndGet { maxOf(it, concurrent.incrementAndGet()) }
                firstEntered.countDown()
                assertTrue(releaseFirst.await(3, TimeUnit.SECONDS))
                concurrent.decrementAndGet()
            }
        }
        val second = Thread {
            secondAttempt.countDown()
            MomoGatewayInboxScanLock.run {
                max.updateAndGet { maxOf(it, concurrent.incrementAndGet()) }
                secondEntered.countDown()
                concurrent.decrementAndGet()
            }
        }
        first.start()
        assertTrue(firstEntered.await(2, TimeUnit.SECONDS))
        second.start()
        assertTrue(secondAttempt.await(2, TimeUnit.SECONDS))
        assertFalse(secondEntered.await(100, TimeUnit.MILLISECONDS))
        releaseFirst.countDown()
        first.join(3000); second.join(3000)
        assertFalse(first.isAlive); assertFalse(second.isAlive)
        assertEquals(1, max.get())
        assertEquals(0L, secondEntered.count)
    }
}

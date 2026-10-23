package app.cool.mobile.receiver_sms

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test

class MomoGatewayWakeupGateTest {
    @Test fun messageWhileWorkerRunsIsRescheduledFromDurableQueueAtCompletion() {
        val gate = MomoGatewayWakeupGate()
        var pending = 0
        var scheduled = 0
        assertTrue(gate.begin())
        pending++
        gate.signal { scheduled++ }
        assertEquals(0, scheduled)
        gate.finish({}, { if (pending > 0) gate.signal { scheduled++ } })
        assertEquals(1, scheduled)
    }
    @Test fun captureDuringEmptyWorkerExitSchedulesAfterTheFinalRecheck() {
        val gate = MomoGatewayWakeupGate()
        val finishEntered = CountDownLatch(1)
        val allowFinish = CountDownLatch(1)
        val signalStarted = CountDownLatch(1)
        val signalFinished = CountDownLatch(1)
        val count = AtomicInteger()
        assertTrue(gate.begin())
        val finishing = Thread {
            gate.finish({ finishEntered.countDown(); assertTrue(allowFinish.await(5, TimeUnit.SECONDS)) }, {})
        }
        finishing.start()
        assertTrue(finishEntered.await(2, TimeUnit.SECONDS))
        val capturing = Thread { signalStarted.countDown(); gate.signal { count.incrementAndGet() }; signalFinished.countDown() }
        capturing.start()
        assertTrue(signalStarted.await(2, TimeUnit.SECONDS))
        allowFinish.countDown()
        assertTrue(signalFinished.await(2, TimeUnit.SECONDS))
        finishing.join(2000); capturing.join(2000)
        assertEquals(1, count.get())
    }
    @Test fun overlappingRecoveryJobCannotStartSecondUploader() {
        val gate = MomoGatewayWakeupGate()
        assertTrue(gate.begin())
        assertFalse(gate.begin())
        gate.finish({}, {})
        assertTrue(gate.begin())
    }
}

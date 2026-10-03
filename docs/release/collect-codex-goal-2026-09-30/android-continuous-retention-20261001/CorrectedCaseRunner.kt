import org.junit.runner.JUnitCore
import org.junit.runner.Request
fun main() {
 val result = JUnitCore().run(Request.method(app.cool.mobile.gateway.GatewayAttemptArchiveTest::class.java, "callbackReceiptAcknowledgementsStayHotUntilActualAttemptArchiveClosesThem"))
 for (failure in result.failures) println(failure.trace)
 println("Tests run: ${result.runCount}, Failures: ${result.failureCount}, Ignored: ${result.ignoreCount}")
 if (result.wasSuccessful() && result.runCount == 1 && result.ignoreCount == 0) { println("OK (1 tests)");System.exit(0) } else System.exit(1)
}

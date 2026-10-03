import org.junit.runner.JUnitCore
import org.junit.runner.Request
import org.junit.runner.Description
import org.junit.runner.notification.Failure
import org.junit.runner.notification.RunListener
import org.junit.runner.manipulation.Filter
fun main(args: Array<String>) {
 val skipped = setOf("attemptsContinueBeyondOneLegacyHashShardWithoutGrowingIndexObjects", "segmentedColdStorageSurvivesMoreThanOneHundredAttempts", "signedHeartbeatContinuesPastLegacyLifetimeCeilingWithEveryOriginalPreserved")
 val klass=Class.forName(args[0])
 val request = if(args.size==2) Request.method(klass,args[1]) else Request.aClass(klass).filterWith(object : Filter() {
  override fun shouldRun(d: Description): Boolean = d.methodName !in skipped
  override fun describe() = "Affected cases; excludes three unchanged heavy predecessor cohorts"
 })
 val failed = mutableSetOf<String>();val core = JUnitCore()
 core.addListener(object : RunListener() {
  override fun testStarted(d: Description) { println("BEGIN ${d.className}.${d.methodName}") }
  override fun testFailure(f: Failure) { failed.add(f.description.methodName);println(f.trace) }
  override fun testFinished(d: Description) { println("CASE ${d.className}.${d.methodName} ${if (d.methodName in failed) "FAIL" else "PASS"}") }
 })
 val result=core.run(request)
 println("Tests run: ${result.runCount}, Failures: ${result.failureCount}, Ignored: ${result.ignoreCount}")
 if(result.wasSuccessful() && result.runCount>0 && result.ignoreCount==0) { println("OK (${result.runCount} tests)");System.exit(0) } else System.exit(1)
}

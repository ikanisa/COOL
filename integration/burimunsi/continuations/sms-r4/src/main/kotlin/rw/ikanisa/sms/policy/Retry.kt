package rw.ikanisa.sms.policy

data class RetryLimits(val maxAttempts: Int = 5,val baseDelayMs: Long = 1000,val maxDelayMs: Long = 60000,
                       val maxElapsedMs: Long = 86400000,val leaseMs: Long = 60000) {
    init { require(maxAttempts in 1..100 && baseDelayMs > 0 && maxDelayMs >= baseDelayMs && maxElapsedMs > 0 && leaseMs > 0) }
}
sealed class RetryDecision {
    data class Wait(val at: Long): RetryDecision()
    data class Hold(val reason: String): RetryDecision()
}
object RetryPolicy {
    fun schedule(attempts: Int,now: Long,started: Long,limits: RetryLimits,serverDelayMs: Long? = null): RetryDecision {
        if (now < 0 || started < 0 || now < started || attempts !in 1..limits.maxAttempts) return RetryDecision.Hold("CLOCK_OR_COUNTER_INVALID")
        if (attempts >= limits.maxAttempts) return RetryDecision.Hold("RETRY_LIMIT")
        if (now-started >= limits.maxElapsedMs) return RetryDecision.Hold("RETRY_AGE_LIMIT")
        if (serverDelayMs != null && serverDelayMs !in 0..limits.maxElapsedMs) return RetryDecision.Hold("RETRY_AFTER_REQUIRES_REVIEW")
        var delay = limits.baseDelayMs
        repeat(attempts-1) { delay = if (delay >= limits.maxDelayMs/2+limits.maxDelayMs%2) limits.maxDelayMs else delay*2 }
        delay = maxOf(delay,serverDelayMs ?: 0)
        if (delay > Long.MAX_VALUE-now) return RetryDecision.Hold("CLOCK_OVERFLOW")
        if (now-started > limits.maxElapsedMs-delay) return RetryDecision.Hold("RETRY_AGE_LIMIT")
        return RetryDecision.Wait(now+delay)
    }
    /** HTTP dates are not guessed. An adapter must validate and convert them against its clock. */
    fun deltaSeconds(raw: String?): Long? = raw?.takeIf { Regex("(?:0|[1-9][0-9]{0,8})").matches(it) }?.toLongOrNull()?.times(1000)
}

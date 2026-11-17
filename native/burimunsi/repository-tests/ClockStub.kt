package android.os

/** Deterministic monotonic clock for synthetic repository tests. */
object SystemClock {
    var fixed:Long?=null
    fun elapsedRealtime():Long=fixed?:System.nanoTime()/1_000_000
}

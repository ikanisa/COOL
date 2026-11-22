package rw.ikanisa.burimunsi.core

/** UI memory must not outlive the repository's bounded read cache. Clock rollback
 * is stale, never an extension. This is display freshness, not authorization. */
object SnapshotFreshness {
    const val TTL_MS:Long = 5 * 60 * 1000
    fun reusable(savedAt:Long?,now:Long):Boolean =
        savedAt!=null&&savedAt>=0&&now>=savedAt&&now-savedAt<=TTL_MS
    /** A combined view is only as trustworthy as EVERY constituent snapshot.
     * Unknown, future or negative clocks are not skipped by minOrNull.
     * Expired clocks remain expired and retain their original provenance.
     * Never extend the age of earlier pages when a subsequent page arrives.
     */
    fun oldest(now: Long, vararg savedAt: Long?): Long? =
        if (savedAt.isEmpty() || savedAt.any { it == null || it < 0 || it > now }) null
        else savedAt.filterNotNull().minOrNull()
}


package rw.ikanisa.burimunsi.core

/** UI memory must not outlive the repository's bounded read cache. Clock rollback
 * is stale, never an extension. This is display freshness, not authorization. */
object SnapshotFreshness {
    const val TTL_MS:Long = 5 * 60 * 1000
    fun reusable(savedAt:Long?,now:Long):Boolean =
        savedAt!=null&&savedAt>=0&&now>=savedAt&&now-savedAt<=TTL_MS
}

package rw.ikanisa.burimunsi.core

/** Never silently de-duplicate incompatible snapshots or loop a provider cursor. */
object PageIntegrity {
    const val MAX_RETAINED = 100_000
    fun <T> append(current:Page<T>,next:Page<T>,id:(T)->String):Page<T> {
        checkContract(current.nextCursor!=null,"pagination_complete")
        checkContract(current.revision==next.revision&&current.totalCount==next.totalCount,"cursor_stale")
        checkContract(next.nextCursor==null||next.nextCursor!=current.nextCursor,"invalid_page")
        val merged=current.items+next.items
        checkContract(merged.size<=MAX_RETAINED&&merged.size<=current.totalCount,"invalid_page")
        checkContract(merged.map(id).toSet().size==merged.size,"invalid_page")
        checkContract(next.items.isNotEmpty(),"invalid_page")
        checkContract((next.nextCursor==null)==(merged.size==current.totalCount),"invalid_page")
        return next.copy(items=merged)
    }
}

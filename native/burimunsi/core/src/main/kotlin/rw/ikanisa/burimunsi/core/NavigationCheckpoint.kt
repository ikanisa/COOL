package rw.ikanisa.burimunsi.core

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.util.Base64

/** Small, encrypted-at-rest navigation context. Never stores records, commands or credentials.
 * Restoring this value is not authorization: the current session and route must be revalidated.
 */
data class NavigationCheckpoint(
    val ownerId: String, val groupId: String, val savedAt: Long,
    val route: Route, val routeId: String? = null, val query: String = "",
    val filter: String = "all", val index: Int = 0, val offset: Int = 0,
    val memberAnchorId: String? = null, val memberListing: ListingQuery? = null,
) {
    fun validFor(owner: String, group: String, now: Long): Boolean =
        ownerId == owner && groupId == group && savedAt > 0 && now >= savedAt &&
        now - savedAt <= TTL_MS && structurallyValid()

    private fun structurallyValid(): Boolean =
        ownerId.length in 1..128 && groupId.length in 1..128 &&
        route != Route.LOGIN && query.length <= 80 && query.none { it.isISOControl() } &&
        index in 0..100_000 && offset in 0..100_000 &&
        (if (route in setOf(Route.PAYMENT, Route.MEMBER))
            routeId != null && Regex("[A-Za-z0-9_.:-]{1,128}").matches(routeId) else routeId == null) &&
        filter in filters(route) &&
        (memberAnchorId?.let { anchor ->
            route == Route.MEMBERS && runCatching { Values.id(anchor) }.isSuccess
        } ?: true) &&
        (memberListing?.let { listing ->
            route == Route.MEMBERS && listing.q == query && runCatching { listing.validated(ListingTarget.MEMBERS) }.isSuccess
        } ?: true)

    fun encode(): String {
        require(structurallyValid())
        val bytes = ByteArrayOutputStream()
        DataOutputStream(bytes).use { out ->
            val version = if (memberAnchorId != null || memberListing != null) 2 else 1
            out.writeInt(version); out.writeUTF(ownerId); out.writeUTF(groupId); out.writeLong(savedAt)
            out.writeUTF(route.name); out.writeUTF(routeId.orEmpty()); out.writeUTF(query)
            out.writeUTF(filter); out.writeInt(index); out.writeInt(offset)
            if (version == 2) {
                out.writeUTF(memberAnchorId.orEmpty())
                out.writeBoolean(memberListing != null)
                memberListing?.let {
                    out.writeUTF(it.sort.name); out.writeUTF(it.active)
                    out.writeLong(it.minRwf ?: Long.MIN_VALUE); out.writeLong(it.maxRwf ?: Long.MIN_VALUE)
                }
            }
        }
        return Base64.getEncoder().encodeToString(bytes.toByteArray())
    }
    companion object {
        const val TTL_MS = 15L * 60L * 1000L
        fun filters(route: Route): Set<String> = when(route) {
            Route.PAYMENTS -> setOf("all", "allocated", "unallocated")
            Route.SMS -> setOf("all", "queued", "duplicate")
            else -> setOf("all")
        }
        fun decode(encoded: String?): NavigationCheckpoint? = runCatching {
            require(encoded != null && encoded.length in 1..4096)
            DataInputStream(ByteArrayInputStream(Base64.getDecoder().decode(encoded))).use { input ->
                val version = input.readInt()
                require(version in 1..2)
                val base = NavigationCheckpoint(input.readUTF(), input.readUTF(), input.readLong(),
                    Route.valueOf(input.readUTF()), input.readUTF().ifEmpty { null }, input.readUTF(),
                    input.readUTF(), input.readInt(), input.readInt())
                val value = if (version == 1) base else {
                    val anchor = input.readUTF().ifEmpty { null }
                    val listing = if (input.readBoolean()) ListingQuery(q = base.query,
                        sort = ListingSort.valueOf(input.readUTF()), active = input.readUTF(),
                        minRwf = input.readLong().takeUnless { it == Long.MIN_VALUE },
                        maxRwf = input.readLong().takeUnless { it == Long.MIN_VALUE }) else null
                    base.copy(memberAnchorId = anchor, memberListing = listing)
                }
                require(input.available() == 0 && value.structurallyValid())
                value
            }
        }.getOrNull()
    }
}

interface NavigationCheckpointStore {
    /** Adapters for the same installation file share this identity within the process. */
    val writeScope: Any get() = this
    fun read(): String?
    fun write(value: String)
    fun clear()
}

/** Reserve each change before dispatching to IO. A superseded save or clear cannot
 * replace a later checkpoint, including across Activity controllers in this process. */
class NavigationCheckpointWriter(private val store: NavigationCheckpointStore) {
    private class Order { val latest = java.util.concurrent.atomic.AtomicLong() }
    private companion object {
        val orders = java.util.WeakHashMap<Any, Order>()
    }
    private val order = synchronized(orders) { orders.getOrPut(store.writeScope) { Order() } }

    fun prepare(bookmark: NavigationCheckpoint?): () -> Unit {
        val encoded = bookmark?.encode()
        val revision = order.latest.incrementAndGet()
        return {
            synchronized(order) {
                if (revision == order.latest.get()) {
                    if (encoded == null) store.clear() else store.write(encoded)
                }
            }
        }
    }
}

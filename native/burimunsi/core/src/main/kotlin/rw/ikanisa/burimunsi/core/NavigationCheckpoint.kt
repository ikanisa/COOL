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
        filter in filters(route)

    fun encode(): String {
        require(structurallyValid())
        val bytes = ByteArrayOutputStream()
        DataOutputStream(bytes).use { out ->
            out.writeInt(1); out.writeUTF(ownerId); out.writeUTF(groupId); out.writeLong(savedAt)
            out.writeUTF(route.name); out.writeUTF(routeId.orEmpty()); out.writeUTF(query)
            out.writeUTF(filter); out.writeInt(index); out.writeInt(offset)
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
                require(input.readInt() == 1)
                val value = NavigationCheckpoint(input.readUTF(), input.readUTF(), input.readLong(),
                    Route.valueOf(input.readUTF()), input.readUTF().ifEmpty { null }, input.readUTF(),
                    input.readUTF(), input.readInt(), input.readInt())
                require(input.available() == 0 && value.structurallyValid())
                value
            }
        }.getOrNull()
    }
}

interface NavigationCheckpointStore {
    fun read(): String?
    fun write(value: String)
    fun clear()
}

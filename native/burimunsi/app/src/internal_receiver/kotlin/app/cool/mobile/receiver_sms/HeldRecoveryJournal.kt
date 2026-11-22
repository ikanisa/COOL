package app.cool.mobile.receiver_sms

import android.content.Context
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.core.Values
import rw.ikanisa.burimunsi.storage.SecureStore
import java.time.Instant
import java.util.concurrent.atomic.AtomicBoolean

/** Reads the encrypted held-observation files written by code 48. Its uncertain
 * records have no original consent generation. They can never authorize upload. */
internal object HeldRecoveryJournal {
    private val namePattern = Regex("^buri-(observation-held-recovery-[a-f0-9]{64})\\.v1(?:\\.bak)?$")
    private val hash = Regex("[a-f0-9]{64}")
    private val compactFields = setOf("version", "phase", "requestId", "sourceId", "rowDigest")
    private val fullFields = setOf("version", "collectionId", "accountId", "installationId", "deviceScope",
        "rowId", "phase", "requestId", "rawSender", "rawBody", "sourceMode", "complete", "capturedAt",
        "serviceCentreAt", "inboxReceivedAt", "subscriptionId", "sourceKey")
    private val terminal = setOf("CONFIRMED", "MATCHED_EXISTING")
    private val lock = Any()
    private val maintenanceRunning = AtomicBoolean(false)

    private data class Scope(val owner: ObservationOwner, val installation: String, val device: String)
    private data class Retained(val scope: Scope, val key: String)
    private data class Inventory(val stores: Set<String>, val uncertain: Set<Retained>, val unreadable: Boolean)
    private data class Cached(val directory: String, val stamps: List<Triple<String, Long, Long>>, val inventory: Inventory)
    private var cached: Cached? = null

    private fun name(scope: Scope, key: String): String {
        require(scope.owner.valid() && Values.requestId(scope.installation) == scope.installation &&
            hash.matches(scope.device) && hash.matches(key))
        val fields = listOf("held-recovery-v1", scope.owner.collectionId, scope.owner.accountId, scope.installation, scope.device, key)
        return "observation-held-recovery-" + Values.sha256(fields.joinToString("") { "${it.length}:$it" })
    }

    private fun JSONObject.text(field: String): String = get(field) as? String ?: error("Invalid held journal")
    private fun JSONObject.optionalText(field: String): String? = if (isNull(field)) null else text(field)
    private fun JSONObject.integer(field: String): Long = when (val value = get(field)) {
        is Int -> value.toLong()
        is Long -> value
        else -> error("Invalid held journal")
    }

    private fun validateCompact(value: JSONObject) {
        require(value.keys().asSequence().toSet() == compactFields && value.integer("version") == 2L &&
            value.text("phase") in terminal && Values.requestId(value.text("requestId")) == value.text("requestId") &&
            Values.id(value.text("sourceId")) == value.text("sourceId") && hash.matches(value.text("rowDigest")))
    }

    private fun inspect(store: SecureStore, storeName: String): Retained? {
        val value = JSONObject(checkNotNull(store.read()))
        if (value.integer("version") == 2L) {
            validateCompact(value)
            return null
        }
        val phase = value.text("phase")
        val completed = phase in terminal
        require(value.integer("version") == 1L && (completed || phase == "PREPARED" || phase == "ATTEMPTING") &&
            value.keys().asSequence().toSet() == if (completed) fullFields + "terminalSourceId" else fullFields)
        val request = value.text("requestId")
        val scope = Scope(ObservationOwner(value.text("collectionId"), value.text("accountId")),
            value.text("installationId"), value.text("deviceScope"))
        val key = value.text("sourceKey")
        val row = value.integer("rowId")
        require(name(scope, key) == storeName && Values.requestId(request) == request && row > 0 &&
            value.text("sourceMode") == "catch_up" && value.get("complete") == false)
        // The protected header suffices to keep an uncertain request. Its raw fields stay unused.
        if (!completed) return Retained(scope, key)
        val sender = value.text("rawSender")
        val body = value.text("rawBody")
        val received = value.text("inboxReceivedAt")
        val sent = value.optionalText("serviceCentreAt")
        val subscription = if (value.isNull("subscriptionId")) null else value.integer("subscriptionId")
        require(sender.length in 1..96 && sender.trim() == sender && body.toByteArray(Charsets.UTF_8).size in 1..3000 &&
            (subscription == null || subscription in 0..Int.MAX_VALUE.toLong()))
        listOfNotNull(value.text("capturedAt"), received, sent).forEach { Instant.parse(it) }
        val source = value.text("terminalSourceId")
        require(Values.id(source) == source)
        val fields = listOf("burimunsi-held-row-v2", row.toString(), key, sender, Values.sha256(body), received,
            sent?.let { "1$it" } ?: "0", subscription?.let { "1$it" } ?: "0")
        val digest = Values.sha256(fields.joinToString("") { "${it.length}:$it" })
        val compact = JSONObject().put("version", 2).put("phase", phase).put("requestId", request)
            .put("sourceId", source).put("rowDigest", digest)
        store.write(compact.toString())
        val saved = JSONObject(checkNotNull(store.read()))
        validateCompact(saved)
        require(compactFields.all { saved.get(it) == compact.get(it) })
        return null
    }

    private fun inventory(context: Context): Inventory = synchronized(lock) {
        val directory = context.noBackupFilesDir
        val files = checkNotNull(directory.listFiles { _, filename -> namePattern.matches(filename) })
        val stamps = files.map { Triple(it.name, it.length(), it.lastModified()) }.sortedBy { it.first }
        cached?.takeIf { it.directory == directory.absolutePath && it.stamps == stamps }?.let { return@synchronized it.inventory }
        val stores = stamps.map { namePattern.matchEntire(it.first)!!.groupValues[1] }.toSet()
        val pending = mutableSetOf<Retained>()
        var unreadable = false
        for (storeName in stores) {
            try {
                inspect(SecureStore(context, storeName), storeName)?.let { pending.add(it) }
            } catch (_: Exception) {
                unreadable = true
            }
        }
        Inventory(stores, pending, unreadable).also {
            cached = if (unreadable) null else Cached(directory.absolutePath, stamps, it)
        }
    }

    fun protects(context: Context, owner: ObservationOwner, installation: String, device: String, key: String): Boolean {
        val inventory = inventory(context)
        if (inventory.unreadable) return true
        if (inventory.stores.isEmpty()) return false
        val scope = Scope(owner, installation, device)
        // A retained row cannot be replayed under a different operator in the same collection.
        return name(scope, key) in inventory.stores || inventory.uncertain.any {
            it.key == key && it.scope.owner.collectionId == owner.collectionId &&
                it.scope.installation == installation && it.scope.device == device
        }
    }

    fun hasUncertain(context: Context, owner: ObservationOwner, installation: String, device: String): Boolean {
        val records = inventory(context)
        return records.unreadable || records.uncertain.any { it.scope == Scope(owner, installation, device) }
    }

    fun hasRecords(context: Context): Boolean = inventory(context).stores.isNotEmpty()

    /** Safe on resume without an authenticated operator. Only valid v1 terminal records are rewritten. */
    fun maintain(context: Context) {
        if (!maintenanceRunning.compareAndSet(false, true)) return
        try {
            Thread({
                try { inventory(context.applicationContext) } catch (_: Exception) { /* Retain every unreadable record for a subsequent attempt. */ }
                finally { maintenanceRunning.set(false) }
            }, "held-recovery-privacy-migration").start()
        } catch (failure: Exception) {
            maintenanceRunning.set(false)
        }
    }
}

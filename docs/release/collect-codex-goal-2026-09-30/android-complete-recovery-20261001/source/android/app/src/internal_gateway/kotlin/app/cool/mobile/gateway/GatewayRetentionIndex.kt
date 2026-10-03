package app.cool.mobile.gateway

import org.json.JSONArray
import org.json.JSONObject

/** Fixed-depth, append-only identity index. Each encrypted node has at most
 * 256 child bytes, independent of lifetime receipt count. The exact object is
 * read back before a leaf and its ancestors are published. A referenced missing
 * node/object is corruption; an interrupted unindexed object may only repair
 * its original identity. This index supplies evidence, never send authority. */
internal class GatewayRetentionIndex(
    private val load: (String) -> JSONObject?,
    private val save: (String, JSONObject) -> Unit,
    private val hasRetentionFiles: () -> Boolean,
) {
    private val kinds = setOf("request", "receipt", "attempt", "callback", "callback-body", "protocol", "terminal", "observed-attempt", "late-evidence", "late-work", "late-body", "late-receipt")
    private fun control(): JSONObject {
        val marker = load("retention-marker")
        val value = load("retention-control")
        if (value == null) {
            if (hasRetentionFiles()) throw GatewayStateException("gateway_retention_missing")
            if (marker != null) {
                requireKeys(marker, setOf("contract_version", "established"))
                if (strictInteger(marker, "contract_version") != 4L || !strictBoolean(marker, "established")) invalidArchive()
            }
            return JSONObject().put("contract_version", 4).put("kinds", JSONArray())
        }
        if (marker == null) invalidArchive()
        requireKeys(marker, setOf("contract_version", "established"))
        if (strictInteger(marker, "contract_version") != 4L || !strictBoolean(marker, "established")) invalidArchive()
        requireKeys(value, setOf("contract_version", "kinds"))
        val rows = value.getJSONArray("kinds")
        if (strictInteger(value, "contract_version") != 4L || rows.length() > kinds.size) invalidArchive()
        val known = (0 until rows.length()).map { rows.getString(it) }
        if (known.toSet().size != known.size || known.any { it !in kinds }) invalidArchive()
        return value
    }
    private fun node(kind: String, prefix: String, required: Boolean): JSONObject? {
        val value = load("retention-index-$kind-${prefix.ifEmpty { "root" }}")
        if (value == null) {
            if (required) throw GatewayStateException("gateway_retention_missing")
            return null
        }
        requireKeys(value, setOf("contract_version", "children", "object_sha256"))
        if (strictInteger(value, "contract_version") != 4L) invalidArchive()
        val rows = value.getJSONArray("children")
        val children = (0 until rows.length()).map { rows.getString(it) }
        if (rows.length() > 256 || children.toSet().size != children.size || children.any { !it.matches(Regex("[0-9a-f]{2}")) }) invalidArchive()
        if (prefix.length == 32) {
            if (rows.length() != 0 || !strictString(value, "object_sha256").matches(Regex("[0-9a-f]{64}"))) invalidArchive()
        } else if (!value.isNull("object_sha256")) invalidArchive()
        return value
    }
    private fun empty() = JSONObject().put("contract_version", 4).put("children", JSONArray()).put("object_sha256", JSONObject.NULL)
    private fun check(kind: String, key: String) { if (kind !in kinds || !key.matches(Regex("[0-9a-f]{32}"))) invalidArchive() }
    fun hasKind(kind: String): Boolean {
        if (kind !in kinds) invalidArchive()
        val rows = control().getJSONArray("kinds")
        return (0 until rows.length()).any { rows.getString(it) == kind }
    }
    /** Fixed-depth successor traversal. Traversal and hash readback read a bounded number of fixed-depth paths
     * per returned key; child sets are bounded to 256 and sorted independently of
     * append order. Referenced missing nodes fail closed. */
    fun page(kind: String, afterExclusive: String?, limit: Int, ceiling: String): List<String> {
        check(kind, ceiling);afterExclusive?.let { check(kind, it) }
        if (limit !in 1..8 || (afterExclusive != null && afterExclusive > ceiling)) invalidArchive()
        val required = hasKind(kind)
        val root = node(kind, "", required) ?: return emptyList()
        val result = ArrayList<String>()
        fun visit(prefix: String, value: JSONObject) {
            if (result.size >= limit || prefix > ceiling.take(prefix.length)) return
            if (prefix.length == 32) { if (afterExclusive == null || prefix > afterExclusive) { if (!indexed(kind, prefix)) invalidArchive();result.add(prefix) };return }
            val children = value.getJSONArray("children")
            for (child in (0 until children.length()).map { children.getString(it) }.sorted()) {
                val next = prefix + child
                if (afterExclusive != null && next < afterExclusive.take(next.length)) continue
                if (next > ceiling.take(next.length)) break
                visit(next, node(kind, next, true) ?: invalidArchive())
                if (result.size >= limit) break
            }
        }
        visit("", root);return result
    }
    fun indexed(kind: String, key: String): Boolean {
        check(kind, key)
        val catalog = control().getJSONArray("kinds")
        var current = node(kind, "", (0 until catalog.length()).any { catalog.getString(it) == kind }) ?: return false
        for (depth in 0 until 16) {
            val byte = key.substring(depth * 2, depth * 2 + 2)
            val children = current.getJSONArray("children")
            if (!(0 until children.length()).any { children.getString(it) == byte }) return false
            current = node(kind, key.substring(0, depth * 2 + 2), true) ?: invalidArchive()
        }
        val value = load("retention-$kind-$key") ?: throw GatewayStateException("gateway_retention_missing")
        if (sha256(retentionCanonical(value)) != strictString(current, "object_sha256")) throw GatewayStateException("gateway_archive_source_conflict")
        return true
    }
    fun read(kind: String, key: String): JSONObject? {
        check(kind, key)
        val indexed = indexed(kind, key)
        val value = load("retention-$kind-$key")
        if (indexed && value == null) throw GatewayStateException("gateway_retention_missing")
        return value
    }
    internal fun validateRecoveryNode(kind: String, prefix: String) {
        if(kind !in kinds || (prefix.isNotEmpty() && !prefix.matches(Regex("(?:[0-9a-f]{2}){1,16}")))) invalidArchive()
        control();val value=node(kind,prefix,true) ?: invalidArchive()
        if(prefix.length==32) {
            val objectValue=load("retention-$kind-$prefix") ?: throw GatewayStateException("gateway_retention_missing")
            if(sha256(retentionCanonical(objectValue))!=strictString(value,"object_sha256")) invalidArchive()
        } else {
            val children=value.getJSONArray("children")
            for(i in 0 until children.length()) node(kind,prefix+children.getString(i),true) ?: invalidArchive()
        }
    }
    internal fun validateRecoveryRoots() {
        val rows=control().getJSONArray("kinds")
        for(i in 0 until rows.length()) node(rows.getString(i),"",true) ?: invalidArchive()
    }
    fun publish(kind: String, key: String, value: JSONObject) {
        check(kind, key)
        val catalog = control()
        val before = read(kind, key)
        if (before != null && !archiveJsonEqual(before, value)) throw GatewayStateException("gateway_archive_immutable")
        // Establish control before the first object. Missing control thereafter
        // cannot reset the namespace and permit a UUID to become a new intent.
        if (load("retention-control") == null) {
            save("retention-marker", JSONObject().put("contract_version", 4).put("established", true))
            save("retention-control", catalog)
        }
        if (before == null) save("retention-$kind-$key", value)
        val readback = load("retention-$kind-$key") ?: invalidArchive()
        if (!archiveJsonEqual(readback, value)) invalidArchive()
        val leaf = empty().put("object_sha256", sha256(retentionCanonical(readback)))
        val priorLeaf = node(kind, key, false)
        if (priorLeaf != null && !archiveJsonEqual(priorLeaf, leaf)) invalidArchive()
        if (priorLeaf == null) save("retention-index-$kind-$key", leaf)
        // Bottom-up publication keeps incomplete new paths invisible. Existing
        // sibling paths remain immutable and readable after every interruption.
        for (depth in 15 downTo 0) {
            val prefix = key.substring(0, depth * 2)
            val byte = key.substring(depth * 2, depth * 2 + 2)
            val parent = node(kind, prefix, false) ?: empty()
            val children = parent.getJSONArray("children")
            if (!(0 until children.length()).any { children.getString(it) == byte }) {
                children.put(byte)
                save("retention-index-$kind-${prefix.ifEmpty { "root" }}", parent)
            }
        }
        val known = catalog.getJSONArray("kinds")
        if (!(0 until known.length()).any { known.getString(it) == kind }) { known.put(kind);save("retention-control", catalog) }
        if (!indexed(kind, key)) invalidArchive()
    }
}

internal fun retentionUuidKey(id: String): String { if (!validUuid(id)) invalidArchive();return id.replace("-", "") }
internal fun retentionCanonical(value: Any?): String = when (value) {
    is JSONObject -> value.keys().asSequence().toList().sorted().joinToString(",", "{", "}") { JSONObject.quote(it) + ":" + retentionCanonical(value.get(it)) }
    is JSONArray -> (0 until value.length()).joinToString(",", "[", "]") { retentionCanonical(value.get(it)) }
    is String -> JSONObject.quote(value)
    is Number -> JSONObject.numberToString(value)
    is Boolean -> value.toString()
    null, JSONObject.NULL -> "null"
    else -> invalidArchive()
}

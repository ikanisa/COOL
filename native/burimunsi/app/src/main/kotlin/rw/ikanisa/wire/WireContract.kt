package rw.ikanisa.wire

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.time.OffsetDateTime

/** Values never appear in failures. This module cannot mutate queues, sessions or money. */
class ContractViolation(val code: String, val fieldPath: String = "$") : IllegalArgumentException(code)
internal fun reject(code: String, path: String = "$"): Nothing = throw ContractViolation(code, path)
@Suppress("UNCHECKED_CAST")
fun objectValue(value: Any?): Map<String, Any?> = value as? Map<String, Any?> ?: reject("CONTRACT_TYPE")
@Suppress("UNCHECKED_CAST")
internal fun arrayValue(value: Any?): List<Any?> = value as? List<Any?> ?: reject("CONTRACT_TYPE")

/** Deliberately narrow media profile, not a general-purpose MIME parser. */
object WireMediaType {
    fun isUtf8(value: String?, mediaType: String = "application/json"): Boolean =
        value != null && value.length <= 256 && value.all { it.code < 128 } && !value.contains('\r') && !value.contains('\n') &&
        Regex("""[ \t]*${Regex.escape(mediaType)}[ \t]*(?:;[ \t]*charset[ \t]*=[ \t]*(?:utf-8|"utf-8")[ \t]*)?""", RegexOption.IGNORE_CASE).matches(value)
}

/** JSON transport profile: canonical safe-integer number tokens, unique keys, bounded depth.
 * A canonical integer token policy is deliberately stricter than general-purpose JSON. */
object StrictJson {
    fun parse(bytes: ByteArray, maxBytes: Int = 2_000_000): Any? {
        if (bytes.size > maxBytes) reject("CONTRACT_SIZE")
        val text = try { Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString() }
        catch (_: Exception) { reject("CONTRACT_UTF8") }
        return parse(text, maxBytes)
    }
    fun parse(text: String, maxBytes: Int = 2_000_000): Any? {
        if (text.toByteArray(Charsets.UTF_8).size > maxBytes) reject("CONTRACT_SIZE")
        return Parser(text).parse()
    }
    private class Parser(private val text: String) {
        private var p = 0
        private var nodes = 0
        private fun peek(): Char? = text.getOrNull(p)
        private fun ws() { while (peek() in listOf(' ', '\t', '\r', '\n')) p++ }
        private fun take(c: Char) { if (peek() != c) reject("CONTRACT_JSON"); p++ }
        private fun string(): String {
            take('"'); val out = StringBuilder()
            while (p < text.length) {
                val ch = text[p++]
                if (ch == '"') {
                    val result = out.toString(); var j = 0
                    while (j < result.length) {
                        val c = result[j++]
                        if (c.isHighSurrogate()) { if (j >= result.length || !result[j++].isLowSurrogate()) reject("CONTRACT_UNICODE") }
                        else if (c.isLowSurrogate()) reject("CONTRACT_UNICODE")
                    }
                    return result
                }
                if (ch.code < 32) reject("CONTRACT_JSON")
                if (ch != '\\') { out.append(ch); continue }
                if (p >= text.length) reject("CONTRACT_JSON")
                when (val e = text[p++]) {
                    '"', '\\', '/' -> out.append(e)
                    'n' -> out.append('\n'); 'r' -> out.append('\r'); 't' -> out.append('\t')
                    'b' -> out.append('\b'); 'f' -> out.append('\u000c')
                    'u' -> { if (p + 4 > text.length) reject("CONTRACT_JSON")
                        val raw = text.substring(p, p + 4)
                        if (!Regex("[0-9a-fA-F]{4}").matches(raw)) reject("CONTRACT_JSON")
                        out.append(raw.toInt(16).toChar()); p += 4 }
                    else -> reject("CONTRACT_JSON")
                }
            }
            reject("CONTRACT_JSON")
        }
        private fun value(depth: Int): Any? {
            if (depth > 64 || ++nodes > 100000) reject("CONTRACT_COMPLEXITY")
            ws()
            when (peek()) {
                '"' -> return string()
                '{' -> {
                    p++; ws(); val result = linkedMapOf<String, Any?>()
                    if (peek() == '}') { p++; return result }
                    while (true) {
                        ws(); if (peek() != '"') reject("CONTRACT_JSON")
                        val key = string(); if (result.containsKey(key)) reject("CONTRACT_DUPLICATE_KEY")
                        ws(); take(':'); result[key] = value(depth + 1); ws()
                        if (peek() == '}') { p++; return result }; take(',')
                    }
                }
                '[' -> {
                    p++; ws(); val result = mutableListOf<Any?>()
                    if (peek() == ']') { p++; return result }
                    while (true) { result.add(value(depth + 1)); ws()
                        if (peek() == ']') { p++; return result }; take(',') }
                }
            }
            for ((literal, v) in listOf("true" to true, "false" to false, "null" to null)) {
                if (text.startsWith(literal, p)) { p += literal.length; return v }
            }
            val token = Regex("-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?").find(text, p)
                ?.takeIf { it.range.first == p }?.value ?: reject("CONTRACT_JSON")
            p += token.length
            if (!Regex("-?(0|[1-9][0-9]*)").matches(token) || token == "-0") reject("CONTRACT_NUMBER")
            val number = token.toLongOrNull() ?: reject("CONTRACT_NUMBER")
            if (number !in -9007199254740991L..9007199254740991L) reject("CONTRACT_NUMBER")
            return number
        }
        fun parse(): Any? { val result = value(0); ws(); if (p != text.length) reject("CONTRACT_JSON"); return result }
    }
}

/** Form-query decoding with fatal UTF-8 and exact duplicate-key detection. */
object StrictQuery {
    fun parse(raw: String): Map<String, Any?> {
        if (raw.toByteArray(Charsets.UTF_8).size > 8192) reject("CONTRACT_QUERY_SIZE")
        if (raw.isEmpty()) return emptyMap()
        fun component(value: String): String {
            val out = java.io.ByteArrayOutputStream()
            var at = 0
            while (at < value.length) {
                when (val ch = value[at]) {
                    '%' -> {
                        if (at + 2 >= value.length || !Regex("[a-fA-F0-9]{2}").matches(value.substring(at+1,at+3))) reject("CONTRACT_QUERY_ENCODING")
                        out.write(value.substring(at+1,at+3).toInt(16)); at += 3
                    }
                    '+' -> { out.write(32); at++ }
                    else -> {
                        if (ch.isSurrogate()) {
                            if (!ch.isHighSurrogate() || at + 1 >= value.length || !value[at+1].isLowSurrogate()) reject("CONTRACT_QUERY_ENCODING")
                            out.write(value.substring(at,at+2).toByteArray(Charsets.UTF_8)); at += 2
                        } else { out.write(ch.toString().toByteArray(Charsets.UTF_8)); at++ }
                    }
                }
            }
            return try { Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(out.toByteArray())).toString() }
                catch (_: Exception) { reject("CONTRACT_QUERY_ENCODING") }
        }
        val result = linkedMapOf<String, Any?>()
        for (pair in raw.split('&')) {
            val at = pair.indexOf('='); if (at <= 0) reject("CONTRACT_QUERY")
            val key = component(pair.substring(0,at)); val value = component(pair.substring(at+1))
            if (result.containsKey(key)) reject("CONTRACT_QUERY_DUPLICATE")
            result[key] = value
        }
        return result
    }
}

class WireContract(private val product: String, private val version: String,
    private val defs: Map<String, Any?>, private val routes: List<List<String>> = emptyList()) {
    fun validate(name: String, value: Any?): Any? {
        val root = defs[name] ?: reject("CONTRACT_OPERATION")
        fun visit(raw: Any?, x: Any?, p: String) {
            val s = objectValue(raw)
            if (s.containsKey("\$ref")) { visit(defs[(s["\$ref"] as String).substring(8)], x, p); return }
            if (s.containsKey("anyOf")) { if (x != null) visit(arrayValue(s["anyOf"])[0], x, p); return }
            val type = s["type"] as String
            val code = s["x-code"] as? String
            val validType = when (type) {
                "object" -> x is Map<*, *>; "array" -> x is List<*>; "string" -> x is String
                "boolean" -> x is Boolean; "integer" -> x is Long || x is Int
                "null" -> x == null; else -> false
            }
            if (!validType) reject(code ?: "CONTRACT_TYPE", p)
            if (s.containsKey("const") && x != s["const"]) reject(code ?: "CONTRACT_VALUE", p)
            if (s.containsKey("enum") && x !in arrayValue(s["enum"])) reject(code ?: "CONTRACT_ENUM", p)
            when (type) {
                "object" -> {
                    val v = objectValue(x); val props = objectValue(s["properties"])
                    for (key in arrayValue(s["required"])) if (!v.containsKey(key)) reject("CONTRACT_MISSING_FIELD", "$p.$key")
                    if (v.keys.any { !props.containsKey(it) }) reject("CONTRACT_UNKNOWN_FIELD", p)
                    for ((key, child) in props) if (v.containsKey(key)) visit(child, v[key], "$p.$key")
                }
                "array" -> {
                    val v = arrayValue(x)
                    if (v.size < (s["minItems"] as Number).toInt() || v.size > (s["maxItems"] as Number).toInt()) reject("CONTRACT_LENGTH", p)
                    if (s["uniqueItems"] == true && v.toSet().size != v.size) reject("CONTRACT_DUPLICATE", p)
                    v.forEachIndexed { index, item -> visit(s["items"], item, "$p[$index]") }
                }
                "string" -> {
                    val v = x as String; val length = v.codePointCount(0, v.length)
                    if ((s["minLength"] is Number && length < (s["minLength"] as Number).toInt()) || (s["maxLength"] is Number && length > (s["maxLength"] as Number).toInt())) reject(code ?: "CONTRACT_STRING", p)
                    if (v.contains('\u0000')) reject(code ?: "CONTRACT_STRING", p)
                    if (s["pattern"] is String && !Regex(s["pattern"] as String).containsMatchIn(v)) reject(code ?: "CONTRACT_STRING", p)
                    if (s["format"] == "date-time" && runCatching { OffsetDateTime.parse(v) }.isFailure) reject("CONTRACT_TIMESTAMP", p)
                }
                "integer" -> {
                    val v = (x as Number).toLong()
                    if (s["minimum"] is Number && v < (s["minimum"] as Number).toLong()) reject(code ?: "CONTRACT_RANGE", p)
                    if (s["maximum"] is Number && v > (s["maximum"] as Number).toLong()) reject(code ?: "CONTRACT_RANGE", p)
                }
            }
        }
        visit(root, value, "$"); return value
    }
    private fun binding(actual: Map<String, Any?>, expected: Map<String, Any?>) {
        for (key in listOf("ownerId", "installationId", "operationId", "action", "requestId", "groupId", "actorId"))
            if (expected.containsKey(key) && actual[key] != expected[key]) reject("CONTRACT_IDENTITY", "$.binding.$key")
        if (expected.containsKey("generation") && actual["generation"] != expected["generation"]) reject("CONTRACT_GENERATION", "$.binding.generation")
        if (expected.containsKey("currentGeneration") && expected["currentGeneration"] != expected["generation"]) reject("CONTRACT_GENERATION", "$.binding.generation")
    }
    fun semantics(operation: String, r: Map<String, Any?>, expected: Map<String, Any?>) {
        val b = objectValue(r["binding"]); binding(b, expected)
        val d = if (product == "mmoney") r else objectValue(r["data"])
        if (product == "mmoney") {
            for (key in listOf("installationId", "generation")) if (r.containsKey(key) && r[key] != b[key]) reject(if (key == "generation") "CONTRACT_GENERATION" else "CONTRACT_IDENTITY", "$.$key")
            if (b["action"] != operation) reject("CONTRACT_IDENTITY", "$.binding.action")
            if (operation == "state" && ((r["state"] == "deleted" && (!r.containsKey("receiptId") || !r.containsKey("deletedAt"))) || (r["state"] == "active" && (r.containsKey("receiptId") || r.containsKey("deletedAt"))))) reject("CONTRACT_STATE")
            if (operation == "ingest") {
                val seen = mutableSetOf<Any?>()
                for (v in arrayValue(r["acknowledgements"])) {
                    val ack = objectValue(v)
                    if (!seen.add(ack["id"])) reject("CONTRACT_DUPLICATE")
                    if (if (ack["status"] == "rejected") ack["canonicalId"] != null || !ack.containsKey("code") else ack["canonicalId"] == null || ack.containsKey("code")) reject("CONTRACT_ACK")
                }
                val ids = expected["messageIds"] as? List<*> ?: reject("CONTRACT_CONTEXT")
                if (ids.toSet().size != ids.size || seen.size != ids.size || ids.any { it !in seen }) reject("CONTRACT_IDENTITY")
            }
            if (operation == "changes") {
                val cursor = expected["cursor"] as? String ?: reject("CONTRACT_CONTEXT")
                if (!Regex("(0|[1-9][0-9]{0,18})").matches(cursor)) reject("CONTRACT_CONTEXT")
                var last = cursor.toBigInteger(); val next = (r["nextCursor"] as String).toBigInteger()
                val changes = arrayValue(r["changes"])
                for (v in changes) {
                    val change = objectValue(v); val step = (change["cursor"] as String).toBigInteger()
                    if (step <= last || step > next) reject("CONTRACT_CURSOR"); last = step
                    val p = objectValue(change["projection"])
                    val outcome = if (p["posted"] == true) "recorded" else if (p["kind"] == "balance") "balance_only" else "original_only"
                    if (change["outcome"] != outcome) reject("CONTRACT_STATUS")
                    if (p["posted"] == true && (p["kind"] !in listOf("received", "payment") || p["amount"] == null || p["amount"] == "0" || p["currency"] != "RWF")) reject("CONTRACT_PROJECTION")
                    if (p["totalDebit"] != null && (p["kind"] != "payment" || p["amount"] == null || (p["totalDebit"] as String).toBigInteger() < (p["amount"] as String).toBigInteger())) reject("CONTRACT_PROJECTION")
                }
                if (last != next || (changes.isEmpty() && r["hasMore"] == true)) reject("CONTRACT_CURSOR")
            }
        } else {
            fun rows(list: Any?) {
                val seen = mutableSetOf<Any?>()
                for (v in arrayValue(list)) { val row = objectValue(v)
                    if (row["groupId"] != b["groupId"]) reject("CONTRACT_IDENTITY")
                    if (!seen.add(row["id"])) reject("CONTRACT_DUPLICATE") }
            }
            if (d.containsKey("items") && operation != "observationReconcileBatch") {
                rows(d["items"]); val items = arrayValue(d["items"])
                if ((d["totalCount"] as Number).toLong() < items.size || (d["nextCursor"] != null && items.isEmpty())) reject("CONTRACT_PAGE")
            }
            if (d.containsKey("recentPayments")) rows(d["recentPayments"])
            if (d.containsKey("groupId") && d["groupId"] != b["groupId"]) reject("CONTRACT_IDENTITY")
            if (operation in listOf("payment", "member", "rawSms") && d["id"] != expected["recordId"]) reject("CONTRACT_IDENTITY")
            if (d.containsKey("profile")) {
                val profile = objectValue(d["profile"])
                if (profile["id"] != b["actorId"]) reject("CONTRACT_IDENTITY")
                if (expected.containsKey("phone") && profile["phone"] != expected["phone"]) reject("CONTRACT_IDENTITY")
                if (expected["now"] is Number && (d["expiresAt"] as Number).toLong() <= (expected["now"] as Number).toLong()) reject("CONTRACT_EXPIRED")
            }
            if (operation == "allocate" && (d["transactionId"] != expected["recordId"] || d["memberId"] != expected["memberId"])) reject("CONTRACT_IDENTITY")
            if (operation == "enroll" && d["phone"] != expected["phone"]) reject("CONTRACT_IDENTITY")
            if (operation == "onboardingSuggestions") for (v in arrayValue(d["items"])) {
                val item=objectValue(v);if(item["id"]!=item["candidateId"])reject("CONTRACT_IDENTITY")
            }
            if (operation == "membersImport") {
                val items=arrayValue(d["results"]).map(::objectValue)
                val requested=expected["importRows"] as? List<*> ?: reject("CONTRACT_CONTEXT")
                val returned=items.map{it["row"]}
                if(d["requestId"]!=expected["commandRequestId"]||returned.toSet().size!=returned.size||
                    returned.toSet()!=requested.toSet()||returned.size!=requested.size||
                    (d["created"] as Number).toInt()!=items.count{it["status"]=="created"}||
                    items.any{(it["status"] in listOf("created","already_registered"))!=(it["memberId"]!=null)})
                    reject("CONTRACT_IDENTITY")
            }
            if (operation == "staffUpdate" && d["id"] != expected["staffId"]) reject("CONTRACT_IDENTITY")
            if (operation == "replace" && d["requestId"] != expected["commandRequestId"]) reject("CONTRACT_IDENTITY")
            if (operation == "observation" || operation == "observationRecoverHeld") {
                if (!expected.containsKey("commandRequestId") || !expected.containsKey("observationBodySha256") ||
                    d["requestId"] != expected["commandRequestId"] || d["bodySha256"] != expected["observationBodySha256"])
                    reject("CONTRACT_IDENTITY")
                if (d["status"] != "source_unresolved" || (d["financialEffects"] as? Number)?.toLong() != 0L) reject("CONTRACT_STATE")
                if (operation == "observationRecoverHeld" && d["autoProcessing"] != "held") reject("CONTRACT_STATE")
            }
            if (operation == "observationConsentSet" &&
                (!expected.containsKey("consentEnabled") || !expected.containsKey("consentGeneration") ||
                 d["enabled"] != expected["consentEnabled"] || d["generation"] != expected["consentGeneration"])) reject("CONTRACT_IDENTITY")
            if (operation == "observationProfile") {
                val now=(expected["now"] as? Number)?.toLong() ?: reject("CONTRACT_CONTEXT")
                val issued=(d["issuedAt"] as? Number)?.toLong() ?: reject("CONTRACT_TIMESTAMP")
                val expires=(d["expiresAt"] as? Number)?.toLong() ?: reject("CONTRACT_TIMESTAMP")
                if (issued<=0 || issued>now+300_000 || expires<=now || expires-issued!=86_400_000L) reject("CONTRACT_EXPIRED")
            }
            if (operation == "observationPage") for (item in arrayValue(d["items"])) {
                val row=objectValue(item)
                if(row["sourceKind"]!="observation"||row["id"]!=row["sourceId"]||row["status"]!="source_unresolved"||
                    (row["financialEffects"] as? Number)?.toLong()!=0L)reject("CONTRACT_IDENTITY")
            }
            if(operation=="observationProcessingStatus"){
                val requested=arrayValue(expected["sourceIds"])
                val statuses=arrayValue(d["statuses"]).map(::objectValue)
                if(statuses.size!=requested.size||statuses.indices.any{i->
                    statuses[i]["sourceId"]!=requested[i]||statuses[i]["canRetry"]==true&&statuses[i]["status"] !in listOf("retrying","needs_review")
                })reject("CONTRACT_IDENTITY")
            }
            if(operation=="observationProcessingRetry"&&
                (d["sourceId"]!=expected["recordId"]||d["requestId"]!=expected["commandRequestId"]))reject("CONTRACT_IDENTITY")
            if(operation=="observationReconcile"&&
                (d["sourceKey"]!=expected["sourceKey"]||(d["state"]=="matched")!=(d["sourceId"]!=null)))reject("CONTRACT_IDENTITY")
            if(operation=="observationReconcileBatch"){
                val requested=arrayValue(expected["sourceKeys"])
                val items=arrayValue(d["items"]).map(::objectValue)
                if(requested.toSet().size!=requested.size||items.size!=requested.size||items.indices.any{i->
                    items[i]["sourceKey"]!=requested[i]||(items[i]["state"]=="matched")!=(items[i]["sourceId"]!=null)
                })reject("CONTRACT_IDENTITY")
            }
            if(operation in setOf("observationReconcileStatus","observationReconcileVerifiedStatus")&&
                (d["hasRecorded"]==true)!=((d["recordedCount"] as Number).toLong()>0L))reject("CONTRACT_STATE")
            if(operation=="observationReconcileVerifiedStatus"&&d["scope"]!="verified_collection")reject("CONTRACT_STATE")
            if (operation == "observationReveal") {
                if(d["sourceKind"]!="observation"||d["sourceId"]!=expected["recordId"]||
                    d["status"]!="source_unresolved"||(d["financialEffects"] as? Number)?.toLong()!=0L)reject("CONTRACT_IDENTITY")
                val requested=(expected["displayHintsVersion"] as? Number)?.toInt()==1
                if(requested!=d.containsKey("displayHints"))reject("CONTRACT_IDENTITY")
                if(d["displayHints"]!=null){
                    val h=objectValue(d["displayHints"])
                    val hints=arrayValue(h["hints"]).map{item->val v=objectValue(item)
                        rw.ikanisa.burimunsi.core.ObservationHint(v["kind"] as String,v["text"] as String,
                            (v["start"] as Number).toInt(),(v["end"] as Number).toInt())}
                    val value=rw.ikanisa.burimunsi.core.ObservationHintSet((h["schemaVersion"] as Number).toInt(),
                        h["kind"] as String,h["profileVersion"] as String,h["profileSha256"] as String,h["bodySha256"] as String,hints)
                    if(!rw.ikanisa.burimunsi.core.ObservationHintValidation.valid(d["rawBody"] as String,value))reject("CONTRACT_IDENTITY")
                }
            }
            if (operation == "retirementOutcome") {
                if (d["requestId"] != expected["recordId"] || d["fingerprint"] != expected["handoffFingerprint"]) reject("CONTRACT_IDENTITY")
                if (if(d["state"] == "retired") d["ack"] == null || objectValue(d["ack"])["requestId"] != d["requestId"] else d["ack"] != null) reject("CONTRACT_STATE")
            }
            if (operation in listOf("operation", "recovery", "staffResolution") && d["requestId"] != expected["recordId"]) reject("CONTRACT_IDENTITY")
            if (operation == "operation") {
                if(d["actorId"] != b["actorId"]) reject("CONTRACT_IDENTITY")
                if(d["state"] == "pending") {
                    if(d["financialState"] != "unresolved" || d.containsKey("operation")) reject("CONTRACT_STATE")
                } else if(d["operation"] !is String || d["financialState"] == "unresolved" ||
                    (d["operation"] == "burimunsi.allocate") == (d["financialState"] == "not_applicable")) reject("CONTRACT_STATE")
            }
            if (operation in listOf("recovery", "staffResolution")) {
                if (d["originDigest"] != expected["originDigest"] || d["actorId"] != b["actorId"] || d["installationId"] != b["installationId"]) reject("CONTRACT_IDENTITY")
                if ((d["state"] == "cancelled") != d.containsKey("operation")) reject("CONTRACT_STATE")
                if (operation == "staffResolution" && (d["state"] == "pending" ||
                    (d["state"] == "cancelled" && d["operation"] != expected["staffOperation"]))) reject("CONTRACT_STATE")
            }
            if (operation == "history") for (v in arrayValue(d["items"])) {
                val row = objectValue(v)
                if (row["transactionId"] != expected["recordId"]) reject("CONTRACT_IDENTITY")
                if (if (row["kind"] == "transaction_recorded") row["id"] != "transaction:" + row["transactionId"] || row["amountRwf"] != null || row["memberId"] != null
                    else !(row["id"] as String).startsWith("ledger:") || row["amountRwf"] == null || row["amountRwf"] == 0L || row["memberId"] == null) reject("CONTRACT_STATE")
            }
        }
    }
    fun decode(operation: String, status: Int, contentType: String?, text: String, expected: Map<String, Any?> = emptyMap()): Map<String, Any?> {
        if (!WireMediaType.isUtf8(contentType)) reject("CONTRACT_CONTENT_TYPE")
        if (status != 200 && status !in 400..599) reject("CONTRACT_HTTP_STATUS")
        val r = StrictJson.parse(text) as? Map<*, *> ?: reject("CONTRACT_VERSION")
        if (r["contractVersion"] != version) reject("CONTRACT_VERSION")
        validate(if (status == 200) "$operation.response" else "error", r)
        val result = objectValue(r)
        if (status == 200) semantics(operation, result, expected)
        return result
    }
    fun query(operation: String, raw: String): Map<String, Any?> {
        val value = StrictQuery.parse(raw)
        try { validate("$operation.query", value) }
        catch (_: ContractViolation) { reject("CONTRACT_QUERY") }
        if (((value["q"] as? String)?.length ?: 0) > 80) reject("CONTRACT_QUERY")
        return value
    }
    fun route(method: String, path: String): Pair<String, String?> {
        for (entry in routes) {
            if (entry[0] != method) continue
            val match = Regex(entry[1]).matchEntire(path.substringBefore('?')) ?: continue
            return entry[2] to if (match.groups.size > 1) match.groups[1]?.value else null
        }
        reject("CONTRACT_OPERATION")
    }
}

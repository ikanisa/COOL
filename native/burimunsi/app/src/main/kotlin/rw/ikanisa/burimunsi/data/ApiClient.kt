package rw.ikanisa.burimunsi.data

import rw.ikanisa.wire.BuriMunsiSchemas
import rw.ikanisa.wire.StrictJson
import rw.ikanisa.wire.ContractViolation
import rw.ikanisa.wire.objectValue
import java.util.UUID
import org.json.JSONObject
import org.json.JSONArray
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import rw.ikanisa.burimunsi.core.ContractFailure
import rw.ikanisa.burimunsi.core.Values
import java.net.HttpURLConnection
import java.net.URI
import rw.ikanisa.wire.ResponseTransport
import rw.ikanisa.wire.WireMediaType

class ApiFailure(val code: String, val status: Int = 0, val uncertain: Boolean = false) : Exception(code)

/** Supplies an already authenticated managed access token, never a PIN, refresh
 * token or service key. The installed identity broker owns its lifecycle. */
fun interface ManagedSessionTokenProvider { fun currentAccessToken(): String? }

/** Optional application-level integration with the genuine managed-login host.
 * No token is persisted or refreshed by this interface. */
interface ManagedSessionHost {
    val managedSessionTokenProvider: ManagedSessionTokenProvider
    fun signOutManagedSession() {}
}

/** Fixed HTTPS origin, redirects denied, bounded bodies, no token or payload logs. */
class ApiClient private constructor(origin: String, val installationId: String,
    private val deviceToken: () -> String, private val managedSession: ManagedSessionTokenProvider?,
    apiPathPrefix: String) {
    constructor(origin: String, installationId: String, deviceToken: () -> String) : this(origin,installationId,deviceToken,null,"")
    constructor(origin: String, installationId: String, apiPathPrefix: String,
        deviceToken: () -> String) : this(origin,installationId,deviceToken,null,apiPathPrefix)
    constructor(origin: String, installationId: String, managedSession: ManagedSessionTokenProvider,
        deviceToken: () -> String) : this(origin,installationId,deviceToken,managedSession,"")
    constructor(origin: String, installationId: String, managedSession: ManagedSessionTokenProvider,
        apiPathPrefix: String, deviceToken: () -> String) : this(origin,installationId,deviceToken,managedSession,apiPathPrefix)
    private val origin = Values.apiOrigin(origin)
    // The shared Collect Edge function is the only additional transport mount.
    // It is configuration, never an alternate logical route or user-controlled URL.
    private val apiPathPrefix = apiPathPrefix.also {
        require(it.isEmpty() || it == "/functions/v1/collect-api") { "Invalid API path prefix" }
    }
    fun call(method: String, path: String, token: String? = null, body: JSONObject? = null, csv: Boolean = false, recoveryOrigin: String? = null, contractContext: Map<String, Any?> = emptyMap()): String {
        require(path.startsWith("/v1/burimunsi/") && !path.contains("\\") && !path.contains("#"))
        val logicalPath=path.substringBefore('?')
        require(!logicalPath.contains('%') && logicalPath.split('/').none { it == "." || it == ".." })
        if(recoveryOrigin!=null){
            require(method=="GET"&&body==null&&!csv&&token!=null&&Regex("[a-f0-9]{64}").matches(token))
            require(Regex("[a-f0-9]{64}").matches(recoveryOrigin))
            require(Regex("/v1/burimunsi/operations/[a-fA-F0-9-]{36}/recovery").matches(path))
            Values.requestId(path.removePrefix("/v1/burimunsi/operations/").removeSuffix("/recovery"))
        }
        val target=origin.resolve(apiPathPrefix+path)
        require(target.scheme==origin.scheme&&target.host==origin.host&&target.port==origin.port&&
            target.rawPath==apiPathPrefix+logicalPath)
        var connection: HttpURLConnection?=null
        var sent=false
        var receivedStatus=0
        try {
            val contract=BuriMunsiSchemas.contract
            val correlation=UUID.randomUUID().toString()
            val generation=contractContext["generation"] as? String ?: "0"
            if(contractContext["groupId"] !is String)throw ContractViolation("CONTRACT_CONTEXT")
            val route=if(csv)null else contract.route(method,path.removePrefix("/v1/burimunsi"))
            contract.query(if(csv)"csv" else route!!.first, path.substringAfter('?', ""))
            val requestData=StrictJson.parse(body?.toString() ?: "null")
            if(route!=null)contract.validate(route.first+".request",requestData)
            if(csv)require(method=="GET"&&body==null&&Regex("/v1/burimunsi/members/[A-Za-z0-9_-]+/ledger\\.csv").matches(path))
            val b=requestData as? Map<*, *>
            val expected=contractContext + mapOf("installationId" to installationId,"generation" to generation,
                "requestId" to correlation,"recordId" to route?.second,"now" to System.currentTimeMillis()) +
                (b?.get("phone")?.let{mapOf("phone" to it)} ?: emptyMap()) +
                (b?.get("memberId")?.let{mapOf("memberId" to it)} ?: emptyMap()) +
                (b?.get("id")?.let{mapOf("staffId" to it)} ?: emptyMap()) +
                (b?.get("installationId")?.let{mapOf("replacementInstallationId" to it)} ?: emptyMap()) +
                (recoveryOrigin?.let{mapOf("originDigest" to it)} ?: emptyMap())
            // Resolve before opening a socket. A missing/broken managed session
            // must not send a PIN-only fallback request in canonical mode.
            val managedToken=if(managedSession==null)null else {
                val value=try{managedSession.currentAccessToken()}catch(_:Exception){null}
                if(value==null||value.length !in 20..8192||!Regex("""[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+""").matches(value))
                    throw ApiFailure("managed_session_required",401,false)
                value
            }
            connection=target.toURL().openConnection() as HttpURLConnection
            connection.requestMethod=method
            connection.instanceFollowRedirects=false
            connection.connectTimeout=15_000
            connection.readTimeout=20_000
            connection.useCaches=false
            connection.setRequestProperty("Accept",if(csv)"text/csv" else "application/json")
            connection.setRequestProperty("Accept-Encoding","identity")
            connection.setRequestProperty("X-BuriMunsi-Installation",installationId)
            connection.setRequestProperty("X-BuriMunsi-Contract",BuriMunsiSchemas.VERSION)
            connection.setRequestProperty("X-BuriMunsi-Request",correlation)
            connection.setRequestProperty("X-BuriMunsi-Generation",generation)
            if(managedToken!=null)connection.setRequestProperty("X-BuriMunsi-Collect-Session",managedToken)
            if(recoveryOrigin!=null)connection.setRequestProperty("X-BuriMunsi-Operation-Origin",recoveryOrigin)
            if(token!=null)connection.setRequestProperty("Authorization","Bearer $token")
            else connection.setRequestProperty("X-BuriMunsi-Device",deviceToken())
            if(body!=null){
                val bytes=body.toString().toByteArray(Charsets.UTF_8);require(bytes.size<=8192)
                connection.doOutput=true;connection.setRequestProperty("Content-Type","application/json; charset=utf-8")
                connection.setFixedLengthStreamingMode(bytes.size)
                // Mark uncertain before first write: a failing close may follow server commit.
                sent=true;connection.outputStream.use{it.write(bytes)}
            }
            val status=connection.responseCode;receivedStatus=status
            val metadata=ResponseTransport.metadata(connection.headerFields, 2_000_000)
            val contentType=metadata.contentType.orEmpty()
            val stream=if(status in 200..299)connection.inputStream else connection.errorStream
            val activeConnection=connection
            val bytes=if(stream==null) byteArrayOf() else ResponseTransport.read(stream,2_000_000,metadata.contentLength,
                beforeRead={remainingMillis->activeConnection.readTimeout=remainingMillis})
            if(stream==null && metadata.contentLength!=null && metadata.contentLength!=0L)throw ContractViolation("CONTRACT_RESPONSE_TRUNCATED")
            val text=try{Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()}
                catch(_:Exception){throw ApiFailure("invalid_api_response",status,sent)}
            val mediaType=contentType.substringBefore(';').trim().lowercase()
            if(csv&&status==200&&WireMediaType.isUtf8(contentType,"text/csv")&&connection.getHeaderField("X-BuriMunsi-Contract")==BuriMunsiSchemas.VERSION)return text
            if(mediaType!="application/json")throw ApiFailure("invalid_api_response",status,sent)
            if(!csv)contract.decode(route!!.first,status,contentType,text,expected)
            else if(status in 200..299)throw ContractViolation("CONTRACT_CONTENT_TYPE")
            val response=try{JSONObject(text)}catch(_:Exception){throw ApiFailure("invalid_api_response",status,sent)}
            val success=if(response.has("ok"))response.get("ok") else null
            if(success !is Boolean)throw ApiFailure("invalid_api_response",status,sent)
            if(status !in 200..299){
                // A malformed rejection cannot settle a dispatched financial command.
                val error=response.optJSONObject("error")
                if(success||error==null)throw ApiFailure("invalid_api_response",status,sent)
                val code=if(error.has("code"))error.get("code") else null
                if(code !is String||!Regex("[a-z0-9_]{1,80}").matches(code))throw ApiFailure("invalid_api_response",status,sent)
                // Redirect/informational, timeout, early-retry and throttling replies
                // do not prove that an already-dispatched mutation was rolled back.
                val ambiguous=status !in 400..499||status in setOf(408,425,429)
                throw ApiFailure(code,status,sent&&ambiguous)
            }
            if(!success||!response.has("data")||response.isNull("data"))throw ApiFailure("invalid_api_response",status,sent)
            val data=response.get("data")
            if(data !is JSONObject&&data !is JSONArray)throw ApiFailure("invalid_api_response",status,sent)
            return data.toString()
        }catch(e:ApiFailure){throw e}
        catch(e:ContractViolation){throw ApiFailure(if(e.code=="CONTRACT_RESPONSE_SIZE")"response_too_large" else e.code.lowercase(),receivedStatus,sent)}
        catch(e:ContractFailure){throw ApiFailure(e.code,0,false)}
        catch(_:Exception){throw ApiFailure("connection_unavailable",0,sent)}
        finally{connection?.disconnect()}
    }
    internal fun validateCached(path: String, payload: String, context: Map<String, Any?>): String =
        validateCachedPayload(installationId,path,payload,context)
}

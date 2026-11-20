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
import rw.ikanisa.burimunsi.core.SmartOnboardingLimits
import rw.ikanisa.burimunsi.core.Values
import java.net.HttpURLConnection
import java.net.URI
import rw.ikanisa.wire.ResponseTransport
import rw.ikanisa.wire.WireMediaType

open class ApiFailure(val code: String, val status: Int = 0, val uncertain: Boolean = false) : Exception(code)
/** Server verified this exact in-flight reservation but could not settle its upload. */
internal class ObservationUploadUnresolved(val requestId:String):ApiFailure("observation_upload_unresolved",503,true)

/** The proof is an assertion about this response only, never an upload ACK. */
internal object ObservationUnresolvedProof {
    fun matches(headers:Map<out String?,List<String>?>,requestId:String,correlation:String):Boolean {
        if(!runCatching{Values.requestId(requestId)==requestId&&Values.requestId(correlation)==correlation}.getOrDefault(false))return false
        fun single(name:String):String? {
            val entries=headers.entries.filter{it.key?.equals(name,ignoreCase=true)==true}
            if(entries.size!=1||entries.single().value?.size!=1)return null
            val value=entries.single().value!!.single()
            if(value.length>128||value.any{it.isISOControl()&&it!='\t'})return null
            return value.trim(' ','\t')
        }
        return single("X-BuriMunsi-Observation-Unresolved")=="v1"&&
            single("X-BuriMunsi-Observation-Request-Id")==requestId&&
            single("X-BuriMunsi-Correlation-Id")==correlation
    }
}

/** Supplies an already authenticated managed access token, never a PIN, refresh
 * token or service key. The installed identity broker owns its lifecycle. */
class ManagedRequestAccess(val token:String,val collectionId:String){override fun toString()="ManagedRequestAccess(redacted)"}
fun interface ManagedSessionTokenProvider {
    fun currentAccessToken():String?
    /** Production broker overrides with one atomic authenticated observation. */
    fun currentAccessContext():ManagedRequestAccess?=null
    fun currentCollectionId():String?=null
}

/** Optional application-level integration with the genuine managed-login host.
 * No token is persisted or refreshed by this interface. */
interface ManagedSessionHost {
    val managedSessionTokenProvider: ManagedSessionTokenProvider
    fun signOutManagedSession() {}
}

/** The public project key is only sent to the selected Supabase API origin. */
internal fun validatedSupabasePublicKey(origin:URI,prefix:String,key:String):String {
    if(key.isEmpty())return ""
    require(Regex("sb_publishable_[A-Za-z0-9_-]{10,300}").matches(key)) { "Invalid public project key" }
    require(origin.scheme=="https"&&origin.host.equals("rrlduytparvsjfmegalh.supabase.co",ignoreCase=true)&&
        (origin.port==-1||origin.port==443)&&prefix=="/functions/v1/collect-api") { "Public project key requires the selected Supabase API" }
    return key
}

/** Fixed HTTPS origin, redirects denied, bounded bodies, no token or payload logs. */
class ApiClient private constructor(origin: String, val installationId: String,
    private val deviceToken: () -> String, private val managedSession: ManagedSessionTokenProvider?,
    apiPathPrefix: String,private val phonePinProfile:String?=null,publicKey:String="") {
    companion object {
        fun phonePin(origin:String,installationId:String,profile:String,apiPathPrefix:String,publicKey:String="",deviceToken:()->String):ApiClient {
            require(profile in setOf("staff","internal_receiver"))
            Values.requestId(installationId)
            return ApiClient(origin,installationId,deviceToken,null,apiPathPrefix,profile,publicKey)
        }
    }
    val resolvesLoginScope:Boolean get()=phonePinProfile!=null
    val installationProfile:String? get()=phonePinProfile
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
    private val publicKey=validatedSupabasePublicKey(this.origin,this.apiPathPrefix,publicKey).also {
        if(phonePinProfile!=null&&this.origin.host.equals("rrlduytparvsjfmegalh.supabase.co",ignoreCase=true))
            require(it.isNotEmpty()) { "Supabase public project key required" }
    }
    fun call(method: String, path: String, token: String? = null, body: JSONObject? = null, csv: Boolean = false, recoveryOrigin: String? = null, contractContext: Map<String, Any?> = emptyMap()): String {
        require(path.startsWith("/v1/burimunsi/") && !path.contains("\\") && !path.contains("#"))
        val logicalPath=path.substringBefore('?')
        require(!logicalPath.contains('%') && logicalPath.split('/').none { it == "." || it == ".." })
        val requestLimit=if(method=="POST"&&logicalPath=="/v1/burimunsi/members/import/preview") 6_991_532
            else if(method=="POST"&&logicalPath=="/v1/burimunsi/members/import") SmartOnboardingLimits.MAX_BATCH_BYTES else 8192
        if(requestLimit>8192)require(token!=null&&Regex("[a-f0-9]{64}").matches(token))
        if(recoveryOrigin!=null){
            val read=method=="GET"&&body==null&&path.endsWith("/recovery")
            val resolution=method=="POST"&&body!=null&&path.endsWith("/staff-resolution")
            require((read||resolution)&&!csv&&token!=null&&Regex("[a-f0-9]{64}").matches(token))
            require(Regex("[a-f0-9]{64}").matches(recoveryOrigin))
            require(Regex("/v1/burimunsi/operations/[a-f0-9-]{36}/(recovery|staff-resolution)").matches(path))
            Values.requestId(path.removePrefix("/v1/burimunsi/operations/").substringBefore('/'))
        }
        val handoffFingerprint=contractContext["handoffFingerprint"] as? String
        if(handoffFingerprint!=null||Regex("/v1/burimunsi/gateway/replacements/[a-f0-9-]{36}/outcome").matches(path)){
            require(handoffFingerprint!=null)
            require(phonePinProfile=="internal_receiver"&&method=="GET"&&body==null&&!csv&&token!=null)
            require(Regex("[a-f0-9]{64}").matches(handoffFingerprint)&&Regex("[a-f0-9]{64}").matches(token))
            require(Regex("/v1/burimunsi/gateway/replacements/[a-f0-9-]{36}/outcome").matches(path))
            Values.requestId(path.removePrefix("/v1/burimunsi/gateway/replacements/").removeSuffix("/outcome"))
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
            val bootstrap=phonePinProfile!=null&&method=="POST"&&logicalPath=="/v1/burimunsi/session/login"
            val group=if(bootstrap)null else (contractContext["groupId"] as? String ?:throw ContractViolation("CONTRACT_CONTEXT"))
            if(group!=null)Values.id(group)
            val route=if(csv)null else contract.route(method,path.removePrefix("/v1/burimunsi"))
            contract.query(if(csv)"csv" else route!!.first, path.substringAfter('?', ""))
            val requestData=StrictJson.parse(body?.toString() ?: "null",requestLimit)
            if(route!=null)contract.validate(route.first+".request",requestData)
            if(csv)require(method=="GET"&&body==null&&Regex("/v1/burimunsi/members/[A-Za-z0-9_-]+/ledger\\.csv").matches(path))
            val b=requestData as? Map<*, *>
            val expected=(if(bootstrap)contractContext-"groupId" else contractContext) + mapOf("installationId" to installationId,"generation" to generation,
                "requestId" to correlation,"recordId" to route?.second,"now" to System.currentTimeMillis()) +
                (b?.get("phone")?.let{mapOf("phone" to it)} ?: emptyMap()) +
                (b?.get("memberId")?.let{mapOf("memberId" to it)} ?: emptyMap()) +
                (b?.get("id")?.let{mapOf("staffId" to it)} ?: emptyMap()) +
                (b?.get("requestId")?.let{mapOf("commandRequestId" to it)} ?: emptyMap()) +
                (b?.get("sourceIds")?.let{mapOf("sourceIds" to it)} ?: emptyMap()) +
                (b?.get("sourceKey")?.let{mapOf("sourceKey" to it)} ?: emptyMap()) +
                ((b?.get("items") as? List<*>)?.map{(it as? Map<*,*>)?.get("sourceKey")}?.let{mapOf("sourceKeys" to it)} ?: emptyMap()) +
                ((b?.get("rows") as? List<*>)?.map{(it as? Map<*,*>)?.get("row")}?.let{mapOf("importRows" to it)} ?: emptyMap()) +
                (b?.get("enabled")?.let{mapOf("consentEnabled" to it)} ?: emptyMap()) +
                (b?.get("generation")?.let{mapOf("consentGeneration" to it)} ?: emptyMap()) +
                (b?.get("displayHintsVersion")?.let{mapOf("displayHintsVersion" to it)} ?: emptyMap()) +
                ((b?.get("rawBody") as? String)?.let{mapOf("observationBodySha256" to Values.sha256(it))} ?: emptyMap()) +
                (b?.get("operation")?.let{mapOf("staffOperation" to it)} ?: emptyMap()) +
                (recoveryOrigin?.let{mapOf("originDigest" to it)} ?: emptyMap())
            // Resolve before opening a socket. A missing/broken managed session
            // must not send a PIN-only fallback request in canonical mode.
            val managedToken=if(managedSession==null)null else {
                val access=try{managedSession.currentAccessContext()}catch(_:Exception){null}
                val value=access?.token
                if(value==null||value.length !in 20..8192||!Regex("""[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+""").matches(value))
                    throw ApiFailure("managed_session_required",401,false)
                if(access.collectionId!=group)throw ApiFailure("managed_scope_changed",409,false)
                value
            }
            val device=deviceToken()
            if(!Regex("[a-f0-9]{64}").matches(device))throw ApiFailure("managed_setup_required",403,false)
            connection=target.toURL().openConnection() as HttpURLConnection
            connection.requestMethod=method
            connection.instanceFollowRedirects=false
            connection.connectTimeout=15_000
            connection.readTimeout=20_000
            connection.useCaches=false
            connection.setRequestProperty("Accept",if(csv)"text/csv" else "application/json")
            connection.setRequestProperty("Accept-Encoding","identity")
            if(publicKey.isNotEmpty())connection.setRequestProperty("apikey",publicKey)
            connection.setRequestProperty("X-BuriMunsi-Installation",installationId)
            connection.setRequestProperty("X-BuriMunsi-Contract",BuriMunsiSchemas.VERSION)
            connection.setRequestProperty("X-BuriMunsi-Request",correlation)
            connection.setRequestProperty("X-BuriMunsi-Generation",generation)
            // Business intent assertion only. Server independently resolves the
            // current installation grant and must refuse a different scope.
            if(group!=null)connection.setRequestProperty("X-BuriMunsi-Group",group)
            connection.setRequestProperty("X-BuriMunsi-Device",device)
            if(phonePinProfile!=null){
                connection.setRequestProperty("X-BuriMunsi-Auth","phone_pin")
                connection.setRequestProperty("X-BuriMunsi-Profile",phonePinProfile)
            }
            if(managedToken!=null)connection.setRequestProperty("X-BuriMunsi-Collect-Session",managedToken)
            if(recoveryOrigin!=null)connection.setRequestProperty("X-BuriMunsi-Operation-Origin",recoveryOrigin)
            if(handoffFingerprint!=null)connection.setRequestProperty("X-BuriMunsi-Handoff-Fingerprint",handoffFingerprint)
            if(token!=null)connection.setRequestProperty("Authorization","Bearer $token")
            if(body!=null){
                val bytes=body.toString().toByteArray(Charsets.UTF_8);require(bytes.size<=requestLimit)
                connection.doOutput=true;connection.setRequestProperty("Content-Type","application/json; charset=utf-8")
                connection.setFixedLengthStreamingMode(bytes.size)
                // Mark uncertain before first write: a failing close may follow server commit.
                sent=true;connection.outputStream.use{it.write(bytes)}
            }
            val status=connection.responseCode;receivedStatus=status
            val responseHeaders=connection.headerFields
            val metadata=ResponseTransport.metadata(responseHeaders, 2_000_000)
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
                val observationId=b?.get("requestId") as? String
                if(sent&&method=="POST"&&path=="/v1/burimunsi/sms/observations"&&status==503&&
                    code=="observation_upload_unresolved"&&observationId!=null&&
                    ObservationUnresolvedProof.matches(responseHeaders,observationId,correlation))
                    throw ObservationUploadUnresolved(observationId)
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

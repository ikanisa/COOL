package rw.ikanisa.burimunsi.data

import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.wire.StrictJson
import rw.ikanisa.wire.ResponseTransport
import rw.ikanisa.wire.WireMediaType
import rw.ikanisa.wire.objectValue
import org.json.JSONObject
import java.net.URI
import java.net.URL
import java.time.Instant
import java.util.Base64
import java.util.Locale
import javax.net.ssl.HttpsURLConnection

/** Native transport to the existing Collect Admin BFF, including its real
 * cookie/CSRF/GoTrue policies. TLS trust is the Android default. No WebView,
 * custom trust manager, redirect, refresh token or shared cookie jar is used.
 */
class CollectAdminTransport(adminOrigin:String,supabaseOrigin:String,
    private val clock:()->Long=System::currentTimeMillis,
    private val connect:(URL)->HttpsURLConnection={it.openConnection() as HttpsURLConnection}):CollectManagedTransport {
    private fun origin(value:String):URI {
        val parsed=Values.apiOrigin(value)
        if(parsed.toString()!=value||parsed.port!=-1||!parsed.host.contains('.'))throw ManagedCollectFailure("configuration_required")
        return parsed
    }
    private val admin=origin(adminOrigin)
    private val issuer=origin(supabaseOrigin).toString()+"/auth/v1"
    private fun invalid():Nothing=throw ManagedCollectFailure("invalid_managed_response")
    private fun Map<String,Any?>.string(key:String)=this[key] as? String ?: invalid()
    private fun Map<String,Any?>.integer(key:String)=this[key] as? Long ?: invalid()
    private fun exactId(value:String):String=try{Values.requestId(value).also{if(it!=value)invalid()}}catch(_:ContractFailure){invalid()}
    private fun exact(keys:Set<String>,expected:Set<String>){if(keys!=expected)invalid()}
    private class Reply(val data:Map<String,Any?>,val headers:Map<out String?,List<String>?>)
    private fun call(path:String,body:JSONObject,session:CollectBffSession?=null,device:String?=null):Reply {
        require(path in setOf("/api/admin/auth/login","/api/admin/auth/logout","/api/admin/burimunsi/access"))
        val target=admin.resolve(path);if(target.origin()!=admin.origin()||target.rawPath!=path)invalid()
        var connection:HttpsURLConnection?=null
        try {
            val bytes=body.toString().toByteArray(Charsets.UTF_8);if(bytes.size>8192)invalid()
            connection=connect(target.toURL())
            connection.requestMethod="POST";connection.instanceFollowRedirects=false
            connection.connectTimeout=15_000;connection.readTimeout=20_000;connection.useCaches=false
            connection.setRequestProperty("Origin",admin.toString())
            connection.setRequestProperty("X-Collect-Requested-With","collect-admin")
            connection.setRequestProperty("Accept","application/json")
            connection.setRequestProperty("Accept-Encoding","identity")
            connection.setRequestProperty("Content-Type","application/json; charset=utf-8")
            if(session!=null){connection.setRequestProperty("Cookie",session.cookie);connection.setRequestProperty("X-Collect-CSRF",session.csrf)}
            if(device!=null)connection.setRequestProperty("X-BuriMunsi-Device",device)
            connection.doOutput=true;connection.setFixedLengthStreamingMode(bytes.size)
            try{connection.outputStream.use{it.write(bytes)}}finally{bytes.fill(0)}
            val status=connection.responseCode
            if(status in 300..399)throw ManagedCollectFailure("managed_redirect_denied",status)
            val metadata=ResponseTransport.metadata(connection.headerFields,65_536)
            if(!WireMediaType.isUtf8(metadata.contentType))invalid()
            val stream=if(status in 200..299)connection.inputStream else connection.errorStream
            if(stream==null)invalid()
            val active=connection
            val payload=ResponseTransport.read(stream,65_536,metadata.contentLength,beforeRead={active.readTimeout=it})
            val data=try{objectValue(StrictJson.parse(payload,65_536))}finally{payload.fill(0)}
            if(status!=200){
                val error=data["error"] as? Map<*,*>;val code=error?.get("code") as? String
                throw ManagedCollectFailure(if(code!=null&&Regex("[a-z0-9_]{1,80}").matches(code))code else "managed_sign_in_unavailable",status)
            }
            val cache=connection.headerFields.entries.filter{it.key?.equals("Cache-Control",true)==true}.flatMap{it.value.orEmpty()}
            if(cache.size!=1||cache.single().split(',').none{it.trim().equals("no-store",true)})invalid()
            return Reply(data,connection.headerFields)
        }catch(e:ManagedCollectFailure){throw e}
        catch(_:rw.ikanisa.wire.ContractViolation){invalid()}
        catch(_:Exception){throw ManagedCollectFailure("managed_connection_unavailable")}
        finally{connection?.disconnect()}
    }
    private fun URI.origin()=scheme+"://"+rawAuthority
    override fun signIn(email:String,password:String):CollectBffSession {
        val normalized=email.trim().lowercase(Locale.ROOT)
        if(normalized.length !in 3..254||!Regex("[^\\s@]+@[^\\s@]+\\.[^\\s@]+").matches(normalized)||
            password.isEmpty()||password.length>128||password.any{it.code<32||it.code==127})throw ManagedCollectFailure("invalid_credentials",400)
        val reply=call("/api/admin/auth/login",JSONObject().put("email",normalized).put("password",password))
        exact(reply.data.keys,setOf("user","expiresAt","csrfToken"))
        val user=objectValue(reply.data["user"])
        if(user.string("email")!=normalized||user.string("role") !in setOf("owner","admin","staff"))invalid()
        val principal=exactId(user.string("principalId"));val public=exactId(user.string("sessionId"))
        val expiry=try{Instant.parse(reply.data.string("expiresAt")).toEpochMilli()}catch(_:Exception){invalid()}
        if(expiry<=clock()+30_000||expiry>clock()+28_801_000)invalid()
        val csrf=reply.data.string("csrfToken");if(!Regex("[a-f0-9]{64}").matches(csrf))invalid()
        val cookies=reply.headers.entries.filter{it.key?.equals("Set-Cookie",true)==true}.flatMap{it.value.orEmpty()}
        if(cookies.size!=1||cookies.single().length>512)invalid()
        val parts=cookies.single().split(';').map{it.trim()}
        val cookie=parts.first();if(!Regex("__Host-collect_admin=[a-f0-9]{64}").matches(cookie))invalid()
        val attributes=parts.drop(1).map{it.substringBefore('=').lowercase(Locale.ROOT) to it.substringAfter('=',"")}
        if(attributes.map{it.first}.distinct().size!=attributes.size)invalid()
        val attrs=attributes.toMap()
        if(attrs.keys!=setOf("path","httponly","samesite","max-age","secure")||attrs["path"]!="/"||
            attrs["httponly"]!=""||attrs["secure"]!=""||attrs["samesite"]!="Strict"||
            attrs["max-age"]?.toLongOrNull() !in 1L..28_800L)invalid()
        return CollectBffSession(cookie,csrf,principal,public,expiry)
    }
    override fun access(session:CollectBffSession,installationId:String,deviceToken:String):CollectManagedAccess {
        exactId(installationId);if(!Regex("[a-f0-9]{64}").matches(deviceToken))throw ManagedCollectFailure("managed_setup_required",403)
        val data=call("/api/admin/burimunsi/access",JSONObject().put("installationId",installationId),session,deviceToken).data
        exact(data.keys,setOf("contractVersion","accessToken","expiresAt","authUserId","principalUserId","principalSessionId","operatorId",
            "collectionId","installationId","profile","accountVersion","credentialVersion","grantVersion","scopeVersion"))
        if(data.string("contractVersion")!="burimunsi.collect-session.v1"||data.string("installationId")!=installationId||data.string("principalUserId")!=session.principalId)invalid()
        val token=data.string("accessToken");if(token.length !in 20..8192||!Regex("[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+").matches(token))invalid()
        // Claim decoding binds the HTTPS response to its expected managed
        // identity. GoTrue, not this parser, verifies the JWT on the server.
        val claims=try{objectValue(StrictJson.parse(Base64.getUrlDecoder().decode(token.split('.')[1]),16_384))}catch(_:Exception){invalid()}
        val auth=exactId(data.string("authUserId"));val sid=exactId(data.string("principalSessionId"));val operator=exactId(data.string("operatorId"))
        val audience=claims["aud"]
        if(claims["sub"]!=auth||claims["session_id"]!=sid||claims["role"]!="authenticated"||claims["iss"]!=issuer||
            !(audience=="authenticated"||audience is List<*>&&audience.contains("authenticated"))||claims["is_anonymous"]==true)invalid()
        val expiry=data.integer("expiresAt");val jwtExpiry=claims.integer("exp")
        if(jwtExpiry !in 1L..9_007_199_254_740L||expiry>jwtExpiry*1000||expiry<=clock()+30_000||expiry>session.expiresAt)invalid()
        val profile=data.string("profile");if(profile !in setOf("staff","internal_receiver"))invalid()
        val versions=listOf("accountVersion","credentialVersion","grantVersion","scopeVersion").map{data.integer(it)}
        if(versions.any{it<1})invalid()
        return CollectManagedAccess(token,expiry,auth,session.principalId,sid,operator,Values.id(data.string("collectionId")),installationId,
            profile,versions[0],versions[1],versions[2],versions[3])
    }
    override fun signOut(session:CollectBffSession){val reply=call("/api/admin/auth/logout",JSONObject(),session);if(reply.data!=mapOf("ok" to true))invalid()}
}

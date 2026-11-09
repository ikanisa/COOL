package rw.ikanisa.burimunsi.managedlogintests

// Actual native HTTP/JSON implementation, explicit in-memory HTTPS connections.
// This does not prove Android TLS, GoTrue, SMTP, a real account or a live device.
import rw.ikanisa.burimunsi.data.CollectAdminTransport
import rw.ikanisa.burimunsi.core.*
import java.net.URL
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.security.cert.Certificate
import java.util.Base64
import javax.net.ssl.HttpsURLConnection

private const val NOW=1794045600000L
private const val ADMIN="https://admin.fixture.invalid"
private const val SUPABASE="https://supabase.fixture.invalid"
private const val PRINCIPAL="10000000-0000-4000-8000-000000000001"
private const val AUTH="10000000-0000-4000-8000-000000000002"
private const val SID="10000000-0000-4000-8000-000000000003"
private const val INSTALL="10000000-0000-4000-8000-000000000004"
private const val OPERATOR="10000000-0000-4000-8000-000000000005"
private val cookie="__Host-collect_admin="+"b".repeat(64)
private val csrf="c".repeat(64)
private val device="d".repeat(64)
private fun encoded(s:String)=Base64.getUrlEncoder().withoutPadding().encodeToString(s.toByteArray())
private fun token(issuer:String=SUPABASE+"/auth/v1",subject:String=AUTH,session:String=SID,role:String="authenticated")=
    encoded("""{"alg":"RS256"}""")+"."+encoded("""{"iss":"$issuer","sub":"$subject","session_id":"$session","role":"$role","aud":"authenticated","exp":${NOW/1000+3600}}""")+".synthetic-signature"
private fun access(jwt:String=token(),install:String=INSTALL,principal:String=PRINCIPAL,version:String="1")="""{"contractVersion":"burimunsi.collect-session.v1","accessToken":"$jwt","expiresAt":${NOW+3_000_000},"authUserId":"$AUTH","principalUserId":"$principal","principalSessionId":"$SID","operatorId":"$OPERATOR","collectionId":"group","installationId":"$install","profile":"staff","accountVersion":$version,"credentialVersion":1,"grantVersion":1,"scopeVersion":1}"""
private val login="""{"user":{"email":"operator@example.invalid","role":"staff","principalId":"$PRINCIPAL","sessionId":"$SID"},"expiresAt":"${java.time.Instant.ofEpochMilli(NOW+3_000_000)}","csrfToken":"$csrf"}"""
private class Reply(val text:String,val status:Int=200,val extra:Map<String,List<String>> = emptyMap())
private class Connection(url:URL,private val reply:Reply):HttpsURLConnection(url){
    val sent=ByteArrayOutputStream();var disconnected=false
    override fun connect(){}
    override fun disconnect(){disconnected=true}
    override fun usingProxy()=false
    override fun getOutputStream()=sent
    override fun getInputStream()=ByteArrayInputStream(reply.text.toByteArray())
    override fun getErrorStream()=inputStream
    override fun getResponseCode()=reply.status
    override fun getHeaderFields():Map<String,List<String>> = mapOf("Content-Type" to listOf("application/json"),
        "Content-Length" to listOf(reply.text.toByteArray().size.toString()),"Cache-Control" to listOf("no-store"))+reply.extra
    override fun getCipherSuite()="fixture-only"
    override fun getLocalCertificates():Array<Certificate>?=null
    override fun getServerCertificates():Array<Certificate> = emptyArray()
}
private class Fixture(vararg replies:Reply){
    val pending=ArrayDeque(replies.toList());val connections=mutableListOf<Connection>()
    val client=CollectAdminTransport(ADMIN,SUPABASE,{NOW}){url->
        check(url.protocol=="https"&&url.host=="admin.fixture.invalid");check(pending.isNotEmpty())
        Connection(url,pending.removeFirst()).also(connections::add)
    }
}
private fun bff()=CollectBffSession(cookie,csrf,PRINCIPAL,SID,NOW+3_000_000)
private fun loginReply(header:String="$cookie; Path=/; HttpOnly; SameSite=Strict; Max-Age=3000; Secure")=Reply(login,extra=mapOf("Set-Cookie" to listOf(header)))

fun main(){
    var count=0
    fun ok(name:String,run:()->Unit){run();count++;println("ok $count - $name")}
    fun reject(code:String?=null,run:()->Unit){val error=runCatching(run).exceptionOrNull();check(error is ManagedCollectFailure);if(code!=null)check(error.code==code)}
    ok("real BFF login carries credentials only to the exact configured HTTPS origin"){
        val f=Fixture(loginReply());val s=f.client.signIn(" Operator@Example.Invalid ","test-only-password")
        check(s.cookie==cookie&&s.csrf==csrf&&s.principalId==PRINCIPAL)
        val c=f.connections.single();check(c.url.toString()==ADMIN+"/api/admin/auth/login"&&c.requestMethod=="POST"&&!c.instanceFollowRedirects)
        check(c.getRequestProperty("Origin")==ADMIN&&c.getRequestProperty("X-Collect-Requested-With")=="collect-admin")
        check(!c.requestProperties.containsKey("Cookie")&&c.disconnected)
    }
    ok("access binds real BFF cookie/CSRF and private device proof to the narrow endpoint"){
        val f=Fixture(Reply(access()));val a=f.client.access(bff(),INSTALL,device);check(a.token==token()&&a.principalSessionId==SID)
        val c=f.connections.single();check(c.url.path=="/api/admin/burimunsi/access"&&c.getRequestProperty("Cookie")==cookie)
        check(c.getRequestProperty("X-Collect-CSRF")==csrf&&c.getRequestProperty("X-BuriMunsi-Device")==device)
        check(!c.sent.toString().contains(device)&&c.disconnected)
    }
    for((name,body) in listOf(
        "wrong issuer" to access(token(issuer="https://other.invalid/auth/v1")),
        "wrong JWT user" to access(token(subject=PRINCIPAL)),
        "wrong JWT session" to access(token(session=PRINCIPAL)),
        "service role" to access(token(role="service_role")),
        "different device" to access(install=SID),
        "different principal" to access(principal=AUTH),
        "stringified version" to access(version="\"1\""),
        "duplicate fields" to access().dropLast(1)+",\"scopeVersion\":1}",
        "unknown fields" to access().dropLast(1)+",\"refresh_token\":\"forbidden\"}",
        "zero version" to access(version="0")
    ))ok("managed transport rejects $name"){
        val f=Fixture(Reply(body));reject{f.client.access(bff(),INSTALL,device)};check(f.connections.single().disconnected)
    }
    for(header in listOf("$cookie; Path=/; SameSite=Strict; Max-Age=3000; Secure", "$cookie; Path=/; HttpOnly; SameSite=Lax; Max-Age=3000; Secure",
        "$cookie; Path=/; HttpOnly; SameSite=Strict; Max-Age=3000; Secure; Domain=fixture.invalid",
        "$cookie; Path=/; HttpOnly; SameSite=Strict; Max-Age=0; Secure"))ok("BFF cookie rejects unsafe custody attributes"){
        val f=Fixture(loginReply(header));reject{f.client.signIn("operator@example.invalid","test-only-password")}
    }
    ok("credential redirects are refused without dispatch to their destination"){
        val f=Fixture(Reply("redirect",302, mapOf("Location" to listOf("https://foreign.invalid"))))
        reject("managed_redirect_denied"){f.client.signIn("operator@example.invalid","test-only-password")};check(f.connections.size==1)
    }
    ok("revoked access preserves the real server denial without returning a token"){
        val f=Fixture(Reply("""{"error":{"code":"burimunsi_access_denied","message":"sanitized"}}""",403))
        reject("burimunsi_access_denied"){f.client.access(bff(),INSTALL,device)}
    }
    ok("managed sign-out reuses exact cookie/CSRF and confirms the actual response"){
        val f=Fixture(Reply("""{"ok":true}"""));f.client.signOut(bff());check(f.connections.single().getRequestProperty("X-Collect-CSRF")==csrf)
    }
    ok("missing device provisioning fails before opening a connection"){
        val f=Fixture();reject("managed_setup_required"){f.client.access(bff(),INSTALL,"1234")};check(f.connections.isEmpty())
    }
    println("1..$count")
}

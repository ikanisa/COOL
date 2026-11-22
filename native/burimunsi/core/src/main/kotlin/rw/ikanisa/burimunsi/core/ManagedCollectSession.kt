package rw.ikanisa.burimunsi.core

import java.util.Locale

/** Same existing-account email shape as Collect Admin. No account is created. */
fun normalizeCollectEmail(value:String):String {
    val email=value.trim().lowercase(Locale.ROOT);val parts=email.split('@')
    if(email.length>254||email.any{it.isWhitespace()||it.code<32||it.code==127}||parts.size!=2)
        throw ManagedCollectFailure("invalid_email",400)
    val local=parts[0];val domain=parts[1].split('.')
    if(local.length !in 1..64||local.startsWith('.')||local.endsWith('.')||local.contains("..")||
        !Regex("[a-z0-9.!#$%&'*+/=?^_`{|}~-]+").matches(local)||domain.size<2||domain.any{
            it.length !in 1..63||!Regex("[a-z0-9](?:[a-z0-9-]*[a-z0-9])?").matches(it)})
        throw ManagedCollectFailure("invalid_email",400)
    return email
}

class CollectEmailChallenge(val email:String,val id:String,val expiresAt:Long,val retryAt:Long,val deliveryUnknown:Boolean=false) {
    override fun toString()="CollectEmailChallenge(redacted)"
}
data class CollectEmailCodeState(val challenge:CollectEmailChallenge?=null,val nextRequestAt:Long=0,val verificationUnknown:Boolean=false)

/** Volatile custody only. No refresh token, service key or PIN enters this realm. */
class CollectBffSession(val cookie:String,val csrf:String,val principalId:String,val publicSessionId:String,val expiresAt:Long) {
    override fun toString()="CollectBffSession(redacted)"
}
class CollectManagedAccess(val token:String,val expiresAt:Long,val authUserId:String,val principalId:String,
    val principalSessionId:String,val operatorId:String,val collectionId:String,val installationId:String,val profile:String,
    val accountVersion:Long,val credentialVersion:Long,val grantVersion:Long,val scopeVersion:Long) {
    override fun toString()="CollectManagedAccess(redacted)"
    fun sameIdentity(other:CollectManagedAccess)=authUserId==other.authUserId&&principalId==other.principalId&&
        principalSessionId==other.principalSessionId&&operatorId==other.operatorId&&collectionId==other.collectionId&&
        installationId==other.installationId&&profile==other.profile
}
class ManagedCollectFailure(val code:String,val status:Int=0):Exception(code)
interface CollectManagedTransport {
    fun requestEmailCode(email:String):CollectEmailChallenge
    fun verifyEmailCode(challenge:CollectEmailChallenge,code:String):CollectBffSession
    fun access(session:CollectBffSession,installationId:String,deviceToken:String):CollectManagedAccess
    fun signOut(session:CollectBffSession)
}

/** Serializes real BFF refresh observations; local generations reject responses
 * from before backgrounding or sign-out. Native command journals remain owned by
 * NativeRepository and are never cleared by a managed identity replacement.
 */
class ManagedCollectSession(private val transport:CollectManagedTransport,private val installationId:String,
    private val profile:String,private val deviceToken:()->String,
    private val clock:()->Long=System::currentTimeMillis) {
    private val stateLock=Any();private val ioLock=Any()
    private var generation=0L
    private var session:CollectBffSession?=null
    private var identity:CollectManagedAccess?=null
    private var cached:CollectManagedAccess?=null
    private var challenge:CollectEmailChallenge?=null
    private var nextRequestAt=0L
    private var verificationUnknown=false
    val signedIn:Boolean get()=synchronized(stateLock){session!=null&&identity!=null}
    /** Only successful shared login + current installation approval establishes
     * this scope. It is neither a build setting nor an unauthenticated selector. */
    val currentCollectionId:String? get()=synchronized(stateLock){if(session==null)null else identity?.collectionId}
    val emailCodeState:CollectEmailCodeState get()=synchronized(stateLock){CollectEmailCodeState(challenge,nextRequestAt,verificationUnknown)}
    private fun denied():Nothing=throw ManagedCollectFailure("managed_session_required",401)
    private fun accept(value:CollectManagedAccess,bff:CollectBffSession,previous:CollectManagedAccess?) {
        if(value.installationId!=installationId||!Regex("[A-Za-z0-9][A-Za-z0-9_-]{0,127}").matches(value.collectionId)||value.profile!=profile||
            value.principalId!=bff.principalId||value.expiresAt<=clock()+30_000||value.expiresAt>bff.expiresAt||
            listOf(value.accountVersion,value.credentialVersion,value.grantVersion,value.scopeVersion).any{it<1}||
            previous!=null&&(!value.sameIdentity(previous)||value.accountVersion<previous.accountVersion||
            value.credentialVersion<previous.credentialVersion||value.grantVersion<previous.grantVersion||value.scopeVersion<previous.scopeVersion))denied()
    }
    fun requestEmailCode(email:String)=synchronized(ioLock){
        val normalized=normalizeCollectEmail(email)
        val ticket=synchronized(stateLock){
            if(session!=null)throw ManagedCollectFailure("managed_session_exists",409)
            if(clock()<nextRequestAt)throw ManagedCollectFailure("auth_rate_limited",429)
            // Reserve the cooldown BEFORE IO, including an uncertain delivery.
            // Retrying or changing the address never automatically sends mail.
            nextRequestAt=clock()+60_000;challenge=null;verificationUnknown=false;++generation
        }
        val result=transport.requestEmailCode(normalized)
        if(result.email!=normalized||result.expiresAt<=clock()||result.expiresAt>clock()+300_000||
            result.retryAt>clock()+60_000||!Regex("[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}").matches(result.id))
            throw ManagedCollectFailure("invalid_managed_response")
        synchronized(stateLock){if(ticket!=generation)denied();challenge=result;nextRequestAt=maxOf(nextRequestAt,result.retryAt)}
    }
    fun verifyEmailCode(code:String)=synchronized(ioLock){
        if(!Regex("[0-9]{6}").matches(code))throw ManagedCollectFailure("invalid_email_code",400)
        val (ticket,pending)=synchronized(stateLock){
            if(session!=null)throw ManagedCollectFailure("managed_session_exists",409)
            val current=challenge
            if(current==null||current.expiresAt<=clock()||verificationUnknown)
                throw ManagedCollectFailure(if(verificationUnknown)"managed_sign_in_unconfirmed" else "email_code_required",401)
            verificationUnknown=true;Pair(++generation,current)
        }
        val bff=try{transport.verifyEmailCode(pending,code)}catch(error:Exception){
            // Only a definite invalid-code response permits another manual
            // attempt. A timeout/invalid response may have consumed this code.
            if(error is ManagedCollectFailure&&error.code=="invalid_credentials"&&error.status in listOf(400,401))
                synchronized(stateLock){if(ticket==generation&&challenge===pending)verificationUnknown=false}
            throw error
        }
        synchronized(stateLock){if(ticket==generation){challenge=null;verificationUnknown=false}}
        install(bff,ticket)
    }
    private fun install(bff:CollectBffSession,ticket:Long) {
        var installed=false
        try {
            val value=transport.access(bff,installationId,deviceToken());accept(value,bff,null)
            synchronized(stateLock){if(ticket!=generation)denied();session=bff;identity=value;cached=value;installed=true}
        } finally {
            // A failed/device-denied/interrupted new login is not left as the
            // application's usable login. Exactly one cleanup attempt, no retry.
            if(!installed)try{transport.signOut(bff)}catch(_:Exception){/* Remote revocation is unconfirmed; no success is reported. */}
        }
    }
    fun currentAccess():CollectManagedAccess=synchronized(ioLock){
        val (ticket,bff,prior)=synchronized(stateLock){
            cached?.let{if(it.expiresAt>clock()+45_000)return@synchronized Triple(-1L,null,it)}
            Triple(generation,session,identity)
        }
        if(ticket==-1L)return@synchronized prior!!
        if(bff==null||prior==null)denied()
        if(bff.expiresAt<=clock()+30_000){forget();denied()}
        try {
            val value=transport.access(bff,installationId,deviceToken());accept(value,bff,prior)
            synchronized(stateLock){if(generation!=ticket||session!==bff)denied();cached=value;identity=value}
            value
        } catch(e:ManagedCollectFailure){
            if(e.status in listOf(401,403))synchronized(stateLock){if(generation==ticket&&session===bff){generation++;session=null;identity=null;cached=null}}
            throw e
        }
    }
    fun currentAccessToken():String=currentAccess().token
    /** Background invalidates in-flight credentials, retaining only the current
     * in-memory BFF cookie so foreground can recheck the real managed session. */
    fun onBackground(){synchronized(stateLock){generation++;cached=null}}
    /** Cancels local code entry without sending mail or resetting cooldown. */
    fun cancelEmailCode(){synchronized(stateLock){if(session!=null)throw ManagedCollectFailure("managed_session_exists",409);generation++;challenge=null;verificationUnknown=false}}
    private fun forget():CollectBffSession?=synchronized(stateLock){val old=session;generation++;session=null;identity=null;cached=null;challenge=null;verificationUnknown=false;old}
    /** Clear locally before dispatch; a failed server logout remains a failure. */
    fun signOut(){val bff=forget();if(bff!=null)synchronized(ioLock){transport.signOut(bff)}}
}

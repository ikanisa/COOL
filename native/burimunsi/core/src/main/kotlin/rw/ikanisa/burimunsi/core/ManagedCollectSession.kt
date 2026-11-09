package rw.ikanisa.burimunsi.core

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
    fun signIn(email:String,password:String):CollectBffSession
    fun access(session:CollectBffSession,installationId:String,deviceToken:String):CollectManagedAccess
    fun signOut(session:CollectBffSession)
}

/** Serializes real BFF refresh observations; local generations reject responses
 * from before backgrounding or sign-out. Native command journals remain owned by
 * NativeRepository and are never cleared by a managed identity replacement.
 */
class ManagedCollectSession(private val transport:CollectManagedTransport,private val installationId:String,
    private val collectionId:String,private val profile:String,private val deviceToken:()->String,
    private val clock:()->Long=System::currentTimeMillis) {
    private val stateLock=Any();private val ioLock=Any()
    private var generation=0L
    private var session:CollectBffSession?=null
    private var identity:CollectManagedAccess?=null
    private var cached:CollectManagedAccess?=null
    val signedIn:Boolean get()=synchronized(stateLock){session!=null&&identity!=null}
    private fun denied():Nothing=throw ManagedCollectFailure("managed_session_required",401)
    private fun accept(value:CollectManagedAccess,bff:CollectBffSession,previous:CollectManagedAccess?) {
        if(value.installationId!=installationId||value.collectionId!=collectionId||value.profile!=profile||
            value.principalId!=bff.principalId||value.expiresAt<=clock()+30_000||value.expiresAt>bff.expiresAt||
            previous!=null&&(!value.sameIdentity(previous)||value.accountVersion<previous.accountVersion||
            value.credentialVersion<previous.credentialVersion||value.grantVersion<previous.grantVersion||value.scopeVersion<previous.scopeVersion))denied()
    }
    fun signIn(email:String,password:String)=synchronized(ioLock){
        val ticket=synchronized(stateLock){if(session!=null)throw ManagedCollectFailure("managed_session_exists",409);++generation}
        val bff=transport.signIn(email,password)
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
    fun currentAccessToken():String=synchronized(ioLock){
        val (ticket,bff,prior)=synchronized(stateLock){
            cached?.let{if(it.expiresAt>clock()+45_000)return@synchronized Triple(-1L,null,it)}
            Triple(generation,session,identity)
        }
        if(ticket==-1L)return@synchronized prior!!.token
        if(bff==null||prior==null)denied()
        if(bff.expiresAt<=clock()+30_000){forget();denied()}
        try {
            val value=transport.access(bff,installationId,deviceToken());accept(value,bff,prior)
            synchronized(stateLock){if(generation!=ticket||session!==bff)denied();cached=value;identity=value}
            value.token
        } catch(e:ManagedCollectFailure){
            if(e.status in listOf(401,403))synchronized(stateLock){if(generation==ticket&&session===bff){generation++;session=null;identity=null;cached=null}}
            throw e
        }
    }
    /** Background invalidates in-flight credentials, retaining only the current
     * in-memory BFF cookie so foreground can recheck the real managed session. */
    fun onBackground(){synchronized(stateLock){generation++;cached=null}}
    private fun forget():CollectBffSession?=synchronized(stateLock){val old=session;generation++;session=null;identity=null;cached=null;old}
    /** Clear locally before dispatch; a failed server logout remains a failure. */
    fun signOut(){val bff=forget();if(bff!=null)synchronized(ioLock){transport.signOut(bff)}}
}

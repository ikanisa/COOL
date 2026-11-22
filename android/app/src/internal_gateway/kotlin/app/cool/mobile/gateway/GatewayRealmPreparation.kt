package app.cool.mobile.gateway

import org.json.JSONObject
import java.io.File
import java.io.OutputStream
import java.nio.file.Files
import java.nio.file.LinkOption
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import javax.crypto.SecretKey

/** Inactive original evidence handoff only. Owner UUIDs are references, never
 * proof of revocation/enrollment or permission to replace a realm/key. */
internal class GatewayRealmPreparation(private val root: File, private val store: GatewayEncryptedStore) {
    internal data class References(val preparation: String, val revoke: String, val enroll: String) {
        init { val ids=listOf(preparation,revoke,enroll);if(ids.any { !validUuid(it) } || ids.toSet().size!=3)throw GatewayStateException("gateway_preparation_arguments_invalid") }
    }
    private fun fail(code: String = "gateway_preparation_invalid"): Nothing = throw GatewayStateException(code)
    private fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private fun exists(file: File) = Files.exists(file.toPath(), LinkOption.NOFOLLOW_LINKS)
    private fun directory(file: File) { GatewayRecoveryStorage.directory(file) }
    private fun parent(file: File) { if(!exists(file)) GatewayRecoveryStorage.fresh(file); directory(file) }
    private fun read(file: File): ByteArray {
        directory(file.parentFile)
        if(Files.isSymbolicLink(file.toPath()) || !Files.isRegularFile(file.toPath(), LinkOption.NOFOLLOW_LINKS) || file.length() !in 1..MAX_JSON) fail()
        return file.readBytes().also { if(it.size !in 1..MAX_JSON || !String(it,Charsets.UTF_8).toByteArray(Charsets.UTF_8).contentEquals(it)) fail() }
    }
    private fun immutable(file: File, value: JSONObject): String {
        val bytes=value.toString().toByteArray(Charsets.UTF_8);if(bytes.size !in 1..MAX_JSON)fail()
        if(exists(file)) { if(!read(file).contentEquals(bytes))fail("gateway_preparation_conflict") }
        else { GatewayRecoveryStorage.output(file).use { it.write(bytes) };GatewayRecoveryStorage.syncFile(file) }
        if(!read(file).contentEquals(bytes))fail("gateway_preparation_unknown")
        return digest(bytes)
    }
    private fun check(cancelled: () -> Boolean) { if(cancelled())throw GatewayStateException("gateway_recovery_cancelled") }
    fun prepare(refs: References, certificate: String, cancelled: () -> Boolean, requirePause: () -> Unit): Map<String,Any?> = synchronized(GatewayJournal.PROCESS_LOCK) {
        check(cancelled);requireExistingSource(root);store.requireActiveInstallation();requirePause()
        if(!certificate.matches(Regex("[0-9a-f]{64}")))fail()
        val metadata=store.readIdentityMetadata() ?: fail();val enrolled=store.readEnrollment() ?: fail()
        val identity=GatewayDeviceIdentity()
        GatewayInstalledEnrollment.verify(metadata,enrolled,identity.keyId(),identity.publicKeyBase64(),certificate)
        val intent=JSONObject().put("contract_version",1).put("inactive",true).put("purpose","original_evidence_preparation")
            .put("preparation_request_id",refs.preparation).put("revoke_request_id",refs.revoke).put("enrollment_request_id",refs.enroll)
            .put("realm","collect_gateway_v1").put("storage_key_alias",GatewayKeyCreationCustody.STORAGE_ALIAS)
            .put("signing_key_alias",GatewayKeyCreationCustody.SIGNING_ALIAS).put("old_identity",metadata).put("old_enrollment",enrolled)
        val namespace=File(root,NAMESPACE);parent(namespace)
        Files.newDirectoryStream(namespace.toPath()).use { paths -> for(path in paths) if(path.fileName.toString() !in setOf("plans","requests"))fail() }
        val plans=File(namespace,"plans");parent(plans);val requests=File(namespace,"requests");parent(requests)
        val plan=File(plans,refs.preparation);val intentFile=File(plan,"intent.json");val freshPlan=!exists(plan)
        // A retained directory without its original intent is uncertain; never
        // infer freshness or recreate missing original bytes.
        if(!freshPlan) { directory(plan);if(!exists(intentFile))fail("gateway_preparation_unknown")
            Files.newDirectoryStream(plan.toPath()).use { paths -> for(path in paths) if(path.fileName.toString() !in setOf("intent.json","complete.json","snapshot"))fail() }
        }
        else GatewayRecoveryStorage.fresh(plan)
        val intentSha=immutable(intentFile,intent)
        for((role,id) in listOf("preparation" to refs.preparation,"revoke" to refs.revoke,"enrollment" to refs.enroll)) {
            val index=File(requests,"$id.json");if(!freshPlan && !exists(index))fail("gateway_preparation_unknown")
            immutable(index,JSONObject().put("contract_version",1).put("role",role)
                .put("preparation_request_id",refs.preparation).put("intent_sha256",intentSha))
        }
        check(cancelled);requirePause()
        val completion=File(plan,"complete.json");val snapshot=File(plan,"snapshot")
        val result: JSONObject
        if(exists(completion)) {
            result=JSONObject(String(read(completion),Charsets.UTF_8));requireKeys(result,COMPLETE_KEYS)
            if(strictInteger(result,"contract_version")!=1L || !strictBoolean(result,"inactive") || strictString(result,"intent_sha256")!=intentSha)fail()
            val sha=strictString(result,"manifest_sha256");val count=strictInteger(result,"files");val transport=strictString(result,"transport_sha256")
            if(count<0 || !sha.matches(Regex("[0-9a-f]{64}")) || !transport.matches(Regex("[0-9a-f]{64}")))fail()
            directory(snapshot);directory(File(snapshot,"objects"))
            val actual=GatewayRecoveryTransfer.write(GatewayRecoveryArchive(snapshot,sha,count),DISCARD,cancelled)
            if(actual!=transport)fail("gateway_preparation_unknown")
        } else {
            if(!freshPlan || exists(snapshot))fail("gateway_preparation_unknown")
            val archive=store.exportRecovery(snapshot) { cancelled() }
            check(cancelled);requirePause()
            val transport=GatewayRecoveryTransfer.write(archive,DISCARD,cancelled)
            result=JSONObject().put("contract_version",1).put("inactive",true).put("intent_sha256",intentSha)
                .put("manifest_sha256",archive.manifestSha256).put("files",archive.files).put("transport_sha256",transport)
            immutable(completion,result)
        }
        check(cancelled);requirePause()
        mapOf("contract_version" to 1,"operation" to "prepareReEnrollment","state" to "complete","phase" to "inactive_evidence",
            "preparation_request_id" to refs.preparation,"intent_sha256" to intentSha,"manifest_sha256" to strictString(result,"manifest_sha256"),
            "files" to strictInteger(result,"files"),"inactive" to true,"requires_re_enrollment" to true,"backend_revocation_proven" to false,
            "dispatch_authority" to false,"reason_code" to "gateway_preparation_evidence_retained")
    }
    companion object {
        const val NAMESPACE="collect_gateway_preparation_v1"
        private const val MAX_JSON=2048
        private val COMPLETE_KEYS=setOf("contract_version","inactive","intent_sha256","manifest_sha256","files","transport_sha256")
        private val DISCARD=object:OutputStream() { override fun write(value:Int)=Unit;override fun write(bytes:ByteArray,offset:Int,length:Int)=Unit }
        fun references(value: Any?): References {
            val args=value as? Map<*,*> ?: throw GatewayStateException("gateway_preparation_arguments_invalid")
            val names=setOf("contract_version","preparation_request_id","revoke_request_id","enrollment_request_id")
            if(args.keys!=names || args["contract_version"]!=1)throw GatewayStateException("gateway_preparation_arguments_invalid")
            val ids=listOf("preparation_request_id","revoke_request_id","enrollment_request_id").map { args[it] as? String ?: throw GatewayStateException("gateway_preparation_arguments_invalid") }
            if(ids.any { !validUuid(it) } || ids.toSet().size!=3)throw GatewayStateException("gateway_preparation_arguments_invalid")
            return References(ids[0],ids[1],ids[2])
        }
        fun requireExistingSource(root: File) {
            GatewayRecoveryStorage.directory(root)
            val realm=File(root,"collect_gateway_v1");GatewayRecoveryStorage.directory(realm)
            if(Files.exists(File(realm,GatewayRecovery.INACTIVE).toPath(),LinkOption.NOFOLLOW_LINKS))throw GatewayStateException("gateway_recovery_inactive")
            // Preparation never lets an ordinary AtomicFile reader repair or
            // discard retained backup/staging bytes. Raw recovery handles them.
            Files.newDirectoryStream(realm.toPath()).use { paths -> for(path in paths) {
                val name=path.fileName.toString()
                if(Files.isSymbolicLink(path) || !Files.isRegularFile(path,LinkOption.NOFOLLOW_LINKS) || name.endsWith(".bak") || name.endsWith(".new"))
                    throw GatewayStateException("gateway_preparation_source_ambiguous")
            } }
            for(name in listOf("identity","enrollment","journal")) {
                val backup=File(realm,"$name.bin.bak");val file=if(Files.exists(backup.toPath(),LinkOption.NOFOLLOW_LINKS))backup else File(realm,"$name.bin")
                if(Files.isSymbolicLink(file.toPath()) || !Files.isRegularFile(file.toPath(),LinkOption.NOFOLLOW_LINKS))throw GatewayStateException("gateway_preparation_source_unavailable")
            }
            val keys=KeyStore.getInstance("AndroidKeyStore").also { it.load(null) }
            if(!keys.containsAlias(GatewayKeyCreationCustody.SIGNING_ALIAS) || keys.getKey(GatewayKeyCreationCustody.SIGNING_ALIAS,null) !is PrivateKey ||
                !keys.containsAlias(GatewayKeyCreationCustody.STORAGE_ALIAS) || keys.getKey(GatewayKeyCreationCustody.STORAGE_ALIAS,null) !is SecretKey)
                throw GatewayStateException("gateway_preparation_source_unavailable")
        }
    }
}

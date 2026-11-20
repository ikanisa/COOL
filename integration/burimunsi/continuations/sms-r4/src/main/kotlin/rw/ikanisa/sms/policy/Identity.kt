package rw.ikanisa.sms.policy

import java.util.Collections

data class OwnerScope(val contract: Contract, val ownerId: String, val installationId: String, val generation: String) {
    fun valid() = listOf(ownerId,installationId,generation).all(EvidenceHash::identity)
    fun fields() = listOf(contract.name,ownerId,installationId,generation)
}
data class SourceBinding(val id: String, val version: Int, val subscriptionId: Int?) {
    fun valid() = EvidenceHash.identity(id) && version > 0 && SimPolicy.valid(subscriptionId)
    fun fields(): List<String?> = listOf(id,version.toString(),subscriptionId?.toString())
}
class SimState(val permissionGranted: Boolean, active: Set<Int>?) {
    val active: Set<Int>? = active?.let { Collections.unmodifiableSet(HashSet(it)) }
}
enum class Route { ACCEPT, OTHER_SIM, HOLD_PERMISSION, HOLD_UNKNOWN, HOLD_BINDING, HOLD_PROFILE }
object SimPolicy {
    fun valid(id: Int?) = id != null && id >= 0 && id < Int.MAX_VALUE
    fun route(binding: SourceBinding, observed: Int?, sim: SimState, profileReady: Boolean = true): Route {
        if (!profileReady) return Route.HOLD_PROFILE
        if (!binding.valid()) return Route.HOLD_BINDING
        if (!sim.permissionGranted) return Route.HOLD_PERMISSION
        val active = sim.active ?: return Route.HOLD_UNKNOWN
        if (active.any { !valid(it) } || binding.subscriptionId !in active) return Route.HOLD_BINDING
        if (!valid(observed) || observed !in active) return Route.HOLD_UNKNOWN
        return if (observed == binding.subscriptionId) Route.ACCEPT else Route.OTHER_SIM
    }
}
data class Authority(val scope: OwnerScope, val binding: SourceBinding, val sessionEpoch: Long,
                     val sim: SimState, val enabled: Boolean = true, val online: Boolean = true)
enum class ClassificationKind { SUPPORTED_RECEIPT, SUPPORTED_CANDIDATE, UNSUPPORTED, AMBIGUOUS, INCOMPLETE }
data class Classification(val contract: Contract,val kind: ClassificationKind,val reason: String,
                          val policyVersion: String,val evidenceFingerprint: String) {
    val eligible get() = kind == ClassificationKind.SUPPORTED_RECEIPT || kind == ClassificationKind.SUPPORTED_CANDIDATE
}
fun interface MessageClassifier { fun classify(assembly: Assembly): Classification }
/** The raw original has no network-operation ID; one immutable batch later owns that identity. */
class Original(val scope: OwnerScope,val binding: SourceBinding,val captureId: String,val sourceId: String,
               val assembly: Assembly,val classification: Classification) {
    val body get() = assembly.body
    val sender get() = assembly.sender
    val bodySha256 = body?.let(EvidenceHash::utf8)
    val key = EvidenceHash.framed(scope.fields() + captureId)
    val evidenceHash = EvidenceHash.framed(scope.fields()+binding.fields()+listOf(captureId,sourceId,assembly.input.fingerprint,body,sender))
    fun valid() = scope.valid() && EvidenceHash.identity(captureId) && EvidenceHash.identity(sourceId) &&
        classification.contract == scope.contract && classification.evidenceFingerprint == assembly.input.fingerprint
    fun eligible() = valid() && binding.valid() && classification.eligible && bodySha256 != null &&
        !body.isNullOrBlank() && !sender.isNullOrBlank() &&
        (assembly.completeness == Completeness.PDU_SET ||
            (scope.contract == Contract.MMONEY_LEDGER_V1 && assembly.completeness == Completeness.PROVIDER_BODY_ONLY))
    override fun toString() = "Original(contract=${scope.contract},key=$key,evidence=$evidenceHash)"
}
/** Frozen order and originals: retries must replay this exact request and operationId. */
class UploadBatch(val operationId: String, originals: List<Original>) {
    val originals = frozen(originals)
    val scope get() = originals.first().scope
    val binding get() = originals.first().binding
    val key = EvidenceHash.framed(listOf("batch") + (originals.firstOrNull()?.scope?.fields() ?: emptyList()) + operationId)
    val payloadHash = EvidenceHash.framed(listOf(operationId) + this.originals.map { it.evidenceHash })
    fun valid(): Boolean = EvidenceHash.identity(operationId) && originals.size in 1..20 && originals.all { it.valid() } &&
        originals.map { it.scope }.distinct().size == 1 && originals.map { it.binding }.distinct().size == 1 &&
        originals.map { it.captureId }.distinct().size == originals.size &&
        (scope.contract != Contract.BURI_COLLECT_V2 || (originals.size == 1 && operationId == originals[0].captureId)) &&
        (scope.contract != Contract.MMONEY_LEDGER_V1 || (AckPolicy.uuid(operationId) && originals.all { AckPolicy.uuid(it.captureId) }))
    override fun toString() = "UploadBatch(key=$key,count=${originals.size},payload=$payloadHash)"
}

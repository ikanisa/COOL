package rw.ikanisa.burimunsi.data

import android.content.Context
import java.util.Base64
import org.json.JSONObject
import org.json.JSONArray
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.storage.*

/** API data is the authority. No local SMS-to-balance arithmetic and no demo accounts. */
class NativeRepository(context: Context, api: ApiClient, groupId: String? = null){
    companion object {
        private val commandPreparationLock = Any()

        internal fun canRestoreObservationOwner(context: Context): Boolean =
            NativeSessions.canRestoreObservationOwner(context)

        internal fun restorableObservationOwner(context: Context): ObservationOwner? =
            NativeSessions.restorableObservationOwner(context)

        internal fun observationOwner(context: Context): ObservationSessionOwner? =
            NativeSessions.observationOwner(context)

        internal fun <T> withObservationOwner(
            context: Context,
            expected: ObservationSessionOwner? = null,
            action: (String, String) -> T,
        ): T? = NativeSessions.withObservationOwner(context, expected, action)
    }

    private val cacheStore = SecureStore(context, "records")
    private val receiptVersions = AllocationReceiptVersions(context)
    private val journal = OperationJournal(AndroidOperationStore(context))
    private val retirementJournal = ReceiverRetirementJournal(AndroidReceiverRetirementStore(context))
    private val sessions = NativeSessions(context, api, groupId, cacheStore)
    private val recordReadOwner = Any()
    private val receiverPairing = NativeReceiverPairing(sessions, api, retirementJournal, journal, commandPreparationLock)
    private val commands = NativeCommandRepository(
        sessions, journal, commandPreparationLock, receiptVersions, cacheStore,
        { api.installationId }, receiverPairing::hasPendingReceiverRetirement,
    )
    private val records = NativeRecordData(sessions, api, cacheStore, receiptVersions, recordReadOwner)
    private val smsData = NativeSmsData(sessions, { api.installationProfile }, recordReadOwner)

    val collectionId: String get() = sessions.groupId
    val boundCollectionId: String? get() = sessions.boundCollectionId
    val sessionRevision: Long? get() = sessions.sessionRevision
    val lastReadSavedAt: Long? get() = sessions.lastReadSavedAt
    val lastReadFromCache: Boolean get() = sessions.lastReadFromCache

    fun restore(): Operator? = sessions.restore()
    fun login(phone: String, pin: String): Operator = sessions.login(phone, pin)
    fun refreshSession(): Operator = sessions.refreshSession()
    fun changePin(current: String, next: String, confirm: String): Operator = sessions.changePin(current, next, confirm)
    fun current(): Operator? = sessions.current()

    internal fun <T> withCurrentProfile(profile: Operator, publish: (String, Long) -> T): T =
        sessions.withCurrentProfile(profile, publish)

    fun reattachSameOwner(owner: String, collection: String): Operator? = sessions.reattachSameOwner(owner, collection)
    fun observeProcessSession(listener: () -> Unit): () -> Unit = sessions.observeProcessSession(listener)
    fun hasPendingPasscode(): Boolean = sessions.hasPendingPasscode()
    fun hasSavedSession(): Boolean = sessions.hasSavedSession()
    fun clearOperator() = sessions.clearOperator()
    fun retryPendingSignOuts(): Boolean = sessions.retryPendingSignOuts()
    fun logout() = sessions.logout()

    fun hasPendingReceiverRetirement(): Boolean = receiverPairing.hasPendingReceiverRetirement()
    fun hasReceiverRetirementRecord(): Boolean = receiverPairing.hasReceiverRetirementRecord()
    fun recoverReceiverRetirement(): JSONObject? = receiverPairing.recoverReceiverRetirement()
    fun pairGateway(code: String, replace: Boolean): JSONObject = receiverPairing.pairGateway(code, replace)

    fun home(): Home = records.home()
    fun recordReadScope(): RecordReadScope = records.recordReadScope()
    fun validateRecordReadScope(scope: RecordReadScope) = records.validateRecordReadScope(scope)

    fun payments(listing: ListingQuery, cursor: String? = null, memberId: String? = null, scope: RecordReadScope? = null): Page<Payment> =
        records.payments(listing, cursor, memberId, scope)

    fun members(listing: ListingQuery, cursor: String? = null, scope: RecordReadScope? = null, anchorId: String? = null): Page<Member> =
        records.members(listing, cursor, scope, anchorId)

    fun ledger(id: String, listing: ListingQuery, cursor: String? = null, scope: RecordReadScope? = null): Page<LedgerRow> =
        records.ledger(id, listing, cursor, scope)

    fun sms(listing: ListingQuery, cursor: String? = null, scope: RecordReadScope? = null, limit: Int = 100): Page<SmsRow> =
        records.sms(listing, cursor, scope, limit)

    fun staff(listing: ListingQuery, cursor: String? = null, scope: RecordReadScope? = null): Page<StaffAccount> =
        records.staff(listing, cursor, scope)

    fun audit(listing: ListingQuery, cursor: String? = null, scope: RecordReadScope? = null): Page<AuditRow> =
        records.audit(listing, cursor, scope)

    fun paymentHistory(id: String, listing: ListingQuery, cursor: String? = null, scope: RecordReadScope? = null): Page<PaymentEvent> =
        records.paymentHistory(id, listing, cursor, scope)

    fun payments(q: String = "", filter: String = "all", cursor: String? = null, memberId: String? = null): Page<Payment> =
        records.payments(q, filter, cursor, memberId)

    fun members(q: String = "", cursor: String? = null): Page<Member> = records.members(q, cursor)
    fun payment(id: String): Payment = records.payment(id)
    fun member(id: String): Member = records.member(id)
    fun ledger(id: String, cursor: String? = null): Page<LedgerRow> = records.ledger(id, cursor)

    fun sms(q: String = "", cursor: String? = null, filter: String = "all", limit: Int? = null): Page<SmsRow> =
        records.sms(q, cursor, filter, limit)

    fun staff(cursor: String? = null): Page<StaffAccount> = records.staff(cursor)
    fun audit(cursor: String? = null): Page<AuditRow> = records.audit(cursor)
    fun paymentHistory(id: String, cursor: String? = null): Page<PaymentEvent> = records.paymentHistory(id, cursor)

    fun observationProfile(): JSONObject = smsData.observationProfile()

    fun observationConsent(): ObservationConsentRevision = smsData.observationConsent()

    fun setObservationConsent(revision: ObservationConsentRevision): ObservationConsentRevision =
        smsData.setObservationConsent(revision)

    fun submitObservation(observation: SmsObservation): ObservationAck = smsData.submitObservation(observation)

    fun reconcileObservation(request: ObservationReconcileRequest): ObservationReconcileReply =
        smsData.reconcileObservation(request)

    fun reconcileObservations(requests: List<ObservationReconcileRequest>): List<ObservationReconcileReply> =
        smsData.reconcileObservations(requests)

    fun observationReconcileStatus(): ObservationReconcileStatus = smsData.observationReconcileStatus()

    fun observationPage(q: String = "", cursor: String? = null, limit: Int? = null): Page<ObservationListRow> =
        smsData.observationPage(q, cursor, limit)

    fun observationPage(
        listing: ListingQuery,
        cursor: String? = null,
        scope: RecordReadScope? = null,
        limit: Int = 100,
    ): Page<ObservationListRow> = smsData.observationPage(listing, cursor, scope, limit)

    fun observationProcessing(sources: List<SmsSourceRef.Observation>): Map<SmsSourceRef.Observation, ObservationProcessing> =
        smsData.observationProcessing(sources)

    fun retryObservation(source: SmsSourceRef.Observation, requestId: String): String =
        smsData.retryObservation(source, requestId)

    fun revealObservation(source: SmsSourceRef.Observation, reason: String): ObservationDisclosure =
        smsData.revealObservation(source, reason)

    fun raw(id: String, reason: String): RawSms = smsData.raw(id, reason)

    fun allocate(p:Payment,member:Member,note:String):JSONObject {
        checkContract(PaymentPresentation.canAllocate(p)&&member.active,"allocation_unavailable")
        checkContract(Presentation.validNote(note),"invalid_note")
        return mutate("POST","/payments/${Values.id(p.id)}/allocate",JSONObject().put("memberId",member.id).put("expectedVersion",p.version).put("note",note.trim()),allocation=p)
    }
    fun enroll(name:String,phone:String)=mutate("POST","/members",JSONObject().put("name",name.trim()).put("phone",Values.phone(phone)))
    fun onboardingSuggestions(q:String,cursor:String?):JSONObject = JSONObject(sessions.request("GET","/members/suggestions"+
        query(mapOf("q" to q,"cursor" to cursor,"limit" to "40"))))
    // Android can deliver a picker result while an unchanged grant is being renewed. The
    // original actor, collection and process generation survive an updated expiry timestamp.
    private fun <T> memberImportBinding(scope: MemberImportScope, action: (Operator, SessionWitness) -> T): T {
        val witness = sessions.ownedSession()
        return sessions.authority.withCurrent(witness) {
            val who = sessions.operator ?: throw ContractFailure("session_unavailable")
            checkContract(witness.generation == scope.sessionRevision && who.id == scope.operatorId &&
                collectionId == scope.collectionId, "session_changed")
            action(who, witness)
        }
    }

    /** In-memory custody only. File reads and preview dispatch also require the current on-disk grant. */
    internal fun <T> withMemberImportScope(scope: MemberImportScope, use: () -> T): T =
        memberImportBinding(scope) { _, _ -> use() }

    private fun memberImportWitness(scope: MemberImportScope): SessionWitness =
        memberImportBinding(scope) { who, witness ->
            checkContract(!sessions.hasInflightPasscode(witness), "session_changed")
            checkContract(Access.allows(who, Capability.ENROLL, System.currentTimeMillis()), "access_denied")
            witness
        }

    fun validateMemberImportScope(scope: MemberImportScope) { memberImportWitness(scope) }

    fun onboardingPreview(mimeType: String, bytes: ByteArray, consent: Boolean, scope: MemberImportScope): JSONObject {
        checkContract(bytes.isNotEmpty() && bytes.size <= 5 * 1024 * 1024, "smart_import_size_invalid")
        val body = JSONObject().put("mimeType", mimeType).put("fileBytes", Base64.getEncoder().encodeToString(bytes))
            .put("externalOcrConsent", consent)
        if (consent) {
            body.put("importFlowId", scope.flowId)
            body.put("ocrDisclosureVersion", MemberImportScope.OCR_DISCLOSURE_VERSION)
        }
        val witness = memberImportWitness(scope)
        return try {
            val reply = sessions.requestOwned(witness, "POST", "/members/import/preview", body)
            memberImportWitness(scope)
            JSONObject(reply)
        } catch (e: ApiFailure) {
            if (e.uncertain) throw ApiFailure("smart_import_preview_unconfirmed", e.status, false)
            throw e
        }
    }
    fun onboardingImport(rows:JSONArray):JSONObject {
        checkContract(rows.length() in 1..500,"invalid_import")
        val body=JSONObject().put("rows",rows)
        // Validate before creating the durable dispatch journal. A request that
        // cannot fit the wire limit must never strand an unsent command as SENT.
        val sized=JSONObject(body.toString()).put("requestId","00000000-0000-4000-8000-000000000000")
        checkContract(sized.toString().toByteArray(Charsets.UTF_8).size<=SmartOnboardingLimits.MAX_BATCH_BYTES,"smart_import_size_invalid")
        return mutate("POST","/members/import",body)
    }
    fun setMemberActive(m:Member,active:Boolean)=mutate("PATCH","/members/${Values.id(m.id)}",JSONObject().put("active",active).put("expectedVersion",m.version))
    fun staffAction(body:JSONObject,resolveBlankPhoneDenial:Boolean=false)=mutate(if(body.getString("action")=="create")"POST" else "PATCH","/staff",JSONObject(body.toString()),resolveBlankPhoneDenial)
    private fun mutate(
        method: String,
        path: String,
        body: JSONObject,
        resolveBlankPhoneDenial: Boolean = false,
        allocation: Payment? = null,
    ): JSONObject = commands.mutate(method, path, body, resolveBlankPhoneDenial, allocation)

    fun pending(): PendingOperation? = commands.pending()

    /** Reconcile the original outcome, including eligible staff resolutions. */
    fun reconcilePending(): JSONObject = commands.reconcilePending()

    /** Use a bounded read-only retry without dispatching the original command. */
    fun reconcilePending(retry: ReadOnlyRecoveryRetry, nowMs: Long): JSONObject =
        commands.reconcilePending(retry, nowMs)

    /** Dispatch only a durable command that has never begun a send attempt. */
    fun retryPending(): JSONObject = commands.retryPending()
}

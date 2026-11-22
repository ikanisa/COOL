package rw.ikanisa.burimunsi.data

import org.json.JSONArray
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.*

/** Observation upload, recovery reads and audited SMS disclosure. */
internal class NativeSmsData(
    session: NativeSessionRequests,
    private val installationProfile: () -> String?,
    private val recordReadOwner: Any,
) : NativeSessionRequests by session {
    private fun observationSession():SessionWitness {
        val witness=ownedSession()
        return authority.withCurrent(witness){
            val who=operator?:throw ApiFailure("session_unavailable",401)
            checkContract(installationProfile()=="internal_receiver"&&who.role==Role.ADMIN&&
                who.expiresAt>System.currentTimeMillis()&&
                setOf(Capability.SMS.key,Capability.GATEWAY.key).all{it in who.capabilities},"access_denied")
            witness
        }
    }
    fun observationProfile():JSONObject = JSONObject(requestOwned(observationSession(),"GET","/sms/observation-profile"))
    fun observationConsent():ObservationConsentRevision {
        val value=JSONObject(requestOwned(observationSession(),"GET","/sms/observation-consent"))
        return ObservationConsentRevision(value.getBoolean("enabled"),value.getLong("generation"))
    }
    fun setObservationConsent(revision:ObservationConsentRevision):ObservationConsentRevision {
        checkContract(revision.generation in 1..ObservationConsent.MAX_GENERATION,"invalid_consent_generation")
        val body=JSONObject().put("enabled",revision.enabled).put("generation",revision.generation)
        val value=JSONObject(requestOwned(observationSession(),"POST","/sms/observation-consent",body))
        val result=ObservationConsentRevision(value.getBoolean("enabled"),value.getLong("generation"))
        checkContract(result==revision,"invalid_consent_response")
        return result
    }
    fun submitObservation(observation:SmsObservation):ObservationAck {
        val body=JSONObject().put("requestId",observation.requestId).put("rawSender",observation.rawSender)
            .put("rawBody",observation.rawBody).put("sourceMode",observation.sourceMode).put("complete",observation.complete)
            .put("capturedAt",observation.capturedAt).put("serviceCentreAt",observation.serviceCentreAt?:JSONObject.NULL)
            .put("inboxReceivedAt",observation.inboxReceivedAt?:JSONObject.NULL).put("subscriptionId",observation.subscriptionId?:JSONObject.NULL)
        observation.sourceKey?.let{body.put("sourceKey",it)}
        val value=JSONObject(requestOwned(observationSession(),"POST","/sms/observations",body))
        val ack=ObservationAck(value.getString("requestId"),value.getString("sourceId"),value.getString("bodySha256"),
            value.getString("status"),value.getInt("financialEffects"))
        checkContract(ObservationAcknowledgement.matches(observation,ack),"invalid_observation_ack")
        return ack
    }
    private fun reconciliationItem(request:ObservationReconcileRequest):JSONObject {
        checkContract(Regex("[a-f0-9]{64}").matches(request.sourceKey)&&Regex("[a-f0-9]{64}").matches(request.bodySha256),
            "invalid_observation_source")
        return JSONObject().put("sourceKey",request.sourceKey).put("bodySha256",request.bodySha256)
            .put("rawSender",request.rawSender).put("serviceCentreAt",request.serviceCentreAt?:JSONObject.NULL)
            .put("inboxReceivedAt",request.inboxReceivedAt).put("subscriptionId",request.subscriptionId?:JSONObject.NULL)
    }
    private fun reconcileReply(key:String,row:JSONObject,latest:String?=null):ObservationReconcileReply {
        val state=row.getString("state")
        val source=row.nullString("sourceId")
        checkContract(row.getString("sourceKey")==key&&state in setOf("matched","missing")&&(state=="matched")==(source!=null)&&
            (source==null||runCatching{Values.requestId(source)==source}.getOrDefault(false))&&
            (latest==null||runCatching{Values.requestId(latest)==latest}.getOrDefault(false)),"invalid_observation_reconciliation")
        return ObservationReconcileReply(key,state,source,latest)
    }
    /** Compare scoped receipt identities; these requests carry no message bodies and cannot acknowledge or post a receipt. */
    private fun <T> readObservationProof(method:String,path:String,body:JSONObject?=null,decode:(JSONObject)->T):T {
        val witness=observationSession()
        val value=JSONObject(requestOwned(witness,method,"/sms/observations/$path",body))
        return authority.withCurrent(witness){
            checkContract(value.getString("groupId")==groupId,"invalid_observation_reconciliation")
            decode(value)
        }
    }
    fun reconcileObservation(request:ObservationReconcileRequest):ObservationReconcileReply =
        readObservationProof("POST","reconcile",reconciliationItem(request)){value->
            reconcileReply(request.sourceKey,value,value.nullString("latestRecordedSourceId"))
        }
    fun reconcileObservations(requests:List<ObservationReconcileRequest>):List<ObservationReconcileReply> {
        checkContract(requests.size in 1..20&&requests.map{it.sourceKey}.distinct().size==requests.size,"invalid_observation_reconciliation")
        val items=JSONArray()
        requests.forEach{items.put(reconciliationItem(it))}
        val body=JSONObject().put("items",items)
        checkContract(body.toString().toByteArray(Charsets.UTF_8).size<=8192,"invalid_observation_reconciliation")
        return readObservationProof("POST","reconcile-batch",body){value->
            val rows=value.getJSONArray("items")
            checkContract(rows.length()==requests.size,"invalid_observation_reconciliation")
            requests.mapIndexed{index,request->reconcileReply(request.sourceKey,rows.getJSONObject(index))}
        }
    }
    fun observationReconcileStatus():ObservationReconcileStatus = readObservationProof("GET","reconcile-status"){value->
        val count=value.getInt("recordedCount");val recorded=value.getBoolean("hasRecorded");val revision=value.getString("revision")
        checkContract(count in 0..100_000&&recorded==(count>0)&&Regex("[a-f0-9]{64}").matches(revision),"invalid_observation_reconciliation")
        ObservationReconcileStatus(value.getBoolean("hasPending"),recorded,count,revision,value.getBoolean("hasUnmatchedCanonical"))
    }
    /** A quarantine page is a distinct source stream, never a canonical SMS/payment page. */
    fun observationPage(q:String="",cursor:String?=null,limit:Int?=null):Page<ObservationListRow> {
        val witness = observationSession()
        val path = "/sms/observations" + query(
            mapOf("q" to q, "cursor" to cursor, "limit" to limit?.coerceIn(1, 100)?.toString()),
        )
        val data = requestOwned(witness, "GET", path)
        return authority.withCurrent(witness) { decodeObservationPage(data) }
    }
    fun observationPage(
        listing: ListingQuery,
        cursor: String?,
        scope: RecordReadScope?,
        limit: Int,
    ): Page<ObservationListRow> {
        val path = listingPath("/sms/observations", ListingTarget.OBSERVATIONS, listing, cursor, limit = limit)
        val witness = observationSession()
        val data = scope?.read(recordReadOwner, path) ?: requestOwned(witness, "GET", path)
        return authority.withCurrent(witness) { decodeObservationPage(data) }
    }
    private fun decodeObservationPage(data:String):Page<ObservationListRow> =
        page(data){row->
            checkedDto("observationPageItem",row)
            checkContract(row.getString("sourceKind")=="observation"&&row.getString("id")==row.getString("sourceId")&&
                row.getString("groupId")==groupId&&row.getString("status")=="source_unresolved"&&row.counter("financialEffects")==0L,"invalid_observation_source")
            ObservationListRow(SmsSourceRef.Observation(Values.id(row.getString("sourceId"))),groupId,row.getString("at"))
        }
    fun observationProcessing(sources:List<SmsSourceRef.Observation>):Map<SmsSourceRef.Observation,ObservationProcessing>{
        checkContract(sources.isNotEmpty()&&sources.size<=100&&sources.distinct().size==sources.size,"invalid_observation_source")
        val ids=JSONArray();sources.forEach{ids.put(Values.id(it.id))}
        val value=JSONObject(requestOwned(observationSession(),"POST","/sms/observations/processing-status",JSONObject().put("sourceIds",ids)))
        val rows=value.getJSONArray("statuses")
        checkContract(value.getString("groupId")==groupId&&rows.length()==sources.size,"invalid_observation_source")
        return sources.mapIndexed{index,source->
            val row=rows.getJSONObject(index);val status=row.getString("status");val retry=row.getBoolean("canRetry")
            checkContract(row.getString("sourceId")==source.id&&status in setOf("pending","retrying","parsed","needs_review","conflict","duplicate","security","historical","unknown")&&
                (!retry||status in setOf("retrying","needs_review")),"invalid_observation_source")
            source to ObservationProcessing(status,retry)
        }.toMap()
    }
    fun retryObservation(source:SmsSourceRef.Observation,requestId:String):String{
        val id=Values.id(source.id)
        val value=JSONObject(requestOwned(observationSession(),"POST","/sms/observations/$id/retry",JSONObject().put("requestId",requestId)))
        checkContract(value.getString("groupId")==groupId&&value.getString("sourceId")==id&&value.getString("requestId")==requestId&&
            value.getString("result") in setOf("scheduled","not_eligible"),"invalid_observation_source")
        return value.getString("result")
    }
    /** Only an explicitly typed observation can use this audited disclosure path. */
    fun revealObservation(source:SmsSourceRef.Observation,reason:String):ObservationDisclosure {
        val normalized=RawDisclosureInput.reason(reason)?:throw ApiFailure("reason_required",400)
        val id=Values.id(source.id)
        val row=JSONObject(requestOwned(observationSession(),"POST","/sms/observations/$id/reveal",JSONObject().put("reason",normalized).put("displayHintsVersion",1)))
        checkedDto("observationReveal.data",row)
        checkContract(row.getString("sourceKind")=="observation"&&row.getString("sourceId")==id&&row.getString("groupId")==groupId&&
            row.getString("status")=="source_unresolved"&&row.counter("financialEffects")==0L,"invalid_observation_source")
        checkContract(row.has("displayHints"),"invalid_observation_source")
        val body=row.getString("rawBody")
        val hints=if(row.isNull("displayHints"))null else row.getJSONObject("displayHints").let{h->
            val values=h.getJSONArray("hints")
            ObservationHintSet(h.getInt("schemaVersion"),h.getString("kind"),h.getString("profileVersion"),h.getString("profileSha256"),h.getString("bodySha256"),
                (0 until values.length()).map{index->val v=values.getJSONObject(index);ObservationHint(v.getString("kind"),v.getString("text"),v.getInt("start"),v.getInt("end"))})
        }
        checkContract(hints==null||ObservationHintValidation.valid(body,hints),"invalid_observation_source")
        return ObservationDisclosure(source,row.getString("at"),row.getString("sender"),body,hints)
    }
    /** Audited, explicit disclosure only. Never cache/journal the reason or body. */
    fun raw(id:String,reason:String):RawSms{
        val normalized=RawDisclosureInput.reason(reason)?:throw ApiFailure("reason_required",400)
        val witness=ownedSession()
        val j=JSONObject(requestOwned(witness,"POST","/sms/"+Values.id(id)+"/reveal",JSONObject().put("reason",normalized)))
        return RawSms(j.getString("id"),j.getString("sender"),j.getString("at"),j.getString("rawBody"),j.nullString("transactionId"),j.optionalNullString("simLabel"))
    }
}

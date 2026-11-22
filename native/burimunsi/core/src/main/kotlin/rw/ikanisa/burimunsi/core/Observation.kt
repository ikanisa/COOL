package rw.ikanisa.burimunsi.core

import java.time.Instant
import java.util.Locale

/** Sender-scoped inbox intake. Parsing and transaction classification happen
 * on the backend; incoming-only markers must not suppress other MoMo messages. */
object ObservationCandidate {
    private val senderControls=Regex("[\\u0000-\\u001f\\u007f\\u202a-\\u202e\\u2066-\\u2069]")
    // Preserve ordinary multiline SMS text without accepting hidden controls.
    private val bodyControls=Regex("[\\u0000-\\u0008\\u000b\\u000c\\u000e-\\u001f\\u007f\\u202a-\\u202e\\u2066-\\u2069]")
    fun accepts(sender:String,body:String,profile:ReceiptProfile):Boolean {
        if(profile.version.isBlank()||profile.version=="unverified"||profile.senders.isEmpty()||profile.senders.size>30||
            profile.senders.any{it.length>160||it.trim().isEmpty()||it.any{c->c=='\r'||c=='\n'||c=='\u0000'}})return false
        return sender.length in 1..96&&sender==sender.trim()&&!senderControls.containsMatchIn(sender)&&
            profile.senders.any{it.lowercase(Locale.ROOT)==sender.lowercase(Locale.ROOT)}&&
            body.toByteArray(Charsets.UTF_8).size in 1..3000&&!bodyControls.containsMatchIn(body)
    }
}

/** A candidate receipt is evidence only: it does not identify a wallet or a ledger credit. */
data class ObservationProfile(val receipt:ReceiptProfile, val issuedAt:Long, val expiresAt:Long, val legacyHold:Boolean?=null) {
    fun current(now:Long):Boolean = now>0 && issuedAt>0 && issuedAt<=now+300_000 && expiresAt>now &&
        expiresAt>issuedAt && expiresAt-issuedAt<=24L*60*60*1000 && receipt.version.isNotBlank() &&
        receipt.version!="unverified" && receipt.offsetMinutes in -840..840
    fun fingerprint():String {
        val parts=listOf(receipt.version,receipt.offsetMinutes.toString())+
            listOf(receipt.senders,receipt.incomingPrefixes,receipt.currencyAliases,receipt.transactionIdPrefixes)
                .flatMap{values->listOf(values.size.toString())+values.sorted()}
        return Values.sha256(parts.joinToString(""){"${it.length}:$it"})
    }
}

/** These values are retained with a single request ID and resent without alteration. */
data class SmsObservation(
    val requestId:String,
    val rawSender:String,
    val rawBody:String,
    val sourceMode:String,
    val complete:Boolean,
    val capturedAt:String,
    val serviceCentreAt:String?,
    val inboxReceivedAt:String?,
    val subscriptionId:Int?,
    val sourceKey:String?=null,
) {
    override fun toString()="SmsObservation(redacted)"
    fun valid(profile:ObservationProfile, now:Long):Boolean {
        if(!profile.current(now) || runCatching{Values.requestId(requestId)==requestId}.getOrDefault(false).not())return false
        if(rawSender.length !in 1..96 || rawSender!=rawSender.trim() || rawBody.toByteArray(Charsets.UTF_8).size !in 1..3000 ||
            !((sourceMode=="live"&&complete)||(sourceMode=="catch_up"&&!complete&&inboxReceivedAt!=null)) ||
            subscriptionId!=null&&subscriptionId<0 || sourceKey!=null&&
                (sourceMode!="catch_up"||!Regex("[a-f0-9]{64}").matches(sourceKey)))return false
        fun timestamp(value:String?)=value==null||Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]{1,9})?Z").matches(value)&&
            runCatching{Instant.parse(value);true}.getOrDefault(false)
        if(!timestamp(capturedAt)||!timestamp(serviceCentreAt)||!timestamp(inboxReceivedAt))return false
        return ObservationCandidate.accepts(rawSender,rawBody,profile.receipt)
    }

    /** Local parsing is a display hint; the backend still owns financial authority. */
    fun unverifiedFacts(profile:ObservationProfile, now:Long):UnverifiedObservationFacts? {
        if(!valid(profile,now))return null
        val parsed=try{if(complete)ReceiptParser.parse(rawSender,rawBody,true,profile.receipt)
            else ReceiptParser.inboxTextHint(rawSender,rawBody,profile.receipt)}catch(_:ContractFailure){return null}
        return UnverifiedObservationFacts(parsed.amountRwf,parsed.payerNameRaw,parsed.payerPhoneRaw,parsed.atRaw,parsed.ftId,complete)
    }
}

data class UnverifiedObservationFacts(val amountRwf:Long,val payerName:String,val payerPhone:String,val receivedAt:String,val reference:String,val sourceComplete:Boolean) {
    override fun toString()="UnverifiedObservationFacts(redacted)"
}

data class ObservationAck(val requestId:String,val sourceId:String,val bodySha256:String,val status:String,val financialEffects:Int)

/** Metadata used to compare one phone inbox source with its retained Cloud source. */
data class ObservationReconcileRequest(
    val sourceKey:String,val bodySha256:String,val rawSender:String,val serviceCentreAt:String?,
    val inboxReceivedAt:String,val subscriptionId:Int?,
) {
    override fun toString()="ObservationReconcileRequest(redacted)"
}

data class ObservationReconcileReply(val sourceKey:String,val state:String,val sourceId:String?,val latestRecordedSourceId:String?) {
    override fun toString()="ObservationReconcileReply(redacted)"
}
data class ObservationReconcileStatus(val hasPending:Boolean,val hasRecorded:Boolean,val recordedCount:Int,val revision:String,
    val hasUnmatchedCanonical:Boolean)

/** Queue removal requires the server's durable unresolved-source acknowledgment. */
object ObservationAcknowledgement {
    fun matches(observation:SmsObservation, ack:ObservationAck):Boolean =
        ack.requestId==observation.requestId && runCatching{Values.id(ack.sourceId);true}.getOrDefault(false) &&
        ack.bodySha256==Values.sha256(observation.rawBody) && ack.status=="source_unresolved" && ack.financialEffects==0
}

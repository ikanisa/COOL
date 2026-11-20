package com.ikanisa.mmoney.platform

import com.ikanisa.mmoney.data.IntakeIdentity
import kotlin.random.Random

/** Shared actual-production contracts used by the host probe and the pinned JUnit build. */
internal object SmsReliabilityContractCases {
    fun run(): List<String> {
        val names = mutableListOf<String>()
        fun case(name: String, block: () -> Unit) { block(); names += name }
        fun source(a: Any?, b: Any? = null, c: Any? = null, d: Any? = null) = SmsSourcePolicy.broadcast(a,b,c,d)
        fun part(body: String?, sender: String? = "M-Money", time: Long = 1000) = SmsBroadcastPart(sender,body,time)
        fun sms(sub: Int?, slot: Int? = 0, row: String? = null, key: String = "delivery") =
            IncomingSms("M-Money","Exact body",777,sub,slot,row,key,"test")
        fun pdu(sequence: Int = 1, count: Int = 1, reference: Int = 7, wide: Boolean = false,
            header: Boolean = true, dcs: Int = 8): ByteArray {
            val h = if (!header) emptyList() else if (wide) listOf(6,8,4,reference shr 8,reference and 255,count,sequence)
                else listOf(5,0,3,reference,count,sequence)
            val data = h + listOf(0,65)
            return (listOf(0,if(header)64 else 0,2,129,33,0,dcs,98,17,144,33,0,0,128,data.size) + data).map(Int::toByte).toByteArray()
        }
        case("integer_subscription") { check(source(5).subscriptionId == 5) }
        case("legacy_long_subscription") { check(source(null,5L).subscriptionId == 5) }
        case("matching_int_long_extras") { check(source(5,5L).subscriptionId == 5) }
        case("conflicting_subscriptions_unresolved") { check(source(5,6L).subscriptionId == null) }
        case("reserved_default_subscription_unresolved") { check(source(Int.MAX_VALUE).subscriptionId == null) }
        case("negative_subscription_unresolved") { check(source(-1).subscriptionId == null) }
        case("overflow_long_unresolved") { check(source(1L shl 40).subscriptionId == null) }
        case("string_float_boolean_not_coerced") { listOf("5",5.0,true).forEach { check(source(it).subscriptionId == null) } }
        case("invalid_primary_not_hidden") { check(source(-1,5L).subscriptionId == null) }
        case("slot_zero_preserved") { check(source(5,null,0).slotIndex == 0) }
        case("conflicting_slots_unresolved") { check(source(5,null,0,1).slotIndex == null) }
        case("slot_never_becomes_source") { check(source(null,null,1).subscriptionId == null) }
        case("provider_subscription_strict") {
            check(SmsSourcePolicy.providerSubscription("5") == 5)
            listOf("-1","2147483647","99999999999999999999","1.0"," 5","+5","").forEach {
                check(SmsSourcePolicy.providerSubscription(it) == null)
            }
        }
        case("slot_swap_retains_source") { check(IntakeIdentity.sourceKey(sms(5,0)) == IntakeIdentity.sourceKey(sms(5,1))) }
        case("replacement_subscription_new_source") { check(IntakeIdentity.sourceKey(sms(5)) != IntakeIdentity.sourceKey(sms(6))) }
        case("unknown_rows_isolated") { check(IntakeIdentity.sourceKey(sms(null,row="7")) != IntakeIdentity.sourceKey(sms(null,row="8"))) }
        case("unknown_provider_broadcast_isolated") { check(IntakeIdentity.sourceKey(sms(null,key="7")) != IntakeIdentity.sourceKey(sms(null,row="7"))) }
        case("reserved_source_not_cloud_eligible") { check(!IntakeIdentity.hasResolvedSource(sms(Int.MAX_VALUE))) }
        case("unicode_crlf_surrogate_boundaries_exact") {
            val x = SmsBroadcastPolicy.assemble(listOf(part("  é\r"),part("\n00123 "),part("\uD83D"),part("\uDE00  ")),4) as SmsBroadcastDecision.Complete
            check(x.body == "  é\r\n00123 😀  ")
        }
        case("missing_decoded_segment_recovers") { check(SmsBroadcastPolicy.assemble(listOf(part("a"),null),2) == SmsBroadcastDecision.Recover) }
        case("null_body_recovers") { check(SmsBroadcastPolicy.assemble(listOf(part(null)),1) == SmsBroadcastDecision.Recover) }
        case("mixed_sender_ignored") { check(SmsBroadcastPolicy.assemble(listOf(part("a"),part("private","Family")),2) == SmsBroadcastDecision.Ignore) }
        case("byte_not_character_limit") { check(SmsBroadcastPolicy.assemble(listOf(part("é".repeat(32769))),1) == SmsBroadcastDecision.Recover) }
        case("exact_byte_limit_accepted") { check((SmsBroadcastPolicy.assemble(listOf(part("é".repeat(32768))),1) as SmsBroadcastDecision.Complete).body.length == 32768) }
        case("single_deliver_pdu") { check(SmsMultipartEnvelope.order(listOf(pdu(header=false)),"3gpp") == listOf(0)) }
        case("out_of_order_8bit_sorted") { check(SmsMultipartEnvelope.order(listOf(pdu(2,2),pdu(1,2)),"3gpp") == listOf(1,0)) }
        case("out_of_order_16bit_sorted") { check(SmsMultipartEnvelope.order(listOf(pdu(2,2,300,true),pdu(1,2,300,true)),"3gpp") == listOf(1,0)) }
        case("lone_multipart_fragment_recovers") { check(SmsMultipartEnvelope.order(listOf(pdu(1,2)),"3gpp") == null) }
        case("duplicate_sequence_rejected") { check(SmsMultipartEnvelope.order(listOf(pdu(1,2),pdu(1,2)),"3gpp") == null) }
        case("mixed_reference_rejected") { check(SmsMultipartEnvelope.order(listOf(pdu(1,2,7),pdu(2,2,8)),"3gpp") == null) }
        case("mixed_reference_width_rejected") { check(SmsMultipartEnvelope.order(listOf(pdu(1,2),pdu(2,2,7,true)),"3gpp") == null) }
        case("mixed_counts_rejected") { check(SmsMultipartEnvelope.order(listOf(pdu(1,2),pdu(2,3)),"3gpp") == null) }
        case("invalid_sequence_and_count_rejected") { listOf(pdu(0,1),pdu(2,1),pdu(1,0)).forEach { check(SmsMultipartEnvelope.order(listOf(it),"3gpp") == null) } }
        case("multiple_no_concat_recovers") { check(SmsMultipartEnvelope.order(listOf(pdu(header=false),pdu(header=false)),"3gpp") == null) }
        case("unsupported_format_recovers") { listOf(null,"3gpp2","unknown").forEach { check(SmsMultipartEnvelope.order(listOf(pdu()),it) == null) } }
        case("truncated_envelope_rejected") { val x=pdu(); x.indices.forEach { check(SmsMultipartEnvelope.order(listOf(x.copyOf(it)),"3gpp") == null) } }
        case("unsupported_dcs_recovers") { listOf(0x20,0xc0,0x0c).forEach { check(SmsMultipartEnvelope.order(listOf(pdu(dcs=it)),"3gpp") == null) } }
        case("4000_malformed_envelopes_do_not_throw") { val rng=Random(83109); repeat(4000) { val x=ByteArray(rng.nextInt(0,200));rng.nextBytes(x);SmsMultipartEnvelope.order(listOf(x),"3gpp") } }
        case("receipt_is_callback_not_service_centre") {
            val x=SmsObservationFactory.broadcast(SmsBroadcastDecision.Complete("M-Money","Exact",1000),source(5),9999)
            check(x.receivedAt==9999L && x.method=="broadcast" && x.body=="Exact")
        }
        case("delivery_identity_survives_callback_clock_rollback") {
            val x=SmsBroadcastDecision.Complete("M-Money","Exact",1000)
            val a=SmsObservationFactory.broadcast(x,source(5),9000);val b=SmsObservationFactory.broadcast(x,source(5),100)
            check(a.deliveryKey==b.deliveryKey && a.receivedAt!=b.receivedAt)
        }
        case("delivery_identity_separates_sources") {
            val x=SmsBroadcastDecision.Complete("M-Money","Exact",1000)
            check(SmsObservationFactory.broadcast(x,source(5),100).deliveryKey!=SmsObservationFactory.broadcast(x,source(6),100).deliveryKey)
        }
        case("history_start_inclusive_end_exclusive") {
            val q=SmsHistoryQuery(100,200,100,-1);check(q.accepts(100,0));check(q.accepts(199,1));check(!q.accepts(99,1));check(!q.accepts(200,1))
        }
        case("history_equal_timestamp_resume_id") {
            val q=SmsHistoryQuery(100,200,150,7);check(!q.accepts(150,7));check(q.accepts(150,8));check(!q.accepts(149,999));check(q.accepts(151,0))
        }
        case("history_bound_arguments") {
            val q=SmsHistoryQuery(100,200,150,7);check(q.arguments.toList()==listOf("m-money","100","200","150","150","7"));check(q.selection.count{it=='?'}==6)
        }
        case("invalid_overflow_row_and_date_rejected") {
            listOf(null,"-1"," 1","1.0","9223372036854775808").forEach { check(SmsHistoryQuery.nonNegativeLong(it)==null) }
            check(SmsHistoryQuery.nonNegativeLong("0")==0L);check(SmsHistoryQuery.nonNegativeLong(Long.MAX_VALUE.toString())==Long.MAX_VALUE)
        }
        return names
    }
}

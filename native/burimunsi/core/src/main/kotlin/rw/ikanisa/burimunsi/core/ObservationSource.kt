package rw.ikanisa.burimunsi.core

/** Source type is explicit; an ID alone never selects a disclosure endpoint. */
sealed class SmsSourceRef(open val id:String) {
    data class Canonical(override val id:String):SmsSourceRef(id)
    data class Observation(override val id:String):SmsSourceRef(id)
}
data class ObservationListRow(val source:SmsSourceRef.Observation,val groupId:String,val retainedAt:String)
/** Processing state is distinct from receipt sync and never implies a payment. */
data class ObservationProcessing(val status:String,val canRetry:Boolean)
/** Audited list content lives only in the active screen's memory. */
data class SmsListContent(val sender:String,val body:String) {
    override fun toString()="SmsListContent(redacted)"
}
object SmsListSearch {
    fun matches(id:String,content:SmsListContent?,query:String):Boolean {
        if(query.isBlank())return true
        val wanted=query.lowercase(java.util.Locale.ROOT)
        return listOf(id,content?.sender.orEmpty(),content?.body.orEmpty()).joinToString(" ").lowercase(java.util.Locale.ROOT).contains(wanted)
    }
}
data class ObservationHint(val kind:String,val text:String,val start:Int,val end:Int)
data class ObservationHintSet(val schemaVersion:Int,val kind:String,val profileVersion:String,val profileSha256:String,
    val bodySha256:String,val hints:List<ObservationHint>) {
    override fun toString()="ObservationHintSet(redacted)"
}
/** Hints quote only the exact retained text; they never assert a wallet or credit. */
object ObservationHintValidation {
    fun valid(body:String,value:ObservationHintSet):Boolean {
        if(value.schemaVersion!=1||value.kind!="partial_inbox_display_only"||value.profileVersion.isBlank()||
            value.profileVersion.length>128||!Regex("[a-f0-9]{64}").matches(value.profileSha256)||
            value.bodySha256!=Values.sha256(body)||value.hints.size !in 1..2||
            value.hints.map{it.kind}.toSet().size!=value.hints.size)return false
        fun boundary(index:Int)=index==0||index==body.length||
            !(Character.isHighSurrogate(body[index-1])&&Character.isLowSurrogate(body[index]))
        return value.hints.all{hint->
            hint.kind in setOf("quoted_incoming_amount","quoted_reference")&&
                hint.start>=0&&hint.end>hint.start&&hint.end<=body.length&&
                boundary(hint.start)&&boundary(hint.end)&&body.substring(hint.start,hint.end)==hint.text
        }
    }
}
data class ObservationDisclosure(val source:SmsSourceRef.Observation,val retainedAt:String,val sender:String,val rawBody:String,
    val displayHints:ObservationHintSet?=null) {
    override fun toString()="ObservationDisclosure(redacted)"
}

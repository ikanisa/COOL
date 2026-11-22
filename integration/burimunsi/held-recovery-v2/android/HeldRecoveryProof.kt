package rw.ikanisa.burimunsi.core

data class HeldObservationAck(val observation:ObservationAck,val autoProcessing:String)
/** An ACK lookup never grants permission to resend the mutating request. */
data class HeldRecoveryResolution(val requestId:String,val sourceKey:String,val bodySha256:String,val state:String,
    val sourceId:String?,val autoProcessing:String,val financialEffects:Int,val retryAllowed:Boolean) {
    override fun toString()="HeldRecoveryResolution(redacted)"
    fun validFor(value:SmsObservation):Boolean = requestId==value.requestId&&sourceKey==value.sourceKey&&
        bodySha256==Values.sha256(value.rawBody)&&financialEffects==0&&!retryAllowed&&when(state){
            "acknowledged"->sourceId?.let{source->runCatching{Values.id(source)==source}.getOrDefault(false)}==true&&autoProcessing=="held"
            "unconfirmed"->sourceId==null&&autoProcessing=="unknown"
            else->false
        }
}

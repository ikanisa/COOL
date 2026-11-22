package rw.ikanisa.burimunsi.core

/** Runtime extension for a canonical state added after the frozen prototype. */
object PaymentPresentation {
    fun payment(value:String?):FinancialPresentation = when(value){
        "corrected" -> FinancialPresentation("Corrected","history","warn",false,false)
        "recorded" -> FinancialPresentation("Transaction recorded","check","info",false,false)
        else -> Presentation.payment(value)
    }
    fun payment(value:Payment):FinancialPresentation = when {
        value.state=="recorded"&&value.outcome=="failed" -> FinancialPresentation("Failed","alert","bad",false,false)
        value.state=="recorded"&&value.outcome=="pending" -> FinancialPresentation("Pending","clock","warn",false,false)
        else -> payment(value.state)
    }
    /** Only an actual successful incoming contribution can be allocated. */
    fun canAllocate(value:Payment)=payment(value.state).canAllocate&&value.direction=="incoming"&&
        value.outcome=="successful"&&value.amountRwf!=null&&value.ftId!=null
    fun directionLabel(value:String)=when(value){
        "incoming"->"Incoming"
        "outgoing"->"Outgoing"
        "reversal"->"Reversal"
        else->"Other"
    }
    fun outcomeLabel(value:String)=when(value){
        "successful"->"Successful"
        "failed"->"Failed"
        "pending"->"Pending"
        else->"Unknown"
    }
}

package rw.ikanisa.burimunsi.export

import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.core.export.*
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.data.RecordReadScope
import rw.ikanisa.burimunsi.gateway.GatewayPort
import java.time.Instant
import java.time.ZoneId

/** Fetches complete, authorized online pages. It never reads message bodies or derives balances. */
internal class ListingExportData(private val repository:NativeRepository,private val gateway:GatewayPort) {
    data class Snapshot(val table:ExportTable,val validateLocal:()->Unit={})
    fun collect(target:ListingTarget,query:ListingQuery,memberId:String?,paymentId:String?,scope:RecordReadScope,
        generatedAt:Instant,zone:ZoneId,check:()->Unit,progress:(Int,Int)->Unit):Snapshot {
        query.validated(target)
        var firstAsOf:String?=null
        fun <T> pages(id:(T)->String,read:(String?)->Page<T>):List<T> {
            check();repository.validateRecordReadScope(scope)
            var page=read(null)
            if(firstAsOf==null)firstAsOf=page.asOf
            checkContract(page.totalCount in 0..20_000,"export_limit")
            checkContract(page.items.map(id).toSet().size==page.items.size&&page.items.size<=page.totalCount,"invalid_page")
            checkContract((page.nextCursor==null)==(page.items.size==page.totalCount),"invalid_page")
            val seen=mutableSetOf<String>()
            if(target !in setOf(ListingTarget.SMS,ListingTarget.OBSERVATIONS))progress(page.items.size,page.totalCount)
            while(page.nextCursor!=null){
                check();repository.validateRecordReadScope(scope)
                val cursor=page.nextCursor!!;checkContract(seen.add(cursor),"invalid_page")
                val next=read(cursor)
                checkContract(next.nextCursor==null||next.nextCursor !in seen,"invalid_page")
                page=PageIntegrity.append(page,next,id)
                if(target !in setOf(ListingTarget.SMS,ListingTarget.OBSERVATIONS))progress(page.items.size,page.totalCount)
            }
            check();repository.validateRecordReadScope(scope)
            return page.items
        }
        fun text(value:String?)=value?.let{ExportCell.Text(it)}?:ExportCell.Blank
        fun money(value:Long?)=value?.let{ExportCell.Money(it,"RWF")}?:ExportCell.Blank
        fun date(value:String):ExportCell=runCatching{ExportCell.DateTime(Instant.parse(value))}.getOrElse{ExportCell.Text(value)}
        fun columns(vararg names:String)=names.mapIndexed{index,name->ExportColumn("c$index",name,if(name.contains("name",true))3 else 2)}
        var localCheck:()->Unit={}
        val (title,cols,rows)=when(target){
            ListingTarget.PAYMENTS->{
                val values=pages<Payment>({it.id}){repository.payments(query,it,memberId,scope)}
                Triple(if(memberId==null)"Transactions" else "Member transactions",
                    columns("Date","Payer name","MoMo number","Principal (RWF)","Fee (RWF)","Wallet balance after (RWF)","Direction","Outcome","Record state","FT ID","Member MoMo"),
                    values.map{p->listOf(date(p.atRaw),text(p.payerNameRaw),text(p.payerPhoneRaw),money(p.amountRwf),money(p.feeRwf),money(p.walletBalanceAfterRwf),text(p.direction),text(p.outcome),text(p.state),text(p.ftId),text(p.memberPhone))})
            }
            ListingTarget.MEMBERS->{
                val values=pages<Member>({it.id}){repository.members(query,it,scope)}
                Triple("Members",columns("Name","MoMo number","Member balance (RWF)","Active","Member ID"),
                    values.map{m->listOf(text(m.name),text(m.phone),money(m.balanceRwf),ExportCell.Boolean(m.active),text(m.id))})
            }
            ListingTarget.LEDGER->{
                val id=memberId?:throw ContractFailure("record_unavailable")
                val values=pages<LedgerRow>({it.id}){repository.ledger(id,query,it,scope)}
                Triple("Member ledger",columns("Date","Signed amount (RWF)","FT ID","Payer name","State","Transaction ID"),
                    values.map{v->listOf(date(v.atRaw),money(v.amountRwf),text(v.ftId),text(v.payerNameRaw),text(v.state),text(v.transactionId))})
            }
            ListingTarget.STAFF->{
                val values=pages<StaffAccount>({it.id}){repository.staff(query,it,scope)}
                Triple("Staff",columns("Name","Login phone","Active","Permissions","Account ID"),
                    values.map{v->listOf(text(v.name),text(v.phone),ExportCell.Boolean(v.active),text(v.capabilities.sorted().joinToString(", ")),text(v.id))})
            }
            ListingTarget.AUDIT->{
                val values=pages<AuditRow>({it.id}){repository.audit(query,it,scope)}
                Triple("Activity log",columns("Date","Action","Event ID"),values.map{v->listOf(date(v.at),text(v.action),text(v.id))})
            }
            ListingTarget.HISTORY->{
                val id=paymentId?:throw ContractFailure("record_unavailable")
                val values=pages<PaymentEvent>({it.id}){repository.paymentHistory(id,query,it,scope)}
                Triple("Contribution history",columns("Recorded at","Event kind","Signed amount (RWF)","Member ID","Transaction ID","Event ID"),
                    values.map{v->listOf(date(v.recordedAt),text(v.kind),money(v.amountRwf),text(v.memberId),text(v.transactionId),text(v.id))})
            }
            ListingTarget.SMS,ListingTarget.OBSERVATIONS->{
                // This is an index of retained sources, not a bulk raw-message disclosure.
                data class Metadata(val at:String,val kind:String,val id:String,val sender:String?,val status:String?,val transaction:String?)
                val metadata=mutableListOf<Metadata>()
                if(target==ListingTarget.SMS&&query.filter!="queued"&&gateway.bound()){
                    pages<SmsRow>({it.id}){repository.sms(query,it,scope)}.forEach{metadata+=Metadata(it.at,"Canonical",it.id,it.sender,it.state,it.transactionId)}
                }
                if(target==ListingTarget.OBSERVATIONS||query.filter=="all"){
                    val oq=query.copy(filter="all")
                    pages<ObservationListRow>({it.source.id}){repository.observationPage(oq,it,scope)}.forEach{metadata+=Metadata(it.retainedAt,"Observation",it.source.id,null,null,null)}
                }
                if(target==ListingTarget.SMS&&query.filter in setOf("all","queued")){
                    val queued=gateway.queuedObservations("")?.let{it.copy(items=it.items.map{row->row.copy(preview="")})}?:throw ContractFailure("queue_unavailable")
                    fun matches(v:QueuedObservationRow):Boolean {
                        val at=runCatching{Instant.parse(v.at)}.getOrNull()?:return false
                        return (query.fromAt==null||at>=Instant.parse(query.fromAt))&&(query.untilAt==null||at<Instant.parse(query.untilAt))&&
                            (query.q.isBlank()||listOf(v.id,v.sender).any{it.contains(query.q,true)})
                    }
                    queued.items.filter(::matches).forEach{metadata+=Metadata(it.at,"Queued on this phone",it.id,it.sender,"queued",null)}
                    localCheck={checkContract(gateway.publishQueued(queued){},"cursor_stale")}
                    localCheck()
                }
                checkContract(metadata.size<=20_000,"export_limit")
                val sorted=metadata.sortedWith(compareBy<Metadata>{Instant.parse(it.at)}.thenBy{it.kind}.thenBy{it.id}).let{if(query.sort==ListingSort.NEWEST)it.reversed()else it}
                Triple("SMS source metadata",columns("Date","Source kind","Source ID","Sender","Status","Transaction ID"),
                    sorted.map{v->listOf(date(v.at),text(v.kind),text(v.id),text(v.sender),text(v.status),text(v.transaction))})
            }
        }
        check();repository.validateRecordReadScope(scope);localCheck()
        val details=mutableListOf(ExportDetail("Collection",repository.boundCollectionId?:throw ContractFailure("session_changed")),
            ExportDetail("Scope",if(target in setOf(ListingTarget.SMS,ListingTarget.OBSERVATIONS))"Authorized source metadata; message text and previews omitted" else "All matching authorized records"),
            ExportDetail("Snapshot read",firstAsOf?:generatedAt.toString()),ExportDetail("Rows",rows.size.toString()),
            ExportDetail("Sort",query.sort.wire))
        query.queryValues(target).filterKeys{it !in setOf("sort")}.filterValues{it.isNotBlank()&&it!="all"}.forEach{(k,v)->details+=ExportDetail(k,v)}
        memberId?.let{details+=ExportDetail("Member ID",it)};paymentId?.let{details+=ExportDetail("Transaction ID",it)}
        val table=ExportTable("BuriMunsi · $title",generatedAt,zone,details,cols,rows)
        table.validate(cancelled={try{check();false}catch(_:Exception){true}})
        return Snapshot(table,localCheck)
    }
}

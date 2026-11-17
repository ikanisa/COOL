package rw.ikanisa.burimunsi.listingdownloadtests

import android.app.Application
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import rw.ikanisa.burimunsi.ui.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.core.export.*
import rw.ikanisa.burimunsi.data.*
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Real controller/collector/encoders with synthetic repository and document-provider boundaries. */
fun main()=runBlocking {
    var checks=0
    fun ck(label:String,value:Boolean){check(value){label};println("PASS $label");checks++}
    val root=Files.createTempDirectory("burimunsi-download-checks").toFile()
    val directory=java.io.File(root,"burimunsi-exports")
    val m=BuriViewModel(Application())
    var picker:BuriViewModel.DownloadRequest?=null
    fun take()=m.takeDownloadRequest().also{if(it!=null)picker=it}
    fun destination(write:((java.io.File,()->Unit)->Unit)?,abort:()->Unit={}){
        val request=picker?:error("No test picker")
        m.downloadDestination(request.id,request.format,write,abort);picker=null
    }
    suspend fun idle(){withTimeout(10_000){while(m.state.busy)delay(2)};delay(25);withTimeout(10_000){while(m.state.busy)delay(2)}}
    suspend fun prepared(){withTimeout(10_000){while(m.exportFeedback?.phase==UiExportPhase.PREPARING||m.state.busy)delay(2)}}
    try{
        idle();m.onForeground();idle()
        var rendered:ExportTable?=null
        m.configureDownloads(directory){format,table,file,cancelled->
            rendered=table
            file.outputStream().use{when(format){ExportFormat.XLSX->XlsxEncoder.write(table,it,cancelled);ExportFormat.CSV->CsvEncoder.write(table,it,cancelled);ExportFormat.PDF->it.write("synthetic-pdf-boundary".toByteArray())}}
        }
        Fixture.paged={target,cursor,_,_->
            val count=if(target=="PAYMENTS")151 else 1
            val ids=if(cursor==null)(1..minOf(count,100)).map{"row-$it"}else(101..count).map{"row-$it"}
            Page(ids,if(count>100&&cursor==null)"page-2"else null,count,"revision-stable","2026-11-14T14:00:00Z")
        }
        m.navigate(Route.PAYMENTS);idle()
        val selected=ListingQuery(q="payer",filter="allocated",sort=ListingSort.AMOUNT_DESC,
            minRwf=100,maxRwf=50_000,fromAt="2026-11-01T00:00:00Z",untilAt="2026-12-01T00:00:00Z",direction="incoming",outcome="successful",credit="credited")
        m.openSheet(Sheet.FILTERS);idle();m.applyListingQuery(selected);idle()
        ck("filter apply restores origin and sends every selected selector",m.state.sheet==null&&m.listingQuery==selected&&Fixture.listingQueries.last().query==selected)
        m.openSheet(Sheet.FILTERS);idle();m.resetListingQuery()
        ck("reset is a filter draft until Apply",m.listingQuery==ListingQuery.defaultsFor(ListingTarget.PAYMENTS))
        m.closeSheet();idle()
        ck("cancelling filter reset preserves active selectors and existing rows",m.listingQuery==selected&&m.state.payments?.totalCount==151)
        m.prepareDownload(ExportFormat.XLSX);prepared()
        ck("Excel preparation fetches all matching pages, not only the visible hundred",rendered?.rowCount==151&&m.state.payments?.items?.size==100&&m.exportFeedback?.phase==UiExportPhase.CHOOSING_DESTINATION)
        val request=take()
        ck("document picker is consumed exactly once with a genuine XLSX MIME",request?.format==ExportFormat.XLSX&&request.fileName.endsWith(".xlsx")&&take()==null)
        val output=java.io.File(root,"saved.xlsx");var aborted=0
        m.onBackground()
        destination({file,check->check();file.copyTo(output);check()},{aborted++})
        ck("destination result waits behind foreground session validation",!output.exists()&&m.screenGate==ScreenGate.BACKGROUND)
        m.onForeground();idle()
        ck("provider close confirms success and removes only the private temporary file",m.exportFeedback?.phase==UiExportPhase.COMPLETE&&output.readBytes().take(2)==listOf(80.toByte(),75.toByte())&&directory.listFiles().isNullOrEmpty()&&aborted==0)
        ck("all export pages use the same selected filters and sort",Fixture.listingQueries.filter{it.target==ListingTarget.PAYMENTS}.all{it.query==selected||it.query==ListingQuery()})
        m.dismissExportFeedback();m.prepareDownload(ExportFormat.XLSX);prepared();take()
        destination({_,_->throw java.io.IOException("synthetic provider failure")},{aborted++});idle()
        ck("write failure is never reported as saved and removes the new partial destination",m.exportFeedback?.phase==UiExportPhase.FAILED&&aborted==1&&directory.listFiles().isNullOrEmpty())
        m.dismissExportFeedback();m.prepareDownload(ExportFormat.PDF);prepared();take();destination(null)
        ck("picker cancellation has no success or retained private file",m.exportFeedback?.phase==UiExportPhase.CANCELLED&&directory.listFiles().isNullOrEmpty())
        m.prepareDownload(ExportFormat.XLSX);prepared();val oldPicker=take()!!;m.cancelExport()
        m.prepareDownload(ExportFormat.PDF);prepared()
        ck("cancelled outstanding picker prevents a replacement download",m.downloadRequest==null&&!m.canExportListing)
        var staleWrites=0;var staleAborts=0
        m.downloadDestination(oldPicker.id,oldPicker.format,{_,_->staleWrites++},{staleAborts++});delay(50)
        ck("late retired picker result is discarded without writing",staleWrites==0&&staleAborts==1&&m.canExportListing)
        m.prepareDownload(ExportFormat.PDF);prepared();val newPicker=take()!!
        m.downloadDestination(oldPicker.id,oldPicker.format,{_,_->staleWrites++},{staleAborts++});delay(50)
        ck("stale request ID cannot consume or save a newer format picker",staleWrites==0&&staleAborts==2&&!m.canExportListing)
        m.downloadDestination(newPicker.id,newPicker.format,null)
        picker=null
        Fixture.paged={_,cursor,_,_->Page(listOf(if(cursor==null)"row-1"else"row-2"),if(cursor==null)"page-2"else null,2,if(cursor==null)"before"else"changed","2026-11-14T14:00:00Z")}
        m.prepareDownload(ExportFormat.XLSX);prepared()
        ck("a changed dataset rejects the entire download rather than publishing partial rows",m.exportFeedback?.phase==UiExportPhase.FAILED&&m.downloadRequest==null&&directory.listFiles().isNullOrEmpty())
        Fixture.paged={_,_,_,_->Page(listOf("member-1"),null,1,"one","2026-11-14T14:00:00Z")}
        m.openSheet(Sheet.STAFF);idle();m.openSheet(Sheet.FILTERS);idle()
        ck("staff filter overlay keeps its own listing origin",m.listingTarget==ListingTarget.STAFF)
        val staffQuery=ListingQuery.defaultsFor(ListingTarget.STAFF).copy(q="staff",active="active",sort=ListingSort.PHONE_ASC)
        m.applyListingQuery(staffQuery);idle()
        ck("staff Apply returns to Staff without replacing the parent payment query",m.state.sheet==Sheet.STAFF&&m.listingQuery==staffQuery&&Fixture.listingQueries.last().target==ListingTarget.STAFF)
        m.closeSheet();idle();ck("closing Staff restores the selected transaction context",m.listingQuery==selected)
        m.prepareDownload(ExportFormat.XLSX);prepared();take()
        Fixture.refreshedRole=Role.STAFF;Fixture.refreshedCaps=setOf(Capability.READ.key)
        var writes=0
        destination({_,_->writes++},{aborted++});idle()
        ck("role changes during the final live check prevent any provider write",writes==0&&m.exportFeedback?.phase!=UiExportPhase.COMPLETE&&aborted==2&&directory.listFiles().isNullOrEmpty())
        Fixture.refreshedRole=null;Fixture.refreshedCaps=null
        m.refreshSession();idle()
        m.navigate(Route.MEMBER,"member-1");idle()
        m.prepareDownload(ExportFormat.CSV);prepared()
        ck("member CSV preserves the explicitly labelled full ledger capability",rendered?.title?.contains("Member ledger")==true&&rendered?.rowCount==1&&Fixture.listingQueries.last().target==ListingTarget.LEDGER&&Fixture.listingQueries.last().query==ListingQuery.defaultsFor(ListingTarget.LEDGER)&&m.exportFeedback?.phase==UiExportPhase.CHOOSING_DESTINATION)
        m.cancelExport()
        val entered=CountDownLatch(1);val release=CountDownLatch(1)
        m.configureDownloads(directory){_,_,_,cancelled->entered.countDown();check(release.await(5,TimeUnit.SECONDS));if(cancelled())throw ExportCancelledException()}
        m.prepareDownload(ExportFormat.XLSX)
        withContext(Dispatchers.IO){check(entered.await(5,TimeUnit.SECONDS))}
        m.onBackground();release.countDown();idle()
        ck("unexpected background cancels preparation and clears its private file",m.downloadRequest==null&&m.exportFeedback?.phase==UiExportPhase.CANCELLED&&directory.listFiles().isNullOrEmpty())
        val recreated=BuriViewModel(Application())
        try{
            withTimeout(10_000){while(recreated.state.busy)delay(2)}
            recreated.restoreDownloadPicker(900,ExportFormat.XLSX)
            recreated.onForeground();delay(50);withTimeout(10_000){while(recreated.state.busy)delay(2)}
            recreated.navigate(Route.PAYMENTS);delay(50);withTimeout(10_000){while(recreated.state.busy)delay(2)}
            recreated.prepareDownload(ExportFormat.XLSX)
            ck("fresh process restores a retired picker lease before allowing replacement",!recreated.canExportListing&&recreated.downloadRequest==null)
            var orphanWrites=0;var orphanAborts=0
            recreated.downloadDestination(900,ExportFormat.XLSX,{_,_->orphanWrites++},{orphanAborts++})
            delay(50)
            ck("restored orphan picker is discarded without any exported bytes",orphanWrites==0&&orphanAborts==1&&recreated.canExportListing)
        }finally{recreated.viewModelScope.cancel()}
        ck("filtering and downloads never submit or reconcile financial commands",Fixture.mutations==0&&Fixture.reconciles==0)
    }finally{m.viewModelScope.cancel();root.deleteRecursively()}
    println("RESULT: $checks listing/download controller checks passed; Android rendering and live provider behavior require their separate device gates.")
}

package rw.ikanisa.burimunsi.export

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import rw.ikanisa.burimunsi.core.export.*
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.OutputStream
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import java.util.zip.ZipInputStream
import javax.xml.parsers.DocumentBuilderFactory

/** Actual Android PDF/ZIP parsing and rendering, synthetic scoped snapshots only.
 * No SAF, app/session/SMS/backend state or external storage permission is used.
 */
@RunWith(AndroidJUnit4::class)
class ExportRenderingTest {
    private val context get()=InstrumentationRegistry.getInstrumentation().targetContext
    private fun sample(count:Int)=ExportTable("Synthetic member statement",Instant.parse("2026-11-14T12:00:00Z"),ZoneId.of("Africa/Kigali"),
        listOf(ExportDetail("Filters","Active · date descending"),ExportDetail("Scope","Synthetic account only")),
        listOf(ExportColumn("id","Reference"),ExportColumn("name","Member",2),ExportColumn("amount","Amount",2),ExportColumn("date","Date"),ExportColumn("note","Details",2)),
        (0 until count).map{i->listOf(ExportCell.Text("ID-${count-i}"),ExportCell.Text("Kanyange Élodie"),ExportCell.Money(10000L+i,"RWF"),ExportCell.Date(LocalDate.of(2026,11,14)),ExportCell.Text("Muraho — こんにちは\nComplete second line"))})
    private class Target(private val failAfter:Int=Int.MAX_VALUE):OutputStream(){
        val data=ByteArrayOutputStream();var closed=false
        override fun write(value:Int){if(data.size()>=failAfter)throw IOException("Synthetic output unavailable");data.write(value)}
        override fun write(value:ByteArray,offset:Int,length:Int){for(i in offset until offset+length)write(value[i].toInt())}
        override fun close(){closed=true}
    }
    private fun withFile(bytes:ByteArray,body:(File)->Unit){
        val directory=File(context.cacheDir,"export-render-test-"+UUID.randomUUID());check(directory.mkdir())
        try{val file=File(directory,"synthetic.pdf");file.writeBytes(bytes);body(file)}finally{directory.deleteRecursively()}
    }

    @Test fun nativePdfOpensAndRendersEveryPageWithoutLosingTheSuppliedRowCount(){
        val target=Target();val table=sample(80);val result=NativePdfExporter(context).write(table,target)
        assertEquals(80,result.rowCount);assertEquals(target.data.size().toLong(),result.bytesWritten);assertFalse(target.closed)
        assertTrue(result.pageCount!!>1)
        withFile(target.data.toByteArray()){file->
            PdfRenderer(ParcelFileDescriptor.open(file,ParcelFileDescriptor.MODE_READ_ONLY)).use{reader->
                assertEquals(result.pageCount!!.toInt(),reader.pageCount)
                for(index in 0 until reader.pageCount){
                    reader.openPage(index).use{page->
                        val bitmap=Bitmap.createBitmap(page.width,page.height,Bitmap.Config.ARGB_8888)
                        try{
                            bitmap.eraseColor(Color.WHITE);page.render(bitmap,null,null,PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            var marked=0
                            for(y in 0 until bitmap.height step 3)for(x in 0 until bitmap.width step 3)
                                if(bitmap.getPixel(x,y)!=Color.WHITE)marked++
                            assertTrue("Every PDF page has actual rendered text/artwork",marked>150)
                        }finally{bitmap.recycle()}
                    }
                }
            }
        }
        val wide=ExportTable("Synthetic detailed listing",Instant.EPOCH,ZoneId.of("UTC"),emptyList(),
            (0 until 11).map{ExportColumn("c$it","Column $it")},listOf((0 until 11).map{ExportCell.Text("Full value $it")}))
        val wideOutput=Target();NativePdfExporter(context).write(wide,wideOutput)
        withFile(wideOutput.data.toByteArray()){file->PdfRenderer(ParcelFileDescriptor.open(file,ParcelFileDescriptor.MODE_READ_ONLY)).use{reader->
            reader.openPage(0).use{page->assertEquals(1191,page.width);assertEquals(842,page.height)}
        }}
        // Deliberately retained synthetic-only output for independent host text
        // extraction before the isolated test package is removed. Rendering
        // pixels alone cannot detect a PDF ToUnicode map that loses digits.
        val textTable=ExportTable("Synthetic transaction text regression",Instant.parse("2026-11-14T12:00:00Z"),ZoneId.of("Africa/Kigali"),
            listOf(ExportDetail("Collection","01234567-89ab-cdef-0123-456789abcdef"),ExportDetail("Scope","Synthetic scoped test records only"),
                ExportDetail("Sort","amount_desc"),ExportDetail("filter","posted")),
            listOf("Date","Payer name","MoMo number","Principal (RWF)","Fee (RWF)","Wallet balance after (RWF)","Direction","Outcome","Record state","FT ID","Member MoMo")
                .mapIndexed{i,label->ExportColumn("c$i",label,if(i==1)3 else 2)},
            listOf(
                listOf(ExportCell.DateTime(Instant.parse("2026-11-14T12:34:56.789Z")),ExportCell.Text("Synthetic office filter ffi"),ExportCell.Text("+250000000001"),
                    ExportCell.Money(9876543210,"RWF"),ExportCell.Money(1023456789,"RWF"),ExportCell.Money(9988776655,"RWF"),
                    ExportCell.Text("incoming"),ExportCell.Text("successful"),ExportCell.Text("allocated"),ExportCell.Text("FT-0123456789-9876543210-0123456789"),ExportCell.Text("+250000000001")),
                listOf(ExportCell.DateTime(Instant.parse("2026-11-14T11:23:45.678Z")),ExportCell.Text("Synthetic affine literal"),ExportCell.Text("+250000000002"),
                    ExportCell.Money(1234567890,"RWF"),ExportCell.Money(1000,"RWF"),ExportCell.Money(1122334455,"RWF"),
                    ExportCell.Text("incoming"),ExportCell.Text("successful"),ExportCell.Text("allocated"),ExportCell.Text("FT-9876543210-0123456789-9876543210"),ExportCell.Text("+250000000002"))))
        val textFile=File(context.cacheDir,"native-export-text-regression.pdf")
        textFile.outputStream().use{NativePdfExporter(context).write(textTable,it)}
        android.system.Os.chmod(textFile.absolutePath,0x180) // 0600, private synthetic fixture only.
        assertTrue(textFile.length()>0)
    }

    @Test fun zeroRecordPdfStillOpensAsOneCompletePage(){
        val target=Target();val result=NativePdfExporter(context).write(sample(0),target)
        assertEquals(0,result.rowCount);assertEquals(1,result.pageCount)
        withFile(target.data.toByteArray()){file->PdfRenderer(ParcelFileDescriptor.open(file,ParcelFileDescriptor.MODE_READ_ONLY)).use{assertEquals(1,it.pageCount)}}
    }

    @Test fun nativePdfPageBudgetFailsBeforeAnyFileBytesInsteadOfDroppingRows(){
        val target=Target();val failure=runCatching{NativePdfExporter(context).write(sample(80),target,limits=ExportLimits(maxPdfPages=1))}.exceptionOrNull()
        assertTrue(failure is ExportFailure&&failure.code==ExportFailureCode.PDF_PAGE_LIMIT)
        assertEquals(0,target.data.size());assertFalse(target.closed)
    }

    @Test fun nativePdfCancellationAndOutputFailureNeverCloseTheCallerOrReturnSuccess(){
        val cancelled=Target();val error=runCatching{NativePdfExporter(context).write(sample(3),cancelled,{true})}.exceptionOrNull()
        assertTrue(error is ExportCancelledException);assertEquals(0,cancelled.data.size());assertFalse(cancelled.closed)
        val failed=Target(64);val writeError=runCatching{NativePdfExporter(context).write(sample(3),failed)}.exceptionOrNull()
        assertTrue(writeError is IOException);assertEquals(64,failed.data.size());assertFalse(failed.closed)
        val interrupted=Target();val interruptedError=runCatching{
            NativePdfExporter(context).write(sample(3),interrupted,{interrupted.data.size()>0})
        }.exceptionOrNull()
        assertTrue(interruptedError is ExportCancelledException);assertTrue(interrupted.data.size()>0);assertFalse(interrupted.closed)
        val limited=Target();val limitError=runCatching{
            NativePdfExporter(context).write(sample(3),limited,limits=ExportLimits(maxOutputBytes=64))
        }.exceptionOrNull()
        assertTrue(limitError is ExportFailure&&limitError.code==ExportFailureCode.OUTPUT_LIMIT)
        assertTrue(limited.data.size()<=64);assertFalse(limited.closed)
        val complete=Target();val result=NativePdfExporter(context).write(sample(3),complete)
        assertEquals(3,result.rowCount);assertTrue(result.bytesWritten>64);assertFalse(complete.closed)
    }

    @Test fun nativeWorkbookContainsReadableXmlAndLiteralFormulaLookingText(){
        val table=ExportTable("Synthetic listing",Instant.EPOCH,ZoneId.of("UTC"),emptyList(),listOf(ExportColumn("reference","Reference")),listOf(listOf(ExportCell.Text("=1+1")),listOf(ExportCell.Text("Élodie\nMuraho"))))
        val target=Target();val result=XlsxEncoder.write(table,target);assertEquals(2,result.rowCount);assertFalse(target.closed)
        var parts=0;var sheet=""
        ZipInputStream(ByteArrayInputStream(target.data.toByteArray())).use{zip->while(true){
            val entry=zip.nextEntry?:break;val bytes=zip.readBytes();parts++
            DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(ByteArrayInputStream(bytes))
            if(entry.name=="xl/worksheets/sheet1.xml")sheet=bytes.toString(Charsets.UTF_8)
        }}
        assertEquals(8,parts);assertTrue(sheet.contains("t=\"inlineStr\""));assertTrue(sheet.contains("=1+1"));assertFalse(sheet.contains("<f>"))
    }
}

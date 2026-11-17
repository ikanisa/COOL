package rw.ikanisa.burimunsi.core.export

import java.io.IOException
import java.io.OutputStream
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeFormatterBuilder
import java.time.temporal.ChronoField
import java.util.Locale
import java.util.Collections

/** Renderers consume this already-authorized complete snapshot; they never fetch or sort data. */
enum class ExportFormat(val extension:String,val mimeType:String) {
    CSV("csv","text/csv"),
    XLSX("xlsx","application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
    PDF("pdf","application/pdf")
}

data class ExportDetail(val label:String,val value:String)
data class ExportColumn(val key:String,val label:String,val widthWeight:Int=1)

sealed class ExportCell {
    object Blank:ExportCell()
    data class Text(val value:String):ExportCell()
    data class Number(val value:BigDecimal):ExportCell()
    /** Conversion from declared minor units is formatting, never a derived financial balance. */
    data class Money(val amountMinor:Long,val currency:String,val fractionDigits:Int=0):ExportCell()
    data class Date(val value:LocalDate):ExportCell()
    data class DateTime(val value:Instant):ExportCell()
    data class Boolean(val value:kotlin.Boolean):ExportCell()
}

class ExportTable(
    val title:String,
    val generatedAt:Instant,
    val zoneId:ZoneId,
    details:List<ExportDetail>,
    columns:List<ExportColumn>,
    rows:List<List<ExportCell>>,
    val emptyMessage:String="No records",
) {
    val details:List<ExportDetail> = Collections.unmodifiableList(ArrayList(details))
    val columns:List<ExportColumn> = Collections.unmodifiableList(ArrayList(columns))
    val rows:List<List<ExportCell>> = Collections.unmodifiableList(rows.map{Collections.unmodifiableList(ArrayList(it))})
    val rowCount:Int get()=rows.size
    fun validate(limits:ExportLimits=ExportLimits(),cancelled:()->kotlin.Boolean={false}) {
        ExportWriteControl(limits,cancelled).validate(this)
    }
}

data class ExportLimits(
    val maxRows:Int=20_000,
    val maxColumns:Int=16,
    val maxCells:Int=200_000,
    val maxInputUtf8Bytes:Long=16L*1024*1024,
    val maxOutputBytes:Long=32L*1024*1024,
    val maxCellChars:Int=32_767,
    val maxPdfPages:Int=500,
) {
    init { require(maxRows>=0&&maxColumns in 1..16_384&&maxCells>=0&&maxInputUtf8Bytes>0&&
        maxOutputBytes>0&&maxCellChars in 1..32_767&&maxPdfPages>0) }
}
data class ExportRenderResult(val bytesWritten:Long,val rowCount:Int,val pageCount:Int?=null)

enum class ExportFailureCode(val description:String) {
    INVALID_TABLE("The export contains invalid table data."),
    ROW_LIMIT("This export exceeds the row limit. Narrow the filters and try again."),
    COLUMN_LIMIT("This export has too many columns."),
    CELL_LIMIT("This export exceeds the cell limit. Narrow the filters and try again."),
    INPUT_LIMIT("This export contains too much data. Narrow the filters and try again."),
    TEXT_LIMIT("An export value is too long to include safely."),
    OUTPUT_LIMIT("The export file exceeds the size limit. Narrow the filters and try again."),
    NUMERIC_PRECISION("A value exceeds Excel's exact numeric precision. Export it as text or use PDF."),
    DATE_RANGE("An export date is outside the supported date range."),
    PDF_PAGE_LIMIT("This PDF exceeds the page limit. Narrow the filters and try again."),
    PDF_LAYOUT("A value or table is too wide or tall for a readable PDF."),
    UNSUPPORTED_GLYPH("A character cannot be rendered by the PDF font. Use Excel for this export."),
    ASSET_UNAVAILABLE("The approved export artwork could not be loaded."),
}
class ExportFailure(val code:ExportFailureCode):IOException(code.description)
class ExportCancelledException:IOException("Export cancelled")

/** Shared bounded I/O for the JVM workbook and Android PDF renderer. Never owns the target. */
class ExportWriteControl(val limits:ExportLimits,private val cancelled:()->kotlin.Boolean) {
    fun checkpoint(){if(Thread.currentThread().isInterrupted||cancelled())throw ExportCancelledException()}
    fun validate(table:ExportTable) {
        checkpoint()
        if(table.rows.size>limits.maxRows)throw ExportFailure(ExportFailureCode.ROW_LIMIT)
        if(table.columns.isEmpty()||table.columns.size>limits.maxColumns)throw ExportFailure(ExportFailureCode.COLUMN_LIMIT)
        if(table.rows.size.toLong()*table.columns.size>limits.maxCells)throw ExportFailure(ExportFailureCode.CELL_LIMIT)
        if(table.title.isBlank()||table.emptyMessage.isBlank()||table.details.size>24||
            table.columns.any{!Regex("[A-Za-z][A-Za-z0-9_-]{0,63}").matches(it.key)||it.label.isBlank()||it.widthWeight !in 1..20}||
            table.columns.map{it.key}.toSet().size!=table.columns.size||table.details.any{it.label.isBlank()})
            throw ExportFailure(ExportFailureCode.INVALID_TABLE)
        if(runCatching{table.generatedAt.atZone(table.zoneId).year in 1900..9999}.getOrDefault(false)!=true)
            throw ExportFailure(ExportFailureCode.DATE_RANGE)
        var bytes=0L
        fun text(value:String){
            if(value.length>limits.maxCellChars)throw ExportFailure(ExportFailureCode.TEXT_LIMIT)
            var index=0
            while(index<value.length){
                val c=value[index]
                if(Character.isHighSurrogate(c)){
                    if(index+1>=value.length||!Character.isLowSurrogate(value[index+1]))throw ExportFailure(ExportFailureCode.INVALID_TABLE)
                    bytes+=4;index+=2
                }else{
                    if(Character.isLowSurrogate(c)||(c<' '&&c !in "\t\n\r")||c=='\uFFFE'||c=='\uFFFF')
                        throw ExportFailure(ExportFailureCode.INVALID_TABLE)
                    bytes+=when{c.code<128->1;c.code<2048->2;else->3};index++
                }
                if(bytes>limits.maxInputUtf8Bytes)throw ExportFailure(ExportFailureCode.INPUT_LIMIT)
            }
        }
        text(table.title);text(table.emptyMessage);text(table.zoneId.id)
        table.details.forEach{text(it.label);text(it.value)}
        table.columns.forEach{text(it.label)}
        table.rows.forEach{row->
            checkpoint()
            if(row.size!=table.columns.size)throw ExportFailure(ExportFailureCode.INVALID_TABLE)
            row.forEach{cell->
                when(cell){
                    is ExportCell.Text->text(cell.value)
                    is ExportCell.Number->{
                        if(cell.value.precision()>50||cell.value.scale() !in -12..8)throw ExportFailure(ExportFailureCode.INVALID_TABLE)
                        text(cell.value.toPlainString())
                    }
                    is ExportCell.Money->{
                        if(!Regex("[A-Z]{3}").matches(cell.currency)||cell.fractionDigits !in 0..4)throw ExportFailure(ExportFailureCode.INVALID_TABLE)
                        text(cell.amountMinor.toString());text(cell.currency)
                    }
                    is ExportCell.Date->{
                        if(cell.value.year !in 1900..9999)throw ExportFailure(ExportFailureCode.DATE_RANGE)
                        text(cell.value.toString())
                    }
                    is ExportCell.DateTime->{
                        val local=runCatching{cell.value.atZone(table.zoneId)}.getOrElse{throw ExportFailure(ExportFailureCode.DATE_RANGE)}
                        if(local.year !in 1900..9999)throw ExportFailure(ExportFailureCode.DATE_RANGE)
                        text(cell.value.toString())
                    }
                    is ExportCell.Boolean->text(if(cell.value)"TRUE"else"FALSE")
                    ExportCell.Blank->Unit
                }
            }
        }
        checkpoint()
    }
    fun output(target:OutputStream)=BoundedExportOutput(target,this)
}

class BoundedExportOutput(private val target:OutputStream,private val control:ExportWriteControl):OutputStream() {
    var bytesWritten:Long=0;private set
    private fun admit(count:Int){
        control.checkpoint()
        if(count<0||bytesWritten>control.limits.maxOutputBytes-count)throw ExportFailure(ExportFailureCode.OUTPUT_LIMIT)
    }
    override fun write(value:Int){admit(1);target.write(value);bytesWritten++}
    override fun write(bytes:ByteArray,offset:Int,length:Int){
        if(offset<0||length<0||offset>bytes.size-length)throw IndexOutOfBoundsException()
        admit(length);target.write(bytes,offset,length);bytesWritten+=length
    }
    override fun flush(){control.checkpoint();target.flush()}
    override fun close(){flush()} // The caller owns and commits/closes its stream.
}

object ExportValues {
    private val day=DateTimeFormatter.ofPattern("yyyy-MM-dd")
    private val moment=DateTimeFormatterBuilder().appendPattern("yyyy-MM-dd HH:mm:ss")
        .appendFraction(ChronoField.NANO_OF_SECOND,3,9,true).toFormatter(Locale.ROOT)
    fun numeric(cell:ExportCell):BigDecimal=when(cell){
        is ExportCell.Number->cell.value
        is ExportCell.Money->BigDecimal.valueOf(cell.amountMinor,cell.fractionDigits)
        else->throw ExportFailure(ExportFailureCode.INVALID_TABLE)
    }
    fun fractionDigits(cell:ExportCell):Int=when(cell){
        is ExportCell.Number->cell.value.scale().coerceAtLeast(0)
        is ExportCell.Money->cell.fractionDigits
        else->0
    }
    fun display(cell:ExportCell,zone:ZoneId):String=when(cell){
        ExportCell.Blank->""
        is ExportCell.Text->cell.value
        is ExportCell.Boolean->if(cell.value)"TRUE"else"FALSE"
        is ExportCell.Date->day.format(cell.value)
        is ExportCell.DateTime->moment.format(cell.value.atZone(zone))
        is ExportCell.Number->grouped(cell.value,cell.value.scale().coerceAtLeast(0))
        is ExportCell.Money->grouped(numeric(cell),cell.fractionDigits)+" "+cell.currency
    }
    private fun grouped(value:BigDecimal,scale:Int):String {
        val plain=value.setScale(scale).toPlainString();val parts=plain.split('.',limit=2)
        val sign=if(parts[0].startsWith('-'))"-"else"";val digits=parts[0].removePrefix("-")
        return sign+digits.reversed().chunked(3).joinToString(",").reversed()+if(parts.size==2)"."+parts[1]else""
    }
}

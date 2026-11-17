package rw.ikanisa.burimunsi.exporttests

import rw.ikanisa.burimunsi.core.export.*
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream
import java.math.BigDecimal
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.zip.ZipInputStream
import javax.xml.parsers.DocumentBuilderFactory

private var checks=0
private fun test(name:String,body:()->Unit){body();checks++;println("PASS $name")}
private fun table(rows:List<List<ExportCell>>,columns:List<ExportColumn> = listOf(ExportColumn("value","Value",2)))=
    ExportTable("Synthetic statement",Instant.parse("2026-11-14T12:00:00Z"),ZoneId.of("Africa/Kigali"),
        listOf(ExportDetail("Filters","Active · date descending")),columns,rows)
private fun xlsx(t:ExportTable):ByteArray=ByteArrayOutputStream().also{XlsxEncoder.write(t,it)}.toByteArray()
private fun parts(bytes:ByteArray):Map<String,ByteArray>{
    val result=linkedMapOf<String,ByteArray>()
    ZipInputStream(ByteArrayInputStream(bytes)).use{zip->while(true){val entry=zip.nextEntry?:break;check(result.put(entry.name,zip.readBytes())==null)}}
    return result
}
private fun xml(bytes:ByteArray)=DocumentBuilderFactory.newInstance().apply{
    isNamespaceAware=true;setFeature("http://apache.org/xml/features/disallow-doctype-decl",true)
    setFeature("http://xml.org/sax/features/external-general-entities",false)
    setFeature("http://xml.org/sax/features/external-parameter-entities",false)
}.newDocumentBuilder().parse(ByteArrayInputStream(bytes))
private fun fails(code:ExportFailureCode,body:()->Unit){
    val failure=runCatching(body).exceptionOrNull();check(failure is ExportFailure&&failure.code==code){"Expected $code; got ${failure?.javaClass?.simpleName}"}
}
private class WatchedOutput(private val failAfter:Int=Int.MAX_VALUE):OutputStream(){
    val bytes=ByteArrayOutputStream();var closed=false
    override fun write(value:Int){if(bytes.size()>=failAfter)throw IOException("Synthetic output failure");bytes.write(value)}
    override fun write(value:ByteArray,offset:Int,length:Int){for(i in offset until offset+length)write(value[i].toInt())}
    override fun close(){closed=true}
}
fun main(args:Array<String>){
    test("immutable snapshot copies caller columns, details and nested row lists"){
        val columns=mutableListOf(ExportColumn("value","Value"));val row=mutableListOf<ExportCell>(ExportCell.Text("before"))
        val rows=mutableListOf<List<ExportCell>>(row);val details=mutableListOf(ExportDetail("Filter","active"))
        val t=ExportTable("Test",Instant.EPOCH,ZoneId.of("UTC"),details,columns,rows)
        row[0]=ExportCell.Text("after");rows.clear();columns.clear();details.clear()
        check(t.rowCount==1&&t.rows.single().single()==ExportCell.Text("before")&&t.columns.size==1&&t.details.size==1)
        check(runCatching{(t.rows as MutableList).clear()}.isFailure)
        check(runCatching{(t.rows[0] as MutableList).clear()}.isFailure)
    }
    test("workbook is an OOXML ZIP with complete well-formed related parts"){
        val p=parts(xlsx(table(listOf(listOf(ExportCell.Text("Jean & Munsi <test> \"quoted\""))))))
        check(p.keys==setOf("[Content_Types].xml","_rels/.rels","docProps/core.xml","docProps/app.xml","xl/workbook.xml","xl/_rels/workbook.xml.rels","xl/styles.xml","xl/worksheets/sheet1.xml"))
        p.values.forEach(::xml)
        check(p["[Content_Types].xml"]!!.toString(Charsets.UTF_8).contains("spreadsheetml.sheet.main+xml"))
    }
    test("formula-looking text stays literal inline text without formulas or external links"){
        val values=listOf("=SUM(A1:A9)","+250700000001"," \t@SUM(A1)","-not a number","_x000A_","one\r\ntwo\t😀")
        val p=parts(xlsx(table(values.map{listOf(ExportCell.Text(it))})));val document=xml(p.getValue("xl/worksheets/sheet1.xml"))
        check(document.getElementsByTagNameNS("*","f").length==0&&p.keys.none{it.contains("externalLink")})
        val cells=document.getElementsByTagNameNS("*","c")
        for(i in 0 until cells.length){val e=cells.item(i) as org.w3c.dom.Element;check(e.getAttribute("t")=="inlineStr")}
        val text=p.getValue("xl/worksheets/sheet1.xml").toString(Charsets.UTF_8)
        check("_x005F_x000A_" in text&&"&#13;" in text&&"😀" in text)
    }
    test("money, decimals and booleans are genuine typed values with exact display units"){
        val t=table(listOf(listOf(ExportCell.Money(123456,"RWF"),ExportCell.Number(BigDecimal("-12.50")),ExportCell.Boolean(true))),
            listOf(ExportColumn("money","Amount"),ExportColumn("number","Decimal"),ExportColumn("flag","Active")))
        val p=parts(xlsx(t));val text=p.getValue("xl/worksheets/sheet1.xml").toString(Charsets.UTF_8)
        check("<v>123456</v>" in text&&"<v>-12.50</v>" in text&&"t=\"b\"><v>1</v>" in text)
        check("RWF" in p.getValue("xl/styles.xml").toString(Charsets.UTF_8))
        check(ExportValues.display(ExportCell.Money(-123456,"USD",2),ZoneId.of("UTC"))=="-1,234.56 USD")
    }
    test("dates use the real Excel1900 calendar without its fictitious leap day"){
        val t=table(listOf(LocalDate.of(1900,1,1),LocalDate.of(1900,2,28),LocalDate.of(1900,3,1)).map{listOf(ExportCell.Date(it))})
        val text=parts(xlsx(t)).getValue("xl/worksheets/sheet1.xml").toString(Charsets.UTF_8)
        check(listOf("<v>1</v>","<v>59</v>","<v>61</v>").all{it in text})
    }
    test("the entire supplied nonalphabetical snapshot remains ordered with declared record count"){
        val values=(0 until 1303).map{"row-${(it*37)%1303}"};val p=parts(xlsx(table(values.map{listOf(ExportCell.Text(it))})))
        val d=xml(p.getValue("xl/worksheets/sheet1.xml"));val texts=d.getElementsByTagNameNS("*","t")
        val actual=(0 until texts.length).map{texts.item(it).textContent}
        check(actual.takeLast(values.size)==values&&"Records: 1303" in actual)
    }
    test("empty data is a genuine zero-record export with headers and explicit empty state"){
        val p=parts(xlsx(table(emptyList())));val text=p.getValue("xl/worksheets/sheet1.xml").toString(Charsets.UTF_8)
        check("Records: 0" in text&&"No records" in text&&"Value" in text)
    }
    test("row/cell/input/text limits fail before writing rather than truncating"){
        val t=table(listOf(listOf(ExportCell.Text("abc")),listOf(ExportCell.Text("def"))));val out=ByteArrayOutputStream()
        fails(ExportFailureCode.ROW_LIMIT){XlsxEncoder.write(t,out,limits=ExportLimits(maxRows=1))};check(out.size()==0)
        fails(ExportFailureCode.CELL_LIMIT){XlsxEncoder.write(t,out,limits=ExportLimits(maxCells=1))};check(out.size()==0)
        fails(ExportFailureCode.INPUT_LIMIT){XlsxEncoder.write(t,out,limits=ExportLimits(maxInputUtf8Bytes=3))};check(out.size()==0)
        fails(ExportFailureCode.TEXT_LIMIT){XlsxEncoder.write(t,out,limits=ExportLimits(maxCellChars=3))};check(out.size()==0)
    }
    test("output budget, I/O failure and cancellation never return a completed result or close the caller"){
        val t=table((0..20).map{listOf(ExportCell.Text("synthetic-$it"))});val small=WatchedOutput()
        fails(ExportFailureCode.OUTPUT_LIMIT){XlsxEncoder.write(t,small,limits=ExportLimits(maxOutputBytes=64))};check(!small.closed)
        val failed=WatchedOutput(31);check(runCatching{XlsxEncoder.write(t,failed)}.exceptionOrNull() is IOException);check(!failed.closed)
        val cancelled=WatchedOutput();check(runCatching{XlsxEncoder.write(t,cancelled,{true})}.exceptionOrNull() is ExportCancelledException);check(cancelled.bytes.size()==0&&!cancelled.closed)
        val mid=WatchedOutput();check(runCatching{XlsxEncoder.write(t,mid,{mid.bytes.size()>80})}.exceptionOrNull() is ExportCancelledException);check(!mid.closed)
    }
    test("successful exports leave the caller open and return exact bytes and data-row count"){
        val out=WatchedOutput();val result=XlsxEncoder.write(table(listOf(listOf(ExportCell.Text("test")))),out)
        check(!out.closed&&result.bytesWritten==out.bytes.size().toLong()&&result.rowCount==1&&result.pageCount==null)
    }
    test("invalid Unicode/control data and malformed row shapes fail without replacing text"){
        for(value in listOf("broken\uD800","bad\u0000value","bad\u000Bvalue","bad\uFFFF"))
            fails(ExportFailureCode.INVALID_TABLE){xlsx(table(listOf(listOf(ExportCell.Text(value)))))}
        fails(ExportFailureCode.INVALID_TABLE){xlsx(table(listOf(emptyList())))}
    }
    test("Excel precision rejects unrepresentable numbers while text identifiers remain exact"){
        fails(ExportFailureCode.NUMERIC_PRECISION){xlsx(table(listOf(listOf(ExportCell.Number(BigDecimal("9007199254740991"))))))}
        fails(ExportFailureCode.NUMERIC_PRECISION){xlsx(table(listOf(listOf(ExportCell.Money(9007199254740991,"RWF")))))}
        check("9007199254740991" in parts(xlsx(table(listOf(listOf(ExportCell.Text("9007199254740991")))))).getValue("xl/worksheets/sheet1.xml").toString(Charsets.UTF_8))
    }
    test("identical supplied snapshots produce deterministic workbook bytes"){
        val t=table(listOf(listOf(ExportCell.Text("same"))));check(xlsx(t).contentEquals(xlsx(t)))
    }
    test("CSV quotes comma/newline/Unicode, blocks whitespace-prefixed formulas and keeps numbers numeric"){
        val t=table(listOf(listOf(ExportCell.Text(" \t=SUM(A1)"),ExportCell.Text("line, \"quoted\"\nMuraho 😀"),ExportCell.Money(-1234,"RWF"))),
            listOf(ExportColumn("unsafe","Text"),ExportColumn("unicode","Details"),ExportColumn("money","Amount")))
        val out=WatchedOutput();val result=CsvEncoder.write(t,out);val bytes=out.bytes.toByteArray();val text=bytes.toString(Charsets.UTF_8)
        check(bytes.take(3)==listOf(0xEF.toByte(),0xBB.toByte(),0xBF.toByte()))
        check("\"' \t=SUM(A1)\"" in text&&"\"line, \"\"quoted\"\"\nMuraho 😀\"" in text&&text.endsWith(",-1234\r\n"))
        check("Amount (RWF)" in text&&!out.closed&&result.bytesWritten==bytes.size.toLong())
    }
    test("all CSV formula prefixes remain text even behind invisible spacing"){
        val values=listOf("\t=1+1"," \r\n+cmd","\u00A0-2","\u200E@SUM(A1)","\uFEFF=1")
        val out=ByteArrayOutputStream();CsvEncoder.write(table(values.map{listOf(ExportCell.Text(it))}),out)
        val text=out.toString(Charsets.UTF_8)
        values.forEach{check("\"'"+it+"\"" in text)}
    }
    test("CSV does not emit ambiguous mixed-currency numbers or Excel-rounded financial values"){
        val out=ByteArrayOutputStream()
        fails(ExportFailureCode.INVALID_TABLE){CsvEncoder.write(table(listOf(listOf(ExportCell.Money(1,"RWF")),listOf(ExportCell.Money(1,"USD")))),out)}
        check(out.size()==0)
        fails(ExportFailureCode.NUMERIC_PRECISION){CsvEncoder.write(table(listOf(listOf(ExportCell.Money(9007199254740991,"RWF")))),out)}
        check(out.size()==0)
        val failed=WatchedOutput(20);check(runCatching{CsvEncoder.write(table(listOf(listOf(ExportCell.Text("test")))),failed)}.exceptionOrNull() is IOException)
        check(!failed.closed)
    }
    test("date range fails clearly and submillisecond source timestamps remain exact text"){
        fails(ExportFailureCode.DATE_RANGE){xlsx(table(listOf(listOf(ExportCell.Date(LocalDate.of(1899,12,31))))))}
        fails(ExportFailureCode.DATE_RANGE){xlsx(table(listOf(listOf(ExportCell.DateTime(Instant.MAX)))))}
        val precise=ExportCell.DateTime(Instant.parse("2026-11-14T12:00:00.123456789Z"))
        val text=parts(xlsx(table(listOf(listOf(precise))))).getValue("xl/worksheets/sheet1.xml").toString(Charsets.UTF_8)
        check("2026-11-14 14:00:00.123456789" in text&&"inlineStr" in text)
    }
    if(args.isNotEmpty()){
        val dir=Path.of(args[0]);Files.createDirectories(dir)
        val cols=listOf(ExportColumn("reference","Reference",2),ExportColumn("member","Member",2),ExportColumn("amount","Amount",2),ExportColumn("day","Date"),ExportColumn("time","Timestamp",2),ExportColumn("active","Active"),ExportColumn("notes","Notes",3))
        val rows=(0 until 180).map{i->listOf(ExportCell.Text(if(i==0)"=1+1"else"REF-${180-i}"),ExportCell.Text("Uwimana Élodie · こんにちは"),ExportCell.Money(123456+i.toLong(),"RWF"),ExportCell.Date(LocalDate.of(2026,11,14)),ExportCell.DateTime(Instant.parse("2026-11-14T12:34:56.789Z")),ExportCell.Boolean(i%2==0),ExportCell.Text("First line\nSecond line, \"quoted\" & complete 😀"))}
        val t=table(rows,cols)
        Files.newOutputStream(dir.resolve("synthetic-export.xlsx")).use{XlsxEncoder.write(t,it)}
        Files.newOutputStream(dir.resolve("synthetic-export.csv")).use{CsvEncoder.write(t,it)}
    }
    println("PASS $checks export checks; synthetic snapshots only, no Android/SAF/backend acceptance claimed")
}

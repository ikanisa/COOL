package rw.ikanisa.burimunsi.core.export

import java.io.OutputStream
import java.io.OutputStreamWriter
import java.io.Writer
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Minimal genuine SpreadsheetML workbook. Text is always inlineStr, never a formula. */
object XlsxEncoder {
    private const val NS="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    private data class NumericStyle(val scale:Int,val currency:String?)

    fun write(table:ExportTable,output:OutputStream,cancelled:()->Boolean={false},limits:ExportLimits=ExportLimits()):ExportRenderResult {
        val control=ExportWriteControl(limits,cancelled);control.validate(table)
        val header=6+table.details.size
        if(table.rowCount.toLong()+header>1_048_576)throw ExportFailure(ExportFailureCode.ROW_LIMIT)
        val formats=linkedMapOf<NumericStyle,Int>()
        table.rows.forEach{row->control.checkpoint();row.forEach{cell->
            if(cell is ExportCell.Number||cell is ExportCell.Money){
                val n=ExportValues.numeric(cell)
                if(n.stripTrailingZeros().precision()>15)throw ExportFailure(ExportFailureCode.NUMERIC_PRECISION)
                val key=NumericStyle(ExportValues.fractionDigits(cell),(cell as? ExportCell.Money)?.currency)
                formats.getOrPut(key){9+formats.size}
            }
        }}
        val bounded=control.output(output)
        ZipOutputStream(bounded).use{zip->
            fun entry(name:String,body:(Writer)->Unit){
                control.checkpoint();zip.putNextEntry(ZipEntry(name).apply{time=0L})
                val writer=OutputStreamWriter(zip,Charsets.UTF_8);body(writer);writer.flush();zip.closeEntry()
            }
            entry("[Content_Types].xml"){w->w.write("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>""")}
            entry("_rels/.rels"){w->w.write("""<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>""")}
            entry("docProps/core.xml"){w->w.write("""<?xml version="1.0" encoding="UTF-8"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>${xml(table.title)}</dc:title><dc:creator>BuriMunsi</dc:creator><cp:lastModifiedBy>BuriMunsi</cp:lastModifiedBy><dcterms:created xsi:type="dcterms:W3CDTF">${xml(table.generatedAt.toString())}</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">${xml(table.generatedAt.toString())}</dcterms:modified></cp:coreProperties>""")}
            entry("docProps/app.xml"){w->w.write("""<?xml version="1.0" encoding="UTF-8"?><Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>BuriMunsi</Application></Properties>""")}
            entry("xl/workbook.xml"){w->w.write("""<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="$NS" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><workbookPr date1904="0"/><sheets><sheet name="BuriMunsi" sheetId="1" r:id="rId1"/></sheets><definedNames><definedName name="_xlnm.Print_Titles" localSheetId="0">BuriMunsi!${'$'}$header:${'$'}$header</definedName></definedNames></workbook>""")}
            entry("xl/_rels/workbook.xml.rels"){w->w.write("""<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>""")}
            entry("xl/styles.xml"){w->styles(w,formats)}
            entry("xl/worksheets/sheet1.xml"){w->sheet(w,table,header,formats,control)}
            control.checkpoint()
        }
        control.checkpoint()
        return ExportRenderResult(bounded.bytesWritten,table.rowCount)
    }

    private fun sheet(w:Writer,table:ExportTable,header:Int,formats:Map<NumericStyle,Int>,control:ExportWriteControl){
        val lastColumn=column(table.columns.lastIndex);val lastRow=header+maxOf(table.rowCount,1)
        w.write("""<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="$NS"><sheetPr><pageSetUpPr fitToPage="1"/></sheetPr><dimension ref="A1:$lastColumn$lastRow"/><sheetViews><sheetView workbookViewId="0"><pane ySplit="$header" topLeftCell="A${header+1}" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="18"/><cols>""")
        val widths=table.columns.map{(12.0*it.widthWeight).coerceIn(14.0,70.0)}
        widths.forEachIndexed{i,width->w.write("""<col min="${i+1}" max="${i+1}" width="$width" customWidth="1"/>""")}
        w.write("</cols><sheetData>")
        fun metadata(row:Int,value:String,style:Int,height:Int){
            val lines=value.split('\n').sumOf{maxOf(1,kotlin.math.ceil(it.length/widths.sum()).toInt())}
            val required=maxOf(height,lines*14+8)
            if(required>409)throw ExportFailure(ExportFailureCode.TEXT_LIMIT)
            w.write("""<row r="$row" ht="$required" customHeight="1">""");textCell(w,"A$row",value,style);w.write("</row>")
        }
        metadata(1,"BuriMunsi",1,32)
        metadata(2,table.title,2,30)
        metadata(3,"Generated: ${table.generatedAt} · Time zone: ${table.zoneId.id}",3,24)
        metadata(4,"Records: ${table.rowCount}",3,22)
        table.details.forEachIndexed{i,d->metadata(i+5,d.label+": "+d.value,3,30)}
        w.write("""<row r="$header" ht="30" customHeight="1">""")
        table.columns.forEachIndexed{i,c->textCell(w,column(i)+header,c.label,4)};w.write("</row>")
        table.rows.forEachIndexed{index,row->
            control.checkpoint();val r=header+index+1
            val lines=row.mapIndexed{i,c->ExportValues.display(c,table.zoneId).split('\n').sumOf{line->maxOf(1,kotlin.math.ceil(line.length/widths[i]).toInt())}}.maxOrNull()?:1
            val height=(lines*16+6).coerceIn(22,409)
            w.write("""<row r="$r" ht="$height" customHeight="1">""")
            row.forEachIndexed{i,cell->
                val ref=column(i)+r
                when(cell){
                    ExportCell.Blank->w.write("""<c r="$ref" s="5"/>""")
                    is ExportCell.Text->textCell(w,ref,cell.value,5)
                    is ExportCell.Boolean->w.write("""<c r="$ref" s="6" t="b"><v>${if(cell.value)1 else 0}</v></c>""")
                    is ExportCell.Date->w.write("""<c r="$ref" s="7"><v>${serial(cell.value)}</v></c>""")
                    is ExportCell.DateTime->{
                        if(cell.value.nano%1_000_000!=0){
                            // Excel dates cannot retain nanoseconds. Preserve the exact
                            // timestamp as text instead of silently rounding it.
                            textCell(w,ref,ExportValues.display(cell,table.zoneId),5)
                        }else{
                            val local=cell.value.atZone(table.zoneId).toLocalDateTime()
                            val fraction=BigDecimal.valueOf(local.toLocalTime().toNanoOfDay()/1_000_000).divide(BigDecimal(86_400_000),10,RoundingMode.HALF_UP)
                            w.write("""<c r="$ref" s="8"><v>${BigDecimal(serial(local.toLocalDate())).add(fraction).toPlainString()}</v></c>""")
                        }
                    }
                    else->{
                        val key=NumericStyle(ExportValues.fractionDigits(cell),(cell as? ExportCell.Money)?.currency)
                        w.write("""<c r="$ref" s="${formats.getValue(key)}"><v>${ExportValues.numeric(cell).toPlainString()}</v></c>""")
                    }
                }
            };w.write("</row>")
        }
        if(table.rows.isEmpty()){w.write("""<row r="${header+1}" ht="24" customHeight="1">""");textCell(w,"A${header+1}",table.emptyMessage,5);w.write("</row>")}
        w.write("</sheetData>")
        w.write("""<autoFilter ref="A$header:$lastColumn${header+table.rowCount}"/>""")
        if(table.columns.size>1){
            val merged=(1..4).toList()+table.details.indices.map{it+5}
            w.write("""<mergeCells count="${merged.size}">""");merged.forEach{r->w.write("""<mergeCell ref="A$r:$lastColumn$r"/>""")};w.write("</mergeCells>")
        }
        w.write("""<printOptions horizontalCentered="1"/><pageMargins left="0.3" right="0.3" top="0.4" bottom="0.4" header="0.2" footer="0.2"/><pageSetup paperSize="9" orientation="${if(table.columns.size>5)"landscape"else"portrait"}" fitToWidth="1" fitToHeight="0"/><headerFooter><oddFooter>&amp;LBuriMunsi&amp;RPage &amp;P of &amp;N</oddFooter></headerFooter></worksheet>""")
    }

    private fun styles(w:Writer,formats:Map<NumericStyle,Int>){
        w.write("""<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="$NS"><numFmts count="${2+formats.size}"><numFmt numFmtId="164" formatCode="yyyy-mm-dd"/><numFmt numFmtId="165" formatCode="yyyy-mm-dd hh:mm:ss.000"/>""")
        formats.entries.forEachIndexed{i,e->
            val pattern="#,##0"+(if(e.key.scale==0)""else"."+"0".repeat(e.key.scale))+(e.key.currency?.let{" \"$it\""}?:"")
            w.write("""<numFmt numFmtId="${166+i}" formatCode="${xml(pattern)}"/>""")
        }
        w.write("""</numFmts><fonts count="5"><font><sz val="11"/><color rgb="FF17171B"/><name val="Arial"/><family val="2"/></font><font><b/><sz val="20"/><color rgb="FFFFFFFF"/><name val="Arial"/></font><font><b/><sz val="16"/><color rgb="FF17171B"/><name val="Arial"/></font><font><sz val="9"/><color rgb="FF5D6068"/><name val="Arial"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Arial"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF46228A"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FFE2E3E7"/></bottom><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="${9+formats.size}">""")
        fun xf(font:Int=0,fill:Int=0,border:Int=0,num:Int=0,align:String="left"){
            w.write("""<xf numFmtId="$num" fontId="$font" fillId="$fill" borderId="$border" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="$align" vertical="center" wrapText="1"/></xf>""")
        }
        xf();xf(1,2);xf(2);xf(3);xf(4,2,1);xf(border=1);xf(border=1,align="center");xf(border=1,num=164);xf(border=1,num=165)
        formats.entries.forEachIndexed{i,_->xf(border=1,num=166+i,align="right")}
        w.write("""</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>""")
    }
    private fun serial(date:LocalDate):Long {
        val days=ChronoUnit.DAYS.between(LocalDate.of(1899,12,31),date)
        return days+if(date>=LocalDate.of(1900,3,1))1 else 0
    }
    private fun column(index:Int):String {
        var n=index+1;val text=StringBuilder()
        while(n>0){n--;text.append(('A'.code+n%26).toChar());n/=26}
        return text.reverse().toString()
    }
    private fun textCell(w:Writer,ref:String,value:String,style:Int){
        // Escape literal OOXML escape-looking sequences before XML escaping.
        val literal=Regex("_x[0-9A-Fa-f]{4}_").replace(value){"_x005F_"+it.value.substring(1)}
        w.write("""<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">${xml(literal)}</t></is></c>""")
    }
    private fun xml(value:String):String=buildString(value.length){value.forEach{c->append(when(c){'&'->"&amp;";'<'->"&lt;";'>'->"&gt;";'\"'->"&quot;";'\r'->"&#13;";else->c.toString()})}}
}

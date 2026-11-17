package rw.ikanisa.burimunsi.core.export

import java.io.OutputStream
import java.io.OutputStreamWriter

/** Compatibility CSV: BOM/UTF-8, exact numeric fields, quoted text and no executable text cells. */
object CsvEncoder {
    fun write(table:ExportTable,output:OutputStream,cancelled:()->Boolean={false},limits:ExportLimits=ExportLimits()):ExportRenderResult {
        val control=ExportWriteControl(limits,cancelled);control.validate(table)
        val currencies=table.columns.indices.map{i->table.rows.mapNotNull{(it[i] as? ExportCell.Money)?.currency}.toSet()}
        if(currencies.any{it.size>1})throw ExportFailure(ExportFailureCode.INVALID_TABLE)
        table.rows.forEach{row->control.checkpoint();row.forEach{cell->
            if((cell is ExportCell.Number||cell is ExportCell.Money)&&ExportValues.numeric(cell).stripTrailingZeros().precision()>15)
                throw ExportFailure(ExportFailureCode.NUMERIC_PRECISION)
        }}
        val bounded=control.output(output)
        bounded.write(byteArrayOf(0xEF.toByte(),0xBB.toByte(),0xBF.toByte()))
        val writer=OutputStreamWriter(bounded,Charsets.UTF_8)
        fun row(cells:List<String>){control.checkpoint();writer.write(cells.joinToString(","));writer.write("\r\n")}
        row(listOf(text("BuriMunsi"),text(table.title)))
        row(listOf(text("Generated"),text(table.generatedAt.toString())))
        row(listOf(text("Time zone"),text(table.zoneId.id)))
        row(listOf(text("Records"),table.rowCount.toString()))
        table.details.forEach{row(listOf(text(it.label),text(it.value)))}
        row(table.columns.mapIndexed{i,column->
            val unit=currencies[i].singleOrNull()
            text(column.label+(if(unit!=null&&!column.label.contains(unit))" ($unit)"else""))
        })
        table.rows.forEach{cells->row(cells.map{cell->when(cell){
            ExportCell.Blank->""
            is ExportCell.Number,is ExportCell.Money->ExportValues.numeric(cell).toPlainString()
            is ExportCell.Boolean->if(cell.value)"TRUE"else"FALSE"
            else->text(ExportValues.display(cell,table.zoneId))
        }})}
        writer.flush();control.checkpoint()
        return ExportRenderResult(bounded.bytesWritten,table.rowCount)
    }
    private fun text(value:String):String {
        val first=value.firstOrNull{!it.isWhitespace()&&!Character.isSpaceChar(it)&&Character.getType(it)!=Character.FORMAT.toInt()}
        val safe=if(first in setOf('=','+','-','@'))"'"+value else value
        return "\""+safe.replace("\"","\"\"")+"\""
    }
}

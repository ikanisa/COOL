package rw.ikanisa.burimunsi.export

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.graphics.text.LineBreaker
import android.text.Layout
import android.text.StaticLayout
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import app.cool.mobile.R
import rw.ikanisa.burimunsi.core.export.*
import java.io.OutputStream
import java.text.BreakIterator
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.max

/** Printable BuriMunsi adaptation: approved wordmark and the actual platform sans-serif
 * used by the native app. No trial/downloaded fonts, source screenshots or new service.
 * This class renders only its supplied immutable snapshot, never permissions or data access.
 */
class NativePdfExporter(context:Context) {
    private val app=context.applicationContext?:context
    fun write(table:ExportTable,output:OutputStream,cancelled:()->Boolean={false},limits:ExportLimits=ExportLimits()):ExportRenderResult {
        val control=ExportWriteControl(limits,cancelled);control.validate(table)
        val body=paint(10.5f);val header=paint(10.5f,true);val title=paint(20f,true);val muted=paint(9f,color=Color.rgb(87,92,103))
        val glyphs=HashSet<String>()
        fun layout(value:String,width:Float,p:TextPaint=body,right:Boolean=false):StaticLayout {
            control.checkpoint()
            val text=value.replace("\r\n","\n").replace('\r','\n')
            val iterator=BreakIterator.getCharacterInstance(Locale.ROOT);iterator.setText(text)
            var start=iterator.first();var end=iterator.next()
            while(end!=BreakIterator.DONE){
                val part=text.substring(start,end)
                if(part.any{!it.isWhitespace()&&Character.getType(it)!=Character.FORMAT.toInt()}&&glyphs.add(part)&&!body.hasGlyph(part))
                    throw ExportFailure(ExportFailureCode.UNSUPPORTED_GLYPH)
                start=end;end=iterator.next()
            }
            return StaticLayout.Builder.obtain(text,0,text.length,p,max(1,width.toInt()))
                .setAlignment(if(right)Layout.Alignment.ALIGN_OPPOSITE else Layout.Alignment.ALIGN_NORMAL)
                .setTextDirection(TextDirectionHeuristics.FIRSTSTRONG_LTR)
                .setIncludePad(true).setLineSpacing(2f,1f)
                .setBreakStrategy(LineBreaker.BREAK_STRATEGY_HIGH_QUALITY)
                .setHyphenationFrequency(Layout.HYPHENATION_FREQUENCY_NONE).build()
        }
        val minimum=FloatArray(table.columns.size){52f}
        table.rows.forEach{row->control.checkpoint();row.forEachIndexed{i,c->
            val text=ExportValues.display(c,table.zoneId)
            when(c){
                is ExportCell.Number,is ExportCell.Money,is ExportCell.Date->minimum[i]=max(minimum[i],ceil(body.measureText(text))+16f)
                is ExportCell.DateTime->minimum[i]=max(minimum[i],text.split(' ').maxOf{ceil(body.measureText(it))}+16f)
                else->Unit
            }
        }}
        val portrait=table.columns.size<=5&&minimum.sum()<=523f
        // Detailed transaction listings use A3 landscape rather than reducing
        // readable type to squeeze eleven or more columns onto A4.
        val wide=table.columns.size>8||minimum.sum()>770f
        val pageWidth=if(wide)1191 else if(portrait)595 else 842
        val pageHeight=if(wide||portrait)842 else 595
        val margin=36f;val tableWidth=pageWidth-2*margin
        if(minimum.sum()>tableWidth)throw ExportFailure(ExportFailureCode.PDF_LAYOUT)
        val spare=tableWidth-minimum.sum();val weight=table.columns.sumOf{it.widthWeight}.toFloat()
        val widths=FloatArray(table.columns.size){i->minimum[i]+spare*table.columns[i].widthWeight/weight}
        val labelLayouts=table.columns.mapIndexed{i,c->layout(c.label,widths[i]-16f,header)}
        val columnHeaderHeight=max(30f,labelLayouts.maxOf{it.height}.toFloat()+14f)
        val titleLayout=layout(table.title,tableWidth,title)
        val generation="Generated ${DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").format(table.generatedAt.atZone(table.zoneId))}\n${table.zoneId.id}"
        val generationLayout=layout(generation,tableWidth-170f,muted,true)
        val metadata=listOf(layout("Records: ${table.rowCount}",tableWidth,muted))+
            table.details.map{layout(it.label+": "+it.value,tableWidth,muted)}
        val titleTop=margin+44f
        val metadataTop=titleTop+titleLayout.height+8f
        val columnTop=metadataTop+metadata.sumOf{it.height+4}+10f
        val firstBodyTop=columnTop+columnHeaderHeight
        val bottom=pageHeight-margin-24f
        if(firstBodyTop+32f>bottom)throw ExportFailure(ExportFailureCode.PDF_LAYOUT)
        val bitmap=BitmapFactory.decodeResource(app.resources,R.drawable.burimunsi_brand_logo,BitmapFactory.Options().apply{inScaled=false})
            ?:throw ExportFailure(ExportFailureCode.ASSET_UNAVAILABLE)
        val document=PdfDocument();var active:PdfDocument.Page?=null
        val fill=Paint(Paint.ANTI_ALIAS_FLAG);val rule=Paint(Paint.ANTI_ALIAS_FLAG).apply{color=Color.rgb(225,228,234);strokeWidth=.6f}
        var pages=0;var y=firstBodyTop;var firstRow=0;var lastRow=0
        fun drawText(value:StaticLayout,x:Float,top:Float){
            val canvas=active!!.canvas;canvas.save()
            try{canvas.translate(x,top);value.draw(canvas)}finally{canvas.restore()}
        }
        fun startPage(nextRow:Int){
            control.checkpoint()
            if(pages>=limits.maxPdfPages)throw ExportFailure(ExportFailureCode.PDF_PAGE_LIMIT)
            pages++;active=document.startPage(PdfDocument.PageInfo.Builder(pageWidth,pageHeight,pages).create())
            val canvas=active!!.canvas;canvas.drawColor(Color.WHITE)
            val logoHeight=32f;val logoWidth=bitmap.width*logoHeight/bitmap.height
            canvas.drawBitmap(bitmap,null,RectF(margin,margin,margin+logoWidth,margin+logoHeight),null)
            drawText(generationLayout,margin+170f,margin)
            drawText(titleLayout,margin,titleTop)
            var top=metadataTop
            metadata.forEach{line->drawText(line,margin,top);top+=line.height+4f}
            fill.color=Color.rgb(242,239,249)
            canvas.drawRect(margin,columnTop,margin+tableWidth,firstBodyTop,fill)
            var x=margin
            labelLayouts.forEachIndexed{i,text->drawText(text,x+8f,columnTop+7f);x+=widths[i]}
            y=firstBodyTop;firstRow=nextRow;lastRow=nextRow
        }
        fun finishPage(){
            val page=active?:return;control.checkpoint()
            val coverage=if(table.rowCount==0)"No records"else"Rows ${firstRow+1}–$lastRow of ${table.rowCount}"
            page.canvas.drawLine(margin,pageHeight-margin-15f,margin+tableWidth,pageHeight-margin-15f,rule)
            drawText(layout("BuriMunsi · $coverage",tableWidth-70f,muted),margin,pageHeight-margin-10f)
            drawText(layout("Page $pages",70f,muted,true),pageWidth-margin-70f,pageHeight-margin-10f)
            document.finishPage(page);active=null
        }
        try{
            startPage(0)
            if(table.rows.isEmpty()){
                val empty=layout(table.emptyMessage,tableWidth-16f)
                if(empty.height+16>bottom-y)throw ExportFailure(ExportFailureCode.PDF_LAYOUT)
                drawText(empty,margin+8f,y+8f)
            }
            table.rows.forEachIndexed{index,row->
                control.checkpoint()
                val cells=row.mapIndexed{i,cell->layout(ExportValues.display(cell,table.zoneId),widths[i]-16f,body,
                    cell is ExportCell.Number||cell is ExportCell.Money)}
                val height=max(30f,cells.maxOf{it.height}.toFloat()+16f)
                if(height>bottom-firstBodyTop)throw ExportFailure(ExportFailureCode.PDF_LAYOUT)
                if(y+height>bottom){finishPage();startPage(index)}
                val canvas=active!!.canvas
                if(index%2==1){fill.color=Color.rgb(249,250,252);canvas.drawRect(margin,y,margin+tableWidth,y+height,fill)}
                var x=margin
                cells.forEachIndexed{i,text->drawText(text,x+8f,y+8f);x+=widths[i]}
                y+=height;lastRow=index+1;canvas.drawLine(margin,y,margin+tableWidth,y,rule)
            }
            finishPage();control.checkpoint()
            val bounded=control.output(output);val nativeOutput=NativeWriteGuard(bounded)
            // Android's native stream adaptor can clear a Java write exception.
            // Preserve its first failure outside JNI before admitting success.
            try{document.writeTo(nativeOutput)}finally{nativeOutput.rethrowFailure()}
            bounded.flush();control.checkpoint()
            return ExportRenderResult(bounded.bytesWritten,table.rowCount,pages)
        }finally{
            // A cancelled/failed render never returns success; the caller discards its
            // partial temp/output. Finish an open native page before closing resources.
            try{active?.let{document.finishPage(it)}}finally{try{document.close()}finally{bitmap.recycle()}}
        }
    }
    private fun paint(size:Float,bold:Boolean=false,color:Int=Color.rgb(25,28,35))=TextPaint(Paint.ANTI_ALIAS_FLAG).apply{
        textSize=size;this.color=color;typeface=Typeface.create(Typeface.SANS_SERIF,if(bold)Typeface.BOLD else Typeface.NORMAL)
        // Skia cannot reverse-map some GSUB digit/ligature variants into PDF
        // ToUnicode entries. Keep the same readable face with literal glyphs.
        fontFeatureSettings="'tnum' 0, 'liga' 0, 'clig' 0";isSubpixelText=true
    }
    private class NativeWriteGuard(private val target:OutputStream):OutputStream(){
        private var failure:Throwable?=null
        fun rethrowFailure(){failure?.let{throw it}}
        private inline fun forward(action:()->Unit){
            rethrowFailure()
            try{action()}catch(error:Throwable){failure=error;throw error}
        }
        override fun write(value:Int)=forward{target.write(value)}
        override fun write(bytes:ByteArray,offset:Int,length:Int)=forward{target.write(bytes,offset,length)}
        override fun flush()=forward{target.flush()}
        override fun close(){flush()} // The caller still owns the actual stream.
    }
}

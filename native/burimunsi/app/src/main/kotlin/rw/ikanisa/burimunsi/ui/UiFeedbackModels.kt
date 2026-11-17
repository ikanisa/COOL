package rw.ikanisa.burimunsi.ui

import rw.ikanisa.burimunsi.core.export.ExportFormat

/** Real work and confirmed SAF outcomes; animations never advance these states. */
enum class UiOperation { NONE, INITIAL_READ, REFRESH, LOAD_MORE, COMMAND, EXPORT }
enum class UiExportPhase { PREPARING, CHOOSING_DESTINATION, WRITING, COMPLETE, CANCELLED, FAILED }
data class UiExportFeedback(
    val phase:UiExportPhase,val format:ExportFormat,val fileName:String?=null,
    val completedRows:Int?=null,val totalRows:Int?=null,val canCancel:Boolean=false,val error:String?=null,
)

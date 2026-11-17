package rw.ikanisa.burimunsi.data
open class ApiFailure(val code:String,val status:Int=0,val uncertain:Boolean=false):Exception(code)
internal class ObservationUploadUnresolved(val requestId:String):ApiFailure("observation_upload_unresolved",503,true)

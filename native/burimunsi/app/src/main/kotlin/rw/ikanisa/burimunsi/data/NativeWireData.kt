package rw.ikanisa.burimunsi.data
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.ContractFailure
import rw.ikanisa.wire.*
/** Cache entries are data, never authority. Revalidate them against the current owner and route. */
internal fun validateCachedPayload(installationId:String,path:String,payload:String,context:Map<String,Any?>):String {
    try {
        val contract=BuriMunsiSchemas.contract
        val route=contract.route("GET",path)
        val data=objectValue(StrictJson.parse(payload))
        contract.validate(route.first+".data",data)
        val binding=context+mapOf("installationId" to installationId)
        contract.semantics(route.first,mapOf("binding" to binding,"data" to data),binding+mapOf("recordId" to route.second))
        return payload
    }catch(e:ContractViolation){throw ApiFailure(e.code.lowercase(),0,false)}
}
internal fun checkedDto(name:String,value:JSONObject) {
    try { BuriMunsiSchemas.contract.validate(name,StrictJson.parse(value.toString())) }
    catch(e:ContractViolation){throw ContractFailure(e.code.lowercase())}
}

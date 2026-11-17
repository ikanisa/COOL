package rw.ikanisa.burimunsi.data
/** Compile-only API factory double. Cycle tests inject a restorer; no socket exists. */
class ApiClient {companion object {
 fun phonePin(origin:String,installation:String,profile:String,prefix:String,publicKey:String="",token:()->String?):ApiClient=ApiClient()
}}

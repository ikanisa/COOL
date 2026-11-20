package android.app
/** Plain Android host: original phone/PIN does not require a managed email broker. */
open class Application {
    val permissionResults=mutableMapOf<String,Int>()
    fun checkSelfPermission(permission:String)=permissionResults[permission]?:0
}

package android.app
/** Native PIN bootstrap uses a plain Android host; no synthetic managed JWT/scope. */
open class Application:android.content.Context(){fun checkSelfPermission(permission:String)=0}

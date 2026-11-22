package android.content
class Context {
 val applicationContext:Context get()=this
 var denied=emptySet<String>()
 fun checkSelfPermission(permission:String)=if(permission in denied)-1 else 0
}

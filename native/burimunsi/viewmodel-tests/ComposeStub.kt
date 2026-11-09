package androidx.compose.runtime
import kotlin.reflect.KProperty
class MutableState<T>(@Volatile var value:T)
fun <T> mutableStateOf(value:T)=MutableState(value)
operator fun <T> MutableState<T>.getValue(thisRef:Any?,property:KProperty<*>):T=value
operator fun <T> MutableState<T>.setValue(thisRef:Any?,property:KProperty<*>,next:T){value=next}

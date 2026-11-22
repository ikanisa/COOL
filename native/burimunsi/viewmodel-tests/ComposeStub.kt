package androidx.compose.runtime

import androidx.compose.runtime.snapshots.Snapshot
import kotlin.reflect.KProperty

fun interface SnapshotMutationPolicy<T> { fun equivalent(a: T, b: T): Boolean }

class MutableState<T>(initial: T, private val policy: SnapshotMutationPolicy<T>) {
    @Suppress("UNCHECKED_CAST")
    internal fun equivalent(a: Any?, b: Any?) = policy.equivalent(a as T, b as T)

    internal var committed: Any? = initial
    internal var version = 0L
    var value: T
        get() = Snapshot.read(this)
        set(next) = Snapshot.write(this, next)
}

fun <T> mutableStateOf(value: T, policy: SnapshotMutationPolicy<T> = SnapshotMutationPolicy { a, b -> a == b }) =
    MutableState(value, policy)
operator fun <T> MutableState<T>.getValue(thisRef: Any?, property: KProperty<*>): T = value
operator fun <T> MutableState<T>.setValue(thisRef: Any?, property: KProperty<*>, next: T) { value = next }

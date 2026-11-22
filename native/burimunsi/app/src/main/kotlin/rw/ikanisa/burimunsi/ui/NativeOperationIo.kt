package rw.ikanisa.burimunsi.ui

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Rejects results from a superseded ViewModel session after off-main work. */
internal class NativeOperationIo(private val generation: () -> Int) {
    suspend operator fun <T> invoke(action: () -> T): T {
        val before = generation()
        val result = withContext(Dispatchers.IO) { action() }
        if (before != generation()) throw CancellationException()
        return result
    }
}

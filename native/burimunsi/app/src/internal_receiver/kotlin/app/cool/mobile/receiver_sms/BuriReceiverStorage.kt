package app.cool.mobile.receiver_sms

import android.content.Context
import android.system.Os
import android.system.OsConstants
import java.io.File

internal fun durableQueueFile(context: Context): BuriQueueFile = BuriQueueFile(
    File(context.noBackupFilesDir, "burimunsi_sms_queue_v2.enc"),
    { directory ->
        val fd = Os.open(directory.absolutePath, OsConstants.O_RDONLY, 0)
        try {
            check(OsConstants.S_ISDIR(Os.fstat(fd).st_mode)) { "Queue parent is not a directory" }
            Os.fsync(fd)
        } finally { Os.close(fd) }
    },
)

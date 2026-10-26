package app.cool.mobile.receiver_sms

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import androidx.core.database.sqlite.transaction
import java.io.File

/** Lightweight no-backup acknowledgement tombstones. Contains no message body or sender. */
internal class SmsCaptureJournal(context: Context) : SQLiteOpenHelper(context,
    File(context.noBackupFilesDir, "collect_sms_capture_journal.db").absolutePath, null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE acknowledged_capture (capture_id TEXT PRIMARY KEY NOT NULL, body_sha256 TEXT NOT NULL)")
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        throw IllegalStateException("Unsupported capture journal version")
    }
    fun acknowledgedHash(id: String): String? = readableDatabase.query("acknowledged_capture", arrayOf("body_sha256"),
        "capture_id = ?", arrayOf(id), null, null, null).use { if (it.moveToFirst()) it.getString(0) else null }
    fun retainAcknowledgements(hashes: Map<String, String>) {
        val db = writableDatabase
        db.transaction {
            for ((id, hash) in hashes) {
                val values = ContentValues().apply { put("capture_id", id); put("body_sha256", hash) }
                db.insertWithOnConflict("acknowledged_capture", null, values, SQLiteDatabase.CONFLICT_IGNORE)
                check(acknowledgedHash(id) == hash) { "Capture acknowledgement conflicts" }
            }
        }
    }
}

package app.cool.mobile.momo_sms

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

internal const val tableSmsQueue = "momo_sms_queue"

/**
 * SQLite database for the MoMo SMS offline queue.
 *
 * Uses raw SQLiteOpenHelper (not Room) to avoid the KSP/KAPT annotation
 * processing dependency in this Flutter host project.
 *
 * Singleton instance — safe to access from BroadcastReceiver,
 * WorkManager, and Flutter method channel simultaneously.
 */
class MomoSmsQueueDatabase private constructor(
    context: Context,
) : SQLiteOpenHelper(context.applicationContext, DB_NAME, null, DB_VERSION) {

    companion object {
        private const val DB_NAME = "cool_momo_sms_queue.db"
        private const val DB_VERSION = 1

        @Volatile
        private var instance: MomoSmsQueueDatabase? = null

        fun getInstance(context: Context): MomoSmsQueueDatabase {
            return instance ?: synchronized(this) {
                instance ?: MomoSmsQueueDatabase(context).also {
                    instance = it
                }
            }
        }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS $tableSmsQueue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL,
                device_message_key TEXT NOT NULL,
                sender TEXT NOT NULL,
                sms_body TEXT NOT NULL,
                sms_received_at TEXT NOT NULL,
                ingestion_source TEXT NOT NULL DEFAULT 'native_sms_receiver',
                status TEXT NOT NULL DEFAULT 'PENDING',
                retries INTEGER NOT NULL DEFAULT 0,
                last_error TEXT,
                created_at INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL DEFAULT 0,
                UNIQUE(user_id, device_message_key)
            )
            """.trimIndent()
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_sms_queue_status ON $tableSmsQueue (status)"
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_sms_queue_user ON $tableSmsQueue (user_id)"
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // V1 only — add migration logic for future schema changes.
    }
}

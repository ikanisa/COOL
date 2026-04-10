package app.cool.mobile.momo_sms

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import java.time.Instant
import java.time.format.DateTimeFormatter

class MomoSmsQueueRepository private constructor(context: Context) {
    companion object {
        private const val maxRetriesBeforeFailure = 5

        @Volatile
        private var instance: MomoSmsQueueRepository? = null

        fun getInstance(context: Context): MomoSmsQueueRepository {
            return instance ?: synchronized(this) {
                instance ?: MomoSmsQueueRepository(context.applicationContext).also {
                    instance = it
                }
            }
        }
    }

    private val database = MomoSmsQueueDatabase.getInstance(context)
    private val isoFormatter = DateTimeFormatter.ISO_INSTANT

    fun insertIfAbsent(userId: String, capture: MomoSmsCapture): Long {
        val now = System.currentTimeMillis()
        val values = ContentValues().apply {
            put("user_id", userId)
            put("device_message_key", capture.deviceMessageKey)
            put("sender", capture.sender)
            put("sms_body", capture.body)
            put("sms_received_at", isoFormatter.format(capture.receivedAt))
            put("ingestion_source", capture.ingestionSource)
            put("status", MomoSmsQueueStatus.PENDING.name)
            put("retries", 0)
            put("created_at", now)
            put("updated_at", now)
        }
        return database.writableDatabase.insertWithOnConflict(
            tableSmsQueue,
            null,
            values,
            android.database.sqlite.SQLiteDatabase.CONFLICT_IGNORE,
        )
    }

    fun getRetryableBatch(
        userId: String,
        limit: Int,
        restrictToIds: Set<Long>? = null,
    ): List<MomoSmsQueueRecord> {
        val selectionParts = mutableListOf(
            "user_id = ?",
            "status = ?",
        )
        val args = mutableListOf(
            userId,
            MomoSmsQueueStatus.PENDING.name,
        )
        if (!restrictToIds.isNullOrEmpty()) {
            val placeholders = restrictToIds.joinToString(",") { "?" }
            selectionParts += "id IN ($placeholders)"
            args += restrictToIds.map(Long::toString)
        }
        val cursor = database.readableDatabase.query(
            tableSmsQueue,
            arrayOf(
                "id",
                "user_id",
                "sender",
                "sms_body",
                "sms_received_at",
                "device_message_key",
                "ingestion_source",
                "status",
                "retries",
                "last_error",
            ),
            selectionParts.joinToString(" AND "),
            args.toTypedArray(),
            null,
            null,
            "sms_received_at ASC, id ASC",
            limit.toString(),
        )
        return cursor.use { rows ->
            buildList {
                while (rows.moveToNext()) {
                    add(rows.toRecord())
                }
            }
        }
    }

    fun markSynced(ids: Collection<Long>) {
        updateStatus(ids, MomoSmsQueueStatus.SYNCED, retriesDelta = 0, error = null)
    }

    fun markRetry(ids: Collection<Long>, error: String?) {
        ids.forEach { id ->
            val record = getRecord(id) ?: return@forEach
            val nextRetries = record.retries + 1
            val nextStatus = if (nextRetries >= maxRetriesBeforeFailure) {
                MomoSmsQueueStatus.FAILED
            } else {
                MomoSmsQueueStatus.PENDING
            }
            updateStatus(
                listOf(id),
                nextStatus,
                retriesDelta = 1,
                error = error,
            )
        }
    }

    fun snapshot(userId: String): MomoSmsQueueSnapshot {
        val databaseRef = database.readableDatabase
        fun count(whereClause: String, args: Array<String>): Int {
            val cursor = databaseRef.rawQuery(
                "SELECT COUNT(*) FROM $tableSmsQueue WHERE $whereClause",
                args,
            )
            return cursor.use {
                if (it.moveToFirst()) it.getInt(0) else 0
            }
        }
        val pending = count(
            "user_id = ? AND status = ?",
            arrayOf(userId, MomoSmsQueueStatus.PENDING.name),
        )
        val failed = count(
            "user_id = ? AND status = ?",
            arrayOf(userId, MomoSmsQueueStatus.FAILED.name),
        )
        val synced = count(
            "user_id = ? AND status = ?",
            arrayOf(userId, MomoSmsQueueStatus.SYNCED.name),
        )
        val total = count("user_id = ?", arrayOf(userId))
        return MomoSmsQueueSnapshot(
            pendingCount = pending,
            failedCount = failed,
            syncedCount = synced,
            totalCount = total,
        )
    }

    fun deleteForUser(userId: String) {
        database.writableDatabase.delete(
            tableSmsQueue,
            "user_id = ?",
            arrayOf(userId),
        )
    }

    private fun updateStatus(
        ids: Collection<Long>,
        status: MomoSmsQueueStatus,
        retriesDelta: Int,
        error: String?,
    ) {
        if (ids.isEmpty()) {
            return
        }
        val now = System.currentTimeMillis()
        database.writableDatabase.beginTransaction()
        try {
            ids.forEach { id ->
                val values = ContentValues().apply {
                    put("status", status.name)
                    put("updated_at", now)
                    put("last_error", error)
                    if (retriesDelta > 0) {
                        val currentRetries = getRecord(id)?.retries ?: 0
                        put("retries", currentRetries + retriesDelta)
                    }
                }
                database.writableDatabase.update(
                    tableSmsQueue,
                    values,
                    "id = ?",
                    arrayOf(id.toString()),
                )
            }
            database.writableDatabase.setTransactionSuccessful()
        } finally {
            database.writableDatabase.endTransaction()
        }
    }

    private fun getRecord(id: Long): MomoSmsQueueRecord? {
        val cursor = database.readableDatabase.query(
            tableSmsQueue,
            arrayOf(
                "id",
                "user_id",
                "sender",
                "sms_body",
                "sms_received_at",
                "device_message_key",
                "ingestion_source",
                "status",
                "retries",
                "last_error",
            ),
            "id = ?",
            arrayOf(id.toString()),
            null,
            null,
            null,
            "1",
        )
        return cursor.use { rows ->
            if (rows.moveToFirst()) rows.toRecord() else null
        }
    }

    private fun Cursor.toRecord(): MomoSmsQueueRecord {
        return MomoSmsQueueRecord(
            id = getLong(getColumnIndexOrThrow("id")),
            userId = getString(getColumnIndexOrThrow("user_id")),
            sender = getString(getColumnIndexOrThrow("sender")),
            body = getString(getColumnIndexOrThrow("sms_body")),
            receivedAt = Instant.parse(getString(getColumnIndexOrThrow("sms_received_at"))),
            deviceMessageKey = getString(getColumnIndexOrThrow("device_message_key")),
            ingestionSource = getString(getColumnIndexOrThrow("ingestion_source")),
            status = MomoSmsQueueStatus.valueOf(getString(getColumnIndexOrThrow("status"))),
            retries = getInt(getColumnIndexOrThrow("retries")),
            lastError = getString(getColumnIndexOrThrow("last_error")),
        )
    }
}

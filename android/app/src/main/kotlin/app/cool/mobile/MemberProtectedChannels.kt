package app.cool.mobile

import android.app.Activity
import app.cool.mobile.receiver_sms.MemberSmsJobs
import app.cool.mobile.receiver_sms.SmsQueueWorker
import app.cool.mobile.security.ContributionCommandStore
import app.cool.mobile.security.ProtectedSnapshotStore
import app.cool.mobile.security.ReceiptSmsPendingStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Member snapshot, session and durable command channels share the native storage worker. */
internal class MemberProtectedChannels(
    private val activity: Activity,
    private val smsAccess: MemberSmsAccessChannel,
) {
    fun register(messenger: BinaryMessenger) {
        registerSnapshot(messenger, "collect/secure_snapshot", "snapshot", "Snapshot required")
        registerSnapshot(messenger, "collect/secure_auth_session", "auth", "Session required") {
            MemberSmsJobs.ensure(activity.applicationContext)
        }
        MethodChannel(messenger, "collect/payment_help_pending")
            .setMethodCallHandler { call, result ->
                val storage = ProtectedSnapshotStore(activity.applicationContext, purpose = "payment_help")
                when (call.method) {
                    "read" -> runTask(result, Failure.PAYMENT_HELP) {
                        storage.read(call.argument<String>("owner_id").orEmpty())
                    }
                    "write" -> runTask(result, Failure.PAYMENT_HELP) {
                        storage.write(call.argument<String>("owner_id").orEmpty(),
                            call.argument<String>("value") ?: throw IllegalArgumentException("Pending request required"))
                    }
                    "clear" -> runTask(result, Failure.PAYMENT_HELP) {
                        val owner = call.argument<String>("owner_id")
                        require(!call.hasArgument("owner_id") || owner != null) { "Owner required" }
                        storage.clear(owner)
                    }
                    else -> result.notImplemented()
                }
            }

        val contributionCommands = ContributionCommandStore(activity.applicationContext)
        MethodChannel(messenger, "collect/contribution_commands_v1")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read", "compareAndSet" -> runTask(result, Failure.CONTRIBUTION) {
                        val arguments = call.arguments as? Map<*, *> ?: error("Arguments required")
                        val expectedKeys = if (call.method == "read") setOf("partition_id")
                            else setOf("partition_id", "expected_revision", "payload")
                        require(arguments.keys == expectedKeys)
                        val partition = arguments["partition_id"] as? String ?: error("Partition required")
                        if (call.method == "read") contributionCommands.read(partition)
                        else contributionCommands.compareAndSet(partition, arguments["expected_revision"],
                            arguments["payload"] as? String ?: error("Payload required"))
                    }
                    else -> result.notImplemented()
                }
            }

        val receiptSmsPending = ReceiptSmsPendingStore(activity.applicationContext)
        MethodChannel(messenger, "collect/receipt_sms_pending")
            .setMethodCallHandler { call, result ->
                val owner = call.argument<String>("owner_id").orEmpty()
                val group = call.argument<String>("collection_id").orEmpty()
                when (call.method) {
                    "read" -> runTask(result, Failure.RECEIPT_SMS) { receiptSmsPending.read(owner, group) }
                    "claim" -> runTask(result, Failure.RECEIPT_SMS) { receiptSmsPending.claim(owner, group, call.argument<Any>("request")) }
                    "claimWithdrawalFence" -> runTask(result, Failure.RECEIPT_SMS) { receiptSmsPending.claim(owner, group, call.argument<Any>("request"), true) }
                    "complete" -> runTask(result, Failure.RECEIPT_SMS) { receiptSmsPending.complete(owner, group, call.argument<Any>("request"), call.argument<Any>("decision_revision")) }
                    "supersede" -> runTask(result, Failure.RECEIPT_SMS) { receiptSmsPending.supersede(owner, group, call.argument<Any>("known_requests"), call.argument<Any>("decision_revision")) }
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerSnapshot(
        messenger: BinaryMessenger,
        channel: String,
        purpose: String,
        missingValue: String,
        afterWrite: () -> Unit = {},
    ) {
        MethodChannel(messenger, channel).setMethodCallHandler { call, result ->
            val storage = ProtectedSnapshotStore(activity.applicationContext, purpose = purpose)
            when (call.method) {
                "read" -> smsAccess.runSmsQueueTask(result) {
                    storage.read(call.argument<String>("owner_id").orEmpty())
                }
                "write" -> smsAccess.runSmsQueueTask(result) {
                    storage.write(
                        call.argument<String>("owner_id").orEmpty(),
                        call.argument<String>("value") ?: throw IllegalArgumentException(missingValue),
                    ).also { if (it) afterWrite() }
                }
                "clear" -> smsAccess.runSmsQueueTask(result) { storage.clear() }
                else -> result.notImplemented()
            }
        }
    }

    private enum class Failure(val code: String, val message: String) {
        PAYMENT_HELP(
            "payment_help_storage_unavailable",
            "Secure payment help recovery is unavailable; retained requests were not discarded.",
        ),
        CONTRIBUTION(
            "contribution_command_storage_unavailable",
            "Secure contribution recovery is unavailable; retained requests were not discarded.",
        ),
        RECEIPT_SMS(
            "receipt_sms_recovery_unavailable",
            "Secure receipt SMS recovery is unavailable; retained requests were not discarded.",
        ),
    }

    private fun runTask(result: MethodChannel.Result, failure: Failure, task: () -> Any?) {
        fun unavailable() = result.error(
            failure.code,
            failure.message,
            null,
        )
        try {
            SmsQueueWorker.execute {
                try {
                    val value = task()
                    activity.runOnUiThread { result.success(value) }
                } catch (_: Exception) {
                    activity.runOnUiThread { unavailable() }
                }
            }
        } catch (_: RuntimeException) {
            unavailable()
        }
    }
}

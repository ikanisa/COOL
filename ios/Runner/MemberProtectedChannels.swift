import Flutter
import Foundation

final class MemberProtectedChannels {
  private var snapshotChannel: FlutterMethodChannel?
  private var authSessionChannel: FlutterMethodChannel?
  private var paymentHelpPendingChannel: FlutterMethodChannel?
  private var receiptSmsPendingChannel: FlutterMethodChannel?
  private var contributionCommandChannel: FlutterMethodChannel?
  private let contributionCommandStore = ContributionCommandStore()
  private let contributionCommandQueue = DispatchQueue(label: "collect.contribution-commands")
  private let receiptSmsPendingStore = ReceiptSmsPendingStore()
  private let receiptSmsPendingQueue = DispatchQueue(label: "collect.receipt-sms.pending")
  private let snapshotQueue = DispatchQueue(label: "collect.secure.snapshot")
  private let snapshotStore = CollectProtectedSnapshotStore()
  private let authSessionStore = CollectProtectedSnapshotStore(purpose: "auth")
  private let paymentHelpPendingStore = CollectProtectedSnapshotStore(purpose: "payment_help")

  func register(with messenger: FlutterBinaryMessenger) {
    snapshotChannel = makeSnapshotChannel(
      messenger: messenger,
      name: "collect/secure_snapshot",
      store: snapshotStore,
      code: "cache_unavailable",
      unavailableMessage: "Protected cache unavailable",
      failureMessage: "Protected cache temporarily unavailable"
    )
    paymentHelpPendingChannel = makeSnapshotChannel(
      messenger: messenger,
      name: "collect/payment_help_pending",
      store: paymentHelpPendingStore,
      code: "payment_help_storage_unavailable",
      unavailableMessage: "Secure payment help recovery is unavailable",
      failureMessage: "Secure payment help recovery is unavailable; retained requests were not discarded.",
      ownerScopedClear: true
    )
    let contributionChannel = FlutterMethodChannel(name: "collect/contribution_commands_v1",
      binaryMessenger: messenger)
    contributionCommandChannel = contributionChannel
    contributionChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "contribution_command_storage_unavailable",
          message: "Secure contribution recovery is unavailable; retained requests were not discarded.", details: nil)); return
      }
      guard ["read", "compareAndSet"].contains(call.method) else { result(FlutterMethodNotImplemented); return }
      self.contributionCommandQueue.async {
        do {
          guard let arguments = call.arguments as? [String: Any],
            Set(arguments.keys) == (call.method == "read" ? Set(["partition_id"]) : Set(["partition_id", "expected_revision", "payload"])),
            let partition = arguments["partition_id"] as? String else { throw ContributionCommandFailure.invalid }
          let value: [String: Any]
          if call.method == "read" { value = try self.contributionCommandStore.read(partition: partition) }
          else {
            guard let payload = arguments["payload"] as? String else { throw ContributionCommandFailure.invalid }
            value = try self.contributionCommandStore.compareAndSet(partition: partition, expected: arguments["expected_revision"], payload: payload)
          }
          DispatchQueue.main.async { result(value) }
        } catch { DispatchQueue.main.async { result(FlutterError(code: "contribution_command_storage_unavailable",
          message: "Secure contribution recovery is unavailable; retained requests were not discarded.", details: nil)) } }
      }
    }
    let receiptChannel = FlutterMethodChannel(name: "collect/receipt_sms_pending",
      binaryMessenger: messenger)
    receiptSmsPendingChannel = receiptChannel
    receiptChannel.setMethodCallHandler { [weak self] call, result in
      guard let self, ["read", "claim", "claimWithdrawalFence", "complete", "supersede"].contains(call.method) else { result(FlutterMethodNotImplemented); return }
      let arguments = call.arguments as? [String: Any] ?? [:]
      self.receiptSmsPendingQueue.async {
        do {
          let owner = arguments["owner_id"] as? String ?? "", group = arguments["collection_id"] as? String ?? ""
          let value: Any?
          switch call.method {
          case "read": value = try self.receiptSmsPendingStore.read(owner: owner, group: group)
          case "claim": value = try self.receiptSmsPendingStore.claim(owner: owner, group: group, value: arguments["request"])
          case "claimWithdrawalFence": value = try self.receiptSmsPendingStore.claim(owner: owner, group: group, value: arguments["request"], fence: true)
          case "complete": value = try self.receiptSmsPendingStore.complete(owner: owner, group: group, value: arguments["request"], head: arguments["decision_revision"])
          default: value = try self.receiptSmsPendingStore.supersede(owner: owner, group: group, values: arguments["known_requests"], head: arguments["decision_revision"])
          }
          DispatchQueue.main.async { result(value) }
        } catch { DispatchQueue.main.async { result(FlutterError(code: "receipt_sms_recovery_unavailable",
          message: "Secure receipt SMS recovery is unavailable; retained requests were not discarded.", details: nil)) } }
      }
    }
    authSessionChannel = makeSnapshotChannel(
      messenger: messenger,
      name: "collect/secure_auth_session",
      store: authSessionStore,
      code: "auth_storage_unavailable",
      unavailableMessage: "Protected sign-in storage unavailable",
      failureMessage: "Protected sign-in storage temporarily unavailable"
    )
  }

  private func makeSnapshotChannel(
    messenger: FlutterBinaryMessenger,
    name: String,
    store: CollectProtectedSnapshotStore,
    code: String,
    unavailableMessage: String,
    failureMessage: String,
    ownerScopedClear: Bool = false
  ) -> FlutterMethodChannel {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: code, message: unavailableMessage, details: nil))
        return
      }
      guard ["read", "write", "clear"].contains(call.method) else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any] ?? [:]
      let owner = arguments["owner_id"] as? String
      self.snapshotQueue.async {
        do {
          let output: Any?
          switch call.method {
          case "read":
            output = try store.read(owner: owner ?? "")
          case "write":
            guard let value = arguments["value"] as? String else { throw CollectSnapshotFailure.invalid }
            try store.write(owner: owner ?? "", value: value)
            output = true
          default:
            if ownerScopedClear && arguments.keys.contains("owner_id") && owner == nil {
              throw CollectSnapshotFailure.invalid
            }
            try store.clear(owner: ownerScopedClear ? owner : nil)
            output = true
          }
          DispatchQueue.main.async { result(output) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: code, message: failureMessage, details: nil))
          }
        }
      }
    }
    return channel
  }
}

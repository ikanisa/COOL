import 'package:flutter/services.dart';
import '../models/receipt_sms_consent.dart';

/// Every operation is an atomic, bounded device-only custody transaction.
abstract interface class ReceiptSmsPendingStore {
  Future<ReceiptSmsRecoveryState> read({
    required String userId,
    required String collectionId,
  });
  Future<ReceiptSmsRecoveryState> claim(
    PendingReceiptSmsRequest request, {
    bool withdrawalFence = false,
  });
  Future<ReceiptSmsRecoveryState> complete(
    PendingReceiptSmsRequest request,
    int acknowledgedDecisionRevision,
  );
  Future<ReceiptSmsRecoveryState> supersede({
    required String userId,
    required String collectionId,
    required List<PendingReceiptSmsRequest> knownRequests,
    required int observedDecisionRevision,
  });
}

final class NativeReceiptSmsPendingStore implements ReceiptSmsPendingStore {
  const NativeReceiptSmsPendingStore({
    this.channel = const MethodChannel('collect/receipt_sms_pending'),
  });
  final MethodChannel channel;
  Map<String, Object?> _target(String user, String group) => {
    'owner_id': receiptSmsUuid(user),
    'collection_id': receiptSmsUuid(group),
  };
  ReceiptSmsRecoveryState _decode(Object? value, String user, String group) =>
      ReceiptSmsRecoveryState.decode(value, user, group);
  @override
  Future<ReceiptSmsRecoveryState> read({
    required String userId,
    required String collectionId,
  }) async => _decode(
    await channel.invokeMethod<Object?>('read', _target(userId, collectionId)),
    userId,
    collectionId,
  );
  @override
  Future<ReceiptSmsRecoveryState> claim(
    PendingReceiptSmsRequest request, {
    bool withdrawalFence = false,
  }) async {
    PendingReceiptSmsRequest.decode(request.toJson());
    if (withdrawalFence && request.optIn) {
      throw const FormatException(
        'Only an explicit withdrawal can fence an earlier request.',
      );
    }
    return _decode(
      await channel.invokeMethod<Object?>(
        withdrawalFence ? 'claimWithdrawalFence' : 'claim',
        {
          ..._target(request.userId, request.collectionId),
          'request': request.toJson(),
        },
      ),
      request.userId,
      request.collectionId,
    );
  }

  @override
  Future<ReceiptSmsRecoveryState> complete(
    PendingReceiptSmsRequest request,
    int acknowledgedDecisionRevision,
  ) async {
    receiptSmsDecisionRevision(acknowledgedDecisionRevision);
    if (acknowledgedDecisionRevision != request.expectedDecisionRevision + 1) {
      throw const FormatException(
        'Receipt SMS acknowledgement order is invalid.',
      );
    }
    return _decode(
      await channel.invokeMethod<Object?>('complete', {
        ..._target(request.userId, request.collectionId),
        'request': request.toJson(),
        'decision_revision': acknowledgedDecisionRevision,
      }),
      request.userId,
      request.collectionId,
    );
  }

  @override
  Future<ReceiptSmsRecoveryState> supersede({
    required String userId,
    required String collectionId,
    required List<PendingReceiptSmsRequest> knownRequests,
    required int observedDecisionRevision,
  }) async {
    receiptSmsDecisionRevision(observedDecisionRevision);
    if (knownRequests.isEmpty ||
        knownRequests.length > 32 ||
        knownRequests.map((r) => r.requestId).toSet().length !=
            knownRequests.length ||
        knownRequests.any(
          (r) => r.userId != userId || r.collectionId != collectionId,
        )) {
      throw const FormatException('Receipt SMS recovery cohort is invalid.');
    }
    for (final request in knownRequests) {
      PendingReceiptSmsRequest.decode(request.toJson());
    }
    return _decode(
      await channel.invokeMethod<Object?>('supersede', {
        ..._target(userId, collectionId),
        'known_requests': knownRequests.map((r) => r.toJson()).toList(),
        'decision_revision': observedDecisionRevision,
      }),
      userId,
      collectionId,
    );
  }
}

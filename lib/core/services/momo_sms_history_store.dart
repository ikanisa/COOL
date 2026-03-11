import 'package:hive_flutter/hive_flutter.dart';

import 'momo_sms_parser.dart';

enum MomoSmsHistoryStatus {
  detected,
  processing,
  confirmed,
  reviewRequired,
  unmatched,
}

class MomoSmsHistoryEntry {
  const MomoSmsHistoryEntry({
    required this.key,
    required this.transaction,
    required this.status,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.rawSmsId,
    this.matchedReference,
    this.updatedAt,
  });

  final String key;
  final MomoTransaction transaction;
  final MomoSmsHistoryStatus status;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final String? rawSmsId;
  final String? matchedReference;
  final DateTime? updatedAt;

  factory MomoSmsHistoryEntry.fromJson(Map<String, dynamic> json) {
    return MomoSmsHistoryEntry(
      key: json['key']?.toString() ?? '',
      transaction: MomoTransaction(
        type: MomoTxType.values.byName(json['type']?.toString() ?? 'payment'),
        amountRwf: (json['amount_rwf'] as num?)?.round() ?? 0,
        transactionId: json['transaction_id']?.toString(),
        country: json['country']?.toString() ?? '',
        provider: json['provider']?.toString() ?? '',
        sender: json['sender']?.toString() ?? '',
        rawMessage: json['raw_message']?.toString() ?? '',
        receivedAt:
            DateTime.tryParse(json['received_at']?.toString() ?? '') ??
            DateTime.now(),
      ),
      status: MomoSmsHistoryStatus.values.byName(
        json['status']?.toString() ?? MomoSmsHistoryStatus.detected.name,
      ),
      firstSeenAt:
          DateTime.tryParse(json['first_seen_at']?.toString() ?? '') ??
          DateTime.now(),
      lastSeenAt:
          DateTime.tryParse(json['last_seen_at']?.toString() ?? '') ??
          DateTime.now(),
      rawSmsId: json['raw_sms_id']?.toString(),
      matchedReference: json['matched_reference']?.toString(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'key': key,
      'type': transaction.type.name,
      'amount_rwf': transaction.amountRwf,
      'transaction_id': transaction.transactionId,
      'country': transaction.country,
      'provider': transaction.provider,
      'sender': transaction.sender,
      'raw_message': transaction.rawMessage,
      'received_at': transaction.receivedAt.toIso8601String(),
      'status': status.name,
      'first_seen_at': firstSeenAt.toIso8601String(),
      'last_seen_at': lastSeenAt.toIso8601String(),
      'raw_sms_id': rawSmsId,
      'matched_reference': matchedReference,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  static const _sentinel = Object();

  MomoSmsHistoryEntry copyWith({
    MomoSmsHistoryStatus? status,
    DateTime? lastSeenAt,
    Object? rawSmsId = _sentinel,
    Object? matchedReference = _sentinel,
    DateTime? updatedAt,
  }) {
    return MomoSmsHistoryEntry(
      key: key,
      transaction: transaction,
      status: status ?? this.status,
      firstSeenAt: firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      rawSmsId: rawSmsId == _sentinel ? this.rawSmsId : rawSmsId as String?,
      matchedReference: matchedReference == _sentinel
          ? this.matchedReference
          : matchedReference as String?,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Local deduped storage for parsed MoMo SMS transactions.
class MomoSmsHistoryStore {
  MomoSmsHistoryStore._();

  static final MomoSmsHistoryStore instance = MomoSmsHistoryStore._();

  static const _boxName = 'momo_sms_history';

  Future<MomoSmsHistoryEntry> recordDetected(
    MomoTransaction transaction,
  ) async {
    final box = await Hive.openBox<dynamic>(_boxName);
    final key = transactionKey(transaction);
    final existingRaw = box.get(key);
    if (existingRaw is Map) {
      final existing = MomoSmsHistoryEntry.fromJson(
        Map<String, dynamic>.from(existingRaw),
      );
      final updated = existing.copyWith(lastSeenAt: DateTime.now());
      await box.put(key, updated.toJson());
      return updated;
    }

    final entry = MomoSmsHistoryEntry(
      key: key,
      transaction: transaction,
      status: MomoSmsHistoryStatus.detected,
      firstSeenAt: DateTime.now(),
      lastSeenAt: DateTime.now(),
    );
    await box.put(key, entry.toJson());
    return entry;
  }

  Future<void> markConfirmed(
    MomoTransaction transaction, {
    String? matchedReference,
    String? rawSmsId,
  }) async {
    await _updateStatus(
      transaction,
      status: MomoSmsHistoryStatus.confirmed,
      rawSmsId: rawSmsId,
      matchedReference: matchedReference,
    );
  }

  Future<void> markProcessing(
    MomoTransaction transaction, {
    String? rawSmsId,
    String? matchedReference,
  }) async {
    await _updateStatus(
      transaction,
      status: MomoSmsHistoryStatus.processing,
      rawSmsId: rawSmsId,
      matchedReference: matchedReference,
    );
  }

  Future<void> markReviewRequired(
    MomoTransaction transaction, {
    String? rawSmsId,
    String? matchedReference,
  }) async {
    await _updateStatus(
      transaction,
      status: MomoSmsHistoryStatus.reviewRequired,
      rawSmsId: rawSmsId,
      matchedReference: matchedReference,
    );
  }

  Future<void> markUnmatched(MomoTransaction transaction) async {
    await _updateStatus(transaction, status: MomoSmsHistoryStatus.unmatched);
  }

  Future<List<MomoSmsHistoryEntry>> recent({int limit = 50}) async {
    final box = await Hive.openBox<dynamic>(_boxName);
    final entries = box.values
        .whereType<Map>()
        .map(
          (raw) => MomoSmsHistoryEntry.fromJson(Map<String, dynamic>.from(raw)),
        )
        .toList(growable: false);
    entries.sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    return entries.take(limit).toList(growable: false);
  }

  String transactionKey(MomoTransaction transaction) {
    final id = transaction.transactionId?.trim();
    if (id != null && id.isNotEmpty) {
      return 'id:${transaction.provider}:$id';
    }

    return 'raw:${transaction.provider}:${transaction.rawMessage.trim()}';
  }

  Future<void> _updateStatus(
    MomoTransaction transaction, {
    required MomoSmsHistoryStatus status,
    String? rawSmsId,
    String? matchedReference,
  }) async {
    final box = await Hive.openBox<dynamic>(_boxName);
    final key = transactionKey(transaction);
    final existingRaw = box.get(key);
    final existing = existingRaw is Map
        ? MomoSmsHistoryEntry.fromJson(Map<String, dynamic>.from(existingRaw))
        : MomoSmsHistoryEntry(
            key: key,
            transaction: transaction,
            status: MomoSmsHistoryStatus.detected,
            firstSeenAt: DateTime.now(),
            lastSeenAt: DateTime.now(),
          );

    final updated = existing.copyWith(
      status: status,
      lastSeenAt: DateTime.now(),
      rawSmsId: rawSmsId ?? existing.rawSmsId,
      matchedReference: matchedReference,
      updatedAt: DateTime.now(),
    );
    await box.put(key, updated.toJson());
  }
}

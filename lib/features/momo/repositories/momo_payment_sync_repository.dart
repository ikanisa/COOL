import 'package:supabase_flutter/supabase_flutter.dart';

enum MomoPaymentSyncStatus { processing, confirmed, reviewRequired, unmatched }

enum MomoPaymentMatchType {
  unknown,
  groupContribution,
  driverSubscription,
  rayonTicket,
  rayonShopOrder,
  rayonInitiativeContribution,
  pendingTransaction,
}

class MomoPaymentSyncResult {
  const MomoPaymentSyncResult({
    required this.status,
    required this.matchType,
    this.reference,
    this.groupId,
    this.driverId,
  });

  final MomoPaymentSyncStatus status;
  final MomoPaymentMatchType matchType;
  final String? reference;
  final String? groupId;
  final String? driverId;

  bool get isConfirmed => status == MomoPaymentSyncStatus.confirmed;
}

class MomoPaymentSyncRepository {
  MomoPaymentSyncRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<MomoPaymentSyncResult?> resolveServerReconciliation({
    required String rawSmsId,
    Duration timeout = const Duration(seconds: 8),
    Duration pollInterval = const Duration(milliseconds: 600),
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || rawSmsId.isEmpty) {
      return null;
    }

    final deadline = DateTime.now().add(timeout);
    MomoPaymentSyncResult? latest;

    while (true) {
      latest = await _readReconciliationState(
        rawSmsId: rawSmsId,
        userId: userId,
      );
      if (latest == null) {
        return null;
      }

      if (latest.status != MomoPaymentSyncStatus.processing) {
        return latest;
      }

      if (DateTime.now().isAfter(deadline)) {
        return latest;
      }

      await Future<void>.delayed(pollInterval);
    }
  }

  Future<MomoPaymentSyncResult?> _readReconciliationState({
    required String rawSmsId,
    required String userId,
  }) async {
    final rawRow = await _client
        .from('momo_sms_raw')
        .select('id, parse_status')
        .eq('id', rawSmsId)
        .eq('user_id', userId)
        .maybeSingle();
    if (rawRow == null) {
      return null;
    }

    final rawParseStatus = rawRow['parse_status']?.toString() ?? 'pending';
    if (rawParseStatus == 'failed') {
      return const MomoPaymentSyncResult(
        status: MomoPaymentSyncStatus.reviewRequired,
        matchType: MomoPaymentMatchType.unknown,
      );
    }

    final parsedRow = await _client
        .from('momo_sms_parsed')
        .select('id, parse_status')
        .eq('raw_sms_id', rawSmsId)
        .eq('user_id', userId)
        .maybeSingle();

    if (parsedRow == null) {
      return const MomoPaymentSyncResult(
        status: MomoPaymentSyncStatus.processing,
        matchType: MomoPaymentMatchType.unknown,
      );
    }

    final parsedSmsId = parsedRow['id']?.toString() ?? '';
    final parsedStatus = parsedRow['parse_status']?.toString() ?? 'parsed';
    if (parsedStatus == 'failed' || parsedStatus == 'needs_review') {
      return const MomoPaymentSyncResult(
        status: MomoPaymentSyncStatus.reviewRequired,
        matchType: MomoPaymentMatchType.unknown,
      );
    }

    final reconciliationRow = await _client
        .from('momo_reconciliations')
        .select(
          'match_type, match_status, target_table, target_record_id, metadata',
        )
        .eq('parsed_sms_id', parsedSmsId)
        .eq('user_id', userId)
        .maybeSingle();

    if (reconciliationRow == null) {
      return const MomoPaymentSyncResult(
        status: MomoPaymentSyncStatus.processing,
        matchType: MomoPaymentMatchType.unknown,
      );
    }

    final matchStatus =
        reconciliationRow['match_status']?.toString() ?? 'pending_review';
    final targetTable = reconciliationRow['target_table']?.toString();
    final metadata = _asMapOrEmpty(reconciliationRow['metadata']);
    final reference = metadata['matched_reference']?.toString();
    final driverId = metadata['driver_id']?.toString() ?? currentUserId;

    switch (matchStatus) {
      case 'matched':
        return MomoPaymentSyncResult(
          status: MomoPaymentSyncStatus.confirmed,
          matchType: _matchTypeFromServer(
            targetTable: targetTable,
            matchType: reconciliationRow['match_type']?.toString(),
          ),
          reference: reference,
          groupId: metadata['group_id']?.toString(),
          driverId: driverId,
        );
      case 'manual_review':
      case 'pending_review':
        return MomoPaymentSyncResult(
          status: MomoPaymentSyncStatus.reviewRequired,
          matchType: _matchTypeFromServer(
            targetTable: targetTable,
            matchType: reconciliationRow['match_type']?.toString(),
          ),
          reference: reference,
          groupId: metadata['group_id']?.toString(),
          driverId: driverId,
        );
      default:
        return MomoPaymentSyncResult(
          status: MomoPaymentSyncStatus.processing,
          matchType: MomoPaymentMatchType.unknown,
          reference: reference,
        );
    }
  }

  MomoPaymentMatchType _matchTypeFromServer({
    required String? targetTable,
    required String? matchType,
  }) {
    switch (targetTable) {
      case 'group_contributions':
        return MomoPaymentMatchType.groupContribution;
      case 'driver_subscriptions':
      case 'mobility_subscriptions':
        return MomoPaymentMatchType.driverSubscription;
      case 'rs_tickets':
        return MomoPaymentMatchType.rayonTicket;
      case 'rs_shop_orders':
        return MomoPaymentMatchType.rayonShopOrder;
      case 'rs_initiative_contributions':
        return MomoPaymentMatchType.rayonInitiativeContribution;
    }

    if (matchType == 'pending_transaction_only') {
      return MomoPaymentMatchType.pendingTransaction;
    }

    return MomoPaymentMatchType.unknown;
  }
}

Map<String, dynamic> _asMapOrEmpty(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}

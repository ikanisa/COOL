import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/momo_statement.dart';

class MomoStatementRepository {
  MomoStatementRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Future<MomoStatementBundle> loadStatementBundle(
    String userId, {
    MomoStatementQuery query = const MomoStatementQuery(),
  }) async {
    final walletPage = await loadWalletStatementPage(userId, query: query);

    return MomoStatementBundle(
      walletEntries: walletPage.entries
          .map(MomoWalletEntry.fromJson)
          .toList(growable: false),
      walletTotalCount: walletPage.totalCount,
    );
  }

  Future<MomoStatementPage<Map<String, dynamic>>> loadWalletStatementPage(
    String userId, {
    MomoStatementQuery query = const MomoStatementQuery(),
  }) async {
    final rows = await _loadWalletRows(userId, query: query);
    return MomoStatementPage<Map<String, dynamic>>(
      entries: rows,
      totalCount: _extractTotalCount(rows, query: query),
    );
  }

  Future<MomoStatementPage<MomoWalletEntry>> loadWalletEntriesPage(
    String userId, {
    MomoStatementQuery query = const MomoStatementQuery(),
  }) async {
    final page = await loadWalletStatementPage(userId, query: query);
    return MomoStatementPage<MomoWalletEntry>(
      entries: page.entries
          .map(MomoWalletEntry.fromJson)
          .toList(growable: false),
      totalCount: page.totalCount,
    );
  }

  Future<MomoStatementPage<PayeePaymentLedgerEntry>>
  loadGroupPaymentLedgerEntriesPage(
    String groupId, {
    MomoStatementQuery query = const MomoStatementQuery(),
    String? payerUserId,
  }) async {
    final rows = await _loadPayeeLedgerRows(
      'get_group_payment_ledger_entries',
      ownerKey: 'p_group_id',
      ownerId: groupId,
      query: query,
      payerUserId: payerUserId,
    );
    return MomoStatementPage<PayeePaymentLedgerEntry>(
      entries: rows
          .map(PayeePaymentLedgerEntry.fromJson)
          .toList(growable: false),
      totalCount: _extractTotalCount(rows, query: query),
    );
  }

  Future<MomoStatementPage<PayeePaymentLedgerEntry>>
  loadGroupTransactionFeedEntriesPage(
    String groupId, {
    MomoStatementQuery query = const MomoStatementQuery(),
    String? payerUserId,
  }) async {
    final rows = await _loadPayeeLedgerRows(
      'get_group_transaction_feed_entries',
      ownerKey: 'p_group_id',
      ownerId: groupId,
      query: query,
      payerUserId: payerUserId,
    );
    return MomoStatementPage<PayeePaymentLedgerEntry>(
      entries: rows
          .map(PayeePaymentLedgerEntry.fromJson)
          .toList(growable: false),
      totalCount: _extractTotalCount(rows, query: query),
    );
  }

  Future<MomoStatementPage<PayeePaymentLedgerEntry>>
  loadPartnerPaymentLedgerEntriesPage(
    String partnerId, {
    MomoStatementQuery query = const MomoStatementQuery(),
    String? payerUserId,
  }) async {
    final rows = await _loadPayeeLedgerRows(
      'get_partner_payment_ledger_entries',
      ownerKey: 'p_partner_id',
      ownerId: partnerId,
      query: query,
      payerUserId: payerUserId,
    );
    return MomoStatementPage<PayeePaymentLedgerEntry>(
      entries: rows
          .map(PayeePaymentLedgerEntry.fromJson)
          .toList(growable: false),
      totalCount: _extractTotalCount(rows, query: query),
    );
  }

  Future<List<Map<String, dynamic>>> _loadWalletRows(
    String userId, {
    required MomoStatementQuery query,
  }) async {
    var request = _client
        .from('momo_ledger_entries')
        .select(
          'id, entry_type, ledger_status, amount, currency, tx_datetime, '
          'external_reference, tx_category, cashflow_bucket, '
          'counterparty_name, statement_label, description, created_at, '
          'momo_sms_parsed(momo_tx_id, payer_name, payer_number_full, payer_number_last3)',
        )
        .eq('user_id', userId);

    final startAt = query.startAtUtc;
    final endBefore = query.endBeforeUtc;
    if (startAt != null) {
      request = request.gte('tx_datetime', startAt.toIso8601String());
    }
    if (endBefore != null) {
      request = request.lt('tx_datetime', endBefore.toIso8601String());
    }

    return _asListOfMaps(
      await request
          .order('tx_datetime', ascending: false)
          .order('created_at', ascending: false)
          .range(query.offset, query.offset + query.limit - 1),
    );
  }

  Future<List<Map<String, dynamic>>> _loadPayeeLedgerRows(
    String rpcName, {
    required String ownerKey,
    required String ownerId,
    required MomoStatementQuery query,
    String? payerUserId,
  }) async {
    if (ownerId.trim().isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    return _asListOfMaps(
      await _client.rpc(
        rpcName,
        params: <String, dynamic>{
          ownerKey: ownerId,
          ..._statementRpcParams(query),
          'p_payer_user_id': _trimToNull(payerUserId),
        },
      ),
    );
  }
}

Map<String, dynamic> _statementRpcParams(MomoStatementQuery query) {
  return <String, dynamic>{
    'p_start_at': query.startAtUtc?.toIso8601String(),
    'p_end_before': query.endBeforeUtc?.toIso8601String(),
    'p_limit': query.limit,
    'p_offset': query.offset,
  };
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

List<Map<String, dynamic>> _asListOfMaps(dynamic value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }

  return value
      .whereType<Map<dynamic, dynamic>>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

int _extractTotalCount(
  List<Map<String, dynamic>> rows, {
  required MomoStatementQuery query,
}) {
  if (rows.isEmpty) {
    return query.offset;
  }

  final totalCount = rows.first['total_count'];
  if (totalCount is int) {
    return totalCount;
  }
  if (totalCount is num) {
    return totalCount.toInt();
  }

  final currentCount = query.offset + rows.length;
  if (rows.length >= query.limit) {
    return currentCount + 1;
  }
  return currentCount;
}

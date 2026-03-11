import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/momo_statement.dart';

class MomoStatementRepository {
  MomoStatementRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<MomoStatementBundle> loadStatementBundle(
    String userId, {
    MomoStatementQuery query = const MomoStatementQuery(),
  }) async {
    final walletPage = await loadWalletStatementPage(userId, query: query);
    final savingsPage = await loadSavingsStatementPage(userId, query: query);
    final needsGroupNameHydration = savingsPage.entries.any(
      (row) => (row['group_name']?.toString().trim().isEmpty ?? true),
    );
    final groupNames = needsGroupNameHydration
        ? await _loadGroupNames(
            savingsPage.entries
                .map((row) => row['group_id']?.toString() ?? '')
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList(growable: false),
          )
        : const <String, String>{};

    return MomoStatementBundle(
      walletEntries: walletPage.entries
          .map(MomoWalletEntry.fromJson)
          .toList(growable: false),
      savingsEntries: savingsPage.entries
          .map(
            (row) => SavingsStatementEntry.fromJson(<String, dynamic>{
              ...row,
              'group_name':
                  row['group_name']?.toString() ??
                  groupNames[row['group_id']?.toString() ?? ''],
            }),
          )
          .toList(growable: false),
      walletTotalCount: walletPage.totalCount,
      savingsTotalCount: savingsPage.totalCount,
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

  Future<MomoStatementPage<Map<String, dynamic>>> loadSavingsStatementPage(
    String userId, {
    MomoStatementQuery query = const MomoStatementQuery(),
  }) async {
    final rows = await _loadSavingsRows(userId, query: query);
    return MomoStatementPage<Map<String, dynamic>>(
      entries: rows,
      totalCount: _extractTotalCount(rows, query: query),
    );
  }

  Future<MomoStatementPage<SavingsStatementEntry>> loadSavingsEntriesPage(
    String userId, {
    MomoStatementQuery query = const MomoStatementQuery(),
  }) async {
    final page = await loadSavingsStatementPage(userId, query: query);
    final rows = page.entries;
    final needsGroupNameHydration = rows.any(
      (row) => (row['group_name']?.toString().trim().isEmpty ?? true),
    );
    final groupNames = needsGroupNameHydration
        ? await _loadGroupNames(
            rows
                .map((row) => row['group_id']?.toString() ?? '')
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList(growable: false),
          )
        : const <String, String>{};

    return MomoStatementPage<SavingsStatementEntry>(
      entries: rows
          .map(
            (row) => SavingsStatementEntry.fromJson(<String, dynamic>{
              ...row,
              'group_name':
                  row['group_name']?.toString() ??
                  groupNames[row['group_id']?.toString() ?? ''],
            }),
          )
          .toList(growable: false),
      totalCount: page.totalCount,
    );
  }

  Future<List<Map<String, dynamic>>> _loadWalletRows(
    String userId, {
    required MomoStatementQuery query,
  }) async {
    try {
      return _asListOfMaps(
        await _client.rpc(
          'get_wallet_statement_entries',
          params: _statementRpcParams(query),
        ),
      );
    } on PostgrestException {
      var request = _client
          .from('momo_ledger_entries')
          .select(
            'id, entry_type, ledger_status, amount, currency, tx_datetime, '
            'external_reference, tx_category, cashflow_bucket, '
            'counterparty_name, statement_label, description, created_at',
          )
          .eq('user_id', userId)
          .eq('ledger_status', 'posted');

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
            .range(query.offset, query.offset + query.limit - 1),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _loadSavingsRows(
    String userId, {
    required MomoStatementQuery query,
  }) async {
    try {
      return _asListOfMaps(
        await _client.rpc(
          'get_group_savings_statement_entries',
          params: _statementRpcParams(query),
        ),
      );
    } on PostgrestException {
      var request = _client
          .from('group_contributions')
          .select('id, group_id, amount, status, created_at, momo_reference')
          .eq('user_id', userId);

      final startAt = query.startAtUtc;
      final endBefore = query.endBeforeUtc;
      if (startAt != null) {
        request = request.gte('created_at', startAt.toIso8601String());
      }
      if (endBefore != null) {
        request = request.lt('created_at', endBefore.toIso8601String());
      }

      return _asListOfMaps(
        await request
            .order('created_at', ascending: false)
            .range(query.offset, query.offset + query.limit - 1),
      );
    }
  }

  Future<Map<String, String>> _loadGroupNames(List<String> groupIds) async {
    if (groupIds.isEmpty) {
      return const <String, String>{};
    }

    final rows = _asListOfMaps(
      await _client.from('groups').select('id, name').inFilter('id', groupIds),
    );

    return <String, String>{
      for (final row in rows)
        if ((row['id']?.toString() ?? '').isNotEmpty)
          row['id'].toString(): row['name']?.toString() ?? 'Savings group',
    };
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

List<Map<String, dynamic>> _asListOfMaps(dynamic value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }

  return value
      .whereType<Map>()
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

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/momo_statement.dart';

class MomoStatementRepository {
  MomoStatementRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<MomoStatementBundle> loadStatementBundle(String userId) async {
    final walletRows = await _loadWalletRows(userId);
    final savingsRows = await _loadSavingsRows(userId);
    final groupNames = await _loadGroupNames(
      savingsRows
          .map((row) => row['group_id']?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false),
    );

    return MomoStatementBundle(
      walletEntries: walletRows
          .map(MomoWalletEntry.fromJson)
          .toList(growable: false),
      savingsEntries: savingsRows
          .map(
            (row) => SavingsStatementEntry.fromJson(<String, dynamic>{
              ...row,
              'group_name': groupNames[row['group_id']?.toString() ?? ''],
            }),
          )
          .toList(growable: false),
    );
  }

  Future<List<Map<String, dynamic>>> _loadWalletRows(String userId) async {
    try {
      return _asListOfMaps(
        await _client
            .from('momo_ledger_entries')
            .select(
              'id, entry_type, ledger_status, amount, currency, tx_datetime, '
              'external_reference, tx_category, cashflow_bucket, '
              'counterparty_name, statement_label, description, created_at',
            )
            .eq('user_id', userId)
            .eq('ledger_status', 'posted')
            .order('tx_datetime', ascending: false)
            .limit(200),
      );
    } on PostgrestException {
      return _asListOfMaps(
        await _client
            .from('momo_ledger_entries')
            .select(
              'id, entry_type, ledger_status, amount, currency, tx_datetime, '
              'external_reference, description, created_at',
            )
            .eq('user_id', userId)
            .eq('ledger_status', 'posted')
            .order('tx_datetime', ascending: false)
            .limit(200),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _loadSavingsRows(String userId) async {
    return _asListOfMaps(
      await _client
          .from('group_contributions')
          .select('id, group_id, amount, status, created_at, momo_reference')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(200),
    );
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

List<Map<String, dynamic>> _asListOfMaps(dynamic value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }

  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

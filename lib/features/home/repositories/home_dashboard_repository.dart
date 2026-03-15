import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/home_dashboard_data.dart';

class HomeDashboardRepository {
  HomeDashboardRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Future<HomeDashboardData> load(String userId) async {
    final membershipRows = _asListOfMaps(
      await _client
          .from('group_members')
          .select('group_id')
          .eq('user_id', userId),
    );

    final groupIds = membershipRows
        .map((row) => row['group_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final allUserContributionsFuture = _client
        .from('group_contributions')
        .select('amount, status')
        .eq('user_id', userId)
        .eq('status', 'confirmed');
    final walletRecentRowsFuture = _client
        .from('momo_ledger_entries')
        .select(
          'entry_type, ledger_status, amount, currency, tx_datetime, '
          'counterparty_name, statement_label, tx_category, description, '
          'created_at',
        )
        .eq('user_id', userId)
        .order('tx_datetime', ascending: false)
        .order('created_at', ascending: false)
        .limit(8);
    final monthStart = DateTime(DateTime.now().year, DateTime.now().month);
    final walletMonthlyRowsFuture = _client
        .from('momo_ledger_entries')
        .select('entry_type, amount, tx_datetime, created_at')
        .eq('user_id', userId)
        .gte('tx_datetime', monthStart.toUtc().toIso8601String());

    final contributionRows = groupIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : _asListOfMaps(
            await _client
                .from('group_contributions')
                .select('group_id, user_id, amount, status, created_at')
                .inFilter('group_id', groupIds)
                .order('created_at', ascending: false)
                .limit(8),
          );
    final allUserContributions = _asListOfMaps(
      await allUserContributionsFuture,
    );
    final walletRecentRows = _asListOfMaps(await walletRecentRowsFuture);
    final walletMonthlyRows = _asListOfMaps(await walletMonthlyRowsFuture);

    final totalBalance = allUserContributions.fold<int>(0, (sum, row) {
      return sum + (_asMoney(row['amount']) ?? 0);
    });

    final contributionGroupIds = contributionRows
        .map((row) => row['group_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final groupsById = await _loadGroupsById(contributionGroupIds);

    return HomeDashboardData(
      totalBalance: totalBalance,
      monthlyNetChange: calculateHomeMonthlyNetChange(
        contributionRows: contributionRows,
        walletRows: walletMonthlyRows,
        now: DateTime.now(),
      ),
      memberCount: groupIds.length,
      recentTransactions: buildHomeRecentTransactions(
        contributionRows: contributionRows,
        walletRows: walletRecentRows,
        groupsById: groupsById,
      ),
    );
  }

  Future<Map<String, String>> _loadGroupsById(List<String> groupIds) async {
    if (groupIds.isEmpty) {
      return const <String, String>{};
    }

    final rows = _asListOfMaps(
      await _client.from('groups').select('id, name').inFilter('id', groupIds),
    );

    return {
      for (final row in rows)
        if ((row['id']?.toString() ?? '').isNotEmpty)
          row['id'].toString(): row['name']?.toString() ?? 'Group',
    };
  }
}

List<HomeDashboardTransaction> buildHomeRecentTransactions({
  required List<Map<String, dynamic>> contributionRows,
  required List<Map<String, dynamic>> walletRows,
  required Map<String, String> groupsById,
  int limit = 8,
}) {
  final transactions = <HomeDashboardTransaction>[
    for (final row in contributionRows)
      _contributionToDashboardTransaction(row, groupsById: groupsById),
    for (final row in walletRows) _walletToDashboardTransaction(row),
  ]..sort((left, right) => right.recordedAt.compareTo(left.recordedAt));

  return transactions.take(limit).toList(growable: false);
}

int calculateHomeMonthlyNetChange({
  required List<Map<String, dynamic>> contributionRows,
  required List<Map<String, dynamic>> walletRows,
  required DateTime now,
}) {
  final monthStart = DateTime(now.year, now.month);
  var monthlyNetChange = 0;

  for (final row in contributionRows) {
    final status = row['status']?.toString() ?? 'pending';
    final recordedAt = _parseDateTime(row['created_at']);
    if (status != 'confirmed' ||
        recordedAt == null ||
        recordedAt.isBefore(monthStart)) {
      continue;
    }
    monthlyNetChange += _asMoney(row['amount']) ?? 0;
  }

  for (final row in walletRows) {
    final recordedAt =
        _parseDateTime(row['tx_datetime']) ?? _parseDateTime(row['created_at']);
    if (recordedAt == null || recordedAt.isBefore(monthStart)) {
      continue;
    }
    monthlyNetChange += _walletSignedAmount(row);
  }

  return monthlyNetChange;
}

HomeDashboardTransaction _contributionToDashboardTransaction(
  Map<String, dynamic> row, {
  required Map<String, String> groupsById,
}) {
  final amount = _asMoney(row['amount']) ?? 0;
  final recordedAt =
      _parseDateTime(row['created_at']) ??
      DateTime.fromMillisecondsSinceEpoch(0);
  final status = row['status']?.toString() ?? 'pending';
  final groupId = row['group_id']?.toString();
  final groupName = groupId == null ? null : groupsById[groupId];

  return HomeDashboardTransaction(
    title: _titleFor('Contribution', groupName),
    type: 'deposit',
    amount: amount,
    currency: 'RWF',
    recordedAt: recordedAt,
    groupName: groupName,
    status: status,
  );
}

HomeDashboardTransaction _walletToDashboardTransaction(
  Map<String, dynamic> row,
) {
  final entryType = row['entry_type']?.toString().toLowerCase() ?? 'credit';
  final amount = _asMoney(row['amount']) ?? 0;
  final recordedAt =
      _parseDateTime(row['tx_datetime']) ??
      _parseDateTime(row['created_at']) ??
      DateTime.fromMillisecondsSinceEpoch(0);
  final title = _walletTitleFor(row);

  return HomeDashboardTransaction(
    title: title,
    type: entryType,
    amount: amount,
    currency: row['currency']?.toString() ?? 'RWF',
    recordedAt: recordedAt,
    status: row['ledger_status']?.toString(),
  );
}

String _walletTitleFor(Map<String, dynamic> row) {
  final preferredTitle =
      [row['statement_label']?.toString(), row['description']?.toString()]
          .map((value) => value?.trim() ?? '')
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
  if (preferredTitle.isNotEmpty) {
    return preferredTitle;
  }

  final counterparty = row['counterparty_name']?.toString().trim() ?? '';
  final entryType = row['entry_type']?.toString().toLowerCase() ?? 'credit';
  if (counterparty.isNotEmpty) {
    return entryType == 'debit'
        ? 'Sent money to $counterparty'
        : 'Received money from $counterparty';
  }

  final category = row['tx_category']?.toString().trim() ?? '';
  if (category.isNotEmpty) {
    return category
        .split('_')
        .map((segment) {
          if (segment.isEmpty) {
            return segment;
          }
          return '${segment[0].toUpperCase()}${segment.substring(1)}';
        })
        .join(' ');
  }

  return 'Wallet transaction';
}

int _walletSignedAmount(Map<String, dynamic> row) {
  final amount = _asMoney(row['amount']) ?? 0;
  final entryType = row['entry_type']?.toString().toLowerCase() ?? 'credit';
  return entryType == 'debit' ? -amount.abs() : amount.abs();
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

int? _asMoney(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value.toString());
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}

String _titleFor(String type, String? groupName) {
  final normalized = type.trim();
  if (groupName == null || groupName.isEmpty) {
    return normalized;
  }

  return '$normalized · $groupName';
}

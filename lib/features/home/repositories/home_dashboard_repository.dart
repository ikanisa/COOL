import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/home_dashboard_data.dart';

class HomeDashboardRepository {
  HomeDashboardRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<HomeDashboardData> load(String userId) async {
    // ── 1. Find group memberships for the current user ──────────────
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

    if (groupIds.isEmpty) {
      return HomeDashboardData(totalBalance: 0, monthlyNetChange: 0);
    }

    final contributionRowsFuture = _client
        .from('group_contributions')
        .select('group_id, user_id, amount, status, created_at')
        .inFilter('group_id', groupIds)
        .order('created_at', ascending: false)
        .limit(8);
    final allUserContributionsFuture = _client
        .from('group_contributions')
        .select('amount, status')
        .eq('user_id', userId)
        .eq('status', 'confirmed');

    final contributionRows = _asListOfMaps(await contributionRowsFuture);
    final allUserContributions = _asListOfMaps(
      await allUserContributionsFuture,
    );

    final totalBalance = allUserContributions.fold<int>(0, (sum, row) {
      return sum + (_asMoney(row['amount']) ?? 0);
    });

    // ── 4. Load group names for display ─────────────────────────────
    final contributionGroupIds = contributionRows
        .map((row) => row['group_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final groupsById = await _loadGroupsById(contributionGroupIds);

    // ── 5. Build recent transactions + monthly net ──────────────────
    final monthStart = DateTime(DateTime.now().year, DateTime.now().month);
    var monthlyNetChange = 0;
    final recentTransactions = <HomeDashboardTransaction>[];

    for (final row in contributionRows) {
      final amount = _asMoney(row['amount']) ?? 0;
      final recordedAt = _parseDateTime(row['created_at']) ?? DateTime.now();
      final status = row['status']?.toString() ?? 'pending';
      final groupId = row['group_id']?.toString();
      final groupName = groupId == null ? null : groupsById[groupId];

      final transaction = HomeDashboardTransaction(
        title: _titleFor('Contribution', groupName),
        type: 'Deposit',
        amount: amount,
        currency: 'RWF',
        recordedAt: recordedAt,
        groupName: groupName,
        status: status,
      );
      recentTransactions.add(transaction);

      if (status == 'confirmed' && !recordedAt.isBefore(monthStart)) {
        monthlyNetChange += transaction.signedAmount;
      }
    }

    return HomeDashboardData(
      totalBalance: totalBalance,
      monthlyNetChange: monthlyNetChange,
      memberCount: groupIds.length,
      recentTransactions: recentTransactions,
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

  String _titleFor(String type, String? groupName) {
    final normalized = type.trim();
    if (groupName == null || groupName.isEmpty) {
      return normalized;
    }

    return '$normalized · $groupName';
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

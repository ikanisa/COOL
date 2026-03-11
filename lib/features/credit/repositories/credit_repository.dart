import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/credit_dashboard.dart';

class CreditRepository {
  CreditRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<CreditDashboard> loadDashboard(String userId) async {
    final statementCount = await _loadAnalyzedTransactionCount(userId);
    final scoreRows = await _loadScoreRows(
      userId,
      fallbackStatementCount: statementCount,
    );

    if (scoreRows.isEmpty) {
      return CreditDashboard(statementCount: statementCount);
    }

    final latest = scoreRows.first;
    final lastUpdated =
        _parseDateTime(latest['generated_at']) ??
        _parseDateTime(latest['recorded_at']);

    // Build factors directly from the score row columns
    final factors = <CreditFactor>[];
    const factorSpecs = <({String key, String label, String emoji})>[
      (key: 'cashflow_stability', label: 'Wallet Cashflow', emoji: '📲'),
      (key: 'savings_discipline', label: 'Savings Discipline', emoji: '💰'),
      (key: 'group_reliability', label: 'Group Reliability', emoji: '👥'),
      (key: 'profile_strength', label: 'Profile Strength', emoji: '🪪'),
    ];
    for (final spec in factorSpecs) {
      final value = _tryAsInt(latest[spec.key]);
      if (value != null) {
        factors.add(
          CreditFactor(
            key: spec.key,
            label: spec.label,
            emoji: spec.emoji,
            score: value.clamp(0, 100),
          ),
        );
      }
    }

    return CreditDashboard(
      statementCount: _tryAsInt(latest['statement_count']) ?? statementCount,
      groupContributionCount: _asInt(latest['group_contribution_count']),
      activeMonthCount: _asInt(latest['active_month_count']),
      score: _asInt(latest['score']),
      scoreBand: _stringOrNull(latest['score_band']),
      summary:
          _stringOrNull(latest['score_summary']) ??
          _summaryForScore(_asInt(latest['score'])),
      periodStart:
          _parseDateTime(latest['scoring_window_start']) ?? lastUpdated,
      periodEnd:
          _parseDateTime(latest['scoring_window_end']) ??
          _parseDateTime(latest['recorded_at']) ??
          lastUpdated,
      lastUpdated: lastUpdated,
      reasonCodes: _asStringList(latest['reason_codes']),
      factors: factors,
      history: scoreRows
          .map(
            (row) => CreditHistoryPoint(
              label: _historyLabel(
                _parseDateTime(row['generated_at']) ??
                    _parseDateTime(row['recorded_at']),
              ),
              score: _asInt(row['score']),
              recordedAt:
                  _parseDateTime(row['generated_at']) ??
                  _parseDateTime(row['recorded_at']) ??
                  DateTime.now(),
            ),
          )
          .toList(growable: false)
          .reversed
          .toList(growable: false),
    );
  }

  String _historyLabel(DateTime? value) {
    if (value == null) {
      return 'Now';
    }
    return DateFormat('MMM').format(value);
  }

  String _summaryForScore(
    int score, {
    int excellent = 720,
    int good = 640,
    int building = 560,
  }) {
    if (score >= excellent) {
      return 'Strong verified wallet and savings behaviour.';
    }
    if (score >= good) {
      return 'Healthy activity with room to strengthen consistency.';
    }
    if (score >= building) {
      return 'The credit file is forming, but it is still thin.';
    }
    return 'Limited verified history is available right now.';
  }

  Future<int> _loadAnalyzedTransactionCount(String userId) async {
    try {
      final ledgerRows = _asListOfMaps(
        await _client
            .from('momo_ledger_entries')
            .select('id')
            .eq('user_id', userId)
            .eq('ledger_status', 'posted'),
      );
      return ledgerRows.length;
    } on PostgrestException {
      final smsRows = _asListOfMaps(
        await _client.from('momo_sms_raw').select('id').eq('user_id', userId),
      );
      return smsRows.length;
    }
  }

  Future<List<Map<String, dynamic>>> _loadScoreRows(
    String userId, {
    required int fallbackStatementCount,
  }) async {
    try {
      final rows = _asListOfMaps(
        await _client
            .from('credit_score_runs')
            .select(
              'score, score_band, score_summary, statement_count, '
              'group_contribution_count, active_month_count, '
              'cashflow_stability, savings_discipline, group_reliability, '
              'profile_strength, reason_codes, scoring_window_start, '
              'scoring_window_end, generated_at',
            )
            .eq('user_id', userId)
            .order('generated_at', ascending: false)
            .limit(6),
      );
      if (rows.isNotEmpty) {
        return rows;
      }
    } on PostgrestException {
      // Fall through to the legacy score table while older environments catch up.
    }

    final legacyRows = _asListOfMaps(
      await _client
          .from('credit_scores')
          .select(
            'score, saving_consistency, group_participation, '
            'payment_history, community_activity, recorded_at',
          )
          .eq('user_id', userId)
          .order('recorded_at', ascending: false)
          .limit(6),
    );

    return legacyRows
        .map((row) {
          final score = _asInt(row['score']);
          return <String, dynamic>{
            'score': score,
            'score_band': _legacyBand(score),
            'score_summary': _summaryForScore(score),
            'statement_count': fallbackStatementCount,
            'group_contribution_count': 0,
            'active_month_count': 0,
            'cashflow_stability': _asInt(row['payment_history']),
            'savings_discipline': _asInt(row['saving_consistency']),
            'group_reliability': _asInt(row['group_participation']),
            'profile_strength': _asInt(row['community_activity']),
            'reason_codes': _legacyReasonCodes(row),
            'scoring_window_start': row['recorded_at'],
            'scoring_window_end': row['recorded_at'],
            'generated_at': row['recorded_at'],
            'recorded_at': row['recorded_at'],
          };
        })
        .toList(growable: false);
  }

  String _legacyBand(int score) {
    if (score >= 720) {
      return 'excellent';
    }
    if (score >= 640) {
      return 'good';
    }
    if (score >= 560) {
      return 'building';
    }
    return 'limited_history';
  }

  List<String> _legacyReasonCodes(Map<String, dynamic> row) {
    final reasons = <String>[];
    if (_asInt(row['payment_history']) < 60) {
      reasons.add('wallet_activity_low');
    }
    if (_asInt(row['saving_consistency']) < 60) {
      reasons.add('savings_pattern_thin');
    }
    if (_asInt(row['group_participation']) < 60) {
      reasons.add('group_activity_low');
    }
    if (_asInt(row['community_activity']) < 60) {
      reasons.add('profile_verification_needed');
    }
    return reasons;
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

int _asInt(dynamic value) => _tryAsInt(value) ?? 0;

int? _tryAsInt(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString());
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}

String? _stringOrNull(dynamic value) {
  if (value == null) {
    return null;
  }
  final normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

List<String> _asStringList(dynamic value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

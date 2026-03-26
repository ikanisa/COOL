import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/supabase_client_provider.dart';

class MomoRiskResult {
  const MomoRiskResult({
    required this.riskScore,
    required this.isAnomaly,
    required this.reason,
    required this.warningTitle,
    required this.warningBody,
    required this.trustScore,
    required this.actionSuggestion,
  });

  factory MomoRiskResult.fromJson(Map<String, dynamic> json) {
    return MomoRiskResult(
      riskScore: (json['risk_score'] as num).toDouble(),
      isAnomaly: json['is_anomaly'] as bool,
      reason: json['reason'] as String,
      warningTitle: json['warning_title'] as String,
      warningBody: json['warning_body'] as String,
      trustScore: (json['trust_score'] as num).toDouble(),
      actionSuggestion: json['action_suggestion'] as String,
    );
  }

  final double riskScore;
  final bool isAnomaly;
  final String reason;
  final String warningTitle;
  final String warningBody;
  final double trustScore;
  final String actionSuggestion;

  bool get shouldWarn => actionSuggestion == 'warn' || riskScore > 0.5;
  bool get shouldBlock =>
      actionSuggestion == 'block_high_risk' || riskScore > 0.9;
}

class MomoRiskNotifier extends StateNotifier<AsyncValue<MomoRiskResult?>> {
  MomoRiskNotifier(this._client) : super(const AsyncValue.data(null));

  final SupabaseClient _client;

  Future<MomoRiskResult?> evaluateRisk({
    required String recipientNumber,
    required int amount,
    required String currency,
  }) async {
    state = const AsyncValue.loading();
    try {
      final response = await _client.functions.invoke(
        'evaluate-transfer-risk',
        body: {
          'recipientNumber': recipientNumber,
          'amount': amount,
          'currency': currency,
        },
      );

      if (response.data != null && response.data['success'] == true) {
        final result = MomoRiskResult.fromJson(
          Map<String, dynamic>.from(response.data['data'] as Map),
        );
        state = AsyncValue.data(result);
        return result;
      }
      throw Exception('Risk evaluation failed');
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }
}

final momoRiskProvider =
    StateNotifierProvider<MomoRiskNotifier, AsyncValue<MomoRiskResult?>>((ref) {
      return MomoRiskNotifier(ref.read(supabaseClientProvider));
    });

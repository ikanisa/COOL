import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_check_service.dart';
import '../../../core/services/operational_health_service.dart';
import '../../../core/utils/json_helpers.dart' as jh;
import '../models/biopay_enrollment_draft.dart';
import '../models/biopay_match_result.dart';
import '../models/biopay_payment_intent.dart';
import '../models/biopay_profile.dart';

typedef BiopayAppCheckTokenProvider = Future<String> Function();

class BiopayRepository {
  BiopayRepository({
    required SupabaseClient client,
    OperationalHealthService? operationalHealthService,
    BiopayAppCheckTokenProvider? appCheckTokenProvider,
  }) : _client = client,
       _operationalHealthService =
           operationalHealthService ?? OperationalHealthService(client: client),
       _appCheckTokenProvider =
           appCheckTokenProvider ??
           (() =>
               AppCheckService.requireLimitedUseToken(featureName: 'BioPay'));

  final SupabaseClient _client;
  final OperationalHealthService _operationalHealthService;
  final BiopayAppCheckTokenProvider _appCheckTokenProvider;

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<Map<String, String>> _buildAttestedHeaders() async {
    final appCheckToken = await _appCheckTokenProvider();
    return <String, String>{'X-Firebase-AppCheck': appCheckToken};
  }

  Future<BiopayProfile?> getMyProfile() async {
    final userId = currentUserId;
    if (userId == null || userId.isEmpty) {
      return null;
    }

    final row = await _client
        .from('biopay_profiles')
        .select()
        .eq('user_id', userId)
        .eq('active', true)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    return BiopayProfile.fromJson(Map<String, dynamic>.from(row));
  }

  Future<BiopayProfile> enroll({
    required BiopayEnrollmentDraft draft,
    required List<double> embedding,
    Map<String, Object?>? liveness,
  }) async {
    try {
      final headers = await _buildAttestedHeaders();
      final response = await _client.functions.invoke(
        'biopay-enroll',
        body: draft.toPayload(embedding, liveness: liveness),
        headers: headers,
      );
      final payload = jh.asMap(response.data);
      if (payload['success'] != true) {
        throw StateError(
          payload['message']?.toString() ?? 'BioPay enrollment failed.',
        );
      }
      final data = jh.asMap(payload['data']);
      return BiopayProfile.fromJson(data);
    } catch (error) {
      await _operationalHealthService.recordEvent(
        service: 'biopay',
        component: 'enrollment',
        status: OperationalHealthStatus.error,
        message: 'BioPay enrollment failed.',
        issueCode: 'biopay_enroll_failed',
        metadata: <String, dynamic>{'error': error.toString()},
      );
      rethrow;
    }
  }

  Future<BiopayMatchResult> matchEmbedding(
    List<double> embedding, {
    Map<String, Object?>? liveness,
  }) async {
    try {
      final headers = await _buildAttestedHeaders();
      final response = await _client.functions.invoke(
        'biopay-match',
        body: <String, Object?>{
          'embedding': embedding,
          ...?(liveness == null
              ? null
              : <String, Object?>{'liveness': liveness}),
        },
        headers: headers,
      );
      final payload = jh.asMap(response.data);
      if (payload['success'] != true) {
        throw StateError(
          payload['message']?.toString() ?? 'BioPay match failed.',
        );
      }
      final data = jh.asMap(payload['data']);
      return BiopayMatchResult.fromApiResponse(data);
    } catch (error) {
      await _operationalHealthService.recordEvent(
        service: 'biopay',
        component: 'matching',
        status: OperationalHealthStatus.error,
        message: 'BioPay matching failed.',
        issueCode: 'biopay_match_failed',
        metadata: <String, dynamic>{'error': error.toString()},
      );
      rethrow;
    }
  }

  Future<void> revoke({String? reason}) async {
    try {
      final headers = await _buildAttestedHeaders();
      final response = await _client.functions.invoke(
        'biopay-revoke',
        body: <String, Object?>{'reason': reason},
        headers: headers,
      );
      final payload = jh.asMap(response.data);
      if (payload['success'] != true) {
        throw StateError(
          payload['message']?.toString() ?? 'BioPay revocation failed.',
        );
      }
    } catch (error) {
      await _operationalHealthService.recordEvent(
        service: 'biopay',
        component: 'revocation',
        status: OperationalHealthStatus.error,
        message: 'BioPay revocation failed.',
        issueCode: 'biopay_revoke_failed',
        metadata: <String, dynamic>{'error': error.toString()},
      );
      rethrow;
    }
  }

  /// Create a server-issued payment intent for a matched profile.
  ///
  /// The intent includes a server-generated USSD code and expires after 5 min.
  /// Any existing pending intents for this user are cancelled server-side.
  Future<BiopayPaymentIntent> createPaymentIntent({
    required String profilePublicId,
    required double matchScore,
  }) async {
    try {
      final headers = await _buildAttestedHeaders();
      final response = await _client.functions.invoke(
        'biopay-create-payment-intent',
        body: <String, Object?>{
          'profile_public_id': profilePublicId,
          'match_score': matchScore,
        },
        headers: headers,
      );
      final payload = jh.asMap(response.data);
      if (payload['success'] != true) {
        throw StateError(
          payload['message']?.toString() ?? 'Failed to create payment intent.',
        );
      }
      final data = jh.asMap(payload['data']);
      return BiopayPaymentIntent.fromApiResponse(data);
    } catch (error) {
      await _operationalHealthService.recordEvent(
        service: 'biopay',
        component: 'payment_intent',
        status: OperationalHealthStatus.error,
        message: 'Payment intent creation failed.',
        issueCode: 'biopay_create_intent_failed',
        metadata: <String, dynamic>{'error': error.toString()},
      );
      rethrow;
    }
  }

  /// Mark a pending intent as dialed (one-time use enforcement).
  Future<void> markIntentDialed(String intentId) async {
    await _client
        .from('biopay_payment_intents')
        .update(<String, Object?>{
          'status': 'dialed',
          'dialed_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', intentId)
        .eq('user_id', currentUserId ?? '')
        .eq('status', 'pending');
  }
}

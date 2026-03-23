import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/operational_health_service.dart';
import '../../../core/utils/json_helpers.dart' as jh;
import '../models/biopay_enrollment_draft.dart';
import '../models/biopay_match_result.dart';
import '../models/biopay_profile.dart';

class BiopayRepository {
  BiopayRepository({
    required SupabaseClient client,
    OperationalHealthService? operationalHealthService,
  }) : _client = client,
       _operationalHealthService =
           operationalHealthService ?? OperationalHealthService(client: client);

  final SupabaseClient _client;
  final OperationalHealthService _operationalHealthService;

  String? get currentUserId => _client.auth.currentUser?.id;

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
  }) async {
    try {
      final response = await _client.functions.invoke(
        'biopay-enroll',
        body: draft.toPayload(embedding),
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

  Future<BiopayMatchResult> matchEmbedding(List<double> embedding) async {
    try {
      final response = await _client.functions.invoke(
        'biopay-match',
        body: <String, Object?>{'embedding': embedding},
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
      final response = await _client.functions.invoke(
        'biopay-revoke',
        body: <String, Object?>{'reason': reason},
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
}

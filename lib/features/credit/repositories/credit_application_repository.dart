import 'package:supabase_flutter/supabase_flutter.dart';

import '../../partners/models/partner.dart';
import '../models/partner_credit_application.dart';

class CreditApplicationRepository {
  CreditApplicationRepository({required SupabaseClient client})
    : _client = client;

  final SupabaseClient _client;

  Future<List<PartnerCreditApplication>> fetchMyApplications() async {
    final rows = await _client
        .from('partner_credit_applications')
        .select(
          'id, user_id, partner_id, application_type, status, readiness_state, '
          'requested_product, applicant_note, official_name, official_phone, '
          'kyc_status, credit_score, credit_score_band, credit_score_version, '
          'score_summary, snapshot_payload, submitted_at, last_handoff_at, '
          'last_handoff_channel, last_destination_path, created_at, updated_at, '
          'partners(name, slug, emoji)',
        )
        .order('created_at', ascending: false)
        .limit(12);

    return List<Map<String, dynamic>>.from(
      rows,
    ).map(PartnerCreditApplication.fromJson).toList(growable: false);
  }

  Future<PartnerCreditApplication> createApplication({
    required Partner partner,
    required String applicationType,
    required String readinessState,
    String? requestedProduct,
    String? applicantNote,
    required bool submitNow,
    String handoffChannel = 'in_app_redirect',
    String? destinationPath,
  }) async {
    final raw = await _client.rpc(
      'create_partner_credit_application',
      params: <String, dynamic>{
        'p_partner_id': partner.id,
        'p_application_type': applicationType,
        'p_readiness_state': readinessState,
        'p_requested_product': requestedProduct,
        'p_applicant_note': applicantNote,
        'p_submit_now': submitNow,
        'p_handoff_channel': handoffChannel,
        'p_destination_path': destinationPath,
      },
    );

    final row = _asMap(raw);
    return PartnerCreditApplication.fromJson(<String, dynamic>{
      ...row,
      'partners': <String, dynamic>{
        'name': partner.name,
        'slug': partner.slug,
        'emoji': partner.emoji,
      },
    });
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw StateError(
    'Expected a JSON object from create_partner_credit_application.',
  );
}

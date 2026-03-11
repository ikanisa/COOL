import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/referral_attribution.dart';

class ReferralRepository {
  ReferralRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<ReferralInviteLink> createInviteLink({
    required String inviteCode,
    required Uri baseUri,
    String? shareChannel,
    String? campaignId,
  }) async {
    final response = await _client.rpc(
      'create_referral_invite',
      params: <String, dynamic>{
        'p_invite_code': inviteCode,
        'p_share_channel': shareChannel,
        'p_deep_link': baseUri.toString(),
        'p_campaign_id': campaignId,
      },
    );

    final row = Map<String, dynamic>.from(response as Map);
    final inviteId = row['id']?.toString();
    if (inviteId == null || inviteId.isEmpty) {
      throw StateError('Referral invite creation did not return an id.');
    }

    final queryParameters = <String, String>{
      ...baseUri.queryParameters,
      'ri': inviteId,
      if (campaignId != null && campaignId.trim().isNotEmpty)
        'campaign': campaignId.trim(),
    };

    return ReferralInviteLink(
      inviteId: inviteId,
      campaignId: campaignId,
      uri: baseUri.replace(queryParameters: queryParameters),
    );
  }

  Future<void> markInviteOpened(String inviteId) async {
    await _client.rpc(
      'mark_referral_invite_opened',
      params: <String, dynamic>{'p_referral_invite_id': inviteId},
    );
  }

  Future<void> activateInvite({
    required String inviteId,
    required String qualifyingEventType,
    String? qualifyingEventId,
    int inviterPoints = 150,
    int inviteePoints = 50,
  }) async {
    await _client.rpc(
      'activate_referral_invite',
      params: <String, dynamic>{
        'p_referral_invite_id': inviteId,
        'p_qualifying_event_type': qualifyingEventType,
        'p_qualifying_event_id': qualifyingEventId,
        'p_inviter_points': inviterPoints,
        'p_invitee_points': inviteePoints,
      },
    );
  }
}

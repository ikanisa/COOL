part of 'collect_repository.dart';

class _CollectLiveReader {
  const _CollectLiveReader(this._supabase);

  final SupabaseClient? _supabase;

  Future<CollectProfile?> fetchProfile(String userId) async {
    final supabase = _supabase;
    if (supabase == null) return null;
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) return null;
    final row = await supabase.rpc<dynamic>('get_current_profile');
    if (row == null) return null;
    return CollectProfile.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<CollectProfile> ensureLiveProfile(
    String userId,
    String normalizedPhone, {
    String? countryCode,
  }) async {
    final supabase = _supabase;
    final currentUser = supabase?.auth.currentUser;
    if (supabase == null || currentUser == null || currentUser.id != userId) {
      throw StateError('Sign in first');
    }
    final row = await supabase.rpc<dynamic>(
      'ensure_current_profile',
      params: {
        'p_whatsapp_phone': normalizedPhone,
        'p_country_code': countryCode,
      },
    );
    if (row == null) {
      throw StateError('Collect profile could not be created');
    }
    return CollectProfile.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<List<CollectCollection>> fetchCollections() async {
    final rows = await _supabase!
        .from('member_collections_view')
        .select()
        .order('created_at', ascending: false);
    final mappedRows = [
      for (final row in rows) Map<String, dynamic>.from(row as Map),
    ];
    return [for (final row in mappedRows) CollectCollection.fromJson(row)];
  }

  Future<List<CollectCollection>> fetchPublicCollections() async {
    final rows = await _supabase!
        .from('public_collections_view')
        .select()
        .order('created_at', ascending: false);
    return [
      for (final row in rows)
        CollectCollection.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<CollectCollection> fetchCollection(String id) async {
    final row = await _supabase!
        .from('member_collections_view')
        .select()
        .eq('id', id)
        .single();
    return CollectCollection.fromJson(Map<String, dynamic>.from(row));
  }

  Future<List<PaymentIntentModel>> fetchPaymentIntents(
    CollectProfile? profile,
  ) async {
    final response = await _supabase!.rpc<dynamic>(
      profile?.isRwanda == true
          ? 'list_current_user_payment_intents'
          : 'list_current_user_bank_transfer_intents',
    );
    final rows = response is List ? response : const [];
    return [
      for (final row in rows)
        PaymentIntentModel.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<List<Contribution>> fetchContributions(CollectProfile? profile) async {
    final response = await _supabase!.rpc<dynamic>(
      profile?.isRwanda == true
          ? 'list_current_user_contributions'
          : 'list_current_user_bank_contributions',
    );
    final rows = response is List ? response : const [];
    return [
      for (final row in rows)
        Contribution.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<Map<String, CollectionSummary>> fetchCollectionSummaries(
    CollectProfile? profile,
  ) async {
    final response = await _supabase!.rpc<dynamic>(
      profile?.isRwanda == true
          ? 'list_current_user_collection_summaries'
          : 'list_current_user_bank_collection_summaries',
    );
    final rows = response is List ? response : const [];
    return {
      for (final row in rows)
        if (row is Map && row['collection_id'] is String)
          row['collection_id'] as String: CollectionSummary.fromJson(
            Map<String, dynamic>.from(row),
          ),
    };
  }

  Future<NotificationPreferences> fetchNotificationPreferences(
    CollectProfile? profile,
  ) async {
    final supabase = _supabase;
    if (supabase == null || profile == null) {
      return NotificationPreferences.defaults;
    }
    final rows = await supabase
        .from('notification_preferences')
        .select()
        .eq('user_id', profile.id)
        .limit(1);
    if (rows.isEmpty) return NotificationPreferences.defaults;
    return NotificationPreferences.fromJson(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  Future<List<NotificationEvent>> fetchNotificationEvents(
    CollectProfile? profile,
  ) async {
    final supabase = _supabase;
    if (supabase == null || profile == null) return const [];
    final rows = await supabase
        .from('notification_events')
        .select()
        .eq('user_id', profile.id)
        .order('created_at', ascending: false)
        .limit(100);
    return [
      for (final row in rows)
        NotificationEvent.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }
}

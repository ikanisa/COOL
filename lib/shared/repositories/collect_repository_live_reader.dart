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
    String normalizedPhone,
  ) async {
    final existing = await fetchProfile(userId);
    if (existing != null) {
      return applyWhatsappMomoDefault(existing, normalizedPhone);
    }
    final supabase = _supabase;
    if (supabase == null || supabase.auth.currentUser == null) {
      throw StateError('Sign in first');
    }
    final row = await supabase.rpc<dynamic>(
      'ensure_current_profile',
      params: {'whatsapp_phone': normalizedPhone},
    );
    if (row == null) {
      throw StateError('Collect profile could not be created');
    }
    return applyWhatsappMomoDefault(
      CollectProfile.fromJson(Map<String, dynamic>.from(row as Map)),
      normalizedPhone,
    );
  }

  Future<CollectProfile> applyWhatsappMomoDefault(
    CollectProfile profile,
    String normalizedPhone,
  ) async {
    if (profile.momoNumber?.trim().isNotEmpty == true) return profile;
    final localMomo = PhoneNormalizer.tryNormalizeMtnMomoLocal(normalizedPhone);
    if (localMomo == null) return profile;

    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      await supabase
          .from('profiles')
          .update({
            'momo_number': localMomo,
            'momo_number_hash': HashUtils.phoneHash(localMomo),
          })
          .eq('id', profile.id);
    }
    return profile.copyWith(momoNumber: localMomo);
  }

  Future<List<CollectCollection>> fetchCollections() async {
    final rows = await _supabase!
        .from('member_collections_view')
        .select()
        .order('created_at', ascending: false);
    final mappedRows = [
      for (final row in rows) Map<String, dynamic>.from(row as Map),
    ];
    final collections = [
      for (final row in mappedRows) CollectCollection.fromJson(row),
    ];
    return attachAuthorizedReceivers(collections);
  }

  Future<CollectCollection> fetchCollection(String id) async {
    final row = await _supabase!
        .from('member_collections_view')
        .select()
        .eq('id', id)
        .single();
    final collections = await attachAuthorizedReceivers([
      CollectCollection.fromJson(Map<String, dynamic>.from(row)),
    ]);
    return collections.single;
  }

  Future<List<CollectCollection>> attachAuthorizedReceivers(
    List<CollectCollection> collections,
  ) async {
    if (collections.isEmpty) return collections;
    final collectionIds = [for (final collection in collections) collection.id];
    final rows = await _supabase!
        .from('collection_receivers')
        .select('collection_id, momo_number, label')
        .inFilter('collection_id', collectionIds)
        .eq('is_active', true);
    final receiversByCollection = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final mapped = Map<String, dynamic>.from(row as Map);
      receiversByCollection.putIfAbsent(
        mapped['collection_id'] as String,
        () => mapped,
      );
    }
    return [
      for (final collection in collections)
        if (receiversByCollection[collection.id] case final receiver?)
          collection.copyWith(
            receiverMomoNumber: receiver['momo_number'] as String?,
            receiverDisplayLabel: receiver['label'] as String?,
          )
        else
          collection,
    ];
  }

  Future<List<PaymentIntentModel>> fetchPaymentIntents() async {
    final rows = await _supabase!
        .from('payment_intents')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    return [
      for (final row in rows)
        PaymentIntentModel.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<List<Contribution>> fetchContributions() async {
    final supabase = _supabase!;
    final safeRows = await supabase
        .from('public_contributions_view')
        .select()
        .order('posted_at', ascending: false)
        .limit(200);
    final memberRows = await supabase
        .from('member_contributions_view')
        .select()
        .order('created_at', ascending: false)
        .limit(200);

    final byId = <String, Contribution>{};
    for (final row in safeRows) {
      final contribution = Contribution.fromJson(
        Map<String, dynamic>.from(row as Map),
      );
      byId[contribution.id] = contribution;
    }
    for (final row in memberRows) {
      final contribution = Contribution.fromJson(
        Map<String, dynamic>.from(row as Map),
      );
      byId[contribution.id] = contribution;
    }
    final contributions = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return contributions;
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
}

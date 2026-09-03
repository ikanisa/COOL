part of 'collect_repository.dart';

class _CollectLiveReader {
  const _CollectLiveReader(this._supabase);

  final SupabaseClient? _supabase;

  Future<CollectProfile?> fetchProfile(String userId) async {
    final supabase = _supabase;
    if (supabase == null) return null;
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) return null;
    final row = await supabase.rpc<dynamic>('get_current_member_profile');
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
      'ensure_current_member_profile',
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
    return _fetchMemberCollections();
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
    final collections = await _fetchMemberCollections(collectionId: id);
    if (collections.length != 1) {
      throw StateError('Group is not available');
    }
    return collections.single;
  }

  Future<List<CollectCollection>> _fetchMemberCollections({
    String? collectionId,
  }) async {
    final response = await _supabase!.rpc<dynamic>(
      'list_current_user_collections',
      params: {'p_collection_id': ?collectionId},
    );
    if (response is! List) {
      throw const FormatException('Group response is unavailable');
    }
    return [
      for (final row in response)
        CollectCollection.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<List<Map<String, dynamic>>> _financialRows(String rpc) async {
    final response = await _supabase!.rpc<dynamic>(rpc);
    if (response is! List || response.any((row) => row is! Map)) {
      throw const FormatException('Financial history is unavailable');
    }
    return [for (final row in response) Map<String, dynamic>.from(row as Map)];
  }

  Future<({List<PaymentIntentModel> items, int pendingCount})>
  fetchRecentIntents({String? intentId}) async {
    final response = await _supabase!.rpc<dynamic>(
      'list_current_member_recent_intents',
      params: {'p_intent_id': ?intentId},
    );
    if (response is! Map ||
        response['pending_count'] is! int ||
        (response['pending_count'] as int) < 0) {
      throw const FormatException('Invalid intent response');
    }
    final rows = _pageRows(response);
    _validatePaymentRows(rows, intents: true);
    return (
      items: [for (final row in rows) PaymentIntentModel.fromJson(row)],
      pendingCount: response['pending_count'] as int,
    );
  }

  Future<MemberHistoryPage> fetchHistoryPage(
    MemberHistoryQuery query, {
    Map<String, dynamic>? cursor,
  }) async {
    final response = await _supabase!.rpc<dynamic>(
      'list_current_member_history_page',
      params: {
        'p_collection_id': ?query.collectionId,
        'p_query': query.search,
        'p_sort': query.sort,
        'p_cursor': ?cursor,
        'p_limit': 50,
      },
    );
    final rows = _pageRows(response);
    _validatePaymentRows(rows, intents: false);
    final page = MemberHistoryPage.fromJson(
      Map<String, dynamic>.from(response as Map),
      [for (final row in rows) Contribution.fromJson(row)],
    );
    if (cursor == null &&
        page.nextCursor == null &&
        page.items.length != page.totalCount) {
      throw const FormatException('Incomplete history response');
    }
    return page;
  }

  List<Map<String, dynamic>> _pageRows(dynamic response) {
    if (response is! Map ||
        response['items'] is! List ||
        (response['items'] as List).length > 50 ||
        (response['items'] as List).any((row) => row is! Map)) {
      throw const FormatException('Invalid financial page');
    }
    return [
      for (final row in response['items'] as List)
        Map<String, dynamic>.from(row as Map),
    ];
  }

  void _validatePaymentRows(
    List<Map<String, dynamic>> rows, {
    required bool intents,
  }) {
    final keys = <String>{};
    for (final row in rows) {
      final id = row[intents ? 'id' : 'payment_id'];
      final rail = row['rail'];
      final currency = row['currency'];
      final amount = row['amount_minor'];
      final date = row[intents ? 'created_at' : 'posted_at'];
      if (id is! String ||
          id.isEmpty ||
          row['collection_id'] is! String ||
          !((rail == 'rwanda_momo' && currency == 'RWF') ||
              (rail == 'diaspora_bank' && currency == 'EUR')) ||
          amount is! int ||
          amount <= 0 ||
          date is! String ||
          DateTime.tryParse(date) == null ||
          !keys.add('$rail:$id') ||
          (intents &&
              (row['expires_at'] is! String ||
                  DateTime.tryParse(row['expires_at'] as String) == null ||
                  row['status'] is! String))) {
        throw const FormatException('Invalid payment history');
      }
    }
  }

  Future<Map<String, CollectionSummary>> fetchCollectionSummaries() async {
    final rows = await _financialRows(
      'list_current_member_collection_balances',
    );
    if (rows.any(
          (row) => row['collection_id'] is! String || row['balances'] is! List,
        ) ||
        rows.map((row) => row['collection_id']).toSet().length != rows.length) {
      throw const FormatException('Group balances are unavailable');
    }
    return {
      for (final row in rows)
        row['collection_id'] as String: CollectionSummary.fromJson(row),
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

part of 'collect_repository.dart';

class _CollectAccessMismatch implements Exception {
  const _CollectAccessMismatch();
}

class _CollectLiveReader {
  const _CollectLiveReader(this._backend);

  final CollectCloudflareClient? _backend;

  Future<CollectProfile?> fetchProfile(
    String userId, {
    String? accessToken,
  }) async {
    final backend = _backend;
    if (backend == null) return null;
    final currentUser = backend.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) return null;
    var request = backend.rpc<dynamic>('get_current_member_profile');
    if (accessToken != null) {
      request = request.setHeader('Authorization', 'Bearer $accessToken');
    }
    final row = await request;
    if (row == null) return null;
    final profile = CollectProfile.fromJson(
      Map<String, dynamic>.from(row as Map),
    );
    if (profile.id != userId) {
      throw const _CollectAccessMismatch();
    }
    return profile;
  }

  Future<CollectProfile> ensureLiveProfile(
    String userId,
    String normalizedPhone, {
    String? countryCode,
  }) async {
    final backend = _backend;
    final currentUser = backend?.auth.currentUser;
    if (backend == null || currentUser == null || currentUser.id != userId) {
      throw StateError('Sign in first');
    }
    final row = await backend.rpc<dynamic>(
      'ensure_current_member_profile',
      params: {
        'p_whatsapp_phone': normalizedPhone,
        'p_country_code': countryCode,
      },
    );
    if (row == null) {
      throw StateError('Collect profile could not be created');
    }
    final profile = CollectProfile.fromJson(
      Map<String, dynamic>.from(row as Map),
    );
    if (profile.id != userId) {
      throw const _CollectAccessMismatch();
    }
    return profile;
  }

  Future<List<CollectCollection>> fetchCollections({
    String? accessToken,
  }) async {
    return _fetchMemberCollections(accessToken: accessToken);
  }

  Future<List<CollectCollection>> fetchPublicCollections() async {
    final rows = await _backend!
        .from('public_collections_view')
        .select()
        .order('created_at', ascending: false);
    return _collectionRows(rows);
  }

  Future<CollectCollection> fetchCollection(
    String id, {
    String? accessToken,
  }) async {
    exactJsonIdentifier(id, field: 'group.id');
    final collections = await _fetchMemberCollections(
      collectionId: id,
      accessToken: accessToken,
    );
    if (collections.length != 1 || collections.single.id != id) {
      throw StateError('Group is not available');
    }
    return collections.single;
  }

  Future<List<CollectCollection>> _fetchMemberCollections({
    String? collectionId,
    String? accessToken,
  }) async {
    var request = _backend!.rpc<dynamic>(
      'list_current_user_collections',
      params: {'p_collection_id': ?collectionId},
    );
    if (accessToken != null) {
      request = request.setHeader('Authorization', 'Bearer $accessToken');
    }
    final response = await request;
    if (response is! List) {
      throw const FormatException('Group response is unavailable');
    }
    return _collectionRows(response);
  }

  List<CollectCollection> _collectionRows(List<dynamic> rows) {
    final seen = <String>{};
    final collections = <CollectCollection>[];
    for (final row in rows) {
      if (row is! Map || row.keys.any((key) => key is! String)) {
        throw const FormatException('Invalid group response');
      }
      final collection = CollectCollection.fromJson(
        Map<String, dynamic>.from(row),
      );
      if (!seen.add(collection.id)) {
        throw const FormatException('Duplicate group response');
      }
      collections.add(collection);
    }
    return List.unmodifiable(collections);
  }

  Future<List<Map<String, dynamic>>> _financialRows(
    String rpc, {
    String? accessToken,
  }) async {
    var request = _backend!.rpc<dynamic>(rpc);
    if (accessToken != null) {
      request = request.setHeader('Authorization', 'Bearer $accessToken');
    }
    final response = await request;
    if (response is! List || response.any((row) => row is! Map)) {
      throw const FormatException('Financial history is unavailable');
    }
    return [for (final row in response) Map<String, dynamic>.from(row as Map)];
  }

  Future<({List<PaymentIntentModel> items, int pendingCount})>
  fetchRecentIntents({String? intentId, String? accessToken}) async {
    if (intentId != null) exactJsonIdentifier(intentId, field: 'intent.id');
    var request = _backend!.rpc<dynamic>(
      'list_current_member_recent_intents',
      params: {'p_intent_id': ?intentId},
    );
    if (accessToken != null) {
      request = request.setHeader('Authorization', 'Bearer $accessToken');
    }
    final response = await request;
    if (response is! Map) {
      throw const FormatException('Invalid intent response');
    }
    final rows = _pageRows(response);
    _validatePaymentRows(rows, intents: true);
    final items = [for (final row in rows) PaymentIntentModel.fromJson(row)];
    if (intentId != null &&
        (items.length > 1 || items.any((item) => item.id != intentId))) {
      throw const FormatException('Intent response does not match the request');
    }
    return (
      items: List<PaymentIntentModel>.unmodifiable(items),
      pendingCount: exactJsonInteger(
        response['pending_count'],
        field: 'intent.pending_count',
        minimum: 0,
      ),
    );
  }

  Future<MemberHistoryPage> fetchHistoryPage(
    MemberHistoryQuery query, {
    Map<String, dynamic>? cursor,
    String? accessToken,
  }) async {
    if (query.collectionId != null) {
      exactJsonIdentifier(query.collectionId, field: 'history.collection_id');
    }
    if (query.search.trim().length > 80 ||
        !const {'newest', 'oldest', 'highest', 'lowest'}.contains(query.sort)) {
      throw const FormatException('Invalid history query');
    }
    var request = _backend!.rpc<dynamic>(
      'list_current_member_history_page',
      params: {
        'p_contract_version': 2,
        'p_collection_id': ?query.collectionId,
        'p_query': query.search,
        'p_sort': query.sort,
        'p_cursor': ?cursor,
        'p_limit': 50,
      },
    );
    if (accessToken != null) {
      request = request.setHeader('Authorization', 'Bearer $accessToken');
    }
    final response = await request;
    final rows = _pageRows(response);
    if (response['contract_version'] is! int ||
        response['contract_version'] != 2) {
      throw const FormatException('Signed history contract is unavailable');
    }
    final page = MemberHistoryPage.fromJson(
      Map<String, dynamic>.from(response as Map),
      [for (final row in rows) Contribution.historyEventFromJson(row)],
    );
    page.validateRequest(query: query, cursor: cursor);
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
          !(rail == 'rwanda_momo' && currency == 'RWF') ||
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

  Future<Map<String, CollectionSummary>> fetchCollectionSummaries({
    String? accessToken,
  }) async {
    final rows = await _financialRows(
      'list_current_member_collection_balances',
      accessToken: accessToken,
    );
    if (rows.any(
          (row) => row['collection_id'] is! String || row['balances'] is! List,
        ) ||
        rows.map((row) => row['collection_id']).toSet().length != rows.length) {
      throw const FormatException('Group balances are unavailable');
    }
    return {
      for (final row in rows)
        exactJsonIdentifier(
          row['collection_id'],
          field: 'summary.collection_id',
        ): CollectionSummary.fromJson(
          row,
        ),
    };
  }

  Future<NotificationPreferenceRead?> fetchNotificationPreferences(
    CollectProfile? profile, {
    required String? accessToken,
  }) async {
    final backend = _backend;
    if (backend == null || profile == null) return null;
    if (accessToken == null) {
      throw StateError('Sign in and refresh notification preferences.');
    }
    final value = await backend
        .rpc<dynamic>('get_notification_preferences_v2')
        .setHeader('Authorization', 'Bearer $accessToken');
    return NotificationPreferenceRead.parse(value, profile.id);
  }

  Future<List<NotificationEvent>> fetchNotificationEvents(
    CollectProfile? profile, {
    String? accessToken,
  }) async {
    final backend = _backend;
    if (backend == null || profile == null) return const [];
    var request = backend
        .from('notification_events')
        .select()
        .eq('user_id', profile.id)
        .order('created_at', ascending: false)
        .limit(100);
    if (accessToken != null) {
      request = request.setHeader('Authorization', 'Bearer $accessToken');
    }
    final rows = await request;
    final ids = <String>{};
    final events = <NotificationEvent>[];
    for (final row in rows) {
      // The scoped read contract already requires String-keyed maps.
      final event = NotificationEvent.fromJson(Map<String, dynamic>.from(row));
      if (event.userId != profile.id || !ids.add(event.id)) {
        throw const _CollectAccessMismatch();
      }
      events.add(event);
    }
    return List.unmodifiable(events);
  }
}

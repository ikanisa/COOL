part of 'collect_repository.dart';

mixin _CollectGroupActions on StateNotifier<CollectState> {
  SupabaseClient? get _supabase;
  _CollectLiveReader get _liveReader;
  bool get _allowLocalWrites;
  int get _loadGeneration;
  Uuid get _uuid;
  Map<String, List<CollectMember>> get _fixtureAdditionalMembers;
  CollectRepository get _groupRepository;
  _CollectSessionFence _captureSession();
  bool _isCurrentSession(_CollectSessionFence session);
  void _requireCurrentMemberSession(
    _CollectSessionFence session,
    String userId,
  );
  CollectProfile _requireReadyProfile();
  CollectCollection _requireActiveCollection(String collectionId);
  CollectProfile _requireCollectionOwner(
    CollectCollection collection, {
    required String action,
  });
  Future<void> loadInitial({bool syncPendingSms = false});
  CollectCollection collectionById(String id);
  CollectCollection? maybeCollectionById(String id);
  CollectCollection collectionBySlug(String slug);
  CollectionSummary? summaryFor(String collectionId);

  final Map<String, List<CollectMember>> _fixtureRosterOverrides = {};

  Future<CollectCollection> joinGroupBySlug(String slug) async {
    final normalizedSlug = slug.trim();
    if (normalizedSlug.isEmpty) {
      throw const FormatException('Group link is invalid');
    }
    _requireReadyProfile();
    final supabase = _supabase;

    final ownerId = supabase?.auth.currentUser?.id;
    if (supabase != null && ownerId != null) {
      final session = _captureSession();
      final generation = _loadGeneration;
      void requireOriginalSession() {
        _requireCurrentMemberSession(session, ownerId);
        if (!mounted ||
            generation != _loadGeneration ||
            supabase.auth.currentUser?.id != ownerId ||
            state.currentProfile?.id != ownerId) {
          throw StateError('Account changed during group join.');
        }
      }

      requireOriginalSession();
      final response = await supabase
          .rpc<dynamic>(
            'join_group_by_share_code',
            params: {'p_group_code': normalizedSlug},
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false);
      requireOriginalSession();
      final id = exactJsonIdentifier(response, field: 'joined_group.id');
      final collection = await _liveReader.fetchCollection(
        id,
        accessToken: session.accessToken,
      );
      requireOriginalSession();
      if (!collection.isCurrentUserMember &&
          collection.creatorUserId != ownerId) {
        throw const FormatException('Joined group membership is invalid.');
      }
      final existing = state.collections.indexWhere(
        (item) => item.id == collection.id,
      );
      final collections = [...state.collections];
      if (existing == -1) {
        collections.insert(0, collection);
      } else {
        collections[existing] = collection;
      }
      state = state.copyWith(collections: collections);
      return collection;
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before joining a group.');
    }

    return collectionBySlug(normalizedSlug);
  }

  Future<String> getGroupShareCode(String collectionId) async {
    final authority = _groupRepository.captureGroupInvitationAuthority(
      collectionId,
    );
    final session = _captureSession();
    try {
      final supabase = _supabase;
      if (supabase != null) {
        final code = await supabase
            .rpc<dynamic>(
              'get_group_share_code',
              params: {'p_collection_id': collectionId},
            )
            .setHeader('Authorization', 'Bearer ${session.accessToken}');
        authority.check();
        if (code is! String || !_invitationUuid.hasMatch(code)) {
          throw const FormatException(
            'The invitation could not be verified. Refresh before sharing.',
          );
        }
        // A deliberate server refresh resolves the display before a new
        // rotation can replace an uncertain prior operation.
        _pendingInvitationRequests(_groupRepository).removeWhere(
          (key, _) =>
              key.startsWith('${session.identity!.userId}:$collectionId:'),
        );
        return code;
      }
      return _requireActiveCollection(collectionId).slug;
    } finally {
      authority.dispose();
    }
  }

  Future<String> rotateGroupShareCode(String collectionId) async {
    final authority = _groupRepository.captureGroupInvitationAuthority(
      collectionId,
      requireOwner: true,
    );
    final session = _captureSession();
    try {
      final supabase = _supabase;
      if (supabase != null) {
        final pending = _pendingInvitationRequests(_groupRepository);
        final key =
            '${session.identity!.userId}:$collectionId:${session.identity!.sessionId}:${session.generation}';
        final requestId = pending.putIfAbsent(key, _uuid.v4);
        final result = await supabase
            .rpc<dynamic>(
              'rotate_group_share_code_v2',
              params: {
                'p_collection_id': collectionId,
                'p_request_id': requestId,
              },
            )
            .retry(enabled: false)
            .setHeader('Authorization', 'Bearer ${session.accessToken}');
        authority.check();
        const fields = {
          'contract_version',
          'ok',
          'collection_id',
          'request_id',
          'share_code',
        };
        if (result is! Map ||
            result.length != fields.length ||
            !result.keys.toSet().containsAll(fields) ||
            result['contract_version'] is! int ||
            result['contract_version'] != 1 ||
            result['ok'] != true ||
            result['collection_id'] != collectionId ||
            result['request_id'] != requestId ||
            result['share_code'] is! String ||
            !_invitationUuid.hasMatch(result['share_code'] as String)) {
          throw const FormatException(
            'The invitation replacement was not acknowledged. Refresh the invitation before replacing it again.',
          );
        }
        if (pending[key] == requestId) pending.remove(key);
        return result['share_code'] as String;
      }
      return _uuid.v4();
    } finally {
      authority.dispose();
    }
  }

  Future<List<CollectMember>> membersForCollection(String collectionId) async {
    final collection = maybeCollectionById(collectionId);
    if (collection == null) return const [];
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      final session = _captureSession();
      final publicId = state.currentProfile?.publicId;
      final rows = await supabase
          .rpc<dynamic>(
            'list_current_member_group_roster',
            params: {'p_collection_id': collectionId},
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}');
      if (!_isCurrentSession(session) ||
          state.currentProfile?.publicId != publicId ||
          maybeCollectionById(collectionId) == null) {
        throw StateError('Account or group access changed');
      }
      if (rows is! List || rows.any((row) => row is! Map)) {
        throw const FormatException('Member roster is unavailable');
      }
      final ids = <String>{};
      final members = <CollectMember>[];
      for (final row in rows) {
        final member = CollectMember.fromJson(
          Map<String, dynamic>.from(row as Map),
        );
        if (!ids.add(member.publicId) ||
            (member.amountScope == 'own' && member.publicId != publicId)) {
          throw const FormatException('Invalid member roster');
        }
        members.add(member);
      }
      return List<CollectMember>.unmodifiable(members);
    }
    if (!_allowLocalWrites || supabase != null) {
      throw StateError('Sign in to view members.');
    }
    final fixtureRoster = _fixtureRosterOverrides[collectionId];
    if (fixtureRoster != null) return List.unmodifiable(fixtureRoster);
    final profile = state.currentProfile;
    final summary = summaryFor(collectionId);
    return [
      if (profile != null &&
          (collection.creatorUserId == profile.id ||
              collection.isCurrentUserMember))
        CollectMember(
          publicId: profile.publicId,
          role: collection.creatorUserId == profile.id ? 'owner' : 'member',
          status: 'active',
          joinedAt: collection.createdAt,
          amountScope: 'own',
          contributionTotals: {
            for (final entry
                in summary?.ownBalancesByCurrency.entries ??
                    const <MapEntry<String, int>>[])
              if (entry.value > 0) entry.key: entry.value,
          },
        ),
      ...?_fixtureAdditionalMembers[collectionId],
    ];
  }

  // Kept as a Dart compatibility name; this promotes an active member directly,
  // not an invitation or platform Admin enrollment.
  Future<void> inviteCollectionAdmin({
    required String collectionId,
    required String publicId,
  }) async {
    final collection = _requireActiveCollection(collectionId);
    final profile = _requireCollectionOwner(
      collection,
      action: 'add a group admin',
    );
    if (collection.isPlatformSponsored || collection.isPublic) {
      throw StateError('Manage this group in Admin.');
    }
    final cleanPublicId = publicId.trim();
    if (!RegExp(r'^[0-9]{6}$').hasMatch(cleanPublicId)) {
      throw const FormatException('Enter a 6 digit Collect ID.');
    }
    if (cleanPublicId == profile.publicId) {
      throw const FormatException(
        'Enter another member’s Collect ID. You already own this group.',
      );
    }
    final supabase = _supabase;
    if (supabase != null) {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null || userId != profile.id) {
        throw StateError('Sign in before adding a group admin.');
      }
      final session = _captureSession();
      _requireCurrentMemberSession(session, userId);
      dynamic result;
      try {
        result = await supabase
            .rpc<dynamic>(
              'add_group_admin',
              params: {
                'collection': collectionId,
                'member_public_id': cleanPublicId,
              },
            )
            .setHeader('Authorization', 'Bearer ${session.accessToken}')
            .retry(enabled: false);
      } on PostgrestException catch (error) {
        if (error.code == '22023') {
          throw const FormatException('Choose another active group member.');
        }
        if (error.code == '42501') {
          throw StateError('Only the current owner can add a group admin.');
        }
        rethrow;
      }
      _requireCurrentMemberSession(session, userId);
      if (result is! Map ||
          result.length != 4 ||
          result['collection_id'] != collectionId ||
          result['public_id'] != cleanPublicId ||
          result['role'] != 'admin' ||
          result['status'] != 'active') {
        throw const FormatException(
          'Group admin update could not be verified.',
        );
      }
    } else {
      if (!_allowLocalWrites) {
        throw StateError('Sign in before adding a group admin.');
      }
      final roster = await membersForCollection(collectionId);
      if (!roster.any(
        (member) =>
            member.publicId == cleanPublicId && member.status == 'active',
      )) {
        throw const FormatException('Choose another active group member.');
      }
      _fixtureRosterOverrides[collectionId] = [
        for (final member in roster)
          if (member.publicId == cleanPublicId)
            CollectMember(
              publicId: member.publicId,
              role: 'admin',
              status: member.status,
              joinedAt: member.joinedAt,
              amountScope: member.amountScope,
              contributionTotals: member.contributionTotals,
            )
          else
            member,
      ];
    }
    // Invalidate the account-scoped roster provider. A live roster is fetched
    // from the server, never optimistically forged from the entered ID.
    state = state.copyWith(collections: [...state.collections]);
  }

  Future<void> archiveCollection(String collectionId) async {
    final collection = _requireActiveCollection(collectionId);
    final profile = _requireCollectionOwner(
      collection,
      action: 'archive this group',
    );
    if (collection.isPlatformSponsored || collection.isPublic) {
      throw StateError('Manage this group in Admin.');
    }
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      final session = _captureSession();
      _requireCurrentMemberSession(session, profile.id);
      await supabase
          .rpc<void>('archive_group', params: {'collection': collectionId})
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false);
      _requireCurrentMemberSession(session, profile.id);
      await loadInitial();
      _requireCurrentMemberSession(session, profile.id);
      return;
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before archiving a group.');
    }
    state = state.copyWith(
      collections: [
        for (final item in state.collections)
          if (item.id == collection.id)
            item.copyWith(moderationStatus: 'archived', isPublic: false)
          else
            item,
      ],
    );
  }

  Future<void> transferCollectionOwnership({
    required String collectionId,
    required String publicId,
  }) async {
    final collection = _requireActiveCollection(collectionId);
    final profile = _requireCollectionOwner(
      collection,
      action: 'transfer group ownership',
    );
    if (collection.isPlatformSponsored || collection.isPublic) {
      throw StateError('Manage this group in Admin.');
    }
    final cleanPublicId = publicId.trim();
    if (!RegExp(r'^[0-9]{6}$').hasMatch(cleanPublicId)) {
      throw const FormatException('Enter a 6 digit Collect ID.');
    }
    if (cleanPublicId == profile.publicId) {
      throw const FormatException(
        'Enter another member’s Collect ID. You already own this group.',
      );
    }
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      final session = _captureSession();
      _requireCurrentMemberSession(session, profile.id);
      await supabase
          .rpc<void>(
            'transfer_group_ownership',
            params: {
              'collection': collectionId,
              'new_owner_public_id': cleanPublicId,
            },
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false);
      _requireCurrentMemberSession(session, profile.id);
      await loadInitial();
      _requireCurrentMemberSession(session, profile.id);
      return;
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before transferring ownership.');
    }
    final previousRoster = await membersForCollection(collectionId);
    _fixtureRosterOverrides[collectionId] = [
      for (final member in previousRoster)
        if (member.publicId != cleanPublicId)
          CollectMember(
            publicId: member.publicId,
            role: member.publicId == profile.publicId ? 'admin' : member.role,
            status: member.status,
            joinedAt: member.joinedAt,
            amountScope: member.amountScope,
            contributionTotals: member.contributionTotals,
          ),
      CollectMember(
        publicId: cleanPublicId,
        role: 'owner',
        status: 'active',
        joinedAt: DateTime.now().toUtc(),
      ),
    ];
    state = state.copyWith(
      collections: [
        for (final item in state.collections)
          if (item.id == collection.id)
            item.copyWith(creatorUserId: 'collect-id-$cleanPublicId')
          else
            item,
      ],
    );
  }

  Future<OwnerGroupHealth> ownerHealthFor(String collectionId) async {
    collectionById(collectionId);
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      final session = _captureSession();
      final row = await supabase
          .rpc<dynamic>(
            'get_owner_group_health',
            params: {'collection': collectionId},
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}');
      if (!_isCurrentSession(session) ||
          maybeCollectionById(collectionId) == null) {
        throw StateError('Account or group access changed');
      }
      if (row is! Map || row.keys.any((key) => key is! String)) {
        throw const FormatException('Group health is unavailable');
      }
      final health = OwnerGroupHealth.fromJson(Map<String, dynamic>.from(row));
      if (health.collectionId != collectionId) {
        throw const FormatException('Group health does not match the request');
      }
      return health;
    }
    if (!_allowLocalWrites) {
      throw StateError('Connect to load group health');
    }
    return OwnerGroupHealth(
      collectionId: collectionId,
      smsAccessEnabled: state.smsAccessEnabled,
      receiverConfigured: collectionById(collectionId).supportsRwandaMomo,
      pendingPaymentIntents: state.paymentIntents
          .where(
            (item) =>
                item.collectionId == collectionId && item.status == 'pending',
          )
          .length,
      needsReviewEvents: 0,
      lastSyncedAt: null,
    );
  }
}

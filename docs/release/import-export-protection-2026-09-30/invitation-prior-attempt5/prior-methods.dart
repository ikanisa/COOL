  Future<String> getGroupShareCode(String collectionId) async {
    final collection = _requireActiveCollection(collectionId);
    final profile = _requireProfile();
    if (!collection.isCurrentUserMember &&
        collection.creatorUserId != profile.id) {
      throw StateError('Join this group before sharing it.');
    }
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      return supabase.rpc<String>(
        'get_group_share_code',
        params: {'p_collection_id': collectionId},
      );
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before sharing a group.');
    }
    return collection.slug;
  }

  Future<String> rotateGroupShareCode(String collectionId) async {
    final collection = _requireActiveCollection(collectionId);
    _requireCollectionOwner(collection, action: 'rotate the group share link');
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      return supabase.rpc<String>(
        'rotate_group_share_code',
        params: {'p_collection_id': collectionId},
      );
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before rotating a group link.');
    }
    return _uuid.v4();
  }

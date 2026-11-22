part of 'collect_repository.dart';

final _invitationUuid = RegExp(
  r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
);

/// One operation's authority. Any observed loss stays invalid even after access
/// returns; old account/group work must never become an export again.
final class _CollectInvitationAuthority implements CollectInvitationAuthority {
  _CollectInvitationAuthority(this._current);
  final bool Function() _current;
  void Function()? _removeListener;
  bool _invalid = false;
  @override
  bool get isCurrent {
    if (!_invalid && !_current()) {
      _invalid = true;
    }
    return !_invalid;
  }

  @override
  void check() {
    if (!isCurrent) {
      throw StateError(
        'Your account or group access changed. Open the invitation again.',
      );
    }
  }

  @override
  void dispose() {
    _invalid = true;
    _removeListener?.call();
    _removeListener = null;
  }
}

mixin _CollectGroupInvitations on StateNotifier<CollectState> {
  final _pendingInvitationRequests = <String, String>{};
  CollectCloudflareClient? get _backend;
  bool get _allowLocalWrites;
  Uuid get _uuid;
  _CollectSessionFence _captureSession();
  bool _isCurrentSession(_CollectSessionFence session);
  CollectProfile _requireProfile();
  CollectCollection _requireActiveCollection(String collectionId);
  CollectCollection? maybeCollectionById(String collectionId);

  CollectInvitationAuthority captureGroupInvitationAuthority(
    String collectionId, {
    bool requireOwner = false,
  }) {
    final session = _captureSession();
    final profile = _requireProfile();
    final initial = _requireActiveCollection(collectionId);
    CollectState? observedState;
    _CollectInvitationAuthority? observedAuthority;
    final removeListener = addListener((value) {
      observedState = value;
      observedAuthority?.isCurrent;
    });
    bool permitted() {
      final current = observedState;
      if (!mounted ||
          !_isCurrentSession(session) ||
          current == null ||
          current.isLoading ||
          current.usingStaleCache ||
          current.currentProfile?.id != profile.id) {
        return false;
      }
      final live = _backend?.auth.currentSession;
      if (_backend != null &&
          (live == null || live.isExpired || live.user.id != profile.id)) {
        return false;
      }
      if (_backend == null && !_allowLocalWrites) {
        return false;
      }
      final group = maybeCollectionById(collectionId);
      return group != null &&
          !group.isArchived &&
          group.creatorUserId == initial.creatorUserId &&
          group.isPublic == initial.isPublic &&
          group.isCurrentUserMember == initial.isCurrentUserMember &&
          (requireOwner
              ? group.creatorUserId == profile.id
              : group.isCurrentUserMember || group.creatorUserId == profile.id);
    }

    final authority = _CollectInvitationAuthority(permitted);
    observedAuthority = authority;
    authority._removeListener = removeListener;
    try {
      authority.check();
      return authority;
    } catch (_) {
      authority.dispose();
      rethrow;
    }
  }

  Future<String> getGroupShareCode(String collectionId) async {
    final authority = captureGroupInvitationAuthority(collectionId);
    final session = _captureSession();
    try {
      final backend = _backend;
      if (backend != null) {
        final code = await backend
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
        _pendingInvitationRequests.removeWhere(
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
    final authority = captureGroupInvitationAuthority(
      collectionId,
      requireOwner: true,
    );
    final session = _captureSession();
    try {
      final backend = _backend;
      if (backend != null) {
        final pending = _pendingInvitationRequests;
        final key =
            '${session.identity!.userId}:$collectionId:${session.identity!.sessionId}:${session.generation}';
        final requestId = pending.putIfAbsent(key, _uuid.v4);
        final result = await backend
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
}

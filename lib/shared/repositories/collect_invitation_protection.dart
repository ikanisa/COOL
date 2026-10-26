part of 'collect_repository.dart';

final _invitationUuid = RegExp(
  r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
);
final _invitationRequests = Expando<Map<String, String>>();
Map<String, String> _pendingInvitationRequests(CollectRepository repository) =>
    _invitationRequests[repository] ??= {};

/// One operation's authority. Any observed loss stays invalid even after access
/// returns; old account/group work must never become an export again.
class CollectInvitationAuthority {
  CollectInvitationAuthority._(this._current);
  final bool Function() _current;
  void Function()? _removeListener;
  bool _invalid = false;
  bool get isCurrent {
    if (!_invalid && !_current()) {
      _invalid = true;
    }
    return !_invalid;
  }

  void check() {
    if (!isCurrent) {
      throw StateError(
        'Your account or group access changed. Open the invitation again.',
      );
    }
  }

  void dispose() {
    _invalid = true;
    _removeListener?.call();
    _removeListener = null;
  }
}

extension CollectInvitationProtection on CollectRepository {
  CollectInvitationAuthority captureGroupInvitationAuthority(
    String collectionId, {
    bool requireOwner = false,
  }) {
    final session = _captureSession();
    final profile = _requireProfile();
    final initial = _requireActiveCollection(collectionId);
    CollectState? observedState;
    CollectInvitationAuthority? observedAuthority;
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

    final authority = CollectInvitationAuthority._(permitted);
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
}

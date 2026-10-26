part of 'collect_repository.dart';

mixin _CollectNotificationActions on StateNotifier<CollectState> {
  CollectCloudflareClient? get _backend;
  _CollectLiveReader get _liveReader;
  bool get _allowLocalWrites;
  _CollectAuthIdentity? get _signingOutIdentity;
  _CollectSessionFence _captureSession();
  bool _isCurrentSession(_CollectSessionFence session);
  void _requireCurrentMemberSession(
    _CollectSessionFence session,
    String userId,
  );
  CollectProfile _requireProfile();

  _CollectNotificationRegistration? _registeredNotification;
  int _notificationRegistrationGeneration = 0;
  int _notificationPreferencesGeneration = 0;
  int _notificationPreferencesReadGeneration = 0;
  int? _notificationPreferencesRevision;
  int? _notificationPreferencesSaveOperation;
  NotificationPreferences? _notificationPreferencesIntent;
  bool _notificationPreferencesNeedsRefresh = false;

  int? get notificationPreferencesRevision => _notificationPreferencesRevision;
  NotificationPreferences? get pendingNotificationPreferences =>
      _notificationPreferencesIntent;
  bool get notificationPreferencesNeedsRefresh =>
      !(_backend == null && _allowLocalWrites) &&
      (_notificationPreferencesNeedsRefresh ||
          _notificationPreferencesRevision == null);

  /// Discard an unsaved choice without granting permission to retry an
  /// uncertain write. The current server revision still requires refresh.
  void discardPendingNotificationPreferences() {
    if (_notificationPreferencesSaveOperation != null) {
      throw StateError(
        'Wait for the notification preference save before discarding.',
      );
    }
    _notificationPreferencesIntent = null;
    state = state.copyWith();
  }

  bool _acceptNotificationPreferencesRead(
    _CollectSessionFence session,
    int mutation,
    int read,
  ) =>
      _isCurrentSession(session) &&
      _signingOutIdentity != session.identity &&
      mutation == _notificationPreferencesGeneration &&
      read == _notificationPreferencesReadGeneration;

  /// User-requested refresh acknowledges the current server revision. Pending
  /// intended changes remain available for review; this never retries a save.
  Future<void> refreshNotificationPreferences() async {
    final profile = _requireProfile();
    final session = _captureSession();
    if (session.identity?.userId != profile.id ||
        session.accessToken == null ||
        _signingOutIdentity == session.identity) {
      throw StateError('Sign in and refresh notification preferences.');
    }
    if (_notificationPreferencesSaveOperation != null) {
      throw StateError(
        'Wait for the notification preference save before refreshing.',
      );
    }
    _notificationPreferencesRevision = null;
    _notificationPreferencesNeedsRefresh = true;
    state = state.copyWith();
    final mutation = _notificationPreferencesGeneration;
    final read = ++_notificationPreferencesReadGeneration;
    try {
      final receipt = await _liveReader.fetchNotificationPreferences(
        profile,
        accessToken: session.accessToken,
      );
      if (!_acceptNotificationPreferencesRead(session, mutation, read) ||
          receipt == null) {
        throw StateError(
          'Notification preference refresh belongs to an earlier operation.',
        );
      }
      _notificationPreferencesRevision = receipt.revision;
      _notificationPreferencesNeedsRefresh = false;
      state = state.copyWith(notificationPreferences: receipt.preferences);
    } catch (_) {
      if (!_acceptNotificationPreferencesRead(session, mutation, read)) {
        throw StateError(
          'Notification preference refresh belongs to an earlier operation.',
        );
      }
      rethrow;
    }
  }

  Future<void> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    final profile = _requireProfile();
    final backend = _backend;
    if (backend == null) {
      if (!_allowLocalWrites) {
        throw StateError('Connect before saving notification preferences.');
      }
      state = state.copyWith(notificationPreferences: preferences);
      return;
    }
    final session = _captureSession();
    if (session.identity?.userId != profile.id ||
        session.accessToken == null ||
        _signingOutIdentity == session.identity) {
      throw StateError('Sign in and refresh notification preferences.');
    }
    _notificationPreferencesIntent = preferences;
    final revision = _notificationPreferencesRevision;
    if (revision == null || _notificationPreferencesNeedsRefresh) {
      _notificationPreferencesNeedsRefresh = true;
      state = state.copyWith();
      throw StateError('Refresh notification preferences before saving.');
    }
    if (_notificationPreferencesSaveOperation != null) {
      state = state.copyWith();
      throw StateError('A notification preference save is still pending.');
    }
    final operation = ++_notificationPreferencesGeneration;
    ++_notificationPreferencesReadGeneration;
    _notificationPreferencesSaveOperation = operation;
    bool current() =>
        _isCurrentSession(session) &&
        _signingOutIdentity != session.identity &&
        operation == _notificationPreferencesGeneration;
    try {
      final response = await backend
          .rpc<dynamic>(
            'set_notification_preferences_v2',
            params: {
              'p_preferences': preferences.toJson(),
              'p_expected_revision': revision,
            },
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}');
      if (!current()) {
        throw StateError(
          'Notification preference save belongs to an earlier session.',
        );
      }
      final acknowledgedRevision = notificationPreferenceSaveRevision(
        response,
        userId: profile.id,
        expectedRevision: revision,
      );
      // A reload can start during the request. Its older server snapshot must
      // never replace an acknowledged write, even when the session is unchanged.
      ++_notificationPreferencesReadGeneration;
      _notificationPreferencesRevision = acknowledgedRevision;
      if (jsonEncode(_notificationPreferencesIntent?.toJson()) ==
          jsonEncode(preferences.toJson())) {
        _notificationPreferencesIntent = null;
      }
      state = state.copyWith(notificationPreferences: preferences);
    } catch (_) {
      if (!current()) {
        throw StateError(
          'Notification preference save belongs to an earlier session.',
        );
      }
      // An uncertain/malformed/conflicting reply requires an explicit refresh;
      // neither cached defaults nor a background reload authorizes an overwrite.
      _notificationPreferencesRevision = null;
      _notificationPreferencesNeedsRefresh = true;
      state = state.copyWith();
      rethrow;
    } finally {
      if (_notificationPreferencesSaveOperation == operation) {
        _notificationPreferencesSaveOperation = null;
      }
    }
  }

  Future<void> markNotificationRead(String eventId) async {
    final cleanEventId = exactJsonIdentifier(eventId, field: 'notification.id');
    final backend = _backend;
    final profile = _requireProfile();
    final session = _captureSession();
    if (backend != null && backend.auth.currentUser != null) {
      _requireCurrentMemberSession(session, profile.id);
      await backend
          .rpc<void>(
            'mark_notification_event_read',
            params: {'p_event_id': cleanEventId},
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false);
      _requireCurrentMemberSession(session, profile.id);
    } else if (!_allowLocalWrites) {
      throw StateError('Sign in before updating notifications.');
    }
    final now = DateTime.now();
    state = state.copyWith(
      notificationEvents: [
        for (final event in state.notificationEvents)
          event.id == cleanEventId && event.userId == profile.id
              ? event.copyWith(status: 'read', readAt: now)
              : event,
      ],
    );
  }

  /// Only an acknowledged registration for the current session is connected.
  bool isNotificationDeviceRegistered({
    required String provider,
    required String token,
  }) {
    final registration = _registeredNotification;
    return mounted &&
        registration != null &&
        registration.identity ==
            _sessionIdentity(_backend?.auth.currentSession) &&
        registration.identity != _signingOutIdentity &&
        registration.provider == provider &&
        registration.token == token;
  }

  Future<void> registerNotificationDevice({
    required String platform,
    required String provider,
    required String token,
    required String environment,
  }) async {
    final profile = _requireProfile();
    final backend = _backend;
    final session = _captureSession();
    if (backend == null ||
        session.identity == null ||
        session.accessToken == null) {
      return;
    }
    if (profile.id != session.identity!.userId ||
        _signingOutIdentity == session.identity) {
      throw StateError(
        'Notification registration requires the current signed-in session.',
      );
    }
    final operation = ++_notificationRegistrationGeneration;
    try {
      final acknowledgedDevice = await backend
          .rpc<dynamic>(
            'register_notification_device',
            params: {
              'p_platform': platform,
              'p_provider': provider,
              'p_token': token,
              'p_environment': environment,
              'p_locale': 'en',
              'p_app_version': null,
            },
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}');
      if (acknowledgedDevice is! String ||
          !RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(acknowledgedDevice.trim().toLowerCase())) {
        throw StateError('Notifications could not connect. Try again.');
      }
    } on CollectApiException catch (error) {
      if (!_isCurrentSession(session) ||
          operation != _notificationRegistrationGeneration) {
        return;
      }
      _registeredNotification = null;
      if (error.code == 'notification_registration_session_stale' ||
          error.message == 'notification_registration_session_stale') {
        const message =
            'Sign in again to register notifications on this device.';
        state = state.copyWith(lastError: message);
        throw StateError(message);
      }
      rethrow;
    } catch (_) {
      if (_isCurrentSession(session) &&
          operation == _notificationRegistrationGeneration) {
        _registeredNotification = null;
      }
      rethrow;
    }
    if (!_isCurrentSession(session) ||
        operation != _notificationRegistrationGeneration ||
        _signingOutIdentity == session.identity) {
      if (_sessionIdentity(backend.auth.currentSession) != session.identity) {
        try {
          // An already-sent registration cannot be cancelled. Cleanup remains
          // bound to the old server session and cannot disable a row already
          // acknowledged for a newer session.
          await backend
              .rpc<void>(
                'unregister_notification_device',
                params: {'p_provider': provider, 'p_token': token},
              )
              .setHeader('Authorization', 'Bearer ${session.accessToken}');
        } catch (_) {
          // Server ordering/session revocation is authoritative when offline.
        }
      }
      return;
    }
    _registeredNotification = (
      identity: session.identity!,
      provider: provider,
      token: token,
    );
  }
}

typedef _CollectNotificationRegistration = ({
  _CollectAuthIdentity identity,
  String provider,
  String token,
});

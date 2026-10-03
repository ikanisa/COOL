part of 'admin_roster_import.dart';

class AdminRosterRequestError implements Exception {
  const AdminRosterRequestError(this.code);
  final String code;
  String get message => switch (code) {
    'roster_fresh_auth_required' =>
      'Sign in again, then explicitly look up and inspect your saved import. No transfer or submission was repeated.',
    'roster_recovery_transferred' =>
      'This editor was already recovered into another sign-in. Its old writes are blocked. Look up the current eligible saved import after fresh sign-in.',
    'roster_recovery_lineage_invalid' || 'roster_preview_unacknowledged' =>
      'The original saved source proof could not be verified. No extraction or submission was retried. Reattach the original source only after checking the saved outcome.',
    'roster_rows_invalid' || 'roster_input_invalid' =>
      'Some rows could not be accepted. Discard this rejected review request, correct the rows and save a new review. The original source receipt is retained.',
    'roster_import_expired' =>
      'This import has expired. Discard this draft and start a new upload.',
    'roster_import_limit' =>
      'The daily import limit has been reached. Wait and retry this upload later.',
    'roster_import_in_progress' =>
      'This upload is still being prepared. Retry this same request later.',
    'roster_revision_superseded' =>
      'A newer review exists. Check the saved import status before deciding how to continue.',
    'roster_draft_superseded' =>
      'Another tab saved a newer editor checkpoint. Check recovery before continuing; your unsaved values remain in this tab.',
    'roster_recovery_limit' =>
      'The private recovery limit has been reached. Close unused drafts or wait for expired recovery payloads to be removed.',
    'roster_recovery_payload_invalid' || 'roster_confirmation_required' =>
      'This recovery request could not be validated. Check the saved status before continuing.',
    'roster_revision_limit' =>
      'This import has reached its review limit. Check its saved status, then discard this draft and start a new upload if it has not been committed.',
    'roster_request_conflict' =>
      'This request ID is already bound to different data. Do not repeat it. Check the saved import status before starting another request.',
    'roster_import_committed' =>
      'This import has already been submitted. Check the saved receipt to confirm its outcome.',
    'roster_actor_unavailable' || 'roster_access_unavailable' =>
      'Your roster access is no longer available. This private draft has been cleared. Ask an owner to review your access before signing in again.',
    'roster_session_required' =>
      'Your sign-in is no longer authorized for this import. This private draft has been cleared. Sign in again to continue.',
    'roster_feature_disabled' =>
      'Roster imports are currently disabled. This private draft has been cleared. Ask an owner before starting another import.',
    'roster_import_unavailable' =>
      'This import is no longer available to your sign-in. This private draft has been cleared.',
    'roster_collection_unavailable' =>
      'This group is no longer eligible for roster imports. Check its current status before starting another import.',
    'roster_provenance_required' =>
      'The roster service requires a compatible app version. Close this draft and update the app before continuing.',
    'roster_commit_conflict' =>
      'The roster conflicts with existing member or group data. No changes were committed. Check the group before discarding this draft.',
    'roster_extraction_failed' ||
    'roster_preview_invalid' ||
    'roster_extraction_timeout' ||
    'roster_extraction_refused' ||
    'roster_extraction_incomplete' ||
    'roster_provider_response_invalid' ||
    'roster_provider_response_too_large' ||
    'roster_extraction_unavailable' =>
      'This source could not be prepared. Discard the draft, correct the source and start a new upload.',
    _ =>
      'This request was not acknowledged. Retry the same request; its source and request ID are retained. Discard only if you want to abandon this draft.',
  };
}

const _safeRosterCodes = {
  'roster_fresh_auth_required',
  'roster_recovery_transferred',
  'roster_recovery_lineage_invalid',
  'roster_preview_unacknowledged',
  'roster_draft_superseded',
  'roster_recovery_limit',
  'roster_recovery_payload_invalid',
  'roster_confirmation_required',
  'roster_rows_invalid',
  'roster_input_invalid',
  'roster_import_expired',
  'roster_import_limit',
  'roster_import_in_progress',
  'roster_revision_superseded',
  'roster_revision_limit',
  'roster_request_conflict',
  'roster_import_committed',
  'roster_actor_unavailable',
  'roster_session_required',
  'roster_feature_disabled',
  'roster_import_unavailable',
  'roster_collection_unavailable',
  'roster_provenance_required',
  'roster_commit_conflict',
  'roster_extraction_failed',
  'roster_preview_invalid',
  'roster_extraction_timeout',
  'roster_extraction_refused',
  'roster_extraction_incomplete',
  'roster_provider_response_invalid',
  'roster_provider_response_too_large',
  'roster_extraction_unavailable',
};
AdminRosterRequestError _safeRosterError(Object error) {
  Object? code;
  if (error is PostgrestException) code = error.message;
  if (error is FunctionException && error.details is Map) {
    code = (error.details as Map)['error'];
  }
  if (!(code is String && _safeRosterCodes.contains(code)) &&
      ((error is PostgrestException && error.code == '42501') ||
          (error is FunctionException && {401, 403}.contains(error.status)))) {
    return const AdminRosterRequestError('roster_access_unavailable');
  }
  return AdminRosterRequestError(
    code is String && _safeRosterCodes.contains(code) ? code : 'unknown',
  );
}

const rosterSessionChanged = 'Your sign-in changed. Start a new roster import.';

abstract class AdminRosterGateway {
  bool get isCurrent;
  bool get supportsRecovery => false;
  String? get ownerDigest => null;
  bool get ownerStillCurrent => isCurrent;
  Stream<void> get invalidations;
  void checkCurrent() {
    if (!isCurrent) throw StateError(rosterSessionChanged);
  }

  Future<Object?> prepare(Map<String, dynamic> body);
  Future<Object?> review(Map<String, dynamic> params);
  Future<Object?> commit(Map<String, dynamic> params);
  Future<Object?> read(String importId) =>
      Future.error(UnsupportedError('Roster status recovery unavailable.'));
  Future<Object?> recoveryRpc(String name, Map<String, dynamic> params) =>
      Future.error(UnsupportedError('Roster reload recovery unavailable.'));
  void dispose();
}

/// Captures actor/session before file reading. Each dispatch pins the current
/// token only after checking that original actor/session and invalidation fence.
/// Same-session refresh is allowed; another session cannot retarget the draft.
class SupabaseAdminRosterGateway extends AdminRosterGateway {
  SupabaseAdminRosterGateway(this.client) {
    final session = client.auth.currentSession;
    userId = session?.user.id ?? '';
    sessionId = _sessionId(session);
    if (userId.isEmpty ||
        !rosterUuid.hasMatch(sessionId) ||
        (session?.accessToken.isEmpty ?? true) ||
        _tokenActor(session) != userId ||
        adminSessionKey(session) == null ||
        _expiration(session) == null ||
        _expiration(session)! <=
            DateTime.now().millisecondsSinceEpoch ~/ 1000) {
      throw StateError('Sign in again before importing a roster.');
    }
    _scheduleExpiry(session!);
    _subscription = client.auth.onAuthStateChange.listen(
      (event) {
        if (_closed || _invalid) return;
        if (_leaseExpired ||
            (event.event == AuthChangeEvent.signedOut &&
                !adminDelayedLocalSignOut(client, event)) ||
            !_matchesOwner(event.session)) {
          _invalidate();
        } else {
          _scheduleExpiry(event.session!);
        }
      },
      onError: (Object _) => _invalidate(),
      onDone: _invalidate,
    );
  }
  @override
  bool get supportsRecovery => true;
  @override
  String get ownerDigest =>
      rosterTextDigest('collect-roster-owner-v1:$userId:$sessionId');
  @override
  Future<Object?> recoveryRpc(String name, Map<String, dynamic> params) =>
      _rpc(name, params);
  final SupabaseClient client;
  late final String userId, sessionId;
  late final StreamSubscription<AuthState> _subscription;
  Timer? _expiry;
  int? _expiresAt;
  final _events = StreamController<void>.broadcast(sync: true);
  bool _invalid = false, _closed = false;
  static int? _expiration(Session? session) {
    try {
      final claims = jsonDecode(
        utf8.decode(
          base64Url.decode(
            base64Url.normalize(session!.accessToken.split('.')[1]),
          ),
        ),
      );
      if (claims is! Map || claims['exp'] is! int) return null;
      final tokenExpiry = claims['exp'] as int;
      final sdkExpiry = session.expiresAt;
      final expiry = sdkExpiry == null || tokenExpiry < sdkExpiry
          ? tokenExpiry
          : sdkExpiry;
      // Prevent invalid DateTime/Timer arithmetic on malformed large claims.
      return expiry > 0 && expiry <= 8640000000000 ? expiry : null;
    } catch (_) {
      return null;
    }
  }

  bool get _leaseExpired =>
      _expiresAt != null &&
      DateTime.now().millisecondsSinceEpoch ~/ 1000 >= _expiresAt!;
  bool _matchesOwner(Session? session) =>
      adminSessionKey(session) == (userId: userId, sessionId: sessionId) &&
      _expiration(session) != null;
  void _scheduleExpiry(Session session) {
    final expiry = _expiration(session);
    if (expiry == null || _leaseExpired) {
      _invalidate();
      return;
    }
    if (expiry == _expiresAt && _expiry?.isActive == true) return;
    _expiresAt = expiry;
    _expiry?.cancel();
    final remaining = DateTime.fromMillisecondsSinceEpoch(
      expiry * 1000,
    ).difference(DateTime.now());
    _expiry = Timer(
      remaining.isNegative
          ? Duration.zero
          : (remaining > const Duration(days: 1)
                ? const Duration(days: 1)
                : remaining),
      () {
        _expiry = null;
        if (_closed || _invalid) return;
        if (_leaseExpired || !_matchesOwner(client.auth.currentSession)) {
          _invalidate();
        } else {
          _scheduleExpiry(client.auth.currentSession!);
        }
      },
    );
  }

  static String _sessionId(Session? session) {
    try {
      final claims = jsonDecode(
        utf8.decode(
          base64Url.decode(
            base64Url.normalize(session!.accessToken.split('.')[1]),
          ),
        ),
      );
      return claims['session_id'] is String
          ? claims['session_id'] as String
          : '';
    } catch (_) {
      return '';
    }
  }

  static String _tokenActor(Session? session) {
    try {
      final claims = jsonDecode(
        utf8.decode(
          base64Url.decode(
            base64Url.normalize(session!.accessToken.split('.')[1]),
          ),
        ),
      );
      return claims['sub'] is String ? claims['sub'] as String : '';
    } catch (_) {
      return '';
    }
  }

  String _dispatchToken() {
    checkCurrent();
    final session = client.auth.currentSession;
    if (!_matchesOwner(session)) {
      _invalidate();
      throw StateError(rosterSessionChanged);
    }
    return session!.accessToken;
  }

  void _invalidate() {
    if (_invalid) return;
    _invalid = true;
    _expiry?.cancel();
    if (!_closed) _events.add(null);
  }

  @override
  bool get isCurrent => !_closed && ownerStillCurrent;
  @override
  bool get ownerStillCurrent {
    if (_closed || _invalid) return false;
    final session = client.auth.currentSession;
    if (_leaseExpired || !_matchesOwner(session)) {
      _invalidate();
      return false;
    }
    _scheduleExpiry(session!);
    return !_invalid;
  }

  @override
  Stream<void> get invalidations => _events.stream;
  @override
  Future<Object?> prepare(Map<String, dynamic> body) async {
    final token = _dispatchToken();
    try {
      final response = await client.functions
          .invoke(
            'prepare-roster-import',
            body: body,
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 75));
      checkCurrent();
      if (response.status != 200) {
        throw StateError(
          'The preview is not acknowledged. Retry the same request.',
        );
      }
      return response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
    } catch (error) {
      checkCurrent();
      throw _safeRosterError(error);
    }
  }

  Future<Object?> _rpc(String name, Map<String, dynamic> params) async {
    final token = _dispatchToken();
    try {
      var request = client
          .rpc<dynamic>(name, params: params)
          .setHeader('Authorization', 'Bearer $token');
      // The locked SDK already sends POST once. Keep roster write policy
      // explicit if a future SDK changes its default retryable methods.
      if (const {
        'admin_review_roster_import',
        'admin_commit_roster_import',
        'admin_stage_roster_import_intent',
        'admin_execute_roster_import_intent',
        'admin_save_roster_import_draft',
        'admin_transfer_interrupted_roster_import',
      }.contains(name)) {
        request = request.retry(enabled: false);
      }
      final result = await request.timeout(const Duration(seconds: 30));
      checkCurrent();
      return result;
    } catch (error) {
      checkCurrent();
      throw _safeRosterError(error);
    }
  }

  @override
  Future<Object?> review(Map<String, dynamic> params) =>
      _rpc('admin_review_roster_import', params);
  @override
  Future<Object?> commit(Map<String, dynamic> params) =>
      _rpc('admin_commit_roster_import', params);
  @override
  Future<Object?> read(String importId) =>
      _rpc('admin_get_roster_import', {'p_import_id': importId});
  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _expiry?.cancel();
    unawaited(_subscription.cancel());
    unawaited(_events.close());
  }
}

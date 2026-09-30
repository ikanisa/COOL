import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'admin_roster_models.dart';
import 'roster_file_parser.dart';

class AdminRosterRequestError implements Exception {
  const AdminRosterRequestError(this.code);
  final String code;
  String get message => switch (code) {
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
        _tokenActor(session) != userId) {
      throw StateError('Sign in again before importing a roster.');
    }
    _subscription = client.auth.onAuthStateChange.listen((event) {
      if (event.session?.user.id != userId ||
          _sessionId(event.session) != sessionId) {
        _invalidate();
      }
    });
  }
  final SupabaseClient client;
  late final String userId, sessionId;
  late final StreamSubscription<AuthState> _subscription;
  final _events = StreamController<void>.broadcast(sync: true);
  bool _invalid = false, _closed = false;
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
    if (_tokenActor(session) != userId || _sessionId(session) != sessionId) {
      _invalidate();
      throw StateError(rosterSessionChanged);
    }
    return session!.accessToken;
  }

  void _invalidate() {
    if (_invalid) return;
    _invalid = true;
    _events.add(null);
  }

  @override
  bool get isCurrent => !_closed && ownerStillCurrent;
  @override
  bool get ownerStillCurrent =>
      !_invalid &&
      client.auth.currentSession?.user.id == userId &&
      _sessionId(client.auth.currentSession) == sessionId &&
      _tokenActor(client.auth.currentSession) == userId;
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
      final result = await client
          .rpc<dynamic>(name, params: params)
          .setHeader('Authorization', 'Bearer $token')
          .timeout(const Duration(seconds: 30));
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
    _closed = true;
    unawaited(_subscription.cancel());
    unawaited(_events.close());
  }
}

String safeRosterFilename(String filename) {
  var safe = filename.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
  if (!RegExp(r'^[A-Za-z0-9]').hasMatch(safe)) safe = 'roster-$safe';
  if (safe.length > 160) {
    final dot = safe.lastIndexOf('.');
    final extension = dot >= 0 && safe.length - dot <= 6
        ? safe.substring(dot)
        : '';
    safe = safe.substring(0, 160 - extension.length) + extension;
  }
  return safe;
}

class AdminRosterUpload {
  AdminRosterUpload._(this.body, this.sourceSha256);
  final Map<String, dynamic> body;
  final String sourceSha256;
  int get sourceSize => body['source_type'] == 'text'
      ? utf8.encode(body['content'] as String).length
      : base64Decode(body['content_base64'] as String).length;
  String? get derivedSha256 => body['derived_content'] == null
      ? null
      : sha256
            .convert(utf8.encode(body['derived_content'] as String))
            .toString();
  String get sourceKind => body['source_type'] as String;
  static AdminRosterUpload pasted(String text) {
    final bytes = utf8.encode(text);
    if (bytes.isEmpty || bytes.length > 512000) {
      throw StateError('Paste a roster of up to 512,000 bytes.');
    }
    return AdminRosterUpload._({
      'contract_version': 1,
      'request_id': const Uuid().v4(),
      'source_type': 'text',
      'content': text,
    }, sha256.convert(bytes).toString());
  }

  static Future<AdminRosterUpload> file(
    PlatformFile file, {
    required bool aiConsent,
  }) async {
    final bytes = await file.readAsBytes();
    return fromBytes(
      file.name,
      file.extension ?? '',
      bytes,
      aiConsent: aiConsent,
    );
  }

  static AdminRosterUpload fromBytes(
    String filename,
    String extension,
    Uint8List bytes, {
    required bool aiConsent,
  }) {
    final kind = extension.toLowerCase();
    const mimes = {
      'csv': 'text/csv',
      'txt': 'text/plain',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'pdf': 'application/pdf',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'webp': 'image/webp',
    };
    if (!mimes.containsKey(kind)) {
      throw StateError('Choose a CSV, TXT, XLSX, PDF, PNG, JPEG or WebP file.');
    }
    if (bytes.isEmpty ||
        bytes.length >
            (const {'csv', 'txt'}.contains(kind) ? 512000 : 5242880)) {
      throw StateError(
        'The selected roster is empty or exceeds its upload limit.',
      );
    }
    final ai = const {'pdf', 'png', 'jpg', 'jpeg', 'webp'}.contains(kind);
    if (ai && !aiConsent) {
      throw StateError('Confirm OpenAI extraction for this PDF or image.');
    }
    if (kind == 'csv' || kind == 'txt') {
      utf8.decode(
        bytes,
      ); // Reject invalid UTF8 without replacing the original file.
    }
    return AdminRosterUpload._({
      'contract_version': 1,
      'request_id': const Uuid().v4(),
      'source_type': const {'png', 'jpg', 'jpeg', 'webp'}.contains(kind)
          ? 'image'
          : kind,
      'filename': safeRosterFilename(filename),
      'mime_type': mimes[kind],
      'content_base64': base64Encode(bytes),
      if (kind == 'xlsx') 'derived_content': decodeRosterXlsx(bytes),
      if (ai) ...{
        'ai_consent': true,
        'consent_version': 'roster-ai-extraction-v1',
      },
    }, sha256.convert(bytes).toString());
  }
}

/// Memory-only private draft. An uncertain request locks its exact payload until
/// an acknowledged retry or explicit discard. No roster is written to disk.
class AdminRosterDraft extends ChangeNotifier {
  AdminRosterDraft(this.gateway, {this.collectionId}) {
    if (collectionId != null && !rosterUuid.hasMatch(collectionId!)) {
      throw const FormatException('Invalid group.');
    }
    _subscription = gateway.invalidations.listen((_) => _clearForSession());
  }
  final AdminRosterGateway gateway;
  final String? collectionId;
  late final StreamSubscription<void> _subscription;
  AdminRosterPreview? initialPreview, preview;
  List<Map<String, dynamic>> rows = [];
  String? error, errorCode;
  final reviewIssues = <int, String>{};
  bool busy = false, invalidated = false, affirmed = false, edited = false;
  int _generation = 0;
  bool _disposed = false;
  AdminRosterUpload? _upload;
  String? _uploadJson, _reviewJson, _commitJson;
  bool _statusRequired = false, _writesStopped = false;
  String? _terminalCode;
  bool get statusRequired => _statusRequired;
  bool get canCheckStatus => preview != null && !busy && !invalidated;
  bool get canRetryCommit =>
      commitPending && !_writesStopped && !_statusRequired;
  bool get canSaveReview =>
      !busy &&
      !invalidated &&
      !_writesStopped &&
      !_statusRequired &&
      !commitPending &&
      !(reviewPending &&
          const {
            'roster_rows_invalid',
            'roster_input_invalid',
          }.contains(errorCode));
  bool get terminalUploadFailure =>
      preview == null &&
      const {
        'roster_extraction_failed',
        'roster_preview_invalid',
        'roster_extraction_timeout',
        'roster_extraction_refused',
        'roster_extraction_incomplete',
        'roster_provider_response_invalid',
        'roster_provider_response_too_large',
        'roster_extraction_unavailable',
        'roster_import_expired',
        'roster_request_conflict',
        'roster_provenance_required',
        'roster_input_invalid',
        'roster_rows_invalid',
      }.contains(errorCode);
  bool get sourceLocked => _uploadJson != null;
  bool get reviewPending => _reviewJson != null;
  bool get canDiscardPendingReview =>
      reviewPending &&
      !busy &&
      const {'roster_rows_invalid', 'roster_input_invalid'}.contains(errorCode);
  void discardRejectedReview() {
    if (!canDiscardPendingReview) return;
    _generation++;
    _reviewJson = null;
    error = null;
    errorCode = null;
    affirmed = false;
    notifyListeners();
  }

  bool get commitPending => _commitJson != null;
  bool get canEdit =>
      !busy &&
      !invalidated &&
      !reviewPending &&
      !commitPending &&
      !_writesStopped &&
      !_statusRequired;
  bool get canCommit =>
      canEdit && affirmed && !edited && preview?.canSubmit == true;
  String get mode => collectionId == null ? 'create' : 'existing';
  bool _current(int generation) {
    if (!_disposed && !invalidated && !gateway.isCurrent) _clearForSession();
    return !_disposed && !invalidated && generation == _generation;
  }

  void _clearForSession({String? code, String? message}) {
    if (_disposed) return;
    invalidated = true;
    _generation++;
    _upload = null;
    _uploadJson = null;
    _reviewJson = null;
    _commitJson = null;
    _statusRequired = false;
    _writesStopped = true;
    initialPreview = null;
    preview = null;
    rows = [];
    affirmed = false;
    busy = false;
    reviewIssues.clear();
    errorCode = code;
    error = message ?? rosterSessionChanged;
    notifyListeners();
  }

  void checkSession() {
    if (!gateway.isCurrent) _clearForSession();
    gateway.checkCurrent();
  }

  Future<T?> _run<T>(Future<T> Function(int generation) operation) async {
    if (busy || invalidated || _disposed) return null;
    if (!gateway.isCurrent) {
      _clearForSession();
      return null;
    }
    final generation = _generation;
    busy = true;
    error = null;
    errorCode = null;
    notifyListeners();
    try {
      return await operation(generation);
    } catch (failure) {
      if (_current(generation)) {
        errorCode = failure is AdminRosterRequestError ? failure.code : null;
        if (const {
          'roster_actor_unavailable',
          'roster_access_unavailable',
          'roster_session_required',
          'roster_feature_disabled',
          'roster_import_unavailable',
        }.contains(errorCode)) {
          _clearForSession(
            code: errorCode,
            message: (failure as AdminRosterRequestError).message,
          );
          return null;
        }
        if (const {
          'roster_revision_limit',
          'roster_request_conflict',
          'roster_import_committed',
          'roster_revision_superseded',
          'roster_import_expired',
          'roster_commit_conflict',
          'roster_collection_unavailable',
          'roster_provenance_required',
        }.contains(errorCode)) {
          _writesStopped = true;
          _terminalCode = errorCode;
          _statusRequired = preview != null;
        } else if (commitPending) {
          _statusRequired = true;
        }
        error = failure is AdminRosterRequestError
            ? failure.message
            : _uploadJson == null
            ? 'The source could not be read. Check its format and size, then try again.'
            : const AdminRosterRequestError('unknown').message;
        if (commitPending && !_writesStopped) {
          error =
              'The submission outcome is unknown. Check the saved import status before retrying. The exact request is retained.';
        } else if (preview == null && errorCode == 'roster_request_conflict') {
          error =
              'This upload request conflicts with a saved request. Do not repeat it. Ask an owner to check upload request ${_upload?.body['request_id']} before starting another upload.';
        }
      } else if (!_disposed && !invalidated) {
        _clearForSession();
      }
      return null;
    } finally {
      if (_current(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> prepare(Future<AdminRosterUpload> Function() readUpload) async {
    if (terminalUploadFailure || _writesStopped || preview != null) return;
    await _run<void>((generation) async {
      if (_upload == null) {
        final upload = await readUpload();
        if (!_current(generation)) return;
        _upload = upload;
        _uploadJson = jsonEncode(upload.body);
      }
      final raw = await gateway.prepare(rosterObject(jsonDecode(_uploadJson!)));
      if (!_current(generation)) return;
      final received = AdminRosterPreview.fromJson(rosterObject(raw));
      received.validateInitial(
        sourceKind: _upload!.sourceKind,
        sourceSha256: _upload!.sourceSha256,
        requestId: _upload!.body['request_id'] as String,
        sourceSize: _upload!.sourceSize,
        filename: _upload!.body['filename'] as String? ?? 'pasted-roster.txt',
        declaredMime: _upload!.body['mime_type'] as String? ?? 'text/plain',
        derivedSha256: _upload!.derivedSha256,
      );
      initialPreview = received;
      preview = received;
      rows = received.rows.map((r) => r.editable).toList();
      edited = false;
      affirmed = false;
    });
  }

  void edit(int index, String field, String value) {
    if (!gateway.isCurrent) {
      _clearForSession();
      return;
    }
    if (!canEdit ||
        !{'member_name', 'momo_name', 'momo_number'}.contains(field)) {
      return;
    }
    rows[index][field] = value;
    reviewIssues.remove(index);
    edited = true;
    affirmed = false;
    notifyListeners();
  }

  void affirm(bool value) {
    if (canEdit) {
      affirmed = value;
      notifyListeners();
    }
  }

  Future<void> saveReview(String reason) async {
    if (preview == null || !canSaveReview) return;
    if (_reviewJson == null) {
      reviewIssues.clear();
      final phones = <String>{};
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        for (final field in ['member_name', 'momo_name']) {
          final name = (row[field] as String)
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          if (name.runes.length < 2 ||
              name.runes.length > 120 ||
              RegExp(r'^[=+@-]|[\x00-\x1f\x7f]').hasMatch(name)) {
            reviewIssues[index] =
                'Names must have 2 to 120 characters, without controls or a leading formula character.';
          }
        }
        var phone = (row['momo_number'] as String).replaceAll(
          RegExp(r'[\s().-]'),
          '',
        );
        if (phone.startsWith('250')) phone = '+$phone';
        if (RegExp(r'^07[2389][0-9]{7}$').hasMatch(phone)) {
          phone = '+250${phone.substring(1)}';
        }
        if (!RegExp(r'^\+2507[2389][0-9]{7}$').hasMatch(phone)) {
          reviewIssues[index] = 'Enter a full Rwanda MoMo number.';
        } else if (!phones.add(phone)) {
          reviewIssues[index] =
              'This MoMo number appears more than once in the roster.';
        }
      }
      if (reviewIssues.isNotEmpty) {
        error = 'Correct the indicated rows before saving the review.';
        notifyListeners();
        return;
      }
    }
    await _run<void>((generation) async {
      final parent = preview!;
      _reviewJson ??= jsonEncode({
        'p_import_id': parent.importId,
        'p_parent_revision_id': parent.revisionId,
        'p_rows': rows,
        'p_reason': reason.trim(),
        'p_request_id': const Uuid().v4(),
      });
      final params = rosterObject(jsonDecode(_reviewJson!));
      final raw = await gateway.review(params);
      if (!_current(generation)) return;
      final received = AdminRosterPreview.fromJson(rosterObject(raw));
      received.validateRevision(parent, (params['p_rows'] as List).length);
      preview = received;
      rows = received.rows.map((r) => r.editable).toList();
      _reviewJson = null;
      edited = false;
      affirmed = false;
    });
  }

  Future<AdminRosterCommit?> commit({
    required String title,
    required String reason,
  }) async {
    if (_statusRequired) return recoverStatus();
    if ((!canCommit && !canRetryCommit) || preview == null) return null;
    return _run<AdminRosterCommit>((generation) async {
      final receipt = preview!;
      _commitJson ??= jsonEncode({
        'p_request_id': const Uuid().v4(),
        'p_import_id': receipt.importId,
        'p_revision_id': receipt.revisionId,
        'p_reviewed_rows_sha256': receipt.reviewedRowsSha256,
        'p_human_affirmed': true,
        'p_mode': mode,
        'p_collection_id': collectionId,
        'p_title': mode == 'create' ? title.trim() : null,
        'p_reason': reason.trim(),
      });
      final params = rosterObject(jsonDecode(_commitJson!));
      final raw = await gateway.commit(params);
      if (!_current(generation)) throw StateError(rosterSessionChanged);
      final acknowledged = AdminRosterCommit.fromJson(
        rosterObject(raw),
        request: params,
        expectedCount: receipt.rowCount,
      );
      // Keep the acknowledged request until the host consumes it and closes.
      return acknowledged;
    });
  }

  /// Never reissues a write. A consumed import acknowledges this draft only
  /// when the server's full commit receipt binds its original pending request.
  Future<AdminRosterCommit?> recoverStatus() async {
    if (!canCheckStatus) return null;
    return _run<AdminRosterCommit?>((generation) async {
      final raw = await gateway.read(preview!.importId);
      if (!_current(generation)) return null;
      final status = AdminRosterStatus.fromJson(
        rosterObject(raw),
        source: initialPreview!,
        current: preview!,
      );
      if (status.state == 'committed') {
        if (_commitJson != null &&
            status.commit!['request_id'] ==
                rosterObject(jsonDecode(_commitJson!))['p_request_id']) {
          final receipt = AdminRosterCommit.fromJson(
            status.commit!,
            request: rosterObject(jsonDecode(_commitJson!)),
            expectedCount: preview!.rowCount,
          );
          _statusRequired = false;
          _writesStopped = true;
          return receipt;
        }
        _writesStopped = true;
        _terminalCode = 'roster_import_committed';
        errorCode = _terminalCode;
        error =
            'The server confirms this import was submitted by another request. No new submission was made. Check group ${status.commit!['collection_id']} before closing this draft.';
      } else {
        if (_terminalCode == 'roster_import_committed') invalidRosterReceipt();
        if (status.preview.revisionId != preview!.revisionId ||
            !status.preview.canSubmit && preview!.isHumanReview) {
          _writesStopped = true;
          _terminalCode ??= 'roster_revision_superseded';
        }
        errorCode = _terminalCode;
        error = _writesStopped
            ? 'The server reports no completed submission for this import. ${AdminRosterRequestError(_terminalCode ?? 'roster_revision_superseded').message}'
            : 'The server reports no completed submission. You may retry the same saved submission; its request ID and data are unchanged.';
      }
      _statusRequired = false;
      return null;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _upload = null;
    _uploadJson = null;
    _reviewJson = null;
    _commitJson = null;
    rows = [];
    initialPreview = null;
    preview = null;
    unawaited(_subscription.cancel());
    gateway.dispose();
    super.dispose();
  }
}

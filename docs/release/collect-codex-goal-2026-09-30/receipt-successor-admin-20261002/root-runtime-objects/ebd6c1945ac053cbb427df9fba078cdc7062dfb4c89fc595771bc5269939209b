import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/exact_json_values.dart';

import 'admin_roster_models.dart';
import 'admin_auth_guard.dart';
import 'admin_roster_checkpoint.dart';
import 'roster_file_parser.dart';

part 'admin_roster_gateway.dart';
part 'admin_roster_upload.dart';

/// Private values stay in memory and bounded session-owned server recovery
/// storage. The browser bookmark contains only references and digests.
class AdminRosterDraft extends ChangeNotifier {
  AdminRosterDraft(
    this.gateway, {
    this.collectionId,
    RosterBookmarkStore? bookmarkStore,
  }) : bookmarkStore = bookmarkStore ?? browserRosterBookmarkStore() {
    if (collectionId != null && !rosterUuid.hasMatch(collectionId!)) {
      throw const FormatException('Invalid group.');
    }
    _subscription = gateway.invalidations.listen((_) => _clearForSession());
    _readBookmark();
  }
  final AdminRosterGateway gateway;
  final String? collectionId;
  final RosterBookmarkStore? bookmarkStore;
  RosterBookmark? _bookmark;
  String? storageWarning, recoveryMessage;
  List<AdminRosterInterruption> interruptedImports = const [];
  AdminRosterInterruption? selectedInterruption;
  AdminRosterInterruptedInspection? interruptedInspection;
  Map<String, dynamic>? completedRecoveryReceipt;
  Map<String, dynamic>? _transferRequest;
  bool freshRecoveryAffirmed = false;
  bool get transferOutcomePending => _transferRequest != null;
  String editorTitle = '', editorReason = '';
  bool reloadAvailable = false,
      recovered = false,
      recoveryUnsaved = false,
      _resumedIntent = false;
  bool get canReaffirm =>
      _resumedIntent &&
      commitPending &&
      !busy &&
      !invalidated &&
      !_writesStopped &&
      !_statusRequired;
  bool get hasUnsavedRecoveryChanges => recoveryUnsaved;
  void _readBookmark() {
    if (!gateway.supportsRecovery ||
        gateway.ownerDigest == null ||
        bookmarkStore == null) {
      return;
    }
    try {
      final text = bookmarkStore!.read();
      if (text == null) return;
      final candidate = RosterBookmark.parse(text, gateway.ownerDigest!);
      if (candidate.collectionId != collectionId) return;
      _bookmark = candidate;
      reloadAvailable = true;
    } catch (_) {
      storageWarning =
          'A recovery reference could not be read. No roster data was stored in this browser.';
      try {
        bookmarkStore!.clear();
      } catch (_) {}
    }
  }

  void _persistBookmark() {
    if (_bookmark == null || bookmarkStore == null) return;
    try {
      bookmarkStore!.write(jsonEncode(_bookmark!.toJson()));
    } catch (_) {
      storageWarning =
          'This browser could not save a recovery reference. Keep this tab open; a reload may lose access to the draft.';
    }
  }

  void discardRecoveryReference() {
    _bookmark = null;
    reloadAvailable = false;
    try {
      bookmarkStore?.clear();
    } catch (_) {
      storageWarning = 'The browser recovery reference could not be removed.';
    }
  }

  void setEditorMetadata({String? title, String? reason}) {
    if (!canEdit) return;
    editorTitle = title ?? editorTitle;
    editorReason = reason ?? editorReason;
    recoveryUnsaved = true;
    notifyListeners();
  }

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
  Map<String, dynamic>? _draftSaveParams;
  bool get canSaveRecoveryDraft =>
      !busy &&
      !invalidated &&
      !_writesStopped &&
      preview != null &&
      gateway.supportsRecovery &&
      (canEdit || _draftSaveParams != null);
  bool _statusRequired = false, _writesStopped = false;
  String? _terminalCode;
  bool get statusRequired => _statusRequired;
  bool get canCheckStatus => preview != null && !busy && !invalidated;
  bool get canRetryCommit =>
      commitPending &&
      !_writesStopped &&
      !_statusRequired &&
      (!_resumedIntent || affirmed);
  bool get canSaveReview =>
      !busy &&
      !invalidated &&
      !_writesStopped &&
      !_statusRequired &&
      !commitPending &&
      _draftSaveParams == null &&
      (!reloadAvailable || recovered) &&
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
      _draftSaveParams == null &&
      !commitPending &&
      !_writesStopped &&
      !_statusRequired &&
      (!reloadAvailable || recovered);
  bool get canCommit =>
      canEdit && affirmed && !edited && preview?.canSubmit == true;
  String get mode => collectionId == null ? 'create' : 'existing';
  bool _current(int generation) {
    if (!_disposed && !invalidated && !gateway.isCurrent) _clearForSession();
    return !_disposed && !invalidated && generation == _generation;
  }

  void _clearForSession({String? code, String? message}) {
    interruptedImports = const [];
    selectedInterruption = null;
    interruptedInspection = null;
    completedRecoveryReceipt = null;
    _transferRequest = null;
    freshRecoveryAffirmed = false;
    if (_disposed) return;
    invalidated = true;
    _generation++;
    discardRecoveryReference();
    _draftSaveParams = null;
    editorTitle = '';
    editorReason = '';
    recoveryUnsaved = false;
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
          'roster_draft_superseded',
          'roster_recovery_limit',
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
    if (terminalUploadFailure ||
        _writesStopped ||
        preview != null ||
        reloadAvailable && !recovered) {
      return;
    }
    await _run<void>((generation) async {
      if (_upload == null) {
        final upload = await readUpload();
        if (!_current(generation)) return;
        _upload = upload;
        _uploadJson = jsonEncode(upload.body);
        if (gateway.supportsRecovery && gateway.ownerDigest != null) {
          _bookmark = RosterBookmark(
            ownerDigest: gateway.ownerDigest!,
            uploadRequestId: upload.body['request_id'] as String,
            sourceSha256: upload.sourceSha256,
            collectionId: collectionId,
          );
          _persistBookmark();
        }
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
      if (_bookmark != null) {
        _bookmark = _bookmark!.withReferences(importId: received.importId);
        _persistBookmark();
      }
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
    recoveryUnsaved = true;
    affirmed = false;
    notifyListeners();
  }

  void affirm(bool value) {
    if (canEdit || canReaffirm) {
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
      final raw = gateway.supportsRecovery
          ? await _stageAndExecute('review', _reviewJson!)
          : await gateway.review(params);
      if (!_current(generation)) return;
      final received = AdminRosterPreview.fromJson(rosterObject(raw));
      received.validateRevision(parent, (params['p_rows'] as List).length);
      preview = received;
      rows = received.rows.map((r) => r.editable).toList();
      _reviewJson = null;
      _resumedIntent = false;
      if (_bookmark != null) {
        _bookmark = _bookmark!.withReferences(clearPending: true);
        _persistBookmark();
      }
      edited = false;
      recoveryUnsaved = true;
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
      final raw = gateway.supportsRecovery
          ? await _stageAndExecute('commit', _commitJson!)
          : await gateway.commit(params);
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

  void _validateRecoveryAck(Object? raw, Map<String, dynamic> expected) {
    final ack = rosterObject(raw);
    final fields = {
      'contract_version',
      'ok',
      'import_id',
      'expires_at',
      ...expected.keys,
    };
    if (ack.length != fields.length ||
        !ack.keys.toSet().containsAll(fields) ||
        ack['contract_version'] != 1 ||
        ack['ok'] != true ||
        ack['import_id'] != preview!.importId ||
        ack['expires_at'] is! String ||
        exactJsonTimestamp(ack['expires_at'], field: 'roster.expires_at') !=
            preview!.expiresAt ||
        expected.entries.any((e) => ack[e.key] != e.value)) {
      invalidRosterReceipt();
    }
  }

  Future<Object?> _stageAndExecute(String kind, String text) async {
    final params = decodeRosterRecoveryPayload(
      text,
      rosterTextDigest(text),
      kind: kind,
    );
    final id = params['p_request_id'] as String, hash = rosterTextDigest(text);
    if (_bookmark != null) {
      _bookmark = _bookmark!.withReferences(
        pendingRequestId: id,
        pendingSha256: hash,
      );
      _persistBookmark();
    }
    final stage = await gateway
        .recoveryRpc('admin_stage_roster_import_intent', {
          'p_request_id': id,
          'p_import_id': preview!.importId,
          'p_kind': kind,
          'p_payload': text,
          'p_payload_sha256': hash,
        });
    gateway.checkCurrent();
    _validateRecoveryAck(stage, {
      'request_id': id,
      'kind': kind,
      'payload_sha256': hash,
    });
    final raw = await gateway.recoveryRpc(
      'admin_execute_roster_import_intent',
      {'p_request_id': id, 'p_payload_sha256': hash, 'p_human_affirmed': true},
    );
    gateway.checkCurrent();
    final ack = rosterObject(raw);
    const fields = {
      'contract_version',
      'ok',
      'request_id',
      'import_id',
      'kind',
      'payload_sha256',
      'result',
    };
    if (ack.length != fields.length ||
        !ack.keys.toSet().containsAll(fields) ||
        ack['contract_version'] != 1 ||
        ack['ok'] != true ||
        ack['request_id'] != id ||
        ack['import_id'] != preview!.importId ||
        ack['kind'] != kind ||
        ack['payload_sha256'] != hash) {
      invalidRosterReceipt();
    }
    return ack['result'];
  }

  Future<void> saveRecoveryDraft() async {
    if (!canSaveRecoveryDraft) return;
    await _run<void>((generation) async {
      if (_draftSaveParams == null) {
        final text = jsonEncode({
          'parent_revision_id': preview!.revisionId,
          'rows': rows,
          'title': editorTitle,
          'reason': editorReason,
        });
        final hash = rosterTextDigest(text);
        decodeRosterRecoveryPayload(text, hash, kind: 'draft');
        _draftSaveParams = {
          'p_import_id': preview!.importId,
          'p_checkpoint_id': const Uuid().v4(),
          'p_previous_checkpoint_id': _bookmark?.checkpointId,
          'p_payload': text,
          'p_payload_sha256': hash,
        };
      }
      final request = _draftSaveParams!;
      final raw = await gateway.recoveryRpc(
        'admin_save_roster_import_draft',
        request,
      );
      if (!_current(generation)) return;
      _validateRecoveryAck(raw, {
        'checkpoint_id': request['p_checkpoint_id'],
        'payload_sha256': request['p_payload_sha256'],
      });
      if (_bookmark != null) {
        _bookmark = _bookmark!.withReferences(
          checkpointId: request['p_checkpoint_id'] as String,
        );
        _persistBookmark();
      }
      _draftSaveParams = null;
      recoveryUnsaved = false;
      recoveryMessage =
          'Recovery draft saved for this sign-in. Unsaved changes after this point will be lost on reload.';
    });
  }

  /// Read-only. Resumption never triggers extraction, review or commit.
  Future<AdminRosterCommit?> recoverReload() async {
    final bookmark = _bookmark;
    if (bookmark == null || !gateway.supportsRecovery) return null;
    return _run<AdminRosterCommit?>((generation) async {
      final raw = await gateway.recoveryRpc('admin_recover_roster_import', {
        'p_upload_request_id': bookmark.uploadRequestId,
        'p_pending_request_id': bookmark.pendingRequestId,
      });
      if (!_current(generation)) return null;
      final receipt = AdminRosterRecovery.fromJson(
        rosterObject(raw),
        uploadRequestId: bookmark.uploadRequestId,
        sourceSha256: bookmark.sourceSha256,
        importId: bookmark.importId,
        pendingRequestId: bookmark.pendingRequestId,
        pendingSha256: bookmark.pendingSha256,
      );
      _draftSaveParams = null;
      _writesStopped = false;
      _terminalCode = null;
      recovered = true;
      affirmed = false;
      _resumedIntent = false;
      _statusRequired = false;
      if (receipt.initial == null) {
        _writesStopped = true;
        recoveryMessage = switch (receipt.state) {
          'missing_source' =>
            'No source receipt exists for this upload reference. The browser saved no file bytes. Discard this reference and reattach the original source to start a new upload.',
          'awaiting_preview' =>
            'The source was received but no preview has been acknowledged. Check recovery again; no extraction was retried. Do not start a duplicate upload while this outcome is uncertain.',
          'expired' =>
            'This recovery draft has expired. Discard its reference and start a new upload. Original audit records are retained.',
          _ =>
            'The source preparation failed. No members were added. Discard the reference and reattach a corrected source.',
        };
        return null;
      }
      initialPreview = receipt.initial;
      preview = receipt.status!.preview;
      rows = preview!.rows.map((r) => r.editable).toList();
      edited = false;
      recoveryUnsaved = false;
      _bookmark = bookmark.withReferences(
        importId: receipt.importId,
        checkpointId: receipt.checkpointId,
      );
      editorTitle = '';
      editorReason = '';
      if (receipt.status!.state == 'committed') {
        _writesStopped = true;
        if (receipt.intentKind == 'commit' &&
            receipt.intent != null &&
            receipt.intentResult != null &&
            receipt.status!.commit!['request_id'] ==
                receipt.intent!['p_request_id']) {
          return AdminRosterCommit.fromJson(
            receipt.status!.commit!,
            request: receipt.intent!,
            expectedCount: preview!.rowCount,
          );
        }
        recoveryMessage =
            'The server confirms this import was submitted. No new submission was made. Check group ${receipt.status!.commit!['collection_id']}.';
      } else if (receipt.intent != null && receipt.intentResult == null) {
        _resumedIntent = true;
        if (receipt.intentKind == 'review') {
          _reviewJson = receipt.intentText;
          rows = (receipt.intent!['p_rows'] as List)
              .map((v) => rosterObject(v))
              .toList();
          edited = true;
          editorReason = receipt.intent!['p_reason'] as String;
          if (receipt.intent!['p_parent_revision_id'] != preview!.revisionId) {
            _writesStopped = true;
          }
          recoveryMessage =
              'A saved review request is pending. Inspect every row, then explicitly continue the same review request. No review was submitted during recovery.';
        } else {
          _commitJson = receipt.intentText;
          editorTitle = receipt.intent!['p_title'] as String? ?? '';
          editorReason = receipt.intent!['p_reason'] as String;
          if (receipt.intent!['p_revision_id'] != preview!.revisionId ||
              receipt.intent!['p_collection_id'] != collectionId) {
            _writesStopped = true;
          }
          recoveryMessage =
              'A saved submission is pending. Recheck every page and confirm the identities again before explicitly continuing the same request. No submission was made during recovery.';
        }
      } else {
        _reviewJson = null;
        _commitJson = null;
        if (receipt.draft != null &&
            receipt.draft!['parent_revision_id'] == preview!.revisionId) {
          rows = (receipt.draft!['rows'] as List)
              .map((v) => rosterObject(v))
              .toList();
          editorTitle = receipt.draft!['title'] as String;
          editorReason = receipt.draft!['reason'] as String;
          edited =
              jsonEncode(rows) !=
              jsonEncode(preview!.rows.map((r) => r.editable).toList());
          recoveryMessage =
              'The saved private editor draft was restored. Later unsaved edits were not stored. Review all pages again before continuing.';
        } else {
          recoveryMessage = receipt.draft != null
              ? 'A newer review superseded the editor draft. The latest saved review is shown; no stale edits were applied.'
              : 'The latest saved review is shown. Unsaved rows, group name and reason were not stored.';
        }
        _bookmark = _bookmark!.withReferences(clearPending: true);
      }
      _persistBookmark();
      return null;
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

  Future<void> listFreshRecovery() async {
    if (preview != null ||
        _transferRequest != null ||
        !gateway.supportsRecovery) {
      return;
    }
    await _run<void>((generation) async {
      final raw = await gateway.recoveryRpc(
        'admin_list_interrupted_roster_imports',
        {},
      );
      if (!_current(generation)) return;
      final list = AdminRosterInterruptedList.fromJson(
        rosterObject(raw),
        gateway.ownerDigest!,
      );
      interruptedImports = list.items;
      selectedInterruption = null;
      interruptedInspection = null;
      freshRecoveryAffirmed = false;
      recoveryMessage = list.items.isEmpty
          ? 'No eligible saved import was found for this fresh sign-in. Unacknowledged uploads and unsaved edits cannot be reconstructed; reattach the original source if needed.'
          : 'Choose an interrupted import to inspect. Lookup does not restore approvals, submit members or retry extraction.';
    });
  }

  Future<void> inspectFreshRecovery(AdminRosterInterruption selected) async {
    if (preview != null ||
        _transferRequest != null ||
        selected.state != 'interrupted') {
      return;
    }
    await _run<void>((generation) async {
      final raw = await gateway.recoveryRpc(
        'admin_inspect_interrupted_roster_import',
        {'p_import_id': selected.importId, 'p_etag': selected.etag},
      );
      if (!_current(generation)) return;
      final inspected = AdminRosterInterruptedInspection.fromJson(
        rosterObject(raw),
        selected,
        gateway.ownerDigest!,
      );
      selectedInterruption = selected;
      interruptedInspection = inspected;
      freshRecoveryAffirmed = false;
      recoveryMessage =
          'This is a read-only inspection. An explicit recovery starts a new branch and resets every review and submission confirmation. No provider call or member submission is made.';
    });
  }

  Future<void> readFreshCommittedStatus(
    AdminRosterInterruption selected,
  ) async {
    if (selected.state != 'committed' || preview != null) return;
    await _run<void>((generation) async {
      final raw = rosterObject(
        await gateway.recoveryRpc(
          'admin_get_interrupted_roster_commit_status',
          {'p_import_id': selected.importId},
        ),
      );
      if (!_current(generation)) return;
      if (raw.keys.toSet().difference({
            'contract_version',
            'ok',
            'import_id',
            'state',
            'commit',
          }).isNotEmpty ||
          raw.length != 5 ||
          raw['contract_version'] != 1 ||
          raw['ok'] != true ||
          rosterId(raw, 'import_id') != selected.importId ||
          raw['state'] != 'committed') {
        invalidRosterReceipt();
      }
      final receipt = rosterObject(raw['commit']);
      final required = {
        'contract_version',
        'ok',
        'request_id',
        'import_id',
        'revision_id',
        'reviewed_rows_sha256',
        'collection_id',
        'mode',
        'roster_count',
        'share_code_ready',
        'replayed',
      };
      if (receipt.length != required.length ||
          !receipt.keys.toSet().containsAll(required) ||
          receipt['ok'] != true ||
          receipt['contract_version'] != 1 ||
          rosterId(receipt, 'import_id') != selected.importId ||
          !{'create', 'existing'}.contains(receipt['mode']) ||
          receipt['roster_count'] is! int ||
          (receipt['roster_count'] as int) < 1 ||
          (receipt['roster_count'] as int) > 500 ||
          receipt['share_code_ready'] is! bool ||
          receipt['replayed'] is! bool ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch('${receipt['reviewed_rows_sha256']}')) {
        invalidRosterReceipt();
      }
      for (final key in ['request_id', 'revision_id', 'collection_id']) {
        rosterId(receipt, key);
      }
      completedRecoveryReceipt = immutableRosterJson(receipt);
      recoveryMessage =
          'This import is already completed. Its saved receipt is read-only; recovery cannot clone or repeat that submission.';
    });
  }

  void affirmFreshRecovery(bool value) {
    if (busy ||
        invalidated ||
        interruptedInspection == null ||
        _transferRequest != null) {
      return;
    }
    freshRecoveryAffirmed = value;
    notifyListeners();
  }

  Future<void> transferFreshRecovery() async {
    if (_transferRequest != null ||
        !freshRecoveryAffirmed ||
        interruptedInspection == null ||
        selectedInterruption == null) {
      return;
    }
    await _run<void>((generation) async {
      _transferRequest = {
        'p_request_id': const Uuid().v4(),
        'p_import_id': selectedInterruption!.importId,
        'p_etag': selectedInterruption!.etag,
        'p_human_affirmed': true,
      };
      final raw = await gateway.recoveryRpc(
        'admin_transfer_interrupted_roster_import',
        _transferRequest!,
      );
      if (!_current(generation)) return;
      await _adoptFreshTransfer(raw, generation);
    });
  }

  /// Response loss never causes an automatic transfer/write retry.
  Future<void> checkFreshTransferStatus() async {
    if (_transferRequest == null || interruptedInspection == null) return;
    await _run<void>((generation) async {
      final raw = rosterObject(
        await gateway.recoveryRpc('admin_get_roster_transfer_status', {
          'p_request_id': _transferRequest!['p_request_id'],
        }),
      );
      if (!_current(generation)) return;
      if (raw['state'] == 'missing') {
        const fields = {'contract_version', 'ok', 'state', 'request_id'};
        if (raw.length != fields.length ||
            !raw.keys.toSet().containsAll(fields) ||
            raw['contract_version'] != 1 ||
            raw['ok'] != true ||
            raw['request_id'] != _transferRequest!['p_request_id']) {
          invalidRosterReceipt();
        }
        recoveryMessage =
            'No transfer was acknowledged. No write was repeated. Close this draft and inspect eligible saved imports again before explicitly deciding to recover.';
        return;
      }
      await _adoptFreshTransfer(raw, generation);
    });
  }

  Future<void> _adoptFreshTransfer(Object? raw, int generation) async {
    final ack = AdminRosterTransferAck.fromJson(
      rosterObject(raw),
      request: _transferRequest!,
      ownerDigest: gateway.ownerDigest!,
      inspected: interruptedInspection!,
    );
    final recoveredRaw = await gateway
        .recoveryRpc('admin_recover_roster_import', {
          'p_upload_request_id': ack.destinationReferenceId,
          'p_pending_request_id': null,
        });
    if (!_current(generation)) return;
    final receipt = AdminRosterRecovery.fromJson(
      rosterObject(recoveredRaw),
      uploadRequestId: ack.destinationReferenceId,
      sourceSha256: interruptedInspection!.initial.sourceSha256,
      importId: ack.toImportId,
    );
    final initial = receipt.initial;
    final lineage = initial?.recoveryLineage;
    if (receipt.state != 'preview_ready' ||
        initial == null ||
        lineage == null ||
        initial.revisionId != ack.initialRevisionId ||
        initial.canSubmit ||
        initial.isHumanReview ||
        lineage.ownerDigest != gateway.ownerDigest ||
        lineage.transferRequestId != ack.requestId ||
        lineage.rootImportId != ack.rootImportId ||
        lineage.fromImportId != ack.fromImportId ||
        lineage.toImportId != ack.toImportId ||
        initial.expiresAt != ack.expiresAt ||
        initial.sourceKind != interruptedInspection!.initial.sourceKind ||
        initial.model != interruptedInspection!.initial.model ||
        jsonEncode(initial.sourceReceipt.raw) !=
            jsonEncode(interruptedInspection!.initial.sourceReceipt.raw) ||
        jsonEncode(initial.raw['rows']) !=
            jsonEncode(interruptedInspection!.initial.raw['rows']) ||
        lineage.originalProofSha256 != ack.originalProofSha256 ||
        receipt.checkpointId != ack.checkpointId ||
        receipt.draft == null ||
        rosterObject(recoveredRaw)['draft'] is! Map ||
        rosterObject(rosterObject(recoveredRaw)['draft'])['payload_sha256'] !=
            ack.draftSha256 ||
        receipt.draft!['parent_revision_id'] != initial.revisionId) {
      invalidRosterReceipt();
    }
    initialPreview = initial;
    preview = receipt.status!.preview;
    rows = (receipt.draft!['rows'] as List).map(rosterObject).toList();
    editorTitle = receipt.draft!['title'] as String;
    editorReason = receipt.draft!['reason'] as String;
    _upload = null;
    _uploadJson = null;
    _reviewJson = null;
    _commitJson = null;
    _draftSaveParams = null;
    _statusRequired = false;
    _writesStopped = false;
    _terminalCode = null;
    _resumedIntent = false;
    edited = true;
    affirmed = false;
    recovered = true;
    recoveryUnsaved = false;
    freshRecoveryAffirmed = false;
    _transferRequest = null;
    interruptedImports = const [];
    selectedInterruption = null;
    interruptedInspection = null;
    _bookmark = RosterBookmark(
      ownerDigest: gateway.ownerDigest!,
      uploadRequestId: ack.destinationReferenceId,
      sourceSha256: initial.sourceSha256,
      collectionId: collectionId,
      importId: initial.importId,
      checkpointId: ack.checkpointId,
    );
    _persistBookmark();
    recoveryMessage =
        'The saved editor was explicitly recovered into this fresh sign-in. All review pages and submission confirmations were reset. Review every row and save a new human review before submitting.';
  }

  @override
  void dispose() {
    _disposed = true;
    interruptedImports = const [];
    selectedInterruption = null;
    interruptedInspection = null;
    completedRecoveryReceipt = null;
    _transferRequest = null;
    _draftSaveParams = null;
    editorTitle = '';
    editorReason = '';
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

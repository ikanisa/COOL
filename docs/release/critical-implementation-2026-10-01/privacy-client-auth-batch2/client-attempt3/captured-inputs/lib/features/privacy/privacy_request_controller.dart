import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'privacy_contract.dart';
import 'privacy_session.dart';
import 'privacy_transport.dart';

/// Staged member mechanics; route wiring and view ownership remain with the
/// caller. Only a confirmed own-server receipt can set [receipt].
final class PrivacyRequestController {
  PrivacyRequestController({
    required this.authority,
    required this.transport,
    String Function()? newSubmissionId,
  }) : _newId = newSubmissionId ?? const Uuid().v4;

  final PrivacySessionAuthority authority;
  final PrivacyRequestTransport transport;
  final String Function() _newId;
  String? _subjectId;
  PrivacySessionSnapshot? _challenge;
  PrivacySessionSnapshot? _fresh;
  PrivacyPendingIdentity? _pending;
  String? _reason;
  bool _reasonKnown = false;
  PrivacyIntakeReceipt? _receipt;
  bool _unknown = false;
  bool _busy = false;
  bool _disposed = false;
  int _epoch = 0;

  bool get busy => _busy;
  bool get codeSent => _challenge != null;
  bool get outcomeUnknown => _unknown;
  PrivacyPendingIdentity? get pendingIdentity => _pending;
  PrivacyIntakeReceipt? get receipt => _receipt;

  /// Cancels this operation, without signing out or retracting an accepted
  /// request. A sent request may commit even when its response is discarded.
  void cancel() {
    ++_epoch;
    _busy = false;
    _challenge = null;
    _fresh = null;
    _reason = null;
    _reasonKnown = false;
    if (!_unknown && _receipt == null) {
      _pending = null;
    }
  }

  void dispose() {
    _disposed = true;
    cancel();
  }

  PrivacySessionSnapshot _capture() {
    if (_disposed) {
      throw const PrivacyRequestException(PrivacyFailure.cancelled);
    }
    final current = authority.capture();
    _subjectId ??= current.subjectId;
    if (_subjectId != current.subjectId) {
      throw const PrivacyRequestException(PrivacyFailure.sessionChanged);
    }
    return current;
  }

  int _begin() {
    if (_busy) throw const PrivacyRequestException(PrivacyFailure.busy);
    _busy = true;
    return _epoch;
  }

  void _fence(PrivacySessionSnapshot original, int epoch) {
    if (_disposed || epoch != _epoch) {
      throw const PrivacyRequestException(PrivacyFailure.cancelled);
    }
    if (!_capture().sameFence(original)) {
      throw const PrivacyRequestException(PrivacyFailure.sessionChanged);
    }
  }

  void _finish(int epoch) {
    if (epoch == _epoch) _busy = false;
  }

  Future<void> sendCode({String? captchaToken}) async {
    final original = _capture();
    final epoch = _begin();
    _challenge = null;
    _fresh = null;
    try {
      _fence(original, epoch);
      await transport.sendCode(original, captchaToken: captchaToken);
      _fence(original, epoch);
      _challenge = original;
    } finally {
      _finish(epoch);
    }
  }

  Future<void> verifyCode(String code, {String? captchaToken}) async {
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      throw const PrivacyRequestException(PrivacyFailure.invalidCode);
    }
    final original = _challenge;
    if (original == null) {
      throw const PrivacyRequestException(PrivacyFailure.codeRequired);
    }
    final epoch = _begin();
    try {
      _fence(original, epoch);
      final verified = await transport.verifyCode(
        original,
        code,
        captchaToken: captchaToken,
      );
      _fence(original, epoch);
      _validateVerified(original, verified);
      // Both operations are synchronous: no late result can overwrite a newer
      // account between the last fence and the pinned session installation.
      final adopted = authority.adopt(original, verified);
      _fence(adopted, epoch);
      _fresh = adopted;
      _challenge = null;
    } finally {
      _finish(epoch);
    }
  }

  void _validateVerified(PrivacySessionSnapshot original, Session verified) {
    final candidate = PrivacySessionSnapshot.parse(
      verified,
      original.generation,
    );
    if (candidate == null ||
        candidate.subjectId != original.subjectId ||
        candidate.sessionId == original.sessionId ||
        privacyAuthPhone(verified) != privacyAuthPhone(original.session) ||
        verified.refreshToken?.isNotEmpty != true ||
        verified.isExpired) {
      throw const PrivacyRequestException(
        PrivacyFailure.verificationUnavailable,
      );
    }
  }

  PrivacySessionSnapshot _freshSession() {
    final current = _capture();
    if (_fresh == null || !current.sameFence(_fresh!)) {
      throw const PrivacyRequestException(PrivacyFailure.freshSignInRequired);
    }
    return current;
  }

  /// First submission. After an ambiguous response use [refreshStatus] before
  /// explicitly choosing [retrySubmission]. No automatic write replay occurs.
  Future<PrivacyIntakeReceipt> submit({String? reason}) async {
    if (_unknown) {
      throw const PrivacyRequestException(PrivacyFailure.outcomeUnknown);
    }
    return _submit(reason, retry: false);
  }

  Future<PrivacyIntakeReceipt> retrySubmission({String? reason}) async {
    if (_pending == null || !_unknown || !_reasonKnown) {
      throw const PrivacyRequestException(PrivacyFailure.outcomeUnknown);
    }
    return _submit(reason, retry: true);
  }

  Future<PrivacyIntakeReceipt> _submit(
    String? reason, {
    required bool retry,
  }) async {
    final original = _freshSession();
    final clean = cleanPrivacyReason(reason);
    if (_receipt != null) return _receipt!;
    if (_pending != null && (!_reasonKnown || clean != _reason)) {
      throw const PrivacyRequestException(PrivacyFailure.conflictingRequest);
    }
    final epoch = _begin();
    try {
      _pending ??= PrivacyPendingIdentity(
        subjectId: original.subjectId,
        submissionId: _newId(),
      );
      _reason = clean;
      _reasonKnown = true;
      _fence(original, epoch);
      // Mark unknown before sending: cancellation or an Auth change cannot
      // turn a potentially committed request into an unsent local draft.
      _unknown = true;
      final accepted = await transport.submit(
        original,
        _pending!.submissionId,
        clean,
      );
      _fence(original, epoch);
      if (accepted.submissionId != _pending!.submissionId ||
          accepted.reasonSupplied != (clean != null)) {
        throw const PrivacyRequestException(PrivacyFailure.outcomeUnknown);
      }
      _receipt = accepted;
      _unknown = false;
      return accepted;
    } on PrivacyRequestException catch (error) {
      if (error.failure == PrivacyFailure.freshSignInRequired) {
        _fresh = null;
      }
      if (error.failure != PrivacyFailure.outcomeUnknown &&
          error.failure != PrivacyFailure.sessionChanged &&
          error.failure != PrivacyFailure.cancelled) {
        _unknown = retry;
      }
      rethrow;
    } finally {
      _finish(epoch);
    }
  }

  /// A live-session read does not require another OTP. The authoritative
  /// canonical lookup recovers accepted requests after process restart without
  /// writing identifiers into the existing financial protected snapshot.
  Future<PrivacyIntakeReceipt?> refreshStatus() async {
    final original = _capture();
    final epoch = _begin();
    try {
      final accepted = _pending == null
          ? await transport.currentStatus(original)
          : await transport.status(original, _pending!.submissionId);
      _fence(original, epoch);
      if (_receipt != null && accepted?.requestId != _receipt!.requestId) {
        throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
      }
      _receipt = accepted;
      if (accepted != null) {
        _unknown = false;
        _reason = null;
        _reasonKnown = false;
      }
      return accepted;
    } finally {
      _finish(epoch);
    }
  }
}

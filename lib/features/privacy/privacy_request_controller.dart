import 'dart:async';

import '../../core/cloudflare/collect_cloudflare_client.dart';
import 'package:uuid/uuid.dart';

import 'privacy_contract.dart';
import 'privacy_email_verification.dart';
import 'privacy_review_contract.dart';
import 'privacy_session.dart';
import 'privacy_transport.dart';

/// Staged member mechanics; route wiring and view ownership remain with the
/// caller. Only a confirmed own-server receipt can set [receipt].
final class PrivacyRequestController {
  PrivacyRequestController({
    required this.authority,
    required this.transport,
    String? subjectId,
    String Function()? newSubmissionId,
  }) : _newId = newSubmissionId ?? const Uuid().v4,
       _subjectId = subjectId {
    if (authority is PrivacyEmailSessionAuthority &&
        transport is PrivacyEmailWireTransport &&
        (transport as PrivacyEmailWireTransport).privacyEmailAvailable) {
      _email = PrivacyEmailVerification(
        authority: authority as PrivacyEmailSessionAuthority,
        transport: transport as PrivacyEmailWireTransport,
      );
      try {
        _usingEmail =
            authority.capture().session.user.email?.isNotEmpty == true;
      } catch (_) {
        _usingEmail = false;
      }
    }
    if (subjectId != null && !privacyUuid(subjectId)) {
      throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
    }
  }

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
  PrivacyReviewStatus? _review;
  PrivacySessionSnapshot? _reviewSession;
  PrivacySessionSnapshot? _verificationOwner;
  PrivacyEmailVerification? _email;
  bool _usingEmail = false;
  bool get emailVerificationAvailable => _email != null;
  bool get usingEmailVerification => _usingEmail;
  bool get emailVerificationPending => _email?.hasAttempt == true;
  bool get emailVerificationUnknown => _email?.unknown == true;
  String? get emailDestinationHint => _email?.destinationHint;
  String get emailVerificationMessage =>
      _email?.message ?? 'Email verification is unavailable.';
  bool get canSendEmailCode => _email?.canStart == true;
  int get emailResendSeconds => _email?.resendSeconds ?? 0;

  void selectEmailVerification(bool email) {
    if (email == _usingEmail) return;
    if (_busy ||
        email && _email == null ||
        _pending != null ||
        _receipt != null) {
      throw const PrivacyRequestException(PrivacyFailure.busy);
    }
    ++_epoch;
    final owner = _verificationOwner;
    if (owner != null && transport is PrivacyVerificationCancellation) {
      (transport as PrivacyVerificationCancellation).cancelVerification(owner);
    }
    if (_usingEmail) unawaited(_email!.cancel());
    _usingEmail = email;
    _challenge = null;
    _fresh = null;
    _verificationOwner = null;
  }

  Future<void> checkEmailVerification() async {
    if (!_usingEmail || _email == null) {
      throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
    }
    final original = _capture(), epoch = _begin();
    try {
      await _email!.status();
      _fence(original, epoch);
      _challenge = _email!.codeReady ? original : null;
    } finally {
      _finish(epoch);
    }
  }

  Future<void> cancelEmailVerification() {
    ++_epoch;
    _busy = false;
    _challenge = null;
    _fresh = null;
    _verificationOwner = null;
    return _email?.cancel() ?? Future<void>.value();
  }

  bool _unknown = false;
  bool _busy = false;
  bool _disposed = false;
  int _epoch = 0;

  bool get busy => _busy && _ownsVisibleState;
  bool get hasFreshVerification {
    final current = _visibleSession();
    return current != null && _fresh != null && current.sameFence(_fresh!);
  }

  bool get codeSent {
    final current = _visibleSession();
    return _challenge != null &&
        current != null &&
        current.sameFence(_challenge!) &&
        (!_usingEmail || _email?.codeReady == true);
  }

  bool get outcomeUnknown => _unknown && _ownsVisibleState;
  PrivacyPendingIdentity? get pendingIdentity =>
      _ownsVisibleState ? _pending : null;
  PrivacyIntakeReceipt? get receipt => _ownsVisibleState ? _receipt : null;
  PrivacyReviewStatus? get reviewStatus {
    final current = _visibleSession();
    return current != null &&
            _reviewSession != null &&
            current.sameFence(_reviewSession!)
        ? _review
        : null;
  }

  PrivacySessionSnapshot? _visibleSession() {
    if (_disposed || _subjectId == null) return null;
    try {
      final current = authority.capture();
      return current.subjectId == _subjectId ? current : null;
    } on PrivacyRequestException {
      return null;
    }
  }

  bool get _ownsVisibleState => _visibleSession() != null;

  /// Cancels this operation, without signing out or retracting an accepted
  /// request. A sent request may commit even when its response is discarded.
  void cancel() {
    ++_epoch;
    final verificationOwner = _verificationOwner;
    _verificationOwner = null;
    final cancellation = transport;
    if (verificationOwner != null &&
        cancellation is PrivacyVerificationCancellation) {
      (cancellation as PrivacyVerificationCancellation).cancelVerification(
        verificationOwner,
      );
    }
    unawaited(_email?.cancel() ?? Future<void>.value());
    _busy = false;
    _challenge = null;
    _fresh = null;
    _reason = null;
    _reasonKnown = false;
    _review = null;
    _reviewSession = null;
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
    _verificationOwner = original;
    _challenge = null;
    _fresh = null;
    try {
      _fence(original, epoch);
      if (_usingEmail) {
        await _email!.challenge(original, captchaToken: captchaToken);
      } else {
        await transport.sendCode(original, captchaToken: captchaToken);
      }
      _fence(original, epoch);
      _challenge = original;
    } finally {
      _finish(epoch);
    }
  }

  Future<void> verifyCode(String code, {String? captchaToken}) async {
    if (!RegExp(
      _usingEmail ? r'^[0-9]{6,10}$' : r'^[0-9]{6}$',
    ).hasMatch(code)) {
      throw const PrivacyRequestException(PrivacyFailure.invalidCode);
    }
    final original = _challenge;
    if (original == null) {
      throw const PrivacyRequestException(PrivacyFailure.codeRequired);
    }
    final epoch = _begin();
    _verificationOwner = original;
    try {
      _fence(original, epoch);
      if (_usingEmail) {
        final adopted = await _email!.verify(code, captchaToken: captchaToken);
        _fence(adopted, epoch);
        _fresh = adopted;
        _challenge = null;
        return;
      }
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

  void _validateVerified(
    PrivacySessionSnapshot original,
    CollectAuthSession verified,
  ) {
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
    _review = null;
    _reviewSession = null;
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

  /// A failed review read never changes the confirmed intake receipt or
  /// supplies a guessed review state. The caller can show both outcomes.
  Future<PrivacyReviewStatus> refreshReviewStatus() async {
    final original = _capture();
    final request = _receipt;
    if (request == null) {
      throw const PrivacyRequestException(PrivacyFailure.requestUnavailable);
    }
    final epoch = _begin();
    _review = null;
    _reviewSession = null;
    try {
      _fence(original, epoch);
      final observed = await transport.reviewStatus(
        original,
        request.requestId,
      );
      _fence(original, epoch);
      if (_receipt?.requestId != request.requestId ||
          observed.requestId != request.requestId) {
        throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
      }
      _review = observed;
      _reviewSession = original;
      return observed;
    } finally {
      _finish(epoch);
    }
  }
}

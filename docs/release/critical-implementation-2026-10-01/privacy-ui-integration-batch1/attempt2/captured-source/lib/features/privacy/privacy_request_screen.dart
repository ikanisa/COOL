import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/env/app_env.dart';
import '../../core/supabase/supabase_module.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../auth/widgets/auth_screen_widgets.dart';
import 'privacy_contract.dart';
import 'privacy_providers.dart';
import 'privacy_request_controller.dart';
import 'privacy_session.dart';
import 'privacy_transport.dart';

/// Own-server intake and recovery. A confirmation records a request for review;
/// it never represents erasure or an approved retention decision.
class DeleteAccountRequestScreen extends ConsumerWidget {
  const DeleteAccountRequestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(privacyRequestControllerProvider);
    if (controller == null) {
      return ScreenScaffold(
        title: 'Delete request',
        children: [
          const InfoSecurityBanner(
            title: 'Request service unavailable',
            message:
                'Connect to Collect to check or submit your account deletion request.',
            tone: CollectStatusTone.warning,
          ),
          CollectButton(
            label: 'Get help',
            onPressed: () => context.go('/settings/help'),
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      );
    }
    // A new subject gets new view ownership as well as a new controller. No
    // old owner's reasons, OTP, outcome, or receipt cross that boundary.
    return _PrivacyRequestForm(
      key: ObjectKey(controller),
      controller: controller,
    );
  }
}

class _PrivacyRequestForm extends ConsumerStatefulWidget {
  const _PrivacyRequestForm({required this.controller, super.key});
  final PrivacyRequestController controller;

  @override
  ConsumerState<_PrivacyRequestForm> createState() =>
      _PrivacyRequestFormState();
}

class _PrivacyRequestFormState extends ConsumerState<_PrivacyRequestForm> {
  final _otp = TextEditingController();
  final Set<String> _reasons = {};
  String? _owner;
  String? _verifiedSessionId;
  String? _error;
  String? _sentReason;
  bool _running = false;
  bool _checkingInitialStatus = true;
  bool _statusAttempted = false;
  Timer? _resendTimer;
  int _resendRemaining = 0;

  PrivacyRequestController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    try {
      _owner = _controller.authority.capture().subjectId;
    } catch (_) {
      _error = _privacyPublicError(PrivacyFailure.sessionChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_checkStatus(initial: true));
    });
  }

  @override
  void dispose() {
    _controller.cancel();
    _resendTimer?.cancel();
    _otp.dispose();
    super.dispose();
  }

  PrivacySessionSnapshot? _liveOwner() {
    try {
      final snapshot = _controller.authority.capture();
      return snapshot.subjectId == _owner ? snapshot : null;
    } catch (_) {
      return null;
    }
  }

  bool get _verified {
    final current = _liveOwner();
    return current != null &&
        _verifiedSessionId != null &&
        current.sessionId == _verifiedSessionId &&
        !_controller.codeSent;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_running || !mounted) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      await action();
    } on PrivacyRequestException catch (error) {
      if (mounted) {
        _error = _privacyPublicError(error.failure);
        if (error.failure == PrivacyFailure.sessionChanged ||
            error.failure == PrivacyFailure.freshSignInRequired) {
          _verifiedSessionId = null;
          _otp.clear();
        }
      }
    } catch (_) {
      if (mounted) {
        _error =
            'The request service is unavailable. Check your connection and try again.';
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _checkStatus({bool initial = false}) async {
    await _run(() async {
      try {
        await _controller.refreshStatus();
      } finally {
        // A read attempt cannot prove that an uncertain write failed. A later
        // retry remains an explicit choice with the exact existing UUID.
        if (mounted) _statusAttempted = true;
      }
    });
    if (initial && mounted) setState(() => _checkingInitialStatus = false);
  }

  Future<void> _sendCode() => _run(() async {
    _verifiedSessionId = null;
    await _controller.sendCode();
    if (!mounted) return;
    _otp.clear();
    _resendTimer?.cancel();
    _resendRemaining = 45;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendRemaining <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendRemaining = 0);
      } else {
        setState(() => _resendRemaining--);
      }
    });
  });

  Future<void> _verifyCode() => _run(() async {
    await _controller.verifyCode(_otp.text);
    final current = _liveOwner();
    if (current == null) {
      throw const PrivacyRequestException(PrivacyFailure.sessionChanged);
    }
    if (mounted) {
      _verifiedSessionId = current.sessionId;
      _otp.clear();
    }
  });

  Future<void> _confirmSubmission({required bool retry}) async {
    if (_running || !_verified || _liveOwner() == null) return;
    final approved = await showCollectConfirmationSheet(
      context: context,
      title: retry ? 'Retry your request?' : 'Submit delete request?',
      message: retry
          ? 'Send the same request again. Its earlier result is still unconfirmed; this will not create a separate deletion request.'
          : 'Send your account deletion request for review. Your account remains accessible while review is pending.',
      confirmLabel: retry ? 'Retry request' : 'Submit request',
      destructive: true,
    );
    if (!approved || !mounted) return;
    await _run(() async {
      if (!retry) {
        _sentReason = _reasons.isEmpty ? null : _reasons.join('; ');
      }
      _statusAttempted = false;
      if (retry) {
        await _controller.retrySubmission(reason: _sentReason);
      } else {
        await _controller.submit(reason: _sentReason);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // This triggers view renewal on ordinary Auth events. Immediate method and
    // receipt ownership still comes from the synchronous live-session fences.
    ref.watch(collectAuthenticatedUserIdProvider);
    final live = _liveOwner();
    final receipt = live == null ? null : _controller.receipt;
    final busy = _running || _checkingInitialStatus;
    final unknown = live != null && _controller.outcomeUnknown;
    final env = ref.watch(appEnvProvider);
    final reasons =
        ref.watch(collectAccountDeletionReasonsProvider).valueOrNull ??
        collectDefaultAccountDeletionReasons;
    final canEdit =
        !busy &&
        live != null &&
        _controller.pendingIdentity == null &&
        receipt == null;
    String? maskedPhone;
    if (live != null) {
      try {
        final phone = privacyAuthPhone(live.session);
        maskedPhone = '•••• ${phone.substring(phone.length - 4)}';
      } catch (_) {
        // An unavailable Auth phone cannot be replaced with a profile/MoMo
        // number or an editable destination for sensitive reauthentication.
      }
    }
    // A configured bot challenge needs an actual solver integration. Asking a
    // member to paste its backend token cannot establish verification.
    final verificationReady = !env.authCaptchaEnabled;
    return ScreenScaffold(
      title: 'Delete request',
      onRefresh: busy ? null : () => _checkStatus(),
      children: [
        if (live == null)
          InfoSecurityBanner(
            title: 'Sign-in required',
            message: _privacyPublicError(PrivacyFailure.sessionChanged),
            tone: CollectStatusTone.warning,
          )
        else if (_checkingInitialStatus)
          const LoadingStatePanel(
            title: 'Checking your request',
            message: 'Reading the status of your account deletion request.',
          )
        else if (receipt != null)
          _PrivacyReceiptCard(receipt: receipt)
        else ...[
          const InfoSecurityBanner(
            title: 'Request account deletion',
            message:
                'Verify your identity to submit a request for review. Submitting a request does not delete your account.',
            tone: CollectStatusTone.privacy,
          ),
          if (unknown)
            const InfoSecurityBanner(
              title: 'Request result unconfirmed',
              message:
                  'Your request may have been received. Check its status before choosing to retry the same request.',
              tone: CollectStatusTone.warning,
            ),
          CollectCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reason (optional)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                CollectSpacing.gap8,
                for (final reason in reasons)
                  CheckboxListTile(
                    value: _reasons.contains(reason.label),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(reason.label),
                    onChanged: canEdit
                        ? (selected) => setState(() {
                            if (selected == true) {
                              _reasons.add(reason.label);
                            } else {
                              _reasons.remove(reason.label);
                            }
                          })
                        : null,
                  ),
              ],
            ),
          ),
          CollectCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _verified ? 'Code verified' : 'Verify your identity',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                CollectSpacing.gap12,
                Text(
                  maskedPhone == null
                      ? 'Your signed-in phone number is unavailable. Get help to continue.'
                      : 'Use the WhatsApp code for your signed-in number $maskedPhone.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (env.authCaptchaEnabled && !_verified) ...[
                  CollectSpacing.gap16,
                  const InfoSecurityBanner(
                    title: 'Verification unavailable',
                    message:
                        'Identity verification is unavailable in this app version. Get help to continue your request.',
                    tone: CollectStatusTone.warning,
                  ),
                  CollectSpacing.gap12,
                  CollectButton(
                    label: 'Get help',
                    variant: CollectButtonVariant.secondary,
                    onPressed: () => context.go('/settings/help'),
                    expand: true,
                  ),
                ],
                if (_controller.codeSent && !_verified) ...[
                  CollectSpacing.gap16,
                  AuthOtpEntry(
                    controller: _otp,
                    enabled: !busy,
                    onChanged: () => setState(() => _error = null),
                  ),
                  CollectSpacing.gap16,
                  CollectButton(
                    key: const ValueKey('privacy_verify_code'),
                    label: 'Verify code',
                    onPressed:
                        !busy &&
                            verificationReady &&
                            RegExp(r'^[0-9]{6}$').hasMatch(_otp.text)
                        ? _verifyCode
                        : null,
                    expand: true,
                  ),
                  CollectSpacing.gap12,
                ] else
                  CollectSpacing.gap16,
                if (!_verified)
                  CollectButton(
                    key: const ValueKey('privacy_send_code'),
                    label: _controller.codeSent
                        ? (_resendRemaining > 0
                              ? 'Resend in ${_resendRemaining}s'
                              : 'Resend code')
                        : 'Send verification code',
                    variant: _controller.codeSent
                        ? CollectButtonVariant.secondary
                        : CollectButtonVariant.primary,
                    onPressed:
                        !busy &&
                            verificationReady &&
                            maskedPhone != null &&
                            _resendRemaining == 0
                        ? _sendCode
                        : null,
                    expand: true,
                  ),
              ],
            ),
          ),
          if (unknown) ...[
            CollectButton(
              key: const ValueKey('privacy_check_status'),
              label: 'Check request status',
              variant: CollectButtonVariant.secondary,
              onPressed: busy ? null : () => _checkStatus(),
              expand: true,
            ),
            CollectButton(
              key: const ValueKey('privacy_retry_request'),
              label: 'Retry request',
              variant: CollectButtonVariant.danger,
              onPressed: busy || !_verified || !_statusAttempted
                  ? null
                  : () => _confirmSubmission(retry: true),
              expand: true,
            ),
          ] else
            CollectButton(
              key: const ValueKey('privacy_submit_request'),
              label: busy ? 'Please wait' : 'Submit request',
              variant: CollectButtonVariant.danger,
              onPressed: busy || !_verified
                  ? null
                  : () => _confirmSubmission(retry: false),
              expand: true,
            ),
        ],
        if (_error != null && live != null)
          Semantics(
            liveRegion: true,
            child: InfoSecurityBanner(
              title: 'Check your request',
              message: _error!,
              tone: CollectStatusTone.warning,
            ),
          ),
        if (receipt != null || _error != null)
          CollectButton(
            label: 'Refresh request status',
            variant: CollectButtonVariant.secondary,
            onPressed: busy || live == null ? null : () => _checkStatus(),
            expand: true,
          ),
      ],
    );
  }
}

class _PrivacyReceiptCard extends StatelessWidget {
  const _PrivacyReceiptCard({required this.receipt});
  final PrivacyIntakeReceipt receipt;

  @override
  Widget build(BuildContext context) => CollectCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CollectStatusChip(
          label: 'Pending review',
          tone: CollectStatusTone.info,
          icon: CollectIcons.pending,
        ),
        CollectSpacing.gap16,
        Text('Request recorded', style: Theme.of(context).textTheme.titleLarge),
        CollectSpacing.gap8,
        const Text(
          'Your account has not been deleted. Your request is awaiting review.',
        ),
        CollectSpacing.gap16,
        Text(
          'Recorded on ${DateFormat.yMMMd('en').format(receipt.acceptedAt.toLocal())}',
        ),
        CollectSpacing.gap12,
        Text(
          'Request reference',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        CollectSpacing.gap8,
        SelectableText(receipt.requestId),
      ],
    ),
  );
}

String _privacyPublicError(PrivacyFailure failure) => switch (failure) {
  PrivacyFailure.sessionChanged =>
    'Your session changed. Sign in again to continue.',
  PrivacyFailure.busy => 'Wait for the current request to finish.',
  PrivacyFailure.cancelled =>
    'The action was cancelled. Check your request status before trying again.',
  PrivacyFailure.codeRequired => 'Send a verification code first.',
  PrivacyFailure.invalidCode =>
    'Check the six-digit code or request a new one.',
  PrivacyFailure.phoneUnavailable =>
    'Your signed-in phone number is unavailable. Get help to continue.',
  PrivacyFailure.captchaRequired =>
    'Complete CAPTCHA verification to continue.',
  PrivacyFailure.rateLimited =>
    'Wait before requesting another verification code.',
  PrivacyFailure.verificationUnavailable =>
    'The code could not be verified. Check it or try again later.',
  PrivacyFailure.freshSignInRequired =>
    'Verify your identity again before submitting the request.',
  PrivacyFailure.invalidReason =>
    'Choose a shorter reason and remove unsupported characters.',
  PrivacyFailure.conflictingRequest =>
    'A request with different details is already recorded. Check its status or get help.',
  PrivacyFailure.submissionLimit =>
    'A request is already recorded. Check its status or get help.',
  PrivacyFailure.outcomeUnknown =>
    'Your request result is unconfirmed. Check its status before retrying.',
  PrivacyFailure.requestUnavailable || PrivacyFailure.protocolUnavailable =>
    'Your request status is unavailable. Check your connection and try again.',
};

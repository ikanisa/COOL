import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/components/admin_page.dart';
import 'admin_account_api.dart';
import 'cloudflare_admin_return_location.dart';
import 'cloudflare_admin_session.dart';

final cloudflareAdminEmailVerificationClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// A quiet utility form using Collect's shared Revolut web-pattern adapters.
/// Returning creates a fresh task page; no financial/privacy action is replayed.
class CloudflareAdminEmailVerificationPage extends ConsumerWidget {
  const CloudflareAdminEmailVerificationPage({this.returnTo, super.key});
  final String? returnTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(cloudflareAdminSessionProvider);
    final session = ref.read(cloudflareAdminSessionProvider.notifier);
    return _EmailVerificationTask(
      key: ValueKey(session.authorityFence),
      session: session,
      now: ref.watch(cloudflareAdminEmailVerificationClockProvider),
      returnTo:
          cloudflareAdminEmailVerificationReturnLocation(returnTo) ??
          '/admin/security',
    );
  }
}

class _EmailVerificationTask extends StatefulWidget {
  const _EmailVerificationTask({
    required this.session,
    required this.returnTo,
    required this.now,
    super.key,
  });
  final CloudflareAdminSession session;
  final String returnTo;
  final DateTime Function() now;

  @override
  State<_EmailVerificationTask> createState() => _EmailVerificationTaskState();
}

class _EmailVerificationTaskState extends State<_EmailVerificationTask>
    with WidgetsBindingObserver {
  final _code = TextEditingController();
  AdminEmailOtpReceipt? _receipt;
  DateTime? _retryAt;
  DateTime? _expiresAt;
  Timer? _clock;
  String? _message;
  bool _busy = false;
  bool _unknown = false;
  bool _unknownChecked = false;
  DateTime? _unknownUntil;
  bool _effectInFlight = false;
  DateTime? _effectDeadline;
  int _operation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    final uncertain = _unknown || _effectInFlight;
    ++_operation;
    widget.session.cancelSensitiveEmailVerification();
    _code.clear();
    if (mounted) {
      setState(() {
        _receipt = null;
        _busy = false;
        _unknown = uncertain;
        _unknownChecked = false;
        if (uncertain) {
          _unknownUntil ??=
              _effectDeadline ?? widget.now().add(const Duration(minutes: 5));
        }
        _effectInFlight = false;
        _message = uncertain
            ? 'Check verification after returning to this page.'
            : 'Request a new code when you are ready.';
      });
    }
  }

  @override
  void dispose() {
    ++_operation;
    widget.session.cancelSensitiveEmailVerification();
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function(bool Function() current) action, {
    bool effect = false,
  }) async {
    if (_busy) return;
    final operation = ++_operation;
    final fence = widget.session.authorityFence;
    bool current() =>
        mounted &&
        operation == _operation &&
        fence == widget.session.authorityFence &&
        ModalRoute.of(context)?.isCurrent == true;
    setState(() {
      _busy = true;
      _effectInFlight = effect;
      _message = null;
    });
    try {
      await action(current);
    } on AdminEmailOtpDeliveryUnknown catch (failure) {
      if (current()) {
        _acceptReceipt(failure.receipt);
        setState(() => _message = failure.message);
      }
    } on Object catch (failure) {
      if (current()) {
        setState(() {
          if (failure is CloudflareAdminRequestException &&
              failure.outcomeUnknown) {
            _unknown = true;
            _unknownChecked = false;
            _unknownUntil =
                _effectDeadline ?? widget.now().add(const Duration(minutes: 5));
          }
          _message = failure is AdminAccountException
              ? failure.message
              : 'Verification could not be checked. Try checking again.';
        });
      }
    } finally {
      if (current()) {
        setState(() {
          _busy = false;
          _effectInFlight = false;
        });
      }
    }
  }

  void _acceptReceipt(AdminEmailOtpReceipt receipt) {
    _receipt = receipt;
    final now = widget.now();
    _retryAt = now.add(Duration(seconds: receipt.retryAfterSeconds));
    _expiresAt = now.add(Duration(seconds: receipt.expiresInSeconds));
    _unknown = false;
    _unknownChecked = false;
    _unknownUntil = null;
  }

  Future<void> _send() => _run((current) async {
    if (_unknown &&
        _unknownChecked &&
        _unknownUntil?.isAfter(widget.now()) == false) {
      widget.session.cancelSensitiveEmailVerification();
      _unknown = false;
    }
    // A fresh send has its own full uncertainty window. An expired receipt
    // from an earlier request must never shorten the new attempt's deadline.
    _receipt = null;
    _expiresAt = null;
    _unknownUntil = null;
    _unknownChecked = false;
    _effectDeadline = widget.now().add(const Duration(minutes: 5));
    final receipt = await widget.session.requestSensitiveEmailVerification();
    if (!current()) return;
    setState(() {
      _acceptReceipt(receipt);
      _message = 'Code requested. Check your email.';
    });
  }, effect: true);

  Future<void> _verify() => _run((current) async {
    final receipt = _receipt;
    if (receipt == null) return;
    final code = _code.text;
    _code.clear();
    _effectDeadline = _expiresAt;
    await widget.session.verifySensitiveEmailVerification(
      challengeId: receipt.challengeId,
      code: code,
    );
    if (current()) {
      setState(() {
        _receipt = null;
        _unknown = false;
      });
    }
  }, effect: true);

  Future<void> _check() => _run((current) async {
    final verified = await widget.session.recheckSensitiveEmailVerification();
    if (current()) {
      setState(() {
        if (verified) {
          _receipt = null;
          _unknown = false;
        }
        if (_unknown) _unknownChecked = true;
        _message = verified
            ? 'Email verified.'
            : 'A recent email verification has not been confirmed.';
      });
    }
  });

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user;
    final available = widget.session.usesEmailVerification && user != null;
    final verified =
        available && user.hasRecentSensitiveVerification(now: widget.now());
    final retry = _retryAt?.difference(widget.now()).inSeconds ?? 0;
    final expired = _expiresAt?.isAfter(widget.now()) == false;
    final canRequest =
        !widget.session.sensitiveEmailVerificationUnconfirmed &&
        (!_unknown ||
            _unknownChecked && _unknownUntil?.isAfter(widget.now()) == false);
    return AdminPage(
      title: 'Verify email',
      leading: IconButton(
        tooltip: 'Back to account security',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/admin/security'),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!available)
                const Text('Sign in again to verify your email.')
              else ...[
                Text(
                  verified
                      ? 'Your email is verified for sensitive changes.'
                      : 'Use an email code before making sensitive changes.',
                ),
                const SizedBox(height: 12),
                Text(user.email),
                if (widget.session.sensitiveEmailVerificationUnconfirmed) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'The previous verification is unconfirmed. Check verification before continuing. A fresh sign-in is also available from account security.',
                  ),
                ],
                const SizedBox(height: 20),
                if (verified) ...[
                  FilledButton.icon(
                    onPressed: _busy ? null : () => context.go(widget.returnTo),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Continue'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Review the reopened task before confirming a change.',
                  ),
                ] else ...[
                  if (_receipt != null && !expired) ...[
                    TextField(
                      controller: _code,
                      enabled: !_busy && !_unknown,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Email code',
                      ),
                      onSubmitted: (_) {
                        if (!_busy && !_unknown) _verify();
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy || _unknown ? null : _verify,
                      child: const Text('Verify email'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (expired) const Text('This code has expired.'),
                  TextButton.icon(
                    onPressed: _busy || !canRequest || retry > 0 ? null : _send,
                    icon: const Icon(Icons.mail_outline),
                    label: Text(
                      retry > 0
                          ? 'Request again in ${retry}s'
                          : _receipt == null
                          ? 'Send email code'
                          : 'Request a new code',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _check,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Check verification'),
                  ),
                ],
              ],
              if (_busy) const LinearProgressIndicator(),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(liveRegion: true, child: Text(_message!)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

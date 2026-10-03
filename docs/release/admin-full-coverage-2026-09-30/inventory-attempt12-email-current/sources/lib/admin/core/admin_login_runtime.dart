part of 'admin_runtime.dart';

class AdminLoginPage extends ConsumerStatefulWidget {
  const AdminLoginPage({super.key});

  @override
  ConsumerState<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends ConsumerState<AdminLoginPage> {
  final _email = TextEditingController();
  String? _requestedEmail;
  final _otp = TextEditingController();
  var _otpSent = false;
  var _isBusy = false;
  var _resendSecondsRemaining = 0;
  String? _error;
  String? _statusMessage;
  Timer? _resendTimer;

  String get _emailForAuth => normalizeAdminEmail(_email.text);

  @override
  void dispose() {
    _resendTimer?.cancel();
    _email.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: colors.screenBase,
      body: ColoredBox(
        color: colors.canvas,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = MediaQuery.sizeOf(context).width;
            final layoutWidth = math.min(constraints.maxWidth, viewportWidth);
            final isCompact = layoutWidth < 600;
            final outerPadding = isCompact ? 16.0 : 32.0;
            final contentWidth = math.max(
              0.0,
              isCompact
                  ? layoutWidth - (outerPadding * 2)
                  : math.min(460.0, layoutWidth - (outerPadding * 2)),
            );
            return SafeArea(
              child: Align(
                alignment: Alignment.center,
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: outerPadding,
                    vertical: 28,
                  ),
                  child: SizedBox(
                    width: contentWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceReadable.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.panelBorder),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(isCompact ? 22 : 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: CollectColors.referenceChromeBlack,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.lock_outline,
                                    color: CollectColors.publicWhite,
                                    size: 21,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'Collect admin login',
                              style: textTheme.headlineSmall?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: CollectTypography.weightBold,
                                height: CollectTypography.leadingDisplayRelaxed,
                              ),
                            ),
                            if (adminPwaEvidenceMode) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: colors.infoContainer,
                                  borderRadius: BorderRadius.circular(
                                    CollectRadius.md,
                                  ),
                                  border: Border.all(
                                    color: colors.infoForeground.withValues(
                                      alpha: 0.24,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Synthetic local review credentials\n'
                                  '$adminEvidenceEmail • OTP $adminEvidenceOtp\nNo email is sent in this fixture.',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colors.textPrimary,
                                    fontWeight:
                                        CollectTypography.weightSemibold,
                                    height: CollectTypography.leadingBody,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 28),
                            const Text(
                              'Use the email of your enrolled and approved operator account.',
                            ),
                            const SizedBox(height: 8),
                            _AdminEmailInput(
                              controller: _email,
                              enabled: !_isBusy && !_otpSent,
                              onSubmitted: (_) {
                                if (!_isBusy && !_otpSent) {
                                  _submit();
                                }
                              },
                            ),
                            if (_otpSent) ...[
                              const SizedBox(height: 18),
                              Text(
                                'OTP code',
                                style: textTheme.labelLarge?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: CollectTypography.weightBold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _AdminOtpInput(
                                controller: _otp,
                                enabled: !_isBusy,
                                onSubmitted: (_) {
                                  if (!_isBusy) {
                                    _submit();
                                  }
                                },
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              _AdminLoginError(message: _error!),
                            ],
                            if (_statusMessage != null) ...[
                              const SizedBox(height: 14),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _statusMessage!,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colors.successForeground,
                                    fontWeight:
                                        CollectTypography.weightSemibold,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            Semantics(
                              button: true,
                              label: _otpSent
                                  ? 'Verify admin email OTP'
                                  : 'Send admin email OTP',
                              hint: _otpSent
                                  ? 'Submits the code.'
                                  : 'Sends the OTP.',
                              enabled: !_isBusy,
                              child: FilledButton.icon(
                                onPressed: _isBusy ? null : _submit,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(58),
                                  backgroundColor:
                                      CollectColors.referenceChromeBlack,
                                  foregroundColor: CollectColors.publicWhite,
                                  disabledBackgroundColor:
                                      colors.neutralContainer,
                                  disabledForegroundColor: colors.textMuted,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      CollectRadius.md,
                                    ),
                                  ),
                                  textStyle: textTheme.titleMedium?.copyWith(
                                    fontWeight: CollectTypography.weightBold,
                                  ),
                                ),
                                icon: _isBusy
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: colors.onImagePrimary,
                                        ),
                                      )
                                    : Icon(
                                        _otpSent
                                            ? Icons.verified_user_outlined
                                            : Icons.mail_outline,
                                        size: 20,
                                      ),
                                label: Text(
                                  _otpSent ? 'Verify code' : 'Send email OTP',
                                ),
                              ),
                            ),
                            if (_otpSent) ...[
                              const SizedBox(height: 10),
                              Semantics(
                                button: true,
                                label: _resendSecondsRemaining > 0
                                    ? 'Resend admin email OTP available in $_resendSecondsRemaining seconds'
                                    : 'Resend admin email OTP',
                                enabled:
                                    !_isBusy && _resendSecondsRemaining == 0,
                                child: TextButton.icon(
                                  onPressed:
                                      _isBusy || _resendSecondsRemaining > 0
                                      ? null
                                      : _resendOtp,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: Text(
                                    _resendSecondsRemaining > 0
                                        ? 'Resend code in ${_resendSecondsRemaining}s'
                                        : 'Resend email OTP',
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _isBusy ? null : _changeEmail,
                                child: const Text('Use a different email'),
                              ),
                            ],
                            const SizedBox(height: 18),
                            const _AdminLoginAssuranceRow(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_isBusy) {
      return;
    }
    setState(() {
      _isBusy = true;
      _error = null;
      _statusMessage = null;
    });
    try {
      final repository = ref.read(adminRepositoryProvider);
      if (!_otpSent) {
        final email = _emailForAuth;
        await repository.sendEmailOtp(email: email);
        if (mounted) {
          setState(() {
            _requestedEmail = email;
            _email.text = email;
            _otpSent = true;
            _statusMessage =
                'Email code requested. Check your approved operator inbox.';
          });
          _startResendCooldown();
        }
      } else {
        final identity = await repository.verifyEmailOtp(
          email: _requestedEmail!,
          otp: normalizeAdminEmailOtp(_otp.text),
        );
        ref.invalidate(adminAuthGuardProvider);
        ref.invalidate(adminIdentityProvider);
        if (!mounted) {
          return;
        }
        if (identity == null) {
          await repository.signOut();
          ref.invalidate(adminAuthGuardProvider);
          if (mounted) {
            setState(
              () => _error = 'This account is not authorized for admin.',
            );
          }
        } else {
          context.go('/admin');
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _adminLoginErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _resendOtp() async {
    if (_isBusy || _resendSecondsRemaining > 0 || _requestedEmail == null) {
      return;
    }
    setState(() {
      _isBusy = true;
      _error = null;
      _statusMessage = null;
    });
    try {
      await ref
          .read(adminRepositoryProvider)
          .sendEmailOtp(email: _requestedEmail!);
      if (!mounted) {
        return;
      }
      _otp.clear();
      setState(
        () => _statusMessage =
            'A new email code was requested. Use the latest message in your approved inbox.',
      );
      _startResendCooldown();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _adminLoginErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsRemaining = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSecondsRemaining <= 1) {
        timer.cancel();
        setState(() => _resendSecondsRemaining = 0);
      } else {
        setState(() => _resendSecondsRemaining -= 1);
      }
    });
  }

  void _changeEmail() {
    _resendTimer?.cancel();
    setState(() {
      _otpSent = false;
      _requestedEmail = null;
      _otp.clear();
      _resendSecondsRemaining = 0;
      _error = null;
      _statusMessage = null;
    });
  }

  String _adminLoginErrorMessage(Object error) {
    final message = error.toString().toLowerCase();
    if (adminPwaEvidenceMode && message.contains('review email')) {
      return 'Use the synthetic local review email $adminEvidenceEmail.';
    }
    if (adminPwaEvidenceMode && message.contains('developer otp')) {
      return 'Use the synthetic local review OTP $adminEvidenceOtp.';
    }
    if (message.contains('email otp') && message.contains('six digits')) {
      return 'Enter the six-digit email code.';
    }
    if (message.contains('format') || message.contains('email is invalid')) {
      return 'Enter a valid operator email address.';
    }
    if (message.contains('signup') ||
        message.contains('signups') ||
        message.contains('user not found') ||
        message.contains('user_not_found')) {
      return 'This email is not provisioned for operator sign-in. Ask the platform owner to enroll and approve the account.';
    }
    if (message.contains('token has expired') ||
        message.contains('expired or is invalid') ||
        message.contains('invalid token') ||
        message.contains('otp_expired')) {
      return 'That code could not be verified. Use the latest email code or request a new one.';
    }
    if (message.contains('rate limit') ||
        message.contains('over_email_send_rate_limit') ||
        message.contains('too many requests')) {
      return 'Please wait before requesting another email code.';
    }
    if (message.contains('not authorized') ||
        message.contains('overview.read') ||
        message.contains('platform admin') ||
        message.contains('42501') ||
        message.contains('permission')) {
      return 'Email verified, but this account is not approved for Admin access. Ask the platform owner to review its enrollment and permissions.';
    }
    if (message.contains('session')) {
      return 'The sign-in session changed. Request a new email code.';
    }
    if (message.contains('network') ||
        message.contains('socket') ||
        message.contains('timeout') ||
        message.contains('failed host lookup')) {
      return 'The sign-in service could not be reached. Try again.';
    }
    if (message.contains('confirmation') ||
        message.contains('email send') ||
        message.contains('smtp') ||
        message.contains('authretryable')) {
      return 'The email code could not be sent. Try again or contact the platform owner.';
    }
    if (error is UnsupportedError) {
      return 'Email operator sign-in is unavailable on this service.';
    }
    return 'Admin email sign-in failed. Try again.';
  }
}

class _AdminEmailInput extends StatelessWidget {
  const _AdminEmailInput({
    required this.controller,
    required this.enabled,
    required this.onSubmitted,
  });
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onSubmitted;
  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return TextField(
      key: const Key('admin-operator-email'),
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const [AutofillHints.username, AutofillHints.email],
      onSubmitted: onSubmitted,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(color: colors.textPrimary),
      decoration: InputDecoration(
        labelText: 'Operator email',
        hintText: 'name@organization.com',
        filled: true,
        fillColor: colors.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: CollectRadius.mdBorder,
          borderSide: BorderSide(color: colors.controlBorder),
        ),
      ),
    );
  }
}

class _AdminOtpInput extends StatelessWidget {
  const _AdminOtpInput({
    required this.controller,
    required this.enabled,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final tokens = context.collectUniversalTokens;
    return Semantics(
      textField: true,
      label: 'OTP code',
      hint: 'Six digit email one-time password for admin sign-in.',
      child: TextField(
        controller: controller,
        enabled: enabled,
        onSubmitted: onSubmitted,
        autofillHints: const [AutofillHints.oneTimeCode],
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: colors.textPrimary,
          fontWeight: CollectTypography.weightBold,
        ),
        decoration: InputDecoration(
          hintText: '6-digit code',
          filled: true,
          fillColor: colors.surfaceMuted,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CollectRadius.md),
            borderSide: BorderSide(color: colors.controlBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CollectRadius.md),
            borderSide: BorderSide(color: colors.controlBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CollectRadius.md),
            borderSide: BorderSide(
              color: tokens.focusRing,
              width: tokens.focusRingWidth,
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminLoginAssuranceRow extends StatelessWidget {
  const _AdminLoginAssuranceRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: colors.textMuted,
      height: CollectTypography.leadingSupporting,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_user_outlined, size: 18, color: colors.success),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Restricted to approved operators. Activity is logged for audit review.',
            style: style,
          ),
        ),
      ],
    );
  }
}

class _AdminLoginError extends StatelessWidget {
  const _AdminLoginError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      liveRegion: true,
      label: 'Admin sign-in error',
      value: message,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.dangerContainer,
          borderRadius: BorderRadius.circular(CollectRadius.md),
          border: Border.all(color: colors.danger.withValues(alpha: 0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: colors.danger, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.danger,
                    fontWeight: CollectTypography.weightBold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

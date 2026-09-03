part of 'admin_runtime.dart';

class AdminLoginPage extends ConsumerStatefulWidget {
  const AdminLoginPage({super.key});

  @override
  ConsumerState<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends ConsumerState<AdminLoginPage> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  var _otpSent = false;
  var _isBusy = false;
  var _resendSecondsRemaining = 0;
  String? _error;
  String? _statusMessage;
  Timer? _resendTimer;

  String get _phoneForAuth {
    final raw = _phone.text.trim();
    if (raw.startsWith('+') || raw.startsWith('00')) return raw;
    final digits = raw
        .replaceAll(RegExp(r'\D'), '')
        .replaceFirst(RegExp(r'^0+'), '');
    return '+250$digits';
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phone.dispose();
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
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: colors.panelBorder),
                        boxShadow: [
                          BoxShadow(
                            color: CollectColors.publicBlack.withValues(
                              alpha: 0.14,
                            ),
                            blurRadius: 48,
                            offset: const Offset(0, 24),
                          ),
                        ],
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
                                  child: Icon(
                                    Icons.lock_outline,
                                    color: colors.surfaceReadable,
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
                                  'Local review credentials\n'
                                  '$adminEvidenceWhatsAppPhone • OTP $adminEvidenceOtp',
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
                            Text(
                              'WhatsApp phone',
                              style: textTheme.labelLarge?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: CollectTypography.weightBold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _AdminPhoneInput(controller: _phone),
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
                              _AdminOtpInput(controller: _otp),
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
                                  ? 'Verify admin WhatsApp OTP'
                                  : 'Send admin WhatsApp OTP',
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
                                  foregroundColor: colors.onImagePrimary,
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
                                            : Icons.chat_bubble_outline,
                                        size: 20,
                                      ),
                                label: Text(
                                  _otpSent
                                      ? 'Verify code'
                                      : 'Send WhatsApp OTP',
                                ),
                              ),
                            ),
                            if (_otpSent) ...[
                              const SizedBox(height: 10),
                              Semantics(
                                button: true,
                                label: _resendSecondsRemaining > 0
                                    ? 'Resend admin WhatsApp OTP available in $_resendSecondsRemaining seconds'
                                    : 'Resend admin WhatsApp OTP',
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
                                        : 'Resend WhatsApp OTP',
                                  ),
                                ),
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
    setState(() {
      _isBusy = true;
      _error = null;
      _statusMessage = null;
    });
    try {
      final repository = ref.read(adminRepositoryProvider);
      if (!_otpSent) {
        await repository.sendOtp(phone: _phoneForAuth);
        if (mounted) {
          setState(() {
            _otpSent = true;
            _statusMessage = 'WhatsApp OTP sent. It expires in 10 minutes.';
          });
          _startResendCooldown();
        }
      } else {
        final identity = await repository.verifyOtp(
          phone: _phoneForAuth,
          otp: _otp.text,
        );
        ref.invalidate(adminAuthGuardProvider);
        ref.invalidate(adminIdentityProvider);
        if (!mounted) return;
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
      if (mounted) setState(() => _error = _adminLoginErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _resendOtp() async {
    setState(() {
      _isBusy = true;
      _error = null;
      _statusMessage = null;
    });
    try {
      await ref.read(adminRepositoryProvider).sendOtp(phone: _phoneForAuth);
      if (!mounted) return;
      _otp.clear();
      setState(
        () => _statusMessage =
            'A new WhatsApp OTP was sent. Earlier codes are no longer accepted.',
      );
      _startResendCooldown();
    } catch (error) {
      if (mounted) setState(() => _error = _adminLoginErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
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

  String _adminLoginErrorMessage(Object error) {
    final message = error.toString().toLowerCase();
    if (adminPwaEvidenceMode && message.contains('dedicated developer')) {
      return 'Use the local review number $adminEvidenceWhatsAppPhone.';
    }
    if (adminPwaEvidenceMode && message.contains('developer otp')) {
      return 'Use the local review OTP $adminEvidenceOtp.';
    }
    if (message.contains('status code returned from hook') ||
        message.contains('authretryablefetchexception') ||
        message.contains('error sending confirmation') ||
        message.contains('send_sms') ||
        message.contains('hook') && message.contains('sms') ||
        message.contains('whatsapp otp delivery') ||
        message.contains('whatsapp otp send failed')) {
      return 'WhatsApp could not send the OTP. Check the approved template and try again.';
    }
    if (message.contains('token has expired or is invalid') ||
        message.contains('expired or is invalid') ||
        message.contains('invalid token')) {
      return 'That code could not be verified. Check the latest WhatsApp code or request a new one.';
    }
    if (message.contains('format') || message.contains('phone')) {
      return 'Enter a valid international WhatsApp number.';
    }
    if (message.contains('not authorized') ||
        message.contains('overview.read') ||
        message.contains('platform admin')) {
      return 'WhatsApp verified, but this profile is not approved for admin access.';
    }
    return 'Admin sign-in failed. Try again.';
  }
}

class _AdminPhoneInput extends StatelessWidget {
  const _AdminPhoneInput({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      textField: true,
      label: 'WhatsApp phone',
      hint: 'Registered Rwanda WhatsApp number used for Collect admin sign-in.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: BorderRadius.circular(CollectRadius.md),
          border: Border.all(color: colors.controlBorder),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 14),
              child: Text(
                '+250',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: CollectTypography.weightBold,
                  letterSpacing: CollectTypography.trackingDefault,
                ),
              ),
            ),
            SizedBox(
              height: 30,
              child: VerticalDivider(
                width: 1,
                thickness: 1,
                color: colors.controlBorder,
              ),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: CollectTypography.weightBold,
                ),
                decoration: const InputDecoration(
                  hintText: 'Phone number',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminOtpInput extends StatelessWidget {
  const _AdminOtpInput({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final tokens = context.collectUniversalTokens;
    return Semantics(
      textField: true,
      label: 'OTP code',
      hint: 'Six digit WhatsApp one-time password for admin sign-in.',
      child: TextField(
        controller: controller,
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

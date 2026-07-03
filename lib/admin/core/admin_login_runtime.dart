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
  String? _error;

  @override
  void dispose() {
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
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: colors.screenGradient),
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
                        border: Border.all(color: colors.glassBorder),
                        boxShadow: [
                          BoxShadow(
                            color: CollectColors.inkPrimary.withValues(
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
                                    color: CollectColors.inkPrimary,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    Icons.lock_outline,
                                    color: colors.surfaceReadable,
                                    size: 21,
                                  ),
                                ),
                                const Spacer(),
                                _AdminLoginStatusChip(colors: colors),
                              ],
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'Collect admin login',
                              style: textTheme.headlineSmall?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Admin WhatsApp sign-in.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyLarge?.copyWith(
                                color: colors.textSecondary,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'WhatsApp phone',
                              style: textTheme.labelLarge?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w700,
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
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _AdminOtpInput(controller: _otp),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              _AdminLoginError(message: _error!),
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
                                  backgroundColor: CollectColors.inkPrimary,
                                  foregroundColor: colors.surfaceReadable,
                                  disabledBackgroundColor:
                                      colors.neutralContainer,
                                  disabledForegroundColor: colors.textMuted,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      CollectRadius.md,
                                    ),
                                  ),
                                  textStyle: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                icon: _isBusy
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: colors.surfaceReadable,
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
    });
    try {
      final repository = ref.read(adminRepositoryProvider);
      if (!_otpSent) {
        await repository.sendOtp(phone: _phone.text);
        if (mounted) setState(() => _otpSent = true);
      } else {
        final identity = await repository.verifyOtp(
          phone: _phone.text,
          otp: _otp.text,
        );
        ref.invalidate(adminAuthGuardProvider);
        ref.invalidate(adminIdentityProvider);
        if (!mounted) return;
        if (identity == null) {
          setState(() => _error = 'This account is not authorized for admin.');
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

  String _adminLoginErrorMessage(Object error) {
    final message = error.toString().toLowerCase();
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
      return 'That code is expired or already used. Request a new WhatsApp OTP.';
    }
    if (message.contains('registered admin whatsapp number')) {
      return 'Use the registered admin WhatsApp number.';
    }
    if (message.contains('admin whatsapp phone is not configured')) {
      return 'Admin WhatsApp phone is not configured.';
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
          border: Border.all(color: colors.borderSoft),
        ),
        child: Row(
          children: [
            Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: colors.borderSoft)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'RW',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: colors.textSecondary,
                    size: 18,
                  ),
                ],
              ),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  hintText: '+250 7XX XXX XXX',
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
          fontWeight: FontWeight.w700,
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
            borderSide: BorderSide(color: colors.borderSoft),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CollectRadius.md),
            borderSide: BorderSide(color: colors.borderSoft),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CollectRadius.md),
            borderSide: const BorderSide(
              color: CollectColors.inkPrimary,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminLoginStatusChip extends StatelessWidget {
  const _AdminLoginStatusChip({required this.colors});

  final CollectColors colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Secure admin area',
      hint: 'Restricted console with audited operator activity.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.successContainer,
          borderRadius: CollectRadius.pillBorder,
          border: Border.all(color: colors.success.withValues(alpha: 0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, size: 16, color: colors.success),
              const SizedBox(width: 6),
              Text(
                'Secure',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.success,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
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
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.textMuted, height: 1.35);
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
                    fontWeight: FontWeight.w700,
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

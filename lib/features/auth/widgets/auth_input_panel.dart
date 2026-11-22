part of 'auth_screen_widgets.dart';

class AuthInputPanel extends StatelessWidget {
  const AuthInputPanel({
    required this.otpSent,
    required this.phoneController,
    this.emailController,
    this.useEmail = false,
    this.phoneMethod = 'WhatsApp',
    this.enabled = true,
    this.verificationUnknown = false,
    required this.otpController,
    required this.error,
    required this.errorKey,
    this.errorTitle = 'Authentication failed',
    required this.resendRemaining,
    required this.countryCode,
    required this.onPhoneChanged,
    required this.onOtpChanged,
    super.key,
  });

  final bool otpSent;
  final TextEditingController phoneController;
  final TextEditingController? emailController;
  final bool useEmail;
  final String phoneMethod;
  final bool enabled;
  final bool verificationUnknown;
  final TextEditingController otpController;
  final String? error;
  final String errorTitle;
  final Key errorKey;
  final int resendRemaining;
  final String countryCode;
  final VoidCallback onPhoneChanged;
  final VoidCallback onOtpChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.authForeground;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!otpSent && useEmail)
          AuthEmailEntry(
            controller: emailController!,
            onChanged: onPhoneChanged,
            enabled: enabled,
          ),
        if (!otpSent && !useEmail)
          AuthPhoneEntry(
            phoneMethod: phoneMethod,
            controller: phoneController,
            countryCode: countryCode,
            enabled: enabled,
            onChanged: onPhoneChanged,
          ),
        if (otpSent) ...[
          AuthOtpEntry(
            controller: otpController,
            onChanged: onOtpChanged,
            enabled: enabled,
            autofocus: enabled && error == null,
          ),
          CollectSpacing.gap20,
          Text(
            verificationUnknown
                ? 'Verification is not confirmed. Use Check verification below.'
                : resendRemaining > 0
                ? 'Resend code in ${(resendRemaining ~/ 60).toString().padLeft(2, '0')}:${(resendRemaining % 60).toString().padLeft(2, '0')}'
                : "Didn't get the code? Use Resend or Change ${useEmail ? 'email' : 'number'} below.",
            key: const ValueKey('auth_otp_recovery_message'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: foreground.withValues(alpha: 0.90),
              fontWeight: CollectTypography.weightSemibold,
            ),
          ),
        ],
        if (error != null) ...[
          CollectSpacing.gap20,
          AuthStatusNotice(key: errorKey, title: errorTitle, message: error!),
        ],
      ],
    );
  }
}

class AuthPhoneEntry extends StatelessWidget {
  const AuthPhoneEntry({
    required this.controller,
    required this.countryCode,
    required this.onChanged,
    this.enabled = true,
    this.phoneMethod = 'WhatsApp',
    super.key,
  });

  final TextEditingController controller;
  final String countryCode;
  final VoidCallback onChanged;
  final bool enabled;
  final String phoneMethod;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.authForeground;
    final borderColor = foreground.withValues(alpha: 0.14);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final fieldHeight = 60.0 + ((textScale - 1).clamp(0.0, 1.35) * 24.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: SizedBox(
        height: fieldHeight,
        child: Row(
          children: [
            Material(
              color: CollectColors.transparentColor,
              child: SizedBox(
                height: fieldHeight,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        countryCode,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: foreground,
                              fontWeight: CollectTypography.weightSemibold,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(width: 1, height: 28, color: borderColor),
            Expanded(
              child: CollectAccessibleTextField(
                controller: controller,
                label: '$phoneMethod phone number',
                onChanged: (_) => onChanged(),
                builder: (focusNode) => TextField(
                  key: ValueKey(
                    phoneMethod == 'SMS'
                        ? 'auth_sms_phone_input'
                        : 'auth_whatsapp_phone_input',
                  ),
                  enabled: enabled,
                  focusNode: focusNode,
                  controller: controller,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                    LengthLimitingTextInputFormatter(24),
                  ],
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: CollectTypography.weightSemibold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: CollectTypography.trackingDefault,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Phone number',
                    hintStyle: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(
                          color: colors.authInputHint,
                          fontWeight: CollectTypography.weightMedium,
                        ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthStatusNotice extends StatelessWidget {
  const AuthStatusNotice({
    required this.title,
    required this.message,
    super.key,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $message',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(CollectIcons.warning, color: colors.danger, size: 22),
            CollectSpacing.gapW12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.danger,
                      fontWeight: CollectTypography.weightBold,
                    ),
                  ),
                  CollectSpacing.gap4,
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.authForeground.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthEmailEntry extends StatelessWidget {
  const AuthEmailEntry({
    required this.controller,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });
  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.authForeground.withValues(alpha: 0.14),
        ),
      ),
      child: CollectAccessibleTextField(
        controller: controller,
        label: 'Email address',
        onChanged: (_) => onChanged(),
        builder: (focusNode) => TextField(
          key: const ValueKey('auth_email_input'),
          focusNode: focusNode,
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          inputFormatters: [LengthLimitingTextInputFormatter(254)],
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: colors.authForeground),
          decoration: InputDecoration(
            hintText: 'Email address',
            hintStyle: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: colors.authInputHint),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
          ),
          onChanged: (_) => onChanged(),
        ),
      ),
    );
  }
}

class AuthSignInOptions extends StatelessWidget {
  const AuthSignInOptions({
    required this.useEmail,
    required this.onSwitch,
    required this.onGoogle,
    this.googleAvailable = false,
    this.whatsAppAvailable = false,
    this.smsAvailable = false,
    this.phoneMethod = 'WhatsApp',
    this.onSms,
    this.onWhatsApp,
    this.guestAvailable = false,
    this.isGuest = false,
    this.onGuest,
    this.onLeaveGuest,
    super.key,
  });
  final bool useEmail;
  final VoidCallback? onSwitch;
  final VoidCallback? onGoogle;
  final bool googleAvailable;
  final bool whatsAppAvailable;
  final bool smsAvailable;
  final String phoneMethod;
  final VoidCallback? onSms;
  final VoidCallback? onWhatsApp;
  final bool guestAvailable;
  final bool isGuest;
  final VoidCallback? onGuest;
  final VoidCallback? onLeaveGuest;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (!useEmail || whatsAppAvailable)
        _AuthNativeActionButton(
          key: const ValueKey('auth_switch_method'),
          label: useEmail ? 'Continue with WhatsApp' : 'Continue with email',
          onPressed: useEmail ? onWhatsApp ?? onSwitch : onSwitch,
          isPrimary: false,
        ),
      if (!useEmail && phoneMethod != 'WhatsApp' && whatsAppAvailable)
        _AuthNativeActionButton(
          key: const ValueKey('auth_whatsapp_method'),
          label: 'Continue with WhatsApp',
          onPressed: onWhatsApp,
          isPrimary: false,
        ),
      if (smsAvailable && (useEmail || phoneMethod != 'SMS'))
        _AuthNativeActionButton(
          key: const ValueKey('auth_sms_method'),
          label: 'Continue with SMS',
          onPressed: onSms,
          isPrimary: false,
        ),
      if (googleAvailable)
        CollectGoogleSignInButton(
          key: const ValueKey('auth_google_button'),
          onPressed: onGoogle,
        ),
      if (guestAvailable && !isGuest)
        _AuthNativeActionButton(
          key: const ValueKey('auth_guest_button'),
          label: 'Browse as guest',
          onPressed: onGuest,
          isPrimary: false,
        ),
      if (isGuest)
        _AuthNativeActionButton(
          key: const ValueKey('auth_leave_guest_button'),
          label: 'Use another account',
          onPressed: onLeaveGuest,
          isPrimary: false,
        ),
    ],
  );
}
